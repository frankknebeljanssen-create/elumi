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
                ctaBlock
                rewardExplainerBlock
                // `wordRunnerDevShortcut` war kurz `#if DEBUG`-gated,
                // aber dieses Projekt setzt `SWIFT_ACTIVE_COMPILATION_
                // CONDITIONS` nirgendwo → die Swift-DEBUG-Flag greift
                // nicht, Karte wäre unsichtbar. Bis die Flag im Projekt
                // eingetragen ist, bleibt die Karte immer sichtbar —
                // Label „DEBUG · Phase 2/3 Prototype" macht den Status
                // am Sprachlabel kenntlich.
                wordRunnerDevShortcut
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

                Text(ArcadeCreditSystem.gamesCost == 1
                    ? "1 Spiel wird verwendet"
                    : "\(ArcadeCreditSystem.gamesCost) Spiele werden verwendet")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                Button {
                    // Empty-State-CTA führt zurück in den Lernbereich.
                    // Wortlaut nach Game-Loop-Spec: „Verdiene Spiele
                    // durch Lernen" — klares Signal, warum man den
                    // Game Hub gerade verlässt.
                    feedbackPlayer.playTabSwitch()
                    goHome()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Verdiene Spiele durch Lernen")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 60)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

                Text("Du hast keine Spiele — spiel eine Runde Lernen, um welche zu verdienen.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
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

    // MARK: - Word Runner Dev-Shortcut
    //
    // Sichtbar unten auf dem Hub, deutlich als Debug markiert.
    // Verbraucht **keine** Credits, hängt nicht an Session/Progress —
    // reiner Tester-Zugang, damit wir den Runner-Prototyp ohne
    // Credit-Farming anspielen können. Wird in Phase 4+ durch die
    // reguläre Spiel-Auswahl ersetzt.
    private var wordRunnerDevShortcut: some View {
        Button {
            showWordRunner = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(AppTheme.Colors.elumiPink.opacity(0.18))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Word Runner")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("DEBUG · Phase 2/3 Prototype")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.subtle)
    }
}
