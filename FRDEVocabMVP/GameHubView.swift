import SwiftUI

/// Game Hub — Phase 4 der Gamification-Architektur.
///
/// Rolle im System (bewusste Trennung zu Home und Progress Hub):
///   • Home        → „Wie läuft's?"  (kompakter Überblick + Motivation)
///   • Progress    → „Wo stehe ich?" (vollständiger Fortschritt)
///   • **Game Hub** → „Was bekomme ich dafür?"  (**Reward nutzen + Spiel starten**)
///
/// Der Screen zeigt in genau drei Zonen:
///   1) Hero — Credits als visuell dominante Zahl + Kontext-Zeile
///   2) CTA — *einer* großer Button „Spiel starten" (bzw. Empty-State-CTA)
///   3) Lern→Reward-Hinweis — wie Credits entstehen
///
/// Bewusst *nicht* enthalten:
///   • ausführliche Fortschrittsinfos (die leben im Progress Hub)
///   • mehrere Startbuttons / konkurrierende Aktionen
///   • Bonus-Runden-Mechanik, Highscore-Listen, Daily-Reward-UI — sind
///     als leere Slots mental vorbereitet, aber hier **noch nicht** gebaut.
struct GameHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @Environment(\.appOpenArcadeAction) private var openArcade
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0
    @ObservedObject private var progressStore = ProgressStore.shared
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    /// Optional — wird vom AppDestinationHost durchgereicht. Nur
    /// nötig für den Word-Runner-DEBUG-Eintrag (Live-Tasks aus
    /// echter Liste); GameHub selbst zeigt keine Listen-Daten.
    var listStore: VocabularyListStore? = nil
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    /// Navigations-Router, vom AppDestinationHost durchgereicht.
    /// Aktuell nur genutzt, um aus dem Word-Runner-Empty-State direkt
    /// auf die Listen-Auswahl zu springen (Cover schließen + push).
    var navigate: ((AppScreen) -> Void)? = nil

    // MARK: - Dev Shortcuts (nur DEBUG)
    //
    // Word Runner (Phase 2+3) hat noch keine eigene Credit-/Session-
    // Integration. Damit wir ihn testen können, ohne die Arcade-Route
    // umzubiegen, bekommt der Hub eine Kurztaste unten:
    // ein Tap öffnet ihn als FullScreenCover, Close schließt's wieder.
    @State private var showWordRunner: Bool = false

    private let sectionStyle: AppSectionStyle = .hearts
    private let livesPerCredit = 4   // sichtbare Credit → Leben Zuordnung
    private let xpPerCredit = ArcadeCreditSystem.xpPerCredit  // 20 XP = 1 Credit (Live-Wert)

    // MARK: - Derived

    private var hasCredits: Bool {
        arcadeCredits >= ArcadeCreditSystem.gamesCost
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                hubHeader
                heroBlock
                // Zwei gleichwertige Start-Buttons (Elumi + Word Runner)
                // direkt unter dem Hero — oben Auswahl, dann Start.
                // Die frühere separate Word-Runner-Dev-Shortcut-Card
                // ganz unten ist damit entfallen.
                gameStartButtons
                rewardExplainerBlock
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .fullScreenCover(isPresented: $showWordRunner) {
            WordRunnerGameView(
                listStore: listStore,
                onClose: { showWordRunner = false },
                onGoToLists: {
                    // Cover zuerst schließen, dann navigieren — sonst
                    // konkurriert der SwiftUI-Push mit der FullScreen-
                    // Cover-Dismiss-Animation.
                    showWordRunner = false
                    navigate?(.lists(nil))
                }
            )
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: { openSettings() },
                isHeartsActive: true
            )
        }
    }

    // MARK: - Header

    private var hubHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text("Spielen")
                .font(AppTheme.Typography.largeTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
    }

    // MARK: - Hero Block

    /// Großer Spiele-Stand als visueller Anker. Keine Navigation, keine
    /// sekundären Aktionen in diesem Block — er ist die **Identität**
    /// des Screens: „Du hast X Spiele verdient."
    ///
    /// Wortschatz-Harmonisierung (User-Request „Footer-Icon-Semantik"):
    /// Footer-Badge, Hero-Label und Session-End nennen alle dasselbe
    /// „Spiele"-Konzept — `arcadeCredits` ist technisch weiterhin
    /// „Credits" (DB-Key), für den User aber durchgängig „Spiele".
    /// `gamesCost == 1` → Credits = Spiele, daher direkt übertragbar.
    private var heroBlock: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(hasCredits ? AppTheme.Colors.cta : AppTheme.Colors.textSecondary)

                Text("\(arcadeCredits)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(arcadeCredits == 1 ? "Spiel" : "Spiele")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer(minLength: 0)
            }

            // Meta-Zeile 1: Spiel → Leben Zuordnung. Ruhiges Icon-+-Text.
            heroMetaRow(
                systemImage: "heart.fill",
                tint: AppTheme.Colors.error.opacity(0.85),
                text: "1 Spiel = \(livesPerCredit) Leben"
            )

            // Meta-Zeile 2: Kontext — *warum* hat der User Spiele?
            heroMetaRow(
                systemImage: "sparkles",
                tint: AppTheme.Colors.cta,
                text: "Verdient durch Lernen"
            )
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.strong, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    @ViewBuilder
    private func heroMetaRow(systemImage: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Game-Start-Buttons (Phase 7.6+)
    //
    // Zwei gleichgroße Primary-CTAs, einer pro Spiel. Visuell
    // identisches Design — gleicher Button-Style, gleiche Höhe, gleiche
    // Icon-Größe —, nur Label + Icon differenzieren die Spiele.
    //
    // Elumi (Arcade) braucht Credits; ohne Credits wird der Button
    // deaktiviert + eine Hinweiszeile unter dem Block zeigt, wie der
    // User an Spiele kommt. Word Runner läuft ohne Credit-Verbrauch
    // (Dev-/Prototyp-Stand) und ist daher immer verfügbar.

    private var gameStartButtons: some View {
        VStack(spacing: 10) {
            // Elumi — Credit-gated
            gameStartButton(
                title: "Elumi starten",
                systemImage: "gamecontroller.fill",
                enabled: hasCredits,
                action: startGameTapped
            )

            // Word Runner — immer verfügbar (kein Credit-Verbrauch)
            gameStartButton(
                title: "Word Runner starten",
                systemImage: "figure.run",
                enabled: true,
                action: { showWordRunner = true }
            )

            // Status-/Hinweiszeile unter den beiden Buttons.
            if hasCredits {
                Text(ArcadeCreditSystem.gamesCost == 1
                    ? "1 Spiel wird für Elumi verwendet"
                    : "\(ArcadeCreditSystem.gamesCost) Spiele werden für Elumi verwendet")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Keine Spiele für Elumi — spiel eine Runde Lernen, um welche zu verdienen. Word Runner kannst du trotzdem starten.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Gemeinsamer Start-Button-Stil — beide Spiele nutzen identisches
    /// Layout (Icon + „… starten"-Label), damit die beiden Buttons
    /// visuell gleichwertig nebeneinander stehen.
    @ViewBuilder
    private func gameStartButton(
        title: String,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard enabled else { return }
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.5)
    }

    private func startGameTapped() {
        guard hasCredits else { return }
        feedbackPlayer.playLaunch()
        // Credit-Abzug **bevor** die Arcade präsentiert wird. Die Arcade
        // bekommt dadurch konsistenten Startzustand und kann im autoStart-
        // Modus ohne eigenen Gate sofort loslegen.
        arcadeCredits -= ArcadeCreditSystem.gamesCost
        // Navigation zur Arcade als echte Route mit autoStart=true —
        // Start-Overlay wird übersprungen, Immersive-Mode aktiviert sich
        // on-appear und lässt den globalen Footer sauber verschwinden.
        openArcade?(true)
    }

    // MARK: - Reward Explainer
    //
    // Kurze, überschaubare Vier-Punkt-Liste: „So verdienst du Spiele."
    // Wortschatz appweit konsistent („Spiele" statt „Credits" — siehe
    // Footer-Badge, Hero-Label, Session-End-Chips). Zahlen gespiegelt
    // aus den zentralen Konstanten (`GamificationConfig`).

    private var rewardExplainerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressSectionHeader(
                title: "So verdienst du Spiele",
                subtitle: nil
            )

            VStack(spacing: 0) {
                // Tagesaufgabe zuerst — direktester Weg zu einem Spiel,
                // passt zur „Retention-Engine".
                rewardExplainerRow(
                    systemImage: "sparkles",
                    tint: AppTheme.Colors.cta,
                    title: "Tagesaufgabe erledigen",
                    subtitle: "täglich +1 Spiel + XP"
                )
                rewardExplainerDivider
                rewardExplainerRow(
                    systemImage: "text.bubble.fill",
                    tint: AppTheme.Colors.elumiBlue,
                    title: "Lernen",
                    subtitle: "\(xpPerCredit) XP = 1 Spiel"
                )
                rewardExplainerDivider
                rewardExplainerRow(
                    systemImage: "flame.fill",
                    tint: Color(hex: "#FF9F40"),
                    title: "Streak halten",
                    subtitle: "Tage in Folge bringen Bonus-Spiele"
                )
                rewardExplainerDivider
                rewardExplainerRow(
                    systemImage: "star.fill",
                    tint: sectionStyle.accent,
                    title: "Level aufsteigen",
                    subtitle: GamificationConfig.creditsPerLevelUp == 1
                        ? "+1 Spiel pro neuem Level"
                        : "+\(GamificationConfig.creditsPerLevelUp) Spiele pro neuem Level"
                )
            }
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.subtle)
        }
    }

    @ViewBuilder
    private func rewardExplainerRow(systemImage: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var rewardExplainerDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.border.opacity(0.4))
            .frame(height: 1)
            .padding(.leading, 58)
    }

}
