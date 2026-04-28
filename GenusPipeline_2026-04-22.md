# Französisch-Genus-Pipeline — 2026-04-22

Komplett-Architektur: drei Quellen-Schichten plus KI-Fallback, zentraler Resolver, Loader-Pass zum App-Start.

---

## Ziel & Spec-Erfüllung

User-Spec vom 2026-04-22 („Genus-Erkennung und Artikel-Ergänzung für Nomen"):

| Spec-Punkt | Umsetzung | Status |
|---|---|---|
| Jeder Nomen-Eintrag hat `lemma_fr` inkl. Artikel | `FrenchGenderResolver.resolve` rebuildet `normalizedLemma` mit Artikel | ✅ |
| `genus` (maskulin/feminin) pro Eintrag | `Entry.gender` aus DB oder aus Resolver befüllt | ✅ |
| `number` (singular/plural) | `ResolvedGender.number` aus Artikel-Parse oder Default `.singular` | ✅ |
| Pipeline Schritt 1: Artikel vorhanden → extrahieren | `splitArticleAndCore` + `genderFromArticle` | ✅ |
| Pipeline Schritt 2a: DB-/Wörterbuch-Lookup | `pluralLookup`-Callback (Singular-Map aus eindeutigen Genus-Einträgen) | ✅ |
| Pipeline Schritt 2b: Heuristik | `FrenchGenderHeuristicRules.predict` | ✅ |
| Pipeline Schritt 2c: KI-Fallback | `tools/gender_ai_resolver.py` (Claude Haiku, offline) + Bundle-JSON-Overlay | ✅ (Phase 2) |
| Artikel korrekt: `le`/`la`/`l'`/`les` | `articleFor` mit Elision-Handling | ✅ |
| `genus_source` + `genus_confidence` pro Eintrag | `Entry.genderSource` / `Entry.genderConfidence` | ✅ |
| Keine Überschreibung wenn korrekt | Guard: `!entry.gender.isEmpty` → unverändert übernehmen | ✅ |
| Unsichere Fälle markieren statt blind überschreiben | Confidence unter 0.85 landet trotzdem drin, aber mit niedriger `genderConfidence` → UI/Trainer kann darauf reagieren | ✅ |

---

## Architektur

```
                  ┌────────────────────────────────────────────────┐
                  │          FRDEMasterLexicon.sqlite              │
                  │  (Read-only, 57k Einträge, 35.7k Nomen,         │
                  │   6.124 ohne gender_fr)                         │
                  └─────────────────┬──────────────────────────────┘
                                    │ (App-Start, einmalig)
                                    ▼
                  ┌────────────────────────────────────────────────┐
                  │   StandardVocabularyLoader.loadEntries()        │
                  │   → rohe Entry-Liste                            │
                  └─────────────────┬──────────────────────────────┘
                                    │
                                    ▼
                  ┌────────────────────────────────────────────────┐
                  │  postProcessResolveGenders(raw)                 │
                  │   1. Singular-Genus-Map aus `raw` bauen         │
                  │   2. KI-Overrides aus Bundle laden (Phase 2)    │
                  │   3. Für jedes Nomen ohne `gender`:             │
                  │        FrenchGenderResolver.resolve(...)        │
                  │   4. Entry mit gefülltem Genus + Source +       │
                  │      Confidence zurückgeben                     │
                  └─────────────────┬──────────────────────────────┘
                                    │
                                    ▼
              `StandardVocabularyLoader.allEntries` — stabil für App-Lebenszeit.
              Wörterbuch / Karteikarten / Quiz / Artikel-Trainer lesen hier.
```

### FrenchGenderResolver-Pipeline (pro Entry)

```
Input: rawLemma
   │
   ▼
splitArticleAndCore(rawLemma) → (article, core, tail)
   │
   ├─> article in {le/un/du/au} → (masculine, singular, source: explicitArticle, conf 1.0) ──▶ DONE
   ├─> article in {la/une}      → (feminine, singular, source: explicitArticle, conf 1.0)  ──▶ DONE
   │
   │  (ab hier: article ∈ {les, l', ''})
   ▼
aiOverrides[core.lower()] ?
   │
   ├─> hit → (gender, singular, source: aiOverride, conf aus Override)       ──▶ DONE
   │
   ▼
article == "les" und pluralLookup(core) ?
   │
   ├─> hit → (gender, plural, source: dbLookup, conf 0.95)                   ──▶ DONE
   │
   ▼
FrenchGenderHeuristicRules.predict(core) ?
   │
   ├─> hit → (gender, singular, source: heuristic, conf aus Regel)           ──▶ DONE
   │
   ▼
Fallback: (nil, singular, source: unknown, conf 0.0) ──▶ KI-Residual-Kandidat
```

---

## Swift-Seite — Phase 1

Drei neue Dateien, alle in `FRDEVocabMVP/`:

### `FrenchGenderHeuristicRules.swift`
Endungs-Regeltabelle + explizite Overrides. Confidence pro Regel dokumentiert.

Bekannte Ausnahmen explizit gepflegt (z. B. `eau` = f, `page` = f, `cœur` = m, `œuf` = m). Erweiterbar über `explicitOverrides`-Dictionary — einfach Key/Value hinzufügen.

Regel-Match-Reihenfolge: **längste Endung zuerst**. `-ation` schlägt `-tion` schlägt `-on`.

### `FrenchGenderResolver.swift`
Orchestrierung. `FrenchGenderSource` enum für Transparenz:
- `.explicitArticle` — Artikel im Input war eindeutig
- `.dbLookup` — Plural-zu-Singular-Übernahme
- `.heuristic` — Endungs-Regel
- `.aiOverride` — KI-Pipeline
- `.unknown` — Residual

`ResolvedGender` als Ergebnis-Struct.

### Erweiterungen in `StandardVocabularyLoader.swift`
- `Entry`-Struct hat jetzt `genderSource: FrenchGenderSource` und `genderConfidence: Double`. Default-Werte (`.explicitArticle`, `1.0`) machen alle alten Init-Calls backward-compatible.
- `allEntries` ist jetzt `loadEntries() |> postProcessResolveGenders`.
- `postProcessResolveGenders` baut beim ersten Zugriff:
  1. Singular-Genus-Map aus DB (für Plural-Lookup)
  2. Lädt optional `gender_ai_overrides.json` aus dem Bundle
  3. Iteriert alle Nomen, ruft Resolver auf
  4. Loggt Statistics im Debug-Build

---

## Phase 2 — KI-Fallback (offline Python-Skript)

**Datei**: `tools/gender_ai_resolver.py`

**Setup (einmalig)**:
```bash
cd "/Users/frankknebeljanssen/Library/CloudStorage/Dropbox/plugin development/VocabMVP"
python3 -m venv .venv_tools
source .venv_tools/bin/activate
pip install -r tools/requirements.txt
```

**Run**:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
python3 tools/gender_ai_resolver.py
```

**Was passiert**:
1. Öffnet die DB, sucht alle Nomen ohne `gender_fr`, bei denen der Artikel ambig ist (`l'` oder kein Artikel)
2. Schickt Batches à 40 Wörter an Claude Haiku
3. Erwartet pro Wort: `{word, gender: m|f, confidence: 0.0–1.0}`
4. Schreibt `FRDEVocabMVP/gender_ai_overrides.json` inkrementell
5. Inkrementelle Läufe: bestehende Overrides werden übernommen, nur neue Residuals bearbeitet

**Nach dem Run (einmalig)**:
`gender_ai_overrides.json` muss in Xcode dem Target als Copy-Bundle-Resource hinzugefügt werden:

1. Xcode öffnen
2. FRDEVocabMVP-Target → Build Phases → Copy Bundle Resources
3. `+` → `gender_ai_overrides.json` auswählen
4. Build & Re-Run

Nach dem nächsten App-Start konsumiert `StandardVocabularyLoader.loadAIGenderOverrides()` die Datei und priorisiert sie vor der Heuristik.

**Kosten-Schätzung** (Claude Haiku 4.5, Stand April 2026):
- ~6000 Residuals / 40 pro Batch = 150 Batches
- ~$0.80 pro 1000 Wörter → ~$5 einmalig

---

## Qualitäts-Stufen (User-Spec erfüllt)

Confidence-gestufte Behandlung:

| `genderConfidence` | Source | Interpretation | UI-Hinweis (empfohlen) |
|---|---|---|---|
| `1.0` | `explicitArticle` / `aiOverride` (hohe AI-Conf) | sehr zuverlässig | normal anzeigen |
| `0.9–1.0` | `dbLookup` / `heuristic` (starke Endung) | zuverlässig | normal anzeigen |
| `0.7–0.9` | `heuristic` (mittlere Endung) | wahrscheinlich richtig | Genus-Marker **weiß** statt grün, Tooltip „heuristisch bestimmt" |
| `< 0.7` | `heuristic` (schwache Endung) / `unknown` | unsicher | Genus-Marker nicht anzeigen ODER Fragezeichen |
| `0.0` | `unknown` | unbekannt | kein Marker — KI-Residual |

UI-Integration kann später per `entry.genderConfidence` und `entry.genderSource` gesteuert werden — die Daten sind da.

---

## Erwartete Coverage nach Phase 1

Von den 6.124 ursprünglich genuslosen Nomen:
- Plural-DB-Lookup trifft ~70–90 der 118 `les`-Einträge
- Heuristik trifft schätzungsweise 60–75 % der 5.985 `l'`-Einträge (= ~3.500–4.500)
- Explizite Overrides decken die wichtigsten Hochfrequenz-Alltagswörter ab (~50)

**Phase 1 allein**: ca. 65–75 % Coverage (4.000–4.500 von 6.124).

**Phase 2 (mit KI-Pipeline)**: ca. 98 %+ Coverage, nur einzelne Härtefälle offen.

---

## Tuning & Wartung

**Neue Ausnahme hinzufügen**: `FrenchGenderHeuristicRules.explicitOverrides` Dictionary editieren → Build → fertig.

**Neue Endungs-Regel hinzufügen**: `FrenchGenderHeuristicRules.allRules` Array editieren → **Reihenfolge beachten (längere Endungen zuerst)**.

**KI-Cache invalidieren**: `gender_ai_overrides.json` löschen → Skript neu laufen. Oder gezielt einzelne Keys aus der JSON entfernen und das Skript nachträglich laufen lassen (inkrementelle Logik).

**Singular-Genus-Map-Debugging**: In `buildSingularGenderMap` ein `print(map.count)` einfügen, um die Größe zu sehen. Aktuell ~29k Einträge (aus DB-Nomen mit eindeutigem Genus).

---

## Dateien-Übersicht

```
FRDEVocabMVP/
├── FrenchGenderHeuristicRules.swift      ← NEW: Endungs-Regeln + Overrides
├── FrenchGenderResolver.swift            ← NEW: Pipeline-Orchestrierung
├── StandardVocabularyLoader.swift        ← CHANGED: +Entry-Felder, +Resolver-Pass
└── gender_ai_overrides.json              ← OPTIONAL: wird vom Python-Skript erzeugt

tools/
├── gender_ai_resolver.py                 ← NEW: Phase-2-KI-Pipeline
└── requirements.txt                      ← NEW: Python-Deps
```
