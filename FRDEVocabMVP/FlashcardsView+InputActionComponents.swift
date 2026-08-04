import SwiftUI

extension FlashcardsView {
    var flashcardTypedAnswerCard: some View {
        Group {
            // **Sweep C — AnswerMode (2026-05-07)** — Bei `.tap` ist
            // die Typed-Answer-Card die **primäre** Eingabe (immer
            // sichtbar). Bei `.speech` bleibt der frühere Reveal-on-
            // Tap-Pfad via `showingTypedAnswerInput` erhalten — User
            // kann Tastatur als Fallback nachträglich anfordern.
            if interaction.showingTypedAnswerInput || interaction.answerMode == .tap {
                HStack(spacing: 8) {
                    // **Eingabefeld-Vereinheitlichung Modul 1 (2026-05-22)** —
                    // KK ist der Pilot für die geteilte `AppInputField`-
                    // Komponente (cream-Look). Optik unverändert; nur die
                    // Quelle wandert von inline → gemeinsame Komponente.
                    AppInputField(
                        placeholder: "Antwort tippen",
                        text: $interaction.typedAnswer,
                        accent: sectionStyle.accent,
                        isEnabled: isSessionReady,
                        focus: $isTypedAnswerFocused,
                        onSubmit: { submitTypedAnswer() },
                        onTap: {
                            interaction.handleAudioModeChange(
                                isEnabled: false,
                                speechController: speechController,
                                speaker: speaker
                            )
                        }
                    )

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
                    // **Feste Breite (2026-05-22)** — klammert das interne
                    // `maxWidth: .infinity` von AppPrimaryButtonStyle, damit
                    // das Eingabefeld die Restbreite bekommt (vorher drückte
                    // der greedy Button das Feld auf ~die Hälfte).
                    .frame(width: 100)
                    .disabled(!isSessionReady || interaction.typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .frame(maxWidth: AppTheme.Layout.maxContentWidth)
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium)
                .shadow(color: AppTheme.Shadow.card.color, radius: 12, x: 0, y: 8)
            }
        }
    }

    /// Primäre Aktionen (Mikro + Lautsprecher + Tastatur) — bilden den
    /// oberen Action-Block direkt unter der Karteikarte.
    ///
    /// **Sweep C — AnswerMode (2026-05-07)** — Speech-Mode-only.
    /// **2026-05-08** — Tap-Mode-Branch entfernt (User-Spec „kein
    /// Vorsprech-Modul im Tippen-Modus"). Im Tap-Mode wird der
    /// gesamte Action-Block am Call-Site (siehe
    /// `flashcardSessionScreen` in `+Layout.swift`) übersprungen —
    /// die Typed-Answer-Card im Overlay ist die einzige Eingabe.
    var flashcardPrimaryActions: some View {
        VStack(spacing: 10) {
            speechModeActionRows
        }
    }

    /// **Ansehen-Modus (2026-05-22)** — untere UI im View-Mode. Zwei
    /// Selbst-Bewertungs-Buttons, sichtbar erst nach dem Aufdecken der
    /// Karte (`showingSolution`); davor ein dezenter Tipp-Hinweis.
    /// Kein Mikro / kein Eingabefeld — der Speech-/Tap-Block entfällt.
    @ViewBuilder
    var flashcardSelfRatingActions: some View {
        if interaction.showingSolution {
            HStack(spacing: 10) {
                // Reihenfolge wie Spec: „Kann ich" (grün) links,
                // „Kann ich nicht" (rot) rechts.
                selfRatingButton(title: "Kann ich", color: AppTheme.Colors.success, known: true)
                selfRatingButton(title: "Kann ich nicht", color: AppTheme.Colors.error, known: false)
            }
        } else {
            Text("Tippe die Karte zum Aufdecken")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: actionButtonHeight)
        }
    }

    /// Einzelner Bewertungs-Button — Token-basiert (success/error), weiße
    /// Schrift (lesbar auf beiden Farben; `AppPrimaryButtonStyle` erzwingt
    /// schwarze Schrift und wäre auf Rot schlecht lesbar).
    private func selfRatingButton(title: String, color: Color, known: Bool) -> some View {
        Button {
            rateViewModeCard(known: known)
        } label: {
            Text(title)
                .font(AppTheme.Typography.button)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: actionButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(color)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isSessionReady)
        .opacity(isSessionReady ? 1 : 0.5)
    }

    /// Speech-Mode-Action-Stack — historisches Layout (Mikro + Speaker
    /// nebeneinander, Tastatur-Toggle drunter). Wird verwendet, wenn
    /// `interaction.answerMode == .speech`.
    @ViewBuilder
    private var speechModeActionRows: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    toggleRecording()
                } label: {
                    Group {
                        if showsSuccessOnlyMessage {
                            Text("Richtig 🙂")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        } else if showsWrongOnlyMessage {
                            Text("Falsch 😕")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        } else if speechController.isRecording {
                            // **2026-06-09** — Ohr statt rotem Stop-
                            // Quadrat: benennt den Zustand („ich höre
                            // zu") statt der Bedienung. Gleich wie im
                            // Vokabel-/Nomen-/Verben-Training.
                            Image(systemName: "ear.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            // Idle: Cartoon-Mikrofon statt mic.fill. Kein
                            // foregroundStyle — das SVG bringt seine
                            // Farbigkeit selbst mit.
                            // Mikrofon-Icon vergrößert (32 → 48 pt) auf
                            // User-Wunsch — Card-Höhe bleibt 54 pt.
                            ElumiIconView(icon: .mikrofon, size: 48)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .background(flashcardRecordingButtonColor)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                }
                .buttonStyle(.plain)
                // **2026-06-09** — Gemeinsamer Zuhör-Puls (siehe
                // `appListeningPulse`); ersetzt den kaum sichtbaren
                // Rahmen-Puls.
                .appListeningPulse(isActive: speechController.isRecording)
                .disabled(!isSessionReady || !isAudioModeEnabled || !canUseSpeechRecognition)
                .opacity(!isSessionReady || !isAudioModeEnabled || !canUseSpeechRecognition ? 0.45 : 1)

                Button {
                    // **Sweep C** — manueller Speaker-Tap; `force: true`
                    // umgeht den Tap-Mode-Auto-Suppress-Guard.
                    speakCurrentPrompt(force: true)
                } label: {
                    // Lautsprecher-Card färbt sich orange, solange TTS spricht
                    // — direktes visuelles Feedback fürs aktuell laufende
                    // Vorlesen. Im Idle-Zustand bleibt die ruhige Card-Optik.
                    let isPlayingTTS = speaker.isSpeaking
                    Group {
                        if isPlayingTTS {
                            // Lautsprecher-Icon auf 48 pt vergrößert —
                            // Card-Höhe unverändert bei 54 pt, Icon füllt
                            // die Card jetzt deutlich präsenter.
                            ElumiIconView(icon: .lautsprecher, size: 48)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: actionButtonHeight)
                                .background(AppTheme.Colors.warning)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                        } else {
                            // Lautsprecher-Icon auf 48 pt vergrößert —
                            // Card-Höhe unverändert bei 54 pt, Icon füllt
                            // die Card jetzt deutlich präsenter.
                            ElumiIconView(icon: .lautsprecher, size: 48)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: actionButtonHeight)
                                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isSessionReady || !isAudioModeEnabled)
                .opacity(isSessionReady && isAudioModeEnabled ? 1 : 0.45)
                .animation(.easeInOut(duration: 0.18), value: speaker.isSpeaking)
            }

            Button {
                showFlashcardTypedAnswerField()
            } label: {
                // Cartoon-Tastatur statt SF `keyboard`. Der Active-State
                // wird weiterhin über den Background signalisiert
                // (sectionStyle.accent statt secondarySurface), der Icon-
                // Look bleibt konstant — das SVG bringt eigene Farbigkeit
                // mit und reagiert nicht auf foregroundStyle.
                // Tastatur-Icon auf 48 pt — parallel zu Mikrofon und
                // Lautsprecher. Card-Höhe bleibt bei 54 pt unverändert.
                ElumiIconView(icon: .tastatur, size: 48)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .background(interaction.showingTypedAnswerInput ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isSessionReady)
            .opacity(isSessionReady ? 1 : 0.45)
        }
    }

    /// **2026-05-08** — `tapModeActionRows` komplett entfernt. Im
    /// Tap-Mode wird der gesamte Primary-Actions-Block am Call-Site
    /// übersprungen (siehe `flashcardSessionScreen` in
    /// `FlashcardsView+Layout.swift`); die Typed-Answer-Card im
    /// Overlay ist die einzige Eingabe.

    /// Sekundäre Aktionen (Zurück + Weiter) — werden im Layout abgesetzt vom
    /// primären Action-Block und nahe am Footer platziert, zusammen mit der
    /// Antwort-Card.
    var flashcardSecondaryActions: some View {
        HStack(spacing: 10) {
            Button {
                restorePreviousFlashcard()
            } label: {
                Label("Zurück", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            // 1pt kleiner als andere Action-Labels — Zurück/Weiter sind
            // sekundäre Aktionen und sollen optisch ein bisschen leiser sein.
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: flashcardSecondaryActionHeight)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium)
            .disabled(!canRestorePreviousFlashcard)
            .opacity(canRestorePreviousFlashcard ? 1 : 0.5)

            Button {
                skipCard()
            } label: {
                // „Weiter" mit Pfeil rechts vom Wort — symmetrisch zum
                // „Zurück"-Button links (arrow.left), aber Icon auf der
                // anderen Seite, damit die Richtung visuell klar ist.
                HStack(spacing: 6) {
                    Text("Weiter")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: flashcardSecondaryActionHeight)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium)
            .disabled(!isSessionReady)
            .opacity(isSessionReady ? 1 : 0.5)
        }
    }
}
