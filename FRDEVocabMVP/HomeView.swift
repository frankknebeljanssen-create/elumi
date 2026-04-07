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

    private var homeFooterClearance: CGFloat {
        usesGlobalChrome
            ? AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
            : AppTheme.Spacing.lg
    }

    private var homeLearningTrainColor: Color { AppTheme.Colors.elumiPinkDeep }
    private var homeLearningFlashcardsColor: Color { AppTheme.Colors.elumiRoseDeep }
    private var homeLearningQuizColor: Color { Color(hex: "#E0648D") }

    private var homeKnowledgeScanColor: Color { AppTheme.Colors.success }
    private var homeKnowledgeLexiconColor: Color { AppTheme.Colors.warning }
    private var homeKnowledgeListsColor: Color { Color(hex: "#57B8C9") }

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            openScreen(screen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                pressedHomeScreen = nil
                isHomeNavigationLocked = false
            }
        }
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
        VStack(spacing: 0) {
            Spacer(minLength: AppTheme.Spacing.xs)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Salut \(displayName) !")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Was möchtest du heute machen?")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.bottom, AppTheme.Spacing.sm)

                LazyVGrid(columns: homeColumns, spacing: AppTheme.Spacing.sm) {
                    homeNavigationButton(
                        screen: .train(nil),
                        title: "Trainieren",
                        systemImage: "mic.circle.fill",
                        accentColor: homeLearningTrainColor,
                        cardColor: homeLearningTrainColor.opacity(0.12)
                    )

                    homeNavigationButton(
                        screen: .flashcards(nil),
                        title: "Karteikarten",
                        systemImage: "square.stack.3d.up.fill",
                        accentColor: homeLearningFlashcardsColor,
                        cardColor: homeLearningFlashcardsColor.opacity(0.12)
                    )

                    homeNavigationButton(
                        screen: .quiz,
                        title: "Quiz",
                        systemImage: "lightbulb.fill",
                        accentColor: homeLearningQuizColor,
                        cardColor: homeLearningQuizColor.opacity(0.12)
                    )

                    homeNavigationButton(
                        screen: .scan,
                        title: "Scan",
                        systemImage: "text.viewfinder",
                        accentColor: homeKnowledgeScanColor,
                        cardColor: homeKnowledgeScanColor.opacity(0.12)
                    )

                    homeNavigationButton(
                        screen: .lexicon,
                        title: "Wörterbuch",
                        systemImage: "book.closed.fill",
                        accentColor: homeKnowledgeLexiconColor,
                        cardColor: homeKnowledgeLexiconColor.opacity(0.12)
                    )

                    homeNavigationButton(
                        screen: .lists(nil),
                        title: "Listen",
                        systemImage: "list.bullet.rectangle.fill",
                        accentColor: homeKnowledgeListsColor,
                        cardColor: homeKnowledgeListsColor.opacity(0.12)
                    )
                }
            }

            Spacer(minLength: AppTheme.Spacing.md)

            homeCreditsView
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppTheme.Spacing.xs)
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
