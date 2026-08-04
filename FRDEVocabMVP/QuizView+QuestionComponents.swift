import SwiftUI

extension QuizView {
    func typingCard(_ question: QuizTypingQuestion) -> some View {
        AppSurfaceCard(tint: sectionStyle.accent) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Eintippen")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(visibleQuizPromptText(question.prompt, category: question.category))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppTheme.Spacing.sm)

                if let correctAnswer = typingShowCorrectAnswer {
                    VStack(spacing: 4) {
                        Text("Richtige Antwort:")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Text(correctAnswer)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.success)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppTheme.Spacing.xs)
                } else {
                    // **Eingabefeld-Vereinheitlichung Modul 2 (2026-05-22)** —
                    // dunkles secondarySurface-Feld → cream-Look via geteilter
                    // AppInputField (wie KK). Quiz-Eigenheit: zentrierter Text
                    // (`alignment: .center`). Der frühere Accent-Border entfällt
                    // zugunsten des einheitlichen cream-Borders.
                    AppInputField(
                        placeholder: "Antwort eingeben",
                        text: $typingInput,
                        accent: sectionStyle.accent,
                        // **2026-06-09** — Grün bei richtiger Antwort in
                        // ALLEN Modi. Vorher nur im Daily-Drop-Count-Modus
                        // (`isCountChainStep && quizAwaitingWeiter`), im
                        // normalen Quiz gab es keine sichtbare Bestätigung.
                        resultState: typingWasCorrect ? .correct : .none,
                        alignment: .center,
                        isEnabled: !typingLocked,
                        focus: $isTypingFieldFocused,
                        onSubmit: { submitTyping(for: question) }
                    )

                    // **Daily Drop Modul 2.12 (2026-05-23)** — im Count-Modus
                    // verschwindet „Überprüfen" sobald geprüft wurde; dann
                    // übernimmt der externe „Weiter"-Button. Bei leerer Eingabe
                    // ist es deaktiviert (kein Check ohne Inhalt) — dadurch
                    // bleibt „Weiter" gedimmt, bis etwas eingegeben + geprüft
                    // wurde (User-Spec 2.12).
                    if !(isCountChainStep && quizAwaitingWeiter) {
                        let trimmedEmpty = typingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Button {
                            submitTyping(for: question)
                        } label: {
                            Text("Überprüfen")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppPrimaryButtonStyle(color: trimmedEmpty ? AppTheme.Colors.textDisabled : AppTheme.Colors.cta))
                        .disabled(trimmedEmpty || typingLocked)
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTypingFieldFocused = true
            }
        }
    }

    func multipleChoiceCard(_ question: QuizMultipleChoiceQuestion) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    // **Daily Drop Modul 2.12 (2026-05-23)** — „Multiple Choice"-
                    // Typ-Label entfernt (User-Spec, generell): die Antwort-
                    // Chips erklären den Aufgabentyp selbst. Andere Typ-Labels
                    // („Eintippen", „Paare finden" …) bleiben.
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
                        // **Daily Drop Modul 2.12 (2026-05-23)** — nach der
                        // Antwort nur die Interaktion sperren, NICHT `.disabled`:
                        // disabled dimmt SwiftUI-weit den Button-Inhalt (auch die
                        // weiße Schrift auf grün/rot wirkt dann ausgegraut).
                        // `allowsHitTesting(false)` hält die Optik voll hell; ein
                        // Re-Tap wird ohnehin vom Guard in `submitMultipleChoice`
                        // abgefangen.
                        .allowsHitTesting(!multipleChoiceLocked)
                    }
                }
            }
        }
    }

    func matchingCard(_ question: QuizMatchingQuestion) -> some View {
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
                            // **2026-06-09** — Beide Seiten gemeinsam
                            // punktieren: sie sind derselbe Satz in zwei
                            // Sprachen, also darf nicht links ein Punkt
                            // und rechts ein Fragezeichen stehen.
                            Text(visibleQuizPairTexts(
                                prompt: pair.prompt,
                                answer: pair.answer,
                                category: question.category
                            ).prompt)
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
                                .zIndex(draggingPromptID == pair.id ? 100 : 0)
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
                    .zIndex(draggingPromptID != nil ? 10 : 0)

                    VStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(question.shuffledAnswers) { pair in
                            Text(visibleQuizPairTexts(
                                prompt: pair.prompt,
                                answer: pair.answer,
                                category: question.category
                            ).answer)
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(matchingTextColor(for: pair.id, isAnswerSide: true))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .padding(.horizontal, AppTheme.Spacing.sm)
                                .background(matchingBackground(for: pair.id, isAnswerSide: true))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                        .stroke(matchingBorderColor(for: pair.id, isAnswerSide: true), lineWidth: matchingBorderWidth(for: pair.id, isAnswerSide: true))
                                )
                                .shadow(color: matchingShadowColor(for: pair.id, isAnswerSide: true), radius: 8, x: 0, y: 4)
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

    // MARK: - Fill-in-the-Blanks Card

    func fillBlanksCard(_ question: QuizFillBlanksQuestion) -> some View {
        AppSurfaceCard(tint: sectionStyle.accent) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Ergänze das fehlende Wort")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                // Sentence with blank
                fillBlanksSentenceView(question)

                // Translation hint
                Text(question.translationHint)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Options 2×2
                let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            guard !fillBlanksLocked, !fillBlanksWrongOptions.contains(option) else { return }
                            fillBlanksSelected = option
                            submitFillBlanks(for: question)
                        } label: {
                            Text(option)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(fillBlanksChipColor(option, correct: question.correctAnswer).text)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                                .background(fillBlanksChipColor(option, correct: question.correctAnswer).bg)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .opacity(fillBlanksWrongOptions.contains(option) ? 0.3 : 1)
                        .disabled(fillBlanksLocked || fillBlanksWrongOptions.contains(option))
                    }
                }
            }
        }
    }

    private func fillBlanksSentenceView(_ question: QuizFillBlanksQuestion) -> some View {
        let parts = question.sentenceWithBlank.components(separatedBy: "_____")
        let before = parts.first ?? ""
        let after = parts.count >= 2 ? parts[1] : ""

        let isCorrect = fillBlanksLocked && fillBlanksSelected == question.correctAnswer
        let blankDisplay = isCorrect ? question.correctAnswer : "______"

        let blankColor: Color = isCorrect ? AppTheme.Colors.success : sectionStyle.accent
        let blankWeight: Font.Weight = isCorrect ? .black : .bold

        return Text(buildFillBlanksAttributedText(
            before: before,
            blank: blankDisplay,
            after: after,
            blankColor: blankColor,
            blankWeight: blankWeight
        ))
        .font(.system(size: 18, weight: .semibold, design: .rounded))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 60)
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func buildFillBlanksAttributedText(before: String, blank: String, after: String, blankColor: Color, blankWeight: Font.Weight) -> AttributedString {
        // **UX-Polish 2026-05-02 (User-Befund)**: ohne expliziten
        // `foregroundColor` auf `before`/`after` rendert SwiftUI die
        // FR-Frage-Schrift im System-Default-Schwarz auf dem dunklen
        // `AppSurfaceCard`-Hintergrund — unlesbar. Nur das Blank-
        // Glyph hatte explizit `blankColor` (sectionStyle.accent /
        // success). Mit `textPrimary` (cream/off-white) ist die
        // Frage jetzt klar lesbar, konsistent zu den anderen Text-
        // Tokens auf Card-Surfaces. Analoger Quick-Fix wie für den
        // Quiz-Typing-Input in Commit `6732570`.
        var beforePart = AttributedString(before)
        beforePart.foregroundColor = AppTheme.Colors.textPrimary
        var blankPart = AttributedString(blank)
        blankPart.foregroundColor = blankColor
        blankPart.font = .system(size: 18, weight: blankWeight, design: .rounded)
        var afterPart = AttributedString(after)
        afterPart.foregroundColor = AppTheme.Colors.textPrimary
        return beforePart + blankPart + afterPart
    }

    private func fillBlanksChipColor(_ option: String, correct: String) -> (text: Color, bg: Color) {
        // Correct answer locked in
        if fillBlanksLocked, fillBlanksSelected == option, option == correct {
            return (.white, AppTheme.Colors.success)
        }
        // Flash the wrong chip that was just tapped
        if fillBlanksFlashWrong == option {
            return (.white, AppTheme.Colors.error)
        }
        return (AppTheme.Colors.textPrimary, AppTheme.Colors.secondarySurface)
    }

    // MARK: - Word Combo Card

    func wordComboCard(_ question: QuizMatchingQuestion) -> some View {
        AppSurfaceCard(tint: AppTheme.Colors.warning) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Verbinde den Ausdruck")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(comboSelectedVerbID == nil ? "Tippe zuerst auf ein Verb, dann auf das passende Nomen." : "Jetzt das passende Nomen tippen.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(comboSelectedVerbID == nil ? AppTheme.Colors.textSecondary : AppTheme.Colors.warning)

                // Verbs row
                VStack(alignment: .leading, spacing: 6) {
                    Text("Verb")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    HStack(spacing: 6) {
                        ForEach(question.pairs) { pair in
                            Button {
                                guard !comboMatchedIDs.contains(pair.id) else { return }
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    comboSelectedVerbID = pair.id
                                }
                            } label: {
                                Text(pair.prompt)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.75)
                                    .foregroundStyle(comboVerbTextColor(pair.id))
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                                    .background(comboVerbBackground(pair.id))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(comboVerbBorder(pair.id), lineWidth: comboSelectedVerbID == pair.id ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .opacity(comboMatchedIDs.contains(pair.id) ? 0.4 : 1)
                        }
                    }
                }

                // Divider
                HStack {
                    Spacer()
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.5))
                    Spacer()
                }

                // Nouns row (shuffled)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nomen")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    HStack(spacing: 6) {
                        ForEach(question.shuffledAnswers) { pair in
                            Button {
                                guard comboSelectedVerbID != nil, !comboMatchedIDs.contains(pair.id) else { return }
                                evaluateComboSelection(verbID: comboSelectedVerbID!, nounPair: pair, in: question)
                            } label: {
                                Text(pair.answer)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.75)
                                    .foregroundStyle(comboNounTextColor(pair.id))
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                                    .background(comboNounBackground(pair.id))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(comboNounBorder(pair.id), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .opacity(comboMatchedIDs.contains(pair.id) ? 0.4 : 1)
                        }
                    }
                }
            }
        }
    }

    private func evaluateComboSelection(verbID: UUID, nounPair: QuizMatchingPair, in question: QuizMatchingQuestion) {
        // The correct noun for this verb has the same ID as the verb (pairs share IDs)
        if verbID == nounPair.id {
            // Correct match
            feedbackPlayer.playStudySuccess()
            withAnimation(.easeInOut(duration: 0.2)) {
                comboMatchedIDs.insert(verbID)
                comboSelectedVerbID = nil
            }
            if comboMatchedIDs.count >= question.pairs.count {
                // **Daily Drop Modul 2.12 (2026-05-23)** — 1 Übung (1 Tick),
                // `correct = !comboHadMistake`. Count-Modus: kein Auto-Advance,
                // „Weiter"-Button übernimmt (gelegte Paare bleiben grün).
                let isCorrect = !comboHadMistake
                scheduleAdvance(after: 0.6) {
                    if isCountChainStep {
                        quizPendingCorrect = isCorrect
                        quizAwaitingWeiter = true
                    } else {
                        completeCurrentQuestion(correct: isCorrect)
                    }
                }
            }
        } else {
            // Wrong match
            feedbackPlayer.playStudyError()
            comboHadMistake = true
            comboFlashVerbID = verbID
            comboFlashNounID = nounPair.id
            scheduleAdvance(after: 0.5) {
                comboFlashVerbID = nil
                comboFlashNounID = nil
                comboSelectedVerbID = nil
            }
        }
    }

    private func comboVerbTextColor(_ id: UUID) -> Color {
        if comboMatchedIDs.contains(id) { return AppTheme.Colors.success }
        if comboFlashVerbID == id { return .white }
        if comboSelectedVerbID == id { return .white }
        return AppTheme.Colors.textPrimary
    }

    private func comboVerbBackground(_ id: UUID) -> Color {
        if comboMatchedIDs.contains(id) { return AppTheme.Colors.success.opacity(0.15) }
        if comboFlashVerbID == id { return AppTheme.Colors.error }
        if comboSelectedVerbID == id { return AppTheme.Colors.warning }
        return AppTheme.Colors.secondarySurface
    }

    private func comboVerbBorder(_ id: UUID) -> Color {
        if comboSelectedVerbID == id { return AppTheme.Colors.warning }
        if comboMatchedIDs.contains(id) { return AppTheme.Colors.success.opacity(0.3) }
        return AppTheme.Colors.borderStrong.opacity(0.2)
    }

    private func comboNounTextColor(_ id: UUID) -> Color {
        if comboMatchedIDs.contains(id) { return AppTheme.Colors.success }
        if comboFlashNounID == id { return .white }
        return AppTheme.Colors.textPrimary
    }

    private func comboNounBackground(_ id: UUID) -> Color {
        if comboMatchedIDs.contains(id) { return AppTheme.Colors.success.opacity(0.15) }
        if comboFlashNounID == id { return AppTheme.Colors.error }
        return AppTheme.Colors.secondarySurface
    }

    private func comboNounBorder(_ id: UUID) -> Color {
        if comboMatchedIDs.contains(id) { return AppTheme.Colors.success.opacity(0.3) }
        return AppTheme.Colors.borderStrong.opacity(0.2)
    }

    var quizProgressBar: some View {
        HStack(spacing: 6) {
            ForEach(Array((0..<displayedQuestionCount).enumerated()), id: \.offset) { index, _ in
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(progressColor(for: index))
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
            }
        }
    }

    func progressColor(for index: Int) -> Color {
        guard index < session.answeredResults.count else {
            return AppTheme.Colors.secondarySurface
        }
        return session.answeredResults[index] ? AppTheme.Colors.success : AppTheme.Colors.error
    }

    func multipleChoiceBackground(for option: String, correctAnswer: String) -> Color {
        guard multipleChoiceLocked else {
            return AppTheme.Colors.secondarySurface
        }
        // **Daily Drop Modul 2.12 (2026-05-23)** — nach der Antwort die
        // richtige (grün) und die falsch angetippte (rot) Option HELL
        // hinterlegen statt nur 18 % Deckkraft (User-Befund: wirkte
        // gedimmt). Volle Akzentfläche + weißer Text/Icon — analog zum
        // Lückentext-Chip (`fillBlanksChipColor`).
        if normalizedLookupText(option) == normalizedLookupText(correctAnswer) {
            return AppTheme.Colors.success
        }
        if selectedMultipleChoiceOption == option {
            return AppTheme.Colors.error
        }
        return AppTheme.Colors.secondarySurface
    }

    func multipleChoiceTextColor(for option: String, correctAnswer: String) -> Color {
        guard multipleChoiceLocked else {
            return AppTheme.Colors.textPrimary
        }
        // Weißer Text/Icon auf der vollen grünen/roten Fläche (s. o.) —
        // klarer Kontrast statt farbiger Text auf zarter Tönung.
        if normalizedLookupText(option) == normalizedLookupText(correctAnswer) {
            return .white
        }
        if selectedMultipleChoiceOption == option {
            return .white
        }
        return AppTheme.Colors.textPrimary
    }

    func multipleChoiceIcon(for option: String, correctAnswer: String) -> String {
        guard multipleChoiceLocked else { return "circle.fill" }
        if normalizedLookupText(option) == normalizedLookupText(correctAnswer) {
            return "checkmark.circle.fill"
        }
        if selectedMultipleChoiceOption == option {
            return "xmark.circle.fill"
        }
        return "circle.fill"
    }

    /// Prüft, ob dieses Card-Rendering (prompt-side ODER answer-side)
    /// gerade als falsch geflasht werden soll. Seitenspezifisch —
    /// `flashingPromptID` gilt **nur** fürs Prompt-Kartensatz,
    /// `flashingAnswerID` **nur** fürs Answer-Kartensatz.
    /// Fix gegen den Bug, dass bei einem falschen Drop ZWEI zusätzliche
    /// Karten (Prompt-Shadow des Answers + Answer-Shadow des Prompts)
    /// mit rot geleuchtet sind, weil `pair.id` auf beiden Seiten geteilt ist.
    private func isFlashingWrong(_ pairID: UUID, isAnswerSide: Bool) -> Bool {
        isAnswerSide
            ? pairID == flashingAnswerID
            : pairID == flashingPromptID
    }

    func matchingBackground(for pairID: UUID, isAnswerSide: Bool = false) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success.opacity(0.18)
        }
        if isFlashingWrong(pairID, isAnswerSide: isAnswerSide) {
            return AppTheme.Colors.error.opacity(0.2)
        }
        if !isAnswerSide, pairID == draggingPromptID {
            return AppTheme.Colors.warning.opacity(0.22)
        }
        if !isAnswerSide, pairID == selectedPromptID {
            return AppTheme.Colors.primary.opacity(0.14)
        }
        if isAnswerSide, pairID == selectedAnswerID {
            return AppTheme.Colors.primary.opacity(0.14)
        }
        return AppTheme.Colors.secondarySurface
    }

    func matchingTextColor(for pairID: UUID, isAnswerSide: Bool = false) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success
        }
        if isFlashingWrong(pairID, isAnswerSide: isAnswerSide) {
            return AppTheme.Colors.error
        }
        if !isAnswerSide, pairID == draggingPromptID {
            return AppTheme.Colors.warning
        }
        if !isAnswerSide, pairID == selectedPromptID {
            return AppTheme.Colors.primary
        }
        if isAnswerSide, pairID == selectedAnswerID {
            return AppTheme.Colors.primary
        }
        return AppTheme.Colors.textPrimary
    }

    func matchingBorderColor(for pairID: UUID, isAnswerSide: Bool = false) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success.opacity(0.7)
        }
        if isFlashingWrong(pairID, isAnswerSide: isAnswerSide) {
            return AppTheme.Colors.error.opacity(0.75)
        }
        if !isAnswerSide, pairID == draggingPromptID {
            return AppTheme.Colors.warning.opacity(0.92)
        }
        if !isAnswerSide, pairID == selectedPromptID {
            return AppTheme.Colors.primary.opacity(0.45)
        }
        if isAnswerSide, pairID == selectedAnswerID {
            return AppTheme.Colors.primary.opacity(0.45)
        }
        return AppTheme.Colors.borderStrong
    }

    func matchingBorderWidth(for pairID: UUID, isAnswerSide: Bool = false) -> CGFloat {
        if !isAnswerSide, pairID == draggingPromptID {
            return 2
        }
        if matchedPairIDs.contains(pairID) || isFlashingWrong(pairID, isAnswerSide: isAnswerSide) {
            return 1.6
        }
        return 1
    }

    func matchingShadowColor(for pairID: UUID, isAnswerSide: Bool = false) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success.opacity(0.18)
        }
        if isFlashingWrong(pairID, isAnswerSide: isAnswerSide) {
            return AppTheme.Colors.error.opacity(0.18)
        }
        if !isAnswerSide, pairID == draggingPromptID {
            return AppTheme.Colors.warning.opacity(0.24)
        }
        return AppTheme.Colors.shadow
    }
}
