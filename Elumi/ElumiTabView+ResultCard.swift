import SwiftUI

// **Codeaudit 2026-09-03, Stufe 4 (Punkt 24)** — `ElumiTabView` war eine
// Datei mit 2198 Zeilen. Sie ist entlang der bereits vorhandenen
// `MARK:`-Abschnitte aufgeteilt; verschoben wurde nur, nichts
// umgeschrieben. Hier: der Haupt-Knopf und die Ergebnis-Card.
//
// Damit die Abschnitte in eigenen Dateien liegen koennen, sind die
// Mitglieder, die sie benutzen, nicht mehr `private` — dieselbe
// Entscheidung, die `TrainingView` und `FlashcardSessionStore` fuer ihre
// Extension-Dateien schon getroffen haben.

extension ElumiTabView {
    // MARK: - Unified CTA „Los geht's" / „Nochmal drehen + Jetzt üben" / „Jetzt üben"

    /// **UX Stufe 3 (2026-04-29)** — drei States, klar getrennt:
    ///
    ///   1. `currentSpinNumber == 0` → ein Full-Width-Button „Los geht's!"
    ///      (erster Versuch, kein Versuchszähler).
    ///   2. `currentSpinNumber > 0 && hasRemainingSpins` → zwei
    ///      gleichwertige Buttons nebeneinander („Nochmal drehen" links,
    ///      „Jetzt üben" rechts), beide gelb gefüllt
    ///      (`AppPrimaryButtonStyle(color: ctaYellow)`). Versuchszähler
    ///      „Versuch X von 3" als separate Caption darüber — nicht im
    ///      Button-Sublabel, weil zwei Buttons mit unterschiedlichen
    ///      Sublabel-Strukturen das equal-weight-Prinzip optisch brechen
    ///      würden.
    ///   3. `!hasRemainingSpins` → ein Full-Width-Button „Jetzt üben"
    ///      (Single-CTA, ehrliche Kommunikation: Spin-Phase vorbei,
    ///      jetzt wird trainiert). Label bleibt „Jetzt üben" identisch
    ///      zum 2-Button-State — Konsistenz für den User.
    @ViewBuilder
    var spinCTA: some View {
        // **Setup-Tweaks v2 — C4 (2026-04-30)**: die separate
        // „Versuch X von 3"-Caption-Zeile oberhalb der Twin-CTAs ist
        // entfernt. Der Counter lebt jetzt als Sub-Label im
        // „Nochmal drehen"-Button (siehe `twinCTAs`). Damit verschwindet
        // der vertikale Layout-Sprung beim Phase-Übergang
        // (revealed → spinning) — der Button-Block hat jetzt eine
        // konstante Höhe über alle Slot-Phasen.
        if currentSpinNumber == 0 {
            singleSpinButton
        } else if hasRemainingSpins {
            twinCTAs
        } else {
            singleTrainingButton
        }
    }

    /// State 1: erster Versuch — ein Full-Width-Button „Maschine starten".
    private var singleSpinButton: some View {
        // **UX-Polish 2026-05-02 (Stufe 7)** — pulsiert wenn der
        // Slot ruht und noch nichts gedreht wurde (`slotPhase == .idle &&
        // currentSpinNumber == 0`). User-Spec: nur dieser CTA + die
        // Pre-Screen-„Bereit?"-Headline pulsieren auf dem Slot/Pre-
        // Screen-Pfad — der „Nochmal drehen"/„Jetzt üben"-Twin-State
        // bleibt ruhig.
        let shouldPulse = slotPhase == .idle && currentSpinNumber == 0 && canTriggerSpin
        // **Slot-CTA-Highlight 2026-05-06** — der pre-Spin-CTA „Drop
        // starten" bekommt dieselbe Border-Glow + Shimmer-Behandlung
        // wie die Daily-Drop-Card auf Home (visuelle Verkettung
        // Card → CTA). Auto-Pause während Reel-Drehung
        // (`slotPhase != .idle`) verhindert Frame-Drops und visuellen
        // Lärm während der Spin-Phase. Wenn der Slot wieder in
        // `.idle` zurückkehrt (z. B. nach Reveal + dismiss), läuft
        // der Glow wieder.
        let glowPaused = slotPhase != .idle
        return Button {
            triggerSpin()
        } label: {
            Text(spinPrimaryLabel)
                .font(.system(size: 19, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: ctaYellow))
        .disabled(!canTriggerSpin)
        .opacity(canTriggerSpin ? 1.0 : 0.45)
        // **Bug-Fix 2026-05-07** — `dailyDropGlow` MUSS vor
        // `pulsing` stehen, damit der Pulse-Scale (`peakScale 1.05`)
        // die Border-Glow-Overlay MIT-skaliert. Vorher saß die Border
        // außerhalb des Scale-Effekts → der gelbe Inhalt wuchs beim
        // Glow-Peak (1.05×), die Gradient-Border blieb auf 1.0× und
        // wirkte „kleiner als der Inhalt". Jetzt skalieren Border +
        // Inhalt synchron — Border umfasst den Inhalt durchgehend.
        .dailyDropGlow(cornerRadius: 16, paused: glowPaused)
        .pulsing(active: shouldPulse, glowColor: ctaYellow)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityLabel(Text("Los geht's"))
        .accessibilityHint(Text("Startet den ersten Slot-Spin"))
    }

    /// State 2: 2-Button-State nach erstem Spin, solange Versuche übrig.
    /// Beide Buttons gelb gefüllt, gleiche Höhe, gleiche Schriftgröße,
    /// `frame(maxWidth: .infinity)` → 50/50-Aufteilung.
    ///
    /// **Setup-Tweaks v2 — C4 (2026-04-30)**: Versuch-Counter
    /// (`currentAttemptDisplay`) ist jetzt **Sub-Label im Re-Spin-
    /// Button**, nicht mehr eine separate Caption-Zeile oberhalb. Der
    /// „Jetzt üben"-Button bekommt eine unsichtbare Reserve-Slot-Zeile
    /// (`Text(" ")` mit identischer Schrift), damit beide Buttons
    /// dieselbe Höhe halten und es keine vertikalen Layout-Sprünge
    /// beim Phase-Wechsel mehr gibt.
    private var twinCTAs: some View {
        HStack(spacing: 12) {
            Button {
                triggerSpin()
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.2.circlepath")
                            .font(.system(size: 14, weight: .bold))
                        Text(spinPrimaryLabel)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(currentAttemptDisplay)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
            }
            // **CTA-Differenzierung (2026-05-02)** — „Nochmal drehen"
            // wird optisch vom „Jetzt üben"-CTA abgesetzt: Warning-Amber
            // signalisiert „Retry-Aktion mit Verlust einer Spin-Chance",
            // im Gegensatz zum Success-Grün der Confirmation-CTA daneben.
            // Pre-Spin-CTA „Los geht's" (`singleSpinButton`) bleibt
            // bewusst auf `ctaYellow` — dort gibt es noch keinen
            // Differenzierungs-Bedarf.
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.warning))
            .disabled(!canTriggerSpin)
            .opacity(canTriggerSpin ? 1.0 : 0.45)
            .accessibilityLabel(Text(spinPrimaryLabel))
            .accessibilityHint(Text("\(currentAttemptDisplay). Erzeugt eine andere zufällige Trainings-Zusammenstellung."))

            Button {
                startTraining()
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Jetzt üben")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    // Sub-Label: gewählte Übungs-Anzahl in Klammern (Modul 3,
                    // ersetzt die Minuten). Identische Schrift wie der
                    // Versuch-Counter im Re-Spin-Button → beide Buttons
                    // symmetrisch zweizeilig, gleich hoch.
                    Text("(\(modalExerciseSelection ?? Self.exerciseCountDefault) Übungen)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
            }
            // **CTA-Differenzierung (2026-05-02)** — „Jetzt üben"
            // ist der Confirmation-CTA → Success-Grün, klar abgesetzt
            // vom Warning-Amber des „Nochmal drehen"-Retry-CTA daneben.
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.success))
            .accessibilityLabel(Text("Jetzt \u{00FC}ben \(modalExerciseSelection ?? Self.exerciseCountDefault) \u{00DC}bungen"))
            .accessibilityHint(Text("Startet die generierte Trainingseinheit sofort"))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    /// State 3: alle Versuche aufgebraucht — ein Full-Width-Button
    /// „Jetzt üben". Label-Konsistenz zur 2-Button-Phase.
    private var singleTrainingButton: some View {
        Button {
            startTraining()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Jetzt üben")
                    .font(.system(size: 19, weight: .black, design: .rounded))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
        }
        // **CTA-Differenzierung (2026-05-02)** — Single-CTA-Final-State
        // (3/3, keine Retries mehr) hält Label-Konsistenz zur 2-Button-
        // Phase und erbt deshalb auch die Success-Grün-Farbe vom
        // „Jetzt üben"-Twin.
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.success))
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .accessibilityLabel(Text("Jetzt üben"))
        .accessibilityHint(Text("Startet die generierte Trainingseinheit"))
    }

    /// **Spin-Gate** — Sache B Stufe 1 (2026-04-29): vereinfacht auf
    /// (a) Phase-Erlaubnis und (b) verbleibende Versuche. Die ehemalige
    /// `selectedDuration != nil`-Bedingung ist entfallen, weil
    /// `selectedDuration` jetzt non-optional persistiert ist und stets
    /// einen sinnvollen Default (`Self.durationDefault` = 10) hält.
    ///
    /// **2026-05-06 Refactor (Pop-up-Only)** — zusätzliche Bedingung
    /// `modalDurationSelection != nil`. Im neuen Flow ist die Zeit-Wahl
    /// pro Session ein bewusster Akt: der User muss im Pop-up eine
    /// Time-Card tappen, bevor der Slot-CTA aktiv wird. Vorher konnte
    /// der User dank `selectedDuration`-Default sofort spinnen, jetzt
    /// gate-t der Slot-CTA bis die Pop-up-Wahl getroffen wurde
    /// (User-Spec: „Falls keine Zeit gewählt: Slot-Screen-CTA bleibt
    /// gegraut/disabled bis Zeit gesetzt ist").
    var canTriggerSpin: Bool {
        // **Daily Drop Modul 3 (2026-05-23)** — Gate auf die Anzahl-Wahl
        // (`modalExerciseSelection`) statt der alten Zeitwahl.
        isSpinAllowed && hasRemainingSpins && modalExerciseSelection != nil
    }

    /// Spin ist nur in `.idle` und `.revealed` erlaubt — während
    /// `.spinning` / `.stopping` / `.landed` muss der Button deaktiviert
    /// sein, damit kein zweiter Spin in einen laufenden Spin reinhackt.
    var isSpinAllowed: Bool {
        slotPhase == .idle || slotPhase == .revealed
    }

}
