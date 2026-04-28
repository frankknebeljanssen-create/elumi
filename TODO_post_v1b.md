# Post-V1b TODO

## Empty-Pool-Hint (Branch: `feature/empty-pool-hint`)

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

**Priorität:** Niedrig — kosmetischer UX-Bug, keine Daten-Korruption.

**Erstellt am:** 2026-04-28 (während V1b-Lernjahr-Rollout)
