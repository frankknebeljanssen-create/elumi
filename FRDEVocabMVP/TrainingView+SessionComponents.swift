import SwiftUI

extension TrainingView {
    var sessionCard: some View {
        Group {
            // Frühere Inline-„Zeit abgelaufen!"-Card + direkte UserDefaults-
            // XP/Credits-Vergabe wurde **entfernt**. Der Speed-Round-Timer
            // setzt jetzt am Ende direkt `trainingSessionOutcome` via
            // `awardTrainingXPIfNeeded()` → die globale `SessionSummaryView`
            // übernimmt. Single Source of Truth für Reward: `ProgressService`.
            // Der frühere Branch war ein Fremdkörper im Summary-Flow und
            // hat XP doppelt vergeben (einmal inline via UserDefaults,
            // einmal später via ProgressService beim Back-Aus).
            if let currentCard, session.hasStartedTraining {
                VStack(alignment: .center, spacing: 8) {
                    if isVerbMode, let selected = verbMCSelected {
                        let isCorrect = selected.lowercased() == verbCorrectAnswer.lowercased()
                        Text(isCorrect ? "Richtig 🙂" : "Falsch 😕")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(isCorrect ? AppTheme.Colors.success : Color(red: 0.9, green: 0.3, blue: 0.15))
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if isNounChoiceMode, let selected = nounMCSelected {
                        // Nomen-Wortauswahl: gleiches Feedback-Label wie
                        // bei Verben — Richtig/Falsch erscheint sofort oben,
                        // nicht erst unten in der Response-Card.
                        let isCorrect = selected.lowercased() == nounCorrectAnswer.lowercased()
                        Text(isCorrect ? "Richtig 🙂" : "Falsch 😕")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(isCorrect ? AppTheme.Colors.success : Color(red: 0.9, green: 0.3, blue: 0.15))
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        if let wcLabel = currentCard.wordClassLabel(for: currentCard.promptLanguageCode) {
                            Text(wcLabel)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    Text(isArticleMode ? (articlePromptText ?? currentCard.prompt) : (isVerbMode ? verbPromptText : currentCard.prompt))
                        .font(isArticleMode ? .system(size: 32, weight: .black, design: .rounded) : sessionPromptFont)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(5)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                }
                .frame(maxWidth: .infinity, minHeight: sessionCardMinHeight, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .appCardBackground(sectionStyle, intensity: (isVerbMode && verbMCSelected != nil) || (isNounChoiceMode && nounMCSelected != nil) ? AppTheme.CardIntensity.strong : AppTheme.CardIntensity.subtle)
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
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.subtle)
            }
        }
    }

    var responseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsNotRecognizedMessage {
                Text("Nicht erkannt, bitte nochmal versuchen.")
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
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
                Text((speechController?.transcript ?? "").isEmpty ? "Noch nichts erkannt" : (speechController?.transcript ?? ""))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle((speechController?.transcript ?? "").isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                    .lineLimit(5)
                    .minimumScaleFactor(0.55)
            }

            if let error = speechController?.recordError {
                Text("Hinweis: \(error)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.error)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(14)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }

    var articleButtons: some View {
        VStack(spacing: 10) {
            if showsSuccessOnlyMessage {
                Text("Richtig 🙂")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(.white)
                    .background(AppTheme.Colors.success)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            } else if showsRetryOnlyMessage {
                Text("Falsch 😕")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.9, green: 0.3, blue: 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            } else {
                HStack(spacing: 10) {
                    ForEach(["le", "la", "l'", "les"], id: \.self) { article in
                        Button {
                            submitArticle(article)
                        } label: {
                            Text(article)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: actionButtonHeight)
                                .foregroundStyle(.white)
                                .background(trainingActionTint)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                        }
                        .buttonStyle(.plain)
                        .disabled(articleLocked)
                    }
                }
            }

            Spacer(minLength: AppTheme.Spacing.sm)

            // Translation hint button — always visible
            if let item = session.currentTrainingItem {
                Button {
                    showingArticleTranslation.toggle()
                } label: {
                    if showingArticleTranslation {
                        Text(item.german)
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
            }
        }
    }

    var verbMCCard: some View {
        VStack(spacing: 8) {
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(verbMCOptions, id: \.self) { option in
                    Button {
                        submitVerbMC(option)
                    } label: {
                        Text(option)
                            .font(.system(size: session.cardType == .phrases ? 12 : 15, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .foregroundStyle(verbMCButtonForeground(option))
                            .background(verbMCButtonBackground(option))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(verbMCLocked)
                }
            }

        }
    }

    func verbMCButtonForeground(_ option: String) -> Color {
        guard let selected = verbMCSelected else { return .white }
        let correct = verbCorrectAnswer.lowercased()
        let isCorrectPick = selected.lowercased() == correct
        if isCorrectPick && option.lowercased() == correct { return .white }
        if !isCorrectPick && option.lowercased() == selected.lowercased() { return .white }
        if verbMCLocked { return AppTheme.Colors.textPrimary.opacity(0.5) }
        return .white
    }

    func verbMCButtonBackground(_ option: String) -> Color {
        guard let selected = verbMCSelected else { return trainingActionTint }
        let correct = verbCorrectAnswer.lowercased()
        let isCorrectPick = selected.lowercased() == correct
        if isCorrectPick && option.lowercased() == correct { return AppTheme.Colors.success }
        if !isCorrectPick && option.lowercased() == selected.lowercased() { return Color(red: 0.9, green: 0.3, blue: 0.15) }
        if verbMCLocked { return AppTheme.Colors.secondarySurface }
        return trainingActionTint
    }

    // MARK: - Nomen Wortauswahl-Card
    //
    // Grid-Variante zur Speech-Alternative. Strukturell identisch zum
    // `verbMCCard` — `LazyVGrid` mit 2 Spalten, pro Option ein
    // Tap-Button, Farben kommen aus `nounMCButtonForeground/Background`.
    // Die Font-Regel (Phrasen kleiner) ist im Nomen-Modul irrelevant (es
    // gibt keine Phrasen im MC-Pool), bleibt aber analog zum Verb-Card-
    // Code — billig und robust gegen spätere Änderungen.

    var nounMCCard: some View {
        VStack(spacing: 8) {
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(nounMCOptions, id: \.self) { option in
                    Button {
                        submitNounMC(option)
                    } label: {
                        Text(option)
                            .font(.system(size: session.cardType == .phrases ? 12 : 15, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .foregroundStyle(nounMCButtonForeground(option))
                            .background(nounMCButtonBackground(option))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(nounMCLocked)
                }
            }
        }
    }

    func nounMCButtonForeground(_ option: String) -> Color {
        guard let selected = nounMCSelected else { return .white }
        let correct = nounCorrectAnswer.lowercased()
        let isCorrectPick = selected.lowercased() == correct
        if isCorrectPick && option.lowercased() == correct { return .white }
        if !isCorrectPick && option.lowercased() == selected.lowercased() { return .white }
        if nounMCLocked { return AppTheme.Colors.textPrimary.opacity(0.5) }
        return .white
    }

    func nounMCButtonBackground(_ option: String) -> Color {
        guard let selected = nounMCSelected else { return trainingActionTint }
        let correct = nounCorrectAnswer.lowercased()
        let isCorrectPick = selected.lowercased() == correct
        if isCorrectPick && option.lowercased() == correct { return AppTheme.Colors.success }
        if !isCorrectPick && option.lowercased() == selected.lowercased() { return Color(red: 0.9, green: 0.3, blue: 0.15) }
        if nounMCLocked { return AppTheme.Colors.secondarySurface }
        return trainingActionTint
    }


    var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                toggleRecording()
            } label: {
                // Feedback-Texte und Idle/Recording-Icon müssen ihren
                // Farb-Kontext getrennt halten: Texte und Stop-Symbol tragen
                // die foregroundStyle-Tönung (weiß / rot), das Cartoon-
                // Mikrofon kommt mit eigener Farbe und ignoriert Tints.
                Group {
                    if showsSuccessOnlyMessage {
                        Text("Richtig 🙂")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    } else if showsRetryOnlyMessage {
                        Text("Falsch 😕")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    } else if isSpeechRecording {
                        // Recording: klassisches rotes Stop-Quadrat
                        // (OS-Konvention, nicht Teil des Cartoon-Sets).
                        Image(systemName: "stop.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.error)
                    } else {
                        // Idle: Cartoon-Mikrofon.
                        ElumiIconView(icon: .mikrofon, size: 32)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: actionButtonHeight)
                .background(recordingButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(isSpeechRecording && isMicPulseVisible ? 0.28 : 0), lineWidth: 2)
                    .animation(.easeInOut(duration: 0.55), value: isMicPulseVisible)
            }
            .disabled(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled || !canUseSpeechRecognition)
            .opacity(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled || !canUseSpeechRecognition ? 0.45 : (isSpeechRecording && isMicPulseVisible ? 0.72 : 1))

            typedAnswerControl

            Button {
                speakCurrentPrompt()
            } label: {
                // Cartoon-Lautsprecher statt SF `speaker.wave.2.fill`.
                // State-Signal bleibt am Background (listeningButtonColor),
                // das Icon selbst ist konstant farbig.
                ElumiIconView(icon: .lautsprecher, size: 32)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
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
                    // Wichtig: Für Verben-MC die Optionen für die neue Karte neu aufbauen,
                    // sonst bleiben die alten Optionen stehen und das Lösungswort
                    // der neuen Runde fehlt.
                    if isVerbMode {
                        verbMCSelected = nil
                        verbMCLocked = false
                        prepareVerbMCOptions()
                    }
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

    var typedAnswerControl: some View {
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
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
            } else {
                Button {
                    guard session.hasStartedTraining, currentCard != nil else { return }
                    stopListeningForTyping()
                    showingTypedAnswerInput = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        typedAnswerFieldFocused = true
                    }
                } label: {
                    // Cartoon-Tastatur als Modus-Öffner. Das Inline-SF
                    // `keyboard` innerhalb der aktiven Input-Card (oben)
                    // bleibt bewusst SF — dort ist es eine schmale
                    // Affordance, kein primärer Action-Slot.
                    ElumiIconView(icon: .tastatur, size: 32)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: actionButtonHeight)
                        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium)
                }
                .buttonStyle(.plain)
                .disabled(!session.hasStartedTraining || currentCard == nil)
                .opacity(!session.hasStartedTraining || currentCard == nil ? 0.5 : 1)
            }
        }
    }
}
