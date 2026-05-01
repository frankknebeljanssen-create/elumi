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
///   2. **`ChainCutoffToast`** als mittiger Overlay-Hint, der genau
///      einmal pro Step erscheint, sobald `timerExpired` von `false`
///      auf `true` wechselt. Auto-Fade-Animation: Scale-In 0.92→1.0
///      (200 ms) + Hold 3.5 s + Fade-Out (500 ms). Show-Once via
///      `chainStore.hasShownExpirationToast`-Flag + lokalem
///      `toastVisible`-State.
///
/// **Layout-Update 2026-05-01 (Stufe 4a-Fix)**: vorherige Variante
/// hatte den Hinweis als Banner unmittelbar unter der Timer-Bar —
/// nahm zu viel vertikalen Platz, kollidierte mit Modul-Content.
/// Jetzt: Bar bleibt schlank (~30 pt), Hinweis ist flüchtig + mittig.
///
/// **Stufe-4a-Verhalten** (rein deskriptiv): Toast triggert KEINEN
/// Force-Done. Stufe 4b ergänzt die Force-Done-Hooks pro Modul.
struct ChainTimerOverlayModifier: ViewModifier {
    @ObservedObject private var chainStore = TrainingChainStore.shared
    @State private var toastVisible: Bool = false

    /// Auto-Hide-Schedule-Werte. Hold-Phase + Fade-Out-Phase werden
    /// hier zentral gehalten, damit zukünftige UX-Änderungen nicht
    /// drei Stellen anfassen müssen.
    private let toastHoldSeconds: Double = 3.5
    private let toastFadeOutSeconds: Double = 0.5

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                topBarOverlay
            }
            .overlay(alignment: .top) {
                toastOverlay
            }
            .onChange(of: chainStore.timerExpired) { _, newValue in
                handleTimerExpiredChange(newValue)
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
           let step = chain.currentStep,
           chainStore.stepTotalSeconds > 0 {
            ChainStepTimerBar(
                stepNumber: chain.displayStepNumber,
                totalSteps: chain.totalStepCount,
                moduleName: step.title,
                remainingSeconds: chainStore.stepRemainingSeconds,
                totalSeconds: chainStore.stepTotalSeconds
            )
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

    // MARK: - Toast (mittig, flüchtig)

    /// Mittiger Soft-Cutoff-Toast. Erscheint via Scale + Opacity
    /// `transition`, wenn `toastVisible == true`. Position: oberer
    /// Drittel-Bereich (35 % der Container-Höhe), damit der Toast
    /// klar unter dem Modul-Header sichtbar wird, aber nicht den
    /// Modul-Content komplett überdeckt.
    @ViewBuilder
    private var toastOverlay: some View {
        if toastVisible {
            GeometryReader { proxy in
                ChainCutoffToast()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * 0.32
                    )
            }
            .transition(
                .scale(scale: 0.92).combined(with: .opacity)
            )
            // Toast soll keine User-Taps abfangen — er ist rein
            // informativ, der User soll weiter mit dem Modul
            // interagieren können (wischen, Mikrofon, Tippen, etc.).
            .allowsHitTesting(false)
        }
    }

    // MARK: - Show/Hide-Logik

    /// Wird vom `.onChange(of: chainStore.timerExpired)`-Handler
    /// gerufen. Zeigt den Toast genau dann, wenn der Timer gerade
    /// abgelaufen ist UND der Toast für diesen Step noch nicht
    /// gezeigt wurde. Schedules Auto-Hide nach Hold + Fade-Out.
    private func handleTimerExpiredChange(_ expired: Bool) {
        // Nur bei Übergang false → true und nur wenn Toast diesem
        // Step noch nicht angezeigt wurde. Beide Bedingungen sind
        // wichtig: ohne `expired` würden wir bei Step-Wechsel
        // (timerExpired auf false) den Toast triggern; ohne das
        // Store-Flag würde ein App-Re-Mount (z.B. Background-
        // Resume) den Toast erneut anzeigen.
        guard expired, !chainStore.hasShownExpirationToast else { return }

        chainStore.markExpirationToastShown()
        withAnimation(.easeOut(duration: 0.2)) {
            toastVisible = true
        }
        // Hold + Fade-Out. Nutzt Wall-Clock-Delays, kein Timer-State
        // im Store — der Toast ist UI-only, der Store-Flag schützt
        // gegen Re-Show.
        DispatchQueue.main.asyncAfter(deadline: .now() + toastHoldSeconds) {
            withAnimation(.easeIn(duration: toastFadeOutSeconds)) {
                toastVisible = false
            }
        }
    }
}
