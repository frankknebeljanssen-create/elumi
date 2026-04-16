import Foundation
import SwiftUI

@MainActor
final class AppNavigationCoordinator: ObservableObject {
    static let isSplashTemporarilyDisabled = false

    @Published var didCompleteSplashAnimation: Bool
    @Published var splashReplayID = UUID()
    @Published var navigationPath: [AppScreen] = []
    @Published var shouldAnimateSplashDismissal = true

    init() {
        didCompleteSplashAnimation = Self.isSplashTemporarilyDisabled
    }

    var currentScreen: AppScreen? {
        navigationPath.last
    }

    var shouldShowSplashOverlay: Bool {
        !Self.isSplashTemporarilyDisabled && !didCompleteSplashAnimation
    }

    var shouldShowGlobalChrome: Bool {
        !shouldShowSplashOverlay
    }

    var isSettingsScreenActive: Bool {
        if case .settings = currentScreen {
            return true
        }
        return false
    }

    var isHeartsScreenActive: Bool {
        if case .hearts = currentScreen {
            return true
        }
        return false
    }

    var isGameHubScreenActive: Bool {
        if case .gameHub = currentScreen {
            return true
        }
        return false
    }

    var isScanScreenActive: Bool {
        if case .scan = currentScreen {
            return true
        }
        return false
    }

    /// Führt eine Path-Mutation ohne Slide-Animation aus. Zentraler Helper
    /// für **alle** Navigation — die App soll sich schnell anfühlen,
    /// kein Rechts-von-Slide, kein Fade, kein Micro-Delay.
    private func navigateInstant(_ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    func goHome() {
        navigateInstant { navigationPath.removeAll() }
    }

    func openInfoScreen() {
        guard currentScreen != .info else { return }
        navigateInstant { navigationPath.append(.info) }
    }

    func openSettingsScreen() {
        guard currentScreen != .settings else { return }
        navigateInstant { navigationPath.append(.settings) }
    }

    func openScanScreen() {
        guard currentScreen != .scan else { return }
        navigateInstant { navigationPath.append(.scan) }
    }

    func openHeartsScreen() {
        guard currentScreen != .hearts else { return }
        navigateInstant { navigationPath.append(.hearts) }
    }

    func openGameHubScreen() {
        guard currentScreen != .gameHub else { return }
        navigateInstant { navigationPath.append(.gameHub) }
    }

    func openLexiconScreen() {
        guard currentScreen != .lexicon else { return }
        navigateInstant { navigationPath.append(.lexicon) }
    }

    var isLexiconScreenActive: Bool {
        if case .lexicon = currentScreen { return true }
        return false
    }

    func openScreenWhenReady(_ screen: AppScreen, onWillNavigate: (() -> Void)? = nil) {
        guard currentScreen != screen else { return }
        onWillNavigate?()
        navigateInstant { navigationPath.append(screen) }
    }

    func completeSplashAndEnsureMenuReady(immediate: Bool) {
        guard !Self.isSplashTemporarilyDisabled else {
            didCompleteSplashAnimation = true
            shouldAnimateSplashDismissal = false
            return
        }

        shouldAnimateSplashDismissal = !immediate

        if immediate {
            didCompleteSplashAnimation = true
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                didCompleteSplashAnimation = true
            }
        }
    }

    func replaySplash() {
        guard !Self.isSplashTemporarilyDisabled else { return }
        splashReplayID = UUID()
        shouldAnimateSplashDismissal = true
        withAnimation(.easeInOut(duration: 0.25)) {
            didCompleteSplashAnimation = false
        }
    }
}
