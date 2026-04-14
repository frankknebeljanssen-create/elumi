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
    @AppStorage(appFirstNameKey) private var firstName = "Frank"
    @AppStorage(appDirectionKey) private var selectedDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0
    @AppStorage(appElumiXPKey) private var collectedXP = 0
    @AppStorage(appQuizHeartsKey) private var collectedWorms = 0
    private let sectionStyle: AppSectionStyle = .home
    @State private var pressedHomeScreen: AppScreen?
    @State private var isHomeNavigationLocked = false

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

    private var displayName: String {
        let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Frank" : trimmed
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
        cardColor: Color
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
            .frame(maxWidth: .infinity, minHeight: AppLayout.homeCardHeight)
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

    // MARK: - Gamification Bar

    private var gamificationBar: some View {
        Button {
            openHomeScreen(.hearts)
        } label: {
            HStack(spacing: 10) {
                // Streak
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "#FF9F40"))
                    Text("\(currentStreak)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }

                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 14)

                // XP
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "#FFC83D"))
                    Text("\(collectedXP)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }

                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 14)

                // Würmchen (collected worms)
                HStack(spacing: 4) {
                    Image("ElumiWuermchen")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                    Text("\(collectedWorms)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "#FF9F40").opacity(0.08))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "#FF9F40").opacity(0.4), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func homeTextIconButton(
        screen: AppScreen,
        title: String,
        textIcon: String,
        accentColor: Color,
        cardColor: Color
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
            .frame(maxWidth: .infinity, minHeight: AppLayout.homeCardHeight)
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
        iconSize: CGFloat = 28
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
                iconSize: iconSize
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
                Text("Salut \(displayName) !")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                gamificationBar
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
                    cardColor: homeFlashcardsColor.opacity(0.12)
                )
                HStack(spacing: 8) {
                    homeTextIconButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .nouns)),
                        title: "Nomen",
                        textIcon: "maison",
                        accentColor: homeNomenColor,
                        cardColor: homeNomenColor.opacity(0.12)
                    )
                    homeArticleButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .articles)),
                        accentColor: homeArticlesColor,
                        cardColor: homeArticlesColor.opacity(0.12)
                    )
                }
                HStack(spacing: 8) {
                    homeTextIconButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .verbs)),
                        title: "Verben",
                        textIcon: "aller",
                        accentColor: homeVerbsColor,
                        cardColor: homeVerbsColor.opacity(0.12)
                    )
                    homeNavigationButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .verbforms)),
                        title: "Verbformen",
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        accentColor: homeVerbformenColor,
                        cardColor: homeVerbformenColor.opacity(0.12),
                        iconSize: 22
                    )
                }
                HStack(spacing: 8) {
                    homeNavigationButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .vocabulary)),
                        title: "Vokabeln",
                        systemImage: "character.book.closed.fill",
                        accentColor: homeVocabularyColor,
                        cardColor: homeVocabularyColor.opacity(0.12)
                    )
                    homeNavigationButton(
                        screen: .quiz(nil),
                        title: "Quiz",
                        systemImage: "lightbulb.fill",
                        accentColor: homeQuizColor,
                        cardColor: homeQuizColor.opacity(0.12)
                    )
                }
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 1)
                    .padding(.vertical, 4)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding + AppTheme.Spacing.md + 145)
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
