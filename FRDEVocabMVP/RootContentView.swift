import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var runtime = AppRuntimeContainer()
    @StateObject private var navigation = AppNavigationCoordinator()
    @ObservedObject private var profileStore = ProfileStore.shared
    @ObservedObject private var accountStore = AccountStore.shared
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
                // **Onboarding-Gate (Phase 8 — Multi-Account)**: beim
                // allerersten Start (oder nach Reset) zeigen wir den
                // Account-Onboarding-Flow *statt* der NavigationStack-
                // Home. Sobald ein Account existiert, rendert die
                // Home-Hierarchie. Der alte single-user `OnboardingView`
                // mit Lernziel-Auswahl ist entfallen — das Account-
                // Modell deckt die Identität jetzt ab; Lernziel kann
                // perspektivisch im Account-Detail erweitert werden.
                if !accountStore.hasAnyAccount {
                    AccountOnboardingView(
                        accountStore: accountStore,
                        onComplete: { account in
                            // Legacy-ProfileStore-Sync: der bestehende
                            // Name-Display greift weiterhin über
                            // `ProfileStore.displayName`. Damit die
                            // Begrüßung auf Home sofort den neuen
                            // Namen zeigt, fassen wir `ProfileStore`
                            // mit gleichem Namen nach — keine
                            // Doppelfelder im UI, beide Stores bleiben
                            // konsistent.
                            profileStore.completeOnboarding(
                                displayName: account.displayName,
                                learningGoal: nil
                            )
                        },
                        allowsCancel: false
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
                            // **Stufe 3 (2026-05-01)** — Push-with-Replace
                            // für Chain-Advance. Modul-Done-CTA → Host-
                            // closure ruft `chainStore.advanceChain(...)`
                            // → wir replacen den Modul-Screen oben im
                            // Stack durch den nächsten Step (oder
                            // `.trainingChainComplete`-Platzhalter), damit
                            // der Stack während einer Chain konstant tief
                            // bleibt. Siehe `AppNavigationCoordinator.replaceTopWith`.
                            replaceTop: { nextScreen in navigation.replaceTopWith(nextScreen) },
                            markFlashcardsOpenTiming: markFlashcardsOpenTiming
                        )
                        // **Direkt auf die Destination** dieselben
                        // Environment-Closures anbinden, die auch
                        // außen am NavigationStack gesetzt sind.
                        // SwiftUI propagiert Environment zwar auch
                        // über `navigationDestination`, aber es gab
                        // User-Reports über „Footer-Buttons außer
                        // Einstellungen reagieren nicht beim ersten
                        // Öffnen einer Route — funktionieren nach
                        // Re-Entry". Das deutet auf einen
                        // First-Push-Env-Timing-Quirk hin. Die
                        // redundante Anwendung hier stellt sicher,
                        // dass env-fallback-Buttons (Kamera,
                        // Wörterbuch, Spiele) IMMER die richtigen
                        // Closures sehen.
                        .environment(\.appOpenScanAction, { openScanScreen() })
                        .environment(\.appOpenLexiconAction, { openLexiconScreen() })
                        .environment(\.appOpenGameHubAction, { openGameHubScreen() })
                        // **2026-05-04** — Trophy-Action analog zu den
                        // anderen Footer-Targets verfügbar machen, damit
                        // Sheet-Picker den Pokal-Button nicht mehr
                        // gedimmt rendern müssen.
                        .environment(\.appOpenTrophyAction, {
                            runtime.feedbackPlayer?.playTabSwitch()
                            navigation.openTrophyScreen()
                        })
                        .environment(\.appOpenAccountAction, { navigation.navigationPath.append(.account) })
                        // **SwiftUI quirk workaround (2026-05-07)** —
                        // `.toolbar(.hidden, …)` und
                        // `.navigationBarBackButtonHidden(true)` MÜSSEN
                        // auf dem `navigationDestination`-Wrapper sitzen,
                        // damit die System-Default-Toolbar beim ersten
                        // Push (Cold-View-Konstruktion) NICHT für einen
                        // Frame aufblitzt. Verschiebt man die beiden
                        // Modifier zurück in den Destination-Body,
                        // greifen sie erst nach Body-Evaluation und der
                        // System-Back-Button flasht kurz auf, bevor der
                        // Custom-Pink-Chevron erscheint (User-Befund:
                        // KK first-push). Tech-Debt-Note siehe
                        // `TODO_post_v1b.md` unter „Chevron-System".
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                        // **Pfad-2 Footer-Inset (2026-05-07)** — Push-
                        // Screens (NavigationStack-Destinations) erben
                        // den auf RootContentView gesetzten
                        // `.safeAreaInset(.bottom, AppBottomBar)` NICHT
                        // zuverlässig (bekannter SwiftUI-Quirk —
                        // Tab-Root-Views wie HomeView funktionieren,
                        // pushed Views wie Slot-Screen / Listen-Hub /
                        // andere brauchen eigene Reservation).
                        //
                        // Hier: transparenter `Color.clear`-Spacer in
                        // gleicher Höhe wie der Footer-Frame (= 50 pt
                        // Bar-Höhe + 8 pt Bottom-Inset), reserviert
                        // den Bereich auf Destination-Ebene. Die Bar
                        // wird visuell weiterhin EINMALIG durch
                        // RootContentView's safeAreaInset gerendert
                        // (siehe oben), kein Doppel-Render.
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if navigation.shouldShowGlobalChrome {
                                Color.clear
                                    .frame(height: AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom)
                            }
                        }
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
                // **Footer-Migration zu safeAreaInset (2026-05-07)** —
                // Vorher `.overlay(alignment: .bottom)`: rein visuelle
                // Schicht ohne Layout-Awareness, ScrollViews extendeten
                // unter den Footer und mussten per-Screen padding-bottom-
                // Workarounds verwalten — auf realen iPhones führte das
                // zu Footer-Overlap (User-Report Slot-Screen-CTA).
                //
                // Mit `.safeAreaInset(edge: .bottom, spacing: 0)` rendert
                // SwiftUI die Bar an gleicher visueller Stelle UND
                // rechnet ihre Höhe in den Safe-Area-Stack ein —
                // Inner-ScrollViews respektieren das automatisch, kein
                // per-Screen-Padding mehr nötig (Cleanup folgt nach
                // Smoke-Identifikation der Drift-Stellen).
                //
                // `spacing: 0` explizit gesetzt, damit kein Default-
                // Spacing zwischen Inset-Bar und Inner-Content.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if navigation.shouldShowGlobalChrome {
                        AppBottomBar(
                            feedbackPlayer: feedbackPlayer,
                            onHome: { runtime.feedbackPlayer?.playTabSwitch(); navigation.goHome() },
                            // Footer-Snack-Button (ehem. „Sammlung") öffnet jetzt den
                            // Game Hub. Der Progress Hub bleibt über den Pokal-Tab
                            // erreichbar — klare Trennung „Footer = Spielen",
                            // „Pokal = Fortschritt".
                            onFavorite: navigation.isGameHubScreenActive ? nil : { openGameHubScreen() },
                            onScan: navigation.isLexiconScreenActive ? nil : { openLexiconScreen() },
                            onSettings: isSettingsScreenActive ? nil : { openSettingsScreen() },
                            // **Pokal-Tab** (Home-Rebuild): tappable im
                            // globalen Footer überall in der App. Auf
                            // dem Pokal-Screen selbst entfällt die Action
                            // (kein Re-Push), Icon bleibt aktiv markiert.
                            onTrophy: navigation.isTrophyScreenActive ? nil : {
                                runtime.feedbackPlayer?.playTabSwitch()
                                navigation.openTrophyScreen()
                            },
                            isHeartsActive: navigation.isGameHubScreenActive,
                            isScanActive: navigation.isLexiconScreenActive,
                            isTrophyActive: navigation.isTrophyScreenActive,
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
                .environment(\.appOpenLexiconAction, {
                    openLexiconScreen()
                })
                .environment(\.appOpenGameHubAction, {
                    openGameHubScreen()
                })
                .environment(\.appOpenTrophyAction, {
                    runtime.feedbackPlayer?.playTabSwitch()
                    navigation.openTrophyScreen()
                })
                .environment(\.appOpenArcadeAction, { autoStart in
                    navigation.openArcadeScreen(autoStart: autoStart)
                })
                .environment(\.appOpenElumiAction, {
                    // **Phase 8**: Axolotl-Footer-Button → persönlicher
                    // Elumi-Tab. Nutzt die gleiche Pfad-Push-Mechanik wie
                    // die anderen Tabs, damit der Screen via Back wieder
                    // sauber zurück zu Home führt.
                    navigation.openElumiScreen()
                })
                .environment(\.appSetImmersiveArcadeAction, { active in
                    navigation.setImmersiveArcade(active)
                })
                // **Daily Drop Modul 2.9 (2026-05-23)** — Layout-Modus
                // entkoppelt vom Keyboard-Flag: der globale Footer (oben,
                // `safeAreaInset` :230) bleibt auf `shouldShowGlobalChrome`
                // gated (versteckt sich bei Tastatur), aber `appUsesGlobalChrome`
                // nutzt `shouldUseGlobalChromeLayout` (ohne `isChatKeyboardActive`).
                // So togglen die Module ihr `appLocalChrome` NICHT mehr beim
                // Tippen → kein Re-Parent → kein Quiz-Typing-Loop.
                .environment(\.appUsesGlobalChrome, navigation.shouldUseGlobalChromeLayout)
                // **Léa-Chat MVP — Keyboard-Footer-Hide (2026-05-10)** —
                // ChatView ruft diese Closure aus seinem
                // NotificationCenter-Listener für `keyboardWillShow/Hide`.
                // Wir schreiben in den Coordinator; das computed
                // `shouldShowGlobalChrome` reagiert dadurch automatisch
                // und der globale Footer wird aus der `safeAreaInset`-
                // Branch ausgeblendet. Die `.animation(...)` weiter unten
                // sorgt für smooth fade.
                .environment(\.appSetChatKeyboardActiveAction, { active in
                    navigation.isChatKeyboardActive = active
                })
                // **Animation-Anchor**: die safeAreaInset oben rendert
                // den AppBottomBar conditional auf `shouldShowGlobalChrome`.
                // Wenn `isChatKeyboardActive` flippt, animiert SwiftUI
                // die strukturelle Insertion/Removal mit dem
                // 0.25 s-easeOut, das parallel zur iOS-Standard-Keyboard-
                // Slide-Duration läuft → optisch synchron.
                .animation(
                    .easeOut(duration: 0.25),
                    value: navigation.isChatKeyboardActive
                )
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
