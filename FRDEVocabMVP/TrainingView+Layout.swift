import SwiftUI
import Combine

/// Tracking-PreferenceKeys für das Drag-and-Drop-Matching im Verbformen-Modul.
/// Dieselbe Mechanik wie im Quiz-Matching: Chips/Targets melden ihre Frames
/// im gemeinsamen `coordinateSpace`, der Drag-State berechnet daraus den Hover-Treffer.
struct VerbformsPronounFramePreferenceKey: PreferenceKey {
    static var defaultValue: [VerbformsPerson: CGRect] = [:]
    static func reduce(value: inout [VerbformsPerson: CGRect], nextValue: () -> [VerbformsPerson: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct VerbformsFormFramePreferenceKey: PreferenceKey {
    static var defaultValue: [VerbformsPerson: CGRect] = [:]
    static func reduce(value: inout [VerbformsPerson: CGRect], nextValue: () -> [VerbformsPerson: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension TrainingView {
    var trainingRootContent: some View {
        ZStack(alignment: .top) {
            Group {
                if isVerbformsMode {
                    if verbformsSession.isActive || verbformsCountdown != nil {
                        verbformsSessionScreen
                    } else if verbformsSession.isFinished {
                        verbformsResultScreen
                    } else {
                        trainingSetupScreen
                    }
                } else if let outcome = trainingSessionOutcome {
                    // Nach einer beendeten Session zeigen wir die einheitliche
                    // `SessionSummaryView` — gleiche Optik wie Karteikarten /
                    // Verbformen. „Weiter" räumt das Outcome weg und gibt die
                    // Setup-Card wieder frei.
                    trainingSummaryScreen(outcome: outcome)
                } else if session.isShowingSetup {
                    trainingSetupScreen
                } else {
                    trainingSessionScreen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Systemweites Top-Padding — Header sitzt auf derselben
            // vertikalen Position wie im Quiz-Setup (Vorlage).
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, usesGlobalChrome ? 0 : AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg)

            // Combo-Toast-Overlay — liegt über allen Session-Screens und
            // zeigt bei erreichter Streak-Schwelle (3/5/10, siehe
            // `FeedbackConfig`) einen abgestuften Toast.
            ComboToastOverlay()
            // Milestone-Overlay — größere, seltenere Momente
            // (Session-Ende, Wort-Mastered). Zweite Z-Ebene, damit es
            // visuell über dem Streak-Toast liegt, falls beide zufällig
            // gleichzeitig feuern (passiert durch den Cooldown praktisch
            // nicht, der Overlay ist trotzdem sauber getrennt).
            MilestoneOverlayView()

            // Empty-Pool-Toast (2026-04-29) — Last-Line-of-Defense-
            // Feedback wenn der User „Los geht's" tippt, der Pre-Tap-
            // Defense (`canStartTraining`) aber den Cache-Stale-Edge-
            // Case durchgelassen hat und der Deck dann doch leer baut.
            // Pattern analog `ListsView`-Toast (Z. 44-48), aber Top-
            // Edge-Slide statt Bottom — damit nichts mit dem CTA am
            // unteren Rand kollidiert. Auto-Dismiss in `showEmptyPoolToast()`.
            if let message = emptyPoolToastMessage {
                emptyPoolToastView(message: message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.top, AppLayout.screenHeaderTopPadding + 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Empty-Pool-Toast-Zelle — Warning-Style (orange Akzent, Achtung-
    /// Icon), inhaltlich identisches Layout wie `ListsView.toastView`
    /// im `isSuccess: false`-Pfad.
    private func emptyPoolToastView(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppTheme.Colors.warning)

            Text(message)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.surface.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(AppTheme.Colors.warning.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: AppTheme.Shadow.card.color, radius: 10, x: 0, y: 4)
    }

    /// Zentrale Session-Summary für das Training-Modul (Vokabeln, Nomen,
    /// Artikel, Verben, Speed-Rounds). Wird nach dem Reward-Hook angezeigt,
    /// wenn die Session Fortschritt hatte. „Weiter" gibt das Outcome frei
    /// und wechselt zurück zur Setup-Card.
    func trainingSummaryScreen(outcome: SessionRewardOutcome) -> some View {
        VStack(spacing: 16) {
            // **Block 2 (2026-05-02)** — User-Spec: im Chain-Mode auf
            // dem Summary-Screen kein Modul-Chevron + Title mehr. Der
            // Chain-Header (3 Step-Cards + Timer) via
            // `ChainTimerOverlayModifier` trägt die Schritt-Identität;
            // ein zusätzlicher Modul-Header dupliziert die Information
            // und nimmt der Chain-Progression visuelles Gewicht. User
            // navigiert via Chain-Header oder System-Back-Geste — kein
            // eigener Chevron nötig. Out-of-Chain-Pfad (Home → Modul
            // direkt) zeigt den Header wie bisher.
            if launchContext?.chainContext == nil {
                trainingCompactHeader
            }

            // **Stufe 3 (2026-05-01)** — Chain-Mode-Branching
            // (siehe FlashcardsView+SessionComponents.swift für Doc).
            let chain = launchContext?.chainContext
            let nextStepTitle = chain?.nextStep?.title
            let isChain = chain != nil
            let primaryLabel: String = isChain
                ? (nextStepTitle.map { "Weiter zu \($0)" } ?? "Training abschließen")
                : "Weiter lernen"
            SessionSummaryView(
                outcome: outcome,
                progress: progressStore.progress,
                primaryCTALabel: primaryLabel,
                onPrimaryCTA: {
                    if isChain {
                        chainAdvance?(outcome)
                    } else {
                        trainingSessionOutcome = nil
                    }
                },
                secondaryCTALabel: isChain ? nil : "Zur Startseite",
                onSecondaryCTA: isChain ? nil : {
                    dismissToHome()
                },
                primaryCTAPulses: isChain,
                hidesDetailedStats: isChain
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 32)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            // Zentraler Hard-Stop für die Training-Session, sobald die
            // globale Summary sichtbar wird: TTS + Speech-Recognition +
            // pending Feedback-Tasks + Speed-Round-Timer werden abge-
            // räumt. Guard gegen „App liest/hört noch unter dem Summary
            // weiter". Bereits laufende `awardTrainingXPIfNeeded` ist
            // idempotent via `session.sessionRewardConsumed`.
            runtimeSpeaker?.stop()
            speechController?.stopRecording()
            cancelPendingFeedback()
            stopSpeedRoundTimer()
        }
    }

    private var sessionHeaderTitle: String {
        switch session.trainingMode {
        case .vocabulary: return "Vokabeln"
        case .nouns: return "Nomen"
        case .articles: return "Artikel"
        case .verbs: return "Verben"
        case .verbforms: return "Verbformen"
        }
    }

    /// Kompakter Header für Training-Setup-Screens (alle Modi). Zurück führt
    /// raus aus dem Training (dismiss → Home).
    var trainingCompactHeader: some View {
        trainingHeaderShared(onBack: { dismiss() })
    }

    /// Kompakter Header für Training-Session-Screens (während Übung). Zurück
    /// führt zur Setup-Card zurück (handleTopBarBack), nicht raus zu Home.
    var trainingSessionCompactHeader: some View {
        trainingHeaderShared(onBack: { handleTopBarBack() })
    }

    /// Gemeinsame Header-Implementierung — nackter Back-Pfeil links
    /// (in Modul-Akzentfarbe), Modul-Titel zentriert, rechts leer.
    /// Analog zu Karteikarten/Quiz/SessionSetup. `onBack` ist die
    /// jeweilige Aktion (Setup → Home; Session → Setup).
    ///
    /// Back-Button und Bottom-Padding kommen aus systemweiten Primitiven,
    /// damit Position + Abstand zum Content auf jedem Screen identisch
    /// bleiben.
    private func trainingHeaderShared(onBack: @escaping () -> Void) -> some View {
        ZStack {
            Text(sessionHeaderTitle)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                AppBackButton(action: onBack, tint: trainingActionTint)

                Spacer()
            }
        }
        .padding(.top, 4)
        .padding(.bottom, AppLayout.screenHeaderBottomPadding)
    }

    var trainingSessionScreen: some View {
        VStack(spacing: 8) {
            // Kompakter Header analog Karteikarten — kleiner „< Zurück" links
            // (führt zur Setup-Card, nicht raus zu Home), Modul-Titel mittig.
            // ScreenHeaderCard + großer Zurück-Button entfernt.
            trainingSessionCompactHeader

            // Progress counter for Nomen, Artikel, Verben
            // **Block 3.7.3 (2026-05-03)** — User-Spec: im Chain-
            // Modus sind Modul-eigene „X / Y"-Counter und „Runde N"
            // redundant zum Chain-Header („ÜBUNG X VON Y"-Step-
            // Indikator). Conditional auf
            // `launchContext?.chainContext == nil` — Counter bleibt
            // out-of-Chain unverändert sichtbar.
            if !session.isSpeedRound, (isNounMode || isArticleMode || isVerbMode), session.hasStartedTraining, !session.isShowingRoundComplete, launchContext?.chainContext == nil {
                let solved = session.preparedTrainingItems.count - session.remainingTrainingItems.count
                let total = session.preparedTrainingItems.count
                HStack {
                    Text("\(solved) / \(total)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(trainingActionTint)
                    Spacer()
                    Text("Runde \(session.completedRound)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, trainingSessionCardInset + 4)
            }

            if session.isShowingRoundComplete {
                roundCompleteView
            } else if let countdown = speedCountdown {
                // 3-2-1 Countdown overlay
                Text("\(countdown)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
            } else {
                if session.isSpeedRound, session.hasStartedTraining {
                    speedRoundTimerBar
                        .padding(.horizontal, trainingSessionCardInset)
                }

                sessionCard
                    .padding(.horizontal, trainingSessionCardInset)
                if isArticleMode {
                    articleButtons
                        .padding(.horizontal, trainingSessionCardInset)
                } else if isNounChoiceMode {
                    // Nomen-Wortauswahl: 8er-Grid statt Mikrofon. Identische
                    // Struktur wie der Verb-MC-Zweig — nur andere MC-State-
                    // Variablen (`nounMC*`). Für Speed Round / Speech bleibt
                    // der Standard-Flow unverändert (isNounChoiceMode ist
                    // dort per Definition false).
                    Spacer().frame(height: AppTheme.Spacing.xs)
                    nounMCCard
                        .padding(.horizontal, trainingSessionCardInset)
                } else if isVerbMode {
                    Spacer().frame(height: AppTheme.Spacing.xs)
                    verbMCCard
                        .padding(.horizontal, trainingSessionCardInset)

                    // Translation hint
                    if let item = session.currentTrainingItem {
                        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
                        let translationText = isFRtoDe ? item.german : item.french
                        Button {
                            showingVerbTranslation.toggle()
                        } label: {
                            if showingVerbTranslation {
                                Text(translationText)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                                    .background(AppTheme.Colors.secondarySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                            } else {
                                Label("Übersetzung", systemImage: "eye")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                                    .background(AppTheme.Colors.secondarySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, trainingSessionCardInset)
                    }
                } else {
                    actionButtons
                        .padding(.horizontal, trainingSessionCardInset)
                    responseCard
                        .padding(.horizontal, trainingSessionCardInset)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var trainingSetupScreen: some View {
        // Migration auf Master-Session-Setup: Header / CTA / Gamification-Bar
        // kommen zentral aus `SessionSetupScreen`. Die modul-spezifischen
        // Listen-Auswahl-Varianten (5 Modi × unterschiedliche Cards) leben
        // weiter in contextContent. Options (Dictionary-Level, Speed-Round,
        // Hints, Verbformen-Tense-Picker) kommen in optionsContent darunter.
        //
        // Vokabel-spezifische CTA-Behandlung (Clean-UX-Umbau):
        //   • CTA-Titel spiegelt den gewählten Modus wider
        //     („Vokabeltraining starten" / „Speed Round starten").
        //   • Keine Subline — die frühere „Viel Erfolg beim Lernen!"-
        //     Zeile ist pro User-Request raus. Der CTA bleibt damit
        //     als single-line-Button, so wie in allen anderen Modulen.
        //   • `showsGamificationBar: false` — die XP/Zeit/Credits-Zeile
        //     sitzt jetzt inline in der Speed-Round-Mode-Card.
        // Alle anderen Module behalten das klassische „Los geht's!" + Bar.
        let isVocabMode = (session.trainingMode == .vocabulary)
        // Vokabeln hat nach dem Struktur-Refactor kein Speed Round mehr
        // → CTA ist immer „Vokabeltraining starten". Alle anderen Module
        // behalten „Los geht's!".
        let ctaTitle: String = isVocabMode ? "Vokabeltraining starten" : "Los geht's!"
        let ctaSubtitle: String? = nil

        // Modul-Icon dynamisch per `trainingMode` — jeder Modus hat
        // seine eigene Home-Identität (Phase 7.6+).
        let moduleIconForMode: HomeModuleIcon = {
            switch session.trainingMode {
            case .vocabulary: return .vokabeln
            case .nouns:      return .nomen
            case .articles:   return .artikel
            case .verbs:      return .verben
            case .verbforms:  return .verbformen
            }
        }()

        return SessionSetupScreen(
            title: sessionHeaderTitle,
            accent: trainingActionTint,
            estimate: trainingSessionEstimate,
            primaryButtonTitle: ctaTitle,
            primarySubtitle: ctaSubtitle,
            isPrimaryEnabled: isVerbformsMode ? verbformsCanStart : canStartTraining,
            // **Chain-Mode XP-Card-Hide (2026-05-02)** — zusätzlich zum
            // bestehenden `!isVocabMode`-Filter (Vokabeln nutzt eigene
            // Speed-Round-Card-XP-Anzeige) blenden wir die zentrale
            // Gamification-Bar im Chain-Modus systemweit aus. Begründung
            // wie bei Quiz: Chain-Timer ist Begrenzung, per-Modul-XP-
            // Schätzung passt nicht. Default true bleibt für Home-Tile-
            // Pfad.
            showsGamificationBar: !isVocabMode && launchContext?.chainContext == nil,
            moduleIcon: moduleIconForMode,
            showsDirectionToggle: true,
            gamificationBarHintText: trainingGamificationHintText,
            onBack: { dismiss() },
            onStart: {
                if isVerbformsMode {
                    guard verbformsCanStart else { return }
                    startVerbformsTraining()
                } else {
                    guard canStartTraining else { return }
                    startTraining()
                }
            },
            contextContent: { trainingSetupContextContent },
            optionsContent: { trainingSetupOptionsContent }
        )
        .sheet(item: $listPickerCategory) { category in
            // **Phase 2 (2026-05-04)** — Migration auf
            // `GlobalListPickerSheet`. `filteredLists(for: category)`
            // pre-filtert nach der vom User getippten Kategorie
            // (.topic / .level / .own / .all), wir reichen das
            // gefilterte Set als `allLists` durch.
            GlobalListPickerSheet(
                allLists: filteredLists(for: category),
                initialSelection: session.selectedTrainingListIDs,
                onCommit: { updatedSelection in
                    session.selectedTrainingListIDs = updatedSelection
                    listPickerCategory = nil
                },
                categoryHeaders: false,
                feedbackPlayer: feedbackPlayer,
                onHome: goHome
            )
        }
    }

    // MARK: - Training-Setup Content-Slots (für SessionSetupScreen)

    /// Context-Slot: **nur** die Listen-Auswahl-Card. Alles, was früher
    /// zusätzlich im Context-Slot mitlief (Vokabeln-Kategorie-Grid,
    /// Verbformen-Tense-Picker), ist in den Options-Slot gewandert — damit
    /// systemweit gilt: direkt unter „Ausgewählte Listen" sitzt die
    /// Richtungs-Zeile, ohne Zwischenelemente.
    @ViewBuilder
    private var trainingSetupContextContent: some View {
        if session.trainingMode == .vocabulary {
            ListCategoryPickerView(
                availableLists: availableTrainingLists,
                selectedListIDs: session.selectedTrainingListIDs,
                accent: trainingActionTint,
                style: sectionStyle,
                feedbackPlayer: feedbackPlayer,
                summaryText: trainingListCount.isEmpty ? "" : (trainingListName + " \u{00B7} " + trainingListCount),
                itemLabel: "Einträge",
                onSelectionChanged: { session.selectedTrainingListIDs = $0 },
                onHome: goHome
            )
        } else if session.trainingMode == .verbforms {
            verbformsListSelectionCard
        } else if session.trainingMode == .verbs {
            verbsListSelectionCard
        } else if session.trainingMode == .nouns {
            nounsListSelectionCard
        } else if session.trainingMode == .articles {
            articlesListSelectionCard
        } else {
            ListCategoryPickerView(
                availableLists: availableTrainingLists,
                selectedListIDs: session.selectedTrainingListIDs,
                accent: trainingActionTint,
                style: sectionStyle,
                feedbackPlayer: feedbackPlayer,
                summaryText: trainingListCount.isEmpty ? "" : (trainingListName + " \u{00B7} " + trainingListCount),
                itemLabel: trainingItemLabel,
                onSelectionChanged: { session.selectedTrainingListIDs = $0 },
                onHome: goHome
            )
        }
    }

    /// Options-Slot: alles, was **unter** der Richtungs-Zeile liegen soll.
    /// Modul-spezifisch:
    ///   • Vokabeln: zweistufige Entscheidungs-Architektur
    ///     („Was möchtest du trainieren?" → Training/Speed-Round-Mode-Cards,
    ///     dann „Wie möchtest du trainieren?" → Detail-Grid). Ersetzt die
    ///     frühere flache Optionsliste + den separaten Speed-Round-Toggle.
    ///   • Nomen: zusätzliche Entscheidungs-Ebene „Wie möchtest du
    ///     antworten?" (Spracheingabe / Wortauswahl) steht **über** dem
    ///     Speed-Round-Toggle. Reihenfolge: Answer-Mode → Speed Round →
    ///     (Gamification-Bar aus dem äußeren `SessionSetupScreen`).
    ///     Speed Round ignoriert den Answer-Mode (eigene Antwort-
    ///     Mechanik), die Answer-Mode-Auswahl definiert den Default
    ///     fürs normale Training.
    ///   • Verbformen: Tense-Picker (Zeitformen).
    ///   • alle Modi außer Vokabeln: Dictionary-Level-Card (konditional),
    ///     Speed-Round-Toggle und Start-Hints.
    @ViewBuilder
    private var trainingSetupOptionsContent: some View {
        if session.trainingMode == .vocabulary {
            vocabularySetupOptions
        } else {
            // Drill-Module (Nomen / Artikel / Verben / Verbformen) haben
            // jetzt alle **dieselbe** Grundstruktur:
            //   1. Modus-Block („Was möchtest du machen?" → Training /
            //      Speed Round)
            //   2. Detail-Optionen **nur** wenn Training aktiv
            //      (Verbformen: Tense-Picker · Nomen: Antwort-Modus ·
            //       Artikel / Verben: keine zusätzlichen Details).
            //   3. Start-Hints bei fehlender Konfiguration.
            // Speed Round ist **kein** eigener Button und kein
            // standalone Toggle mehr, sondern eine Modus-Wahl.
            drillModeSection

            if !session.isSpeedRound {
                if session.trainingMode == .verbforms {
                    verbformsSetupOptions
                }

                if isDictionaryTrainingSelected {
                    dictionaryTrainingLevelCard
                }

                if session.trainingMode == .nouns {
                    nounAnswerModeSection
                }
            }

            // Verbformen/Verben: Hint steht jetzt **in** der
            // GamificationBar über dem CTA (siehe
            // `trainingGamificationHintText`) — keine lose Inline-Zeile
            // mehr. Nomen/Artikel/Vokabeln bleiben beim bisherigen
            // Inline-Pattern, damit der Hint dort sichtbar ist.
            if !canStartTraining, !isVerbformsMode, !isVerbMode {
                Text(startHintText)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    // MARK: - Nomen Answer-Mode Section
    //
    // Sekundäre Entscheidungs-Ebene im Nomen-Setup: „Wie möchtest du
    // antworten?". Zwei Cards side-by-side, beide mit Nomen-Akzent
    // (sectionStyle.accent ≈ grün). Deutlich ruhiger als die Speed-Round-
    // Card darüber — Hierarchie-Signal „sekundäre Entscheidung".
    //
    // `session.nounAnswerMode` (`.speech` / `.choice`) ist schon in der
    // Session verdrahtet. Wortauswahl ist architektonisch vorbereitet,
    // die konkrete 8er-Grid-Matching-Logik wird in einer Folge-PR
    // implementiert. Aktuell startet auch bei `.choice` das bestehende
    // Speech-Training (kein Breakage, nur UI-State).

    private var nounAnswerModeSection: some View {
        // Sublines pro User-Request komplett raus („Wähle die Eingabeform"
        // als Section-Subline, „Sprich das richtige Wort ein" auf der
        // Speech-Card, „Wähle aus 8 Wörtern" auf der Choice-Card). Der
        // Header trägt jetzt nur noch den Titel, die Cards nur noch
        // Icon + Titel — dieselbe Reduktionsstufe wie die Vokabel-Detail-
        // Cards. Die Bedeutung erschließt sich aus Icon (Mikrofon /
        // Grid) + Titel, eine Erklär-Zeile ist redundant.
        VStack(alignment: .leading, spacing: 10) {
            Text("Wie möchtest du antworten?")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 10) {
                nounAnswerModeCard(
                    mode: .speech,
                    title: "Sprache",
                    systemImage: "mic.fill"
                )
                nounAnswerModeCard(
                    mode: .choice,
                    title: "Wortauswahl",
                    // SF-Symbol `square.grid.2x2.fill` — Grid-Icon passt
                    // zur 8er-Auswahl-Mechanik (Grid-Layout im Session-
                    // Screen). Gleiche Strichstärke wie die anderen Icons
                    // im Setup.
                    systemImage: "square.grid.2x2.fill"
                )
            }
        }
    }

    /// Eine der zwei Nomen-Answer-Mode-Cards. Visuell analog zu den
    /// Vokabel-Modus-Cards (Icon-Puck oben-zentriert, Titel mittig),
    /// aber ruhiger im Gewicht: kleinere Schrift, kleinere Icon-Puck-
    /// Größe, kein Shadow. Aktive Card bekommt einen kräftigeren Tint-Fill
    /// + sichtbaren Border in Modul-Akzent.
    @ViewBuilder
    private func nounAnswerModeCard(
        mode: NounAnswerMode,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = (session.nounAnswerMode == mode)

        Button {
            feedbackPlayer.playTabSwitch()
            session.nounAnswerMode = mode
        } label: {
            VStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(trainingActionTint.opacity(isSelected ? 0.28 : 0.14))
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(trainingActionTint)
                }
                .frame(width: 38, height: 38)
                .padding(.top, 2)

                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            // Nach dem Subline-Wegfall fallen ~14 pt Content weg — die
            // gemeinsame `minHeight` rutscht entsprechend von 110 auf
            // **92 pt**. Die beiden Cards bleiben exakt gleich hoch,
            // nur insgesamt kompakter, passend zur reduzierten
            // Inhalts-Zeile (nur noch Icon + Titel).
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                            .fill(trainingActionTint.opacity(isSelected ? AppTheme.CardIntensity.medium : AppTheme.CardIntensity.subtle))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(
                        isSelected ? trainingActionTint : AppTheme.Colors.border.opacity(0.7),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            // Kein Shadow — Answer-Mode-Cards sind sekundäre Ebene,
            // visuell flacher als die Speed-Round-Card darüber.
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "ausgewählt" : "nicht ausgewählt")
    }

    // MARK: - Vokabel-Setup: zweistufige Entscheidungs-Architektur
    //
    // Umbau nach User-Brief „Vokabeln Screen clean UX":
    //   1. Haupt-Entscheidung: Trainingsmodus (Vokabeltraining vs Speed Round)
    //      → zwei gleichgroße, visuell prominente Cards mit Akzent-Tint,
    //      Speed-Round-Card trägt XP/Dauer/Credits inline (ersetzt die
    //      frühere zentrale Gamification-Bar unten).
    //   2. Sekundäre Entscheidung: Detail-Auswahl (Themen / Niveau /
    //      Eigene / Wörterbuch) → 2×2-Grid mit gleichem Modul-Akzent,
    //      aber deutlich ruhiger (flacheres Card-BG, kein Shadow,
    //      kleineres Icon) — sekundäre Hierarchie-Stufe.
    // Bei Speed-Round-Modus wird das Detail-Grid visuell abgedimmt
    // (Opacity 0.45) — bleibt sichtbar, damit das Layout nicht springt,
    // wirkt aber inaktiv, weil Speed Round keine Detail-Kategorie braucht.

    @ViewBuilder
    private var vocabularySetupOptions: some View {
        // Struktur-Refactor TYPE 3 (Flow Modul): Vokabeln hat **kein**
        // Speed Round mehr. Die frühere `vocabularyModeSection` (Training
        // vs Speed Round) ist entfernt — der Vokabeln-Flow ist jetzt
        // ausschließlich Training mit Detail-Auswahl (Themen/Niveau/
        // Eigene/Wörterbuch). CTA-Label + Session-Logik behandeln
        // `isSpeedRound` für diesen Mode implizit als false.
        //
        // Spacing zwischen Detail-Grid und Dictionary-Level-Card nutzt
        // `setupMainSectionSpacing` — systemweit mit allen anderen
        // Modul-Setups abgestimmt.
        VStack(alignment: .leading, spacing: AppLayout.setupMainSectionSpacing) {
            vocabularyDetailSection

            // Dictionary-Level-Card bleibt konditional — wenn der Nutzer
            // „Ganzes Wörterbuch" aktiviert, erscheint die Level-Picker-
            // Card aus dem bestehenden System.
            if isDictionaryTrainingSelected {
                dictionaryTrainingLevelCard
            }

            if !canStartTraining {
                Text(startHintText)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // Ehemalige `vocabularyModeSection` (Vokabeltraining vs Speed Round
    // für das Vokabeln-Modul) wurde mit dem Speed-Round-Cleanup des
    // Flow-Moduls Vokabeln entfernt. Die Modus-Auswahl für die Drill-
    // Module läuft über `drillModeSection` weiter unten.

    /// Systemweiter Modus-Block für die Drill-Module (Nomen, Artikel,
    /// Verben, Verbformen). Zeigt das Paar [Training] [Speed Round]
    /// und schreibt die Auswahl in `session.isSpeedRound` — ersetzt
    /// den früheren standalone `speedRoundToggle`.
    private var drillModeSection: some View {
        VStack(alignment: .leading, spacing: AppLayout.setupHeadlineToContentSpacing) {
            vocabularySectionTitle(
                title: "Was möchtest du machen?",
                subtitle: nil
            )

            HStack(alignment: .top, spacing: AppLayout.setupDetailBlockSpacing) {
                drillModeCard(
                    isSpeedRound: false,
                    title: "Training",
                    subtitle: "Gezielt üben und behalten",
                    systemImage: "book.fill"
                )
                drillModeCard(
                    isSpeedRound: true,
                    title: SpeedRoundTerminology.name,
                    // Subtitle liest die globale Dauer aus den Settings —
                    // „20 Sekunden Tempo", „30 Sekunden Tempo" usw.
                    subtitle: SpeedRoundTerminology.subtitle(forSeconds: speedRoundDurationSeconds),
                    systemImage: "bolt.fill"
                )
            }
        }
    }

    /// Section 2 — Sekundäre Entscheidung: Detail-Kategorie.
    ///
    /// Titel + Subline pro User-Request komplett entfernt („Wie möchtest
    /// du trainieren?" und die zugehörige Subline sind raus). Das 2×2-
    /// Grid steht jetzt headerless direkt unter den Modus-Cards — die
    /// Hierarchie bleibt erhalten (Modus-Cards sind visuell prominenter
    /// als die Detail-Cards), aber der Screen wird insgesamt ruhiger
    /// und die Section-Trennung läuft rein über Spacing + Card-Gewicht,
    /// nicht mehr über einen zweiten Section-Titel. Die VStack-Hülle
    /// bleibt erhalten, damit der Rhythmus zu den anderen Sektionen
    /// stabil bleibt.
    private var vocabularyDetailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                vocabularyDetailCard(
                    category: .topic,
                    title: "Nach Themen",
                    systemImage: "tag.fill"
                )
                vocabularyDetailCard(
                    category: .level,
                    title: "Nach Niveau",
                    systemImage: "chart.bar.fill"
                )
                vocabularyDetailCard(
                    category: .own,
                    title: "Eigene Listen",
                    systemImage: "person.fill"
                )
                // „Ganzes Wörterbuch" → „Wörterbuch" (User-Request:
                // „Ganzes weglassen, nur Wörterbuch schreiben"). Die
                // Card verweist weiterhin auf denselben All-in-One-
                // Listen-Pool — nur das Label wird kompakter.
                vocabularyDetailCard(
                    category: .all,
                    title: "Wörterbuch",
                    systemImage: "book.fill"
                )
            }
        }
    }

    /// Section-Header — Titel + optionale Subline. Vereinheitlicht den Look
    /// beider Vokabel-Setup-Sektionen (Modus + Detail). Subline ist
    /// optional: ist sie `nil`, rendert nur der Titel — so kann die
    /// Modus-Sektion ohne Subline auskommen, die Detail-Sektion aber
    /// weiterhin die kurze Orientierungszeile mitnehmen.
    private func vocabularySectionTitle(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Eine der zwei Haupt-Modus-Cards (Vokabeltraining / Speed Round).
    /// Speed-Round-Card blendet zusätzlich eine kompakte XP/Zeit/Credits-
    /// Zeile ein (ersetzt die frühere Gamification-Bar am Screen-Bottom).
    ///
    /// `subtitle` ist optional — die Speed-Round-Card nutzt `nil`, weil
    /// die Mini-Metriken inline (+XP/Zeit/Credits) das Speed-Versprechen
    /// konkreter tragen als Marketing-Prosa. Die Vokabeltraining-Card
    /// behält ihre Subline („Gezielt lernen und behalten"), um den
    /// Kontrast zwischen den beiden Modi sichtbar zu machen.
    @ViewBuilder
    /// Modus-Card für Drill-Module — schlankere Variante der früheren
    /// `vocabularyModeCard` ohne die Vokabeln-spezifischen Inline-
    /// Metriken. Tap setzt `session.isSpeedRound` und spielt Tap-Sound.
    /// Layout: Icon-Puck oben, Titel + optionaler Subtext darunter.
    /// Beide Cards bekommen dieselbe Min-Höhe, damit der Modus-Block
    /// über alle Drill-Module identisch aussieht.
    private func drillModeCard(
        isSpeedRound: Bool,
        title: String,
        subtitle: String?,
        systemImage: String
    ) -> some View {
        let isSelected = (session.isSpeedRound == isSpeedRound)

        // `subtitle` ist per User-Spec entfallen („Gezielt üben und behalten"
        // + „30 Sekunden Tempo" sind raus). Parameter bleibt in der API,
        // wird intern aber ignoriert — Call-Sites müssen nicht angefasst
        // werden, falls später wieder eine Subline gebraucht wird.
        _ = subtitle

        return Button {
            feedbackPlayer.playTabSwitch()
            session.isSpeedRound = isSpeedRound
        } label: {
            VStack(alignment: .center, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(trainingActionTint.opacity(isSelected ? 0.28 : 0.16))
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(trainingActionTint)
                }
                .frame(width: 38, height: 38)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .center)

                Text(title)
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
            // minHeight auf 92 pt — identisch zur Nomen-Answer-Mode-Card
            // darunter (Sprache / Wortauswahl). Das Modus-Cards-Paar und
            // das Answer-Cards-Paar wirken dadurch als einheitliche
            // 2-Spalten-Reihen gleicher Höhe.
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .top)
            .background(vocabularyModeCardBackground(isSelected: isSelected))
            .overlay(vocabularyModeCardBorder(isSelected: isSelected))
            .shadow(
                color: Color.black.opacity(isSelected ? 0.28 : 0.18),
                radius: isSelected ? 8 : 5,
                x: 0,
                y: isSelected ? 4 : 2
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // Legacy `vocabularyModeCard` (inkl. Speed-Round-Inline-Metriken)
    // wurde beim Flow-Modul-Refactor Vokabeln komplett abgelöst — die
    // aktuelle `drillModeCard` oben deckt alle Drill-Module ab. Der
    // frühere Stub wurde entfernt, um Dead-Code + Warn-Noise zu
    // vermeiden.

    /// Inline-Mini-Metriken für die Speed-Round-Card. Zeigt XP/Dauer/
    /// Credits als eine Zeile „+225 XP · ~3 min · +4". Holt die Werte aus
    /// `speedRoundPreviewEstimate` (immer Speed-Round-Annahme, unabhängig
    /// vom aktuell gewählten Modus — so weiß der Nutzer, was ihn erwartet,
    /// wenn er Speed Round tappt).
    private var vocabularySpeedRoundInlineMetrics: some View {
        let estimate = speedRoundPreviewEstimate
        var parts: [String] = []
        if estimate.expectedXP > 0 {
            parts.append("+\(estimate.expectedXP) XP")
        }
        if let minutes = estimate.estimatedMinutes {
            parts.append("~\(minutes) min")
        }
        if let credits = estimate.estimatedCreditsText {
            parts.append("\(credits)")
        }
        let text = parts.isEmpty ? " " : parts.joined(separator: "  ·  ")

        return Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    private func vocabularyModeCardBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(trainingActionTint.opacity(isSelected ? AppTheme.CardIntensity.medium : AppTheme.CardIntensity.gentle))
            )
    }

    private func vocabularyModeCardBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
            .stroke(
                isSelected ? trainingActionTint : AppTheme.Colors.border,
                lineWidth: isSelected ? 2 : 1
            )
    }

    /// Sekundäre Detail-Card (eine von vier im 2×2-Grid). Visuell deutlich
    /// ruhiger als die Modus-Cards: kleineres Icon, kein Shadow, reduzierter
    /// Tint — damit die Hierarchie (Modus-Entscheidung > Detail) liest.
    @ViewBuilder
    private func vocabularyDetailCard(
        category: ListPickerCategory,
        title: String,
        systemImage: String
    ) -> some View {
        // Sublines sind pro User-Request komplett raus:
        //   • „Strukturiert lernen" (Themen)
        //   • „Dein passendes Level" (Niveau)
        //   • „Deine erstellten Listen" (Eigene)
        //   • „Alle Vokabeln" (Wörterbuch)
        // Die Cards tragen jetzt nur noch Titel + Icon — keine zweite
        // Text-Ebene mehr. Die Beschreibung/Beispiele (was genau hinter
        // „Themen" / „Niveau" steckt) liefert das anschließende Picker-
        // Sheet, nicht die Startcard. Parameter `subtitle` ist gestrichen,
        // weil kein Call-Site sie noch setzt.
        Button {
            feedbackPlayer.playTabSwitch()
            if category == .all {
                if let allList = filteredLists(for: .all).first {
                    session.selectedTrainingListIDs = [allList.id]
                }
            } else {
                listPickerCategory = category
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                // Icon-Puck — kleiner als bei den Modus-Cards (36 vs 44) und
                // links angeordnet, damit die Card sich als „Listen-Row"
                // liest, nicht als Haupt-Action.
                ZStack {
                    Circle()
                        .fill(trainingActionTint.opacity(0.14))
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(trainingActionTint)
                }
                .frame(width: 32, height: 32)

                // Title-Font: 13 → **14** pt (+1, User-Request „weiße
                // Schrift in den 4 Cards alle +1 p"). Bleibt `.bold`,
                // bleibt `.rounded` — die Cards lesen sich dadurch
                // minimal kräftiger, ohne visuell zu springen. Subline
                // fällt weg, deshalb nutzt der Titel jetzt die ganze
                // Card-Höhe allein.
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                            .fill(trainingActionTint.opacity(AppTheme.CardIntensity.subtle))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.border.opacity(0.7), lineWidth: 1)
            )
            // Absichtlich KEIN Shadow — sekundäre Cards sollen flacher wirken
            // als die Modus-Cards darüber (Hierarchie-Signal).
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - Round Complete View

    private var roundCompleteView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "star.circle.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(AppTheme.Colors.warning)

            Text("Runde \(session.completedRound) geschafft!")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("\(session.preparedTrainingItems.count) \(trainingItemLabel) durchgearbeitet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer()

            Button {
                feedbackPlayer.playStudySuccess()
                session.continueNextRound()
            } label: {
                Text("Weiter \u{2192} Runde \(session.completedRound + 1)")
                    .font(AppTheme.Typography.button)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(AppTheme.Colors.cta)
                    .cornerRadius(AppTheme.Radius.md)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, trainingSessionCardInset)

            Button {
                handleTopBarBack()
            } label: {
                Label("Zur\u{00FC}ck", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textSecondary))
            .padding(.horizontal, trainingSessionCardInset)

            Spacer().frame(height: 8)
        }
        .onAppear {
            feedbackPlayer.playStudyAchievement()
        }
    }

    // MARK: - Verb Content Type Selector (Verben / Phrasen)

    private var verbContentTypeSelector: some View {
        HStack(spacing: 10) {
            ForEach([CardType.words, CardType.phrases], id: \.self) { type in
                Button {
                    session.cardType = type
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: type == .words ? "textformat" : "text.quote")
                            .font(.system(size: 16, weight: .bold))
                        Text(type == .words ? "Verben" : "Phrasen")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .foregroundStyle(session.cardType == type ? .white : AppTheme.Colors.textPrimary)
                    .background(session.cardType == type ? trainingActionTint : AppTheme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(session.cardType == type ? trainingActionTint : AppTheme.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Verbformen Setup Options

    /// Custom Listen-Auswahl-Card für Verbformen — Speed-Round-Stil.
    /// Bei Mehrfachauswahl werden ALLE gewählten Listen untereinander angezeigt
    /// (max. 5 lt. App-Limit), darunter die Gesamt-Anzahl Verben.
    private var verbformsListSelectionCard: some View {
        let selectedIDs = session.selectedTrainingListIDs
        let selectedLists = availableTrainingLists.filter { selectedIDs.contains($0.id) }
        let hasSelection = !selectedLists.isEmpty
        let lemmas = verbformsLemmasFromSelectedLists()
        let verbformsCount = lemmas.count

        return Button {
            feedbackPlayer.playTabSwitch()
            verbformsListPickerActive = true
        } label: {
            // Header GANZ links oben + HStack mit Icon, Listen, Stift-Pill —
            // analog zum Karteikarten-Setup (siehe `setupListSelectionCard`).
            VStack(alignment: .leading, spacing: 8) {
                setupCardLabel("Ausgewählte Listen")

                HStack(alignment: .center, spacing: 14) {
                    // Home-Listen-Icon — identisch zur "Listen"-Kachel auf
                    // dem Home-Screen (Asset `HomeIconListen`). Systemweit
                    // identisches Icon für „Ausgewählte Listen" statt des
                    // früheren SF-Symbols `list.bullet.rectangle.fill`.
                    HomeModuleIconView(icon: .listen, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        if hasSelection {
                            // Pro-Liste-Row: nur der Name. Die frühere „X Einträge"-
                            // Zahl rechts ist raus — die Gesamt-Summary
                            // („N Verben gesamt") darunter sagt das gleiche und
                            // in kompakter. Doppelung entfernt, Card wirkt ruhiger.
                            ForEach(selectedLists.prefix(AppLayout.maxSelectableLists)) { list in
                                Text(list.name)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            // **Phase 5 (2026-05-04)** — Summary mit optionalem
                            // LJ-Range. Ohne Range: „X Verben gesamt", mit Range:
                            // „LJ 1-N · X Verben gesamt".
                            let verbformsTotal = "\(verbformsCount) Verb\(verbformsCount == 1 ? "" : "en") gesamt"
                            let verbformsSummary: String = {
                                if let range = VocabularyListSelectionResolver.lernjahrRangeLabel(forSelectedLists: selectedLists) {
                                    return "\(range) · \(verbformsTotal)"
                                }
                                return verbformsTotal
                            }()
                            Button {
                                feedbackPlayer.playTabSwitch()
                                verbformsVerbDetailActive = true
                            } label: {
                                Text(verbformsSummary)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                                    .underline(true, color: AppTheme.Colors.elumiBlue.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        } else {
                            Text("Keine Liste gewählt")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text("Tippe zum Auswählen")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.elumiBlue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Systemweit: Stift-Pill 16/38, vertikal mittig
                    // durch äußeren `frame(maxHeight: .infinity)` —
                    // HStack-Center allein reichte nicht, wenn die
                    // VStack nebenan asymmetrisches Padding hat.
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(trainingActionTint)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(trainingActionTint.opacity(0.18))
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
        .sheet(isPresented: $verbformsListPickerActive) {
            // **Phase 3 (2026-05-04)** — Migration auf
            // `GlobalListPickerSheet` für Verbformen.
            GlobalListPickerSheet(
                allLists: availableTrainingLists,
                initialSelection: session.selectedTrainingListIDs,
                onCommit: { updated in
                    session.selectedTrainingListIDs = updated
                    verbformsListPickerActive = false
                },
                categoryHeaders: false,
                feedbackPlayer: feedbackPlayer,
                onHome: goHome
            )
        }
        .sheet(isPresented: $verbformsVerbDetailActive) {
            VerbLemmaListSheet(lemmas: verbformsLemmasFromSelectedLists())
        }
    }

    /// Berechnet die Lemma-Liste für die Setup-Card abhängig vom Trainings-Modus.
    /// Die expensive `FrenchListStatisticsAggregator.cachedStatistics`-Berechnung
    /// läuft auf einem Background-Thread (`Task.detached`), das Ergebnis wird
    /// per `MainActor.run` in `setupCardLemmas` zurückgespielt — verhindert
    /// UI-Freeze beim Öffnen oder bei Selection-Wechsel.
    func refreshSetupCardLemmas() {
        let mode = session.trainingMode
        guard mode != .vocabulary else {
            setupCardLemmas = []
            setupCanStartCached = false
            return
        }
        let selectedIDs = session.selectedTrainingListIDs
        let lists = availableTrainingLists.filter { selectedIDs.contains($0.id) }
        let lang = selectedAppDirection.sourceLanguage
        let items = lists.flatMap(\.items).filter { $0.sourceLanguage == lang }

        guard !items.isEmpty else {
            setupCardLemmas = []
            setupCanStartCached = false
            return
        }

        Task.detached(priority: .userInitiated) {
            let stats = FrenchListStatisticsAggregator.cachedStatistics(for: items)
            let lemmas: [String]
            switch mode {
            case .verbforms, .verbs:
                lemmas = stats.verbLemmas
            case .nouns, .articles:
                lemmas = stats.nounLemmas
            case .vocabulary:
                lemmas = []
            }
            let canStart = !lemmas.isEmpty
            await MainActor.run {
                setupCardLemmas = lemmas
                setupCanStartCached = canStart
            }
        }
    }

    /// Anzahl eindeutiger Nomen-Lemmata aus der Listen-Analyse — Pendant zu
    /// `verbformsLemmasFromSelectedLists()`. Wird in der Listen-Card der
    /// Module „Nomen" und „Artikel" als Anzeige verwendet.
    func nounsLemmasFromSelectedLists() -> [String] {
        let selectedIDs = session.selectedTrainingListIDs
        guard !selectedIDs.isEmpty else { return [] }
        let lists = availableTrainingLists.filter { selectedIDs.contains($0.id) }
        let items = lists.flatMap(\.items)
            .filter { $0.sourceLanguage == selectedAppDirection.sourceLanguage }
        let stats = FrenchListStatisticsAggregator.cachedStatistics(for: items)
        return stats.nounLemmas
    }

    /// Generischer Helper für die Listen-Auswahl-Card im Speed-Round-Stil.
    /// Nutzt Listen aus `session.selectedTrainingListIDs`. Zeigt alle gewählten
    /// Listen untereinander (max. 5), darunter den `countLabel`-Text mit
    /// `countValue`. Optionaler Tap-Handler auf den Counter (Detail-Sheet).
    @ViewBuilder
    private func setupListSelectionCard(
        countLabel: String,
        countValue: Int,
        onTapPicker: @escaping () -> Void,
        onTapCounter: (() -> Void)? = nil
    ) -> some View {
        let selectedIDs = session.selectedTrainingListIDs
        let selectedLists = availableTrainingLists.filter { selectedIDs.contains($0.id) }
        let hasSelection = !selectedLists.isEmpty

        Button {
            feedbackPlayer.playTabSwitch()
            onTapPicker()
        } label: {
            // Header GANZ links oben + HStack mit Icon, Listen, Stift-Pill —
            // analog zum Karteikarten-Setup. Single Source of Truth: nutzt
            // `setupCardLabel` und `appSetupCardBackground` aus AppViewModifiers.
            VStack(alignment: .leading, spacing: 8) {
                setupCardLabel("Ausgewählte Listen")

                HStack(alignment: .center, spacing: 14) {
                    // Home-Listen-Icon — identisch zur "Listen"-Kachel auf
                    // dem Home-Screen (Asset `HomeIconListen`). Systemweit
                    // identisches Icon für „Ausgewählte Listen" statt des
                    // früheren SF-Symbols `list.bullet.rectangle.fill`.
                    HomeModuleIconView(icon: .listen, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        if hasSelection {
                            // Pro-Liste-Row: nur der Name. Die frühere „X Einträge"-
                            // Zahl rechts ist raus — die Gesamt-Summary
                            // („N Liste(n) · M … gesamt") darunter sagt das gleiche
                            // in kompakter. Doppelung entfernt, Card wirkt ruhiger.
                            ForEach(selectedLists.prefix(AppLayout.maxSelectableLists)) { list in
                                Text(list.name)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            // Gesamt-Summary in elumiBlue (Info-Token, konsistent
                            // mit Karteikarten-Setup). Klickbar wenn Counter-
                            // Handler übergeben.
                            // **Phase 5 (2026-05-04)** — optionales LJ-Range-Insert,
                            // wenn cumulative-Liste mit aktivem Filter selektiert.
                            let listsText = "\(selectedLists.count) Liste\(selectedLists.count == 1 ? "" : "n")"
                            let totalText = "\(countValue) \(countLabel) gesamt"
                            let summary: String = {
                                if let range = VocabularyListSelectionResolver.lernjahrRangeLabel(forSelectedLists: selectedLists) {
                                    return "\(listsText) · \(range) · \(totalText)"
                                }
                                return "\(listsText) · \(totalText)"
                            }()
                            if let onTapCounter {
                                Button {
                                    feedbackPlayer.playTabSwitch()
                                    onTapCounter()
                                } label: {
                                    Text(summary)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.elumiBlue)
                                        .underline(true, color: AppTheme.Colors.elumiBlue.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 2)
                            } else {
                                Text(summary)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                                    .padding(.top, 2)
                            }
                        } else {
                            Text("Keine Liste gewählt")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text("Tippe zum Auswählen")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.elumiBlue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Stift in rundem Pill — dezent, konsistent mit Karteikarten.
                    // Systemweit: Stift-Pill 16/38, vertikal mittig
                    // durch äußeren `frame(maxHeight: .infinity)` —
                    // HStack-Center allein reichte nicht, wenn die
                    // VStack nebenan asymmetrisches Padding hat.
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(trainingActionTint)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(trainingActionTint.opacity(0.18))
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

    /// Custom Listen-Auswahl-Card für Verben — Speed-Round-Stil mit klickbarer
    /// Verben-Anzahl. Counter aus gecachtem `setupCardLemmas` (wird via
    /// onChange aktualisiert, nicht pro Render).
    private var verbsListSelectionCard: some View {
        setupListSelectionCard(
            countLabel: "Verben",
            countValue: setupCardLemmas.count,
            onTapPicker: { verbsListPickerActive = true },
            onTapCounter: { verbsVerbDetailActive = true }
        )
        .sheet(isPresented: $verbsListPickerActive) {
            // **Phase 3 (2026-05-04)** — Migration auf `GlobalListPickerSheet`.
            GlobalListPickerSheet(
                allLists: availableTrainingLists,
                initialSelection: session.selectedTrainingListIDs,
                onCommit: { updated in
                    session.selectedTrainingListIDs = updated
                    verbsListPickerActive = false
                },
                categoryHeaders: false,
                feedbackPlayer: feedbackPlayer,
                onHome: goHome
            )
        }
        .sheet(isPresented: $verbsVerbDetailActive) {
            VerbLemmaListSheet(lemmas: setupCardLemmas)
        }
    }

    /// Custom Listen-Auswahl-Card für Nomen — Speed-Round-Stil, ohne Detail-Sheet
    /// auf der Anzahl (User wollte nur Anzeige). Counter aus gecachtem State.
    private var nounsListSelectionCard: some View {
        setupListSelectionCard(
            countLabel: "Nomen",
            countValue: setupCardLemmas.count,
            onTapPicker: { nounsListPickerActive = true },
            onTapCounter: nil
        )
        .sheet(isPresented: $nounsListPickerActive) {
            // **Phase 3 (2026-05-04)** — Migration auf `GlobalListPickerSheet`.
            GlobalListPickerSheet(
                allLists: availableTrainingLists,
                initialSelection: session.selectedTrainingListIDs,
                onCommit: { updated in
                    session.selectedTrainingListIDs = updated
                    nounsListPickerActive = false
                },
                categoryHeaders: false,
                feedbackPlayer: feedbackPlayer,
                onHome: goHome
            )
        }
    }

    /// Custom Listen-Auswahl-Card für Artikel — gleiche Anzeige wie Nomen.
    private var articlesListSelectionCard: some View {
        setupListSelectionCard(
            countLabel: "Nomen",
            countValue: setupCardLemmas.count,
            onTapPicker: { articlesListPickerActive = true },
            onTapCounter: nil
        )
        .sheet(isPresented: $articlesListPickerActive) {
            // **Phase 3 (2026-05-04)** — Migration auf `GlobalListPickerSheet`.
            GlobalListPickerSheet(
                allLists: availableTrainingLists,
                initialSelection: session.selectedTrainingListIDs,
                onCommit: { updated in
                    session.selectedTrainingListIDs = updated
                    articlesListPickerActive = false
                },
                categoryHeaders: false,
                feedbackPlayer: feedbackPlayer,
                onHome: goHome
            )
        }
    }

    private var verbformsSetupOptions: some View {
        // Zeit-Auswahl-Card im Karteikarten-Setup-Stil:
        // Links das Uhr-Icon (Modul-Akzent, vertikal zentriert), rechts die
        // 4 Tense-Buttons als 2x2-Raster. Buttons im Mastery-Look
        // (#1A2A40 inaktiv / #1A3A55 + elumiBlue Border aktiv).
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(trainingActionTint)
                .frame(width: 40, alignment: .center)

            let columns = [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(VerbformsTense.allCases) { tense in
                    verbformsTenseButton(for: tense)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private func verbformsTenseButton(for tense: VerbformsTense) -> some View {
        let isActive = tense.isAvailable
        let isSelected = verbformsSession.selectedTenses.contains(tense)
        return Button {
            guard isActive else { return }
            if isSelected {
                if verbformsSession.selectedTenses.count > 1 {
                    verbformsSession.selectedTenses.remove(tense)
                }
            } else {
                verbformsSession.selectedTenses.insert(tense)
            }
        } label: {
            Text(tense.rawValue)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color(hex: "#1A3A55") : Color(hex: "#1A2A40"))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected
                                ? AppTheme.Colors.elumiBlue
                                : Color(hex: "#243B55"),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
                .opacity(isActive ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
    }

    // MARK: - Verbformen Session Screen

    var verbformsSessionScreen: some View {
        VStack(spacing: 12) {
            // Kompakter Header analog Karteikarten — Zurück resettet die
            // Verbformen-Session und führt zurück zur Setup-Card, nicht raus
            // zu Home. ScreenHeaderCard + großer Zurück-Button entfernt.
            //
            // **Chain-Mode Back-Chevron (2026-05-02)** — im Chain-Mode
            // POPpen wir die Modul-Route stattdessen → Pre-Screen
            // sichtbar (Setup-Skip-Spec-Konsistenz mit den anderen 4
            // Modulen). XP wird idempotent vergeben (`sessionRewardConsumed`-
            // Schutz), Speed-Round-Timer + TTS + Mikro werden vor
            // dem Pop sauber gestoppt. Der `verbformsSession.reset()`-
            // Pfad wird im Chain bewusst übersprungen — die View wird
            // ohnehin gepopt, und ein Reset würde durch das `.onChange(of:
            // verbformsSession.isFinished)` zusätzliche State-
            // Mutations triggern.
            trainingHeaderShared {
                if launchContext?.chainContext != nil {
                    awardVerbformsXPIfNeeded()
                    verbformsSession.stopSpeedRoundTimer()
                    verbformsCountdown = nil
                    runtimeSpeaker?.stop()
                    speechController?.stopRecording()
                    dismiss()
                } else {
                    verbformsSession.reset()
                    verbformsCountdown = nil
                }
            }

            if let countdown = verbformsCountdown {
                // 3-2-1 Countdown
                Spacer()
                Text("\(countdown)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(trainingActionTint)
                    .transition(.scale.combined(with: .opacity))
                Spacer()
            } else if verbformsSession.isSpeedRound {
                // Speed Round Timer
                verbformsSpeedRoundBar
                verbformsActiveContent
            } else if verbformsSession.isShowingRoundComplete {
                // Runde abgeschlossen → Gratulation + Weitermachen / Fertig
                verbformsRoundCompleteView
            } else {
                // Runden-Anzeige rechts oben — Counter „X/Y" weggelassen,
                // weil der Status unten im Weiter-Button den Fortschritt zeigt.
                HStack {
                    Spacer()
                    Text("Runde \(verbformsSession.completedRound)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text("·")
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text("\(verbformsSession.score) richtig")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 4)
                verbformsActiveContent
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 16)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Colors.background.ignoresSafeArea())
    }

    /// Zeigt je nach Modus das Matching-Grid (Drag&Drop) oder den Typing-Input.
    @ViewBuilder
    var verbformsActiveContent: some View {
        if verbformsSession.mode == .multipleChoice,
           let round = verbformsSession.currentMatching {
            verbformsMatchingContent(round: round)
        } else if let question = verbformsSession.currentQuestion {
            verbformsTypingQuestionContent(question: question)
        }
    }

    // MARK: - Drag & Drop Matching (Auswählen-Modus)

    /// Einheitliche Farbe für alle 6 Pronomen-Chips — das Verbformen-Purple
    /// des Moduls. Keine Variationen, damit keine Positions-/Farb-Hints
    /// auf die Lösung entstehen.
    static let verbformsPronounColor = Color(hue: 0.72, saturation: 0.55, brightness: 0.78)

    /// Einheitliche Farbe für alle 6 Form-Karten — ein sattes Blau.
    /// Absichtlich NICHT grün (= richtig) und NICHT orange (= falsch), damit
    /// die Feedback-Farben eindeutig bleiben. Klar vom Purple unterscheidbar.
    static let verbformsFormColor = Color(hue: 0.58, saturation: 0.55, brightness: 0.80)

    /// Aktuell vom DragGesture überfahrene Form-Karte (für Hover-Highlight).
    /// WICHTIG: Filter NICHT per matched-Anchor — bei N-zu-1 müssen mehrere
    /// Pronomen nacheinander auf dieselbe Form-Card gedroppt werden können
    /// (z.B. je, il und elles alle auf „parle"). `dropPronoun` validiert
    /// selbst, ob das Pronomen zur Form passt.
    func verbformsHoveredFormPerson(for pronoun: VerbformsPerson) -> VerbformsPerson? {
        guard let pronounFrame = verbformsPronounFrames[pronoun] else { return nil }
        let dragged = CGPoint(
            x: pronounFrame.midX + verbformsDragOffset.width,
            y: pronounFrame.midY + verbformsDragOffset.height
        )
        return verbformsFormFrames.first(where: { _, frame in
            frame.contains(dragged)
        })?.key
    }

    /// Beendet eine Drag-Geste: prüft welche Form-Karte unter dem Cursor liegt
    /// und ruft `dropPronoun` im Session-Controller auf. Setzt Drag-State zurück.
    func verbformsFinishDrag(for pronoun: VerbformsPerson) {
        let target = verbformsHoveredFormPerson(for: pronoun)
        if let target {
            let correct = verbformsSession.dropPronoun(pronoun, onForm: target)
            if correct {
                feedbackPlayer.playStudySuccess()
            } else {
                feedbackPlayer.playStudyError()
            }
        }
        // Snap zurück (egal ob richtig oder falsch — bei richtig wird der Chip
        // ohnehin ausgeblendet, bei falsch springt er optisch in seine Grid-Position)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            verbformsDragOffset = .zero
        }
        verbformsDraggingPronoun = nil
        verbformsHoveredForm = nil
    }

    @ViewBuilder
    private func verbformsMatchingContent(round: VerbformsMatchingRound) -> some View {
        // Fragekarte: Infinitiv + Tempus + gefragte Form („1. Person Plural" etc.)
        VStack(spacing: 8) {
            Text(round.infinitive)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            if !round.translation.isEmpty {
                Text("(\(round.translation))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Text(round.tense.rawValue)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(trainingActionTint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(trainingActionTint.opacity(0.12))
                .clipShape(Capsule())

            // Gefragte Person als zentrale „Fragestellung" — Font 19pt
            // (kräftig in Akzentfarbe).
            if let nextPerson = verbformsSession.nextTargetPerson {
                Text(nextPerson.promptLabel)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(trainingActionTint)
                    .padding(.top, 2)
            } else {
                Text("Alle Paare gefunden!")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.success)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)

        // Engerer Abstand zwischen Fragekarte und Pronomen-Grid, damit
        // der größere Spacing zwischen Pronomen-Grid und Form-Grid (+12)
        // das Form-Grid nicht nach unten verschiebt → Weiter-Button bleibt
        // an der gleichen Position.
        Spacer().frame(height: 0)

        let pronounColumns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        // Drag/Drop-Container: gemeinsamer coordinateSpace + Frame-Tracking
        // Spacing 18 zwischen Pronomen- und Form-Grid → klare visuelle Trennung
        // zwischen „oben Pronomen" und „unten Verbformen".
        VStack(spacing: 18) {
            // Draggable pronouns (2×3) in gemischter Reihenfolge
            LazyVGrid(columns: pronounColumns, spacing: 10) {
                ForEach(verbformsSession.shuffledPronouns, id: \.self) { person in
                    verbformsPronounChip(person: person)
                }
            }

            // Form-Slots (2×3): pro eindeutiger Form eine Karte, Rest leere
            // Platzhalter-Slots, sodass die Grid-Struktur immer stabil ist.
            LazyVGrid(columns: pronounColumns, spacing: 10) {
                ForEach(Array(verbformsSession.displayedFormSlots.enumerated()), id: \.offset) { _, slot in
                    if let anchorPerson = slot {
                        verbformsFormTarget(person: anchorPerson, round: round)
                    } else {
                        verbformsFormPlaceholder()
                    }
                }
            }
        }
        .coordinateSpace(name: "verbformsMatchingArea")
        .onPreferenceChange(VerbformsPronounFramePreferenceKey.self) { frames in
            verbformsPronounFrames = frames
        }
        .onPreferenceChange(VerbformsFormFramePreferenceKey.self) { frames in
            verbformsFormFrames = frames
        }

        // Weiter-Button — IMMER sichtbar während der Runde.
        // - Bevor das erste Paar gelöst ist: grau, disabled, Status-Text mit
        //   noch zu lösenden Paaren (max 6).
        // - Sobald die richtige Card abgelegt wurde (= mind. 1 Drop korrekt):
        //   orange CTA „Weiter", aktiv → Klick führt zur nächsten Verbform.
        if verbformsSession.currentMatching != nil,
           !verbformsSession.isSpeedRound,
           !verbformsSession.isShowingRoundComplete,
           verbformsCountdown == nil {
            let canContinue = verbformsSession.matchedPersons.count > 0
            let remaining = verbformsSession.remainingItemsInRound
            Button {
                guard canContinue else { return }
                feedbackPlayer.playStudySuccess()
                // **Stufe 4b-5 (2026-05-02)** — Chain-Timer-aware
                // Wrapper. Bei abgelaufenem Chain-Timer wird Force-
                // Done getriggert, sonst Pass-through.
                handleVerbformsNext()
            } label: {
                Text(canContinue ? "Weiter" : "Noch \(remaining) zu lösen")
                    .font(AppTheme.Typography.button)
                    .foregroundColor(canContinue ? .black : AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(canContinue ? AppTheme.Colors.cta : AppTheme.Colors.secondarySurface)
                    .cornerRadius(AppTheme.Radius.md)
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
            .padding(.top, 0)
            .animation(.easeInOut(duration: 0.2), value: canContinue)
        }
    }

    /// Leerer Form-Slot — sichtbar als gestrichelter Rahmen, hält die
    /// 2×3-Grid-Struktur stabil, wenn ein Verb weniger als 6 unterschiedliche
    /// Formen hat (z.B. -er-Präsens mit je=il=elles → 5 Forms + 1 Platzhalter).
    @ViewBuilder
    private func verbformsFormPlaceholder() -> some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
            .strokeBorder(
                AppTheme.Colors.border.opacity(0.4),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
    }

    // MARK: - Verbformen Round-Complete View

    private var verbformsRoundCompleteView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "star.circle.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(AppTheme.Colors.warning)

            Text("Runde \(verbformsSession.completedRound) geschafft!")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("\(verbformsSession.score) von \(verbformsSession.totalAsked) Zuordnungen richtig")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer()

            Button {
                feedbackPlayer.playStudySuccess()
                verbformsSession.continueToNextRound()
            } label: {
                Text("Weiter \u{2192} Runde \(verbformsSession.completedRound + 1)")
                    .font(AppTheme.Typography.button)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(AppTheme.Colors.cta)
                    .cornerRadius(AppTheme.Radius.md)
            }
            .buttonStyle(.plain)

            Button {
                verbformsSession.finishTraining()
            } label: {
                Label("Fertig", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textSecondary))

            Spacer().frame(height: 8)
        }
    }

    /// Pronomen-Chip als Drag-Source — manuelle DragGesture (kein Long-Press),
    /// Quiz-Stil. Beim Drag-Update wird der Hover über Form-Karten live berechnet,
    /// beim Drag-Ende erfolgt Drop-Validation via `verbformsFinishDrag`.
    @ViewBuilder
    private func verbformsPronounChip(person: VerbformsPerson) -> some View {
        let isUsed = verbformsSession.usedPronouns.contains(person)
        let tint = Self.verbformsPronounColor
        let isDragging = verbformsDraggingPronoun == person

        Text(person.label)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .foregroundStyle(.white)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(isUsed ? 0.0 : 1.0)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .shadow(color: isDragging ? tint.opacity(0.5) : .clear,
                    radius: isDragging ? 12 : 0, x: 0, y: isDragging ? 6 : 0)
            .offset(isDragging ? verbformsDragOffset : .zero)
            .zIndex(isDragging ? 100 : 0)
            .animation(.easeOut(duration: 0.25), value: isUsed)
            .allowsHitTesting(!isUsed)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: VerbformsPronounFramePreferenceKey.self,
                        value: [person: geo.frame(in: .named("verbformsMatchingArea"))]
                    )
                }
            )
            .gesture(
                DragGesture(coordinateSpace: .named("verbformsMatchingArea"))
                    .onChanged { value in
                        guard !isUsed else { return }
                        verbformsDraggingPronoun = person
                        verbformsDragOffset = value.translation
                        verbformsHoveredForm = verbformsHoveredFormPerson(for: person)
                    }
                    .onEnded { _ in
                        guard !isUsed else { return }
                        verbformsFinishDrag(for: person)
                    }
            )
    }

    /// Form-Karte als Drop-Target. Default-Farbe Blau, Match → grün (sobald
    /// mindestens eine passende Person gedropped), Wrong-Flash → orange.
    @ViewBuilder
    private func verbformsFormTarget(person: VerbformsPerson, round: VerbformsMatchingRound) -> some View {
        let form = round.forms[person] ?? "?"
        let sharedPersons = verbformsSession.personsSharingForm(with: person)
        let isMatched = sharedPersons.contains(where: { verbformsSession.matchedPersons.contains($0) })
        let isFlashWrong = verbformsSession.wrongFlashTarget == person
        let isHovered = verbformsHoveredForm == person

        let bg: Color = {
            if isMatched { return AppTheme.Colors.success }
            if isFlashWrong { return Color(red: 0.95, green: 0.55, blue: 0.15) }
            return Self.verbformsFormColor
        }()

        // Form-Card zeigt NUR die Verbform (keine Subjekt-Pronomen).
        Text(form)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .lineLimit(2)
            .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .padding(.horizontal, 6)
        .foregroundStyle(.white)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(isHovered ? Color.white : Color.white.opacity(0.25),
                        lineWidth: isHovered ? 2.5 : 1)
        )
        .scaleEffect(isHovered && !isMatched ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.18), value: isMatched)
        .animation(.easeInOut(duration: 0.18), value: isFlashWrong)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: VerbformsFormFramePreferenceKey.self,
                    value: [person: geo.frame(in: .named("verbformsMatchingArea"))]
                )
            }
        )
    }

    // MARK: - Typing-Modus-Frage (alt: verbformsQuestionContent)

    @ViewBuilder
    private func verbformsTypingQuestionContent(question: VerbformsQuestion) -> some View {
        // Verb card — Infinitiv + Übersetzung + Person/Zeit
        VStack(spacing: 10) {
            Text(question.infinitive)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            if !question.translation.isEmpty {
                Text("(\(question.translation))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            HStack(spacing: 8) {
                Text(question.person.promptLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(trainingActionTint)
                    .clipShape(Capsule())
                Text(question.tense.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.Colors.secondarySurface)
                    .clipShape(Capsule())
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)

        verbformsTypingInput(question: question)

        if verbformsSession.isLocked, !verbformsSession.isSpeedRound {
            Spacer(minLength: 8)
            Button {
                // **Stufe 4b-5 (2026-05-02)** — Chain-Timer-aware
                // Wrapper, siehe oberen Aufruf in der Multiple-Choice-
                // Variante.
                handleVerbformsNext()
            } label: {
                Text("Weiter")
                    .font(AppTheme.Typography.button)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(trainingActionTint)
                    .cornerRadius(AppTheme.Radius.md)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private func verbformsTypingInput(question: VerbformsQuestion) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(question.person.label)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(trainingActionTint)
                    .frame(width: 70, alignment: .trailing)

                TextField("Verbform eingeben", text: $verbformsSession.typedAnswer)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(verbformsSession.isLocked)
            }

            if !verbformsSession.isLocked {
                Button {
                    verbformsSession.submitTyping()
                    if case .correct = verbformsSession.typingResult {
                        feedbackPlayer.playStudySuccess()
                    } else {
                        feedbackPlayer.playStudyError()
                    }
                } label: {
                    Text("Prüfen")
                        .font(AppTheme.Typography.button)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(verbformsSession.typedAnswer.isEmpty ? AppTheme.Colors.textDisabled : trainingActionTint)
                        .cornerRadius(AppTheme.Radius.md)
                }
                .buttonStyle(.plain)
                .disabled(verbformsSession.typedAnswer.isEmpty)
            }

            if let result = verbformsSession.typingResult {
                switch result {
                case .correct:
                    if let question = verbformsSession.currentQuestion {
                        // Volle Phrase als Bestätigung: „Richtig: je vais"
                        let full = VerbformsEngine.fullConjugation(
                            person: question.person,
                            form: question.correctAnswer
                        )
                        Text("Richtig: \(full)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.success)
                    } else {
                        Text("Richtig!")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.success)
                    }
                case .incorrect(let correctAnswer):
                    // correctAnswer ist die kurze Form (z.B. „vais") — für
                    // das Feedback rekonstruieren wir die volle Phrase.
                    let fullCorrect: String = {
                        guard let question = verbformsSession.currentQuestion else {
                            return correctAnswer
                        }
                        return VerbformsEngine.fullConjugation(
                            person: question.person,
                            form: correctAnswer
                        )
                    }()
                    VStack(spacing: 4) {
                        Text("Fast.")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.9, green: 0.3, blue: 0.15))
                        Text("Die richtige Form ist: \(fullCorrect)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.gentle, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    // MARK: - Verbformen Result Screen

    /// Verbformen-Result: einheitliche `SessionSummaryView` statt früher
    /// separatem Score-Screen. Reward wird bei `onAppear` konsumiert und in
    /// `verbformsSessionOutcome` gespeichert; die Summary zeigt XP-Breakdown,
    /// Credits, Level-Progress analog Karteikarten.
    var verbformsResultScreen: some View {
        VStack(spacing: 16) {
            // **Block 2 (2026-05-02)** — siehe `trainingSummaryScreen`:
            // im Chain-Mode kein Modul-Chevron + Title auf dem Done-
            // Screen. Chain-Header trägt die Schritt-Identität.
            if launchContext?.chainContext == nil {
                trainingSessionCompactHeader
            }

            // **Stufe 3 (2026-05-01)** — Chain-Mode-Branching für
            // Verbformen-Pfad. Verbformen läuft NICHT als
            // `.train(...)` durchs Chain-Mapping, sondern als
            // `HomeHeroModule.verbformen` → `.train(preferredMode:
            // .verbforms, ...)` (siehe `HomeHeroModule.chainScreen`).
            // Erkenntnis: `launchContext?.chainContext` ist also auch
            // hier gesetzt, wenn Verbformen ein Chain-Step ist.
            let verbformsOutcome = verbformsSessionOutcome ?? .empty
            let chain = launchContext?.chainContext
            let nextStepTitle = chain?.nextStep?.title
            let isChain = chain != nil
            let primaryLabel: String = isChain
                ? (nextStepTitle.map { "Weiter zu \($0)" } ?? "Training abschließen")
                : "Weiter lernen"
            SessionSummaryView(
                outcome: verbformsOutcome,
                progress: progressStore.progress,
                primaryCTALabel: primaryLabel,
                onPrimaryCTA: {
                    if isChain {
                        chainAdvance?(verbformsOutcome)
                    } else {
                        verbformsSessionOutcome = nil
                        verbformsSession.reset()
                    }
                },
                secondaryCTALabel: isChain ? nil : "Zur Startseite",
                onSecondaryCTA: isChain ? nil : {
                    dismissToHome()
                },
                primaryCTAPulses: isChain,
                hidesDetailedStats: isChain
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 32)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .onAppear {
            // Zentrale Reward-Vergabe für Verbformen (XP, Credits, Streak).
            // `awardVerbformsXPIfNeeded` ist idempotent via `sessionRewardConsumed`.
            awardVerbformsXPIfNeeded()
            // Session hart stoppen — TTS + Speech-Recognition dürfen
            // nach Summary-Erscheinen nicht weiterlaufen. Timer ist
            // bereits durch `finishSpeedRound()` invalidiert.
            runtimeSpeaker?.stop()
            speechController?.stopRecording()
        }
    }

    // MARK: - Verbformen Speed Round Bar

    private var verbformsSpeedRoundBar: some View {
        // Zentrale `SpeedRoundTimerCard` — teilt Look + Verhalten mit
        // Training und Akzente. Alle Änderungen an Urgency-Farben,
        // Progress-Balken oder Puls-Effekt passieren an genau einer
        // Stelle (`SpeedRoundTimerCard.swift`) und greifen hier mit.
        SpeedRoundTimerCard(
            remainingSeconds: verbformsSession.speedRoundTimeRemaining,
            totalSeconds: verbformsSession.speedRoundTotalSeconds,
            correctCount: verbformsSession.score,
            sectionStyle: sectionStyle
        )
    }

    // MARK: - Verbformen Start

    /// Zentrale Lemma-Quelle für Verbformen — nutzt dieselbe Analyse-Pipeline wie
    /// „Verben trainieren" (FrenchListStatisticsAggregator.verbLemmas).
    /// Damit: gleiche Liste → gleiche Verb-Basis in beiden Modulen.
    /// Liefert Lemmas inkl. reflexiver Form („s'appeler", „se lever").
    func verbformsLemmasFromSelectedLists() -> [String] {
        let selectedIDs = session.selectedTrainingListIDs
        guard !selectedIDs.isEmpty else { return [] }
        let lists = availableTrainingLists.filter { selectedIDs.contains($0.id) }
        let items = lists.flatMap(\.items)
            .filter { $0.sourceLanguage == selectedAppDirection.sourceLanguage }
        let stats = FrenchListStatisticsAggregator.cachedStatistics(for: items)
        return stats.verbLemmas
    }

    /// Kann Verbformen mit der aktuellen Listen-Auswahl gestartet werden?
    var verbformsCanStart: Bool {
        // Nutzt cached Lemma-State (gleich wie canStartTraining), damit der
        // Setup-Body keinen synchronen analyze() pro Render auslöst.
        return setupCanStartCached && !verbformsSession.availableTenses.isEmpty
    }

    /// Hilfetext, der erklärt, warum nicht gestartet werden kann.
    /// Liest aus dem gecachten setupCardLemmas — kein Live-Compute pro Render.
    var verbformsStartHint: String {
        if session.selectedTrainingListIDs.isEmpty {
            return "Wähle zuerst eine Liste aus."
        }
        if setupCardLemmas.isEmpty {
            return "In der gewählten Liste wurden keine Verben erkannt."
        }
        if verbformsSession.availableTenses.isEmpty {
            return "Für die erkannten Verben sind noch keine Konjugationsformen verfügbar."
        }
        return ""
    }

    func loadVerbformsAvailableTenses() {
        let lemmas = verbformsLemmasFromSelectedLists()
        let inflections = lemmas.isEmpty ? [] : VerbformsEngine.loadInflections(forLemmas: lemmas)
        verbformsSession.availableTenses = VerbformsEngine.availableTenses(in: inflections)
        // Auto-select only available tenses
        verbformsSession.selectedTenses = verbformsSession.selectedTenses.intersection(verbformsSession.availableTenses)
        if verbformsSession.selectedTenses.isEmpty, let first = verbformsSession.availableTenses.first {
            verbformsSession.selectedTenses = [first]
        }
    }

    func startVerbformsTraining() {
        // Verben aus den gewählten Listen holen (via Analyse-Pipeline, konsistent
        // mit „Verben trainieren"). Reflexive Lemmas werden im Engine-Lookup
        // auf ihre konjugierte Reflexiv-Form expandiert.
        let lemmas = verbformsLemmasFromSelectedLists()
        guard !lemmas.isEmpty else { return }

        let allInflections = VerbformsEngine.loadInflections(forLemmas: lemmas)
        guard !allInflections.isEmpty else { return }

        verbformsSession.availableTenses = VerbformsEngine.availableTenses(in: allInflections)
        let isSpeed = session.isSpeedRound
        let selectedTenses = verbformsSession.selectedTenses.intersection(verbformsSession.availableTenses)
        guard !selectedTenses.isEmpty else { return }

        // Modus-Weiche: MC-Modus = Drag&Drop-Matching-Runden (6 Paare pro Verb);
        // Typing-Modus = klassische Einzelfragen (1 Person pro Karte).
        let isMatching = (verbformsSession.mode == .multipleChoice)

        let matchingCount = isSpeed ? 10 : 8
        let questionCount = isSpeed ? 30 : 20

        let matchingRounds: [VerbformsMatchingRound]
        let questions: [VerbformsQuestion]
        if isMatching {
            matchingRounds = VerbformsEngine.generateMatchingRounds(
                from: allInflections, tenses: selectedTenses, count: matchingCount
            )
            questions = []
            guard !matchingRounds.isEmpty else { return }
        } else {
            matchingRounds = []
            questions = VerbformsEngine.generateQuestions(
                from: allInflections, tenses: selectedTenses, count: questionCount
            )
            guard !questions.isEmpty else { return }
        }

        feedbackPlayer.playTabSwitch()

        let startSession: () -> Void = {
            if isMatching {
                verbformsSession.startMatching(with: matchingRounds, inflections: allInflections, speedRound: isSpeed)
            } else {
                verbformsSession.start(with: questions, inflections: allInflections, speedRound: isSpeed)
            }
        }

        if isSpeed {
            startSession()
            verbformsCountdown = 3
            feedbackPlayer.playToggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                guard verbformsSession.isActive else { return }
                verbformsCountdown = 2
                feedbackPlayer.playToggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                    guard verbformsSession.isActive else { return }
                    verbformsCountdown = 1
                    feedbackPlayer.playToggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                        guard verbformsSession.isActive else { return }
                        verbformsCountdown = nil
                        feedbackPlayer.playLaunch()
                        verbformsSession.startSpeedRoundTimer(feedbackPlayer: feedbackPlayer)
                    }
                }
            }
        } else {
            startSession()
        }
    }

    var body: some View {
        trainingRootContent
            .appScreenBackground(sectionStyle)
            .dismissKeyboardOnTap()
            .toolbar(.hidden, for: .navigationBar)
            .appLocalChrome(enabled: !usesGlobalChrome) {
                AppTopBar(onBack: { handleTopBarBack() }, onInfo: openInfo)
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.top, AppLayout.topBarInsetTop)
            } bottomBar: {
                AppBottomBar(
                    feedbackPlayer: feedbackPlayer,
                    onHome: { dismissToHome() },
                    onFavorite: nil,
                    onScan: nil,
                    onSettings: { openSettings() }
                )
            }
            .onAppear {
                handleTrainingAppear()
                if isVerbformsMode { loadVerbformsAvailableTenses() }
                refreshSetupCardLemmas()
                // **Stufe 4b-Modal-Refactor (2026-05-02)** —
                // registriert je nach aktivem Modus den passenden
                // Force-Done-Closure für den „Jetzt weiter"-CTA des
                // `ChainCutoffModal`. TrainingView hostet zwei Modi:
                // Verbformen-Layout und das reguläre Training-Layout
                // (vocabulary/nouns/articles/verbs). Closure
                // entscheidet beim Fire anhand `isVerbformsMode`,
                // welcher Helper läuft. Token-basiert für Race-
                // Safety bei Chain-Step-Transitions zwischen Modi.
                forceAdvanceHandlerToken = TrainingChainStore.shared.registerForceAdvanceHandler {
                    if isVerbformsMode {
                        forceVerbformsDoneFromChainTimer()
                    } else {
                        forceTrainingDoneFromChainTimer()
                    }
                }
            }
            .onDisappear {
                stopSpeedRoundTimer()
                TrainingChainStore.shared.unregisterForceAdvanceHandler(token: forceAdvanceHandlerToken)
                forceAdvanceHandlerToken = nil
            }
            // **Stufe 4b-5 (2026-05-02)** — Verbformen Setup-Skip im
            // Chain-Modus. `handleTrainingAppear` triggert
            // `startVerbformsTraining()` (siehe Lifecycle), aber
            // `verbformsCanStart` braucht `availableTenses`
            // populiert — diese werden async von
            // `loadVerbformsAvailableTenses()` befüllt. Wenn die Tenses
            // erst nach Mount ankommen, holen wir den Auto-Start
            // hier nach. Idempotent über `verbformsSession.isActive` /
            // `verbformsSession.isFinished` und `verbformsCanStart`.
            // Pattern-Mirror zu Quiz `handleQuizCandidatesChange`.
            .onChange(of: verbformsSession.availableTenses.count) { _, _ in
                handleVerbformsAvailableTensesChange()
            }
            .onChange(of: session.direction) { _, _ in
                handleTrainingDirectionChange()
            }
            .onChange(of: session.cardType) { _, _ in
                handleTrainingCardTypeChange()
            }
            .onChange(of: session.selectedTrainingListID) { _, _ in
                handleTrainingListChange()
            }
            .onChange(of: session.selectedTrainingListIDs) { _, _ in
                // Verfügbare Zeiten für Verbformen hängen direkt an der gewählten Liste
                if isVerbformsMode { loadVerbformsAvailableTenses() }
                // Setup-Card-Lemmas neu berechnen (gecached, NICHT pro Render)
                refreshSetupCardLemmas()
            }
            .onChange(of: session.trainingMode) { _, _ in
                refreshSetupCardLemmas()
            }
            .onChange(of: session.currentTrainingItem) { _, newItem in
                // Pragmatischer Fix gegen „Lösungswort fehlt in Runde 2":
                // Sobald sich die aktuelle Trainingskarte ändert, im Verben-
                // bzw. Nomen-Wortauswahl-MC die Optionen (Lösung + frische
                // Distraktoren) KOMPLETT neu aufbauen und die Selection/
                // Lock-State zurücksetzen.
                guard newItem != nil else { return }
                if isVerbMode {
                    verbMCSelected = nil
                    verbMCLocked = false
                    prepareVerbMCOptions()
                } else if isNounChoiceMode {
                    nounMCSelected = nil
                    nounMCLocked = false
                    prepareNounMCOptions()
                }
            }
            .onChange(of: session.selectedDictionaryLearningLevel) { _, _ in
                handleDictionaryLearningLevelChange()
            }
            .onChange(of: selectedAppDirectionRaw) { _, _ in
                handleTrainingAppDirectionChange()
            }
            .onChange(of: listStore.customLists) { _, _ in
                handleTrainingCustomListsChange()
            }
            .onChange(of: session.showingTrainingListPicker) { _, _ in
                handleTrainingListPickerChange()
            }
            .onReceive(runtimeSpeechController?.$isRecording.removeDuplicates().eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { isRecording in
                let was = wasRecording
                wasRecording = isRecording
                handleTrainingRecordingTransition(from: was, to: isRecording)
                handleTrainingRecordingPulseChange(isRecording)
            }
            .onReceive(runtimeSpeaker?.$isSpeaking.removeDuplicates().eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { isSpeaking in
                let was = wasSpeakerSpeaking
                wasSpeakerSpeaking = isSpeaking
                handleTrainingSpeakerTransition(from: was, to: isSpeaking)
            }
            .onChange(of: feedbackPlayer.areSoundsEnabled) { _, isEnabled in
                handleAudioModeChange(isEnabled: isEnabled)
            }
            .onChange(of: typedAnswerFieldFocused) { _, isFocused in
                handleTypedAnswerFocusChange(isFocused)
            }
            .onDisappear {
                handleTrainingDisappear()
            }
    }
}
