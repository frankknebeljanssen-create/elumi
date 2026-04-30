import Foundation

// MARK: - ⚠️ DEPRECATED — Removal-Backlog
//
// **2026-04-30, Branch `feature/training-session-flow`, Stufe 1**:
// Mit der Trainings-Session-Auto-Verkettung (Slot-Spin diktiert die
// Modul-Reihenfolge direkt, siehe `TrainingChainContext.make(...)`) ist
// dieser dramaturgische Block-Generator obsolet. **Verifiziert per
// `grep -rn "TrainingGenerator.generate\|TrainingGenerator(" --include="*.swift"`
// am 2026-04-30**: einzige Live-Call-Site war `ElumiTabView.startTraining()`,
// jetzt durch Chain-Builder ersetzt. Keine weiteren Referenzen im Code.
//
// Die 3 Files (`TrainingGenerator.swift`, `TrainingGeneratorStore.swift`,
// `TrainingGeneratorModels.swift` ≈ 16KB / ~330 LoC) bleiben in Stufe 1
// erhalten, damit der Chain-Branch atomar bleibt. Removal als
// separates Backlog-Item in `TODO_post_v1b.md` nach Merge des
// `feature/training-session-flow`-Branches.

/// **Training-Generator** — baut aus Dauer + Fokus eine komplette
/// `GeneratedTrainingSession`. Reine Logik, keine Side-Effects, keine
/// UI-Referenzen — leicht unit-testbar und später durch echte
/// Lernfortschritts-Signale erweiterbar.
///
/// Dramaturgie-Regeln (V1, regelbasiert):
///   • Block 1 ist immer `warmup` (leichter Einstieg, bekanntes Vokabular)
///   • Block 2 ist die **Kernübung** (Flashcards oder Quiz)
///   • Block 3 ist eine **spielerische Challenge** (Speed/Articles/Accents)
///   • Block 4 (nur bei 15/20 min) ist **Wiederholung** oder zweiter Kern
///   • Keine zwei aufeinanderfolgenden Blöcke haben denselben
///     `exerciseType`
///
/// V2+-Vorbereitung: Die Signatur nimmt optional `history`-Daten entgegen
/// (Platzhalter heute), damit später schwache Bereiche bevorzugt
/// eingebaut werden können ohne den Call-Site der View anzufassen.
enum TrainingGenerator {
    /// Generiert eine neue Session. Jeder Aufruf produziert eine
    /// **neue** Zufallsvariante (für „Neu mischen"-Button auf dem
    /// Result-Screen).
    static func generate(
        duration: Int,
        focus: TrainingFocus
    ) -> GeneratedTrainingSession {
        let blocks: [TrainingBlock]
        switch duration {
        case 5:  blocks = buildFiveMinute(focus: focus)
        case 10: blocks = buildTenMinute(focus: focus)
        case 15: blocks = buildFifteenMinute(focus: focus)
        case 20: blocks = buildTwentyMinute(focus: focus)
        default: blocks = buildTenMinute(focus: focus)
        }
        return GeneratedTrainingSession(
            blocks: blocks,
            totalDurationMinutes: duration,
            focus: focus
        )
    }

    // MARK: - Session-Builder pro Dauer

    /// **5 min**: 2 Blöcke à ~2,5 min. Warmup + eine kurze Kernübung.
    private static func buildFiveMinute(focus: TrainingFocus) -> [TrainingBlock] {
        var blocks: [TrainingBlock] = []
        blocks.append(makeWarmup(durationMinutes: 2, intensity: 1))
        let core = pickCoreExercise(excluding: [.warmup])
        blocks.append(
            TrainingBlock(
                durationMinutes: 3,
                exerciseType: core,
                intensity: 2
            )
        )
        return blocks
    }

    /// **10 min**: 3 Blöcke à ~3 min. Warmup + Kern + Challenge.
    private static func buildTenMinute(focus: TrainingFocus) -> [TrainingBlock] {
        var blocks: [TrainingBlock] = []
        var used: Set<TrainingExerciseType> = []

        let warmup = makeWarmup(durationMinutes: 2, intensity: 1)
        blocks.append(warmup)
        used.insert(.warmup)

        let core = pickCoreExercise(excluding: used)
        blocks.append(TrainingBlock(durationMinutes: 4, exerciseType: core, intensity: 2))
        used.insert(core)

        let challenge = pickChallengeExercise(excluding: used)
        blocks.append(TrainingBlock(durationMinutes: 4, exerciseType: challenge, intensity: 2))
        return blocks
    }

    /// **15 min**: 4 Blöcke à ~3–4 min. Warmup + Kern + Challenge +
    /// zweiter Kern / Wiederholung.
    private static func buildFifteenMinute(focus: TrainingFocus) -> [TrainingBlock] {
        var blocks: [TrainingBlock] = []
        var used: Set<TrainingExerciseType> = []

        blocks.append(makeWarmup(durationMinutes: 3, intensity: 1))
        used.insert(.warmup)

        let core1 = pickCoreExercise(excluding: used)
        blocks.append(TrainingBlock(durationMinutes: 4, exerciseType: core1, intensity: 2))
        used.insert(core1)

        let challenge = pickChallengeExercise(excluding: used)
        blocks.append(TrainingBlock(durationMinutes: 4, exerciseType: challenge, intensity: 2))
        used.insert(challenge)

        // Vierter Block: Wiederholung, oder — falls review schon via
        // Fokus an anderer Stelle genutzt wurde — ein zweiter Kern.
        let fourth = pickReviewOrSecondCore(excluding: used)
        blocks.append(TrainingBlock(durationMinutes: 4, exerciseType: fourth, intensity: 2))
        return blocks
    }

    /// **20 min**: 4 Blöcke à ~4–6 min. Gleiche Struktur wie 15 min,
    /// aber mit längeren Einzelblöcken und leicht höherer Intensität.
    private static func buildTwentyMinute(focus: TrainingFocus) -> [TrainingBlock] {
        var blocks: [TrainingBlock] = []
        var used: Set<TrainingExerciseType> = []

        blocks.append(makeWarmup(durationMinutes: 4, intensity: 1))
        used.insert(.warmup)

        let core1 = pickCoreExercise(excluding: used)
        blocks.append(TrainingBlock(durationMinutes: 5, exerciseType: core1, intensity: 2))
        used.insert(core1)

        let challenge = pickChallengeExercise(excluding: used)
        blocks.append(TrainingBlock(durationMinutes: 5, exerciseType: challenge, intensity: 3))
        used.insert(challenge)

        let fourth = pickReviewOrSecondCore(excluding: used)
        blocks.append(TrainingBlock(durationMinutes: 6, exerciseType: fourth, intensity: 2))
        return blocks
    }

    // MARK: - Pick-Helfer

    private static func makeWarmup(durationMinutes: Int, intensity: Int) -> TrainingBlock {
        TrainingBlock(
            title: "Warmup",
            subtitle: "Schneller Einstieg mit bekannten Wörtern",
            durationMinutes: durationMinutes,
            exerciseType: .warmup,
            intensity: intensity
        )
    }

    /// „Kern" = ruhige, strukturierte Übung zum Festigen.
    private static let corePool: [TrainingExerciseType] = [.flashcards, .quiz]

    /// „Challenge" = spielerische oder spezialisierte Übung.
    private static let challengePool: [TrainingExerciseType] = [.speed, .articles, .accents]

    private static func pickCoreExercise(excluding: Set<TrainingExerciseType>) -> TrainingExerciseType {
        let candidates = corePool.filter { !excluding.contains($0) }
        return candidates.randomElement() ?? corePool[0]
    }

    private static func pickChallengeExercise(excluding: Set<TrainingExerciseType>) -> TrainingExerciseType {
        let candidates = challengePool.filter { !excluding.contains($0) }
        return candidates.randomElement() ?? challengePool[0]
    }

    private static func pickReviewOrSecondCore(excluding: Set<TrainingExerciseType>) -> TrainingExerciseType {
        // Bevorzugt `.review`, sofern nicht schon verwendet.
        if !excluding.contains(.review) { return .review }
        // Sonst: ein nicht-benutzter Kern-Typ.
        let remainingCore = corePool.filter { !excluding.contains($0) }
        if let alt = remainingCore.first { return alt }
        // Fallback: ein nicht-benutzter Challenge-Typ.
        let remainingChallenge = challengePool.filter { !excluding.contains($0) }
        return remainingChallenge.first ?? .flashcards
    }
}
