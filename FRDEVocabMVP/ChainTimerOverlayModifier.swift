import SwiftUI

/// **Trainings-Chain Timer-Overlay-Modifier** (Stufe 4a, 2026-05-01,
/// Branch `feature/training-session-flow`).
///
/// Wird in jedem Chain-aware Modul-Destination im
/// `AppDestinationHost` als `.modifier(ChainTimerOverlayModifier())`
/// angewendet. Wenn der `TrainingChainStore` eine aktive Chain hält,
/// blendet der Modifier oben eine `ChainStepTimerBar` ein (via
/// `safeAreaInset(edge: .top)`, sodass das Modul-Layout nicht in den
/// Top-Bereich kollidiert) und — wenn der Step-Timer abgelaufen ist
/// (`timerExpired == true`) — ein neutrales Soft-Cutoff-Banner
/// darunter.
///
/// **Stufe-4a-Verhalten** (rein deskriptiv): das Banner zeigt
/// „Trainingszeit für diese Übung ist abgelaufen — du kannst manuell
/// weiter, wenn du möchtest". Es triggert KEINEN Force-Done — der
/// User kann weitermachen oder über den Modul-Done-CTA → „Weiter zu
/// …"-Pfad weiter zur nächsten Chain-Stufe. Stufe 4b ergänzt den
/// Force-Done-Hook und passt das Wording auf die action-implizite
/// Variante an.
///
/// **Wenn keine Chain aktiv ist**: der Modifier ist transparent, das
/// Modul rendert wie ohne ihn — keine zusätzliche Layout-Inset-Höhe,
/// kein zusätzliches Rendering.
struct ChainTimerOverlayModifier: ViewModifier {
    @ObservedObject private var chainStore = TrainingChainStore.shared

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                overlayContent
            }
    }

    /// Zentrale Logik für den Overlay-Bereich. Wenn keine Chain aktiv
    /// ist (oder Daten nicht vollständig), liefert ein `EmptyView` —
    /// `safeAreaInset` interpretiert das als „kein Inset" und das
    /// Modul rendert wie ohne Modifier.
    @ViewBuilder
    private var overlayContent: some View {
        if let chain = chainStore.currentChain,
           let step = chain.currentStep,
           chainStore.stepTotalSeconds > 0 {
            VStack(spacing: 6) {
                ChainStepTimerBar(
                    stepNumber: chain.displayStepNumber,
                    totalSteps: chain.totalStepCount,
                    moduleName: step.title,
                    remainingSeconds: chainStore.stepRemainingSeconds,
                    totalSeconds: chainStore.stepTotalSeconds
                )

                if chainStore.timerExpired {
                    expiredBanner
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .background(
                // Halb-transparenter Hintergrund, damit die Bar sauber
                // vom Modul-Content getrennt ist. Kein voller Solid-
                // Fill, damit der Modul-Topbar-Bereich nicht doppelt
                // aussieht.
                AppTheme.Colors.background.opacity(0.85)
            )
        }
    }

    /// Soft-Cutoff-Banner. Stufe-4a-Wording: bewusst **neutral**
    /// formuliert — suggeriert KEINEN automatischen Force-Done, weil
    /// in 4a kein solcher implementiert ist. In 4b ergänzen wir
    /// Auto-Advance + entsprechend action-implizites Wording.
    private var expiredBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.Colors.warning)

            Text("Trainingszeit für diese Übung ist abgelaufen — du kannst manuell weiter, wenn du möchtest.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Colors.warning.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.Colors.warning.opacity(0.40), lineWidth: 1)
        )
    }
}
