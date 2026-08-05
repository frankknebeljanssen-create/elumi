import SwiftUI

/// Start-Screen des Akzent-Moduls.
///
/// Struktur analog zu Train/Quiz: oben Listen-Auswahl, darunter drei
/// Modus-Cards (Lernen / Üben / Speed Round). Tap auf eine Card startet
/// die jeweilige Session. Der Speed-Round-Modus teilt sich Mechanik,
/// Timer, Summary und Reward-Pfad mit allen anderen Modulen — siehe
/// `SpeedRoundSettings` / `SpeedRoundTerminology`.
///
/// Navigation läuft über den lokalen `NavigationStack` im Host —
/// selektierte Session wird via `.navigationDestination` gezeigt.
struct AccentsEntryView: View {
    /// Durchgereicht vom `AppDestinationHost`. Liefert die Listen.
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    /// Speaker vom Runtime-Container durchgereicht — wird in Audio-
    /// Exercises für französische TTS genutzt.
    @ObservedObject var speaker: Speaker

    /// Optional vom Launch-Context vorgegeben.
    let launchContext: AccentsLaunchContext?
    /// **Stufe 3 (2026-05-01)** — Chain-Advance-Closure (siehe
    /// FlashcardsView.swift:Doc).
    @Environment(\.appChainAdvanceAction) private var chainAdvance

    /// V3: persistente Adaptive-Confidence — wird für die Seed-Gewichtung
    /// in `AccentContentBuilder` und das Result-Screen-Ranking genutzt.
    @StateObject private var adaptiveStore = AccentAdaptiveStore.shared

    @State private var selectedListID: UUID
    /// **Gruppe-4-Migration (2026-05-22)** — Push-State für den
    /// `UnifiedListCategoryPicker`. Ersetzt `showingListPicker` (war
    /// Sheet-Trigger). `.navigationDestination` sitzt im `body`-Modifier.
    @State private var listPickerActive = false
    @State private var activeSession: ActiveSession?
    @State private var showingResult: SessionResult?
    /// **A3 Master-Migration (2026-05-06)** — bewusst gewählter Modus
    /// für die nächste Session. Vorher startete der Tap auf eine Mode-
    /// Card direkt; jetzt setzt der Tap nur die Auswahl, der CTA am
    /// unteren Rand triggert den Start (analog zu Quiz / Karteikarten /
    /// Training, nicht mehr direkt-tap wie früher). `nil` = noch keine
    /// Wahl getroffen → CTA bleibt disabled.
    @State private var selectedMode: AccentMode? = nil
    /// **Chain-Mode State-Leak-Guard (2026-05-02)** — once-only-Flag
    /// für `handleAccentsAppear`. Beim ersten `.onAppear` mit
    /// `shouldAutoStart=true` startet die Session und das Flag wird
    /// auf `true` gesetzt. Subsequent `.onAppear`-Aufrufe (z.B. nach
    /// Cover-Dismiss zurück zur AccentsEntryView) sehen das Flag und
    /// re-triggern den Auto-Start NICHT — verhindert den vorher
    /// dokumentierten State-Leak, bei dem nach Cover-Dismiss das
    /// Cover sofort wieder aufpoppte. Bleibt für die View-Lifetime
    /// gesetzt; bei Route-Pop wird die View destroy't und das Flag
    /// resettet sich automatisch beim nächsten Mount.
    @State private var hasAutoStarted: Bool = false
    /// Bindet die globale Speed-Round-Dauer live ins UI — Änderungen in
    /// den Settings werden auf der Setup-Card sofort sichtbar, ohne dass
    /// ein manueller Reload nötig ist. Der Wert landet auch auf dem
    /// Engine-Timer (siehe `AccentSessionEngine.startSpeedRoundTimer`).
    @AppStorage(appSpeedRoundDurationKey) private var speedRoundSecondsRaw: Int = SpeedRoundDuration.defaultDuration.rawValue
    /// Captured `SessionRewardOutcome` vom letzten Session-Finish.
    /// Wird an die geteilte `SessionSummaryView` gereicht — identisch
    /// zu Flashcards/Quiz/Training.
    @State private var sessionOutcome: SessionRewardOutcome?

    @Environment(\.dismiss) private var dismiss
    private let sectionStyle: AppSectionStyle = .accents
    private var moduleAccentColor: Color { sectionStyle.accent }

    init(
        listStore: VocabularyListStore,
        feedbackPlayer: FeedbackPlayer,
        speaker: Speaker,
        goHome: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        launchContext: AccentsLaunchContext? = nil
    ) {
        self.listStore = listStore
        self.feedbackPlayer = feedbackPlayer
        self.speaker = speaker
        self.goHome = goHome
        self.openSettings = openSettings
        self.launchContext = launchContext

        // Bevorzugte Liste aus dem Context, sonst erste verfügbare, sonst
        // dictionary-Fallback.
        let preferred = launchContext?.preferredListID
            ?? listStore.customLists.first?.id
            ?? VocabularyListStore.dictionaryListID
        self._selectedListID = State(initialValue: preferred)
    }

    // MARK: - Body

    /// Prüft, ob das globale App-Chrome aktiv ist (AppTopBar + AppBottomBar
    /// werden zentral gerendert). Fallback: lokal rendern, damit wir auch
    /// außerhalb des globalen Frames funktionieren.
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    var body: some View {
        primaryContent
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // **Stufe 4b-Modal-Refactor / Chain-Auto-Start (2026-05-02)** —
        // Pattern-Mirror von `QuizView+Lifecycle.swift:19` und
        // `TrainingView+Lifecycle.swift:19`. Wenn die Akzente vom
        // Chain-Step (oder einem anderen Caller mit
        // `shouldAutoStart = true`) geöffnet werden, überspringen wir
        // den Setup-Screen mit Liste/Mode-Cards und starten direkt
        // die Session im vom Caller vorgegebenen Modus
        // (`preferredMode`, Default `.uben`).
        //
        // **Idempotenz** über `activeSession == nil`-Guard — der
        // `.onAppear` feuert auch beim Pop einer
        // NavigationDestination und beim Dismiss eines Covers; wir
        // wollen nicht jedes Mal eine neue Session bauen, sondern
        // nur beim ersten Mount im Chain-Mode.
        //
        // **Out-of-chain-Pfad** (Home-Tile → Akzente, kein
        // launchContext oder `shouldAutoStart = false`): Branch
        // ist No-Op, Setup-Screen bleibt sichtbar wie heute.
        .onAppear {
            handleAccentsAppear()
        }
        .appLocalChrome(enabled: !usesGlobalChrome) {
            // **Chain-Mode Back-Chevron (2026-05-02)** — defensiv: in
            // Chain-Mode sollte der Setup-Screen mit Mode-Cards
            // ohnehin nie sichtbar sein (Setup-Skip + Cover startet
            // sofort), aber falls doch (z.B. State-Leak-Edge-Case),
            // dismissen wir die Modul-Route → Pre-Screen, statt
            // direkt zu Home zu springen.
            //
            // **A3 Smoke-Fix (2026-05-06)** — Out-of-chain Back nutzt
            // jetzt `dismiss()` statt `goHome()`. `goHome()` läuft
            // über `AppNavigationCoordinator.navigateInstant` und
            // schaltet Animationen explizit ab — kein Slide. Mit
            // `dismiss()` kommt die native NavigationStack-Pop-
            // Animation, identisch zu Quiz / Training / Verben (alle
            // dort dismissen). Konsistent mit dem System-Pattern.
            AppTopBar(
                onBack: { dismiss() },
                onInfo: nil
            )
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: { openSettings() }
            )
        }
        .fullScreenCover(item: $activeSession) { session in
            // **Stufe 6 (2026-05-02)** — Lernen-Modus entfernt; nur
            // Üben + Speed Round laufen über `AccentsSessionView`.
            AccentsSessionView(
                    mode: session.mode,
                    exercises: session.exercises,
                    resumeSnapshot: session.resumeSnapshot,
                    resumeListID: selectedList?.id,
                    accentColor: moduleAccentColor,
                    feedbackPlayer: feedbackPlayer,
                    speaker: speaker,
                    onClose: {
                        // **Chain-Mode Back-Chevron (2026-05-02)** — im
                        // Chain-Mode reicht nicht nur Cover-Dismiss, sonst
                        // landet User auf der AccentsEntryView Setup-
                        // Card (Mode-Cards) → Setup-Skip-Verstoß. Wir
                        // dismissen daher zusätzlich die Modul-Route
                        // selbst → User landet auf Pre-Screen. Audio-
                        // Cleanup läuft via SessionView's `.onDisappear`
                        // (Cover-Dismiss-Trigger).
                        activeSession = nil
                        if launchContext?.chainContext != nil {
                            dismiss()
                        }
                    },
                    onHome: goHome,
                    onSettings: openSettings,
                    onFinish: { payload in
                        activeSession = nil
                        // Gamification-Hook — identisch zu Quiz/Training/
                        // Flashcards. XP, Credits, Streak, Daily-Bonus,
                        // Variable-Reward werden zentral vergeben. Das
                        // Outcome füttern wir in die geteilte
                        // `SessionSummaryView`.
                        let wrong = max(0, payload.total - payload.correct)
                        let learningSession = LearningSession(
                            origin: .accents,
                            correctCount: payload.correct,
                            wrongCount: wrong,
                            longestCombo: 0,
                            masteredCardCount: 0
                        )
                        sessionOutcome = ProgressService.shared.record(session: learningSession)

                        // V3: Adaptive-Store aktualisieren — pro Akzenttyp
                        // wird die Trefferquote in die persistente
                        // Confidence eingemischt. Nächste Session nutzt
                        // diese Confidence automatisch.
                        adaptiveStore.updateFromSession(breakdown: payload.breakdown)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingResult = SessionResult(mode: session.mode)
                        }
                    }
                )
        }
        .fullScreenCover(item: $showingResult) { result in
            // Systemweiter Summary-Screen — **identisch** zu Flashcards,
            // Quiz, Training, Verbformen. Akzente liefert nur die
            // Content-Payload (origin=.accents, correctCount,
            // wrongCount); Layout, XP-Hero, Progress, Reward-Bereich,
            // CTA-Position kommen aus der geteilten View.
            //
            // **Headline-Override bei Speed Round** — die zentrale
            // Logik in `LearningSession.resultHeadline` spricht bei
            // `.accents` das gleiche Format wie Quiz/Training/
            // Verbformen („X von Y richtig"). Das passt für den
            // Üben-Modus, aber nicht für die Akzente-Speed-Round: dort
            // ist — genauso wie bei allen anderen Speed-Rounds — die
            // Zeit das Besondere. Deshalb setzen wir den Override
            // (`resultHeadline`) nur in diesem Fall auf das
            // „N Treffer in Xs"-Format, analog zu `LearningSession`
            // `case .speedRound`. Dadurch spricht jeder Speed-Round-
            // Summary dieselbe Sprache, unabhängig vom Modul.
            //
            // CTA-Labels an System-Konvention angeglichen:
            //   • Primär: Speed Round → "Noch eine Runde" (nochmal
            //     spielen), Üben → "Weiter lernen" (wie in Training,
            //     Quiz, Flashcards).
            //   • Sekundär: "Zur Startseite" (überall gleich) —
            //     schließt das Akzente-Modul komplett.
            let effectiveHeadline: String? = {
                guard result.mode == .speedRound,
                      let correct = sessionOutcome?.session.correctCount else {
                    return nil  // nil → default aus `LearningSession.resultHeadline`
                }
                return Self.speedRoundSummaryHeadline(correct: correct)
            }()

            // **Stufe 3 (2026-05-01)** — Chain-Mode-Branching. Im
            // Chain-Modus ignorieren wir den speedRound-Pfad-spezifischen
            // „Noch eine Runde"-Label und nehmen die einheitliche
            // „Weiter zu …"/"Training abschließen"-Wording.
            let accentsOutcome = sessionOutcome ?? .empty
            let chain = launchContext?.chainContext
            let nextStepTitle = chain?.nextStep?.title
            let isChain = chain != nil
            let primaryLabel: String = {
                if isChain {
                    return nextStepTitle.map { "Weiter zu \($0)" } ?? "Training abschließen"
                }
                return result.mode == .speedRound ? "Noch eine Runde" : "Nächste Runde"
            }()
            // **Full-Screen-Background-Wrapper (2026-05-02)** —
            // `SessionSummaryView` ist eine Card ohne eigenen Full-
            // Screen-Background; im AccentsEntryView läuft sie via
            // `.fullScreenCover`, also ohne ParentView-Background-
            // Quelle. Ohne expliziten ZStack-Wrapper rendert iOS den
            // Cover mit System-Default-Hintergrund (weiß) — das war
            // nicht sichtbar solange Chain-Mode den Result-Pfad nie
            // erreichte. Wrapper repliziert das Pattern aus
            // `AccentsSessionView.body`: `AppTheme.Colors.background`
            // + `ignoresSafeArea` als Backdrop-Layer, ScrollView für
            // sichere Vertikal-Aufnahme bei langen Summary-Inhalten.
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    SessionSummaryView(
                        outcome: accentsOutcome,
                        progress: ProgressStore.shared.progress,
                        resultHeadline: effectiveHeadline,
                        primaryCTALabel: primaryLabel,
                        onPrimaryCTA: {
                            if isChain {
                                chainAdvance?(accentsOutcome)
                            } else {
                                showingResult = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    startSession(mode: result.mode)
                                }
                            }
                        },
                        secondaryCTALabel: isChain ? nil : "Zur Startseite",
                        onSecondaryCTA: isChain ? nil : {
                            showingResult = nil
                            goHome()
                        },
                        primaryCTAPulses: isChain,
                        hidesDetailedStats: isChain
                    )
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.top, AppLayout.screenHeaderTopPadding)
                    .padding(.bottom, AppLayout.screenPadding)
                    .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        // **Gruppe-4-Migration (2026-05-22)** — Push statt Sheet.
        // `UnifiedListCategoryPicker` mit `singleSelect: true` ersetzt
        // `GlobalListPickerSheet` direkt. Auto-Pop: nach Commit setzt
        // `onCommit` `listPickerActive = false` → NavigationStack
        // poppt sofort (kein manuelles „Zurück" nötig nach Auswahl).
        .navigationDestination(isPresented: $listPickerActive) {
            UnifiedListCategoryPicker(
                availableLists: availableLists,
                selectedIDs: [selectedListID],
                onCommit: { newSelection in
                    if let id = newSelection.first {
                        selectedListID = id
                        listPickerActive = false
                    }
                },
                accent: sectionStyle.accent,
                singleSelect: true,
                includeWoerterbuch: false,
                itemLabel: "Einträge",
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onSettings: { openSettings() }
            )
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Primary Content

    /// **A3 Master-Migration (2026-05-06)** — Akzente-Setup nutzt jetzt
    /// `SessionSetupScreen` als gemeinsame Hülle (Header, Spacing,
    /// CTA-Block). Vorher baute Akzente eigenes Layout aus
    /// `ModuleHeaderCard` + `listSelectorCard` + `modeCards`. Folge
    /// damals: UI-Drift bei jedem Setup-System-Upgrade musste pro
    /// Modul gepflegt werden. Mit der Migration:
    ///   • `contextContent` = `listSelectorCard` (Listen-Auswahl mit
    ///     LJ-Pill, weiterhin Akzente-spezifisch single-select).
    ///   • `optionsContent` = `modeCards` mit Selection-State; Tap
    ///     setzt jetzt `selectedMode`, kein direkt-Start.
    ///   • CTA „Akzente starten" am unteren Rand, gated by
    ///     `selectedMode != nil`. Konsistent mit Quiz „Quiz starten",
    ///     Karteikarten „Karteikarten starten" etc.
    ///   • `showsDirection: false` + `showsDirectionToggle: false` —
    ///     Akzente sind FR-spezifisch, kein Direction-Switch nötig.
    ///   • `showsGamificationBar: false` — Akzente hatte historisch
    ///     keine XP/Dauer-Bar; bewusst weglassen statt mit `.zero`-
    ///     Estimate eine leere Bar zu rendern.
    private var primaryContent: some View {
        SessionSetupScreen(
            title: "Akzente",
            accent: sectionStyle.accent,
            estimate: .zero,
            // **Naming-Sweep 2026-05-06** — „Akzente starten" →
            // „Los geht's!" (CTA-Vereinheitlichung).
            primaryButtonTitle: "Los geht's!",
            isPrimaryEnabled: selectedMode != nil,
            showsDirection: false,
            showsGamificationBar: false,
            moduleIcon: .akzente,
            helpTopic: .accents,
            onBack: {
                // **A3 Smoke-Fix (2026-05-06)** — durchgängig
                // `dismiss()` für Slide-Animation. Im Chain-Mode war
                // das ohnehin schon so; out-of-chain war früher
                // `goHome()` (instant, kein Slide). Mit dismiss() in
                // beiden Pfaden poppt der NavigationStack mit der
                // System-Slide-Animation — analog Quiz/Training/
                // Verben.
                dismiss()
            },
            onStart: {
                // CTA gated über `isPrimaryEnabled` → wenn wir hier
                // landen, ist `selectedMode` garantiert non-nil.
                guard let mode = selectedMode else { return }
                startSession(mode: mode)
            },
            contextContent: { listSelectorCard },
            optionsContent: { modeCards }
        )
    }

    // MARK: - List Selector

    /// Listen-Auswahl — exakt wie in Verbformen / Vokabeln / Quiz:
    ///   • weißes `HomeIconListen`-Asset als 36pt Icon (kein getönter Tile)
    ///   • Liste-Name in Weiß links + „N Einträge" in Accent rechts
    ///   • Summary-Zeile darunter in **Elumi-Blau** (systemweit
    ///     einheitlich — wirkt wie ein Link)
    ///   • Pencil-Pill in Modul-Accent
    ///   • `appSetupCardBackground` als Container
    private var listSelectorCard: some View {
        Button {
            listPickerActive = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // **Naming-Sweep 2026-05-06** — „AUSGEWÄHLTE
                // LISTEN" → „DEINE LISTEN" (konsistent appweit).
                Text("AUSGEWÄHLTE LERNLISTEN")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.Colors.cardLabel)

                HStack(alignment: .center, spacing: 14) {
                    // Home-Listen-Icon — systemweit identisch zur
                    // „Listen"-Kachel auf dem Home-Screen.
                    HomeModuleIconView(icon: .listen, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        if let list = selectedList {
                            Text(list.name)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Summary-Zeile in Elumi-Blau — systemweiter
                            // Link-Look, identisch zu Verbformen/Vokabeln.
                            // Kein redundanter Right-Side-Badge mehr.
                            //
                            // **V1b (2026-04-28)**: Count respektiert
                            // den globalen Lernjahr-Filter — User sieht
                            // ehrlich, wieviele Karten ins Akzent-Pool
                            // einfließen.
                            //
                            // **A3 Master-Migration (2026-05-06)** —
                            // LJ-Range ist jetzt eine tappbare
                            // `AppLernjahrPill` (B2-Pattern), kein
                            // Plain-Text mehr. Eligibility identisch
                            // zu allen anderen Modulen: Pill nur, wenn
                            // mindestens eine cumulative-Liste mit
                            // aktivem Filter ausgewählt ist.
                            let cnt = VocabularyListSelectionResolver.effectiveItems(
                                for: list,
                                lernjahrMax: VocabularyListSelectionResolver.currentLernjahrMax()
                            ).count
                            let totalText = "\(cnt) \(cnt == 1 ? "Eintrag" : "Einträge")"
                            let lernjahrRange = VocabularyListSelectionResolver.lernjahrRangeLabel(forSelectedLists: [list])
                            HStack(spacing: 4) {
                                Text("1 Lernliste ·")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                                if let range = lernjahrRange {
                                    AppLernjahrPill(label: range, tint: AppTheme.Colors.elumiBlue)
                                    Text("·")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.elumiBlue)
                                }
                                Text(totalText)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                            }
                            .padding(.top, 2)
                        } else {
                            Text("Standard-Wörter")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text("Built-in Akzent-Katalog")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.elumiBlue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Stift in rundem Pill — systemweit einheitlich
                    // (16/38, Accent 0.18). `frame(maxHeight: .infinity)`
                    // zentriert den Pill exakt vertikal in der HStack-
                    // Höhe, unabhängig von der VStack-Geometrie daneben.
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(moduleAccentColor)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(moduleAccentColor.opacity(0.18))
                        )
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode Cards

    private var modeCards: some View {
        // **2026-05-04 Layout-Konsistenz** — Akzente an
        // `TrainingView+Layout.drillModeCard` (Verbformen-Pattern)
        // angeglichen: 2 Cards nebeneinander statt vertikal gestapelt,
        // ohne Subline, kompaktere Icon/Headline-Größen.
        //
        // **A3 Master-Migration (2026-05-06)** — Direkt-Start raus.
        // Mode-Cards setzen jetzt `selectedMode`; Start läuft über den
        // Master-CTA „Akzente starten". Cards bekommen Selected-State-
        // Styling (Akzent-Stroke + Highlight-Background), damit der
        // User die getroffene Wahl visuell bestätigt sieht.
        HStack(alignment: .top, spacing: AppLayout.setupDetailBlockSpacing) {
            modeCard(
                mode: .uben,
                icon: "scope",
                // **Naming-Sweep 2026-05-06** — „Üben" → „Training"
                // damit Akzente konsistent zu Nomen / Verben /
                // Artikel / Verbformen ist (alle nutzen
                // „Training" / „Speed-Modus" als Mode-Card-Paar).
                // Der zugrundeliegende Enum-Case `.uben` bleibt
                // (rawValue-Kompatibilität persistierter Resume-
                // Snapshots).
                headline: "Training"
            )
            modeCard(
                mode: .speedRound,
                icon: "bolt.fill",
                headline: SpeedRoundTerminology.name
            )
        }
    }

    /// Modus-Card — visuell am `drillModeCard`-Stil aus
    /// `TrainingView+Layout` (Verbformen / Verben / Nomen / Artikel)
    /// orientiert. Icon-Circle 38 pt, 16 pt black-rounded Headline,
    /// keine Subline, minHeight 92.
    ///
    /// **A3 Master-Migration (2026-05-06)** — Tap setzt jetzt
    /// `selectedMode` statt direkt zu starten. Selected-Styling über
    /// Akzent-Stroke + dichteren Background, identisch zur Quiz-/
    /// Training-Mode-Wahl-Konvention. Tap-Feedback bleibt (Haptik).
    private func modeCard(mode: AccentMode, icon: String, headline: String) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMode = mode
            }
        } label: {
            VStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(moduleAccentColor.opacity(isSelected ? 0.30 : 0.16))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(moduleAccentColor)
                }
                .frame(width: 38, height: 38)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .center)

                Text(headline)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
            .appCardBackground(
                sectionStyle,
                intensity: isSelected ? AppTheme.CardIntensity.medium : AppTheme.CardIntensity.soft
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(isSelected ? moduleAccentColor : Color.clear, lineWidth: isSelected ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(headline))
        .accessibilityHint(Text(isSelected ? "Ausgewählt" : "Tippen, um diesen Modus auszuwählen"))
    }

    // MARK: - Helpers

    /// Alle wählbaren Listen — User-Request: nicht nur `customLists`,
    /// sondern **alle** Listen des Stores (inkl. Built-in-Sammlungen wie
    /// Themen-Listen, Niveau-Listen, Wörterbuch-Level). `allLists` ist
    /// die zentrale API, die auch vom ListPickerSheet in anderen
    /// Modulen (Lists, Training) genutzt wird.
    private var availableLists: [VocabularyList] {
        listStore.allLists
    }

    private var selectedList: VocabularyList? {
        availableLists.first(where: { $0.id == selectedListID })
    }

    /// Headline-Override für die Akzente-**Speed-Round**-Summary.
    /// Format identisch zu `LearningSession.resultHeadline` im
    /// `case .speedRound`-Branch: „N Treffer in Ys". Die Sekundenzahl
    /// kommt aus der globalen `SpeedRoundSettings`, damit die Anzeige
    /// zur tatsächlich abgelaufenen Dauer passt (20/30/45/60 s).
    ///
    /// Dieser Helper lebt in AccentsEntryView (nicht in
    /// `LearningSession`), weil `origin == .accents` modul-semantisch
    /// korrekt bleibt (Gamification-Thresholds + Streak-Logik orientieren
    /// sich daran). Die Headline ist reiner UI-Text und lässt sich
    /// sauber über den Override-Parameter der Summary-View einspeisen.
    private static func speedRoundSummaryHeadline(correct: Int) -> String {
        let seconds = SpeedRoundSettings.currentSeconds
        return correct == 1
            ? "1 Treffer in \(seconds)s"
            : "\(correct) Treffer in \(seconds)s"
    }

    /// Subline der Speed-Round-Card — liest die aktuelle globale Dauer,
    /// damit Nutzer direkt sehen, wie lang die gerade konfigurierte
    /// Runde ist (z. B. „30 Sekunden Tempo", wenn in den Settings
    /// 30 s gewählt wurde). Fallback auf den Default, falls der
    /// persistierte Wert aus irgendeinem Grund ungültig ist.
    private var speedRoundSubline: String {
        let seconds = SpeedRoundDuration(rawValue: speedRoundSecondsRaw)?.seconds
            ?? SpeedRoundDuration.defaultDuration.seconds
        return SpeedRoundTerminology.subtitle(forSeconds: seconds)
    }

    /// **Stufe 4b-Modal-Refactor / Chain-Auto-Start (2026-05-02)** —
    /// `.onAppear`-Handler. Wenn die Akzente per `shouldAutoStart` aus
    /// einem Chain-Step (oder einem anderen Auto-Start-Caller) geöffnet
    /// werden, überspringt die View den Setup-Screen und startet
    /// direkt die Session im vorgegebenen Modus. Pattern-Konsistenz zu
    /// Quiz / Training. `activeSession == nil`-Guard sichert Idempotenz
    /// gegen Re-Appear (z.B. nach Cover-Dismiss).
    ///
    /// **2026-05-04 Fix** — Vorher las Akzente *nie* die globale
    /// Listen-Auswahl. `selectedListID` wurde nur in `init` aus dem
    /// `launchContext` oder als Custom-Listen-Default initialisiert.
    /// Folge: User wählt Liste in Listen-Tab oder einem anderen
    /// Modul-Setup, geht zu Akzente — Akzente nutzt weiterhin die
    /// alte init-Liste. Pattern-Mirror zu Quiz/Training/Flashcards:
    /// auf jedem `onAppear` aus dem globalen Slot lesen und in den
    /// `selectedListID` mappen, falls verfügbar.
    private func handleAccentsAppear() {
        restoreSelectedListIDFromGlobal()

        guard launchContext?.shouldAutoStart == true,
              activeSession == nil,
              !hasAutoStarted else {
            return
        }
        hasAutoStarted = true
        let mode = launchContext?.preferredMode ?? .uben
        startSession(mode: mode)
    }

    /// Liest die globale Listen-Auswahl und übernimmt das erste
    /// passende Element in `selectedListID`. Akzente ist single-select,
    /// also greift bei Multi-Auswahl der erste Eintrag aus dem Set.
    /// `effectiveSelectedListIDs` mit leerem Per-Modul-Fallback —
    /// Akzente persistiert keine eigene Per-Modul-Auswahl, deshalb gibt
    /// es nur den globalen Pfad.
    private func restoreSelectedListIDFromGlobal() {
        let globalIDs = VocabularyListSelectionResolver.effectiveSelectedListIDs {
            return []
        }
        guard let firstID = globalIDs.first,
              availableLists.contains(where: { $0.id == firstID }) else {
            return
        }
        selectedListID = firstID
    }

    private func startSession(mode: AccentMode) {
        switch mode {
        case .uben:
            // Üben-Modus ist resumable — erst prüfen, ob ein passender
            // Snapshot vorliegt (gleicher Mode + gleiche Liste). Fällt
            // der Fingerprint-Check durch, wird der Snapshot verworfen
            // und eine frische Session gebaut.
            let expectedFingerprint = AccentSessionResumeStore.fingerprint(
                mode: .uben,
                selectedListID: selectedList?.id
            )
            if let snapshot = AccentSessionResumeStore.load(),
               snapshot.configFingerprint == expectedFingerprint,
               !snapshot.exercises.isEmpty {
                activeSession = ActiveSession(
                    mode: .uben,
                    exercises: snapshot.exercises,
                    resumeSnapshot: snapshot
                )
                return
            } else if AccentSessionResumeStore.load() != nil {
                // Snapshot liegt, passt aber nicht mehr → aufräumen.
                AccentSessionResumeStore.clear()
            }

            // Frische Session.
            let exercises = AccentContentBuilder.buildSession(
                mode: .uben,
                from: selectedList,
                adaptiveStore: adaptiveStore
            )
            guard !exercises.isEmpty else { return }
            activeSession = ActiveSession(
                mode: .uben,
                exercises: exercises,
                resumeSnapshot: nil
            )

        case .speedRound:
            // Speed Round: kein Resume (Timer-Runde). Falls ein alter
            // Üben-Snapshot liegt, bleibt er unverändert — er gehört zum
            // Üben-Pfad und wird dort beim nächsten Start wieder gefunden.
            let exercises = AccentContentBuilder.buildSession(
                mode: .speedRound,
                from: selectedList,
                adaptiveStore: adaptiveStore
            )
            guard !exercises.isEmpty else { return }
            activeSession = ActiveSession(
                mode: .speedRound,
                exercises: exercises,
                resumeSnapshot: nil
            )
        }
    }
}

// MARK: - Model Shells für Sheets

/// Wrapper, damit `.fullScreenCover(item:)` ein Identifiable bekommt.
private struct ActiveSession: Identifiable {
    let id = UUID()
    let mode: AccentMode
    let exercises: [AccentExercise]
    // **Stufe 6 (2026-05-02)** — `learningCards` mit dem Lernen-
    // Modus entfernt; ActiveSession trägt jetzt nur noch Üben-/
    // Speed-Round-Exercises plus optionalen Resume-Snapshot.
    /// Wenn gesetzt, wird der Engine via `restoringFrom:` konstruiert —
    /// Queue, Index, Answer-Records, Reinsertion-Counter werden 1:1
    /// zurückgespielt. `nil` bei frischer Session.
    let resumeSnapshot: AccentSessionResumeState?

    init(
        mode: AccentMode,
        exercises: [AccentExercise],
        resumeSnapshot: AccentSessionResumeState? = nil
    ) {
        self.mode = mode
        self.exercises = exercises
        self.resumeSnapshot = resumeSnapshot
    }
}

private struct SessionResult: Identifiable {
    let id = UUID()
    /// Nur der Modus — der Inhalt des Summary-Screens kommt komplett
    /// aus dem geteilten `SessionRewardOutcome`. Die früher hier
    /// gespeicherten Felder (correct/total/breakdown/audioSplit) sind
    /// obsolet, seit Akzente die systemweite `SessionSummaryView`
    /// nutzt. Mode bleibt, weil der „Noch eine Runde"-CTA den gleichen
    /// Modus neu startet.
    let mode: AccentMode
}
