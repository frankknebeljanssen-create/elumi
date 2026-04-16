import SwiftUI

struct AppBottomBar: View {
    @Environment(\.appOpenScanAction) private var globalOpenScanAction
    @AppStorage(appQuizHeartsKey) private var collectedHearts = 0
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let onHome: () -> Void
    let onFavorite: (() -> Void)?
    let onScan: (() -> Void)?  // Now used for Lexicon (historical name)
    let onSettings: (() -> Void)?
    var onScanCamera: (() -> Void)? = nil  // New: actual Scan/camera action
    var isHeartsActive: Bool = false
    var isScanActive: Bool = false  // Now isLexiconActive
    var isScanCameraActive: Bool = false
    var isSettingsActive: Bool = false

    private var homeTint: Color { Color(hex: "#78C8FF") }
    private var soundTint: Color {
        AppTheme.Colors.warning
    }
    private var scanTint: Color { Color(hex: "#FF9F40") }
    private var lexiconTint: Color { AppTheme.Colors.moduleLexicon }
    private var settingsTint: Color { Color(hex: "#B38DFF") }

    private var resolvedScanAction: (() -> Void)? {
        onScan ?? globalOpenScanAction
    }

    var body: some View {
        VStack(spacing: 6) {
            if let toast = feedbackPlayer.soundToggleToast {
                AppBottomBarSoundToastView(
                    toast: toast,
                    areSoundsEnabled: feedbackPlayer.areSoundsEnabled
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                AppBottomBarIconButton(
                    systemImage: "house.fill",
                    accessibilityLabel: "Home",
                    action: onHome,
                    foregroundColor: homeTint
                )

                Spacer(minLength: 0)

                ElumiFooterFeastButton(feedbackPlayer: feedbackPlayer)

                Spacer(minLength: 0)

                AppBottomBarSnackButton(
                    accessibilityLabel: "Sammlung",
                    action: onFavorite,
                    isActive: isHeartsActive,
                    kind: elumiSnackKind(for: collectedHearts),
                    badgeText: collectedHearts > 0 ? "\(collectedHearts)" : nil
                )

                Spacer(minLength: 0)

                AppBottomBarIconButton(
                    systemImage: "camera.viewfinder",
                    accessibilityLabel: "Scan",
                    action: onScanCamera ?? globalOpenScanAction,
                    isActive: isScanCameraActive,
                    foregroundColor: scanTint
                )

                Spacer(minLength: 0)

                AppBottomBarIconButton(
                    systemImage: isScanActive ? "book.closed.fill" : "book.closed",
                    accessibilityLabel: "Wörterbuch",
                    action: resolvedScanAction,
                    isActive: isScanActive,
                    foregroundColor: lexiconTint
                )

                Spacer(minLength: 0)

                // Menü-Icon: „Kreis mit drei Punkten" statt Zahnrad. Visuell
                // weniger technisch-rigide und gleichzeitig ein etabliertes
                // „mehr"-Symbol — führt weiterhin auf App-Einstellungen.
                AppBottomBarIconButton(
                    systemImage: isSettingsActive ? "ellipsis.circle.fill" : "ellipsis.circle",
                    accessibilityLabel: "Einstellungen",
                    action: onSettings,
                    isActive: isSettingsActive,
                    foregroundColor: settingsTint
                )
            }
            .padding(.top, 11)
            .modifier(AppBottomBarSurfaceModifier())
        }
        .animation(.easeInOut(duration: 0.2), value: feedbackPlayer.soundToggleToast)
    }
}
