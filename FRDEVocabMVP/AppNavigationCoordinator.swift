import Foundation
import SwiftUI

@MainActor
final class AppNavigationCoordinator: ObservableObject {
    static let isSplashTemporarilyDisabled = false

    @Published var didCompleteSplashAnimation: Bool
    @Published var splashReplayID = UUID()
    @Published var navigationPath: [AppScreen] = []
    @Published var shouldAnimateSplashDismissal = true
    /// Sichtbar-ausblenden des globalen Footers, wenn die Arcade tatsächlich
    /// gespielt wird. Beim Start-Overlay ist der Footer bewusst weiter sichtbar,
    /// damit User bei Fehltap direkt zum nächsten Footer-Button wechseln kann.
    @Published var isImmersiveArcadeActive = false

    /// **Léa-Chat MVP — Polish (2026-05-10)** — Footer-Hide während das
    /// System-Keyboard im ChatView sichtbar ist. Erspart visuelle Kollision
    /// zwischen Tab-Bar und Chat-Input-Bar (WhatsApp-/iMessage-Look) und
    /// reklamiert die Footer-Fläche, sodass der Chat-Input ohne Doppel-
    /// Padding direkt über der Keyboard-Kante sitzt.
    ///
    /// Wird ausschließlich von `ChatView` gesetzt (via NotificationCenter-
    /// Listener auf `keyboardWillShow/Hide`). Andere Screens lassen den
    /// Wert unangetastet — defaults bleibt false.
    @Published var isChatKeyboardActive = false

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
        !shouldShowSplashOverlay && !isImmersiveArcadeActive && !isChatKeyboardActive
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

    /// **Hot-Fix 2026-05-02 — Chain-State-Cleanup auf goHome.**
    /// Vorher: `goHome()` poppte nur den NavigationPath, ließ aber
    /// `TrainingChainStore.shared.currentChain` aktiv. Folge: nach einem
    /// abgebrochenen Chain-Step (z.B. via Footer-Home, ChainComplete-
    /// Header-Back, Swipe-Back) leakte der Chain-State in die nächste
    /// Modul-Session — `ChainTimerOverlayModifier` rendert seine
    /// „ÜBUNG X VON Y"-Bar in jeder Chain-aware Modul-Destination,
    /// solange `currentChain != nil`, unabhängig vom `launchContext`.
    /// Jetzt: jeder Pop nach Root räumt auch den Chain-Store
    /// (inkl. der drei Modul-Resume-Stores via `clear()`-Symmetrie).
    /// Idempotent — `clear()` ist no-op auf nil-State.
    func goHome() {
        navigateInstant { navigationPath.removeAll() }
        TrainingChainStore.shared.clear()
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

    func openArcadeScreen(autoStart: Bool) {
        // Falls bereits auf Arcade: nichts tun (kein Stacking).
        if case .arcade = currentScreen { return }
        navigateInstant { navigationPath.append(.arcade(autoStart: autoStart)) }
    }

    /// **Word Runner** als echte Nav-Destination (Phase 7.5):
    /// Start-Screen zeigt jetzt den globalen Footer — analog zur
    /// Arcade. Sobald der User in den Run geht, ruft WR
    /// `setImmersiveArcade(true)` auf und blendet den Footer aus.
    func openWordRunnerScreen() {
        if case .wordRunner = currentScreen { return }
        navigateInstant { navigationPath.append(.wordRunner) }
    }

    var isWordRunnerScreenActive: Bool {
        if case .wordRunner = currentScreen { return true }
        return false
    }

    func setImmersiveArcade(_ active: Bool) {
        isImmersiveArcadeActive = active
    }

    func openLexiconScreen() {
        guard currentScreen != .lexicon else { return }
        navigateInstant { navigationPath.append(.lexicon) }
    }

    var isLexiconScreenActive: Bool {
        if case .lexicon = currentScreen { return true }
        return false
    }

    /// **Elumi-Tab** (Phase 8): vom Footer-Axolotl-Button aus aufgerufen.
    /// Stacked-Push analog zu GameHub/Trophy/Lexicon — Back führt sauber
    /// zurück zu Home.
    func openElumiScreen() {
        guard currentScreen != .elumi else { return }
        navigateInstant { navigationPath.append(.elumi) }
    }

    var isElumiScreenActive: Bool {
        if case .elumi = currentScreen { return true }
        return false
    }

    /// Pokal-Tab-Navigation. Der Tab sammelt die ausführlichen
    /// Status-Cards (Streak, Level/XP, Lernstatus) — auf Home leben
    /// nach dem Rebuild nur noch die kompakten Versionen.
    func openTrophyScreen() {
        guard currentScreen != .trophy else { return }
        navigateInstant { navigationPath.append(.trophy) }
    }

    var isTrophyScreenActive: Bool {
        if case .trophy = currentScreen { return true }
        return false
    }

    func openScreenWhenReady(_ screen: AppScreen, onWillNavigate: (() -> Void)? = nil) {
        guard currentScreen != screen else { return }
        onWillNavigate?()
        navigateInstant { navigationPath.append(screen) }
    }

    /// **Stufe 3 (2026-05-01, Branch `feature/training-session-flow`)** —
    /// Push mit gleichzeitigem Pop des aktuellen Top-Screens. Wird im
    /// Chain-Modus benutzt, damit der NavigationStack auf konstanter
    /// Tiefe bleibt: aus `[Tab, PreScreen, ModulA]` → `[Tab, PreScreen,
    /// ModulB]` statt `[Tab, PreScreen, ModulA, ModulB, …]`. Folge:
    /// Back-Chevron in Modul N pop-t zum Pre-Screen, Pre-Screen-Back
    /// räumt die Chain (siehe Stufe-2-Wiring).
    ///
    /// `removeLast` + `append` in derselben Frame — SwiftUI führt das
    /// als Push+Pop-Animation aus, fühlt sich wie ein normaler Push
    /// an. Defensive: bei leerem Stack (kein Top zum Replacen) wird
    /// einfach gepusht — das passiert in der Praxis nicht im
    /// Chain-Pfad, schadet aber auch nicht.
    func replaceTopWith(_ screen: AppScreen) {
        navigateInstant {
            if !navigationPath.isEmpty {
                navigationPath.removeLast()
            }
            navigationPath.append(screen)
        }
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
