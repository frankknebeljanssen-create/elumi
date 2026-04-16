import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var runtime = AppRuntimeContainer()
    @StateObject private var navigation = AppNavigationCoordinator()
    @ObservedObject private var profileStore = ProfileStore.shared
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
        runtime.feedbackPlayer?.playTabSwitch()
        navigation.openSettingsScreen()
    }

    private func openScanScreen() {
        runtime.feedbackPlayer?.playTabSwitch()
        navigation.openScanScreen()
    }

    private func openLexiconScreen() {
        runtime.feedbackPlayer?.playTabSwitch()
        navigation.openLexiconScreen()
    }

    private func openHeartsScreen() {
        runtime.feedbackPlayer?.playTabSwitch()
        navigation.openHeartsScreen()
    }

    private func openGameHubScreen() {
        runtime.feedbackPlayer?.playTabSwitch()
        navigation.openGameHubScreen()
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
                // Onboarding-Gate: beim allerersten Start (oder nach
                // Reset) zeigen wir den leichten Willkommens-Flow
                // *statt* der NavigationStack-Home. Der Flag flippt
                // atomar via ProfileStore.completeOnboarding, SwiftUI
                // rendert dann die Home-Hierarchie.
                if !profileStore.hasCompletedOnboarding {
                    OnboardingView(
                        profileStore: profileStore,
                        feedbackPlayer: feedbackPlayer
                    )
                    .transition(.opacity)
                } else {
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
                    navigation.shouldAnimateSplashDismissal ? .easeOut(duration: 0.45) : nil,
                    value: navigation.shouldShowSplashOverlay
                )
                .overlay(alignment: .bottom) {
                    if navigation.shouldShowGlobalChrome {
                        AppBottomBar(
                            feedbackPlayer: feedbackPlayer,
                            onHome: { runtime.feedbackPlayer?.playTabSwitch(); navigation.goHome() },
                            // Footer-Snack-Button (ehem. „Sammlung") öffnet jetzt den
                            // Game Hub. Der Progress Hub bleibt über das Home-Board
                            // erreichbar — klare Trennung „Footer = Spielen",
                            // „Home-Board = Fortschritt".
                            onFavorite: navigation.isGameHubScreenActive ? nil : { openGameHubScreen() },
                            onScan: navigation.isLexiconScreenActive ? nil : { openLexiconScreen() },
                            onSettings: isSettingsScreenActive ? nil : { openSettingsScreen() },
                            isHeartsActive: navigation.isGameHubScreenActive,
                            isScanActive: navigation.isLexiconScreenActive,
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
                } // ← schließt Onboarding-Gate-else (NavigationStack-Branch)
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
        .onAppear {
            runtime.bootstrapDependenciesIfNeeded()
            runtime.feedbackPlayer?.playAppStart()
            // Letzte-Nutzung-Zeitstempel pflegen, sobald ein Profil da ist.
            // Robust gegen fehlendes Profil (Onboarding läuft noch) —
            // touchLastActive() ist dann ein No-Op.
            if profileStore.hasCompletedOnboarding {
                profileStore.touchLastActive()
            }
        }
    }

    @MainActor
    private func completeSplashAndEnsureMenuReady(immediate: Bool) {
        runtime.ensureHomeShellDependenciesReady()
        runtime.bootstrapDependenciesIfNeeded()
        navigation.completeSplashAndEnsureMenuReady(immediate: immediate)
        // App start sound moved to .onAppear below
    }

    @MainActor
    private func replaySplash() {
        navigation.replaySplash()
    }
}
