import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var runtime = AppRuntimeContainer()
    @StateObject private var navigation = AppNavigationCoordinator()
    @ObservedObject private var profileStore = ProfileStore.shared
    @ObservedObject private var accountStore = AccountStore.shared
    @ObservedObject private var hintStore = HintStore.shared
    @ObservedObject private var goalStore = LearningGoalStore.shared

    /// **Ziel-Onboarding (2026-08-05)** — reiner Launch-State, analog zu
    /// `hasDismissedWelcomeThisLaunch`. Hält das Overlay explizit offen,
    /// nachdem der Flow selbst schon einen Plan gespeichert hat (Timing-
    /// Grund siehe Doc-Kommentar in `LearningGoalOnboardingView`), und
    /// wird beim regulären Abschluss bzw. beim Handoff in den Scan-Flow
    /// zurück auf `false` gesetzt.
    @State private var isGoalOnboardingLatched = false

    /// **Welcome-Screen (2026-06-09)** — pro App-Start einmal true,
    /// sobald der User den Screen weggeklickt hat. Bewusst reiner
    /// Launch-State (kein UserDefaults): mit
    /// `FeatureFlags.alwaysShowWelcomeScreen == true` erscheint der
    /// Screen dadurch bei JEDEM Start neu. Im Release-Pfad (Flag
    /// `false`) übernimmt zusätzlich der `HintStore` die dauerhafte
    /// Persistenz — siehe `shouldShowWelcomeScreen`.
    @State private var hasDismissedWelcomeThisLaunch = false
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

            // **Welcome-Screen (2026-06-09)** — liegt ÜBER Home, aber
            // UNTER dem Splash: erscheint erst, wenn der Splash durch
            // ist, und nur wenn schon ein Account existiert (sonst
            // läuft noch das Account-Onboarding).
            if shouldShowWelcomeScreen {
                WelcomeScreen(onStart: dismissWelcomeScreen)
                    .transition(.opacity)
                    .zIndex(1)
            }

            // **Ziel-Onboarding (2026-08-05)** — liegt ÜBER Home, UNTER
            // dem Welcome-Screen: erscheint erst, wenn Welcome durch ist
            // und ein Account existiert (der Scan-Handoff braucht die
            // echte `runtime`/`navigation`-Infrastruktur, die es vor
            // Account-Anlage noch nicht gibt). Mutuell exklusiv zu
            // Welcome über die Sichtbarkeitsbedingungen — zIndex(1)
            // schadet trotzdem nicht.
            if shouldShowGoalOnboarding {
                LearningGoalOnboardingView(
                    displayName: accountStore.currentAccount?.displayName ?? "",
                    listStore: runtime.ensureListStoreReady(),
                    // **Ring-Schließen-Fix (2026-08-05)**: kommt der
                    // Nutzer aus dem Scan-Rückweg zurück, direkt beim
                    // Feier-Screen einsteigen statt wieder bei "Was
                    // steht bei dir an?" — Plan und Liste stehen schon.
                    initialStep: goalStore.pendingCelebrationRequested ? .celebration : .transition,
                    navigate: { screen in
                        // Zielscreen wird gezielt über die dedizierte
                        // Coordinator-Methode geöffnet (Guard gegen
                        // Doppel-Push + instant-Transition, gleiches
                        // Verhalten wie beim Scan-Einstieg über den
                        // Footer). Fällt auf reinen Pfad-Push zurück,
                        // falls dieser Onboarding-Flow künftig weitere
                        // Screens ansteuert, für die es keine eigene
                        // Coordinator-Methode gibt.
                        if screen == .scan {
                            openScanScreen()
                        } else {
                            navigation.navigationPath.append(screen)
                        }
                    },
                    onDismissOverlay: {
                        withAnimation(.easeOut(duration: 0.28)) {
                            isGoalOnboardingLatched = false
                        }
                        goalStore.pendingCelebrationRequested = false
                    }
                )
                .transition(.opacity)
                .zIndex(1)
                .onAppear { isGoalOnboardingLatched = true }
            }
        }
        .onAppear {
            // **2026-08-05, Testphase** — siehe Doc-Kommentar am Flag.
            // Muss VOR `bootstrapDependenciesIfNeeded()` laufen, damit
            // beim allerersten Render dieses Starts schon `plan == nil`
            // gilt und `shouldShowGoalOnboarding` sofort korrekt greift.
            //
            // Der Einmal-pro-Start-Guard sitzt IM Store, nicht hier:
            // `onAppear` feuert auch beim Rückkehren aus dem Hintergrund
            // (z. B. nach Kamera/Fotoauswahl im Scan-Flow) und würde das
            // Ziel sonst mitten im Onboarding löschen.
            goalStore.resetForTestingIfNeeded()
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

    // MARK: - Welcome-Screen

    /// Sichtbarkeit des Willkommensscreens.
    ///
    /// **2026-06-09** — Der Screen läuft bewusst VOR dem Account-
    /// Onboarding: Erstnutzer sehen erst, worum es geht, und geben
    /// danach ihren Namen ein. Deshalb hier KEINE Bedingung auf
    /// `accountStore.hasAnyAccount` — der Screen liegt im ZStack über
    /// beidem und gibt nach dem CTA den Blick frei auf das, was
    /// dahinter dran ist (Onboarding beim ersten Mal, sonst Home).
    ///
    /// Bedingungen:
    ///   • Splash ist durch — sonst lägen zwei Vollbild-Layer übereinander.
    ///   • In diesem App-Start noch nicht weggeklickt.
    ///   • Testphase (`alwaysShowWelcomeScreen == true`): immer.
    ///     Release (`false`): nur solange die ID im `HintStore` fehlt.
    private var shouldShowWelcomeScreen: Bool {
        guard !navigation.shouldShowSplashOverlay,
              !hasDismissedWelcomeThisLaunch
        else { return false }

        if FeatureFlags.alwaysShowWelcomeScreen { return true }
        return !hintStore.hasSeen(WelcomeScreen.hintID)
    }

    // MARK: - Ziel-Onboarding

    /// Sichtbarkeit des Ziel-Onboardings.
    ///
    /// Bedingungen:
    ///   • Splash ist durch, Welcome-Screen ist (falls es erschien)
    ///     bereits weggeklickt — kein Übereinanderstapeln zweier
    ///     Vollbild-Intros.
    ///   • Ein Account existiert — der Scan-Handoff braucht die echte
    ///     Navigation, die es vor Account-Anlage noch nicht gibt.
    ///   • `isGoalOnboardingLatched` ODER noch kein Plan gesetzt ODER
    ///     `pendingCelebrationRequested`: Der Riegel hält den Screen
    ///     offen, obwohl der Flow selbst schon früh (Rhythmus-Schritt)
    ///     einen Plan speichert (siehe Doc-Kommentar in
    ///     `LearningGoalOnboardingView`); das Celebration-Signal öffnet
    ///     das Overlay ein zweites Mal, wenn der Nutzer aus dem
    ///     Scan-Rückweg zurückkommt (Ring-Schließen-Fix).
    private var shouldShowGoalOnboarding: Bool {
        guard !navigation.shouldShowSplashOverlay,
              !shouldShowWelcomeScreen,
              accountStore.hasAnyAccount
        else { return false }

        return isGoalOnboardingLatched
            || goalStore.plan == nil
            || goalStore.pendingCelebrationRequested
    }

    @MainActor
    private func dismissWelcomeScreen() {
        runtime.feedbackPlayer?.playTabSwitch()
        withAnimation(.easeOut(duration: 0.28)) {
            hasDismissedWelcomeThisLaunch = true
        }
        // Im Release-Pfad zusätzlich dauerhaft merken. In der Testphase
        // ist das wirkungslos, weil `shouldShowWelcomeScreen` das Flag
        // vorher abfängt — schadet aber nicht und macht das Umstellen
        // auf Release zu einer Ein-Zeilen-Änderung.
        hintStore.markSeen(WelcomeScreen.hintID)
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
