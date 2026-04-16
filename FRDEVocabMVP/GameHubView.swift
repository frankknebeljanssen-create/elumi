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
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0
    @ObservedObject private var progressStore = ProgressStore.shared
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void

    /// Zeigt den Arcade-FullScreenCover an, wenn `true`. Wird vom CTA
    /// gesetzt, nachdem der Credit-Abzug erfolgt ist (siehe `startGameTapped`).
    @State private var isPresentingArcade = false

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
                ctaBlock
                rewardExplainerBlock
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
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
        .fullScreenCover(isPresented: $isPresentingArcade) {
            // Credit-Abzug ist beim CTA-Tap schon passiert → autoStart = true,
            // damit das Arcade-Overlay übersprungen und direkt gespielt wird.
            ElumiArcadeGameView(feedbackPlayer: feedbackPlayer, autoStart: true)
        }
    }

    // MARK: - Header

    private var hubHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text("Spielen")
                .font(AppTheme.Typography.largeTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Setze deine Credits ein.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    // MARK: - Hero Block

    /// Großer Credit-Stand als visueller Anker. Keine Navigation, keine
    /// sekundären Aktionen in diesem Block — er ist die **Identität**
    /// des Screens: „Du hast X Credits verdient."
    private var heroBlock: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(hasCredits ? AppTheme.Colors.cta : AppTheme.Colors.textSecondary)

                Text("\(arcadeCredits)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(arcadeCredits == 1 ? "Credit" : "Credits")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer(minLength: 0)
            }

            // Meta-Zeile 1: Credit → Leben Zuordnung. Ruhiges Icon-+-Text.
            heroMetaRow(
                systemImage: "heart.fill",
                tint: AppTheme.Colors.error.opacity(0.85),
                text: "1 Credit = \(livesPerCredit) Leben"
            )

            // Meta-Zeile 2: Kontext — *warum* hat der User Credits?
            heroMetaRow(
                systemImage: "sparkles",
                tint: AppTheme.Colors.cta,
                text: "Verdient durch Lernen"
            )
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(sectionStyle, intensity: 0.16, cornerRadius: AppLayout.largeCardCornerRadius)
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

    // MARK: - CTA Block
    //
    // **Ein** Button — keine konkurrierenden Aktionen, kein Sekundär-CTA.
    // Kontext-sensitiv: mit Credits = „Spiel starten"; ohne Credits wird
    // der Button zum Lern-Einstieg, damit der User nicht auf einem toten
    // Screen sitzt.

    private var ctaBlock: some View {
        VStack(spacing: 8) {
            if hasCredits {
                Button {
                    startGameTapped()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                        Text("Spiel starten")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 60)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

                Text("\(ArcadeCreditSystem.gamesCost) Credit wird verwendet")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                Button {
                    // Empty-State-CTA führt zurück in den Lernbereich.
                    // Dismiss Navigation-Stack zurück zu Home — der User
                    // startet dort die nächste Lernsession und verdient
                    // sich die ersten Credits.
                    feedbackPlayer.playTabSwitch()
                    goHome()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Lerne, um Credits zu verdienen")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 60)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

                Text("Credits entstehen beim Lernen.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private func startGameTapped() {
        guard hasCredits else { return }
        feedbackPlayer.playLaunch()
        // Credit-Abzug **bevor** die Arcade präsentiert wird. Die Arcade
        // bekommt dadurch konsistenten Startzustand und kann im autoStart-
        // Modus ohne eigenen Gate sofort loslegen.
        arcadeCredits -= ArcadeCreditSystem.gamesCost
        // Instant-Switch ohne Slide-from-bottom — konsistent mit
        // Footer-Navigation und AppNavigationCoordinator.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isPresentingArcade = true
        }
    }

    // MARK: - Reward Explainer
    //
    // Kurze, überschaubare Drei-Punkt-Liste: „So kommst du an Credits."
    // Bewusst keine Zahlen-Tabelle, keine ausführliche Formel-Erklärung —
    // das bleibt dem Progress Hub / Session End vorbehalten.

    private var rewardExplainerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressSectionHeader(
                title: "So verdienst du Credits",
                subtitle: nil
            )

            VStack(spacing: 0) {
                // Tagesaufgabe zuerst — direktester Weg zu Credits,
                // passt zur „Retention-Engine" aus Phase 5.
                rewardExplainerRow(
                    systemImage: "sparkles",
                    tint: AppTheme.Colors.cta,
                    title: "Tagesaufgabe erledigen",
                    subtitle: "täglich +1 Credit + XP-Reward"
                )
                rewardExplainerDivider
                rewardExplainerRow(
                    systemImage: "text.bubble.fill",
                    tint: AppTheme.Colors.elumiBlue,
                    title: "Lernen",
                    subtitle: "\(xpPerCredit) XP = 1 Credit"
                )
                rewardExplainerDivider
                rewardExplainerRow(
                    systemImage: "flame.fill",
                    tint: Color(hex: "#FF9F40"),
                    title: "Streak halten",
                    subtitle: "Tage in Folge bringen Bonus-Credits"
                )
                rewardExplainerDivider
                rewardExplainerRow(
                    systemImage: "star.fill",
                    tint: sectionStyle.accent,
                    title: "Level aufsteigen",
                    subtitle: "+\(GamificationConfig.creditsPerLevelUp) Credits pro neuem Level"
                )
            }
            .appCardBackground(sectionStyle, intensity: 0.07)
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
