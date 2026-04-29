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

### 1. Dead-Code-Cleanup `FlashcardsView+PersonalDeck.swift`

`createPersonalDeck(fromSelectedListIDs:)` und
`updatePersonalDeck(_:withSelectedListIDs:)` in
`FlashcardsView+PersonalDeck.swift` (ab Zeile 133 bzw. 160) haben
**keine Caller** (verifiziert via `grep -rn`-Suche während
Empty-Pool-Hint-Audit). Der echte Personal-Deck-Create/Update-Flow
läuft über `PersonalDecksView.swift:219` (createDeck) + `:235`
(updateDeck).

`TODO_post_v1b.md` hatte vor diesem Eintrag den falschen Pfad
referenziert (`:138` als „Quelle der Empty-Pool-Bug"). Beim Empty-
Pool-Hint-Implement wurde an der echten Stelle (PersonalDecksView)
gehängt, der Dead-Code blieb unberührt.

**Empfehlung:**
- Beide Funktionen entfernen
- File ggf. ganz löschen falls sonst nichts mehr drin steht
- pbxproj-Inspektion vor Commit

**Priorität:** Niedrig — Hygiene, keine User-sichtbaren Auswirkungen.

**Branch-Vorschlag:** `chore/remove-dead-personal-deck-helpers`

---

### 2. Personal-Deck-Löschen-Bug

User-gemeldet während Empty-Pool-Hint-Smoke-Test (2026-04-29):
„löschen option fehlt". Code dafür existiert in
`PersonalDecksView.swift:165` als Alert mit
`Button("Löschen", role: .destructive)`, getriggert via
`deckPendingAction != nil`-Binding. **Trigger-Pfad zur Alert-
Aktivierung scheint nicht zu funktionieren** — User konnte den
Lösch-Button nicht erreichen.

**Nicht reproduziert** im Empty-Pool-Hint-Branch (Scope war anders).

**Empfohlene Diagnose:**
- Wo wird `deckPendingAction` gesetzt? Long-Press-Gesture? Context-
  Menu? Tap auf Pencil-Icon?
- Funktioniert die Setter-Action im aktuellen Zustand?
- Funktioniert das Alert-Modal im aktuellen iOS-Sim?
- Falls Trigger korrekt ist: ist der Alert-Render-Pfad gebrochen?

**Branch-Vorschlag:** `fix/personal-deck-delete-trigger`

**Priorität:** Mittel — wenn der User keine Stapel löschen kann,
hängt er beim 2-Stapel-Limit fest (siehe nächstes Backlog-Item).

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

### 4. Selection-leer bei „Fertig"-Tap im Personal-Deck-Sheet

User tippt im `FlashcardStackComposerSheet` „Fertig" **ohne Listen-
Auswahl** → Sheet schließt, kein Deck wird angelegt. Silent no-op
durch `guard !selectedIDs.isEmpty` in `createDeck`/`updateDeck`.

**Vor-existent**, **nicht** durch Empty-Pool-Hint-Branch eingeführt
oder gelöst. Mein `validate`-Closure hat diesen Fall absichtlich
durchgelassen (Spec-Scope war nur Empty-Pool-after-Filter).

**Trivialer Fix:** validate-Closure-Erweiterung — wenn `selectedIDs.isEmpty`,
String zurückgeben („Wähle mindestens eine Liste."). Kein Code-Pfad-
Umbau nötig, der Sheet hat das Inline-Render bereits.

**Branch-Vorschlag:** `fix/empty-selection-personal-deck` oder als
zweiter Commit in einem zusammengefassten „Personal-Deck-Validation-
Polish"-Branch zusammen mit Item 2.

**Priorität:** Niedrig — kosmetischer UX-Bug, gleicher Pattern wie
Empty-Pool, leichte Spec-Erweiterung.

---
