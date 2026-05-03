# Post-V1b TODO

## ✅ Empty-Pool-Hint (Branch: `feature/empty-pool-hint`) — ERLEDIGT 2026-04-29 in `v2-empty-pool-hint`

> **Status:** Beide Sub-Items (Training-Pool + Personal-Deck-Pool) implementiert
> und gemerged auf main als Tag `v2-empty-pool-hint`.
>
> - Training-Pool: Toast-Pattern in `TrainingView` (Commit `5bf2e4a`)
> - Personal-Deck-Pool: Inline-Fehler in `FlashcardStackComposerSheet`
>   mit optionaler `validate`-Closure (Commit `82068d9`)
>
> Hinweis zur ursprünglichen Quelle-Referenz unten: `FlashcardsView+PersonalDeck.swift:138`
> war Dead-Code (kein Caller). Echter Personal-Deck-Pfad lebt in
> `PersonalDecksView.swift:219` (createDeck) + `:235` (updateDeck) — dort
> wurde die Validation eingehängt. Siehe Backlog-Item unten zum
> Dead-Code-Cleanup.

**Symptom:** Bei leerem oder zu kleinem Item-Pool macht das Training-Modul einen
silent-fail mit State-Reset und ohne User-Feedback.

**Quelle:** `TrainingSessionController+SessionFlow.swift:68-71`

```swift
guard !deck.isEmpty else {
    resetTrainingSessionState()
    return false
}
```

**Beobachtet bei V1b-Edge-Case-Test (2026-04-28):**
Mode `.verbs` mit kleiner Liste (45 Items) und `lernjahrMax=1` lieferte 0
Verb-Lemmata. App-State resettete leise — User tippt „Los geht's" und nichts
sichtbar passiert.

**Existierender Bug**, durch V1b nur **häufiger sichtbar geworden** (engerer
Filter erzeugt häufiger leere Pools).

**Plan:**
- Neuer Branch `feature/empty-pool-hint`
- Toast-/Card-Hint statt silent reset: „Pool ist leer für Modus X. Wähle eine
  andere Liste oder mehr Lernjahre."
- Greift mindestens für Training; analog für Akzente/Quiz/Flashcards prüfen.
- Setup-CTA disable, solange Pool < Block-Min, mit klarer Fehlerlinie statt
  Silent-Tap.

**Variante: Empty Personal-Deck Create (V1b Step 3, 2026-04-28)**

Beim Erstellen eines persönlichen Stapels (Karteikarten → Personal-Deck →
„Stapel erstellen") gilt das gleiche Muster:

```swift
// FlashcardsView+PersonalDeck.swift:138 (createPersonalDeck)
let cardIDs = PersonalDeck.buildCardOrderSnapshot(from: selectedLists)
guard !cardIDs.isEmpty else { return }   // ← silent return
```

Wenn alle Items der gewählten Quell-Listen außerhalb des aktuellen
`lernjahrMax` liegen (z. B. User wählt nur Y3-getaggte Listen aber hat
`max=1`), wird der Deck **silent NICHT angelegt**. User tippt „Speichern",
das Sheet schließt, aber kein neues Deck erscheint in der Übersicht.

**Same Pattern, gleiche Lösung:** im Empty-Pool-Hint-Branch mit erfassen.
Toast/Inline-Fehler im Sheet: „In deinem aktuellen Lernjahr-Range
ergeben diese Listen keine Karten — wähle andere Listen oder erweitere
den Range."

**Recovery-Pfad-Notiz (zur Reference):**
`PersonalDeck.buildCardOrderSnapshot(from:)` wird auch im UUID-Stale-
Recovery-Pfad genutzt (`FlashcardsView+PersonalDeck.swift:233`). Dort
gelten die **aktuellen Filter-Regeln** (nicht die zur Erstellungs-Zeit) —
weil Recovery den Original-Snapshot ohnehin zerstört (Mastery-Daten weg,
neuer Shuffle). Konsistent zum globalen Filter-Verhalten. Kein Bug.

**Priorität:** Niedrig — kosmetischer UX-Bug, keine Daten-Korruption.

**Erstellt am:** 2026-04-28 (während V1b-Lernjahr-Rollout)
**Erweitert am:** 2026-04-28 (V1b Step 3, Personal-Deck-Variante)
**Erledigt am:** 2026-04-29 (Tag `v2-empty-pool-hint`)

---

## Offene Backlog-Items (nach `v2-empty-pool-hint`-Merge)

### ✅ 1. Dead-Code-Cleanup `FlashcardsView+PersonalDeck.swift` — ERLEDIGT 2026-04-30 in `v2-personal-deck-polish`

`createPersonalDeck(fromSelectedListIDs:)`, `updatePersonalDeck(_:withSelectedListIDs:)`
und der private `autoName(fromLists:)`-Helper aus
`FlashcardsView+PersonalDeck.swift` sind entfernt (Commit `2f5f51b`).
Keine Caller waren vorhanden — der echte Personal-Deck-Create/Update-
Flow läuft über `PersonalDecksView.swift:325/364`.

Mit-aufgeräumt: `PersonalDeckSlotView.swift` (gesamt 209 LoC) als
toter Datei-Removal mit pbxproj-Cleanup (4 Einträge). Die einzig
lebende Definition daraus — die `PersonalDeck.color(for:)`-
Extension — wurde nach `PersonalDeck.swift` (Model-File) migriert.

---

### ✅ 2. Personal-Deck-Löschen-Bug — ERLEDIGT 2026-04-30 in `v2-personal-deck-polish`

User-gemeldet aus dem Empty-Pool-Hint-Smoke-Test: „löschen option
fehlt". Diagnose: der Delete-Pfad existierte technisch (über den
„Bearbeiten"-Text-Button → kombinierter Rename/Delete-Alert), aber
der Trigger war ein subtiler `Color.white.opacity(0.55)`-Text-Button
im Card-Header — auf einer dunklen Card unentdeckbar.

Fix (Commit `92f011f`):
- Long-Press-Context-Menu auf der Stapel-Card mit drei Aktionen
  (Bearbeiten / Listen ändern / Löschen)
- Dedicated `.alert`-Bestätigung mit zwei klar sichtbaren Buttons
  (Abbrechen + Löschen)
- Message stellt explizit klar, dass nur der Stapel + Lernfortschritt
  gelöscht werden — die Quelllisten (z. B. Grundwortschatz) bleiben
  erhalten

Implementations-Note: erste Iteration nutzte `.confirmationDialog` —
auf iOS 26 rendert das als kompakter Popover mit verschluckten
Cancel-Button und schwer lesbarer Destructive-Schrift. Umgestellt
auf klassisches `.alert`.

---

### 3. Personal-Deck 2-Stapel-Limit

Per `appPersonalDecksKey`-Doc (`AppStorageKeys.swift`):
> **Persönlicher Trainingsmodus** (Phase 8): bis zu zwei persistierte
> User-Stapel.

**Information, kein Bug.** User stieß im Empty-Pool-Hint-Smoke-Test auf
das Limit. Falls die Bemerkung zukünftig zur Spec-Diskussion führt
(„warum eigentlich nur 2?"), hier dokumentiert.

**Priorität:** Keine — Information.

---

### ✅ 4. Selection-leer bei „Fertig"-Tap im Personal-Deck-Sheet — ERLEDIGT 2026-04-30 in `v2-personal-deck-polish`

Fix (Commit `c7f91dc`): die `validate`-Closure aus dem Empty-Pool-
Hint (sowohl Create- als auch Edit-Sheet) gibt jetzt bei leerer
Selection den Inline-Fehler „Wähle mindestens eine Liste, aus der
dein Stapel bestehen soll." zurück. Sheet bleibt offen, Inline-
Fehler erscheint, Auto-Reset bei nächster Selection-Change wie
bisher. Kein Regress am bestehenden Empty-Pool-Hint.

---

### ✅ 5. Filename-Cleanup `AppIconRegistry.swift` → `UUIDExtensions.swift` — ERLEDIGT 2026-04-30 in `v2-uuid-extensions-rename`

Datei umbenannt via `git mv` (File-History erhalten), pbxproj-
Einträge mit-aktualisiert (4 Stellen), File-Header reduziert
(historischer Cleanup-Kontext jetzt nur noch im Repo-Log + Backlog).
`import SwiftUI` zurückgestuft auf `import Foundation` (UUID lebt
dort, SwiftUI-Import war historisches Relikt aus den jetzt
entfernten `Image`-Extensions).

---

### 6. Verwaister UserDefaults-Key `appIconSet`

Aus dem Stufe-6-Icon-Cleanup (Tag `v2-icon-cleanup`, 2026-04-29):
beim Removal der Icon-Set-A/B-Switch-Settings-UI wurde der
`UserDefaults["appIconSet"]`-Key bewusst **nicht** aktiv aus den
Geräten gelöscht. Auf existierenden User-Geräten liegt der Eintrag
weiterhin verwaist herum und wird nie wieder gelesen.

**Status:** Harmlos für Funktionalität (kein Code referenziert den
Key mehr). Datensparsamkeits-/Hygiene-mäßig nicht ideal, aber kein
akutes Problem.

**Empfehlung:**
- **Nicht** als eigener Migration-Pfad — der Aufwand für einen
  Delete-on-Launch-Hook für genau einen Key lohnt sich nicht.
- **Bei nächstem ohnehin notwendigen Migration-Pfad** (z. B.
  Schema-Bump im `AccountStore` oder anderer Persistenz-Layer-
  Wechsel) den Key in der Migrations-Liste mit-aufräumen.
- Sonst nichts.

**Priorität:** Niedrig — passiv, wartet auf Anlass.

---

### 7. Akzente-Integration in den globalen Listen-Auswahl-Modus

Aus Stufe 5 (Tag `v2-global-list-selection`, 2026-04-30): das Akzente-
Modul ist bewusst **außerhalb** der globalen Listen-Auswahl belassen
worden. Begründung: Akzente nutzt aktuell `@State selectedListID:
UUID` mit optionalem `AccentsLaunchContext`-Override — eine **Single-
Pick-mit-Session-Scope**-Architektur, die nicht zum Multi-Set-Pool
der globalen Auswahl passt. Akzente persistiert seine Wahl heute
nicht über Sessions hinweg.

**Trigger für eine spätere Integration:** sobald Akzente Multi-List-
Support bekommt (User wählt mehrere Listen für Akzent-Übung) oder
eine Persistenz-Schicht für den Listen-Picker eingeführt wird, kann
Akzente analog zu Quiz/Flashcards/Training/Word Runner über die
`VocabularyListSelectionResolver.effectiveSelectedListIDs(...)`-Helper
ans globale System angeschlossen werden.

**Empfehlung:**
- Kein vorgezogener Refactor — die aktuelle Single-UUID-Architektur
  ist konsistent mit dem Akzente-Use-Case (User wählt EINE Quelle
  zum Üben).
- Bei nächstem Akzente-Feature-Touch den Punkt mit-bewerten.

**Priorität:** Niedrig — keine UX-Asymmetrie für Bestandsfunktionalität,
nur ein offenes Architektur-Anschluss-Stelle für künftige Erweiterungen.

**Branch-Vorschlag:** `feature/accents-global-list-integration` (wenn
zusammen mit Multi-List-Support geplant).

---

### Doku-Note: Personal-Decks bleiben außerhalb der globalen Auswahl

**Kein Backlog-Item — bewusste Spec-Entscheidung der Stufe-5-
Diskussion (2026-04-29).**

Persönliche Stapel speichern ihre Quell-Listen als Teil der Deck-
Identität in `PersonalDeck.sourceListIDs` und einen einmal gemischten
`cardOrder`-Snapshot. Die Listen-Auswahl ist **nicht** ein modul-
weiter Selection-State, sondern eine **Eigenschaft des Stapels**.
Wenn Stufe 5 hier eingreifen würde, würden sich beim Toggle-On
plötzlich die Quell-Listen aller Decks ändern — User-Daten
würden effektiv mutiert, Mastery-Snapshots wären invalidiert.

**Konsequenz:** der globale Toggle hat **keine Wirkung** auf
existierende oder neue Personal-Decks. Die List-Selection-Sheet
beim Deck-Erstellen/Bearbeiten zeigt weiterhin den vollen Catalog,
die Auswahl wird in den Deck eingefroren.

Diese Note ist hier dokumentiert, damit Future-You / Future-Claude
beim Lesen der Stufe-5-Spec nicht den Reflex bekommt, „Personal-
Decks vergessen — nachträglich integrieren". Es war kein Vergessen,
es war eine Architektur-Entscheidung.

---

## Sache-B-Spec-Erweiterungen (Tags `v2-elumi-setup-always-show` + `v2-elumi-setup-tweaks-v2`, 2026-04-30)

Das ursprüngliche Sache-B-Setup-Modal-Design (Tag
`v2-time-picker-modal`, 2026-04-29 — Modal nur einmal beim
Erstöffnen, danach Re-Edit über Pencil) wurde am 2026-04-30 in
zwei Iterationen weiterentwickelt:

**Iteration 1** (Tag `v2-elumi-setup-always-show`, 3 Commits):
- Modal erscheint jetzt **bei jedem** Elumi-Tab-Open, nicht mehr
  nur einmalig. `appTrainingGeneratorOnboardingSeenKey` ist
  deprecated (Wert wird nicht mehr gelesen oder geschrieben),
  bleibt aus Backward-Compat in `AppStorageKeys.swift` und
  `AccountScopedKeys.userDefaultsKeys` registriert.
- Process-Hint-Zeile im Modal („Zeit wählen → Slot starten →
  Üben") als dezente `.caption`-Orientierung.
- `timeDisplayCard` kompakter: XXL-Zahl 56 → 46pt, vertikales
  Padding 10 → 6pt, damit der „Los geht's!"-Spin-CTA komplett
  über dem Footer sichtbar bleibt.

**Iteration 2** (Tag `v2-elumi-setup-tweaks-v2`, 5 Commits):
- Versuch-Counter „Versuch X/3" verschoben aus separater
  Caption-Zeile **in den „Nochmal drehen"-Button** als Sub-Label
  (`.caption2` Schrift). Der Jetzt-üben-Button bekam einen
  symmetrischen Sub-Label-Slot mit der gewählten Trainings-Dauer
  in Klammern (z. B. `(15 min)`). Damit verschwand der
  vertikale Layout-Sprung beim Slot-Phase-Wechsel (revealed →
  spinning) — beide Buttons sind durchgehend gleich hoch.
- 4 Zeit-Optionen statt 3: `[5, 10, 15, 20]`, im Modal als
  2×2-`LazyVGrid`. `TrainingGenerator.generate(duration: 5,
  focus:)` wurde vor dem Branch-Start verifiziert (liefert
  `buildFiveMinute(focus:)` → 2 Blöcke: Warmup 2min + Kern 3min).
  Default bleibt 10min.
- `timeDisplayCard`-Inhalt **horizontal zentriert**: Section-
  Header „TRAININGSZEIT" und XXL-Wert beide mittig, mit
  Spacer-Spacer-Pattern. Links 40pt-Reserve-Slot, rechts 40pt-
  Pencil — ehrliche Card-Mitte.
- Pre-Spin-Result-Slots: kleine Sparkle-im-Circle + „—"-Caption
  ersetzt durch **großes zentriertes Fragezeichen** (28pt
  questionmark in Section-Accent-Color, opacity 0.75).
  Card-Dimensions unverändert.
- Result-Card-Icons (Reveal-State) skaliert:
  HomeModuleIconView 40 → 52pt (+30%), Elumi-Cartoon-Assets
  38×38 → 50×50 (+32%). Card-Dimensions unverändert.

Der ursprüngliche Sache-B-Stand (Modal-only-once, 3 Chips, Card-
Layout 1.0) ist damit obsolet. Falls Future-You / Future-Claude
in den Sache-B-Commits liest und sich wundert „warum sieht es
heute anders aus": die hier gelisteten Tweaks sind die Antwort.
Kein Bug, sondern Spec-Iterationen nach realer Nutzung.

---

## 🛠️ Spec-Wissen: Vokabel-Cleanup im SQLite-Bundle

**Erstmals dokumentiert 2026-04-30, Tag `v2-vocab-cleanup-milchtritt`** —
falls weitere User-Reports „Wort X ist sinnlos / falsch übersetzt, bitte
löschen" auflaufen, ist der Cleanup-Pfad jetzt erprobt:

**Quelle:** `FRDEVocabMVP/FRDEMasterLexicon.sqlite` (~65 MB Bundle-DB).
6 Tabellen: `entries`, `senses`, `forms`, `examples`, `pronunciations`,
`relations`. Jede Vokabel hat eine `entry_id` (Primary Key in `entries`),
auf die alle anderen Tabellen via Foreign-Key-Spalte zeigen.

**Workflow:**

1. **Eintrag identifizieren** (case-insensitive, mehrere Felder):
   ```sql
   SELECT entry_id, lemma_fr, lemma_de, word_class FROM entries
   WHERE lemma_fr LIKE '%suchwort%' OR lemma_de LIKE '%suchwort%';
   ```
   Plus `senses.translation_de`, `forms.form` durchsuchen — das zu
   löschende Wort kann in mehreren Tabellen-Spalten als String stehen.

2. **Ähnlich aussehende, aber andere Vokabeln prüfen** — `le patou`
   (Pyrenäenberghund) sieht aus wie `le patounage` (Milchtritt), darf
   aber nicht mit-gelöscht werden. Manuelle Inspection vor DELETE.

3. **Volle Reihenfolge der Tabellen-Cleanups** in einer Transaction
   (Foreign-Key-Order, Eltern zuletzt):
   ```sql
   BEGIN TRANSACTION;
   DELETE FROM relations WHERE entry_id IN (X, Y) OR related_entry_id IN (X, Y);
   DELETE FROM examples WHERE entry_id IN (X, Y);
   DELETE FROM forms    WHERE entry_id IN (X, Y);
   DELETE FROM senses   WHERE entry_id IN (X, Y);
   DELETE FROM entries  WHERE entry_id IN (X, Y);
   COMMIT;
   VACUUM;
   ```
   Wichtig: `relations` hat **bidirektionale** Verlinkung
   (`entry_id` UND `related_entry_id`) — beide Seiten löschen, sonst
   bleiben tote Pointer auf benachbarte Vokabeln zurück.

4. **VACUUM** nicht vergessen — sonst bleibt die DB-Datei gleich groß
   trotz gelöschter Rows. Bei Milchtritt-Cleanup hat VACUUM 3 MB
   reklamiert (65 → 62 MB).

5. **Verifikations-Query nach Delete:**
   ```sql
   SELECT COUNT(*) FROM entries WHERE entry_id IN (X, Y);  -- sollte 0
   SELECT COUNT(*) FROM forms   WHERE entry_id IN (X, Y);  -- sollte 0
   -- … für alle 5 abhängigen Tabellen
   ```

6. **Build-verify** — die DB ist im App-Bundle, Build muss erfolgreich
   durchlaufen (sollte er, da binary asset, kein Schema-Bezug im Code).

7. **User-Daten nicht anfassen.** Lernfortschritt, Personal-Decks, alte
   Lexikon-Caches in UserDefaults referenzieren ggf. die gelöschten
   `entry_id`s. Tote Referenzen werden im UI als „Vokabel nicht
   gefunden" silently übersprungen — Cleanup von User-State ist
   Migration-Territorium und wäre ein eigener Branch mit explizitem
   Spec.

8. **Random-Shuffle-Test im Sim** ist bei einzelnen Vokabel-Cleanups
   unverlässlich (Treffer-Wahrscheinlichkeit niedrig). DB-Grep
   verifiziert vollständige Entfernung aus Source-Set zuverlässiger.

**Tools-Hinweis:** `sqlite3` ist auf macOS Standard verfügbar. Keine
Node.js / Python-Helper nötig. Datei ist im Repo getrackt — Diff
zeigt nur „Binary files differ", aber `git revert` / `git checkout
HEAD~1 -- file.sqlite` funktioniert normal.

---

## 🎮 Player-Level-System (Super Learner etc.) — Spec offen

**Erfasst 2026-04-30** beim Pool-Vereinheitlichungs-Branch
(`feature/training-session-flow`, Tag-Folge `v2-vocab-cleanup-milchtritt`
→ noch in Arbeit). Mit der Zusammenführung von `arcadeCredits` +
`playCredits` zu einem einzigen Pool wurde der vorherige separate
Power-Up-Pool (`ElumiCreditsStore`, durch Slot-Spin gefüllt für
Rescue/Skip im Arcade) verdrängt — Rescue + Skip kosten ab Stufe 1b
aus demselben Ticket-Pool wie der Spielstart. **Konsequenz: ohne
Player-Level-Boni bezahlt der User Power-Ups aus dem gleichen
Topf wie Spielstarts.**

**Geplante Boni (Spec-Skizze, nicht abgeschlossen):**
  • **Extra Rescue/Skip pro Spiel ab bestimmtem Player-Level** —
    z.B. ab Level 10: 1 kostenfreier Rescue pro Run, ab Level 20:
    1 kostenfreier Skip zusätzlich. So wird das Power-Up zu einem
    Level-Reward, nicht einem Pool-Verbrauch.
  • **Pro-Tickets** — separate Sub-Kategorie der Tickets, höherer
    Wert (z.B. „Pro-Tickets" für Premium-Modi). Architektur:
    weiterer optionaler Pool oder Markierung am Ticket-Eintrag.
  • **Bonus-XP-Multiplikator** — Tier-Boost (z.B. ab Level 15:
    +10 % XP, ab Level 25: +20 %). Greift in `ProgressService`
    beim Award-Pfad.

**Architektur-Hook:** Rescue + Skip könnten von festem Pool-Verbrauch
zu Level-Bonus umgestellt werden — siehe
`ElumiArcadeGameView+PlayCredits.consumePlayCreditRescue()` und
`consumePlayCreditSkipRound()`. Heute hartes `arcadeCredits -= 1`;
mit Level-System würde dort zuerst geprüft, ob ein kostenfreier
Use-Slot frei ist (Counter pro Run), erst danach Pool-Verbrauch.

**Naming-Note:** Die `playCredit…`-Symbol-Namen in
`ElumiArcadeGameView+PlayCredits.swift` sind aus Backward-Compat-
Gründen erhalten (8 Stellen). Bei Player-Level-Refactoring bietet
sich an, das gemeinsam in `arcadePowerUp…`-Namen umzubenennen — die
heutigen Doc-Comments machen klar dass die Pool-Quelle ohnehin
`arcadeCredits` ist.

**Priorität:** Mittel — kein Blocker, aber im Bestand der App fehlt
die Differenzierung zwischen „Eintritt zahlen" und „Hilfe nutzen"
sichtbar, was die Tickets-Mechanik fad wirken lässt sobald der User
sich an den einen Pool gewöhnt hat.

**Erstellt am:** 2026-04-30 (Stufe 1b Pool-Vereinheitlichung,
Branch `feature/training-session-flow`)

---

## 📋 Lernjahr-UI fehlt in 3 Modul-Sheets (Pre-existing seit V1)

**Symptom:** Lernjahr-Filter ist global (`appLernjahrMaxKey`), greift in allen
Modulen. Aber Lernjahr-UI (Edit-Möglichkeit) existiert nur in:
- `ListPickerSheet` (Listen, Akzente, Word Runner)
- `ChainListSelectionSheet` (Chain-Setup-Modal, ab `v2-training-session-flow`)

Karteikarten / Quiz / Training (Vokabeln, Verben, Verbformen, Nomen,
Artikel) nutzen `ListSelectionSheet` bzw. `FlashcardStackComposerSheet` —
kein Lernjahr-UI.

**Discovery-Problem:** User der primär über Karteikarten / Quiz /
Training einsteigt, kann das Lernjahr-Setting nirgends finden. Filter
wirkt trotzdem (Default 99 = alles, oder zuletzt-gesetzter Wert), aber
editieren geht nur über andere Module.

**Lösungs-Optionen:**
- **(a) Eines der 3 Sheet-Patterns als Standard wählen, andere
  migrieren.** Vereinheitlicht UX, aber großer Refactor (3 Sheets,
  alle Module-Setups touched).
- **(b) Lernjahr-Setting in Settings-View als zentralen Edit-Punkt
  ergänzen.** Klein, schnell — User kann Wert global überall finden.
  Aber bricht das Modul-lokale-Edit-Pattern in Listen/Akzente/Word
  Runner.
- **(c) Beides** — Settings als zentraler Edit-Punkt sofort, Sheet-
  Vereinheitlichung später als größerer Refactor.

**Spec-Diskussion nötig** vor Implementation. Eigener Branch:
`chore/unify-list-pickers-with-lernjahr` (oder kurzfristig
`chore/lernjahr-in-settings`).

**Erfasst beim:** Stufe 1c (Branch `feature/training-session-flow`,
2026-04-30) — User hat den Gap im Smoke-Test entdeckt, dass Lernjahr
im Chain-Setup-Modal sichtbar ist, in Karteikarten/Quiz/Training aber
nicht.

**Priorität:** Mittel — Discovery-Problem, nicht nur Kosmetik.
Funktional kein Bug (Filter wirkt korrekt), aber UX-Inkonsistenz.

---

## 🔊 Slot-Machine Sounds — fehlende Sound-Files (Branch `feature/slot-machine-sounds`, 2026-04-30)

**Erstmals aufgesetzt** in commit `855ce93` mit
`SlotAudioPlayer.swift` und dem Click-Sample
`Sounds/slot_reel_click.wav`. Drei weitere Sound-Events laufen
aktuell mit **iOS-System-Sound-Platzhaltern** und müssen durch
echte Files ersetzt werden:

  • **Settle** (Reel-Stillstand, `phase == .landed`) — aktuell
    System-Sound 1057 (Tink). Brauche: kurzer „Klacken"-Sound,
    ~150-300 ms, ähnlich einem Mechanik-Stop.
  • **Win** (Reveal mit `elumiCount == 2`) — aktuell System-Sound
    1025. Brauche: kurzes positives Cue, ~400-600 ms, „kleiner
    Erfolg".
  • **Jackpot** (Reveal mit `elumiCount == 3`) — aktuell System-
    Sound 1306. Brauche: längerer feierlicher Sound, ~1-2 Sek.,
    deutlich opulenter als Win. Wird in **Stufe 6** des
    `feature/training-session-flow`-Branches bei der Feuerwerk-
    Animation auch visuell gespiegelt.

**Beschaffungs-Pfad** (laut Project-Konvention): Freesound oder
ElevenLabs (Sound-Generation) — dann ins `Sounds/`-Verzeichnis
ablegen, pbxproj-Eintrag (BuildFile + FileReference + Group +
Resources-Phase, vier Stellen wie für `slot_reel_click.wav`).
**Konfigurations-Punkt** in `SlotAudioPlayer.swift`: aktuell sind
die System-Sound-IDs hart-codiert in `playSettle/playWin/playJackpot`
(je `AudioServicesPlaySystemSound(ID)`-Aufruf). Beim Swap auf echte
Files: API-Wechsel auf den AVAudioPlayer-Pool-Pattern (analog
zur Click-Implementation), oder zentrales File-Mapping in der
Klasse.

**Audio-Mute-Toggle**: existiert bereits, lebt im
`FeedbackPlayer.areSoundsEnabled`-Toggle (Footer-Sound-Toast).
`SlotAudioPlayer` respektiert ihn via UserDefaults-Read auf
`soundsEnabledKey`. Bei Sound-Erweiterungen (echte Settle/Win/
Jackpot-Files) sollten **alle Play-Pfade weiterhin den Mute-State
respektieren** — Pattern ist die `guard soundsEnabled else { return }`-
Zeile am Anfang jeder Play-Methode.

**Priorität:** Mittel — die System-Sound-Platzhalter sind funktional,
aber stilistisch nicht App-konsistent (iOS-System-Klang sticht
gegen die App-eigene Sound-Welt heraus).

---

## Duration-Card 3min temporär statt 6min — nach Stufe 4b-Tests rückbauen

**Status:** Aktiv (Branch `feature/training-session-flow`).

`ElumiTabView.swift` Z. 287 — `durationOptions: [Int] = [3, 12, 18]`.

Die linke Zeit-Card im Setup-Modal wurde temporär von **6 min** auf
**3 min** geändert, damit die Stufe-4b-Chain-Force-Done-Hooks
(Karteikarten / Akzente / Quiz / Training) im Sim mit kurzen Step-
Timern getestet werden können (3 min total / 3 Steps ≈ 1 min/Step).
`durationDefault = 12` ist unverändert — die 3-min-Option ist also
opt-in pro Spin, kein Default-Drift.

**Migration**: defensive-on-Read in `mainContent.onAppear` fängt
existierende User mit gespeichertem Wert `6` ab und resettet auf
`durationDefault` (= 12). Idempotent. Kein Datenverlust.

**Rückbau-Trigger**: nach Stufe 4b komplett (alle 5 Module-Hooks)
und Stufe 4b-6 (Toast-Wording-Update) gemergt sind.

**Rückbau-Schritt**:
1. Zeile in `ElumiTabView.swift` Z. 287 zurück auf `[6, 12, 18]`
2. Doc-Comment-TODO oberhalb derselben Zeile löschen
3. Diesen Backlog-Eintrag markieren als „erledigt"

**Priorität**: Niedrig — temporär, automatischer Rückbau geplant.

---

## Module-Done-Screens: Chain-CTA muss above-the-fold sichtbar sein

**Status:** Aktiv (Branch `feature/training-session-flow`, entdeckt 2026-05-02 beim 4b-3-Smoke).

**Symptom:** Auf dem Quiz-Done-Screen (`quizResultScreen` in `QuizView+Components.swift:220`) liegt der Chain-Primary-CTA („Weiter zu Quiz" / „Training abschließen") **unter dem sichtbaren Viewport**. User muss scrollen, um die wichtigste Aktion zu sehen. Im Stufe-3-Chain-Flow ist das die zentrale Übergangs-Stelle zum nächsten Modul — sie sollte unmittelbar erkennbar sein, ohne Scroll-Geste.

**Vermutlich gleiche Issue bei** Karteikarten / Training / Verbformen / Akzente Done-Screens — alle nutzen `SessionSummaryView` als geteilte Komponente und bauen darum herum modul-spezifischen Reward-Content (Würmchen-Hero, Streak-Chips, „Perfekte Lektion!"-Text). Bei vollem Reward-Hero (Level-Up + Perfekt-Bonus + Multi-Reward-Chips) drückt der Content den CTA unter den Fold.

**Quelle (Quiz)**: `QuizView+Components.swift:220-339` — `ScrollView` mit `quizResultHero` (groß), Reward-Card, Stats-Card, dann SessionSummaryView mit CTA. Vertikal ~700pt+, sichtbarer Viewport iPhone-Pro ~750pt minus Top-Bar-Inset/Bottom-Bar = effektiv ~500pt.

**Lösungs-Skizzen** (zur Diskussion):
1. **CTA als sticky-bottom**: SessionSummaryView-CTA-Footer als `.safeAreaInset(edge: .bottom)` rausziehen, immer sichtbar. Reward-Hero scrollt unter dem Footer durch.
2. **Reward-Hero kompakter**: vertikale Höhe reduzieren — kleineres Würmchen-Icon, Stats und Reward-Headline in einer Zeile, kein „Perfekte Lektion!"-Block extra. Spart ~150pt.
3. **CTA dupliziert**: zusätzlicher Mini-CTA oben (Top-Bar-Bereich) plus Voll-CTA unten. Redundant aber sicher sichtbar.
4. **Layout-Reorder**: SessionSummaryView (mit CTA) ZUERST, Reward-Hero darunter. Verzichtet auf das „Celebration-zuerst"-Pattern aber maximiert CTA-Visibility.

**Empfehlung (vorläufig)**: Variante 1 (sticky-bottom-CTA) — minimalste Layout-Änderung, behält Celebration-First-Pattern, CTA immer reachable. Bei Karteikarten / Training / Verbformen / Akzente analog ausrollen.

**Trigger**: nach 4b-Sweep komplett, vor App-Release. Aktuell **Smoke-Test-Tauglichkeit ist gegeben** (CTA ist erreichbar, nur unter-dem-Fold) — kein Blocker für Stufe 4b.

**Priorität**: Mittel — UX-relevant für die Chain-Flow-Erfahrung, aber kein Funktions-Bug.

---

## State-Leak: Akzente-Setup-Skip kann Chain-Step-Auswahl überschreiben

**Status:** Aktiv (Branch `feature/training-session-flow`, beobachtet 2026-05-02 beim Commit-1-Smoke).

**Symptom:** Nach mehreren Chain-Tests in derselben App-Session konnte das Tappen auf „Training starten" auf dem Pre-Screen einer KK-First-Chain zu **Akzente** (statt Karteikarten) führen. Reproduzierbar nur **ohne** App-Kill zwischen den Tests; nach frischem App-Start verschwindet das Verhalten.

**Vermutete Wurzel:** `AccentsEntryView.handleAccentsAppear` (Stufe 4b-5 / Setup-Skip-Commit) feuert auf jedem `.onAppear`. Wenn AccentsEntryView noch im NavigationStack hängt von einer vorigen Akzente-Test-Session — z.B. weil ein `.fullScreenCover`-Dismiss + Re-Mount (Quiz/KK-Pop) die View revisit triggert — und der `launchContext` der alten View noch `shouldAutoStart=true` hält, öffnet das Cover-Sheet erneut. Effektiv überschreibt die Akzente-Cover-Layer das Karteikarten-Modul-View, das gerade frisch gepusht wurde.

**Quelle:** `AccentsEntryView.swift:74-86` (`handleAccentsAppear()`):
```swift
private func handleAccentsAppear() {
    guard launchContext?.shouldAutoStart == true,
          activeSession == nil else {
        return
    }
    let mode = launchContext?.preferredMode ?? .uben
    startSession(mode: mode)
}
```

Vermutete Fix-Skizze: zusätzlicher Guard auf `launchContext?.chainContext?.id == TrainingChainStore.shared.currentChain?.id` — Auto-Start nur, wenn der View-launchContext zur AKTUELL aktiven Chain im Store gehört, nicht zu einem alten. Alternativ: launchContext-„consumed"-Flag in `@State`, das nach erstem `startSession`-Aufruf gesetzt wird und Re-Triggern verhindert.

**Reproduktion:** in einer App-Session 2-3 Chain-Tests durchspielen mit unterschiedlichen 1.-Steps; ggf. tritt der Bug nicht jedes Mal auf, weil's auch von Pop-Reihenfolge abhängt.

**Workaround heute:** App-Kill + Neustart vor jedem Chain-Test.

**Priorität:** Mittel — User-irritierend, aber nicht Daten-zerstörend, nur in Test-Sessions reproduzierbar (User würde im realen Lauf zwischen Chains pausieren). Nach 4b-Sweep aufnehmen, vor App-Release fixen.

---

## Chain-Mode Back-Navigation: aus Modul-Step zurück führt auf Pre-Screen statt Slot/Home

**Status:** Aktiv (Branch `feature/training-session-flow`, beobachtet 2026-05-02 beim Commit-1-Smoke).

**Symptom:** Im Chain-Modus, wenn der User aus einem Modul-Step (z.B. Karteikarten) per Back-Chevron zurück navigiert, landet er auf dem `TrainingChainOverviewView`-Pre-Screen — nicht direkt zurück auf der Slot-Maschine im ElumiTab oder auf der App-Home. Bei 1-Step-Chains wirkt das verwirrend, weil der Pre-Screen visuell ähnlich zum Modul-Setup-Screen ist und die Geste „Back" eher den ElumiTab erwarten lässt.

**Quelle:** Module-spezifische `handleBackNavigation()`-Funktionen rufen alle `dismiss()` auf (FlashcardsView, AccentsEntryView, QuizView, TrainingView). `dismiss()` pop-t **eine** NavigationStack-Ebene → User landet auf der Ebene direkt darunter, im Chain-Modus immer der Pre-Screen.

**Lösungs-Skizze**: in den Modul-`handleBackNavigation()`-Funktionen branchen auf `launchContext?.chainContext != nil`:
```swift
if launchContext?.chainContext != nil {
    // Chain-Mode: 2 Ebenen poppen → Pre-Screen + Modul → ElumiTab
    // ODER: chain abbrechen via TrainingChainStore.shared.clear()
    //       und dann zur Root navigieren
} else {
    dismiss()
}
```

Plus Spec-Frage: bei Multi-Step-Chain während Step 2 → Back: zum Pre-Screen oder zum vorigen Step? Macht keinen Sinn zum vorigen Step (war schon abgeschlossen). Vermutlich: immer zur Slot-Maschine mit Chain-Cancel-Hint („Chain abgebrochen, wieder einen Spin?").

**Reproduktion:** ElumiTab → Spin → „Jetzt üben" → Pre-Screen → „Training starten" → in Modul → tap Back-Chevron oben links.

**Priorität:** Mittel — UX-Friction in Chain-Tests; vor App-Release fixen, gehört zum Polish-Pass für die Chain-Navigation. Out-of-scope für Commit 1 (Setup-Skip + XP-Hide).

---

## Cutoff-Toast Auto-Fade verpasst Visibility (gelöst durch Commit-2-Modal-Refactor)

**Status:** Beobachtet beim Commit-1-Smoke-Test 2026-05-02. **Gelöst durch Commit 2** (Modal-Refactor) — kein Standalone-Fix nötig.

**Symptom 1 (Bug 2 aus Smoke):** Bei Vokabeln (Training-Modus, irgendein anderes Modul auch) zeigt der Cutoff-Toast altes Wording „du kannst manuell weitermachen" — kein Modal mit zwei Buttons. Erwartung: Modal mit „Aufgabe fertigmachen" + „Jetzt weiter".

**Symptom 2 (Bug 3 aus Smoke):** Bei Nomen (Training-Modus, Choice-Variante) erscheint der Cutoff-Toast scheinbar gar nicht. Tatsächliche Ursache: Toast erscheint kurz (Scale-In 200ms + Hold 3.5s + Fade-Out 500ms = 4.2s total) und wird zwischen Submit-Eval-Animation/Mode-Card-Re-Render visuell verpasst.

**Quelle:** `ChainTimerOverlayModifier.swift` aktueller Stand mountet `ChainCutoffToast` mit Auto-Fade-Schedule (Z. 139-143). Die im Stash@{0} liegende `ChainCutoffModal`-Component blockt mit Backdrop bis User aktiv reagiert — kein Auto-Fade.

**Fix:** Modal-Refactor in Commit 2 löst beide Symptome:
- Symptom 1: neues Modal-Wording mit zwei CTAs (Spec-konform)
- Symptom 2: Modal bleibt sichtbar bis User-Tap, kein Auto-Fade-Window

**Verifikation post-Commit-2:** explizit mit Force-Set `nomen,nomen,nomen` und `vokabeln,vokabeln,vokabeln` testen — beide Symptome sollten nach Commit-2-Stash-Pop weg sein.

**Priorität:** Niedrig — wird automatisch durch nächsten Commit gelöst.

---

## Chain-Modus: Retry-Loop bei falscher Antwort

Im Non-Speed-Modus (Verben/Vokabeln/Nomen/Articles) hat der User
unbegrenzte Retry-Versuche bei falscher Antwort (`maxAttempts = 999`).
Im Chain-Modus kann das zu UX-Problem werden: User strandet bei
schwieriger Aufgabe, Timer ist abgelaufen, kommt nicht zum nächsten
Step.

Future-Spec-Erwägung nach Commit 2 (mit Force-Done-Hooks):
- Max-Attempts-Begrenzung im Chain-Modus (z.B. 2-3 Versuche, dann
  Force-next-Card)
- Alternative: existierender Skip-Button verfügbar machen falls
  vorhanden

Erst nach echtem Chain-Test mit Force-Done entscheiden ob nötig.

Prio: Niedrig (User hat Modal mit „Jetzt weiter" als Notausgang).

## App-Crash am Ende einer Chain (One-Off, 2026-05-02)

User berichtet App-Crash während/nach 3. Modul der Chain. Beim
zweiten Versuch nicht reproduzierbar.

**Crash-Log-Befund:** Zwei `.ips`-Dateien vom 2026-05-02 in
`~/Library/Logs/DiagnosticReports/` gefunden:
- `myVoc-2026-05-02-152609.ips` (15:26)
- `myVoc-2026-05-02-163436.ips` (16:34)

Beide mit **identischer Stack-Signatur**:

- Exception: `EXC_BAD_ACCESS / SIGSEGV / KERN_INVALID_ADDRESS at 0x0`
- Triggered Thread: `com.apple.main-thread`
- Crash-Frame: `swift::TargetMetadata::isCanonicalStaticallySpecializedGenericMetadata`
  (NULL-Pointer beim Type-Metadata-Lookup)
- Pfad: `_UIHostingView.beginTransaction` → `flushTransactions`
  → `DynamicViewList.updateValue` → `_ConditionalContent.makeChildViewList`
  → 7 Levels `ConditionalTypeDescriptor.project` → `_AppearanceActionModifier`
  → `_ValueActionModifier2` (`onChange`) → `_OverlayModifier` (`overlay`)
  → `_InsetViewModifier` (`safeAreaInset`)

**Modifier-Stack matcht exakt `ChainTimerOverlayModifier`:**

```swift
content
    .safeAreaInset(edge: .top, spacing: 0) { topBarOverlay }   // _InsetViewModifier
    .overlay(alignment: .top) { toastOverlay }                  // _OverlayModifier
    .onChange(of: chainStore.timerExpired) { ... }              // _ValueActionModifier2
```

**Hypothese:** SwiftUI-Runtime-Crash (iOS 26 / macOS 26) beim
Mid-Transition-Re-Render eines Chain-aware Modul-Destinations,
wenn `chainStore.currentChain` flippt während ein DynamicViewList
(ForEach in Quiz/MC-Optionen, Matching-Pairs, FillBlank-Options)
gerade re-evaluiert wird. Type-Metadata-Cache findet beim Generic-
Spezialisieren der ConditionalContent-Hierarchie eine NULL-Slot.

**Entwarnung-Faktor — Hot-Fix vom 2026-05-02 macht's
unwahrscheinlicher:** Vorher leakte `currentChain` über `goHome()`
und ChainComplete-Header-Back. Mit dem Hot-Fix räumt jeder Pop-
nach-Root den Chain-Store ab (sequentiell vor / parallel zu
`navigationPath.removeAll()`) — die Race-Window mit
mid-flushTransactions-Update wird kleiner, weil currentChain nicht
mehr mid-render von einer entfernten Subtree wegrutscht.

**Beobachten ob Crash wiederkommt.** Bei Wiederholung detaillierte
Reproduce-Bedingungen sammeln:
- Welches 3. Modul war's (Karteikarten / Quiz / Akzente / Training-X)
- Genau bei welchem UI-Übergang (Done-CTA-Tap / Force-Done /
  ChainComplete-Render / Header-Back-Tap)
- Ob Chain-Timer gerade abgelaufen war (timerExpired-Toast aktiv)

**Mögliche Hypothesen-Bereiche** (für künftige Diagnose):
- ChainTimerOverlayModifier — die safeAreaInset+overlay+onChange-
  Kette ist in der Crash-Signatur exakt zu sehen. Möglicher
  Mitigation: ChainTimerOverlayModifier-Body in eine `struct`-
  Subview extrahieren statt direkt in `body` zu inlinen, damit
  SwiftUI weniger nested generic-specialization braucht.
- ChainComplete-Placeholder-Render-Pfad — Mount-Race wenn
  `replaceTopWith` von `.train`/`.quiz`/etc. auf `.trainingChainComplete`
  schaltet, während `currentChain` noch alten State hält.
- Resume-Store-Cleanup-Race bei Final-Step — adressiert durch
  Hot-Fix (clear() ist jetzt symmetrisch zu start()).
- Force-Done-Hook-State-Race in einem der 5 Module — kommt mit
  Commit 2 ins Spiel, beobachten ob Crash dort wiederkommt.
- TrainingChainStore.advanceChain mit nil currentChain (Race) —
  Code hat `guard let chain = currentChain else { return nil }`,
  also defensiv abgesichert. Nicht der Crash-Pfad.

Prio: Mittel (One-Off, aber Crashes generell ernst nehmen). Bei
zweiter Sichtung: Repro sammeln, dann ChainTimerOverlayModifier
in extrahierte Subview umbauen als ersten Mitigations-Versuch.

## Jackpot-Feier-Mechanik (Stufe 6 im 8-Stufen-Plan)

User-Spec aus 2026-05-02 Diskussion:
- Feier soll schon beim Slot-Reveal kommen (3× Game), nicht erst
  nach „Jetzt üben"
- Sofortige Reaktion: Konfetti / Sound / großer JACKPOT-Text
- CTA „Nochmal drehen" prominent statt „Zurück zum Setup"
- Pre-Screen entfällt bei Jackpot komplett
- Detail-Spec (Feier-Elemente, CTA-Mechanik, Auto-Reset) wird
  vor Implementation finalisiert

Aktuell: `TrainingChainCompletePlaceholderView` ist gedimmt,
unfeierlich, „Zurück zum Setup" nicht führend, nicht kindgerecht.

Implementation als Stufe 6 nach Sweep (Commit 2/3/4).

## SQLite-Daten-Fehler-Sammelpunkt

Beim Testen entdeckte Daten-Fehler in `FRDEMasterLexicon.sqlite`.
Werden gemeinsam in einer Massen-Migration gefixt sobald Liste
größer ist (Pattern wie Milchtritt-Cleanup).

Bekannte Fehler:
- „le mars" wird als „les mars" angezeigt (März fälschlich
  pluralisiert) — 2026-05-03

Beim Auftauchen weiterer Fehler: hier sammeln, nicht einzeln
fixen. Massen-Migration nach Sammlung in eigenem Commit.
