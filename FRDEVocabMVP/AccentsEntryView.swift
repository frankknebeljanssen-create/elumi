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
    @State private var showingListPicker = false
    @State private var activeSession: ActiveSession?
    @State private var showingResult: SessionResult?
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
            // direkt zu Home zu springen. Out-of-chain Verhalten
            // unverändert (User kam von Home → geht zurück nach Home).
            AppTopBar(
                onBack: {
                    if launchContext?.chainContext != nil {
                        dismiss()
                    } else {
                        goHome()
                    }
                },
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
            if session.mode == .lernen {
                // Lernen-Modus: Karten-View. Nach „Jetzt üben" direkt in
                // eine Üben-Session rüber.
                AccentsLearningView(
                    cards: session.learningCards,
                    accentColor: moduleAccentColor,
                    onClose: { activeSession = nil },
                    onStartPractice: {
                        activeSession = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            startSession(mode: .uben)
                        }
                    },
                    feedbackPlayer: feedbackPlayer,
                    onHome: goHome,
                    onSettings: openSettings
                )
            } else {
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
                return result.mode == .speedRound ? "Noch eine Runde" : "Weiter lernen"
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
                        }
                    )
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.top, AppLayout.screenHeaderTopPadding)
                    .padding(.bottom, AppLayout.screenPadding)
                    .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .sheet(isPresented: $showingListPicker) {
            ListPickerSheet(
                style: sectionStyle,
                lists: availableLists,
                selectedListID: selectedListID,
                onSelect: { id in
                    selectedListID = id
                    showingListPicker = false
                },
                onDelete: { _ in /* nicht erlaubt aus dem Akzent-Modul */ }
            )
        }
    }

    // MARK: - Primary Content

    /// Systemkonformer Aufbau analog zu ListsView / LexiconView:
    /// ScreenHeaderCard (centered title + Back-Chevron) oben, darunter
    /// die eigentlichen Module-Cards im selben Spacing-Raster wie alle
    /// anderen Module. Kein eigener Header mehr — die Top-Bar kommt
    /// vom App-Chrome.
    private var primaryContent: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    ModuleHeaderCard(
                        icon: .akzente,
                        title: "Akzente",
                        accent: sectionStyle.accent,
                        // **Chain-Mode Back-Chevron (2026-05-02)** —
                        // analog AppTopBar oben: Chain → dismiss
                        // (Pre-Screen), out-of-chain → goHome.
                        onBack: {
                            if launchContext?.chainContext != nil {
                                dismiss()
                            } else {
                                goHome()
                            }
                        }
                    )

                    listSelectorCard
                    modeCards

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.screenHeaderTopPadding)
                .padding(.bottom, AppLayout.screenPadding)
                .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.bottom, usesGlobalChrome ? 0 : AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg)
        }
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
            showingListPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("AUSGEWÄHLTE LISTEN")
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
                            Text({
                                let cnt = VocabularyListSelectionResolver.effectiveItems(
                                    for: list,
                                    lernjahrMax: VocabularyListSelectionResolver.currentLernjahrMax()
                                ).count
                                return "1 Liste · \(cnt) \(cnt == 1 ? "Eintrag" : "Einträge") gesamt"
                            }())
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.elumiBlue)
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
        VStack(spacing: AppTheme.Spacing.sm) {
            modeCard(
                mode: .lernen,
                icon: "book.closed.fill",
                headline: "Lernen",
                subline: "Accents entspannt kennenlernen"
            )
            modeCard(
                mode: .uben,
                icon: "scope",
                headline: "Üben",
                subline: "Mit direktem Feedback trainieren"
            )
            // Speed Round — appweit gleicher Kurzmodus, gleicher Timer,
            // gleicher Summary-Pfad. Headline liest aus der zentralen
            // Terminologie (einfacher späterer Rename); das Subline-
            // Format „N Sekunden Tempo" spiegelt die globale Dauer.
            modeCard(
                mode: .speedRound,
                icon: "bolt.fill",
                headline: SpeedRoundTerminology.name,
                subline: speedRoundSubline
            )
        }
    }

    /// Modus-Card — visuell an den systemweiten `drillModeCard`-Stil
    /// (Training/Nomen/Artikel/Verben) angeglichen: Icon oben
    /// zentriert, Headline + Subline darunter, keine Chevron-Navigation.
    /// Vorher war Akzente das einzige Mode-Modul mit horizontalem
    /// Chevron-Row-Layout; jetzt stehen die drei Modi (Lernen / Üben /
    /// Speed Round) als gleichwertige Card-Trio-Gruppe — identische
    /// optische Sprache wie bei den Drill-Modulen.
    private func modeCard(mode: AccentMode, icon: String, headline: String, subline: String) -> some View {
        Button {
            startSession(mode: mode)
        } label: {
            // Cards ~20 % flacher (User-Wunsch):
            //   • minHeight 120 → 96
            //   • vertical padding 14 → 10
            //   • Icon-Circle 54 → 48 pt (+ Spacing/Top angepasst)
            VStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(moduleAccentColor.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(moduleAccentColor)
                }
                .frame(width: 48, height: 48)
                .padding(.top, 2)

                VStack(alignment: .center, spacing: 3) {
                    Text(headline)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subline)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
        }
        .buttonStyle(.plain)
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
    private func handleAccentsAppear() {
        guard launchContext?.shouldAutoStart == true,
              activeSession == nil,
              !hasAutoStarted else {
            return
        }
        hasAutoStarted = true
        let mode = launchContext?.preferredMode ?? .uben
        startSession(mode: mode)
    }

    private func startSession(mode: AccentMode) {
        switch mode {
        case .lernen:
            // Lernen-Modus: eigene View mit Intro-Karten, keine Session-Engine nötig.
            let cards = AccentContentBuilder.buildLearningCards()
            activeSession = ActiveSession(
                mode: .lernen,
                exercises: [],
                learningCards: cards
            )

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
                    learningCards: [],
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
                learningCards: [],
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
                learningCards: [],
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
    let learningCards: [AccentContentBuilder.LearningCard]
    /// Wenn gesetzt, wird der Engine via `restoringFrom:` konstruiert —
    /// Queue, Index, Answer-Records, Reinsertion-Counter werden 1:1
    /// zurückgespielt. `nil` bei frischer Session.
    let resumeSnapshot: AccentSessionResumeState?

    init(
        mode: AccentMode,
        exercises: [AccentExercise],
        learningCards: [AccentContentBuilder.LearningCard],
        resumeSnapshot: AccentSessionResumeState? = nil
    ) {
        self.mode = mode
        self.exercises = exercises
        self.learningCards = learningCards
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
