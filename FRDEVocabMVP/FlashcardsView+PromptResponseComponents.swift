import SwiftUI

extension FlashcardsView {
    var flashcardPromptCard: some View {
        Group {
            if let currentFlashCard, sessionStore.hasActiveSession {
                // Hinweis: progressText / masteryProgressBar wurden in den Header-
                // Stats-Row (`flashcardStatsRow`) verschoben, damit die Karteikarte
                // selbst optisch ruhig bleibt.
                //
                // **Design-Phase 8**: Karte zeigt rechts oben einen Streak-Block
                // (Dots). Streak kommt direkt aus dem SM-2-Datenmodell
                // (`CardMastery.consecutiveCorrect` via `session.cardMastery`),
                // also KEINE neue Datenstruktur. Card-Index ist die 1-basierte
                // Position des Decks — zeigt dem Lerner, wo im Stapel er steht.
                //
                // **Personal-Deck-Variante (Phase 8)**: Wenn die Session aus
                // einem PersonalDeck läuft (`activePersonalDeckID` gesetzt),
                // zeigen Card-Index + Total die Gesamt-Position im
                // Personal-Deck statt der Session-internen Position. Damit
                // matcht das Tag-Label der User-Spec „Français · 248 / 1.300".
                let activePersonalDeck = sessionStore.activePersonalDeckID.flatMap {
                    personalDeckStore.deck(withID: $0)
                }
                let cardIndex: Int = {
                    if let deck = activePersonalDeck {
                        return min(deck.currentIndex + 1, deck.cardOrder.count)
                    }
                    guard let cardID = sessionStore.session?.currentCardID,
                          let index = sessionStore.selectedDeck.cards.firstIndex(where: { $0.id == cardID }) else {
                        return 1
                    }
                    return index + 1
                }()
                let totalCards: Int = activePersonalDeck?.cardOrder.count ?? sessionStore.totalCount
                let streakValue: Int = {
                    guard let cardID = sessionStore.session?.currentCardID,
                          let mastery = sessionStore.session?.cardMastery[cardID] else {
                        return 0
                    }
                    return mastery.consecutiveCorrect
                }()
                // Dot-Anzahl = wie oft muss die Karte korrekt sein, bis sie
                // aus dem Stapel fällt. Kommt direkt aus der aktiven
                // Session, damit Mitten-drin-Threshold-Änderungen nicht
                // zu Inkonsistenz führen.
                let streakTargetValue = sessionStore.masteryThreshold

                VStack(spacing: 6) {
                    // **Personal-Deck-Badge (Phase 8)** — kleiner Hinweis
                    // oben-links über der Karte, der das Stapel-Branding
                    // zeigt. Nur sichtbar, wenn eine Personal-Deck-Session
                    // läuft. Dot in Deck-Farbe + Stapelname.
                    if let deck = activePersonalDeck {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(PersonalDeck.color(for: deck.colorIndex))
                                .frame(width: 5, height: 5)
                            Text(deck.name)
                                .font(.system(size: 7, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Color(hex: "#1A3A55"), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Stack-Badge unten links/rechts entfernt — die Stats-Row
                    // oben zeigt die gleichen Counts schon prominent.
                    ZStack {
                        flashcardFace(
                            text: currentFlashCard.prompt,
                            isAnswerSide: false,
                            languageCode: currentFlashCard.promptLanguageCode,
                            wordClassLabel: currentFlashCard.wordClassLabel(for: currentFlashCard.promptLanguageCode),
                            cardIndex: cardIndex,
                            totalCount: totalCards,
                            streak: streakValue,
                            streakTarget: streakTargetValue,
                            hidesCardCounter: launchContext?.chainContext != nil
                        )
                        .opacity(interaction.isFlashcardFlipped ? 0 : 1)

                        flashcardFace(
                            text: currentFlashCard.answer,
                            isAnswerSide: true,
                            languageCode: currentFlashCard.answerLanguageCode,
                            wordClassLabel: currentFlashCard.wordClassLabel(for: currentFlashCard.answerLanguageCode),
                            cardIndex: cardIndex,
                            totalCount: totalCards,
                            streak: streakValue,
                            streakTarget: streakTargetValue,
                            hidesCardCounter: launchContext?.chainContext != nil
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
                    .frame(maxWidth: .infinity)
                    .frame(height: flashcardFaceHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isSessionReady else { return }
                        feedbackPlayer.playCardFlip()
                        if interaction.showingSolution {
                            interaction.flipBackToFront(dismissTypedAnswerFocus: { dismissTypedAnswerFocus() })
                        } else {
                            interaction.revealSolution(
                                sessionStore: sessionStore,
                                speechController: speechController,
                                // **Ansehen-Modus** — im View-Mode ist das
                                // Aufdecken der Flow, kein Spicken → peek-frei.
                                countsAsPeek: interaction.answerMode != .view,
                                dismissTypedAnswerFocus: { dismissTypedAnswerFocus() }
                            )
                        }
                    }
                    // Drag-State + Rotation: Karte folgt dem Finger und kippt
                    // leicht in Wischrichtung (max. ±8°).
                    .offset(x: interaction.swipeDragOffset)
                    .rotationEffect(.degrees(swipeRotationDegrees))
                    .gesture(flashcardSwipeGesture)
                    // KEIN globaler `.animation(value:)` — wir steuern alle
                    // Bewegungen explizit (live folgen beim Drag, Spring-Back
                    // und Fly-Out-/Slide-In bei Karten-Wechsel).

                    // **Personal-Deck-Footer-Hinweis (Phase 8)**: „X aktiv
                    // verbleibend" unten-links unter der Karte. Zeigt
                    // Gesamtkarten minus gemastered — gibt dem Lerner ein
                    // klares „soviel bleibt noch übrig"-Gefühl.
                    if let deck = activePersonalDeck {
                        HStack {
                            Text("\(deck.activeRemainingCount) aktiv verbleibend")
                                .font(.system(size: 7, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.25))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
                    }

                    // **Peek-Toast (User-Revision 2026-04-22)**: kurzer
                    // Hinweis unter der Karte, wenn der User sie manuell
                    // geflippt hat. Fade-in/out via `peekToastVisible`,
                    // getriggert vom `triggerPeekToast()` im Controller.
                    if interaction.peekToastVisible {
                        Text("Karte als nicht gekonnt gewertet")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 1.0, green: 100.0/255.0, blue: 100.0/255.0).opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .transition(.opacity)
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
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.subtle)
            }
        }
    }

    var flashcardResponseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFlashcardSessionCompleted {
                Text("Alle Karten aus dem Stapel sind raus. 🙂")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.success)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if interaction.isAwaitingContinueAfterWrong {
                // **User-Revision 2026-04-22**: Falsch-Antwort-Flow —
                // Karte bleibt auf der Rückseite, User steuert den
                // Wechsel selbst über „Weiter". Rote Hinweiszeile +
                // CTA-Pill in Modul-Akzent.
                //
                // **Block 2.5 (2026-05-02, Subpunkt 2)** — User-Spec:
                // im Chain-Mode den roten Text-Hint ausblenden, der
                // „Weiter"-Button bleibt aber erhalten (User braucht
                // den zum nächsten Card-Advance). Außerhalb Chain
                // unverändert wie heute.
                VStack(alignment: .center, spacing: 10) {
                    if launchContext?.chainContext == nil {
                        Text("Falsch 😕 — schau dir die Lösung an")
                            .font(AppTheme.Typography.body)
                            .foregroundStyle(AppTheme.Colors.error)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Button {
                        interaction.continueAfterWrongAnswer(
                            sessionStore: sessionStore,
                            speechController: speechController,
                            speaker: speaker,
                            feedbackPlayer: feedbackPlayer
                        )
                    } label: {
                        Text("Weiter")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.Colors.cta)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if interaction.showingSolution {
                Text("Rückseite geöffnet")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(sectionStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if interaction.lastResult?.label == "Nicht erkannt" {
                Text("Nicht erkannt, bitte nochmal versuchen.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if sessionStore.hasActiveSession {
                // 2pt kleiner als `AppTheme.Typography.body` (14 statt 16),
                // damit die „Antwort"-Card kompakter wirkt.
                Text("Antwort")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(speechController.transcript.isEmpty ? "Noch nichts erkannt" : speechController.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    // Idle: elumiBlue (Info-Token, konsistent mit Setup-Subtitles).
                    // Aktiver Transcript: CTA-Amber (#FFD166) — neuer App-Akzent.
                    .foregroundStyle(speechController.transcript.isEmpty ? AppTheme.Colors.elumiBlue : AppTheme.Colors.cta)
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
        .frame(minHeight: 38, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .appSetupCardBackground()
    }

    var masteryProgressBar: some View {
        GeometryReader { geo in
            let total = max(sessionStore.totalCount, 1)
            let width = geo.size.width
            let masteredW = width * CGFloat(sessionStore.masteredCount) / CGFloat(total)
            let almostW = width * CGFloat(sessionStore.almostMasteredCount) / CGFloat(total)
            let wrongW = width * CGFloat(sessionStore.wrongAnsweredCardCount) / CGFloat(total)

            ZStack(alignment: .leading) {
                // Hintergrund: noch offene Karten (grau).
                Capsule()
                    .fill(AppTheme.Colors.textSecondary.opacity(0.2))

                // Rote „Problem"-Markierung am rechten Rand — unique Karten,
                // die mind. einmal falsch waren und noch im Stapel sind.
                // Über den grauen Hintergrund gelegt, wird aber von den
                // grünen/gelben Progress-Segmenten (links) überdeckt.
                if wrongW > 0 {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Capsule()
                            .fill(AppTheme.Colors.error.opacity(0.75))
                            .frame(width: wrongW)
                    }
                }

                // Fast-sicher-Bereich (gelb) — Mastered + Almost.
                Capsule()
                    .fill(AppTheme.Colors.warning.opacity(0.7))
                    .frame(width: max(0, masteredW + almostW))

                // Sicher (grün) — vollständig gemasterte Karten.
                Capsule()
                    .fill(AppTheme.Colors.success)
                    .frame(width: max(0, masteredW))
            }
        }
    }

    /// Swipe-Geste auf der Karteikarte. Karte folgt dem Finger; bei einer
    /// horizontalen Bewegung > 50pt wird die Karte „weggewischt" und die
    /// nächste/vorherige Karte angezeigt. Sonst springt sie zurück.
    var flashcardSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard isSessionReady else { return }
                // **Ansehen-Modus (2026-05-22)** — Swipes deaktiviert; im
                // View-Mode steuern ausschließlich die 2 Bewertungs-Buttons.
                guard interaction.answerMode != .view else { return }
                // Vertikale Drags ignorieren — verhindert Konflikte mit Scroll.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                // Live ohne Animation, damit die Karte exakt am Finger klebt.
                interaction.swipeDragOffset = value.translation.width
            }
            .onEnded { value in
                guard interaction.answerMode != .view else { return }
                guard isSessionReady else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        interaction.swipeDragOffset = 0
                    }
                    return
                }
                let threshold: CGFloat = 50
                let dx = value.translation.width

                if dx <= -threshold {
                    // Wisch nach links → nächste Karte
                    triggerSwipeOut(direction: .left)
                } else if dx >= threshold {
                    // Wisch nach rechts → vorherige Karte
                    triggerSwipeOut(direction: .right)
                } else {
                    // Zu kurz → Spring-Back zur Mitte
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        interaction.swipeDragOffset = 0
                    }
                }
            }
    }

    /// Rotations-Winkel proportional zur Drag-Distanz, gedeckelt auf ±8°.
    /// Computed Property statt inline-Math, damit der Type-Check sauber bleibt.
    var swipeRotationDegrees: Double {
        let raw = Double(interaction.swipeDragOffset) / 28.0
        return min(max(raw, -8), 8)
    }

    /// Wisch-Hinweis-Card — separat von `flashcardPromptCard`, damit sie nicht
    /// vom Fly-Out-Modifier der Karte mitgezogen wird und das Layout sie
    /// unabhängig zwischen Karte und Antwort-Block platzieren kann.
    /// Verschwindet nach dem ersten Swipe (`hasSeenSwipeHint`).
    @ViewBuilder
    var flashcardSwipeHintCard: some View {
        // **Ansehen-Modus (2026-05-22)** — kein Wisch-Hinweis, da Swipes
        // im View-Mode deaktiviert sind (nur die 2 Bewertungs-Buttons).
        if !interaction.hasSeenSwipeHint, sessionStore.hasActiveSession,
           interaction.answerMode != .view {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("wischen")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.7))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .appSetupCardBackground()
            .transition(.opacity)
        }
    }

    enum SwipeDirection { case left, right }

    /// Animiert die Karte aus dem Bildschirm raus, gibt Haptic-Feedback und
    /// triggert dann den Karten-Wechsel. Die NEUE Karte fliegt anschließend
    /// von der gegenüberliegenden Seite hinein — Wisch nach links: aktuelle
    /// Karte raus links, neue rein von rechts; Wisch nach rechts: aktuelle
    /// raus rechts, neue (vorherige) rein von links.
    func triggerSwipeOut(direction: SwipeDirection) {
        // Haptic Feedback — bewusst leicht (light) für unauffällige Bestätigung.
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()

        interaction.markSwipeHintSeen()

        let flyOut: CGFloat = direction == .left ? -500 : 500
        let outDuration: TimeInterval = 0.22

        withAnimation(.easeOut(duration: outDuration)) {
            interaction.swipeDragOffset = flyOut
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + outDuration) {
            // 1. Karten-Daten wechseln
            switch direction {
            case .left:
                if isSessionReady { skipCard() }
            case .right:
                if canRestorePreviousFlashcard { restorePreviousFlashcard() }
            }

            // 2. Neue Karte SOFORT auf gegenüberliegende Seite teleportieren
            //    (ohne Animation), damit der nachfolgende Slide-In sichtbar wird.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                interaction.swipeDragOffset = -flyOut
            }

            // 3. Im nächsten RunLoop-Tick die neue Karte in die Mitte gleiten
            //    lassen — easeOut wirkt natürlicher als spring fürs Slide-In.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.28)) {
                    interaction.swipeDragOffset = 0
                }
            }
        }
    }
}

