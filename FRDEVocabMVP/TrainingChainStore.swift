import Foundation
import SwiftUI
import Combine

/// **Trainings-Session-Auto-Verkettung — Chain-Store**
/// (Stufe 1, 2026-04-30, Branch `feature/training-session-flow`).
///
/// In-Memory-Store für die aktuell laufende Trainings-Chain. Wird im
/// `ElumiTabView`-Scope als `@StateObject` gehalten und beim Slot-Spin
/// neu befüllt. **Persistiert NICHT** — Chain überlebt App-Restart
/// bewusst nicht (User-Spec: nach Restart frisch beim Setup-Modal).
///
/// Verantwortlichkeiten:
///   • `currentChain`: aktueller Chain-Context (nil = keine aktive Chain)
///   • `stepOutcomes`: aggregierte Reward-Outcomes pro Modul-Step (für
///     End-Summary in Stufe 4 — Stufe 1 sammelt nur, nutzt sie noch nicht)
///   • `start(_:)`: setzt Context, clear-t Resume-Stores aller drei
///     Module-Stores (Training/Quiz/Akzente) — User-Spec R5: keine
///     Resume-Konflikte mit Chain-Lauf.
///   • `advance()`: rotiert auf den nächsten Step (Stufe 2 nutzt das
///     aus den Modul-CTAs)
///   • `recordOutcome(_:)`: pusht ein abgeschlossenes Step-Result in
///     `stepOutcomes` (Stufe 4 zeigt das im End-Summary aggregiert)
///   • `clear()`: Setzt alles zurück — am Chain-Ende oder bei Abbruch.
@MainActor
final class TrainingChainStore: ObservableObject {
    /// **Stufe 2 (2026-04-30)** — Singleton. Pattern analog zu
    /// `ProgressStore.shared`, `AccountStore.shared`,
    /// `ElumiCreditsStore.shared`. Begründung: ab Stufe 2 wird der
    /// Store von mindestens **zwei Stellen** referenziert
    /// (`ElumiTabView` für Slot-Spin → Chain-Init, plus
    /// `TrainingChainOverviewView` für Back-Chevron-Clear). Singleton
    /// vermeidet Pass-Through über AppRuntimeContainer und matcht
    /// existierendes Codebase-Pattern für In-Memory-only Stores.
    static let shared = TrainingChainStore()

    @Published private(set) var currentChain: TrainingChainContext?
    @Published private(set) var stepOutcomes: [SessionRewardOutcome] = []

    /// Initialisiert eine neue Chain. Clear-t **vorab** alle drei
    /// expliziten Resume-Stores (Pattern aus
    /// `GameStateResetService.swift` Z. 57-59), damit Chain-Steps nicht
    /// auf alten Resume-States stolpern (z.B. Quiz, das mitten in einer
    /// alt-abgebrochenen Session weiterläuft statt frisch zu starten).
    func start(_ chain: TrainingChainContext) {
        // **R5 Resume-Konflikt-Auflösung** (Audit-Spec): Chain-Lauf darf
        // nicht zufällig auf einen alten Resume-State eines Moduls
        // treffen. Vor dem Chain-Lauf alle drei Stores leeren.
        TrainingSessionResumeStore.clear()
        AccentSessionResumeStore.clear()
        QuizSessionResumeStore.clear()

        currentChain = chain
        stepOutcomes = []

        #if DEBUG
        let path = chain.plannedSteps.map(\.rawValue).joined(separator: " → ")
        print("🔗 [TrainingChainStore] start — id=\(chain.id.shortID), steps=[\(path)], perStep=\(chain.perStepDurationMin)min")
        #endif
    }

    /// Rotiert den Index +1. Wird in Stufe 2 von den Modul-CTAs
    /// aufgerufen, wenn der User „Weiter zur nächsten Übung" tappt.
    func advance() {
        guard let chain = currentChain else { return }
        currentChain = chain.advancedToNextStep()

        #if DEBUG
        let idx = currentChain?.currentIndex ?? -1
        let total = currentChain?.totalStepCount ?? 0
        print("🔗 [TrainingChainStore] advance — index=\(idx)/\(total)")
        #endif
    }

    /// Sammelt das Outcome eines abgeschlossenen Steps für die spätere
    /// Aggregation im End-Summary (Stufe 4). Stufe 1 ruft das noch nicht
    /// auf — bleibt für Stufe-2-Hook bereit.
    func recordOutcome(_ outcome: SessionRewardOutcome) {
        stepOutcomes.append(outcome)
    }

    /// Räumt den Store komplett ab. Wird am Chain-Ende (nach
    /// End-Summary-CTA) oder beim manuellen Abbruch aufgerufen.
    func clear() {
        currentChain = nil
        stepOutcomes = []

        #if DEBUG
        print("🔗 [TrainingChainStore] clear")
        #endif
    }
}
