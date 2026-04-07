import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var runtime = AppRuntimeContainer()
    @StateObject private var navigation = AppNavigationCoordinator()
    @AppStorage(appDirectionKey) private var selectedDirectionRaw = Direction.frenchToGerman.rawValue

    private var navigationPathBinding: Binding<[AppScreen]> {
        Binding(
            get: { navigation.navigationPath },
            set: { navigation.navigationPath = $0 }
        )
    }

    private var isSettingsScreenActive: Bool {
        navigation.isSettingsScreenActive
    }

    private var isHeartsScreenActive: Bool {
        navigation.isHeartsScreenActive
    }

    private var isScanScreenActive: Bool {
        navigation.isScanScreenActive
    }

    private func openInfoScreen() {
        navigation.openInfoScreen()
    }

    private func openSettingsScreen() {
        navigation.openSettingsScreen()
    }

    private func openScanScreen() {
        navigation.openScanScreen()
    }

    private func openHeartsScreen() {
        navigation.openHeartsScreen()
    }

    @MainActor
    private func openScreenWhenReady(_ screen: AppScreen) {
        navigation.openScreenWhenReady(screen) {
            if case .flashcards = screen {
                startFlashcardsOpenTiming("navigation_request")
            }
        }
    }

    var body: some View {
        ZStack {
            if let feedbackPlayer = runtime.feedbackPlayer {
                NavigationStack(path: navigationPathBinding) {
                    HomeView(
                        feedbackPlayer: feedbackPlayer,
                        openScreen: { openScreenWhenReady($0) },
                        openSettings: { openSettingsScreen() },
                        openInfo: { openInfoScreen() },
                        openAccount: { navigation.navigationPath.append(.account) },
                        replaySplash: { replaySplash() }
                    )
                    .transition(.opacity)
                    .navigationDestination(for: AppScreen.self) { screen in
                        AppDestinationHost(
                            screen: screen,
                            runtime: runtime,
                            feedbackPlayer: feedbackPlayer,
                            goHome: { navigation.goHome() },
                            openSettings: { openSettingsScreen() },
                            openInfo: { openInfoScreen() },
                            navigate: { nextScreen in navigation.navigationPath.append(nextScreen) },
                            markFlashcardsOpenTiming: markFlashcardsOpenTiming
                        )
                    }
                    .onAppear {
                        let currentDirection = Direction(rawValue: selectedDirectionRaw) ?? .frenchToGerman
                        let sanitizedDirection = currentDirection.sanitizedForFrenchOnly
                        if sanitizedDirection != currentDirection {
                            selectedDirectionRaw = sanitizedDirection.rawValue
                        }
                    }
                }
                .scaleEffect(navigation.shouldShowSplashOverlay ? 0.998 : 1)
                .blur(radius: navigation.shouldShowSplashOverlay ? 28 : 0)
                .saturation(navigation.shouldShowSplashOverlay ? 0.6 : 1)
                .brightness(navigation.shouldShowSplashOverlay ? -0.02 : 0)
                .opacity(navigation.shouldShowSplashOverlay ? 0.74 : 1)
                .overlay {
                    UnderwaterRevealOverlay(progress: navigation.shouldShowSplashOverlay ? 1 : 0)
                }
                .animation(
                    navigation.shouldAnimateSplashDismissal ? .easeOut(duration: 1.05) : nil,
                    value: navigation.shouldShowSplashOverlay
                )
                .overlay(alignment: .bottom) {
                    if navigation.shouldShowGlobalChrome {
                        AppBottomBar(
                            feedbackPlayer: feedbackPlayer,
                            onHome: { navigation.goHome() },
                            onFavorite: isHeartsScreenActive ? nil : { openHeartsScreen() },
                            onScan: isScanScreenActive ? nil : { openScanScreen() },
                            onSettings: isSettingsScreenActive ? nil : { openSettingsScreen() },
                            isHeartsActive: isHeartsScreenActive,
                            isScanActive: isScanScreenActive,
                            isSettingsActive: isSettingsScreenActive
                        )
                    }
                }
                .environment(\.appOpenAccountAction, {
                    navigation.navigationPath.append(.account)
                })
                .environment(\.appOpenScanAction, {
                    openScanScreen()
                })
                .environment(\.appUsesGlobalChrome, navigation.shouldShowGlobalChrome)
            } else {
                AppTheme.Colors.background
                    .ignoresSafeArea()
            }

            if navigation.shouldShowSplashOverlay {
                SplashView { isImmediateSkip in
                    completeSplashAndEnsureMenuReady(immediate: isImmediateSkip)
                }
                .id(navigation.splashReplayID)
                .transition(.opacity)
            }
        }
        .task {
            runtime.bootstrapDependenciesIfNeeded()
        }
    }

    @MainActor
    private func completeSplashAndEnsureMenuReady(immediate: Bool) {
        runtime.ensureHomeShellDependenciesReady()
        runtime.bootstrapDependenciesIfNeeded()
        navigation.completeSplashAndEnsureMenuReady(immediate: immediate)
    }

    @MainActor
    private func replaySplash() {
        navigation.replaySplash()
    }
}
