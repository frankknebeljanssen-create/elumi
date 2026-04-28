# Wörterbuch-Audit & Bereinigung — 2026-04-22

Stand: Abend-Session nach den Slot-Machine-Fixes.

## TL;DR

Drei Migrationen sind produktiv, eine gezielte Fehler-Korrektur für Custom-Listen ist neu drin, und die SQLite-Master-DB wurde systematisch auf typische Fehlerklassen abgeklopft. Die breite DB-Bereinigung bleibt für eine separate Session offen — die hier gefundenen DB-Befunde sind dokumentiert.

---

## 1. Bereits aktive Bereinigungs-Mechanismen

### 1.1 `PhraseNounCapitalizationMigration.swift`
**Wirkung**: läuft genau einmal pro Installation. Geht alle Custom-Listen (nicht Built-In) durch, nimmt jedes Phrase-Item (`cardType == .phrases`) und kapitalisiert im `german`-Feld jedes Wort, das auch als Nomen im Lexikon bekannt ist.

**Flag**: `elumi.migrations.phraseNounCapitalization.v1` (UserDefaults)

**Beispiel**: In einer User-Liste stand „mein bester freund" — nach dem Lauf steht dort „mein bester Freund". Der Punctuations-Handler ist robust gegen Klammern/Satzzeichen: `(freund)` → `(Freund)`.

**Nomen-Lookup-Quellen**:
- `StandardVocabularyLoader.nounEntries` (alle deutschen Nomen aus `FRDEMasterLexicon.sqlite`)
- Custom-Listen-Items mit `wordClass == "noun"` oder (Heuristik für Alt-Items) `cardType == .words` + großer Anfangsbuchstabe + kein Leerzeichen

---

### 1.2 `TextNormalizationEngine` Rule-4-Fix in `TextCasingRules.swift`
**Wirkung**: zur Laufzeit bei jeder Display-Normalisierung. Betrifft **alle** Anzeigepfade — Wörterbuch, Karteikarten, Quiz, Scan-Review.

**Gelöstes Problem**: die Rule „nach Artikel → groß, aber nur wenn das Wort das letzte Content-Token ist" (bug-fix von vorher für „das saubere Geschirrtuch") war zu eng und hat Kompositum-Phrasen zerlegt.

Beispiel (DB-Eintrag korrekt, Display aber falsch):
- DB: `préparer la protection de pluie pour poussette` → `den Regenschutz für den Kinderwagen vorbereiten` (gross)
- Display vor dem Fix: `den regenschutz für den kinderwagen vorbereiten` (komplett klein außer letztes Wort vor Verb)
- Display nach dem Fix: `den Regenschutz für den Kinderwagen vorbereiten` ✓

**Erweiterung**: Rule 4 prüft jetzt zusätzlich `StandardVocabularyLoader.germanNounSet` (neue Static-Let in `StandardVocabularyLoader.swift`) — ein Set aller **deutschen Nomen-Tokens** aus den Nomen-Einträgen der SQLite-DB. Wenn ein Token nach einem Artikel steht und im Nomen-Set ist, wird es kapitalisiert, auch wenn es nicht das letzte Content-Token ist.

**Nomen-Set-Aufbau**: aus jedem `nounEntry.target` werden alle Tokens gesammelt, die mit einem Großbuchstaben beginnen (im Master-Export immer die Nomen, niemals Artikel/Präpositionen/Adjektive). Ergibt ~35k Einträge.

---

### 1.3 `VocabularyKnownBadEntriesMigration.swift` — **NEU**
**Wirkung**: one-shot Migration, läuft genau einmal pro Installation. Geht alle Custom-Listen durch und sucht nach **exakten Paar-Matches** (Französisch + Deutsch), die als Fehler bekannt sind. Korrigiert diese entweder per `.replace(...)` oder löscht sie per `.delete`.

**Flag**: `elumi.migrations.vocabularyKnownBadEntries.v1`

**Architektur**: zentrale Swift-Literal-Liste `corrections`. Jeder Eintrag hat Match-Werte + Action. Erweiterbar durch Hinzufügen weiterer Einträge — beim nächsten Launch laufen neue unter dem gleichen `v1`-Flag **nicht** mehr, deshalb für jede neue Bereinigungs-Welle `v2`, `v3`, … benutzen.

**Aktuell enthaltene Korrektur**:

| Match FR  | Match DE           | Action    | Ziel FR       | Ziel DE              | wordClass | cardType |
|-----------|--------------------|-----------|---------------|----------------------|-----------|----------|
| `dur`     | `gekochtes Ei`     | `.replace`| `l'œuf dur`   | `das gekochte Ei`    | `noun`    | `.words` |

**Warum ist das wichtig?** Der Befund (s. u.) zeigt: die SQLite-Master-DB hatte beide korrekten Einträge drin. Der fehlerhafte Eintrag entstand vermutlich aus einer alten Scan-Session, bei der der Post-Processor noch nicht den „Dual-Form-Splitter" hatte und aus „l'œuf dur → das gekochte Ei" (OCR-Ergebnis) den Lernkern „dur" extrahiert hat, ohne die Übersetzung zu verkürzen.

---

## 2. DB-Audit: FRDEMasterLexicon.sqlite

Systematische Sanity-Checks auf der Master-DB (57.029 Einträge).

### 2.1 Gesamt-Statistik
| Kategorie                    | Anzahl  |
|-----------------------------|---------|
| Einträge gesamt              | 57.029  |
| Nomen                        | 35.716  |
| Verben                       | 3.117   |
| Adjektive                    | 4.575   |
| Phrasen (`word_class='phrase'` OR `is_phrase=1`) | 12.861 |
| Nomen **ohne** `gender_fr`   | 6.124   |

### 2.2 Der konkrete User-Fall „dur"
```sql
SELECT lemma_fr, lemma_de, word_class FROM entries
WHERE lemma_fr='dur' OR lemma_de LIKE '%gekocht%Ei%';
```
Ergebnis:
- `l'œuf dur` → `das gekochte Ei` (noun) ✓ **korrekt in DB**
- `dur` → `hart` (adjective) ✓ **korrekt in DB**

**Befund**: Der User-Fehleintrag `dur` → `gekochtes Ei` ist **NICHT** in der DB. Er existiert nur in den persistierten Custom-Listen (UserDefaults-JSON). Daher die gezielte Migration in 1.3.

### 2.3 Weitere Auffälligkeiten (dokumentiert, **nicht** gefixt — separate Session)

#### (a) Adjektive mit Nomen-Kompositum-Übersetzung
```sql
SELECT lemma_fr, lemma_de FROM entries WHERE word_class='adjective'
  AND (lemma_de LIKE 'der %' OR lemma_de LIKE 'die %' OR lemma_de LIKE 'das %');
```
Nur 4 Treffer:
- `cardiaque` → `das Herz betreffend` (OK — idiomatisch, kein Fehler)
- `cutané` → `die Haut betreffend` (OK — idiomatisch)
- `estivalier` → `der Sommerfrischler` (⚠️ **vermutlich Fehl-Klassifikation**: sollte `noun` sein, nicht `adjective`)

#### (b) Kurze Adjektive mit fragwürdiger Übersetzung
```sql
SELECT lemma_fr, lemma_de, word_class FROM entries WHERE LENGTH(lemma_fr)=2 AND word_class='adjective';
```
- `un` → `eins; ein` (adjective) — könnte besser als `numeral` oder `article` klassifiziert sein
- `un` → `einzig` (adjective) — akzeptabel (= „ein einziger")
- `nu` → `nackt` (adjective) ✓
- `or` → `Gold` (⚠️ **Fehl-Klassifikation**: „or" als Nomen bedeutet „Gold" — es gibt parallel `l'or` → `Gold` (noun) korrekt; der Eintrag ohne Artikel mit Klassifikation `adjective` ist falsch. Zusätzlich gibt es `or` → `nun / jedoch` (conjunction) — das ist korrekt)

#### (c) Duplikate
170 Einträge mit gleichem `lemma_fr` (unterschiedliche Bedeutung/Wortklasse). Top-Beispiele:
- `bref` × 3 · `en général` × 3 · `en particulier` × 3 · `par hasard` × 3 · `sur place` × 3 · `un` × 3
- Meist intentional (verschiedene Wortarten oder Bedeutungen). Keine Löschung empfohlen ohne Einzelprüfung.

#### (d) Nomen ohne Genus
6.124 Einträge (= 17 % aller Nomen) haben kein `gender_fr`. Diese werden vom Artikel-Trainer als „unbekannt" behandelt. **Empfehlung** für spätere Session: systematisch via `SupplementalFreeDictLexicon`-Abgleich + Artikel-Heuristik füllen.

---

## 3. Was ist die architektonische Geschichte?

Warum bleibt die DB teilweise unsauber, aber wir beheben Fehler nicht in der DB selbst?

- **Master-DB (SQLite)** ist Read-only zur Laufzeit. Fixes dort brauchen einen neuen App-Bundle-Release.
- **Custom-Listen** sind User-Daten, liegen in UserDefaults als JSON. Hier können wir per Migration eingreifen.
- **Display-Engine** (`TextNormalizationEngine`) läuft pro Render und ist der idealste Punkt, um inkonsistente DB-Daten auf Display-Ebene zu normalisieren — ohne die DB selbst zu ändern (sie kann beim nächsten Master-Export ohnehin repariert werden).

Die drei Mechanismen zusammen bilden eine **defensive Kette**: Migration für User-Daten (einmalig), Engine für Runtime-Display (kontinuierlich), DB-Fix für Master-Daten (nächste Session).

---

## 4. Ausblick — „Breite Wörterbuch-Bereinigung" (separate Session)

Aufgaben, die beim Audit sichtbar wurden, aber bewusst nicht in dieser Session adressiert werden:

1. **DB-Level-Fixes** für die unter 2.3(a)–(b) genannten Fehlklassifikationen. Brauchen einen neuen Python-Build-Durchlauf des Master-Exports.
2. **Genus-Vervollständigung** für die 6.124 genuslosen Nomen.
3. **Duplikat-Review** (170 Fälle) — intentional vs. versehentlich trennen.
4. **Phrase-Format-Prüfung** — konsistente Verwendung von Artikel-Präfixen (immer/nie), Aussprache-Spezialfälle.
5. **Evaluation von Short-Words** (1-2 Buchstaben) auf ihre Lerntauglichkeit — manche sind Abkürzungen, die als eigene Einträge sinnvoll sind, andere sind Müll.

---

## 5. Dateien & Locations (für nächste Session)

- Master-DB: `FRDEVocabMVP/FRDEMasterLexicon.sqlite`
- Loader: `StandardVocabularyLoader.swift` (zeilen 18–94)
- Display-Engine: `TextCasingRules.swift` (zeilen 245–298 = `normalizeGermanToken`)
- Nomen-Set: `StandardVocabularyLoader.germanNounSet`
- Migration 1 (Phrase-Capitalization): `PhraseNounCapitalizationMigration.swift`
- Migration 2 (Known-Bad-Entries): `VocabularyKnownBadEntriesMigration.swift` ← **neu**
- Aufruf-Site für Migrationen: `VocabularyListStore.swift` (`init`)
