import SwiftUI

struct AppBottomBar: View {
    @Environment(\.appOpenScanAction) private var globalOpenScanAction
    @Environment(\.appOpenLexiconAction) private var globalOpenLexiconAction
    @Environment(\.appOpenGameHubAction) private var globalOpenGameHubAction
    @Environment(\.appOpenTrophyAction) private var globalOpenTrophyAction
    @AppStorage(appQuizHeartsKey) private var collectedHearts = 0
    /// Verfügbare Arcade-Credits = verfügbare Spiele (da
    /// `ArcadeCreditSystem.gamesCost == 1`). Die Footer-Badge zeigt
    /// jetzt diesen Wert statt der früheren Hearts-Sammlung —
    /// konsistent zum Game-Hub, wo Credits ebenfalls als „Spiele"
    /// dargestellt werden.
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let onHome: () -> Void
    let onFavorite: (() -> Void)?
    let onScan: (() -> Void)?  // Now used for Lexicon (historical name)
    let onSettings: (() -> Void)?
    var onScanCamera: (() -> Void)? = nil  // Legacy: vorher Scan-Button im Footer.
                                            // Bleibt als Param erhalten, weil
                                            // andere Screens (Lists/Quiz/etc.)
                                            // ihn noch befüllen — Footer rendert
                                            // ihn aber nicht mehr.
    /// **Pokal-Tab** (Home-Rebuild): ersetzt den alten Scan-Button im
    /// Footer. Führt zu `AppScreen.trophy` mit den ausführlichen
    /// Status-Cards (Streak, Level/XP, Lernstatus).
    var onTrophy: (() -> Void)? = nil
    var isHeartsActive: Bool = false
    var isScanActive: Bool = false  // Now isLexiconActive
    var isScanCameraActive: Bool = false
    var isTrophyActive: Bool = false
    var isSettingsActive: Bool = false

    private var homeTint: Color { Color(hex: "#78C8FF") }
    private var soundTint: Color {
        AppTheme.Colors.warning
    }
    private var scanTint: Color { Color(hex: "#FF9F40") }
    private var trophyTint: Color { Color(hex: "#FFC857") }
    private var lexiconTint: Color { AppTheme.Colors.moduleLexicon }
    private var settingsTint: Color { Color(hex: "#B38DFF") }

    /// Action für den Wörterbuch-Button. Vorher fiel das auf
    /// `globalOpenScanAction` zurück, wenn `onScan` nil war — das
    /// öffnete den Scanner statt das Wörterbuch (Bug-Report aus dem
    /// Lists-Screen-Footer). Jetzt saubere Trennung: eigener
    /// Lexicon-Env-Key als Fallback.
    private var resolvedScanAction: (() -> Void)? {
        onScan ?? globalOpenLexiconAction
    }

    /// **2026-05-04** — Spiele/GameHub-Action mit env-Fallback. Analog
    /// zu `resolvedScanAction`: explizit gesetzter Callback gewinnt;
    /// sonst greift die globale `appOpenGameHubAction`. Damit bleibt
    /// der Spiele-Button auch in Sheet-Kontexten (wo der explizite
    /// Callback meist `nil` ist) tappbar — `DismissingFooterActionsModifier`
    /// wraps den env-Wert mit `dismiss()`-first.
    private var resolvedFavoriteAction: (() -> Void)? {
        onFavorite ?? globalOpenGameHubAction
    }

    /// **2026-05-04** — Pokal/Trophy-Action mit env-Fallback. Bevor der
    /// `appOpenTrophyAction`-Env-Key existierte, war der Pokal-Button
    /// in Sheets ohne Callback gedimmt + nicht tappbar (siehe
    /// `AppBottomBarComponents.AppBottomBarIconButton`-Disable-Regel).
    /// Mit env-Fallback erbt jeder Screen die globale Trophy-Navigation
    /// von RootContentView.
    private var resolvedTrophyAction: (() -> Void)? {
        onTrophy ?? globalOpenTrophyAction
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

                // **2026-05-06 Tab-Bar-Refactor (Hybrid γ v3)** —
                // Maskottchen-Button übernimmt die ehemalige
                // Position 3 (Spiele/Game-Hub-Routing). Vorher waren
                // hier zwei separate Buttons: der Maskottchen-Button
                // (führte zum Elumi-Tab) und der Snack-Console-Button
                // (führte zum Game-Hub). Mit dem Refactor entfällt der
                // separate Elumi-Tab vollständig — die Slot-Maschine
                // ist nur noch über die Mix-Training-Card auf Home
                // erreichbar. Maskottchen-Button hier routet jetzt
                // direkt in den Game-Hub (siehe
                // `ElumiFooterFeastButton`).
                ElumiFooterFeastButton(feedbackPlayer: feedbackPlayer)

                Spacer(minLength: 0)

                // **Pokal-Tab** (Home-Rebuild Phase): ersetzt den
                // bisherigen Scan-Button im Footer. Scan ist nicht
                // mehr im Footer; er bleibt als Hero-Tool auf Home
                // und über `appOpenScanAction`-Env weiterhin global
                // aufrufbar — nur eben nicht mehr im Footer.
                AppBottomBarIconButton(
                    systemImage: isTrophyActive ? "trophy.fill" : "trophy",
                    accessibilityLabel: "Pokal",
                    action: resolvedTrophyAction,
                    isActive: isTrophyActive,
                    foregroundColor: trophyTint
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
