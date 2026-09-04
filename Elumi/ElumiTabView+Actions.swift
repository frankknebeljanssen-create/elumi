import SwiftUI

// **Codeaudit 2026-09-03, Stufe 4 (Punkt 24)** — `ElumiTabView` war eine
// Datei mit 2198 Zeilen. Sie ist entlang der bereits vorhandenen
// `MARK:`-Abschnitte aufgeteilt; verschoben wurde nur, nichts
// umgeschrieben. Hier: Ergebnis-Card, Aktionen, Ticket-Vergabe und die Jackpot-Feier.
//
// Damit die Abschnitte in eigenen Dateien liegen koennen, sind die
// Mitglieder, die sie benutzen, nicht mehr `private` — dieselbe
// Entscheidung, die `TrainingView` und `FlashcardSessionStore` fuer ihre
// Extension-Dateien schon getroffen haben.

extension ElumiTabView {
    // MARK: - „Dein Ergebnis"-Card — IMMER sichtbar

    /// Flache Card unter der Slot Machine. Zeigt vor dem Spin einen
    /// ruhigen Placeholder (drei Geist-Slots + Hinweis), nach dem Spin
    /// die drei tatsächlich gezogenen Symbole.
    /// Per User-Spec 2026-04-24: kompakt, weniger vertikales Padding,
    /// damit die Card nicht wie ein großer Content-Block wirkt.
    var trainingResultCard: some View {
        // **2026-04-25 Dauerhaft-Pulse-Fix** (User-Spec „muss dauerhaft
        // blinken, nicht stoppen, bis Nochmal oder Training starten
        // gedrückt wird").
        //
        // Vorher: `.repeatForever(autoreverses: true)` auf @State-
        // basierten Glow/Scale — SwiftUI konnte die Animation unter
        // bestimmten Re-Render-Pfaden abbrechen.
        // Jetzt: `TimelineView(.animation)` treibt Glow + Scale direkt
        // aus einer Sinuswelle basierend auf der System-Uhr. Diese
        // Schleife läuft GARANTIERT so lange die View sichtbar ist —
        // kein SwiftUI-Animation-State kann sie abbrechen.
        //
        // Gated by `slotPhase == .revealed`: nur während der Reveal-
        // Phase sind Glow und Scale aktiv. In allen anderen Phasen
        // (`.spinning`, `.stopping`, `.idle`, `.landed`) wird der
        // Multiplikator 0 → kein Glow, Scale 1.0.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let isRevealed = slotPhase == .revealed
            let t = context.date.timeIntervalSinceReferenceDate
            // **2026-04-25 V3 (User „stärker + schneller blinken")**:
            // Cycle 1.4s → 0.75s (fast 2× schneller). Glow-Amplitude
            // 0.55…1.0 → 0.2…1.0 (deutlich breiterer Swing). Scale
            // 0.018 → 0.025 (intensiver Pop). Shadow-Radius 16 → 22
            // (mehr sichtbare „Strahlung"). Fühlt sich klar als
            // Blinken/Pulsieren an, nicht mehr wie ruhiges Atmen.
            let cycle: Double = 0.75
            let phase = t.truncatingRemainder(dividingBy: cycle) / cycle
            let wave = (sin(phase * 2 * .pi) + 1) / 2  // 0…1
            let pulseGlow: Double = isRevealed ? (0.2 + 0.8 * wave) : 0.0
            let pulseScale: CGFloat = isRevealed
                ? CGFloat(1.0 + 0.025 * wave)
                : 1.0

            return trainingResultCardContent
                .scaleEffect(pulseScale * resultHighlightScale)
                .shadow(
                    color: resultGlowColor.opacity(pulseGlow),
                    radius: 22,
                    x: 0,
                    y: 0
                )
        }
    }

    /// Reiner Card-Inhalt ohne Pulse-Effekte. Wird von der TimelineView
    /// in `trainingResultCard` umschlossen; so bleibt der Content stabil
    /// und nur die Pulse-Werte re-rendern pro Frame.
    private var trainingResultCardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dein Ergebnis")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            if let result = lastSpinResult, slotPhase == .revealed {
                filledModulesRow(for: result)
            } else {
                placeholderModulesRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .appSetupCardBackground()
    }

    private func filledModulesRow(for result: SlotSpinResult) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(result.centerSymbols.enumerated()), id: \.offset) { _, symbol in
                moduleResultCard(for: symbol)
            }
        }
    }

    private var placeholderModulesRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                placeholderModuleSlot
            }
        }
    }

    private var placeholderModuleSlot: some View {
        // **Setup-Tweaks v2 — C5 (User-Spec 2026-04-30)**: kleine
        // Circle-Sparkle + „—"-Label ersetzt durch **großes zentriertes
        // Fragezeichen** in der Card-Akzent-Farbe. Card-Dimensions
        // unverändert — das Q wirkt dominant „hier kommt was rein".
        //
        // Vorgeschichte (2026-04-25 Visibility-Pass): die kleinen
        // Sparkle-Circles hatten den Slot zu zaghaft markiert. Das
        // dominante Q ist die nächste Iteration und kommuniziert
        // klarer „Slot ist noch leer, Spin füllt ihn".
        //
        // **UX-Polish 2026-05-02 (Stufe 7)** — Layout-Shift-Fix.
        // Vorher: Placeholder ~44 pt vs Filled (`moduleResultCard`)
        // ~92 pt → Card wechselt Höhe beim Spin-Reveal, CTA-Position
        // wandert vertikal. Jetzt: fixe `frame(height: Self.resultSlotHeight)`
        // an beiden Pfaden — CTA-Position konstant über alle Slot-
        // Phasen.
        VStack(spacing: 0) {
            Image(systemName: "questionmark")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(sectionStyle.accent.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.resultSlotHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    AppTheme.Colors.border.opacity(0.75),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                )
        )
    }

    /// **UX-Polish 2026-05-02** — fixe Höhe für Result-Slots
    /// (Placeholder + Filled). Wert ist gewählt nach gemessener
    /// Filled-Card-Höhe: 52 pt Icon + 5 pt Spacing + 12 pt Label +
    /// 12 pt Vertical-Padding (6 pt × 2) = ~92 pt. Etwas Reserve
    /// für Font-Metrics auf großen Dynamic-Type-Settings.
    private static let resultSlotHeight: CGFloat = 92

    /// Result-Modul-Card — zeigt das gezogene Modul mit demselben
    /// Home-Icon wie im Home-Screen.
    ///
    /// **V4.8 Icon-Migration (2026-04-25)**: direkt `HomeModuleIconView`
    /// für Trainingsmodule, `ElumiWasserfloh`-Asset für Elumi. Kein
    /// SF-Symbol-Pfad mehr — identische Icon-Quelle wie in der
    /// Slot-Machine + Home-Cards.
    private func moduleResultCard(for symbol: ReelSymbol) -> some View {
        // **2026-04-25 (User „keine Pills, Icons größer")**: Der
        // Circle-Pill um das Icon ist entfernt. Das Icon steht jetzt
        // direkt im Card-Rahmen — klarer Fokus, weniger Layer-Rauschen.
        //
        // **Setup-Tweaks v2 — C6 (User-Spec 2026-04-30)**: Icon-Größen
        // nochmal hoch — Card-Dimensions sind unverändert geblieben,
        // Platz war da. Iteration:
        //   • HomeModuleIconView 32 → 40 (+25%, 2026-04-25)
        //   • HomeModuleIconView 40 → 52 (+30%, 2026-04-30)
        //   • Elumi-Asset 30 → 38 (+27%, 2026-04-25)
        //   • Elumi-Asset 38 → 50 (+32%, 2026-04-30)
        VStack(spacing: 5) {
            if let module = symbol.homeModule {
                HomeModuleIconView(icon: module.icon, size: 52)
            } else if let assetName = symbol.assetImage {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
            }
            Text(symbol.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        // **UX-Polish 2026-05-02** — fixe Höhe wie placeholder, damit
        // `trainingResultCard` zwischen Pre-Spin/Post-Spin nicht
        // mehr wächst. Siehe Doc bei `resultSlotHeight`.
        .frame(height: Self.resultSlotHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
    }

    // **2026-04-24 Versuchslogik**: Der separate `startTrainingCTA`
    // ist entfallen. Die Training-Starten-Funktion wohnt jetzt im
    // `trainingModeButton` (Teil von `spinCTA`), der nach dem 3. Spin
    // automatisch erscheint.

    // MARK: - Aktionen

    /// Wird vom Spin-CTA aufgerufen — startet einen frischen Spin
    /// und versteckt das alte Ergebnis (Reset-Verhalten per Spec).
    /// **2026-04-24 Gate**: läuft nur wenn die Phase es erlaubt und
    /// noch Versuche übrig sind (siehe `canTriggerSpin`).
    func triggerSpin() {
        guard canTriggerSpin else { return }
        // **Sache B Stufe 2 Future-Insurance** (2026-04-29): zusätzlicher
        // Guard gegen den Fall, dass ein zukünftiger Auto-Spin / Push-
        // Trigger / Background-Notification den Spin programmatisch
        // anstoßen will, während das Setup-Modal offen ist. Aktuell
        // unmöglich, weil der Modal-Backdrop alle UI-Tap-Pfade blockiert
        // und es keinen externen Trigger-Pfad gibt — billige Versicherung
        // gegen Race-Conditions in V2/V3, falls jemand einen
        // programmatischen Spin-Pfad einführt.
        guard !showSetupModal else { return }
        feedbackPlayer.playTabSwitch()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Altes Ergebnis verwerfen, damit der Bereich beim erneuten
        // Drehen sauber verschwindet (User-Spec: „Reset-Verhalten").
        lastSpinResult = null_lastSpin()
        // Pre-computed Targets via DropRate-Pipeline (gewichtete
        // Elumi-Wahrscheinlichkeit pro Reel).
        spinTargets = computeSpinTargets()
        // Trigger an die SlotMachineView. Sie setzt das Token nach
        // dem vollständigen Spin-Sequenz-Durchlauf selbst auf false.
        slotStartToken = true
    }

    /// Helfer, der `lastSpinResult` defensiv auf nil setzt — als
    /// Funktion ausgelagert, damit Type-Checker happy bleibt mit dem
    /// `Optional<SlotSpinResult>` literal.
    private func null_lastSpin() -> SlotSpinResult? { nil }

    /// Pro-Reel Ziel-Symbol berechnen mit aktueller Elumi-Chance.
    ///
    /// **Regel (2026-04-25 User-Spec)**: Es dürfen NIE zweimal
    /// dasselbe Trainingsmodul im selben Spin vorkommen. Elumi
    /// (Bonus-Symbol) darf mehrfach erscheinen (2× oder 3× Elumi
    /// sind ausdrücklich erlaubt — das ist der „Jackpot"-Effekt).
    ///
    /// Algorithmus:
    ///   1. Pro Reel Elumi-Roll (unabhängig wie vorher).
    ///   2. Der Daily-Drop-Pool hat nur zwei eindeutige Module, aber es
    ///      gibt drei Walzen — mindestens eine Walze muss also immer
    ///      Elumi zeigen. **Welche** das ist, wird ausgewürfelt.
    ///   3. Die verbleibenden Modul-Walzen bekommen je ein noch nicht
    ///      belegtes Modul aus ihrem Pool.
    ///
    /// **Positions-Fix (2026-09-03)** — User-Report: „das Elumi kommt
    /// immer im rechten Slot". Ursache war die alte Links-nach-rechts-
    /// Schleife: Reel 0 und 1 griffen die beiden verfügbaren Module ab,
    /// für Reel 2 blieb dann zwangsläufig nichts mehr übrig und es wurde
    /// auf Elumi gesetzt. Damit landete Elumi in rund 70 % aller Spins
    /// rechts, links und in der Mitte dagegen nur mit der reinen
    /// Basis-Chance. Jetzt wird zuerst die Elumi-Maske gebildet und die
    /// überzählige Modul-Walze **zufällig** gezogen — die Position ist
    /// über alle drei Walzen gleichverteilt. Die Häufigkeit von Doppel-
    /// und Dreifach-Elumi bleibt unverändert (sie hängt allein an den
    /// Rolls aus `ElumiDropRateControllerStore`).
    private func computeSpinTargets() -> [ReelSymbol?] {
        let chance = dropRate.currentElumiChance()
        let pools = ReelSymbol.standardReelPools

        // **Daily Drop Modul 2 (2026-05-23)** — MVP-Pool: nur Quiz +
        // Vokabeln. Rotation-ready: der `usedModules`-Filter +
        // `randomElement` unten bleiben unverändert (spätere Gewichtung/
        // Memory dockt genau dort an). Beim 5-Typen-Ausbau wird dieses
        // Set erweitert.
        let dailyDropModules: Set<HomeHeroModule> = [.quiz, .vokabeln]

        // 1) Unabhängiger Elumi-Roll pro Walze — Verteilung wie bisher.
        var isElumi: [Bool] = (0..<3).map { _ in dropRate.drawIsElumi(chance: chance) }

        // 2) Mehr Modul-Walzen als eindeutige Module → überzählige
        //    Walzen werden zu Elumi. Zufällig gezogen, damit der Bonus
        //    nicht systematisch an derselben Position klebt.
        var moduleReels = (0..<3).filter { !isElumi[$0] }
        if moduleReels.count > dailyDropModules.count {
            let surplus = moduleReels.count - dailyDropModules.count
            for reelIndex in moduleReels.shuffled().prefix(surplus) {
                isElumi[reelIndex] = true
            }
            moduleReels = (0..<3).filter { !isElumi[$0] }
        }

        // 3) Modul-Walzen befüllen — nie zweimal dasselbe Modul im Spin.
        var targets: [ReelSymbol?] = [nil, nil, nil]
        var usedModules: Set<HomeHeroModule> = []
        for reelIndex in moduleReels {
            let candidates = pools[reelIndex].filter { symbol in
                guard let module = symbol.homeModule else { return false }
                return dailyDropModules.contains(module) && !usedModules.contains(module)
            }
            guard let chosen = candidates.randomElement() else { continue }
            if let module = chosen.homeModule {
                usedModules.insert(module)
            }
            targets[reelIndex] = chosen
        }

        // 4) Alles, was keine Modul-Walze ist (inkl. Edge-Case „Pool
        //    liefert nichts"), zeigt den Game-Bonus.
        for reelIndex in 0..<3 where targets[reelIndex] == nil {
            targets[reelIndex] = ReelSymbol.elumi
        }
        return targets
    }

    /// Wird von `SlotMachineView` aufgerufen, sobald die komplette
    /// Spin-Sequenz (inkl. Reveal) durch ist.
    ///
    /// **2026-04-30 Credit-Grant-Verlagerung (Stufe 1b, Patch)**: die
    /// Credit-Vergabe wandert vom Slot-Stop **zum „Jetzt üben"-Tap** —
    /// siehe `startTraining()`. Begründung: bisher gutgeschriebene
    /// Tickets pro Drehung erlaubten Re-Roll-Farming (User dreht 3×,
    /// kassiert Tickets aus allen drei Drehungen, drückt nicht „Jetzt
    /// üben"). Neue Regel: nur die EINE Drehung, mit der der User in
    /// die Übung geht, zählt. Dieser Callback inkrementiert daher nur
    /// noch Spin-Budget-Bonus (intern für mehr Spins) und Drop-Rate-
    /// Statistik — keine `arcadeCredits`-Änderung.
    ///
    /// **Versuchslogik**: Hier — und NUR hier — wird
    /// `currentSpinNumber` inkrementiert. Bei bloßem Button-Tap oder
    /// während einer abgebrochenen Animation wird dieser Pfad NICHT
    /// erreicht, Versuche gehen nicht verloren.
    func handleSlotLanded(_ result: SlotSpinResult) {
        lastSpinResult = result
        // **Stufe 2 (2026-04-30)** — neuer Spin = neuer Grant erlaubt.
        // Erst beim „Jetzt üben"-Tap wird der Flag auf `true` gesetzt.
        // Solange der User dreht (Re-Roll), bleibt der nächste Grant
        // wieder offen.
        creditGrantConsumed = false
        currentSpinNumber = min(currentSpinNumber + 1, maxSpins)
        dropRate.registerSpinResult(elumiCount: result.elumiCount)
        budget.awardBonusCredits(for: result.elumiCount)
        #if DEBUG
        appDebugLog("🎰 [ElumiTab] Spin abgeschlossen — currentSpinNumber=\(currentSpinNumber)/\(maxSpins), Elumis=\(result.elumiCount) (Credit-Grant erfolgt erst beim 'Jetzt üben'-Tap)")
        #endif
        // **V4.4 Final-Result-Sound**:
        //   • Elumi-Treffer (1+) → Achievement-Sound (bonusbubble)
        //     + heavy Haptic → spürbarer Gewinn-Moment.
        //   • Kein Treffer → neutrales Round-Clear (leichter Abschluss-
        //     Ton) + success-Notification-Haptik. Vorher lief hier
        //     nur eine Haptik ohne Sound — der User erlebte das als
        //     „Stille nach dem Spin".
        if result.elumiCount > 0 {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            feedbackPlayer.playAchievement()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            feedbackPlayer.playRoundClear()
        }
    }

    // **2026-04-24 User-Spec + Pool-Vereinheitlichung 2026-04-30**: Der
    // separate `playCreditsChip` ist entfallen — Credits werden im
    // Arcade-Spiel-HUD und im Footer-Badge angezeigt. Mit dem Pool-
    // Merge in Stufe 1b sind Footer-Badge und In-Game-Anzeige derselbe
    // `arcadeCredits`-Wert.

    /// Baut aus dem Slot-Ergebnis eine `TrainingChainContext` und
    /// navigiert zum ersten Modul-Step.
    ///
    /// **Stufe 1 (2026-04-30, Branch `feature/training-session-flow`)**:
    /// Der frühere Pfad über `TrainingGenerator.generate(...)` ist
    /// abgelöst — der Slot-Spin selbst diktiert jetzt die Modul-
    /// Reihenfolge. Game-Slots sind in `TrainingChainContext.make(...)`
    /// bereits gefiltert; bei reinem Game-Jackpot (3× Game) ist das
    /// Builder-Result `nil`, und wir fallen still zurück (Stufe 5
    /// führt das Jackpot-UI ein).
    ///
    /// **Versuchslogik-Reset**: Vor der Navigation setzen wir
    /// `currentSpinNumber` auf 0 + räumen das lastSpinResult auf.
    /// Damit hat der Nutzer bei Rückkehr zum Tab frische 3 Versuche.
    ///
    /// **Stufe 2 (2026-04-30)** — Pre-Screen-Verkettung. Statt direkt
    /// aufs erste Modul zu pushen, navigieren wir auf
    /// `.trainingChainOverview(chain)`. Der Pre-Screen rendert den Plan
    /// und pusht beim CTA-Tap selbst auf das erste Modul (über
    /// `HomeHeroModule.chainScreen(...)` im `AppDestinationHost`).
    ///
    /// **Slot-State bleibt sichtbar (R12)**: die früheren Resets
    /// (`currentSpinNumber = 0`, `lastSpinResult = nil`,
    /// `slotPhase = .idle`, `resultHighlight*`) sind entfernt. Wenn der
    /// User auf dem Pre-Screen den Back-Chevron tappt, soll er sein
    /// Spin-Ergebnis im Tab unverändert wiedersehen — sonst wirkt der
    /// Chevron wie ein Hard-Reset. Der Chain-Reset selbst läuft via
    /// `TrainingChainStore.shared.clear()` aus dem Pre-Screen.
    ///
    /// **Idempotenz (creditGrantConsumed)**: verhindert die
    /// Re-Roll-Cheat-Variante 2, in der der User „Jetzt üben → Back →
    /// Jetzt üben" mit demselben `lastSpinResult` mehrfach durchläuft.
    /// Tickets gibt's nur beim ersten Tap; jeder weitere Tap mit
    /// demselben Ergebnis baut zwar die Chain neu (Pre-Screen erscheint
    /// erneut), gibt aber keine Tickets mehr. Spin/Re-Roll setzt das
    /// Flag in `handleSlotLanded` zurück.
    ///
    /// **Jackpot-Pfad (3× Game)**: `TrainingChainContext.make(...)`
    /// liefert seit Stufe 2 auch hier einen gültigen Context (mit
    /// leerem `plannedSteps`). Pre-Screen rendert nur Game-Cards und
    /// ein disabled-CTA. Credits werden trotzdem gutgeschrieben (+6).
    func startTraining() {
        feedbackPlayer.playTabSwitch()

        guard let pendingResult = lastSpinResult else { return }

        // **Credit-Grant beim 'Jetzt üben'-Tap** (Stufe 1b Patch,
        // 2026-04-30): nur die Drehung, mit der der User tatsächlich
        // ins Training geht, gibt Tickets — verhindert Re-Roll-Farming.
        // Mapping aus `slotCreditGrantTable` (1×→+1, 2×→+3, 3×→+6).
        //
        // **Block 5 (2026-05-03)**: Grant-Logik extrahiert nach
        // `grantSpinTicketsIfNeeded(_:)` — wird auch vom Jackpot-Pfad
        // (`triggerJackpotIfApplicable`) genutzt. Idempotenz via
        // `creditGrantConsumed` bleibt unverändert.
        _ = grantSpinTicketsIfNeeded(for: pendingResult)

        // Chain-Build aus Slot-Result. Game-Slots sind in `make(...)`
        // bereits aus `plannedSteps` gefiltert (sourceCenterSymbolKinds
        // bewahrt sie für End-Summary in Stufe 4). Bei Jackpot (3× Game)
        // ist `plannedSteps` leer — Pre-Screen rendert dann nur die
        // Game-Cards und disabled-CTA mit Hint „Drehe noch mal für
        // Übungen" (siehe `TrainingChainContext.isJackpot`).
        // **Daily Drop Modul 6 (2026-05-23)** — Zweimodiger Step-Bau:
        //   • N=10 (Ausnahme): wie bisher (Modul 3) — Even-split über die
        //     tatsächlichen Modul-Steps (1–2) → gemischt, KEIN Break.
        //   • N≥20 (Variante C): feste Block-Größe 10, `stepCount = N/10`,
        //     Round-Robin der Slot-Typen → Break an jeder Zwischen-Grenze.
        // Der `blockBreaks`-Flag der erzeugten Chain steuert das Routing in
        // `advanceChain`. Bei Jackpot (0 Module) bauen beide Pfade eine
        // leere Chain (Pre-Screen-Hint).
        let n = modalExerciseSelection ?? Self.exerciseCountDefault
        let chain: TrainingChainContext
        if n <= 10 {
            let moduleSteps = pendingResult.centerSymbols.filter { symbol in
                !symbol.isElumi && symbol.homeModule != nil
            }.count
            let perStep = moduleSteps > 0 ? n / moduleSteps : 0
            chain = TrainingChainContext.make(
                from: pendingResult,
                perStepCount: perStep
            )
        } else {
            chain = TrainingChainContext.makeBlocks(
                from: pendingResult,
                blockSize: 10,
                stepCount: n / 10
            )
        }

        // Chain-Start: Resume-Stores werden im Store geleert (R5).
        // **Performance-Fix 2026-05-01**: direkter Singleton-Call
        // statt observed-store, siehe Doc beim `@StateObject dropRate`-
        // Block oben. Verhalten unverändert — nur die Re-Render-
        // Cascade ist weg.
        TrainingChainStore.shared.start(chain)

        // **Stufe 2 Navigation**: Pre-Screen statt direktes Modul-Push.
        // Der Pre-Screen pusht beim „Übung starten"-CTA selbst auf den
        // ersten Chain-Step (Logik im `AppDestinationHost`-Wiring).
        navigate(.trainingChainOverview(chain))
    }

    // MARK: - Tickets-Grant (extrahiert für Block 5, 2026-05-03)

    /// Schreibt die Tickets-Belohnung für ein abgeschlossenes Spin-
    /// Ergebnis ins `ProgressStore`. Idempotent über
    /// `creditGrantConsumed` — ein und dieselbe Drehung kann nicht
    /// doppelt gegrantet werden (Re-Roll-Cheat-Variante 2 wird hier
    /// abgewehrt).
    ///
    /// Returns: Anzahl tatsächlich vergebener Tickets (`0` wenn schon
    /// gegrantet oder kein Mapping-Eintrag).
    ///
    /// **Block 5**: aus `startTraining()` herausgezogen. Wird vom
    /// Jackpot-Pfad (`triggerJackpotIfApplicable`) zur Reveal-Zeit
    /// gerufen, damit der Counter im Overlay sofort den neuen Wert
    /// im Footer-Badge widerspiegelt — und vom regulären
    /// „Jetzt üben"-Pfad in `startTraining()` zur Tap-Zeit, wie bisher.
    @discardableResult
    private func grantSpinTicketsIfNeeded(for result: SlotSpinResult) -> Int {
        guard !creditGrantConsumed else { return 0 }
        let granted = Self.slotCreditGrantTable[result.elumiCount] ?? 0
        if granted > 0 {
            ProgressStore.shared.mutate { progress in
                progress.arcadeCredits += granted
            }
            // Mirror auf bare `@AppStorage`-Key — siehe Pattern aus
            // FlashcardsView+SessionComponents:42, damit Footer-Badge
            // den neuen Wert sofort sieht.
            arcadeCredits = ProgressStore.shared.progress.arcadeCredits
        }
        creditGrantConsumed = true
        return granted
    }

    // MARK: - Jackpot-Feier-Trigger (Block 5, 2026-05-03)

    /// Prüft das aktuelle `lastSpinResult` auf Jackpot-Konfiguration
    /// (alle drei Reels = Game-Symbol) und löst gegebenenfalls die
    /// In-Place-Feier aus.
    ///
    /// Wird aus `.onChange(of: slotPhase) → .revealed` gerufen, also
    /// genau in dem Moment, in dem die Reels stillstehen. Tickets
    /// werden hier — nicht erst beim Tap auf einen Folge-CTA —
    /// gutgeschrieben, damit der Footer-Badge synchron mit dem
    /// Counter-Animation im Overlay hochzählt.
    ///
    /// Bei Nicht-Jackpot-Spins ist diese Funktion ein No-Op.
    func triggerJackpotIfApplicable() {
        guard let result = lastSpinResult else { return }
        guard result.elumiCount == 3 else { return }
        // Tickets-Counter-Werte VOR dem Grant einfangen, damit der
        // Counter im Overlay sauber von alt → neu animiert.
        let beforeBalance = ProgressStore.shared.progress.arcadeCredits
        let granted = grantSpinTicketsIfNeeded(for: result)
        // Falls schon gegrantet (defensiv — würde theoretisch nur bei
        // Re-Render-Race auftreten): Counter trotzdem zeigen, aber mit
        // Granted = 0. Praktisch: erste Reveal triggert hier, Folge-
        // Renders sehen `creditGrantConsumed == true`.
        jackpotTicketsBefore = beforeBalance
        jackpotTicketsGranted = granted
        jackpotConfettiStartDate = Date()

        // Erfolgs-Haptik — additive Wuchtigkeit zum bestehenden
        // `playJackpot()`-Sound aus `SlotMachineView.runSpinSequence`.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // Layered Sound: zusätzlich Level-Up-Sound für tiefe Pointe
        // (Jackpot-System-Sound 1306 läuft schon parallel aus dem
        // Reel-Settle-Pfad; das Level-Up bringt einen warmen Layer
        // dazu, der auch bei stummgeschalteten System-Sounds noch
        // Punch hat).
        feedbackPlayer.playLevelUp()

        showJackpotCelebration = true
    }

    /// CTA-Closure aus `JackpotCelebrationView` — Primary „Nochmal
    /// drehen!". Schließt das Overlay und triggert einen frischen Spin
    /// (gleicher Code-Pfad wie der reguläre `triggerSpin`-CTA).
    ///
    /// Wir respektieren `canTriggerSpin` — wenn der User schon alle
    /// drei Versuche durch hat (`!hasRemainingSpins`), darf hier
    /// trotzdem nichts passieren. In der Praxis aber: Jackpot kann nur
    /// nach einem Spin auftreten, also ist `currentSpinNumber >= 1`
    /// und höchstens `== maxSpins`. Bei `currentSpinNumber == maxSpins`
    /// hat der User keinen Re-Spin mehr — Button bleibt clickable, aber
    /// der `triggerSpin()`-Guard verhindert den Spin und das Overlay
    /// dismisst trotzdem (User-Feedback: Tap reagiert).
    func handleJackpotSpinAgain() {
        showJackpotCelebration = false
        triggerSpin()
    }

    /// CTA-Closure aus `JackpotCelebrationView` — Secondary „Zur
    /// Startseite". Schließt das Overlay und navigiert zum Home-Tab.
    /// Slot-State wird dabei *nicht* zurückgesetzt — der Slot-Tab
    /// bleibt mit dem Jackpot-Result sichtbar, falls der User später
    /// zurückkommt.
    func handleJackpotGoHome() {
        showJackpotCelebration = false
        goHome()
    }

    /// Mappt einen Chain-Step (HomeHeroModule) auf den passenden
    /// `AppScreen` mit injiziertem `chainContext` und
    /// `shouldAutoStart=true` (Setup-Screen überspringen).
    ///
    /// **R3 (Audit-Spec)**: Akzente nutzt `.uben` als Chain-Default —
    /// Speed-Round bleibt manueller Pfad und kommt nicht aus dem Slot.
    /// **R4**: Vokabeln/Nomen/Artikel/Verben/Verbformen laufen alle
    /// über `.train(TrainingLaunchContext)`, der `preferredMode` schaltet
    /// die TrainingView intern auf den richtigen Modus.
    ///
    /// **Stufe 2 (2026-04-30)**: Wrapper um `HomeHeroModule.chainScreen(...)`
    /// — die Logik ist nach `AppNavigationModels.swift` umgezogen, weil
    /// auch `AppDestinationHost` (Pre-Screen-CTA-Closure) den Mapping
    /// braucht. Hier bleibt nur der Wrapper damit existing Call-Sites
    /// unverändert bleiben.
    private func screenForChainStep(
        _ step: HomeHeroModule,
        chainContext: TrainingChainContext
    ) -> AppScreen {
        step.chainScreen(chainContext: chainContext)
    }

    // MARK: - Result-Highlight (2026-04-25 User-Spec)

    /// **V3 (2026-04-25)**: Nur noch Initial-Burst-Scale via @State.
    /// Der kontinuierliche Pulse läuft jetzt aus der `TimelineView`
    /// in `trainingResultCard` — robust gegen SwiftUI-Animation-Stops.
    /// Diese Methode ist daher schlanker: einmal kurz „Pop" auf 1.03,
    /// zurück auf 1.0. Das TimelineView-Pulse überlagert sich dann
    /// multiplikativ.
    func triggerResultHighlight() {
        withAnimation(.spring(response: 0.40, dampingFraction: 0.52)) {
            resultHighlightScale = 1.03
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            guard slotPhase == .revealed else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                resultHighlightScale = 1.0
            }
        }
    }

    // **Stufe 1 (2026-04-30)**: `routeForBlock(_:)` entfernt — der
    // `TrainingExerciseType`→`AppScreen`-Mapper war auf den alten
    // `TrainingGenerator`-Pfad gemünzt. Chain-Routing geht jetzt über
    // `screenForChainStep(_:chainContext:)` direkt aus
    // `HomeHeroModule`-Slots (siehe oben).

    // **2026-04-24 Vereinfachung**: statusCard + statusMetric +
    // statusDivider entfernt. Sie waren am Footer gepinnt und
    // verursachten den „halb sichtbar unter Footer"-Bug. Streak/Level
    // bleiben im Trophy-Tab sichtbar — der Elumi-Tab fokussiert sich
    // jetzt nur auf die Slot-Machine.
}
