import SwiftUI

/// **Trainings-Chain Timer-Overlay-Modifier** (Stufe 4a, 2026-05-01,
/// Branch `feature/training-session-flow`).
///
/// Wird in jedem Chain-aware Modul-Destination im
/// `AppDestinationHost` als `.modifier(ChainTimerOverlayModifier())`
/// angewendet. Wenn der `TrainingChainStore` eine aktive Chain hält:
///
///   1. **Kompakte `ChainStepTimerBar`** ganz oben (via
///      `safeAreaInset(edge: .top)`) — schiebt den Modul-Inhalt
///      sauber nach unten, kein Overlap mit AppTopBar oder
///      Modul-Content.
///
///   2. **`ChainCutoffModal`** als blockierender Overlay-Backdrop +
///      zentrierte Card mit zwei CTAs („Aufgabe fertigmachen" und
///      „Jetzt weiter"). Erscheint genau einmal pro Step, sobald
///      `timerExpired` von `false` auf `true` wechselt. Show-Once via
///      `chainStore.hasShownExpirationToast`-Flag, Visibility live
///      über `chainStore.cutoffModalVisible`.
///
/// **Layout-Update 2026-05-01 (Stufe 4a-Fix)**: vorherige Variante
/// hatte den Hinweis als Banner unmittelbar unter der Timer-Bar —
/// nahm zu viel vertikalen Platz, kollidierte mit Modul-Content.
/// Jetzt: Bar bleibt schlank (~30 pt), Hinweis als mittiger Toast.
///
/// **Stufe 4b-Modal-Refactor (2026-05-02)**: Toast wird durch das
/// `ChainCutoffModal` ersetzt — User muss aktiv zwischen „Aufgabe
/// fertigmachen" (Soft-Cutoff bleibt aktiv, nächster Submit löst
/// Auto-Advance über die existierenden Modul-Hooks) und „Jetzt weiter"
/// (sofortiger Force-Done über die `appChainForceAdvanceAction`-
/// Environment-Closure des aktiven Moduls) wählen. Modal blockiert
/// Modul-Interaktion via Backdrop. Auto-Fade-Logik (Stufe 4a) komplett
/// entfernt — Modal bleibt offen bis User reagiert.
struct ChainTimerOverlayModifier: ViewModifier {
    @ObservedObject private var chainStore = TrainingChainStore.shared

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                topBarOverlay
            }
            .overlay {
                cutoffModalOverlay
            }
            .overlay {
                wuermchenTickOverlay
            }
            .onChange(of: chainStore.timerExpired) { _, newValue in
                handleTimerExpiredChange(newValue)
            }
    }

    // MARK: - Würmchen-Tick (Modul 5)

    /// **Daily Drop Modul 5 (2026-05-23)** — Mikro-Würmchen-Tick pro richtiger
    /// Aufgabe, NUR im Count-Modus. Ein Mount hier deckt alle Count-Chain-
    /// Steps (Quiz + Vokabel) ab. Zeit-Chain + normale Module: kein Tick
    /// (EmptyView → kein Overlay-Effekt). Rein visuell, lauscht am globalen
    /// `successPulseTrigger`.
    @ViewBuilder
    private var wuermchenTickOverlay: some View {
        if chainStore.currentChain?.isCountMode == true {
            WuermchenTickOverlay()
                // **Modul 5 Fix (2026-05-23)** — Identität an den Step
                // (`currentIndex`) koppeln: Beim Step-Wechsel (chainAdvance
                // setzt `currentChain.advancedToNextStep()`) ändert sich die
                // `.id` → SwiftUI verwirft das alte Overlay samt evtl. noch
                // laufendem Tick und mountet ein leeres. So „rutscht" kein
                // Alt-Tick aus dem vorigen Step in den neuen durch.
                .id(chainStore.currentChain?.currentIndex ?? -1)
        }
    }

    // MARK: - Top-Bar (kompakt)

    /// Schmaler Top-Streifen mit der Timer-Bar. Wenn keine Chain
    /// aktiv ist (oder Daten unvollständig), liefert ein `EmptyView`
    /// — `safeAreaInset` interpretiert das als „kein Inset" und das
    /// Modul rendert wie ohne Modifier.
    @ViewBuilder
    private var topBarOverlay: some View {
        if let chain = chainStore.currentChain,
           chain.currentStep != nil,
           (chain.isCountMode || chainStore.stepTotalSeconds > 0) {
            chainBar(for: chain)
            .background(
                // Halb-transparenter Hintergrund, damit die Bar sauber
                // vom Modul-Content getrennt ist. Nicht voll-solid,
                // damit es sich nicht wie eine zweite Top-Bar anfühlt.
                AppTheme.Colors.background.opacity(0.92)
            )
            .overlay(
                // Hauchdünne Border-Bottom-Linie als visueller Cut zur
                // App-Top-Bar darunter. Konsistent mit der Footer-
                // Top-Border in `AppBottomBarSurfaceModifier`.
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            )
        }
    }

    /// **Daily Drop Modul 2 (2026-05-23)** — wählt die Bar je Modus:
    /// Count-Modus → `ChainStepCountBar` („Übung X von N"); sonst die
    /// klassische `ChainStepTimerBar` (Countdown). Die `||`-Bedingung in
    /// `topBarOverlay` garantiert, dass der Else-Zweig nur bei
    /// `stepTotalSeconds > 0` greift.
    @ViewBuilder
    private func chainBar(for chain: TrainingChainContext) -> some View {
        if chain.isCountMode {
            ChainStepCountBar(
                results: chainStore.exerciseResults,
                total: chainStore.totalExercises
            )
        } else {
            ChainStepTimerBar(
                sourceSlots: chain.sourceCenterSymbolKinds,
                currentStepIndex: chain.currentIndex,
                remainingSeconds: chainStore.stepRemainingSeconds,
                totalSeconds: chainStore.stepTotalSeconds
            )
        }
    }

    // MARK: - Cutoff-Modal (blockierend)

    /// Full-screen Cutoff-Modal mit Backdrop. Erscheint via Scale +
    /// Opacity-Transition, wenn `chainStore.cutoffModalVisible == true`.
    /// Render-Position: full-overlay über dem Modul, Backdrop fängt
    /// jegliche Touches ab — Modul-Content ist nicht mehr klickbar bis
    /// User eine der beiden CTAs tappt.
    @ViewBuilder
    private var cutoffModalOverlay: some View {
        if chainStore.cutoffModalVisible {
            ChainCutoffModal(
                moduleName: chainStore.currentChain?.currentStep?.title,
                onFinishTask: {
                    // Soft-Cutoff bleibt aktiv: `timerExpired = true`
                    // unverändert, damit der nächste Modul-Submit
                    // über die existierenden Hooks (4b-1/2/3/4)
                    // als Auto-Advance auflöst. Nur Modal verschwindet.
                    chainStore.dismissCutoffModal()
                },
                // Primary „Jetzt weiter" wird nur dann angeboten, wenn
                // das aktive Modul einen Force-Done-Handler im Store
                // registriert hat (siehe `registerForceAdvanceHandler`
                // in `TrainingChainStore`). Ohne Handler → `nil` → das
                // Modal versteckt den Primary-Button und User hat nur
                // den „Aufgabe fertigmachen"-Pfad. Tap auf Primary
                // schließt Modal + ruft den Handler aus dem Store.
                onAdvanceNow: chainStore.hasForceAdvanceHandler
                    ? { chainStore.forceAdvanceFromCutoffModal() }
                    : nil
            )
            .transition(
                .scale(scale: 0.92).combined(with: .opacity)
            )
        }
    }

    // MARK: - Show/Hide-Logik

    /// Wird vom `.onChange(of: chainStore.timerExpired)`-Handler
    /// gerufen. Triggert das Modal genau dann, wenn der Timer gerade
    /// abgelaufen ist UND das Modal für diesen Step noch nicht
    /// gezeigt wurde. `presentCutoffModal()` enthält die Show-Once-
    /// Guard, damit ein App-Re-Mount (z.B. Background-Resume mit
    /// `timerExpired == true`) keinen erneuten Trigger bedeutet.
    private func handleTimerExpiredChange(_ expired: Bool) {
        guard expired else { return }
        chainStore.presentCutoffModal()
    }
}
