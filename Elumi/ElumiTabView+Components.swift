import SwiftUI

// **Codeaudit 2026-09-03, Stufe 4 (Punkt 24)** — `ElumiTabView` war eine
// Datei mit 2198 Zeilen. Sie ist entlang der bereits vorhandenen
// `MARK:`-Abschnitte aufgeteilt; verschoben wurde nur, nichts
// umgeschrieben. Hier: Kopfzeile, Slot-Machine, Trainingszeit und der Daily-Drop-Picker.
//
// Damit die Abschnitte in eigenen Dateien liegen koennen, sind die
// Mitglieder, die sie benutzen, nicht mehr `private` — dieselbe
// Entscheidung, die `TrainingView` und `FlashcardSessionStore` fuer ihre
// Extension-Dateien schon getroffen haben.

extension ElumiTabView {
    // MARK: - Header-Titel

    // **2026-05-22** — Header zeigt fest „Daily Drop" (Modus-Name,
    // konsistent mit den anderen Setup-Screens). Vorher rotierte hier
    // ein zufälliger Hint-Pool (`ElumiHints`) pro Tab-Visit; das wurde
    // auf User-Spec entfernt, weil der Header den Modus klar benennen
    // soll (vorheriger Stand: rotierende Hints; davor statisch „Salut
    // Frank!", was im Maschine-Tab keinen Sinn ergab).

    // MARK: - Slot-Machine-Bereich

    var slotMachineArea: some View {
        // **V4.4 Sound-Pass (2026-04-24)**: differenzierte SFX für
        // jeden Slot-Event-Typ — keine einheitlichen `playTabSwitch`
        // mehr für alle drei Callbacks.
        //   • onSpinStart → `playLaunch()` (kraftvoller Start-Sound).
        //   • onReelSettled → `playTabSwitch()` (klares Tick pro Reel).
        //   • onLanded → wird in `handleSlotLanded` separat behandelt
        //     (Achievement bei Elumi-Treffer, neutraler Success-Ton
        //     ohne Treffer).
        // Dazu unterschiedlich starke Haptik-Impulse, damit der
        // User auch mit Ton aus Feedback spürt.
        SlotMachineView(
            reelPools: ReelSymbol.standardReelPools,
            accent: sectionStyle.accent,
            spinTargets: $spinTargets,
            spinStartToken: $slotStartToken,
            phase: $slotPhase,
            onLanded: handleSlotLanded,
            onReelSettled: { reelIndex in
                // **2026-04-25 Sound-Pass V2** (User-Report „Klicks nicht
                // hörbar"): dedizierte `playSlotReelClick` / `playSlotFinalReelClick`
                // Methoden mit markanteren Assets (`toggle` + `listaction`)
                // statt der generischen `playTabSwitch`. Jeder Stop hat so
                // ein deutlich wahrnehmbares Klack.
                let isFinalReel = (reelIndex == 2)
                UIImpactFeedbackGenerator(
                    style: isFinalReel ? .heavy : .medium
                ).impactOccurred()
                if isFinalReel {
                    feedbackPlayer.playSlotFinalReelClick()
                } else {
                    feedbackPlayer.playSlotReelClick()
                }
                #if DEBUG
                appDebugLog("🔊 [Slot] Reel \(reelIndex) Click (final=\(isFinalReel))")
                #endif
            },
            onSpinStart: {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                // **Audio-Session-Priming** (2026-04-25): sorgt dafür,
                // dass die Click-Sounds nicht durch eine schlafende oder
                // konkurrierende Audio-Session gedämpft werden. Der
                // Session-Warm-Up bleibt für die ganze Spin-Sequenz
                // aktiv — nachfolgende Reel-Stops klingen dann sofort
                // ohne Anlauf-Delay.
                feedbackPlayer.sp.ensureAudioSession()
                // **Start-Sound entfernt** (Branch
                // `feature/slot-machine-sounds`, 2026-04-30) — der frühere
                // `playLaunch()` (kraftvoller Start-Sound) war ein
                // hörbarer Cue *vor* dem neuen Click-Stream und wirkte
                // gegenüber dem realistischen Reel-Click redundant /
                // konkurrierend. User-Spec: „start sound muss weg
                // (der vor dem neuen click sound kommt)". Haptik und
                // Session-Priming bleiben — beides ist nicht hörbar.
                #if DEBUG
                appDebugLog("🔊 [Slot] Spin gestartet (session primed, kein Launch-Sound mehr)")
                #endif
            }
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Trainingszeit-Anzeige (Sache B Stufe 3) — IMMER sichtbar

    /// XXL-Anzeige der gewählten Trainingsdauer + Pencil-Pill für
    /// Re-Edit. Ersetzt die ehemalige `durationCard` mit drei Chips
    /// (User-Spec Sache B 2026-04-29): nach dem Setup-Modal-Refactor
    /// (Stufe 2) ist die Chip-Wahl ins Modal gewandert; hier zeigt die
    /// Card jetzt nur noch die persistierte Wahl groß.
    ///
    /// Komponenten:
    ///   • Section-Label „TRAININGSZEIT" via `setupCardLabel(...)`-Helper
    ///   • XXL-Zahl in 56pt black rounded, accent-Color, mit
    ///     `.contentTransition(.numericText())` für smoothes Update
    ///     beim Re-Edit
    ///   • „min"-Suffix in 16pt semibold, dezent in `textSecondary`
    ///   • Pencil-Pill (40×40 Circle, accent.opacity(0.14)) rechts
    ///     bündig — Pattern analog zu `SessionContextCard`
    ///   • Pencil ist `disabled(!isSpinAllowed)` — kein Re-Edit
    ///     während die Slot-Machine rollt (Edge-Case E2)
    var timeDisplayCard: some View {
        // **Slot-Layout-Tighten 2026-05-07 Iteration 2** —
        // Wert-Block (Dauer + Zahl + min) **mittig** als
        // zusammenhängender String („Dauer 12 min"), Pencil rechts.
        // Reserve-Slot links spiegelt den Pencil-Width, damit der
        // Wert-Block ehrlich in der Card-Mitte sitzt (nicht durch
        // den Pencil-Asymmetrie-Effekt nach links versetzt).
        // Vertikales Padding 4 → 12 pt (User-Spec „padding über und
        // unter Dauer-Card erhöhen, ist zu eng, CTA hat noch Platz").
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            // Reserve-Slot links — gleich breit wie der Pencil
            // rechts, damit der Wert-Block exakt mittig sitzt.
            // **Iter 4 (2026-05-07)** — Reserve zurück auf 32×32,
            // synchron mit dem Pencil (User-Spec „Pencil wieder wie
            // vorher").
            Color.clear.frame(width: 32, height: 32)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Dauer-Label inline mit der Zahl — gleiche Font-
                // Klasse wie der Wert. Mixed-Case statt Caps, weil
                // als Wort + Zahl zusammen ruhiger wirkt.
                // **Daily Drop Modul 3 (2026-05-23)** — zeigt jetzt die
                // gewählte Übungs-Anzahl statt der (toten) Minuten.
                Text("Anzahl")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(modalExerciseSelection ?? Self.exerciseCountDefault)")
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(sectionStyle.accent)
                        // `.identity`: harter Crossfade ohne Glyph-Morphing
                        // beim Wechsel 10/20/30.
                        .contentTransition(.identity)

                    Text("Übungen")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                openSetupModalForReEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(sectionStyle.accent.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isSpinAllowed)
            .opacity(isSpinAllowed ? 1.0 : 0.45)
            .accessibilityLabel(Text("Trainingsdauer ändern"))
            .accessibilityHint(Text("Öffnet den Setup-Dialog mit der aktuellen Wahl preselected"))
        }
        .padding(.horizontal, 14)
        // **Iter 6 (2026-05-07)** — Iter-5-Änderungen reverted
        // (Font/Pencil zurück auf Iter-4-Werte). Der externe
        // Atemraum oben/unten zur Nachbarschaft kommt aus dem
        // `padding(.vertical, 10)`-Modifier am Call-Site (siehe
        // `mainContent` oben), nicht aus dem Card-internen Padding.
        // Internal-Vertical bleibt schmal (8 pt), damit die Card
        // selbst kompakt sitzt.
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
        .animation(.easeInOut(duration: 0.20), value: modalExerciseSelection)
        .animation(.easeInOut(duration: 0.20), value: isSpinAllowed)
    }

    /// Re-Edit-Pfad — Pencil-Tap im Setup-Screen öffnet das Setup-Modal
    /// mit der persistierten Wahl preselected. Animation-Strategie ist
    /// Single-Source: `withAnimation` um den State-Toggle gewrappt,
    /// die View-Transition läuft über `.animation(value: showSetupModal)`
    /// am ZStack-Wrapper + `.transition(...)` am Mount-Site (Stufe 2).
    /// Erstmaliges Modal-Erscheinen und Re-Edit nutzen denselben Pfad —
    /// keine duplizierte Animation, keine getrennten States.
    private func openSetupModalForReEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // **2026-05-06 Refactor (Pop-up-Only)** — Re-Edit zeigt die
        // aktuelle Wahl als preselected an. Vorher wurde
        // `modalDurationSelection` nilliert, um dem User eine bewusste
        // Re-Wahl abzunötigen — mit dem neuen `canTriggerSpin`-Gate
        // (`modalDurationSelection != nil`) würde das aber den Slot-CTA
        // disablen, sobald der User das Pop-up via Skip-X / Backdrop
        // schließt ohne neue Card zu tappen. Stattdessen: Re-Edit
        // preselected die persistierte `selectedDuration`. Dismiss
        // ohne Änderung → CTA bleibt aktiv (kein Regression). Tap auf
        // andere Card → Auto-Close mit neuem Wert.
        // **Daily Drop Modul 3 (2026-05-23)** — Re-Edit: Material neu zählen
        // (globale Auswahl kann sich geändert haben). `modalExerciseSelection`
        // bleibt als aktuelle Wahl erhalten → Chip preselected, Slot-CTA aktiv.
        recomputeDailyDropMaterial()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            showSetupModal = true
        }
    }

    // MARK: - Daily Drop Modul 3 — Anzahl-Picker + Material-Gating

    /// **Daily Drop Modul 3 (2026-05-23)** — Längen-Label für die
    /// Anzahl-Chips (Kurz/Mittel/Lang).
    func exerciseLengthLabel(_ count: Int) -> String {
        switch count {
        case 10: return "Kurz"
        case 20: return "Mittel"
        case 30: return "Lang"
        default: return "\(count)"
        }
    }

    /// **Daily Drop Modul 6 (2026-05-23)** — benötigtes Material pro Länge.
    /// N=10 (Ausnahme, gemischt, Even-split 5/Step) → ≥5. N≥20 (Variante C,
    /// fixe 10er-Blöcke mit erlaubter Wiederholung) → ≥10 (ein voller Block;
    /// Repeats füllen weitere Blöcke). Ersetzt die alte `count / 2`-Regel
    /// (die Lang fälschlich auf 15 setzte).
    func materialThreshold(for count: Int) -> Int {
        count <= 10 ? 5 : 10
    }

    /// **Daily Drop Modul 3 (2026-05-23)** — zählt das nutzbare Material der
    /// globalen Auswahl und cached `min(quizUsable, vokabelUsable)`. Quiz-
    /// nutzbar = richtungsgefilterte, deduplizierte Merged-Items
    /// (`makeMergedItems`); Vokabel-nutzbar = effectiveItems mit
    /// `cardType == .words`. Aufruf NUR bei Modal-Open + Selection-Change
    /// (teuer wegen `effectiveItems`-Slicing) — nie pro Render.
    func recomputeDailyDropMaterial() {
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        let direction = (Direction(rawValue: UserDefaults.standard.string(forKey: appDirectionKey) ?? "") ?? .frenchToGerman).sanitizedForFrenchOnly
        // **Daily Drop Modul 3 (2026-05-23)** — leere globale Auswahl → A1-
        // Grundwortschatz-Fallback, exakt wie `effectiveSelectedListIDs`
        // (`currentGlobalSelectedListIDs() ?? [defaultGlobalSelectionListID]`).
        // KRITISCH: ohne diesen Fallback würde ein frischer User (nie global
        // gewählt) Material 0 zählen → „zu wenig" → kein Einstieg, obwohl die
        // echte Session auf A1 zurückfällt und Material hätte.
        let resolvedIDs = globalSelectedListIDs.isEmpty
            ? [VocabularyListSelectionResolver.defaultGlobalSelectionListID]
            : globalSelectedListIDs
        let lists = listStore.allLists.filter { resolvedIDs.contains($0.id) }
        let quizUsable = QuizBuildService.makeMergedItems(
            from: lists,
            direction: direction,
            lernjahrMax: lernjahrMax
        ).count
        let vokabelUsable = lists
            .flatMap { VocabularyListSelectionResolver.effectiveItems(for: $0, lernjahrMax: lernjahrMax) }
            .filter { $0.sourceLanguage == direction.sourceLanguage }
            .filter { $0.cardType == .words }
            .count
        cachedDailyDropMaterial = min(quizUsable, vokabelUsable)
        #if DEBUG
        appDebugLog("📦 [DailyDrop] material recompute — quiz=\(quizUsable) vokabel=\(vokabelUsable) → min=\(cachedDailyDropMaterial)")
        #endif
    }

    /// **Daily Drop Modul 3 (2026-05-23)** — Anzahl-Chip (Kurz/Mittel/Lang).
    /// Ausgegraut + nicht tappbar, wenn zu wenig Material für diese Länge
    /// (`cachedDailyDropMaterial < count`). Tap setzt die Wahl + auto-close.
    func exerciseCountChip(count: Int) -> some View {
        let moduleColor = sectionStyle.accent
        let isSelected = modalExerciseSelection == count
        // **Daily Drop Modul 6 (2026-05-23)** — Schwelle pro Länge:
        // N=10 → ≥5, N≥20 → ≥10 (fixe 10er-Blöcke, Wiederholung erlaubt).
        let isAvailable = cachedDailyDropMaterial >= materialThreshold(for: count)
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? moduleColor.opacity(0.25) : AppTheme.Colors.secondarySurface)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? moduleColor : Color.clear, lineWidth: isSelected ? 2 : 0)
            VStack(alignment: .center, spacing: 2) {
                Text(exerciseLengthLabel(count))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("\(count) Übungen")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .opacity(isAvailable ? (isSelected ? 1.0 : 0.85) : 0.35)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .contentShape(Rectangle())
        .allowsHitTesting(isAvailable)
        .onTapGesture {
            guard isAvailable else { return }
            modalExerciseSelection = count
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismissSetupModal()
        }
        .animation(.easeInOut(duration: 0.20), value: modalExerciseSelection)
    }

    /// Pro-Chip-Renderer für das Setup-Modal (Sache B Stufe 2). Vor
    /// Stufe 3 wurde dieser Helper auch von der ehemaligen
    /// `durationCard` im Setup-Screen genutzt; mit dem Wechsel zur
    /// `timeDisplayCard` (XXL + Pencil) ist das Modal jetzt der einzige
    /// Call-Site.
    /// **Daily Drop Modul 3 (2026-05-23)** — toter Code (ersetzt durch
    /// `exerciseCountChip`); bleibt vorerst (separater Cleanup).
    private func durationChip(minutes: Int) -> some View {
        // **2026-04-24 Tap-Reliability-Fix** (User-Report: „1–2 Taps
        // gehen, dann nicht mehr"). Frühere Varianten mit `Button {}
        // label:` in einer ScrollView haben nach State-Changes
        // intermittent Taps verloren. Der robusteste Pattern für
        // ScrollView-Inhalte ist ein pures `ZStack + onTapGesture`
        // mit:
        //
        //   1. ZStack mit Background + Stroke + Label — alles EINE
        //      zusammenhängende View (kein Button-Wrapper, der seine
        //      eigene Hit-Area ableitet).
        //   2. `.frame(maxWidth: .infinity, minHeight: 44)` — Apple-
        //      HIG-kompatible Tap-Area, expliziter Full-Width-Stretch,
        //      damit der ganze 1/3-Slot tappbar ist.
        //   3. `.contentShape(Rectangle())` NACH dem Background — setzt
        //      die Hit-Area auf das volle Rechteck.
        //   4. `.onTapGesture { ... }` — schneller, reliabler Tap-
        //      Handler ohne Button-Wrapper-Overhead.
        //   5. Farb-Transition kommt über `.animation(_, value:)` auf
        //      der Chip-Ebene — nur auf Color-Änderung.
        //
        // **Sache B Stufe 1 (2026-04-29)**: Pulse-Animation entfernt.
        // Vorher pulsierten alle drei Chips so lange `selectedDuration
        // == nil`, um zur Wahl einzuladen. Mit der `@AppStorage`-Migration
        // ist `selectedDuration` immer gesetzt (Default = `durationDefault`),
        // ergo kein nil-State mehr → der Pulse wäre tot. Die TimelineView
        // + wave/stagger/glow-Mechanik ist daher entfallen; der Chip ist
        // jetzt rein state-driven.
        // **UX-Polish 2026-05-02** — Modal-Selektion ist jetzt
        // optional (`modalDurationSelection`); bei Modal-Open kein
        // Preselect. Selected-State liest den Modal-State, nicht
        // `selectedDuration`. Tap setzt beide Werte (View-State +
        // persistent storage).
        let moduleColor = sectionStyle.accent
        let isSelected = modalDurationSelection == minutes
        let shouldPulse = modalDurationSelection == nil
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isSelected
                        ? moduleColor.opacity(0.25)
                        : AppTheme.Colors.secondarySurface
                )
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? moduleColor : Color.clear,
                    lineWidth: isSelected ? 2 : 0
                )
            // **UX-Polish 2026-05-02** — Number-Font 16 → 32 pt,
            // Card-Höhe 44 → 88. Cards prominent als „bewusste Wahl"-
            // Element, statt als Kleingedrucktes neben anderen Modal-
            // Elementen.
            VStack(alignment: .center, spacing: 2) {
                Text("\(minutes)")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("min")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textPrimary.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .opacity(isSelected ? 1.0 : 0.85)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            #if DEBUG
            appDebugLog("🕒 [DurationChip] tap on \(minutes) (prev=\(String(describing: modalDurationSelection)))")
            #endif
            modalDurationSelection = minutes
            selectedDuration = minutes
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #if DEBUG
            appDebugLog("🕒 [DurationChip] modalDurationSelection → \(minutes) ✓")
            #endif
            // **2026-05-06 Refactor (Pop-up-Only)** — Auto-Close direkt
            // nach Time-Tap. User-Spec: „User tippt Zeit-Card → Pop-up
            // schließt automatisch → Slot-Screen erscheint mit
            // blinkendem CTA". Kein zusätzlicher „Los geht's"-CTA mehr
            // im Pop-up, der Tap auf die Zeit-Card IST die Bestätigung.
            dismissSetupModal()
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        // **UX-Polish 2026-05-02** — Pulsations-Hint solange noch
        // keine Card gewählt. Bei erstem Tap stoppt die Pulse-
        // Schleife (`shouldPulse = false`); Pulse springt auf den
        // CTA „Los geht's" über.
        .pulsing(active: shouldPulse, glowColor: moduleColor)
    }

}
