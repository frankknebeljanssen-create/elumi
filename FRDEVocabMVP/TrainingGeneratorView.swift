import SwiftUI

/// **Training-Generator-Screen** (Phase 8, V4) — separater Einstieg aus dem
/// Elumi-Tab. Zwei interne Stages im selben Screen:
///
///   1. `.setup` — Dauer + Fokus wählen, „Training bauen" tippen
///   2. `.slot`  — Slot-Machine (drehen), Reveal + Ergebnis-Panel + CTAs
///                 alles auf demselben Screen. KEIN Auto-Navigation!
///
/// V4-Änderungen (User-Spec 2026-04-22 Nachmittag+Abend):
///   • Zusammengelegte Stages — kein separater Result-Screen mehr
///   • Slot-Machine lebt komplett auf dem Slot-Stage, Reveal-Moment
///     und Ergebnis-Panel erscheinen dort inline
///   • User entscheidet aktiv (Training starten / Nochmal drehen)
///   • Spin-Budget: 3 Base-Spins + Bonus-Credits über Elumi-Treffer
///   • Elumi-Bonus-Symbol mit gewichteter Drop-Rate (s. `SlotMachineDropRate`)
struct TrainingGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let navigate: (AppScreen) -> Void

    @StateObject private var store = TrainingGeneratorStore.shared
    @StateObject private var dropRate = ElumiDropRateControllerStore()
    @StateObject private var budget = SlotMachineSpinBudgetStore()

    @State private var selectedDuration: Int = 10
    @State private var selectedFocus: TrainingFocus = .mixed
    @State private var stage: Stage = .setup

    // MARK: Slot-State

    @State private var slotPhase: SlotPhase = .idle
    @State private var slotStartToken: Bool = false
    @State private var spinTargets: [ReelSymbol?] = [nil, nil, nil]
    @State private var lastSpinResult: SlotSpinResult?
    /// Letzter vergebener Bonus in Credits — für die „+N Credits"-Toast.
    @State private var lastBonusToast: Int = 0
    @State private var showBonusToast: Bool = false

    private let sectionStyle: AppSectionStyle = .elumi

    private enum Stage {
        case setup
        case slot
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            switch stage {
            case .setup: setupStage
            case .slot:  slotStage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appScreenBackground(sectionStyle)
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: openSettings
            )
        }
        .onAppear {
            print("🎰 [TrainingGeneratorView.onAppear] stage=\(stage), slotPhase=\(slotPhase)")
            // State aus dem Store vorauswählen — der User kommt ggf. aus
            // einer vorherigen Session und findet seine Einstellung wieder.
            selectedDuration = store.lastDuration
            selectedFocus = store.lastFocus
            // **V4.1 Stability-Pass**: KEIN Auto-Jump mehr in `.slot`,
            // auch wenn eine alte Session existiert. Der User soll beim
            // Einstieg immer auf Setup landen und bewusst „Training
            // bauen" tippen. Das verhindert das berichtete
            // „Screens überlagern sich"-Verhalten, wenn man aus einer
            // Sub-Navigation zurückkommt.
        }
    }

    // MARK: - Stage 1: Setup

    private var setupStage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ModuleHeaderCard(
                    systemImage: "sparkles",
                    title: "Training-Generator",
                    accent: sectionStyle.accent,
                    onBack: { dismiss() }
                )

                headlineCard
                durationPicker
                focusPicker
                Spacer(minLength: 24)
                buildTrainingCTA
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Elumi baut dein Training")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Wähle, wie lange du üben möchtest. Elumi stellt dir daraus ein passendes Training zusammen.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .appSetupCardBackground()
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DAUER")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(AppTheme.Colors.cardLabel)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach([5, 10, 15, 20], id: \.self) { minutes in
                    durationChip(minutes: minutes)
                }
            }
        }
    }

    private func durationChip(minutes: Int) -> some View {
        let isSelected = selectedDuration == minutes
        return Button {
            selectedDuration = minutes
            store.lastDuration = minutes
        } label: {
            VStack(spacing: 2) {
                Text("\(minutes)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Minuten")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: "#888888"))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? sectionStyle.accent.opacity(0.22) : Color(hex: "#1A2A40"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? sectionStyle.accent : Color(hex: "#243B55"),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var focusPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOKUS")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(AppTheme.Colors.cardLabel)
                .textCase(.uppercase)

            // Zwei-Zeilen-Grid, damit alle fünf Fokus-Optionen gleichmäßig
            // nebeneinander passen. Nicht-voll-unterstützte Optionen sind
            // mit reduzierter Opacity markiert, bleiben aber tappbar —
            // der Generator baut dann einen Mixed-Fallback.
            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(TrainingFocus.allCases) { focus in
                    focusChip(focus)
                }
            }
        }
    }

    private func focusChip(_ focus: TrainingFocus) -> some View {
        let isSelected = selectedFocus == focus
        return Button {
            selectedFocus = focus
            store.lastFocus = focus
        } label: {
            VStack(spacing: 4) {
                Image(systemName: focus.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? sectionStyle.accent : Color.white.opacity(0.55))
                Text(focus.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? sectionStyle.accent.opacity(0.18) : Color(hex: "#1A2A40"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? sectionStyle.accent : Color(hex: "#243B55"),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .opacity(focus.isFullySupportedV1 ? 1.0 : 0.75)
        }
        .buttonStyle(.plain)
    }

    private var buildTrainingCTA: some View {
        SessionPrimaryCTA(title: "Los geht's!") {
            startBuildFlow()
        }
    }

    // MARK: - Stage 2: Slot-Machine V4.2 (Overlay-Pass)

    /// Slot-Screen als ZStack mit klarer Schicht-Reihenfolge:
    ///   1. Background: Maschine + Budget-Banner (+ „Drehen"-CTA gepinnt)
    ///   2. Result-Overlay: nur wenn `slotPhase == .revealed`, blockiert
    ///      Interaktion mit Hintergrund, enthält eigenes „Training
    ///      starten" + „Nochmal drehen"
    ///
    /// Die untere Safe-Area-CTA wird ausgeblendet, sobald das Overlay
    /// aktiv ist — keine doppelten Buttons.
    private var slotStage: some View {
        ZStack {
            slotBackgroundLayer

            if slotPhase == .revealed, let session = store.lastSession {
                slotResultOverlay(for: session)
                    .zIndex(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: slotPhase)
    }

    /// Haupt-Content unter dem potenziellen Overlay.
    private var slotBackgroundLayer: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ModuleHeaderCard(
                    systemImage: "sparkles",
                    title: "Dein Spiel!",
                    accent: sectionStyle.accent,
                    onBack: handleBackFromSlot
                )

                spinBudgetBanner

                slotMachineArea
                    .padding(.top, 4)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, AppLayout.sessionCTABottomClearance + 140)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear {
            print("🎰 [slotStage.onAppear] stage=\(stage), slotPhase=\(slotPhase)")
        }
        .safeAreaInset(edge: .bottom) {
            // CTA **nur** sichtbar, solange kein Overlay aktiv ist —
            // das Overlay bringt seine eigenen Aktionen mit.
            if slotPhase != .revealed {
                slotActionCTAs
            }
        }
    }

    // MARK: - Slot-Stage-Teile

    private var spinBudgetBanner: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.circlepath")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
                Text("Spins: \(budget.totalSpinsAvailable)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(sectionStyle.accent.opacity(0.14)))
            .overlay(Capsule().stroke(sectionStyle.accent.opacity(0.45), lineWidth: 1))

            if budget.bonusCredits > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "#FFD166"))
                    Text("+\(budget.bonusCredits) Bonus")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#FFD166"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(hex: "#FFD166").opacity(0.15)))
                .overlay(Capsule().stroke(Color(hex: "#FFD166").opacity(0.55), lineWidth: 1))
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: budget.bonusCredits)
    }

    private var slotMachineArea: some View {
        VStack(spacing: 12) {
            SlotMachineView(
                reelPools: ReelSymbol.standardReelPools,
                accent: sectionStyle.accent,
                spinTargets: $spinTargets,
                spinStartToken: $slotStartToken,
                phase: $slotPhase,
                onLanded: handleSlotLanded,
                onReelSettled: { _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    feedbackPlayer.playTabSwitch()
                },
                onSpinStart: {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    feedbackPlayer.playTabSwitch()
                }
            )
            .frame(maxWidth: .infinity)

            // Status-Label unter der Maschine
            Text(statusLabelForSlotPhase)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .animation(nil, value: slotPhase)
        }
    }

    private var statusLabelForSlotPhase: String {
        switch slotPhase {
        case .idle:     return "Bereit — tippe auf Drehen, wenn du startklar bist."
        case .spinning: return "Elumi würfelt dein Training …"
        case .stopping: return "Die Walzen halten an …"
        case .landed:   return "Einrasten …"
        case .revealed: return "Dein Training ist bereit."
        }
    }

    // MARK: - Result-Overlay

    /// Result-Overlay als eigener Layer über dem Slot-Screen.
    /// Blockiert die Hintergrund-Interaktion durch einen
    /// tappbaren Dimm-Background + eigenes Card-Panel mit allen
    /// Aktions-CTAs.
    @ViewBuilder
    private func slotResultOverlay(for session: GeneratedTrainingSession) -> some View {
        ZStack {
            // Dimm-Hintergrund — blockiert Interaktion mit Slot-Screen
            // darunter. Kein Tap-Dismiss — User muss bewusst CTA wählen.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* intentional no-op: Overlay bleibt sichtbar bis CTA */ }

            // Result-Card
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Dein Training ist bereit")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("\(session.blocks.count) Blöcke · \(session.totalDurationMinutes) min")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(session.blocks.enumerated()), id: \.element.id) { index, block in
                            blockCard(block, index: index + 1)
                        }
                    }
                }
                .frame(maxHeight: 320)

                VStack(spacing: 10) {
                    SessionPrimaryCTA(title: "Training starten", isEnabled: true) {
                        startTraining()
                    }

                    Button {
                        triggerSpinFromOverlay()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.2.circlepath")
                                .font(.system(size: 16, weight: .bold))
                            Text(spinAgainButtonLabel)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(budget.canSpin ? sectionStyle.accent : AppTheme.Colors.textSecondary.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(sectionStyle.accent.opacity(budget.canSpin ? 0.14 : 0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(sectionStyle.accent.opacity(budget.canSpin ? 0.4 : 0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!budget.canSpin)
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#101522"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(sectionStyle.accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 24)
        }
    }

    /// Aus dem Overlay „Nochmal drehen" — setzt Phase auf idle zurück
    /// und triggert direkt einen neuen Spin. Overlay verschwindet durch
    /// den Phase-Wechsel automatisch.
    private func triggerSpinFromOverlay() {
        guard budget.canSpin else { return }
        slotPhase = .idle
        triggerSpin()
    }

    private var slotActionCTAs: some View {
        VStack(spacing: 12) {
            // Nochmal drehen — sekundäre Action.
            Button {
                triggerSpin()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.system(size: 18, weight: .bold))
                    Text(spinAgainButtonLabel)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                }
                .foregroundStyle(canSpin ? sectionStyle.accent : AppTheme.Colors.textSecondary.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 53)
                .background(
                    RoundedRectangle(cornerRadius: AppLayout.sessionCTARadius, style: .continuous)
                        .fill(sectionStyle.accent.opacity(canSpin ? 0.12 : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppLayout.sessionCTARadius, style: .continuous)
                        .stroke(sectionStyle.accent.opacity(canSpin ? 0.35 : 0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSpin)

            // Training starten — primär. Erst ab `.revealed` aktiviert.
            SessionPrimaryCTA(
                title: "Training starten",
                isEnabled: slotPhase == .revealed && store.lastSession != nil
            ) {
                startTraining()
            }
            .padding(.bottom, AppLayout.sessionCTABottomClearance)
        }
        .padding(.horizontal, AppLayout.screenPadding)
    }

    private var canSpin: Bool {
        budget.canSpin && (slotPhase == .idle || slotPhase == .revealed)
    }

    private var spinAgainButtonLabel: String {
        if !budget.canSpin {
            return "Keine Spins mehr"
        }
        if slotPhase == .idle {
            return "Drehen"
        }
        return "Nochmal drehen"
    }

    private func blockCard(_ block: TrainingBlock, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(sectionStyle.accent.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: block.exerciseType.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(block.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("· Block \(index)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Text(block.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(block.durationMinutes) min")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.cta)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(AppTheme.Colors.cta.opacity(0.15))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    // MARK: - Actions

    /// Setup-Screen „Training bauen" — wechselt in den Slot-Stage.
    /// **V4.1 Stability-Pass**: kein Auto-Spin mehr. Der User tippt
    /// auf „Drehen" im Slot-Screen, wenn er bereit ist. Damit ist klar
    /// getrennt: Setup → Slot-Screen (idle) → User-Aktion → Spin.
    private func startBuildFlow() {
        print("🎰 [startBuildFlow] stage=.slot, slotPhase=.idle (kein Auto-Spin)")
        feedbackPlayer.playTabSwitch()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        budget.reset()
        dropRate.reset()
        slotPhase = .idle
        spinTargets = [nil, nil, nil]
        slotStartToken = false
        showBonusToast = false
        stage = .slot
    }

    /// Slot-Spin auslösen (Base-Spin oder Bonus-Credit). Wird nur
    /// vom „Drehen" / „Nochmal drehen"-Button aus dem Slot-Screen
    /// aufgerufen — NIE automatisch.
    private func triggerSpin() {
        print("🎰 [triggerSpin] canSpin=\(canSpin), phase=\(slotPhase), budget=\(budget.totalSpinsAvailable)")
        guard canSpin else { return }
        guard budget.consumeSpin() else { return }
        // Pro-Reel Ziel-Symbol berechnen mit aktueller Elumi-Chance.
        let chance = dropRate.currentElumiChance()
        let pools = ReelSymbol.standardReelPools
        var targets: [ReelSymbol?] = []
        for reelIndex in 0..<3 {
            if dropRate.drawIsElumi(chance: chance) {
                targets.append(ReelSymbol.elumi)
            } else {
                let pool = pools[reelIndex]
                targets.append(pool.randomElement())
            }
        }
        spinTargets = targets
        slotStartToken = true
    }

    /// Callback von `SlotMachineView` nach Landing+Reveal.
    /// **V4.1 Stability-Pass**: KEINE automatische Screen-Navigation.
    /// Wir bauen die Session und halten das Ergebnis. User entscheidet
    /// selbst über „Training starten" oder „Nochmal drehen".
    private func handleSlotLanded(_ result: SlotSpinResult) {
        print("🎰 [handleSlotLanded] elumiCount=\(result.elumiCount) — KEIN Auto-Wechsel")
        lastSpinResult = result
        dropRate.registerSpinResult(elumiCount: result.elumiCount)
        let awarded = budget.awardBonusCredits(for: result.elumiCount)
        if awarded > 0 {
            lastBonusToast = awarded
            showBonusToast = true
            let style: UIImpactFeedbackGenerator.FeedbackStyle = result.elumiCount >= 3 ? .heavy : (result.elumiCount == 2 ? .medium : .light)
            UIImpactFeedbackGenerator(style: style).impactOccurred()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            feedbackPlayer.playAchievement()
            // Toast-Auto-Ausblenden ENTFERNT — bleibt stehen, bis der
            // User den nächsten Spin startet. Keine async-Timer mehr
            // hier, die später ungewollt eine State-Änderung auslösen.
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        let session = TrainingGenerator.generate(
            duration: selectedDuration,
            focus: selectedFocus
        )
        store.storeSession(session)
    }

    private func handleBackFromSlot() {
        // Back aus dem Slot-Screen → zurück zum Setup, Slot-State reset.
        print("🎰 [handleBackFromSlot] → stage=.setup")
        slotPhase = .idle
        slotStartToken = false
        spinTargets = [nil, nil, nil]
        showBonusToast = false
        stage = .setup
    }

    private func startTraining() {
        guard let firstBlock = store.lastSession?.blocks.first else { return }
        feedbackPlayer.playTabSwitch()
        // **V1-Stub-Architektur**: Der Training-Generator baut die Session
        // komplett, aber die echte Verkettung mehrerer Blöcke durch die
        // bestehenden Module-Views fehlt noch. V1 navigiert direkt in den
        // ersten Block-Mode; spätere Ausbaustufe kann die Session an den
        // AppDestinationHost reichen und über alle Blöcke iterieren.
        navigate(routeForBlock(firstBlock))
    }

    /// Mappt `TrainingExerciseType` auf die beste verfügbare App-Route.
    /// Fallback auf Flashcards für Typen ohne direkten 1:1-Match in V1.
    private func routeForBlock(_ block: TrainingBlock) -> AppScreen {
        switch block.exerciseType {
        case .warmup, .flashcards, .review:
            return .flashcards(nil)
        case .quiz:
            return .quiz(nil)
        case .speed, .writing, .match:
            return .train(nil)
        case .articles:
            return .train(nil)
        case .accents:
            return .accents(nil)
        }
    }
}
