import SwiftUI

struct TrainingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @AppStorage(appDirectionKey) private var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var speechController: SpeechController
    @ObservedObject var speaker: Speaker
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let launchContext: TrainingLaunchContext?
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    private let sectionStyle: AppSectionStyle = .train

    @StateObject private var session = TrainingSessionController()
    @State private var lastResult: ScoreResult?
    @State private var shouldEvaluateAfterStop = false
    @State private var pendingFeedbackTask: DispatchWorkItem?
    @State private var typedAnswer = ""
    @State private var showingTypedAnswerInput = false
    @State private var isMicPulseVisible = false
    @FocusState private var typedAnswerFieldFocused: Bool

    private var activeItems: [VocabularyItem] {
        session.activeItems(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    private var currentCard: FlashCard? {
        session.currentTrainingItem?.card(for: session.direction)
    }

    private var dictionaryTrainingList: VocabularyList? {
        session.dictionaryTrainingList()
    }

    private var shouldPrepareDictionaryTrainingList: Bool {
        session.shouldPrepareDictionaryTrainingList(launchContext: launchContext)
    }

    private var availableTrainingLists: [VocabularyList] {
        session.availableTrainingLists(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    private var selectedTrainingList: VocabularyList? {
        session.selectedTrainingList(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    private var selectedAppDirection: Direction {
        (Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    private var selectedTrainingListLanguages: [StudyLanguage] {
        session.selectedTrainingListLanguages(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    private var isDictionaryTrainingSelected: Bool {
        session.isDictionaryTrainingSelected()
    }

    private var localeIdentifierForRecognition: String {
        session.direction.recognitionLocaleIdentifier
    }

    private var actionButtonHeight: CGFloat {
        AppTheme.Layout.buttonHeight
    }

    private var trainingSessionCardInset: CGFloat {
        8
    }

    private var recordingSymbolName: String {
        speechController.isRecording ? "stop.fill" : "mic.fill"
    }

    private var showsRetryOnlyMessage: Bool {
        lastResult?.label == "Falsch"
    }

    private var showsNotRecognizedMessage: Bool {
        lastResult?.label == "Nicht erkannt"
    }

    private var showsSuccessOnlyMessage: Bool {
        lastResult?.label == "Richtig 🙂"
    }

    private var showsSolutionMessage: Bool {
        lastResult?.label == "Lösung"
    }

    private var solutionUnlockThreshold: Int {
        2
    }

    private var canRevealSolution: Bool {
        session.hasStartedTraining && currentCard != nil && session.failedAttemptsOnCurrentCard >= solutionUnlockThreshold
    }

    private var recordingButtonColor: Color {
        if showsSuccessOnlyMessage {
            return AppTheme.Colors.success
        }

        if showsRetryOnlyMessage {
            return AppTheme.Colors.warning
        }

        return AppTheme.Colors.warning
    }

    private var listeningButtonColor: Color {
        AppTheme.Colors.warning
    }

    private var trainingActionTint: Color {
        AppTheme.Colors.warning
    }

    private var isAudioModeEnabled: Bool {
        feedbackPlayer.areSoundsEnabled
    }

    private var canUseSpeechRecognition: Bool {
        speechController.authorizationStatus != .denied && speechController.authorizationStatus != .restricted
    }

    private var solutionButtonTitle: String {
        if canRevealSolution {
            return "Lösung"
        }
        return "Lösung \(session.failedAttemptsOnCurrentCard)/\(solutionUnlockThreshold)"
    }

    private var nextCardTitle: String {
        session.cardType == .phrases ? "Nächste Phrase" : "Nächstes Wort"
    }

    private var sessionCardMinHeight: CGFloat {
        session.cardType == .phrases ? 152 : 118
    }

    private var sessionPromptFont: Font {
        .system(size: session.cardType == .phrases ? 24 : 28, weight: .bold, design: .rounded)
    }

    private var canStartTraining: Bool {
        !activeItems.isEmpty
    }

    private var startHintText: String {
        if isDictionaryTrainingSelected {
            return "Wähle ein anderes Lernniveau oder eine andere Quelle."
        }
        if availableTrainingLists.isEmpty {
            return "Lege zuerst eine Liste mit Vokabeln an."
        }
        return "Für diesen Typ gibt es in der gewählten Liste noch keine Einträge."
    }

    // body, trainingSetupScreen, trainingSessionScreen are defined in TrainingView+Layout.swift

    private var dictionaryTrainingLevelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lernniveau")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                ForEach(DictionaryLearningLevel.allCases) { option in
                    Button {
                        session.selectedDictionaryLearningLevel = option
                    } label: {
                        Text(option.title)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(session.selectedDictionaryLearningLevel == option ? .white : AppTheme.Colors.textPrimary)
                            .background(session.selectedDictionaryLearningLevel == option ? trainingActionTint : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private func largeTrainingSelectionCard(title: String, value: String) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: title.isEmpty ? 0 : 8) {
                if !title.isEmpty {
                    Text(title)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(trainingActionTint)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: title.isEmpty ? 72 : AppLayout.largeSelectionHeight)
        .padding(.horizontal, AppTheme.Spacing.md)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private var largeTrainingTypeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(CardType.allCases) { item in
                    Button {
                        session.cardType = item
                    } label: {
                        Text(item.rawValue)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(session.cardType == item ? .white : AppTheme.Colors.textPrimary)
                            .background(session.cardType == item ? trainingActionTint : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 76)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private var sessionCard: some View {
        Group {
            if let currentCard, session.hasStartedTraining {
                VStack(alignment: .center, spacing: 8) {
                    Text(currentCard.category.uppercased())
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(currentCard.prompt)
                        .font(sessionPromptFont)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.62)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, minHeight: sessionCardMinHeight, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .appCardBackground(sectionStyle, intensity: 0.07)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keine Karten")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(startHintText)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .appCardBackground(sectionStyle, intensity: 0.07)
            }
        }
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsNotRecognizedMessage {
                Text("Nicht erkannt, bitte nochmal versuchen.")
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if showsRetryOnlyMessage {
                Text("Falsch, bitte nochmal. 🙃")
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.error)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if showsSolutionMessage, let currentCard {
                Text("Lösung")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(currentCard.answer)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else if !session.hasStartedTraining {
                Text("Bereit?")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Tippe oben auf Los geht's!, dann startet die erste Karte direkt.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Antwort")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(speechController.transcript.isEmpty ? "Noch nichts erkannt" : speechController.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(speechController.transcript.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }

            if let error = speechController.recordError {
                Text("Hinweis: \(error)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.error)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(14)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                toggleRecording()
            } label: {
                Group {
                    if showsSuccessOnlyMessage {
                        Text("Richtig 🙂")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    } else if showsRetryOnlyMessage {
                        Text("Falsch")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: recordingSymbolName)
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: actionButtonHeight)
                .foregroundStyle(.white)
                .background(recordingButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(speechController.isRecording && isMicPulseVisible ? 0.28 : 0), lineWidth: 2)
                    .animation(.easeInOut(duration: 0.55), value: isMicPulseVisible)
            }
            .disabled(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled || !canUseSpeechRecognition)
            .opacity(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled || !canUseSpeechRecognition ? 0.45 : (speechController.isRecording && isMicPulseVisible ? 0.72 : 1))

            typedAnswerControl

            Button {
                speakCurrentPrompt()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 25, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(.white)
                    .background(listeningButtonColor)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled)
            .opacity(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled ? 0.45 : 1)

            HStack(spacing: 10) {
                Button {
                    revealSolution()
                } label: {
                    Label(solutionButtonTitle, systemImage: "lightbulb")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: actionButtonHeight)
                        .font(AppTheme.Typography.button)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: trainingActionTint))
                .disabled(!canRevealSolution)
                .opacity(canRevealSolution ? 1 : 0.6)

                Button {
                    cancelPendingFeedback()
                    loadNextTrainingCard()
                    speakCurrentPromptAfterScreenUpdate(initialDelay: 0.06)
                } label: {
                    Label(nextCardTitle, systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: actionButtonHeight)
                        .font(AppTheme.Typography.button)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: trainingActionTint))
                .disabled(!session.hasStartedTraining || session.preparedTrainingItems.isEmpty)
                .opacity(!session.hasStartedTraining || session.preparedTrainingItems.isEmpty ? 0.5 : 1)
            }
        }
    }

    private var typedAnswerControl: some View {
        Group {
            if showingTypedAnswerInput {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(trainingActionTint)

                    TextField("Antwort tippen", text: $typedAnswer)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!session.hasStartedTraining || currentCard == nil)
                        .focused($typedAnswerFieldFocused)
                        .onSubmit {
                            submitTypedAnswer()
                        }

                    Button("Prüfen") {
                        submitTypedAnswer()
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                    .disabled(!session.hasStartedTraining || currentCard == nil || typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .appCardBackground(sectionStyle, intensity: 0.09)
            } else {
                Button {
                    guard session.hasStartedTraining, currentCard != nil else { return }
                    stopListeningForTyping()
                    showingTypedAnswerInput = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        typedAnswerFieldFocused = true
                    }
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 25, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: actionButtonHeight)
                        .foregroundStyle(trainingActionTint)
                        .appCardBackground(sectionStyle, intensity: 0.11)
                }
                .buttonStyle(.plain)
                .disabled(!session.hasStartedTraining || currentCard == nil)
                .opacity(!session.hasStartedTraining || currentCard == nil ? 0.5 : 1)
            }
        }
    }

    private func dismissToHome() {
        resetTrainingSession()
        goHome()
    }

    private func returnToTrainingSetup() {
        resetTrainingSession()
        session.returnToSetup()
    }

    private func applyLaunchContextIfNeeded() {
        session.applyLaunchContextIfNeeded(
            launchContext,
            listStore: listStore,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    private func ensureTrainingSelectionValidity() {
        session.ensureTrainingSelectionValidity(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection
        )
    }

    private func ensureDirectionValidity() {
        session.ensureDirectionValidity(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    private func refreshDictionaryTrainingListIfNeeded() {
        session.refreshDictionaryTrainingListIfNeeded(
            launchContext: launchContext,
            listStore: listStore,
            selectedAppDirection: selectedAppDirection,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    private func resetTrainingSession() {
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        session.resetTrainingSessionState()
        lastResult = nil
        speaker.stop()
        speechController.stopRecording()
        speechController.transcript = ""
        speechController.recordError = nil
        typedAnswer = ""
        showingTypedAnswerInput = !isAudioModeEnabled
        typedAnswerFieldFocused = false
        isMicPulseVisible = false
    }

    private func startTraining() {
        ensureTrainingSelectionValidity()
        guard session.startTraining(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection
        ) else {
            resetTrainingSession()
            return
        }
        showingTypedAnswerInput = false
        typedAnswerFieldFocused = false
        speakCurrentPromptAfterScreenUpdate(initialDelay: 0.12)
    }

    private func speakCurrentPrompt() {
        guard let currentCard else { return }
        stopListeningForTyping()
        guard isAudioModeEnabled else {
            showingTypedAnswerInput = true
            return
        }
        speaker.speak(text: currentCard.prompt, languageCode: currentCard.promptLanguageCode)
    }

    private func toggleRecording() {
        guard session.hasStartedTraining, currentCard != nil else { return }
        cancelPendingFeedback()
        typedAnswerFieldFocused = false

        if speechController.isRecording {
            shouldEvaluateAfterStop = false
            speechController.stopRecording()
        } else {
            speaker.stop()
            lastResult = nil
            typedAnswer = ""
            showingTypedAnswerInput = false
            shouldEvaluateAfterStop = true
            speechController.startRecording(localeIdentifier: localeIdentifierForRecognition)
        }
    }

    private func loadNextTrainingCard() {
        speechController.transcript = ""
        speechController.recordError = nil
        lastResult = nil
        typedAnswer = ""
        showingTypedAnswerInput = false
        typedAnswerFieldFocused = false
        session.loadNextTrainingCard()
    }

    private func evaluateTranscript() {
        evaluateResponse(speechController.transcript)
    }

    private func submitTypedAnswer() {
        guard session.hasStartedTraining, currentCard != nil else { return }
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        stopListeningForTyping()
        typedAnswerFieldFocused = false
        speechController.transcript = typedAnswer
        evaluateResponse(typedAnswer)
    }

    private func evaluateResponse(_ rawInput: String) {
        guard session.hasStartedTraining, let currentCard else { return }

        let expected = normalized(currentCard.answer)
        let got = normalized(rawInput)

        guard !got.isEmpty else {
            lastResult = ScoreResult(
                label: "Nicht erkannt",
                detail: "Bitte nochmal versuchen."
            )
            return
        }

        if isCorrect(got: got, expected: expected, for: currentCard) {
            typedAnswer = ""
            showingTypedAnswerInput = false
            handleCorrectAnswer()
        } else {
            feedbackPlayer.playStudyError()
            session.incrementFailedAttempts()
            lastResult = ScoreResult(
                label: "Falsch",
                detail: "Bitte nochmal."
            )
            typedAnswer = ""
            showingTypedAnswerInput = false
            repeatCurrentPrompt()
        }
    }

    private func handleCorrectAnswer() {
        feedbackPlayer.playStudySuccess()
        lastResult = ScoreResult(label: "Richtig 🙂", detail: "")
        scheduleNextCard()
    }

    private func revealSolution() {
        guard let currentCard, canRevealSolution else { return }
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController.stopRecording()
        speechController.transcript = ""
        speechController.recordError = nil
        typedAnswerFieldFocused = false
        lastResult = ScoreResult(label: "Lösung", detail: currentCard.answer)
    }

    private func repeatCurrentPrompt() {
        guard let currentCard else { return }
        scheduleFeedbackTask(after: 0.35) {
            guard isShowing(currentCard) else { return }
            speakCurrentPromptAfterScreenUpdate(initialDelay: 0.02)
        }
    }

    private func scheduleNextCard() {
        guard let currentCard else { return }
        scheduleFeedbackTask(after: 0.55) {
            guard isShowing(currentCard) else { return }
            loadNextTrainingCard()
            if session.hasStartedTraining {
                speakCurrentPromptAfterScreenUpdate(initialDelay: 0.06)
            }
        }
    }

    private func speakCurrentPromptAfterScreenUpdate(initialDelay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            await Task.yield()
            guard session.hasStartedTraining, currentCard != nil else { return }
            speakCurrentPrompt()
        }
    }

    private func scheduleFeedbackTask(after delay: TimeInterval, action: @escaping () -> Void) {
        cancelPendingFeedback()
        let workItem = DispatchWorkItem(block: action)
        pendingFeedbackTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingFeedback() {
        pendingFeedbackTask?.cancel()
        pendingFeedbackTask = nil
    }

    private func beginAutomaticListeningIfNeeded() {
        guard session.hasStartedTraining, currentCard != nil else { return }
        guard isAudioModeEnabled, canUseSpeechRecognition else { return }
        guard !showingTypedAnswerInput, !typedAnswerFieldFocused else { return }
        guard !speechController.isRecording else { return }
        shouldEvaluateAfterStop = true
        speechController.startRecording(localeIdentifier: localeIdentifierForRecognition)
    }

    private func stopListeningForTyping() {
        shouldEvaluateAfterStop = false
        if speechController.isRecording {
            speechController.stopRecording()
        }
        speaker.stop()
        isMicPulseVisible = false
    }

    private func handleAudioModeChange(isEnabled: Bool) {
        if !isEnabled {
            stopListeningForTyping()
            showingTypedAnswerInput = true
        } else if session.hasStartedTraining, currentCard != nil, !showingTypedAnswerInput {
            speakCurrentPrompt()
        }
    }

    private func isShowing(_ card: FlashCard) -> Bool {
        guard let currentCard else { return false }
        return isSameTrainingCard(currentCard, card)
    }

    private func isSameTrainingCard(_ lhs: FlashCard, _ rhs: FlashCard) -> Bool {
        lhs.prompt == rhs.prompt
            && lhs.answer == rhs.answer
            && lhs.category == rhs.category
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "’", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isCorrect(got: String, expected: String, for card: FlashCard) -> Bool {
        if requiresFrenchArticle(for: card),
           hasFrenchArticleMismatch(got: got, expected: expected) {
            return false
        }

        let expectedVariants = answerVariants(for: expected, answerLanguageCode: card.answerLanguageCode)
        let gotVariants = answerVariants(for: got, answerLanguageCode: card.answerLanguageCode)

        for gotVariant in gotVariants {
            if expectedVariants.contains(where: { isApproximateMatch(got: gotVariant, expected: $0) }) {
                return true
            }
        }

        return false
    }

    private func isApproximateMatch(got: String, expected: String) -> Bool {
        if got == expected {
            return true
        }

        let distance = levenshtein(got, expected)
        let maxLength = max(got.count, expected.count)
        let ratio = maxLength == 0 ? 0 : Double(distance) / Double(maxLength)
        return ratio <= 0.25 || got.contains(expected) || expected.contains(got)
    }

    private func requiresFrenchArticle(for card: FlashCard) -> Bool {
        card.answerLanguageCode == "fr-FR" && card.category == CardType.words.categoryName
    }

    private func hasFrenchArticleMismatch(got: String, expected: String) -> Bool {
        let expectedStem = droppingFrenchLeadingArticle(from: expected)
        guard expectedStem != expected else { return false }

        let gotStem = droppingFrenchLeadingArticle(from: got)
        let gotHasArticle = gotStem != got
        let expectedArticle = leadingFrenchArticle(in: expected)
        let gotArticle = leadingFrenchArticle(in: got)
        let stemsMatch = isApproximateMatch(got: gotStem, expected: expectedStem)

        guard stemsMatch else { return false }
        return !gotHasArticle || gotArticle != expectedArticle
    }

    private func droppingFrenchLeadingArticle(from text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return text }

        if words.count >= 2 {
            let firstTwo = "\(words[0]) \(words[1])"
            if frenchTwoWordArticles.contains(firstTwo) {
                return words.dropFirst(2).joined(separator: " ")
            }
        }

        if frenchSingleWordArticles.contains(words[0]) {
            return words.dropFirst().joined(separator: " ")
        }

        return text
    }

    private func leadingFrenchArticle(in text: String) -> String? {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        if words.count >= 2 {
            let firstTwo = "\(words[0]) \(words[1])"
            if frenchTwoWordArticles.contains(firstTwo) {
                return firstTwo
            }
        }

        if frenchSingleWordArticles.contains(words[0]) {
            return words[0]
        }

        return nil
    }

    private var frenchSingleWordArticles: Set<String> {
        ["l", "la", "le", "les", "un", "une", "des", "du", "au", "aux"]
    }

    private var frenchTwoWordArticles: Set<String> {
        ["de la", "de l", "de les", "a la", "a l"]
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(
                        dist[i - 1][j] + 1,
                        dist[i][j - 1] + 1,
                        dist[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return dist[a.count][b.count]
    }
}

struct FlashcardsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @AppStorage(appDirectionKey) private var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @ObservedObject var sessionStore: FlashcardSessionStore
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var speechController: SpeechController
    @ObservedObject var speaker: Speaker
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let launchContext: FlashcardLaunchContext?
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    private let sectionStyle: AppSectionStyle = .flashcards

    @StateObject private var setup = FlashcardsSetupController()
    @StateObject private var interaction = FlashcardsSessionController()
    @FocusState private var isTypedAnswerFocused: Bool
    @FocusState private var isCardCountFieldFocused: Bool
    private let flashcardCountInputScrollID = "flashcardCountInput"

    private var currentCard: FlashcardDeckCard? {
        sessionStore.currentCard
    }

    private var currentFlashCard: FlashCard? {
        interaction.currentFlashCard
    }

    private var isSessionReady: Bool {
        sessionStore.hasActiveSession && currentCard != nil
    }

    private var isFlashcardSessionCompleted: Bool {
        sessionStore.session?.isCompleted == true
    }

    private var actionButtonHeight: CGFloat {
        54
    }

    private var flashcardSessionCardInset: CGFloat {
        8
    }

    private var flashcardSecondaryActionHeight: CGFloat {
        38
    }

    private var flashcardFaceHeight: CGFloat {
        152
    }

    private var recordingSymbolName: String {
        speechController.isRecording ? "stop.fill" : "mic.fill"
    }

    private var progressText: String {
        "\(sessionStore.masteredCount)/\(sessionStore.totalCount) · \(sessionStore.wrongCount) falsch"
    }

    private var selectedAppDirection: Direction {
        Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman
    }

    private var availableStackLists: [VocabularyList] {
        setup.availableStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
    }

    private var selectedStackLists: [VocabularyList] {
        setup.selectedStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
    }

    private var selectedStackCardCount: Int {
        setup.selectedStackCardCount(from: listStore, selectedAppDirection: selectedAppDirection)
    }

    private var effectiveSelectedCardCount: Int {
        setup.effectiveSelectedCardCount(for: selectedStackCardCount)
    }

    private var selectedCardCountForSetup: Int {
        setup.selectedCardCountForSetup(selectedStackCardCount: selectedStackCardCount)
    }

    private var selectedStackSummary: String {
        let listCount = selectedStackLists.count
        let cardCount = selectedCardCountForSetup

        if listCount == 0 {
            return "Liste wählen"
        }

        if listCount == 1, let firstList = selectedStackLists.first {
            return "\(flashcardListDisplayName(firstList)) · \(countLabel(cardCount, singular: "Karte", plural: "Karten"))"
        }

        return "\(countLabel(listCount, singular: "Liste", plural: "Listen")) · \(countLabel(cardCount, singular: "Karte", plural: "Karten"))"
    }

    private var isDictionarySelectedInStack: Bool {
        setup.isDictionarySelectedInStack()
    }

    private var canStartSetup: Bool {
        selectedCardCountForSetup > 0
    }

    private var showsSuccessOnlyMessage: Bool {
        interaction.lastResult?.label == "Korrekt! 🙂"
    }

    private var showsWrongOnlyMessage: Bool {
        interaction.lastResult?.label == "Falsch"
    }

    private var flashcardRecordingButtonColor: Color {
        if showsSuccessOnlyMessage {
            return .green
        }
        if showsWrongOnlyMessage {
            return AppTheme.Colors.error
        }
        return sectionStyle.accent
    }

    private var isAudioModeEnabled: Bool {
        feedbackPlayer.areSoundsEnabled
    }

    private var canUseSpeechRecognition: Bool {
        speechController.authorizationStatus != .denied && speechController.authorizationStatus != .restricted
    }

    private var canRestorePreviousFlashcard: Bool {
        interaction.canRestorePreviousFlashcard && !setup.isShowingSetup
    }

    private var flashcardTopBarSpacing: CGFloat {
        AppLayout.topBarInsetTop + AppTheme.Spacing.xs
    }

    private var flashcardBottomBarSpacing: CGFloat {
        AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
    }

    @ViewBuilder
    private var flashcardsRootContent: some View {
        if setup.isShowingSetup {
            flashcardSetupScreen
        } else {
            flashcardSessionScreen
        }
    }

    @ViewBuilder
    private var flashcardTypedAnswerOverlay: some View {
        if !setup.isShowingSetup && !isFlashcardSessionCompleted && interaction.showingTypedAnswerInput {
            VStack {
                Spacer()
                flashcardTypedAnswerCard
                    .padding(.horizontal, AppLayout.screenPadding + flashcardSessionCardInset)
                    .padding(.bottom, AppTheme.Layout.footerHeight + flashcardBottomBarSpacing + AppTheme.Spacing.sm)
            }
            .zIndex(3)
        }
    }

    private var flashcardsBodyContent: AnyView {
        AnyView(
            ZStack(alignment: .top) {
                flashcardsRootContent
                flashcardTypedAnswerOverlay
            }
        )
    }

    private var flashcardsTopBar: some View {
        AppTopBar(onBack: { handleBackNavigation() }, onInfo: openInfo)
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, flashcardTopBarSpacing)
    }

    private var flashcardsBottomBar: some View {
        AppBottomBar(
            feedbackPlayer: feedbackPlayer,
            onHome: { dismissToHome() },
            onFavorite: nil,
            onScan: nil,
            onSettings: { openSettings() }
        )
    }

    private var flashcardsChromeContent: AnyView {
        AnyView(
            flashcardsBodyContent
                .tint(sectionStyle.accent)
                .appScreenBackground(sectionStyle)
                .dismissKeyboardOnTap()
                .simultaneousGesture(
                    TapGesture().onEnded {
                        dismissTypedAnswerFocus()
                    }
                )
                .toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        if setup.isShowingSetup && !setup.isUsingAllCardCount {
                            Spacer()
                            Button("OK") {
                                confirmCardCountEntry()
                            }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                    }
                }
                .appLocalChrome(enabled: !usesGlobalChrome) {
                    flashcardsTopBar
                } bottomBar: {
                    flashcardsBottomBar
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if setup.isShowingSetup && !setup.isUsingAllCardCount && isCardCountFieldFocused {
                        flashcardKeyboardConfirmBar
                    }
                }
        )
    }

    private var flashcardsLifecycleStage1: AnyView {
        AnyView(
            flashcardsChromeContent
                .onAppear {
                    handleFlashcardsAppear()
                }
                .onChange(of: sessionStore.selectedDeckID) { _, _ in
                    interaction.syncDisplayedCard(with: sessionStore)
                    resetTransientState()
                }
                .onChange(of: sessionStore.selectedDirection) { _, _ in
                    interaction.syncDisplayedCard(with: sessionStore)
                    resetTransientState()
                }
        )
    }

    private var flashcardsLifecycleStage2: AnyView {
        AnyView(
            flashcardsLifecycleStage1
                .onChange(of: sessionStore.session) { _, _ in
                    interaction.syncDisplayedCard(with: sessionStore)
                }
                .onChange(of: selectedAppDirectionRaw) { _, _ in
                    setup.syncSetupSelection(
                        selectedAppDirection: selectedAppDirection,
                        sessionStore: sessionStore
                    )
                    refreshDictionaryStackListIfNeeded()
                }
                .onChange(of: setup.selectedStackDictionaryLearningLevel) { _, _ in
                    refreshDictionaryStackListIfNeeded()
                }
                .onChange(of: setup.isShowingSetup) { _, _ in
                    refreshDictionaryStackListIfNeeded()
                }
                .onChange(of: setup.showingStackComposer) { _, _ in
                    refreshDictionaryStackListIfNeeded()
                }
        )
    }

    private var flashcardsLifecycleStage3: AnyView {
        AnyView(
            flashcardsLifecycleStage2
                .onChange(of: setup.selectedStackListIDs) { _, _ in
                    refreshDictionaryStackListIfNeeded()
                }
                .onChange(of: listStore.customLists) { _, _ in
                    ensureStackSelectionValidity()
                }
                .onChange(of: setup.customCardCountText) { _, _ in
                    setup.sanitizeCustomCardCountTextIfNeeded()
                }
                .onChange(of: speechController.isRecording) { wasRecording, isRecording in
                    interaction.handleRecordingStateChange(
                        wasRecording: wasRecording,
                        isRecording: isRecording,
                        sessionStore: sessionStore,
                        speechController: speechController,
                        speaker: speaker,
                        feedbackPlayer: feedbackPlayer,
                        dismissTypedAnswerFocus: dismissTypedAnswerFocus
                    )
                }
        )
    }

    private var flashcardsLifecycleContent: AnyView {
        AnyView(
            flashcardsLifecycleStage3
                .onChange(of: feedbackPlayer.areSoundsEnabled) { _, isEnabled in
                    interaction.handleAudioModeChange(
                        isEnabled: isEnabled,
                        speechController: speechController,
                        speaker: speaker
                    )
                }
                .onChange(of: isTypedAnswerFocused) { _, isFocused in
                    if isFocused {
                        interaction.handleAudioModeChange(
                            isEnabled: false,
                            speechController: speechController,
                            speaker: speaker
                        )
                    }
                }
                .onDisappear {
                    interaction.handleDisappear(
                        speechController: speechController,
                        speaker: speaker,
                        dismissTypedAnswerFocus: dismissTypedAnswerFocus
                    )
                }
        )
    }

    var body: some View {
        flashcardsLifecycleContent
    }

    private var flashcardSessionScreen: some View {
        VStack(spacing: 8) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Karteikarten",
                subtitle: "",
                systemImage: "rectangle.stack.fill"
            )

            if isFlashcardSessionCompleted {
                flashcardCompletionCard
                    .padding(.horizontal, flashcardSessionCardInset)

                Button {
                    returnToFlashcardSetup()
                } label: {
                    Label("Zurück zur Auswahl", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                .padding(.horizontal, flashcardSessionCardInset)
            } else {
                Button {
                    returnToFlashcardSetup()
                } label: {
                    Label("Zurück zur Auswahl", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .font(AppTheme.Typography.button)
                        .foregroundStyle(sectionStyle.accent)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(AppTheme.Colors.secondarySurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .stroke(sectionStyle.accent.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, flashcardSessionCardInset)

                flashcardPromptCard
                    .padding(.horizontal, flashcardSessionCardInset)
                flashcardActionButtons
                    .padding(.horizontal, flashcardSessionCardInset)
                flashcardResponseCard
                    .padding(.horizontal, flashcardSessionCardInset)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var flashcardSetupScreen: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    ScreenHeaderCard(
                        style: sectionStyle,
                        title: "Karteikarten",
                        subtitle: "",
                        systemImage: "rectangle.stack.fill"
                    )

                    Button {
                        setup.showingStackComposer = true
                    } label: {
                        largeFlashcardToggleCard(
                            title: "Ausgewählte Pakete",
                            value: selectedStackSummary
                        )
                    }
                    .buttonStyle(.plain)

                    if isDictionarySelectedInStack {
                        flashcardDictionaryLevelCard
                    }

                    largeFlashcardContentCard
                    flashcardCountLimitCard

                    Button {
                        startFlashcardsFromSetup()
                    } label: {
                        Text("Los geht's!")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: canStartSetup ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled))
                    .disabled(!canStartSetup)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, isCardCountFieldFocused ? 140 : AppTheme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: isCardCountFieldFocused) { _, isFocused in
                guard isFocused else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        proxy.scrollTo(flashcardCountInputScrollID, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $setup.showingStackComposer) {
            FlashcardStackComposerSheet(
                style: sectionStyle,
                lists: availableStackLists,
                selectedListIDs: setup.selectedStackListIDs,
                language: selectedAppDirection.sourceLanguage,
                cardTypeFilter: setup.selectedSetupContent.preferredCardType
            ) { updatedSelection in
                setup.selectedStackListIDs = updatedSelection
                setup.showingStackComposer = false
            }
        }
    }

    private var flashcardDictionaryLevelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lernniveau")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                ForEach(DictionaryLearningLevel.allCases) { option in
                    Button {
                        setup.selectedStackDictionaryLearningLevel = option
                    } label: {
                        Text(option.title)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(setup.selectedStackDictionaryLearningLevel == option ? .white : AppTheme.Colors.textPrimary)
                            .background(setup.selectedStackDictionaryLearningLevel == option ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private func largeSetupSelectionCard(title: String, value: String) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(value)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(sectionStyle.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: AppLayout.largeSelectionHeight)
        .padding(.horizontal, 18)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private var largeFlashcardContentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(FlashcardContentSelection.allCases) { option in
                    Button {
                        setup.selectedSetupContent = option
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 68)
                            .foregroundStyle(setup.selectedSetupContent == option ? .white : AppTheme.Colors.textPrimary)
                            .background(setup.selectedSetupContent == option ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 108)
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private var flashcardCountLimitCardLegacy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anzahl der Karten")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                Button {
                    setup.isUsingAllCardCount = true
                    isCardCountFieldFocused = false
                } label: {
                    flashcardCountModeCard(
                        title: "ALLE",
                        subtitle: countLabel(selectedStackCardCount, singular: "Karte", plural: "Karten"),
                        isSelected: setup.isUsingAllCardCount
                    )
                }
                .buttonStyle(.plain)

                Button {
                    setup.isUsingAllCardCount = false
                    isCardCountFieldFocused = true
                } label: {
                    flashcardCountModeCard(
                        title: "ANZAHL",
                        subtitle: !setup.isUsingAllCardCount && effectiveSelectedCardCount > 0
                            ? countLabel(effectiveSelectedCardCount, singular: "Karte", plural: "Karten")
                            : "Eigene Zahl",
                        isSelected: !setup.isUsingAllCardCount
                    )
                }
                .buttonStyle(.plain)
            }

            if !setup.isUsingAllCardCount {
                HStack(spacing: 10) {
                    TextField("Anzahl eingeben", text: $setup.customCardCountText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .keyboardType(.numberPad)
                        .submitLabel(.done)
                        .focused($isCardCountFieldFocused)

                    Button("OK") {
                        confirmCardCountEntry()
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(AppTheme.Colors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .id(flashcardCountInputScrollID)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 156)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private func flashcardCountModeCard(title: String, subtitle: String, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(AppTheme.Typography.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .foregroundStyle(isSelected ? Color.white.opacity(0.84) : AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 82)
        .foregroundStyle(isSelected ? .white : AppTheme.Colors.textPrimary)
        .background(isSelected ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func confirmCardCountEntry() {
        setup.confirmCardCountEntry()
        isCardCountFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder
    private var flashcardKeyboardConfirmBar: some View {
        HStack {
            Spacer()
            Button("OK") {
                confirmCardCountEntry()
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppTheme.Spacing.xs)
        .padding(.bottom, AppTheme.Spacing.sm)
        .background(
            Rectangle()
                .fill(AppTheme.Colors.background.opacity(0.94))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func largeFlashcardToggleCard(title: String, value: String) -> some View {
        let valueParts = value.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let primaryValue = valueParts.first ?? value
        let secondaryValue = valueParts.count > 1 ? valueParts.dropFirst().joined(separator: " · ") : ""

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if !title.isEmpty {
                    Text(title)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Text(primaryValue)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(title.isEmpty ? 2 : 1)
                    .minimumScaleFactor(0.8)

                if !secondaryValue.isEmpty {
                    Text(secondaryValue)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(sectionStyle.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 96)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private var flashcardPromptCard: some View {
        Group {
            if let currentFlashCard, sessionStore.hasActiveSession {
                VStack(spacing: 10) {
                    Text(progressText)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            flashcardFace(
                                text: currentFlashCard.prompt,
                                isAnswerSide: false,
                                languageCode: currentFlashCard.promptLanguageCode
                            )
                            .opacity(interaction.isFlashcardFlipped ? 0 : 1)

                            flashcardFace(
                                text: currentFlashCard.answer,
                                isAnswerSide: true,
                                languageCode: currentFlashCard.answerLanguageCode
                            )
                            .opacity(interaction.isFlashcardFlipped ? 1 : 0)
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                        }
                        .rotation3DEffect(
                            .degrees(interaction.isFlashcardFlipped ? 180 : 0),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.72
                        )
                        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
                        .shadow(color: AppTheme.Shadow.card.color, radius: 14, x: 0, y: 8)
                        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: interaction.isFlashcardFlipped)

                        FlashcardStackBadge(
                            remainingCount: sessionStore.remainingCount,
                            totalCount: sessionStore.totalCount
                        )
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: flashcardFaceHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isSessionReady else { return }
                        if interaction.showingSolution {
                            interaction.flipBackToFront(dismissTypedAnswerFocus: dismissTypedAnswerFocus)
                        } else {
                            interaction.revealSolution(
                                speechController: speechController,
                                dismissTypedAnswerFocus: dismissTypedAnswerFocus
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
                .offset(x: interaction.cardFlyOutOffset)
                .rotationEffect(.degrees(interaction.cardFlyOutRotation))
                .opacity(interaction.cardFlyOutOpacity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bereit für Karteikarten?")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Starte oben deinen Karteikarten-Stapel.")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .appCardBackground(sectionStyle, intensity: 0.07)
            }
        }
    }

    private var flashcardResponseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFlashcardSessionCompleted {
                Text("Alle Karten aus dem Stapel sind raus. 🙂")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.success)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if interaction.showingSolution {
                Text("Rückseite geöffnet")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(sectionStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if interaction.lastResult?.label == "Falsch" {
                Text("Falsch")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.error)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if interaction.lastResult?.label == "Nicht erkannt" {
                Text("Nicht erkannt, bitte nochmal versuchen.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if sessionStore.hasActiveSession {
                Text("Antwort")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(speechController.transcript.isEmpty ? "Noch nichts erkannt" : speechController.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(speechController.transcript.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            } else {
                Text("Fortschritt")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Richtige Karten werden aus dem Stapel entfernt. Falsche Karten bleiben drin, bis du am Ende alle geschafft hast.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            if let error = speechController.recordError {
                Text("Hinweis: \(error)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.error)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 46, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    private var flashcardCompletionCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppTheme.Colors.warning)

            Text("Stapel geschafft!")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(flashcardCompletionMessage)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                flashcardCompletionStat(
                    title: "Richtig",
                    value: "\(flashcardCompletionCorrectCount)",
                    color: AppTheme.Colors.success
                )
                flashcardCompletionStat(
                    title: "Fehler",
                    value: "\(flashcardCompletionWrongCount)",
                    color: AppTheme.Colors.warning
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .appCardBackground(sectionStyle, intensity: 0.12, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private func flashcardCompletionStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.Colors.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var flashcardCompletionCorrectCount: Int {
        sessionStore.session?.correctCount ?? sessionStore.masteredCount
    }

    private var flashcardCompletionWrongCount: Int {
        sessionStore.session?.wrongCount ?? sessionStore.wrongCount
    }

    private var flashcardCompletionMessage: String {
        if flashcardCompletionWrongCount == 0 {
            return "Alles geschafft, ganz ohne Fehler. Sehr stark."
        }

        return "Alle Karten sind durch. Du kannst jetzt zurück zur Auswahl gehen und den nächsten Stapel starten."
    }

    private var flashcardTypedAnswerCard: some View {
        Group {
            if interaction.showingTypedAnswerInput {
                HStack(spacing: 8) {
                    TextField("Antwort tippen", text: $interaction.typedAnswer)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTypedAnswerFocused)
                        .disabled(!isSessionReady)
                        .onTapGesture {
                            interaction.handleAudioModeChange(
                                isEnabled: false,
                                speechController: speechController,
                                speaker: speaker
                            )
                        }
                        .onSubmit {
                            submitTypedAnswer()
                        }

                    Button {
                        dismissTypedAnswerFocus()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 22, weight: .bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                    Button("Prüfen") {
                        submitTypedAnswer()
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                    .disabled(!isSessionReady || interaction.typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .frame(maxWidth: AppTheme.Layout.maxContentWidth)
                .appCardBackground(sectionStyle, intensity: 0.12)
                .shadow(color: AppTheme.Shadow.card.color, radius: 12, x: 0, y: 8)
            }
        }
    }

    private var flashcardActionButtons: some View {
        VStack(spacing: 10) {
            Button {
                toggleRecording()
            } label: {
                Group {
                    if showsSuccessOnlyMessage {
                        Text("Korrekt! 🙂")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                    } else if showsWrongOnlyMessage {
                        Text("Falsch")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: recordingSymbolName)
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: actionButtonHeight)
                .foregroundStyle(.white)
                .background(flashcardRecordingButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(speechController.isRecording && interaction.isMicPulseVisible ? 0.28 : 0), lineWidth: 2)
                    .animation(.easeInOut(duration: 0.55), value: interaction.isMicPulseVisible)
            }
            .disabled(!isSessionReady || !isAudioModeEnabled || !canUseSpeechRecognition)
            .opacity(!isSessionReady || !isAudioModeEnabled || !canUseSpeechRecognition ? 0.45 : (speechController.isRecording && interaction.isMicPulseVisible ? 0.72 : 1))

            Button {
                speakCurrentPrompt()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .appCardBackground(sectionStyle, intensity: 0.11)
            }
            .buttonStyle(.plain)
            .disabled(!isSessionReady || !isAudioModeEnabled)
            .opacity(isSessionReady && isAudioModeEnabled ? 1 : 0.45)

            Button {
                showFlashcardTypedAnswerField()
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(interaction.showingTypedAnswerInput ? .white : AppTheme.Colors.textPrimary)
                    .background(interaction.showingTypedAnswerInput ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isSessionReady)
            .opacity(isSessionReady ? 1 : 0.45)

            HStack(spacing: 10) {
                Button {
                    restorePreviousFlashcard()
                } label: {
                    Label("Zurück", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(AppTheme.Typography.button)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: flashcardSecondaryActionHeight)
                .appCardBackground(sectionStyle, intensity: 0.11)
                .disabled(!canRestorePreviousFlashcard)
                .opacity(canRestorePreviousFlashcard ? 1 : 0.5)

                Button {
                    skipCard()
                } label: {
                    Label("Überspringen", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(AppTheme.Typography.button)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: flashcardSecondaryActionHeight)
                .appCardBackground(sectionStyle, intensity: 0.11)
                .disabled(!isSessionReady)
                .opacity(isSessionReady ? 1 : 0.5)
            }
        }
    }

    private func flashcardFace(text: String, isAnswerSide: Bool, languageCode: String) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(isAnswerSide ? AppTheme.Colors.secondarySurface : AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isAnswerSide ? AppTheme.Colors.warning.opacity(0.14) : sectionStyle.accent.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isAnswerSide ? AppTheme.Colors.borderStrong : AppTheme.Colors.border, lineWidth: 1)
            )
            .overlay(alignment: .center) {
                Text(text)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(isAnswerSide ? AppTheme.Colors.textPrimary : AppTheme.Colors.textPrimary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.62)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, isAnswerSide ? 14 : 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: flashcardFaceHeight)
    }

    private func selectionChip(title: String, value: String) -> some View {
        CompactSelectionChip(style: sectionStyle, title: title, value: value)
    }

    private func dismissToHome() {
        resetTransientState()
        sessionStore.clearTransientCustomDeckState()
        goHome()
    }

    private func returnToFlashcardSetup() {
        resetTransientState()
        setup.prepareReturnToSetup(
            selectedAppDirection: selectedAppDirection,
            sessionStore: sessionStore
        )
    }

    private func handleBackNavigation() {
        if setup.isShowingSetup {
            sessionStore.clearTransientCustomDeckState()
            dismiss()
            return
        }

        resetTransientState()
        sessionStore.clearTransientCustomDeckState()
        setup.prepareReturnToSetup(
            selectedAppDirection: selectedAppDirection,
            sessionStore: sessionStore
        )
    }

    private func applyLaunchContextIfNeeded() {
        setup.applyLaunchContextIfNeeded(
            launchContext,
            listStore: listStore,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 },
            sessionStore: sessionStore
        )
    }

    private func ensureStackSelectionValidity() {
        setup.ensureStackSelectionValidity(
            listStore: listStore,
            selectedAppDirection: selectedAppDirection,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    private func syncSetupSelection() {
        setup.syncSetupSelection(
            selectedAppDirection: selectedAppDirection,
            sessionStore: sessionStore
        )
    }

    private func refreshDictionaryStackListIfNeeded() {
        setup.refreshDictionaryStackListIfNeeded(
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection,
            listStore: listStore,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    private func startFlashcardsFromSetup(autoplayPrompt: Bool = false) {
        resetTransientState()
        isCardCountFieldFocused = false
        guard setup.startFlashcardsFromSetup(
            listStore: listStore,
            selectedAppDirection: selectedAppDirection,
            sessionStore: sessionStore
        ) else { return }
        interaction.syncDisplayedCard(with: sessionStore)
        if autoplayPrompt {
            speakCurrentPrompt()
        }
    }

    private func toggleRecording() {
        interaction.toggleRecording(
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    private func speakCurrentPrompt() {
        interaction.speakCurrentPrompt(
            speechController: speechController,
            speaker: speaker,
            areSoundsEnabled: isAudioModeEnabled
        )
    }

    private func submitTypedAnswer() {
        interaction.submitTypedAnswer(
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            feedbackPlayer: feedbackPlayer,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    private func skipCard() {
        interaction.skipCard(
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            areSoundsEnabled: isAudioModeEnabled,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    private func restorePreviousFlashcard() {
        interaction.restorePreviousFlashcard(
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    private func resetTransientState() {
        interaction.resetTransientState(
            speechController: speechController,
            speaker: speaker,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    private func handleFlashcardsAppear() {
        markFlashcardsOpenTiming("flashcards_view_on_appear")
        applyLaunchContextIfNeeded()
        ensureStackSelectionValidity()
        refreshDictionaryStackListIfNeeded()
        interaction.syncDisplayedCard(with: sessionStore)
        if setup.shouldAutoStartFromLaunch {
            setup.shouldAutoStartFromLaunch = false
            startFlashcardsFromSetup(autoplayPrompt: false)
        } else {
            syncSetupSelection()
        }
        if sessionStore.hasActiveSession == false {
            speechController.stopRecording()
            speechController.deactivateAudioSession()
        }
        endFlashcardsOpenTiming("flashcards_ready")
    }

    private func dismissTypedAnswerFocus() {
        isTypedAnswerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func showFlashcardTypedAnswerField() {
        interaction.handleAudioModeChange(
            isEnabled: false,
            speechController: speechController,
            speaker: speaker
        )
        guard interaction.showTypedAnswerField(isSessionReady: isSessionReady) else { return }
        DispatchQueue.main.async {
            isTypedAnswerFocused = true
        }
    }
}

struct QuizView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @AppStorage(appDirectionKey) private var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appQuizHeartsKey) private var collectedWorms = 0
    @AppStorage(appElumiWaterflohKey) private var collectedWaterfloh = 0
    @AppStorage(appElumiAlgenkugelKey) private var collectedAlgenkugel = 0
    @AppStorage(appElumiXPKey) private var collectedXP = 0
    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0
    @AppStorage(appElumiBestStreakKey) private var bestStreak = 0
    @AppStorage(appElumiLastRewardDayIndexKey) private var lastRewardDayIndex = 0
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    private let sectionStyle: AppSectionStyle = .quiz

    @StateObject private var session = QuizSessionController()
    @State private var selectedMultipleChoiceOption: String?
    @State private var multipleChoiceLocked = false
    @State private var selectedPromptID: UUID?
    @State private var selectedAnswerID: UUID?
    @State private var matchedPairIDs: Set<UUID> = []
    @State private var matchingHadMistake = false
    @State private var flashingPromptID: UUID?
    @State private var flashingAnswerID: UUID?
    @State private var draggingPromptID: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var hoveredAnswerID: UUID?
    @State private var answerFrames: [UUID: CGRect] = [:]
    @State private var promptFrames: [UUID: CGRect] = [:]
    @State private var awardedHearts = 0
    @State private var awardedWaterfloh = 0
    @State private var awardedAlgenkugel = 0
    @State private var awardedXP = 0
    @State private var unlockedRewardLevels: [ElumiLevelTier] = []
    @State private var didPersistHearts = false
    @State private var advanceTask: DispatchWorkItem?

    private var selectedAppDirection: Direction {
        (Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    private var availableQuizLists: [VocabularyList] {
        var lists: [VocabularyList] = [listStore.builtInList]
        if let aggregateList = listStore.allCustomVocabularyList {
            lists.append(aggregateList)
        }
        lists.append(contentsOf: listStore.sortedCustomLists)
        return lists
    }

    private var selectedQuizLists: [VocabularyList] {
        availableQuizLists.filter { session.selectedListIDs.contains($0.id) }
    }

    private var canStartQuiz: Bool {
        session.canStartQuiz
    }

    private var currentQuestion: QuizQuestion? {
        session.currentQuestion
    }

    private var displayedQuestionCount: Int {
        session.displayedQuestionCount
    }

    private var correctCount: Int {
        session.correctCount
    }

    private var wrongCount: Int {
        session.wrongCount
    }

    private var resultHeadline: String {
        if !unlockedRewardLevels.isEmpty {
            return "Level-Up!"
        }

        if wrongCount == 0, !session.answeredResults.isEmpty {
            return "Perfekte Lektion!"
        }

        switch correctCount {
        case 8...:
            return "Excellent !"
        case 5...:
            return "Très bien !"
        case 1...:
            return "Bien joué !"
        default:
            return "Continue !"
        }
    }

    private var rewardSummaryText: String {
        var parts: [String] = []

        if awardedHearts > 0 {
            parts.append("+\(awardedHearts) Würmchen")
        }
        if awardedWaterfloh > 0 {
            parts.append("+\(awardedWaterfloh) Wasserflöhe")
        }
        if awardedAlgenkugel > 0 {
            parts.append("+\(awardedAlgenkugel) Algenkugeln")
        }
        if awardedXP > 0 {
            parts.append("+\(awardedXP) XP")
        }

        return parts.isEmpty ? "Quiz beendet" : parts.joined(separator: " · ")
    }

    private var currentLevelAfterRewards: ElumiLevelTier {
        elumiLevelTier(for: collectedXP)
    }

    private var isPerfectQuiz: Bool {
        wrongCount == 0 && !session.answeredResults.isEmpty
    }

    private var totalRewardCount: Int {
        awardedHearts + awardedWaterfloh + awardedAlgenkugel
    }

    private var dominantRewardSnackKind: ElumiSnackKind {
        if awardedAlgenkugel > 0 {
            return .algenkugel
        }
        if awardedWaterfloh > 0 {
            return .wasserfloh
        }
        return .wuermchen
    }

    private var quizTopBarSpacing: CGFloat {
        AppLayout.topBarInsetTop + AppTheme.Spacing.xs
    }

    private var quizBottomBarSpacing: CGFloat {
        AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
    }

    private var quizSetupCardInset: CGFloat {
        8
    }

    var body: some View {
        Group {
            if session.isShowingResult {
                quizResultScreen
            } else if session.questions.isEmpty {
                quizSetupScreen
            } else {
                quizSessionScreen
            }
        }
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { handleBackNavigation() }, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, quizTopBarSpacing)
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
            session.syncSelectedLists(availableLists: availableQuizLists)
            session.refreshMergedItemsIfNeeded(
                from: selectedQuizLists,
                direction: selectedAppDirection,
                force: session.cachedMergedItems.isEmpty
            )
        }
        .onChange(of: listStore.customLists) { _, _ in
            session.clearMergedCache()
            session.syncSelectedLists(availableLists: availableQuizLists)
            session.refreshMergedItemsIfNeeded(
                from: selectedQuizLists,
                direction: selectedAppDirection,
                force: true
            )
        }
        .onChange(of: session.selectedListIDs) { _, _ in
            session.refreshMergedItemsIfNeeded(
                from: selectedQuizLists,
                direction: selectedAppDirection
            )
        }
        .onChange(of: selectedAppDirectionRaw) { _, _ in
            session.refreshMergedItemsIfNeeded(
                from: selectedQuizLists,
                direction: selectedAppDirection
            )
        }
        .onChange(of: session.questionCountOption) { _, _ in
            session.invalidatePreparedQuestions()
        }
        .onChange(of: session.isShowingResult) { _, isShowingResult in
            guard isShowingResult else { return }
            prepareQuizRewards()
        }
        .onDisappear {
            cancelAdvanceTask()
        }
    }

    private var quizSetupScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ScreenHeaderCard(
                    style: sectionStyle,
                    title: "Quiz",
                    subtitle: "",
                    systemImage: "lightbulb.fill"
                )

                AppSurfaceCard(tint: sectionStyle.accent) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Listen")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        ForEach(availableQuizLists) { list in
                            Button {
                                toggleListSelection(list.id)
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(list.name)
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundStyle(AppTheme.Colors.textPrimary)
                                            .lineLimit(2)
                                        Text("\(list.items.count) Einträge")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(AppTheme.Colors.textSecondary)
                                    }

                                    Spacer(minLength: 0)

                                    Image(systemName: session.selectedListIDs.contains(list.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(session.selectedListIDs.contains(list.id) ? sectionStyle.accent : AppTheme.Colors.textDisabled)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .appCardBackground(
                                    sectionStyle,
                                    intensity: session.selectedListIDs.contains(list.id) ? 0.13 : 0.06
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, quizSetupCardInset)

                AppSurfaceCard(tint: sectionStyle.accent) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fragen")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        HStack(spacing: 8) {
                            ForEach(QuizQuestionCountOption.allCases) { option in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        session.questionCountOption = option
                                    }
                                } label: {
                                    Text(option.title)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundStyle(session.questionCountOption == option ? .white : AppTheme.Colors.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 34)
                                        .background(session.questionCountOption == option ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, quizSetupCardInset)

                if !canStartQuiz {
                    Text("Wähle mindestens eine Liste mit zwei Einträgen.")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(.horizontal, quizSetupCardInset)
                }

                Button {
                    startQuiz()
                } label: {
                    Text(session.isPreparingQuiz ? "Quiz wird gestartet..." : "Quiz starten")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                .disabled(!canStartQuiz || session.isPreparingQuiz)
                .opacity(canStartQuiz && !session.isPreparingQuiz ? 1 : 0.55)
                .padding(.horizontal, quizSetupCardInset)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.bottom, AppTheme.Spacing.sm)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var quizSessionScreen: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Quiz",
                subtitle: "",
                systemImage: "lightbulb.fill"
            )

            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack {
                        Text("\(min(session.currentQuestionIndex + 1, displayedQuestionCount)) von \(displayedQuestionCount)")
                            .font(AppTheme.Typography.cardTitle)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Spacer(minLength: 0)
                        Text("\(correctCount) richtig · \(wrongCount) falsch")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    quizProgressBar
                }
            }

            if let currentQuestion {
                switch currentQuestion {
                case .multipleChoice(let question):
                    multipleChoiceCard(question)
                case .matching(let question):
                    matchingCard(question)
                }
            } else if session.isLoadingRemainingQuestions {
                AppSurfaceCard(tint: sectionStyle.accent) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(sectionStyle.accent)

                        Text("Nächste Frage wird geladen ...")
                            .font(AppTheme.Typography.body)
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var quizResultScreen: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Ergebnis",
                subtitle: "",
                systemImage: "rosette"
            )

            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(spacing: AppTheme.Spacing.lg) {
                    VStack(spacing: AppTheme.Spacing.xs) {
                        QuizRewardHeroView(
                            dominantKind: dominantRewardSnackKind,
                            worms: awardedHearts,
                            waterfloh: awardedWaterfloh,
                            algae: awardedAlgenkugel,
                            accent: sectionStyle.accent
                        )

                        Text(rewardSummaryText)
                            .font(AppTheme.Typography.screenTitle)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(resultHeadline)
                            .font(AppTheme.Typography.cardTitle)
                            .foregroundStyle(sectionStyle.accent)
                            .multilineTextAlignment(.center)

                    }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        resultStatCard(
                            title: "Richtig",
                            value: "\(correctCount)",
                            tint: AppTheme.Colors.success
                        )
                        resultStatCard(
                            title: "Falsch",
                            value: "\(wrongCount)",
                            tint: AppTheme.Colors.warning
                        )
                        resultStatCard(
                            title: "XP",
                            value: "\(awardedXP)",
                            tint: sectionStyle.accent
                        )
                    }

                    if totalRewardCount > 0 {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            rewardChip(kind: .wuermchen, value: awardedHearts)
                            rewardChip(kind: .wasserfloh, value: awardedWaterfloh)
                            rewardChip(kind: .algenkugel, value: awardedAlgenkugel)
                        }
                    }

                    if !unlockedRewardLevels.isEmpty {
                        VStack(spacing: AppTheme.Spacing.xs) {
                            ForEach(unlockedRewardLevels) { level in
                                Text("Level \(level.level) freigeschaltet: \(level.title)")
                                    .font(AppTheme.Typography.body)
                                    .foregroundStyle(AppTheme.Colors.warning)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.md)
            }

            Button {
                resetQuizToSetup()
            } label: {
                Text("Nochmal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

            Button {
                dismissToHome()
            } label: {
                Text("Zur Startseite")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            persistHeartsIfNeeded()
        }
    }

    private func resultStatCard(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: AppTheme.Spacing.xxs) {
            Text(value)
                .font(AppTheme.Typography.screenTitle)
                .foregroundStyle(tint)
            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(tint.opacity(0.92))
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(tint.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(tint.opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func rewardChip(kind: ElumiSnackKind, value: Int) -> some View {
        if value > 0 {
            HStack(spacing: 6) {
                ElumiSnackIcon(kind, size: 18)
                Text("+\(value)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AppTheme.Colors.secondarySurface)
            .clipShape(Capsule())
        }
    }

    private func multipleChoiceCard(_ question: QuizMultipleChoiceQuestion) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Multiple Choice")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Text(visibleQuizPromptText(question.prompt, category: question.category))
                        .font(quizPromptTypography(for: question.prompt, category: question.category))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(quizPromptLineLimit(for: question.prompt, category: question.category))
                        .minimumScaleFactor(quizPromptMinimumScale(for: question.prompt, category: question.category))
                        .multilineTextAlignment(.leading)
                }
            }

            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            submitMultipleChoice(option, for: question)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Text(visibleQuizAnswerText(option, category: question.category))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(multipleChoiceTextColor(for: option, correctAnswer: question.correctAnswer))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.78)
                                Spacer(minLength: 0)
                                Image(systemName: multipleChoiceIcon(for: option, correctAnswer: question.correctAnswer))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(multipleChoiceTextColor(for: option, correctAnswer: question.correctAnswer))
                            }
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .background(multipleChoiceBackground(for: option, correctAnswer: question.correctAnswer))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(multipleChoiceLocked)
                    }
                }
            }
        }
    }

    private func matchingCard(_ question: QuizMatchingQuestion) -> some View {
        AppSurfaceCard(tint: sectionStyle.accent) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Paare finden")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(draggingPromptID == nil ? "Ziehe links zur passenden Karte rechts." : "Ziehe auf die passende Karte und lass los.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(draggingPromptID == nil ? AppTheme.Colors.textSecondary : sectionStyle.accent)

                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    VStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(question.pairs) { pair in
                            Text(visibleQuizPromptText(pair.prompt, category: question.category))
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(matchingTextColor(for: pair.id))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .padding(.horizontal, AppTheme.Spacing.sm)
                                .background(matchingBackground(for: pair.id))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                        .stroke(matchingBorderColor(for: pair.id), lineWidth: matchingBorderWidth(for: pair.id))
                                )
                                .shadow(color: matchingShadowColor(for: pair.id), radius: draggingPromptID == pair.id ? 18 : 8, x: 0, y: draggingPromptID == pair.id ? 10 : 4)
                                .scaleEffect(draggingPromptID == pair.id ? 1.035 : 1)
                                .offset(draggingPromptID == pair.id ? dragOffset : .zero)
                                .opacity(matchedPairIDs.contains(pair.id) ? 0.7 : 1)
                                .zIndex(draggingPromptID == pair.id ? 10 : 0)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: QuizPromptFramePreferenceKey.self,
                                            value: [pair.id: geo.frame(in: .named("quizMatchingArea"))]
                                        )
                                    }
                                )
                                .gesture(
                                    DragGesture(coordinateSpace: .named("quizMatchingArea"))
                                        .onChanged { value in
                                            guard !matchedPairIDs.contains(pair.id) else { return }
                                            draggingPromptID = pair.id
                                            dragOffset = value.translation
                                            updateHoveredAnswer(for: pair.id)
                                        }
                                        .onEnded { _ in
                                            finishDrag(for: pair.id, in: question)
                                        }
                                )
                        }
                    }

                    VStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(question.shuffledAnswers) { pair in
                            Text(visibleQuizAnswerText(pair.answer, category: question.category))
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(matchingTextColor(for: pair.id))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .padding(.horizontal, AppTheme.Spacing.sm)
                                .background(matchingBackground(for: pair.id))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                        .stroke(matchingBorderColor(for: pair.id), lineWidth: matchingBorderWidth(for: pair.id))
                                )
                                .shadow(color: matchingShadowColor(for: pair.id), radius: 8, x: 0, y: 4)
                                .scaleEffect(1)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: QuizAnswerFramePreferenceKey.self,
                                            value: [pair.id: geo.frame(in: .named("quizMatchingArea"))]
                                        )
                                    }
                                )
                        }
                    }
                }
                .coordinateSpace(name: "quizMatchingArea")
                .onPreferenceChange(QuizPromptFramePreferenceKey.self) { frames in
                    promptFrames = frames
                }
                .onPreferenceChange(QuizAnswerFramePreferenceKey.self) { frames in
                    answerFrames = frames
                }
            }
        }
    }

    private var quizProgressBar: some View {
        HStack(spacing: 6) {
            ForEach(Array((0..<displayedQuestionCount).enumerated()), id: \.offset) { index, _ in
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(progressColor(for: index))
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
            }
        }
    }

    private func progressColor(for index: Int) -> Color {
        guard index < session.answeredResults.count else {
            return AppTheme.Colors.secondarySurface
        }
        return session.answeredResults[index] ? AppTheme.Colors.success : AppTheme.Colors.error
    }

    private func multipleChoiceBackground(for option: String, correctAnswer: String) -> Color {
        guard multipleChoiceLocked else {
            return AppTheme.Colors.secondarySurface
        }
        if normalizedLookupText(option) == normalizedLookupText(correctAnswer) {
            return AppTheme.Colors.success.opacity(0.18)
        }
        if selectedMultipleChoiceOption == option {
            return AppTheme.Colors.error.opacity(0.18)
        }
        return AppTheme.Colors.secondarySurface
    }

    private func multipleChoiceTextColor(for option: String, correctAnswer: String) -> Color {
        guard multipleChoiceLocked else {
            return AppTheme.Colors.textPrimary
        }
        if normalizedLookupText(option) == normalizedLookupText(correctAnswer) {
            return AppTheme.Colors.success
        }
        if selectedMultipleChoiceOption == option {
            return AppTheme.Colors.error
        }
        return AppTheme.Colors.textPrimary
    }

    private func multipleChoiceIcon(for option: String, correctAnswer: String) -> String {
        guard multipleChoiceLocked else { return "circle.fill" }
        if normalizedLookupText(option) == normalizedLookupText(correctAnswer) {
            return "checkmark.circle.fill"
        }
        if selectedMultipleChoiceOption == option {
            return "xmark.circle.fill"
        }
        return "circle.fill"
    }

    private func matchingBackground(for pairID: UUID) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success.opacity(0.18)
        }
        if pairID == flashingPromptID || pairID == flashingAnswerID {
            return AppTheme.Colors.error.opacity(0.2)
        }
        if pairID == draggingPromptID {
            return AppTheme.Colors.warning.opacity(0.22)
        }
        if pairID == selectedPromptID || pairID == selectedAnswerID {
            return AppTheme.Colors.primary.opacity(0.14)
        }
        return AppTheme.Colors.secondarySurface
    }

    private func matchingTextColor(for pairID: UUID) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success
        }
        if pairID == flashingPromptID || pairID == flashingAnswerID {
            return AppTheme.Colors.error
        }
        if pairID == draggingPromptID {
            return AppTheme.Colors.warning
        }
        if pairID == selectedPromptID || pairID == selectedAnswerID {
            return AppTheme.Colors.primary
        }
        return AppTheme.Colors.textPrimary
    }

    private func matchingBorderColor(for pairID: UUID) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success.opacity(0.7)
        }
        if pairID == flashingPromptID || pairID == flashingAnswerID {
            return AppTheme.Colors.error.opacity(0.75)
        }
        if pairID == draggingPromptID {
            return AppTheme.Colors.warning.opacity(0.92)
        }
        if pairID == selectedPromptID || pairID == selectedAnswerID {
            return AppTheme.Colors.primary.opacity(0.45)
        }
        return AppTheme.Colors.borderStrong
    }

    private func matchingBorderWidth(for pairID: UUID) -> CGFloat {
        if pairID == draggingPromptID {
            return 2
        }
        if matchedPairIDs.contains(pairID) || pairID == flashingPromptID || pairID == flashingAnswerID {
            return 1.6
        }
        return 1
    }

    private func matchingShadowColor(for pairID: UUID) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success.opacity(0.18)
        }
        if pairID == flashingPromptID || pairID == flashingAnswerID {
            return AppTheme.Colors.error.opacity(0.18)
        }
        if pairID == draggingPromptID {
            return AppTheme.Colors.warning.opacity(0.24)
        }
        return AppTheme.Colors.shadow
    }

    private func toggleListSelection(_ id: UUID) {
        if session.selectedListIDs.contains(id) {
            if session.selectedListIDs.count > 1 {
                session.selectedListIDs.remove(id)
            }
        } else {
            session.selectedListIDs.insert(id)
        }
    }

    private func startQuiz() {
        session.syncSelectedLists(availableLists: availableQuizLists)
        session.startQuiz(direction: selectedAppDirection)
        awardedHearts = 0
        awardedWaterfloh = 0
        awardedAlgenkugel = 0
        awardedXP = 0
        unlockedRewardLevels = []
        didPersistHearts = false
        resetPerQuestionState()
    }

    private func submitMultipleChoice(_ option: String, for question: QuizMultipleChoiceQuestion) {
        guard !multipleChoiceLocked else { return }
        multipleChoiceLocked = true
        selectedMultipleChoiceOption = option

        let isCorrect = normalizedLookupText(option) == normalizedLookupText(question.correctAnswer)
        if isCorrect {
            feedbackPlayer.playStudySuccess()
        } else {
            feedbackPlayer.playStudyError()
        }

        scheduleAdvance(after: 0.95) {
            completeCurrentQuestion(correct: isCorrect)
        }
    }

    private func updateHoveredAnswer(for promptID: UUID) {
        selectedPromptID = promptID
        selectedAnswerID = hoveredAnswerID
        hoveredAnswerID = droppedAnswerID(for: promptID)
        selectedAnswerID = hoveredAnswerID
    }

    private func finishDrag(for promptID: UUID, in question: QuizMatchingQuestion) {
        selectedPromptID = promptID
        selectedAnswerID = droppedAnswerID(for: promptID)
        hoveredAnswerID = selectedAnswerID

        guard selectedAnswerID != nil else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                dragOffset = .zero
            }
            draggingPromptID = nil
            selectedPromptID = nil
            return
        }

        evaluateMatchingSelection(in: question)
    }

    private func droppedAnswerID(for promptID: UUID) -> UUID? {
        guard let promptFrame = promptFrames[promptID] else { return nil }
        let draggedCenter = CGPoint(
            x: promptFrame.midX + dragOffset.width,
            y: promptFrame.midY + dragOffset.height
        )

        return answerFrames.first(where: { candidateID, frame in
            !matchedPairIDs.contains(candidateID) && frame.contains(draggedCenter)
        })?.key
    }

    private func selectPrompt(_ id: UUID) {
        guard !matchedPairIDs.contains(id) else { return }
        selectedPromptID = id
        if let selectedAnswerID, selectedAnswerID == id {
            selectedPromptID = nil
            self.selectedAnswerID = nil
        }
    }

    private func selectAnswer(_ id: UUID, in question: QuizMatchingQuestion) {
        guard !matchedPairIDs.contains(id) else { return }
        selectedAnswerID = id
        evaluateMatchingSelection(in: question)
    }

    private func evaluateMatchingSelection(in question: QuizMatchingQuestion) {
        guard let selectedPromptID, let selectedAnswerID else { return }

        if selectedPromptID == selectedAnswerID {
            feedbackPlayer.playStudySuccess()
            let snapOffset = matchingSnapOffset(for: selectedPromptID, answerID: selectedAnswerID)

            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                dragOffset = snapOffset
            }

            scheduleAdvance(after: 0.22) {
                matchedPairIDs.insert(selectedPromptID)
                draggingPromptID = nil
                dragOffset = .zero
                self.selectedPromptID = nil
                self.selectedAnswerID = nil
                hoveredAnswerID = nil

                if matchedPairIDs.count == question.pairs.count {
                    let isCorrect = !matchingHadMistake
                    scheduleAdvance(after: 0.72) {
                        completeCurrentQuestion(correct: isCorrect)
                    }
                }
            }
        } else {
            feedbackPlayer.playStudyError()
            matchingHadMistake = true
            flashingPromptID = selectedPromptID
            flashingAnswerID = selectedAnswerID

            withAnimation(.easeOut(duration: 0.14)) {
                dragOffset = CGSize(width: dragOffset.width * 0.25, height: dragOffset.height * 0.25)
            }

            scheduleAdvance(after: 0.5) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    dragOffset = .zero
                }
                draggingPromptID = nil
                flashingPromptID = nil
                flashingAnswerID = nil
                hoveredAnswerID = nil
                self.selectedPromptID = nil
                self.selectedAnswerID = nil
            }
        }
    }

    private func completeCurrentQuestion(correct: Bool) {
        resetPerQuestionState()
        session.completeCurrentQuestion(correct: correct)
    }

    private func prepareQuizRewards() {
        let rewardOutcome = computeElumiRewardOutcome(
            baseWorms: correctCount,
            baseXP: correctCount * 10,
            isPerfectLesson: isPerfectQuiz,
            currentXP: collectedXP,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            lastRewardDayIndex: lastRewardDayIndex
        )

        awardedHearts = rewardOutcome.worms
        awardedWaterfloh = rewardOutcome.waterfloh
        awardedAlgenkugel = rewardOutcome.algenkugel
        awardedXP = rewardOutcome.xp
        unlockedRewardLevels = rewardOutcome.unlockedLevels
        if totalRewardCount > 0 || awardedXP > 0 {
            feedbackPlayer.playStudyAchievement()
        }
    }

    private func persistHeartsIfNeeded() {
        guard !didPersistHearts else { return }
        let rewardOutcome = computeElumiRewardOutcome(
            baseWorms: correctCount,
            baseXP: correctCount * 10,
            isPerfectLesson: isPerfectQuiz,
            currentXP: collectedXP,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            lastRewardDayIndex: lastRewardDayIndex
        )

        collectedWorms += rewardOutcome.worms
        collectedWaterfloh += rewardOutcome.waterfloh
        collectedAlgenkugel += rewardOutcome.algenkugel
        collectedXP += rewardOutcome.xp
        currentStreak = rewardOutcome.currentStreak
        bestStreak = rewardOutcome.bestStreak
        lastRewardDayIndex = rewardOutcome.lastRewardDayIndex
        didPersistHearts = true
    }

    private func resetPerQuestionState() {
        cancelAdvanceTask()
        selectedMultipleChoiceOption = nil
        multipleChoiceLocked = false
        selectedPromptID = nil
        selectedAnswerID = nil
        matchedPairIDs = []
        matchingHadMistake = false
        flashingPromptID = nil
        flashingAnswerID = nil
        draggingPromptID = nil
        dragOffset = .zero
        hoveredAnswerID = nil
        answerFrames = [:]
        promptFrames = [:]
    }

    private func matchingSnapOffset(for promptID: UUID, answerID: UUID) -> CGSize {
        guard let promptFrame = promptFrames[promptID],
              let answerFrame = answerFrames[answerID] else {
            return dragOffset
        }

        return CGSize(
            width: answerFrame.midX - promptFrame.midX,
            height: answerFrame.midY - promptFrame.midY
        )
    }

    private func scheduleAdvance(after delay: TimeInterval, action: @escaping () -> Void) {
        cancelAdvanceTask()
        let workItem = DispatchWorkItem(block: action)
        advanceTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelAdvanceTask() {
        advanceTask?.cancel()
        advanceTask = nil
    }

    private func resetQuizToSetup() {
        cancelAdvanceTask()
        session.resetToSetup()
        awardedHearts = 0
        awardedWaterfloh = 0
        awardedAlgenkugel = 0
        awardedXP = 0
        unlockedRewardLevels = []
        didPersistHearts = false
        resetPerQuestionState()
    }

    private func dismissToHome() {
        resetQuizToSetup()
        goHome()
    }

    private func handleBackNavigation() {
        if session.isShowingResult || !session.questions.isEmpty {
            resetQuizToSetup()
        } else {
            dismiss()
        }
    }
}
