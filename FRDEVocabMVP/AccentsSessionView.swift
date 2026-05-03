import SwiftUI

/// Aktive Übungs-Session für Akzente (Üben + Speed Round).
///
/// **Stufe 6 (2026-05-02)** — der Lernen-Modus mit eigener
/// `AccentsLearningView` ist appweit entfernt; diese View ist
/// jetzt der einzige Akzente-Session-Renderer.
///
/// Struktur:
/// - Progress-Bar oben
/// - Task-Karte in der Mitte (Wort + Optionen)
/// - Feedback-Overlay bei Antwort
/// - Footer-Button „Weiter"
struct AccentsSessionView: View {
    let mode: AccentMode
    let exercises: [AccentExercise]
    let accentColor: Color
    let onClose: () -> Void
    /// Called when session completes. (correct, total, breakdownByType,
    /// audioVisualSplit, answerRecords) — letzteres für adaptive
    /// Store-Updates + Result-Screen-Hints.
    let onFinish: (AccentSessionFinishPayload) -> Void
    /// Feedback + Navigation für den Bottom-Bar.
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let onHome: () -> Void
    let onSettings: () -> Void
    /// Optionaler Speaker — wenn nil, werden Audio-Exercises nicht
    /// erkennbar gerendert (Fallback: reine visuelle Pick-Varianten).
    /// Kommt via `runtime.speaker` von ganz oben durchgereicht.
    @ObservedObject var speaker: Speaker

    @StateObject private var engine: AccentSessionEngine

    /// Cache für die Shuffle-Reihenfolge pro Exercise. Wird einmalig
    /// befüllt, wenn eine Exercise zum ersten Mal gerendert wird, und
    /// bleibt stabil, solange dieselbe Exercise aktiv ist. Verhindert,
    /// dass der grüne „Richtig"-Button beim Feedback-State-Wechsel an
    /// eine andere Position springt (Bug: jedes Body-Re-Render rief
    /// `shuffledOptions()` neu auf und mischte die Grid-Items).
    @State private var shuffledOptionsByID: [UUID: [String]] = [:]
    @State private var shuffledLettersByID: [UUID: [String]] = [:]
    /// **Stufe 4b-Modal-Refactor (2026-05-02)** — Token der aktuellen
    /// `TrainingChainStore`-Force-Advance-Handler-Registration. Siehe
    /// `FlashcardsView.forceAdvanceHandlerToken` für Doc.
    @State private var forceAdvanceHandlerToken: UUID?


    init(
        mode: AccentMode,
        exercises: [AccentExercise],
        resumeSnapshot: AccentSessionResumeState? = nil,
        resumeListID: UUID? = nil,
        accentColor: Color,
        feedbackPlayer: FeedbackPlayer,
        speaker: Speaker,
        onClose: @escaping () -> Void,
        onHome: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onFinish: @escaping (AccentSessionFinishPayload) -> Void
    ) {
        self.mode = mode
        self.exercises = exercises
        self.accentColor = accentColor
        self.feedbackPlayer = feedbackPlayer
        self.speaker = speaker
        self.onClose = onClose
        self.onHome = onHome
        self.onSettings = onSettings
        self.onFinish = onFinish
        // Zwei Init-Pfade: frischer Start nutzt die normale Init-API
        // mit `exercises`, Resume geht über den Convenience-Init der
        // Engine, der die gesamte Queue plus Index/Records übernimmt.
        if let snapshot = resumeSnapshot {
            self._engine = StateObject(wrappedValue: AccentSessionEngine(
                restoringFrom: snapshot,
                resumeListID: resumeListID
            ))
        } else {
            self._engine = StateObject(wrappedValue: AccentSessionEngine(
                mode: mode,
                exercises: exercises,
                resumeListID: resumeListID
            ))
        }
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                // Countdown läuft? Dann **alles** unter dem Header
                // durch die große 3-2-1-Zahl ersetzen — keine Timer-
                // Bar, kein Content, kein Footer/BottomBar sichtbar.
                // Analog zum Training-Verhalten (siehe
                // `TrainingView+Layout.swift:177`): der User sieht
                // während des Countdowns ausschließlich Header +
                // zentrierte Zahl, **nicht** den Aufgaben-Screen im
                // Hintergrund. Overlay-Variante davor zeigte den
                // Content durch — das war der Bug.
                if let countdown = engine.speedCountdown {
                    countdownInlineView(value: countdown)
                } else {
                    // Speed-Round-Modus: Timer-Bar statt der linearen
                    // Queue-Progress-Bar — der Timer bestimmt wann die
                    // Session endet, nicht die Queue-Länge. Die Timer-
                    // Länge kommt aus `SpeedRoundSettings` (globale
                    // Settings-Einstellung, Default
                    // `SpeedRoundDuration.defaultDuration`).
                    if mode == .speedRound {
                        speedRoundTimerBar
                    } else {
                        progressBar
                    }
                    Spacer()
                    content
                    Spacer()
                    footer
                    bottomBar
                }
            }
        }
        .onAppear {
            // Speed Round startet mit 3-2-1-Countdown + Timer in der
            // globalen Dauer (SpeedRoundSettings.currentSeconds).
            if mode == .speedRound, !engine.isSpeedRoundActive, engine.speedCountdown == nil {
                engine.startSpeedRound(feedbackPlayer: feedbackPlayer)
            }
        }
        .onChange(of: engine.isFinished) { _, finished in
            if finished {
                // Zentrale Finalize-Sequenz bei Session-Ende:
                //   1. TTS + Speed-Round-Timer hart stoppen (kein
                //      Vorlesen über die Summary hinweg, keine Timer-
                //      Nachläufer-Ticks).
                //   2. Achievement-Sound spielen.
                //   3. Payload bilden + Parent (via `onFinish`) den
                //      Summary-Trigger setzen lassen.
                speaker.stop()
                engine.cancelSpeedRound()
                feedbackPlayer.playStudyAchievement()
                let payload = AccentSessionFinishPayload(
                    correct: engine.correctCount,
                    total: engine.currentTotal,
                    breakdown: engine.breakdownByType(),
                    audioVisualSplit: engine.audioVisualSplit(),
                    answerRecords: engine.answerRecords
                )
                onFinish(payload)
            }
        }
        // Antwort-Sounds — identisch zu Quiz/Training: Success bei
        // richtig, Error bei falsch. Guard `!engine.isFinished` verhindert,
        // dass ein verspätet einlaufender Feedback-Tick nach Session-End
        // noch einen Sound abspielt.
        .onChange(of: engine.feedback) { _, newValue in
            guard let feedback = newValue, !engine.isFinished else { return }
            if feedback.isCorrect {
                feedbackPlayer.playStudySuccess()
            } else {
                feedbackPlayer.playStudyError()
            }
        }
        .onDisappear {
            // Speaker stumm + Speed-Round-Timer abräumen, falls der User
            // die Session vorzeitig verlässt.
            speaker.stop()
            engine.cancelSpeedRound()
        }
        // **Stufe 4b-Modal-Refactor (2026-05-02)** — der Chain-Timer-
        // Overlay-Modifier wird hier in der SessionView gemountet
        // (nicht mehr in `AppDestinationHost` auf der EntryView), weil
        // die Session in einem `.fullScreenCover` der EntryView läuft
        // und ein Modifier auf der EntryView hinter dem Cover wäre
        // (visuell unsichtbar). Hier mountet sich der Modifier
        // direkt auf den Cover-Content — Timer-Bar und Cutoff-Modal
        // erscheinen sichtbar über der laufenden Akzente-Session.
        .modifier(ChainTimerOverlayModifier())
        // **Stufe 4b-Modal-Refactor (2026-05-02)** — registriert den
        // modul-spezifischen Force-Done-Closure für den „Jetzt
        // weiter"-CTA des `ChainCutoffModal` direkt am
        // `TrainingChainStore`. Store-Registration ist mount-
        // layering-agnostic. Closure ruft den existierenden 4b-2-
        // Helper auf der `AccentSessionEngine` — Idempotenz-Guard
        // ist dort eingebaut (`!isFinished`).
        .onAppear {
            forceAdvanceHandlerToken = TrainingChainStore.shared.registerForceAdvanceHandler { [weak engine] in
                engine?.forceFinishFromChainTimer()
            }
        }
        .onDisappear {
            TrainingChainStore.shared.unregisterForceAdvanceHandler(token: forceAdvanceHandlerToken)
            forceAdvanceHandlerToken = nil
        }
        // Auto-Advance per-Question ist im Speed Round **nicht mehr nötig**:
        // Der 45-Sekunden-Global-Timer begrenzt die Gesamtzeit, der User
        // bestimmt das Tempo zwischen Fragen selbst per „Weiter"-Tap.
        // (Üben-Modus war ohnehin schon immer manuell.)
    }

    // MARK: - Header (systemkonform, einheitlich zu Lernen)

    private var header: some View {
        AccentsSessionHeader(onBack: onClose) {
            Text("\(min(engine.currentIndex + 1, exercises.count)) / \(exercises.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    // MARK: - Progress

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accentColor)
                    .frame(width: geo.size.width * CGFloat(engine.progress))
                    .animation(.easeOut(duration: 0.25), value: engine.progress)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, AppLayout.screenPadding)
    }

    // MARK: - Speed Round Timer Bar

    /// Seit der Vereinheitlichung: zentrale `SpeedRoundTimerCard` —
    /// identisches Layout + Verhalten wie Training/Verbformen. Die
    /// frühere Akzente-eigene Variante (kleiner Blitz oben, Balken
    /// dünner, keine Urgency-Pulse) ist damit weg; Akzente folgt
    /// derselben visuellen Sprache wie alle anderen Speed-Round-Module.
    private var speedRoundTimerBar: some View {
        SpeedRoundTimerCard(
            remainingSeconds: max(0, engine.speedRoundTimeRemaining),
            totalSeconds: engine.speedRoundTotalSeconds,
            correctCount: engine.correctCount,
            sectionStyle: .accents
        )
        .padding(.horizontal, AppLayout.screenPadding)
    }

    // MARK: - 3-2-1 Countdown Inline-View

    /// Inline-Replacement für den gesamten Session-Body während des
    /// 3-2-1-Countdowns. Füllt die Fläche **unter dem Header** voll aus,
    /// damit kein Content (Progress-Bar, Aufgaben-Card, Footer,
    /// BottomBar) mehr sichtbar ist. Die große Zahl sitzt zentriert —
    /// derselbe Look wie Training/Verbformen, wo der Countdown den
    /// SessionCard-Bereich inline ersetzt.
    ///
    /// Der Warning-Ton (wie bei Training) statt Akzent-Farbe sorgt
    /// appweit für den gleichen „gleich geht's los"-Impuls. Kein
    /// abgedunkelter Hintergrund nötig, weil der VStack den gesamten
    /// Raum bereits mit dem normalen App-Background belegt.
    private func countdownInlineView(value: Int) -> some View {
        // Größe + Farbe an Training/Verbformen-Countdown angeglichen:
        // 72 pt `.warning` statt 120 pt Accent-Color. Damit spielen alle
        // Speed-Round-Intros appweit dieselbe visuelle Sprache.
        Text("\(value)")
            .font(.system(size: 72, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Colors.warning)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.scale.combined(with: .opacity))
            .id(value)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: value)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let exercise = engine.currentExercise {
            VStack(spacing: AppTheme.Spacing.md) {
                promptQuestionCard(for: exercise)
                promptWordCard(for: exercise)
                answersView(for: exercise)
            }
            .padding(.horizontal, AppLayout.screenPadding)
        } else {
            EmptyView()
        }
    }

    /// **Obere Card** — enthält nur den Fragetext („Wähle die richtige
    /// Schreibweise" / „Welches Zeichen gehört an die markierte Stelle?").
    /// Bewusst eine eigene Card über der Wort-Card, damit Frage und
    /// Aufgaben-Inhalt optisch getrennt sind — wie in Quiz/Training-
    /// Setup-Screens.
    @ViewBuilder
    private func promptQuestionCard(for exercise: AccentExercise) -> some View {
        Text(taskPrompt(for: exercise))
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(AppTheme.Layout.cardPadding)
            .frame(maxWidth: .infinity)
            .appCardBackground(.accents, intensity: AppTheme.CardIntensity.soft)
    }

    /// **Mittlere Card** — Wort (oder Letter-Highlight) + Accent-Typ-Pill.
    /// Die eigentliche Aufgaben-Visual. Gleiche Card-Sprache (`appCardBackground`)
    /// wie die Frage-Card darüber.
    @ViewBuilder
    private func promptWordCard(for exercise: AccentExercise) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            switch exercise.kind {
            case .pickCorrectWord:
                Text(exercise.baseWord)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.sm)

            case .chooseAccent:
                letterHighlightView(for: exercise)

            case .listenAndPick:
                audioPlayButton(for: exercise)
            }

            // **UX-Polish 2026-05-02 (User-Spec „Akzent-Typ-Pill
            // systemweit entfernen")**: vorher zeigte unter dem
            // Frage-Wort eine Chip-Card mit dem germanLabel des
            // Akzent-Typs (z.B. „Akut", „Grave", „Cedille"). User
            // soll aus dem Wort selber erkennen, welcher Akzent
            // fehlt — die Pill war ein didaktischer Spoiler. Gilt
            // für alle Akzente-Versionen (Üben, Speed Round, Chain),
            // weil dieser Renderer der einzige ist seit dem Lernen-
            // Modus-Removal in Stufe 6.
        }
        .padding(AppTheme.Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .appCardBackground(.accents, intensity: AppTheme.CardIntensity.soft)
    }

    /// Wort mit hervorgehobenem Target-Zeichen (Variante B).
    /// Genutzt wird ein **einziges** Text-View mit `AttributedString` statt
    /// eines HStacks aus Einzel-Zeichen. Das garantiert sauberen Schrift-
    /// satz (Kerning, Ligaturen, korrekte Inter-Character-Abstände) auch
    /// bei längeren Wörtern oder Wörtern mit unterschiedlichen Glyph-
    /// Breiten. Die Hervorhebung (Farbe + Underline) wirkt nur auf den
    /// Target-Index.
    private func letterHighlightView(for exercise: AccentExercise) -> some View {
        var attributed = AttributedString(exercise.baseWord)
        if let idx = exercise.targetCharacterIndex, idx >= 0, idx < exercise.baseWord.count {
            let start = attributed.index(attributed.startIndex, offsetByCharacters: idx)
            let end = attributed.index(start, offsetByCharacters: 1)
            attributed[start..<end].foregroundColor = accentColor
            attributed[start..<end].underlineStyle = .single
        }

        return Text(attributed)
            .font(.system(size: 36, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppTheme.Spacing.sm)
    }

    private func taskPrompt(for exercise: AccentExercise) -> String {
        switch exercise.kind {
        case .pickCorrectWord: return "Wähle die richtige Schreibweise"
        case .chooseAccent:    return "Welches Zeichen gehört an die markierte Stelle?"
        case .listenAndPick:   return "Hör zu und wähle die richtige Schreibweise"
        }
    }

    // MARK: - Audio Play Button (listenAndPick)

    /// Großer runder Play-Button im Accent-Tint. Bei Tap wird das
    /// korrekte Wort per TTS (fr-FR) abgespielt. User kann mehrmals
    /// tappen — kein Auto-Play, damit der User den Rhythmus bestimmt.
    /// Optischer State (speaking) pulsiert leicht.
    @ViewBuilder
    private func audioPlayButton(for exercise: AccentExercise) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button {
                playCurrentWord(exercise: exercise)
            } label: {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.18))
                        .frame(width: 110, height: 110)
                    Circle()
                        .stroke(accentColor.opacity(speaker.isSpeaking ? 0.8 : 0.35), lineWidth: 3)
                        .frame(width: 110, height: 110)
                    Image(systemName: speaker.isSpeaking ? "waveform" : "speaker.wave.2.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(accentColor)
                        .symbolEffect(.pulse, options: .repeating, isActive: speaker.isSpeaking)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wort abspielen")

            Text("Zum Abspielen tippen")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .onAppear {
            // Beim ersten Mount einer Audio-Aufgabe einmalig automatisch
            // abspielen, damit der User den Flow spürt. Weitere Plays
            // nur via Tap.
            playCurrentWord(exercise: exercise, isInitial: true)
        }
    }

    private func playCurrentWord(exercise: AccentExercise, isInitial: Bool = false) {
        // Bei Initial-Play: nur starten wenn nichts läuft (Race beim
        // Re-Render vermeiden). Bei User-Tap: immer neu starten.
        if isInitial && speaker.isSpeaking { return }
        speaker.speak(text: exercise.correctWord, languageCode: "fr-FR")
    }

    // MARK: - Answer Buttons

    @ViewBuilder
    private func answersView(for exercise: AccentExercise) -> some View {
        switch exercise.kind {
        case .pickCorrectWord, .listenAndPick:
            // Audio- und visuelle Pick-Varianten nutzen das gleiche
            // Wort-Options-Grid — einziger Unterschied ist, dass im
            // Audio-Fall das Wort **nicht** oben als Text steht.
            wordOptionsGrid(for: exercise)
        case .chooseAccent:
            letterOptionsGrid(for: exercise)
        }
    }

    /// 2×2 Grid für Variante A (4 Optionen). Nutzt den **Cache** — die
    /// Reihenfolge bleibt während der gesamten Exercise stabil, damit der
    /// grüne „Richtig"-Button nach dem Feedback nicht an eine andere
    /// Position springt.
    private func wordOptionsGrid(for exercise: AccentExercise) -> some View {
        let options = stableOptions(for: exercise)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(options, id: \.self) { option in
                answerButton(label: option, answer: option, exercise: exercise, minHeight: 62, fontSize: 20)
            }
        }
    }

    /// Horizontale Reihe für Variante B (kurze Zeichen). Auch über
    /// den Cache stabil.
    private func letterOptionsGrid(for exercise: AccentExercise) -> some View {
        let variants = stableLetterVariants(for: exercise)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: min(variants.count, 4))
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(variants, id: \.self) { variant in
                answerButton(label: variant, answer: variant, exercise: exercise, minHeight: 78, fontSize: 34)
            }
        }
    }

    /// Liefert eine einmalig gemischte Reihenfolge der Pick-Optionen
    /// (Variante A). Wird per Side-Effect während der `body`-Auswertung
    /// ins Cache geschrieben — SwiftUI toleriert das, solange `DispatchQueue.main.async`
    /// verwendet wird (kein State-Update mitten im Render-Pfad).
    private func stableOptions(for exercise: AccentExercise) -> [String] {
        if let cached = shuffledOptionsByID[exercise.id] { return cached }
        let new = exercise.shuffledOptions()
        // Cache-Update auf dem nächsten Runloop-Tick — verhindert
        // „Modifying state during view update"-Warnings.
        DispatchQueue.main.async {
            if shuffledOptionsByID[exercise.id] == nil {
                shuffledOptionsByID[exercise.id] = new
            }
        }
        return new
    }

    /// Analog für Variante B.
    private func stableLetterVariants(for exercise: AccentExercise) -> [String] {
        if let cached = shuffledLettersByID[exercise.id] { return cached }
        let new = exercise.shuffledLetterVariants()
        DispatchQueue.main.async {
            if shuffledLettersByID[exercise.id] == nil {
                shuffledLettersByID[exercise.id] = new
            }
        }
        return new
    }

    private func answerButton(label: String, answer: String, exercise: AccentExercise, minHeight: CGFloat, fontSize: CGFloat) -> some View {
        let correct = correctAnswerString(for: exercise)
        let isCorrectAnswer = answer == correct
        let wasUserChoice = engine.lastChosenAnswer == answer
        let showsFeedback = engine.feedback != nil
        // Drei relevante Zustände für die Farbgebung nach Antwort:
        // 1. Die korrekte Antwort → grün (immer markiert, sobald Feedback sichtbar)
        // 2. Die falsch gewählte Antwort des Users → rot
        // 3. Alle anderen → neutral
        let highlightGreen = showsFeedback && isCorrectAnswer
        let highlightRed = showsFeedback && wasUserChoice && !isCorrectAnswer

        // Text bleibt bewusst **immer weiß** (`textPrimary`), auch nach
        // Feedback — kein SwiftUI-Auto-Dimming. Daher **nicht** `.disabled`
        // setzen (das würde den Text greyscale ziehen). Stattdessen Tap
        // ignorieren, wenn Feedback schon aktiv ist.
        return Button {
            if engine.feedback == nil {
                // Tap-Sound — der nachfolgende Success/Error-Sound aus
                // dem feedback-onChange kommt separat (sanfter Zweischritt).
                feedbackPlayer.playTabSwitch()
                engine.submitAnswer(answer)
            }
        } label: {
            Text(label)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: minHeight)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(buttonFill(highlightGreen: highlightGreen, highlightRed: highlightRed))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(buttonStroke(highlightGreen: highlightGreen, highlightRed: highlightRed), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(engine.feedback == nil)
    }

    private func correctAnswerString(for exercise: AccentExercise) -> String {
        switch exercise.kind {
        case .pickCorrectWord, .listenAndPick:
            // Audio- und visuelle Pick-Variante nutzen beide das komplette
            // korrekte Wort als „richtige Antwort".
            return exercise.correctWord
        case .chooseAccent:
            guard let idx = exercise.targetCharacterIndex,
                  idx >= 0, idx < exercise.correctWord.count else { return "" }
            let stringIdx = exercise.correctWord.index(exercise.correctWord.startIndex, offsetBy: idx)
            return String(exercise.correctWord[stringIdx])
        }
    }

    /// Button-Fill bei Feedback — **nicht gedimmt**, sondern voll-
    /// saturiertes Grün / Rot, damit die richtige Antwort deutlich
    /// „leuchtet" und nicht wie abgegraut wirkt.
    private func buttonFill(highlightGreen: Bool, highlightRed: Bool) -> Color {
        if highlightGreen { return AppTheme.Colors.success.opacity(0.55) }
        if highlightRed   { return AppTheme.Colors.moduleHearts.opacity(0.50) }
        return AppTheme.Colors.surface
    }

    private func buttonStroke(highlightGreen: Bool, highlightRed: Bool) -> Color {
        if highlightGreen { return AppTheme.Colors.success }
        if highlightRed   { return AppTheme.Colors.moduleHearts }
        return accentColor.opacity(0.25)
    }

    // MARK: - Advance-Button mit Countdown (Speed Round)

    /// Der „Weiter"-Button — System-CTA. In Speed Round zeigt der Button
    /// immer „Weiter" (der globale Speed-Round-Timer — Dauer aus
    /// `SpeedRoundSettings` — entscheidet über das Session-Ende,
    /// nicht die Queue-Länge). Im Üben-Modus wechselt der Label auf
    /// „Ergebnis anzeigen", sobald die letzte Aufgabe erreicht ist.
    private var advanceButton: some View {
        let isLastInUben = mode == .uben && engine.currentIndex + 1 >= exercises.count
        let label = isLastInUben ? "Ergebnis anzeigen" : "Weiter"
        return Button(label) {
            feedbackPlayer.playTabSwitch()
            engine.advance()
        }
        .buttonStyle(AppPrimaryButtonStyle())
    }

    // MARK: - Bottom Bar (systemkonform)

    private var bottomBar: some View {
        AppBottomBar(
            feedbackPlayer: feedbackPlayer,
            onHome: onHome,
            onFavorite: nil,
            onScan: nil,
            onSettings: onSettings
        )
    }

    // MARK: - Footer (Feedback + Weiter)

    @ViewBuilder
    private var footer: some View {
        if let feedback = engine.feedback {
            feedbackFooter(feedback)
        } else {
            Color.clear.frame(height: AppTheme.Layout.buttonHeight + 2 * AppTheme.Spacing.md)
        }
    }

    private func feedbackFooter(_ feedback: AccentSessionEngine.Feedback) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Feedback-Banner — Headline only, Detail-Erklärung entfernt.
            // Headline +2 pt (15 → 17) damit das Feedback-Wort kräftiger
            // sitzt. Die frühere Detail-Zeile („école — hier wird aus e
            // ein é") war zu klein und wirkte hineingedrängt.
            HStack(spacing: 10) {
                Image(systemName: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(feedback.isCorrect ? AppTheme.Colors.success : AppTheme.Colors.warning)
                Text(feedback.headline)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill((feedback.isCorrect ? AppTheme.Colors.success : AppTheme.Colors.warning).opacity(0.14))
            )

            // Weiter-Button mit optionalem Auto-Advance-Countdown
            // (nur Speed Round). User-Tap überspringt den Timer sofort.
            advanceButton
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.vertical, AppTheme.Spacing.md)
    }
}
