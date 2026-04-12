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
        HStack(spacing: 8) {
            directionButton(
                direction: .frenchToGerman,
                leftFlag: "FR",
                rightFlag: "DE"
            )
            directionButton(
                direction: .germanToFrench,
                leftFlag: "DE",
                rightFlag: "FR"
            )
        }
    }

    private func directionButton(direction: Direction, leftFlag: String, rightFlag: String) -> some View {
        let isSelected = selectedDirection == direction
        return Button {
            feedbackPlayer.playToggle()
            selectedDirectionRaw = direction.rawValue
        } label: {
            HStack(spacing: 10) {
                StraightFlagBadge(countryCode: leftFlag, width: 36, height: 24, labelFontSize: 10)
                    .opacity(isSelected ? 1 : 0.25)
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .opacity(isSelected ? 1 : 0.25)
                StraightFlagBadge(countryCode: rightFlag, width: 36, height: 24, labelFontSize: 10)
                    .opacity(isSelected ? 1 : 0.25)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color, radius: AppTheme.Shadow.card.radius, x: 0, y: 6)
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
                HStack(spacing: 2) {
                    Text("le")
                        .font(.system(size: 17, weight: .black, design: .serif))
                    Text("la")
                        .font(.system(size: 17, weight: .black, design: .serif))
                }
                .foregroundStyle(accentColor)
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
        accentColor: Color
    ) -> some View {
        Button {
            openHomeScreen(screen)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                            .fill(accentColor.opacity(0.06))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .opacity(pressedHomeScreen == screen ? 0.8 : 1)
            .scaleEffect(pressedHomeScreen == screen ? 0.97 : 1)
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
        cardColor: Color
    ) -> some View {
        Button {
            openHomeScreen(screen)
        } label: {
            HomeActionButton(
                title: title,
                subtitle: "",
                systemImage: systemImage,
                accentColor: accentColor,
                cardColor: cardColor
            )
            .opacity(pressedHomeScreen == screen ? 0.8 : 1)
            .scaleEffect(pressedHomeScreen == screen ? 0.965 : 1)
            .animation(.easeOut(duration: 0.12), value: pressedHomeScreen == screen)
        }
        .buttonStyle(.plain)
        .disabled(isHomeNavigationLocked)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Greeting — fixed at top
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Salut \(displayName) !")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Was möchtest du heute machen?")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 28)

            // Hero cards — fixed position
            VStack(spacing: 10) {
                // Karteikarten — full width hero
                homeNavigationButton(
                    screen: .flashcards(nil),
                    title: "Karteikarten",
                    systemImage: "square.stack.3d.up.fill",
                    accentColor: homeFlashcardsColor,
                    cardColor: homeFlashcardsColor.opacity(0.12)
                )

                // Artikel + Verben
                HStack(spacing: 8) {
                    homeArticleButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .articles)),
                        accentColor: homeArticlesColor,
                        cardColor: homeArticlesColor.opacity(0.12)
                    )

                    homeNavigationButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .verbs)),
                        title: "Verben",
                        systemImage: "arrow.triangle.branch",
                        accentColor: homeVerbsColor,
                        cardColor: homeVerbsColor.opacity(0.12)
                    )
                }

                // Vokabeln + Quiz
                HStack(spacing: 8) {
                    homeNavigationButton(
                        screen: .train(TrainingLaunchContext(preferredMode: .vocabulary)),
                        title: "Vokabeln",
                        systemImage: "character.book.closed.fill",
                        accentColor: homeVocabularyColor,
                        cardColor: homeVocabularyColor.opacity(0.12)
                    )

                    homeNavigationButton(
                        screen: .quiz,
                        title: "Quiz",
                        systemImage: "lightbulb.fill",
                        accentColor: homeQuizColor,
                        cardColor: homeQuizColor.opacity(0.12)
                    )
                }
            }
            .padding(.top, 105)

            // Bottom section — pinned to bottom
            VStack(spacing: 10) {
                directionToggle

                HStack(spacing: 10) {
                    homeSecondaryButton(
                        screen: .lists(nil),
                        title: "Listen",
                        systemImage: "list.bullet.rectangle.fill",
                        accentColor: homeListsColor
                    )

                    homeSecondaryButton(
                        screen: .scan,
                        title: "Scan",
                        systemImage: "camera.viewfinder",
                        accentColor: homeScanColor
                    )
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 10)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, homeFooterClearance)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                isSettingsActive: false
            )
        }
    }
}
