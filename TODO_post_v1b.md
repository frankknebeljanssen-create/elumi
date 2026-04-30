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

### 5. Filename-Cleanup `AppIconRegistry.swift` → `UUIDExtensions.swift`

Aus dem Stufe-6-Icon-Cleanup (Tag `v2-icon-cleanup`, 2026-04-29):
nach Entfernen der gesamten Icon-Set-A/B-Switch-Maschinerie enthält
`AppIconRegistry.swift` nur noch eine Zwei-Zeiler-Convenience-
Extension `UUID.shortID` für kompakte Scanner-Logs. Filename ist
irreführend.

**Empfehlung:**
- Datei umbenennen `AppIconRegistry.swift` → `UUIDExtensions.swift`
  o.ä.
- pbxproj-Eintrag entsprechend anpassen
- File-Header-Comment anpassen (aktuell dokumentiert er den
  Cleanup-Hintergrund — kann reduziert werden auf einen kurzen
  „UUID-Convenience"-Header)

**Branch-Vorschlag:** `chore/rename-app-icon-registry-to-uuid-extensions`

**Priorität:** Niedrig — Hygiene, kein Funktions-Impact. Wegen
pbxproj-Touch eigener Branch (Lessons-Learned aus dem
TrainingGeneratorView-Cleanup: File-Renames in pbxproj sind ihr
eigenes Build-Verify-Risiko).

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
