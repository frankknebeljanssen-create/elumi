import Foundation
import SwiftUI

struct HomeView: View {
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let openScreen: (AppScreen) -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let openAccount: () -> Void
    let replaySplash: () -> Void
    @AppStorage(appDirectionKey) private var selectedDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0
    @AppStorage(appElumiXPKey) private var collectedXP = 0
    @AppStorage(appQuizHeartsKey) private var collectedWorms = 0
    // Zentraler Credit-Counter — wird von ProgressService/ProgressStore befüllt
    // und von der Gamification-Leiste sowie der Hearts-Übersicht gespiegelt.
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0
    private let sectionStyle: AppSectionStyle = .home
    @State private var pressedHomeScreen: AppScreen?
    @State private var isHomeNavigationLocked = false
    @ObservedObject private var progressStore = ProgressStore.shared
    // Profil als persönliche Identitätsquelle — ersetzt den alten direkten
    // @AppStorage-Zugriff auf `appFirstNameKey`. Der Store hält den Namen
    // als Single Source, Views konsumieren nur über Personalization.
    @ObservedObject private var profileStore = ProfileStore.shared
    // Tagesaufgabe — wird im Home-Progress-Board als Tagesstatus ausgegeben.
    // Keine Fallback-Initialisierung in der View: der Store kümmert sich
    // selbst um Generierung + Tag-Rollover.
    @ObservedObject private var dailyChallengeStore = DailyChallengeStore.shared

    private var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(shortVersion) (\(buildNumber))"
    }

    private var homeColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 14),
            GridItem(.flexible(), spacing: 14)
        ]
    }

    /// Legacy-Accessor, der jetzt aus dem ProfileStore speist. Bleibt als
    /// Property, damit bestehende Call-Sites (Begrüßung etc.) unverändert
    /// weiter funktionieren — der eigentliche Begrüßungstext kommt aber
    /// jetzt zentral aus `Personalization.homeGreeting(for:)`.
    private var displayName: String {
        profileStore.displayName
    }

    private var selectedDirection: Direction {
        Direction(rawValue: selectedDirectionRaw) ?? .frenchToGerman
    }

    private var directionToggle: some View {
        let isFrToDE = selectedDirection == .frenchToGerman
        return Button {
            feedbackPlayer.playToggle()
            selectedDirectionRaw = isFrToDE
                ? Direction.germanToFrench.rawValue
                : Direction.frenchToGerman.rawValue
        } label: {
            HStack(spacing: 10) {
                StraightFlagBadge(countryCode: isFrToDE ? "FR" : "DE", width: 36, height: 24, labelFontSize: 10)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                StraightFlagBadge(countryCode: isFrToDE ? "DE" : "FR", width: 36, height: 24, labelFontSize: 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var homeFooterClearance: CGFloat {
        usesGlobalChrome
            ? AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
            : AppTheme.Spacing.lg
    }

    private var homeVocabularyColor: Color { AppTheme.Colors.moduleVocabulary }
    private var homeArticlesColor: Color { AppTheme.Colors.moduleArticles }
    private var homeVerbsColor: Color { AppTheme.Colors.moduleVerbs }
    private var homeFlashcardsColor: Color { AppTheme.Colors.moduleFlashcards }
    private var homeQuizColor: Color { AppTheme.Colors.moduleQuiz }
    private var homeNomenColor: Color { AppTheme.Colors.moduleNomen }
    private var homeVerbformenColor: Color { AppTheme.Colors.moduleVerbforms }
    private var homeScanColor: Color { AppTheme.Colors.moduleScan }
    private var homeLexiconColor: Color { AppTheme.Colors.moduleLexicon }
    private var homeListsColor: Color { AppTheme.Colors.moduleLists }

    private var homeCreditsView: some View {
        Button {
            replaySplash()
        } label: {
            VStack(spacing: 3) {
                Text("© Frank Knebel-Janssen 2026")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(versionText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, homeFooterClearance)
    }

    private func openHomeScreen(_ screen: AppScreen) {
        guard !isHomeNavigationLocked else { return }

        isHomeNavigationLocked = true
        pressedHomeScreen = screen
        feedbackPlayer.playTabSwitch()
        openScreen(screen)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pressedHomeScreen = nil
            isHomeNavigationLocked = false
        }
    }

    @ViewBuilder
    private func homeArticleButton(
        screen: AppScreen,
        accentColor: Color,
        cardColor: Color,
        minHeight: CGFloat = AppLayout.homeCardHeight
    ) -> some View {
        Button {
            openHomeScreen(screen)
        } label: {
            VStack(spacing: 6) {
                Text("le/la/les")
                    .font(.system(size: 17, weight: .black, design: .serif))
                    // Dunklerer Grünton — analog zu „maison" (moduleNomen).
                    // Die Card-Fläche behält den helleren Artikel-Ton über cardColor.
                    .foregroundStyle(AppTheme.Colors.moduleNomen)
                    .frame(height: 32)

                Text("Artikel")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background {
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                            .fill(cardColor)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
            .opacity(pressedHomeScreen == screen ? 0.8 : 1)
            .scaleEffect(pressedHomeScreen == screen ? 0.965 : 1)
            .animation(.easeOut(duration: 0.12), value: pressedHomeScreen == screen)
        }
        .buttonStyle(.plain)
        .disabled(isHomeNavigationLocked)
    }

    @ViewBuilder
    private func homeSecondaryButton(
        screen: AppScreen,
        title: String,
        systemImage: String,
        accentColor: Color,
        minHeight: CGFloat? = nil
    ) -> some View {
        Button {
            openHomeScreen(screen)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight) // eigentliche Fläche
            .background {
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                            .fill(accentColor.opacity(0.12))
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
            .opacity(pressedHomeScreen == screen ? 0.8 : 1)
            .scaleEffect(pressedHomeScreen == screen ? 0.965 : 1)
            .animation(.easeOut(duration: 0.12), value: pressedHomeScreen == screen)
        }
        .buttonStyle(.plain)
        .disabled(isHomeNavigationLocked)
    }

    // MARK: - Home Progress Board (Mini-Dashboard, Phase-4 Home-Redesign)
    //
    // **Ein** zusammenhängendes Board — ersetzt die bisherige zweiteilige
    // Kombination aus Gamification-Bar + separatem Tagesbonus-Chip. Im Board:
    //
    //   obere Zeile: Streak (links als emotionaler Anker) · Level + Progress
    //                (Zentrum, flexibel) · XP · Credits (rechts, kompakt)
    //   Hairline-Divider (1 pt, niedrige Opacity — trennt, zerschneidet nicht)
    //   untere Zeile: Tagesstatus + optionaler Ziel-Hinweis („Noch X XP bis …")
    //                + dezenter Chevron als Hinweis auf Progress-Hub-Sprung
    //
    // Der ganze Block ist ein Button → tappt man ihn, landet man im Progress
    // Hub (`.hearts`). Kein lauter CTA — die Chevron-Ikonographie reicht,
    // damit „tap me for more" lesbar ist, ohne den Block als Button zu
    // schreien. Visuell derselbe Container wie die alte Balanced Bar (gleicher
    // Hintergrund, gleicher Akzent-Border) — so bleibt die Sprache zwischen
    // Home und Progress Hub konsistent.
    //
    // Die Sub-Segmente bleiben als separate Helper erhalten, damit sie später
    // im Game-Screen als kompakte Meta-Kopfzeile wiederverwendet werden können.

    private var homeProgressBoard: some View {
        let level = GamificationConfig.level(forXP: collectedXP)
        let levelProgress = GamificationConfig.progressTowardNextLevel(totalXP: collectedXP)
        let status = homeDailyStatus
        return Button {
            openHomeScreen(.hearts)
        } label: {
            VStack(spacing: 12) {
                // Obere Zeile — kompakte Primär-Werte
                HStack(spacing: 14) {
                    gamificationStreakSegment
                    gamificationSegmentDivider
                    gamificationLevelSegment(level: level, progress: levelProgress)
                    gamificationSegmentDivider
                    gamificationXPSegment
                    gamificationSegmentDivider
                    gamificationCreditsSegment
                }

                // Hairline — trennt oberen Werteblock vom Tagesstatus
                Rectangle()
                    .fill(AppTheme.Colors.textSecondary.opacity(0.14))
                    .frame(height: 1)

                // Untere Zeile — Tagesstatus + optionaler Ziel-Hinweis + Chevron
                HStack(spacing: 10) {
                    Image(systemName: status.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(status.tint)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if let goalHint = homeGoalHint {
                            Text(goalHint)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(gamificationBarBackground)
            .overlay(gamificationBarBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: AppTheme.Shadow.card.color.opacity(0.55),
                radius: 8,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fortschritt öffnen")
        .accessibilityHint("Öffnet den vollständigen Fortschrittsbereich.")
    }

    /// Tagesstatus-Paket basierend auf der heutigen Tagesaufgabe.
    /// Drei Zustände — genau **eine** klare Botschaft:
    ///  • `.open`       → „Tagesaufgabe: <Titel>"
    ///  • `.inProgress` → „<currentProgress> von <target> geschafft"
    ///  • `.done`       → „Tagesziel erreicht"
    private var homeDailyStatus: (icon: String, title: String, tint: Color) {
        guard let challenge = dailyChallengeStore.challenge else {
            // Solange der Store die Challenge noch nicht erzeugt hat
            // (Erststart-Race), zeigen wir neutralen Fallback.
            return (
                icon: "sparkles",
                title: "Tagesaufgabe wird vorbereitet …",
                tint: AppTheme.Colors.textSecondary
            )
        }
        switch challenge.status {
        case .open:
            return (
                icon: challenge.type.systemImage,
                title: "Tagesaufgabe: \(challenge.type.title)",
                tint: AppTheme.Colors.cta
            )
        case .inProgress:
            return (
                icon: challenge.type.systemImage,
                title: "\(challenge.currentProgress) von \(challenge.target) geschafft",
                tint: AppTheme.Colors.cta
            )
        case .done:
            return (
                icon: "checkmark.circle.fill",
                title: "Tagesziel erreicht",
                tint: AppTheme.Colors.success
            )
        }
    }

    /// Optionaler Ziel-Hinweis in der zweiten Zeile. Zeigt „Noch X XP bis
    /// <Tier>" — nutzt dieselbe Elumi-Tier-Benennung wie der Progress Hub,
    /// damit Home und Hub die gleiche Sprache sprechen. Max-Level → `nil`
    /// (Zeile verschwindet, Layout bleibt sauber).
    private var homeGoalHint: String? {
        guard let next = nextElumiLevelTier(for: collectedXP) else { return nil }
        let remaining = max(0, next.threshold - collectedXP)
        guard remaining > 0 else { return nil }
        return "Noch \(remaining) XP bis \(next.title)"
    }

    /// Streak-Segment (emotionaler Einstieg, etwas präsenter als die
    /// Rand-Bereiche). Icon + Zahl in enger, stabiler Gruppierung.
    private var gamificationStreakSegment: some View {
        HStack(spacing: 7) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: "#FF9F40"))
            Text("\(currentStreak)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(minWidth: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streak: \(currentStreak) Tage")
    }

    /// Level + Progress-Bar — das Zentrum der Leiste. Nimmt verfügbaren
    /// Restplatz via `frame(maxWidth: .infinity)`. Die Progress-Bar ist
    /// spürbar dicker als vorher (8pt) und wirkt als echtes
    /// Fortschrittselement, nicht als Dekoration.
    private func gamificationLevelSegment(level: Int, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Lv")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .tracking(0.8)
                Text("\(level)")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
            }
            gamificationProgressBar(progress: progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(level), \(Int(progress * 100))% zum nächsten Level")
    }

    /// Progress-Bar — dicker (8pt) und mit subtiler Innen-Tiefe durch einen
    /// 2-Stopp-Gradient auf dem Fortschrittsanteil. Kein Shine, keine Animation
    /// im Idle — wir wollen ruhige Wertigkeit, keine Arcade-Optik.
    private func gamificationProgressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.Colors.textSecondary.opacity(0.16))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.cta,
                                AppTheme.Colors.cta.opacity(0.82)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * progress))
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    /// XP-Segment — klare Zahl mit dezentem Mikro-Label drüber.
    /// Bewusst kompakter als Streak, damit die Hierarchie sitzt.
    private var gamificationXPSegment: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("XP")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("\(collectedXP)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(minWidth: 40, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collectedXP) XP")
    }

    /// Credits-Segment — klares Hexagon-Gitter-Icon (statt dem bisherigen
    /// Würmchen-Asset, das im Meta-Kontext nicht eindeutig als Credits
    /// lesbar war). Icon + Zahl kompakt, sichtbar, aber nicht dominant.
    private var gamificationCreditsSegment: some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.Colors.elumiBlue)
            Text("\(arcadeCredits)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(minWidth: 40, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(arcadeCredits) Credits")
    }

    /// Subtiler vertikaler Divider — 1pt breit, geringe Opacity, nicht über
    /// die volle Höhe des Containers. Soll trennen, aber nicht zerschneiden.
    private var gamificationSegmentDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.textSecondary.opacity(0.18))
            .frame(width: 1, height: 26)
    }

    /// Hintergrund: neutrale Surface mit dezentem vertikalem Highlight-Gradient,
    /// damit die Leiste eine Spur Tiefe bekommt — ohne Glanz oder Game-Look.
    private var gamificationBarBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
    }

    /// Dezenter Akzent-Border in CTA-Gelb mit sehr niedriger Opacity — hebt
    /// die Bar als wertiges UI-Element ab, ohne sie als Arcade-Chrom zu markieren.
    private var gamificationBarBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.Colors.cta.opacity(0.22), lineWidth: 1)
    }

    // dailyBonusChip entfernt — der Tagesstatus lebt jetzt direkt im
    // `homeProgressBoard` in der unteren Zeile. So gibt es auf Home kein
    // Doppel-Element mehr, keine Widersprüche zwischen Bar und Chip.

    @ViewBuilder
    private func homeTextIconButton(
        screen: AppScreen,
        title: String,
        textIcon: String,
        accentColor: Color,
        cardColor: Color,
        minHeight: CGFloat = AppLayout.homeCardHeight
    ) -> some View {
        Button {
            openHomeScreen(screen)
        } label: {
            VStack(spacing: 6) {
                Text(textIcon)
                    .font(.system(size: 17, weight: .black, design: .serif))
                    .foregroundStyle(accentColor)
                    .frame(height: 32)

                Text(title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background {
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                            .fill(cardColor)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
            .opacity(pressedHomeScreen == screen ? 0.8 : 1)
            .scaleEffect(pressedHomeScreen == screen ? 0.965 : 1)
            .animation(.easeOut(duration: 0.12), value: pressedHomeScreen == screen)
        }
        .buttonStyle(.plain)
        .disabled(isHomeNavigationLocked)
    }

    @ViewBuilder
    private func homeNavigationButton(
        screen: AppScreen,
        title: String,
        systemImage: String,
        accentColor: Color,
        cardColor: Color,
        iconSize: CGFloat = 28,
        minHeight: CGFloat = AppLayout.homeCardHeight
    ) -> some View {
        Button {
            openHomeScreen(screen)
        } label: {
            HomeActionButton(
                title: title,
                subtitle: "",
                systemImage: systemImage,
                accentColor: accentColor,
                cardColor: cardColor,
                iconSize: iconSize,
                minHeight: minHeight
            )
            .opacity(pressedHomeScreen == screen ? 0.8 : 1)
            .scaleEffect(pressedHomeScreen == screen ? 0.965 : 1)
            .animation(.easeOut(duration: 0.12), value: pressedHomeScreen == screen)
        }
        .buttonStyle(.plain)
        .disabled(isHomeNavigationLocked)
    }

    var body: some View {
        ZStack {
            // TOP BLOCK — absolute position at top
            VStack(alignment: .leading, spacing: 13) {
                // Zentrale Personalisierungs-Logik statt inline-String.
                // Fällt sauber auf „Salut !" zurück, falls kein Profil da ist.
                Text(Personalization.homeGreeting(for: profileStore.profile?.displayName))
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                // Home Progress Board — ein einziges kompaktes Mini-Dashboard
                // mit integriertem Tagesstatus. Tap führt in den Progress Hub.
                homeProgressBoard
                Text("Was möchtest du üben?")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding + AppTheme.Spacing.md + 0)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)

            // MIDDLE BLOCK — 7 modules + divider, absolute position
            VStack(spacing: 10) {
                homeNavigationButton(
                    screen: .flashcards(nil),
                    title: "Karteikarten",
                    systemImage: "square.stack.3d.up.fill",
                    accentColor: homeFlashcardsColor,
                    cardColor: homeFlashcardsColor.opacity(0.12),
                    // Flacher als die Standard-Hero-Cards, damit die
                    // Karte nicht mit dem Home-Progress-Board oben kollidiert.
                    minHeight: 82
                )
                // 6 Modul-Cards je 4pt flacher als Flashcards darüber —
                // so bekommt die Flashcards-Card optisch mehr Gewicht,
                // und der Home-Progress-Block darüber bekommt ein Stück
                // Luft zwischen sich und der obersten Modul-Reihe.
                HStack(spacing: 8) {
                    homeTextIconButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .nouns)),
                        title: "Nomen",
                        textIcon: "maison",
                        accentColor: homeNomenColor,
                        cardColor: homeNomenColor.opacity(0.12),
                        minHeight: 98
                    )
                    homeArticleButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .articles)),
                        accentColor: homeArticlesColor,
                        cardColor: homeArticlesColor.opacity(0.12),
                        minHeight: 98
                    )
                }
                HStack(spacing: 8) {
                    homeTextIconButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .verbs)),
                        title: "Verben",
                        textIcon: "aller",
                        accentColor: homeVerbsColor,
                        cardColor: homeVerbsColor.opacity(0.12),
                        minHeight: 98
                    )
                    homeNavigationButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .verbforms)),
                        title: "Verbformen",
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        accentColor: homeVerbformenColor,
                        cardColor: homeVerbformenColor.opacity(0.12),
                        iconSize: 22,
                        minHeight: 98
                    )
                }
                HStack(spacing: 8) {
                    homeNavigationButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .vocabulary)),
                        title: "Vokabeln",
                        systemImage: "character.book.closed.fill",
                        accentColor: homeVocabularyColor,
                        cardColor: homeVocabularyColor.opacity(0.12),
                        minHeight: 98
                    )
                    homeNavigationButton(
                        screen: .quiz(nil),
                        title: "Quiz",
                        systemImage: "lightbulb.fill",
                        accentColor: homeQuizColor,
                        cardColor: homeQuizColor.opacity(0.12),
                        minHeight: 98
                    )
                }
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 1)
                    .padding(.vertical, 4)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            // Middle-Block startet tiefer, damit das taller gewordene Home-
            // Progress-Board (Bar + Tagesstatus in einer Karte) Luft hat
            // und Flashcards klar unterhalb sitzt. Der freigewordene Platz
            // aus den 4-pt-flacheren Modul-Cards wird hier investiert.
            .padding(.top, AppLayout.contentTopPadding + AppTheme.Spacing.md + 177)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)

            // FLAGS (links) + LISTEN (rechts) — in einer Zeile am unteren Rand.
            // Listen-Button: echte Fläche minHeight = 90 (+50% ggü. ~60 Standard).
            // HStack .center → Flaggen vertikal auf Button-Mitte ausgerichtet.
            HStack(alignment: .center, spacing: 10) {
                directionToggle
                    .frame(maxWidth: .infinity)
                homeSecondaryButton(
                    screen: .lists(nil),
                    title: "Listen",
                    systemImage: "list.bullet.rectangle.fill",
                    accentColor: homeListsColor,
                    // Hero-Cards sind AppLayout.homeCardHeight (102pt). Listen 10pt flacher
                    // als die reine Hälfte → kompakter, weniger dominant.
                    minHeight: (AppLayout.homeCardHeight / 2) - 10
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.bottom, homeFooterClearance + 2) // Zeile 10pt tiefer als vorher
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onInfo: openInfo, onAccount: openAccount)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: {},
                onFavorite: nil,
                onScan: nil,
                onSettings: openSettings,
                onScanCamera: { openHomeScreen(.scan) },
                isSettingsActive: false
            )
        }
    }
}
