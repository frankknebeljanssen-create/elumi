import SwiftUI

/// **Trainings-Chain End-Summary — Platzhalter** (Stufe 3, 2026-05-01,
/// Branch `feature/training-session-flow`).
///
/// Wird gepusht, wenn der letzte Modul-Step der Chain via „Training
/// abschließen"-CTA durchgelaufen ist (siehe `AppDestinationHost`-
/// Wiring, Case `.trainingChainComplete`). Der Inhalt ist bewusst
/// minimal — Stufe 5 ersetzt die View durch eine aggregierte End-
/// Summary auf Basis von `TrainingChainStore.shared.stepOutcomes`,
/// die bereits durch die `advanceChain(recordedOutcome:)`-Pfade
/// gefüllt wird (R6-Vorbereitung).
///
/// **Verhalten:**
///   • Hero-Headline „Training abgeschlossen 🎉"
///   • Sub-Note „End-Summary kommt in Stufe 5 — du bekommst hier
///     bald deine Gesamtleistung der Chain als Aggregat."
///   • Ein „Zur Startseite"-CTA: räumt die Chain
///     (`TrainingChainStore.shared.clear()`) und ruft `goHome` —
///     Stack pop-t auf den Tab zurück.
///
/// **Back-Chevron:** kein eigener Back-Button; SwiftUI-Default-Back
/// pop-t im NavigationStack zum vorherigen Modul-Screen
/// (replaceTopWith hat den letzten Modul-Screen ersetzt → Top vor
/// dem Complete-Screen ist der Pre-Screen). Der User kann aber auch
/// direkt via Footer-Home oder den großen CTA zur Startseite springen.
struct TrainingChainCompletePlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void

    private let sectionStyle: AppSectionStyle = .home

    /// **Hot-Fix 2026-05-02 — alle drei Exit-Pfade räumen die Chain.**
    /// Vorher: Body-CTA „Zur Startseite" (Z. 71) war der einzige Pfad,
    /// der `TrainingChainStore.shared.clear()` rief. Header-Back,
    /// AppTopBar-Back und Footer-Home dismissten nur — der
    /// Chain-Store blieb mit `currentChain != nil` zurück und leakte
    /// in die nächste Modul-Session (Timer-Bar erschien). Jetzt
    /// räumt jeder Exit explizit. `goHome()` clear-t selbst zwar
    /// schon (siehe `AppNavigationCoordinator.goHome`), aber das
    /// hier ist Defense-in-Depth + Klarheit am Call-Site.
    private func dismissWithChainCleanup() {
        TrainingChainStore.shared.clear()
        dismiss()
    }

    private func goHomeWithChainCleanup() {
        TrainingChainStore.shared.clear()
        goHome()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            ModuleHeaderCard(
                systemImage: "checkmark.seal.fill",
                title: "Training abgeschlossen",
                accent: sectionStyle.accent,
                onBack: { dismissWithChainCleanup() }
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Training abgeschlossen 🎉")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("End-Summary kommt in Stufe 5 — du bekommst hier bald deine Gesamtleistung der Chain als Aggregat (Module, XP, Tickets, Genauigkeit).")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )

            Spacer(minLength: 0)

            Button {
                // Chain räumen, dann nach Home zurück.
                TrainingChainStore.shared.clear()
                goHome()
            } label: {
                Text("Zur Startseite")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.screenHeaderTopPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.md)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismissWithChainCleanup() }, onInfo: nil)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHomeWithChainCleanup() },
                onFavorite: nil,
                onScan: nil,
                onSettings: openSettings
            )
        }
    }
}
