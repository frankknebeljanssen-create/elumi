import SwiftUI

/// **Trainings-Chain Step-Header** (Stufe 5, 2026-05-02,
/// Branch `feature/training-session-flow`).
///
/// Refactor von der Single-Line-Bar (Stufe 4a) zu einem reicheren
/// **Header-Block mit drei Step-Cards plus prominent gerendertem
/// Countdown-Timer**. Wird vom `ChainTimerOverlayModifier` per
/// `safeAreaInset(edge: .top)` injiziert, sobald eine Chain aktiv
/// ist.
///
/// **Layout-Schichten (oben → unten):**
///
///   1. **Drei Step-Cards** (gleichbreit, HStack mit kleinem Spacing).
///      Rendert ALLE drei Slot-Resultate aus
///      `chain.sourceCenterSymbolKinds`, also auch die Game-Slots —
///      User-Wunsch „header soll alle drei Slots zeigen, auch wenn
///      einer ein Game ist". `plannedSteps` (Game-gefiltert) wird nur
///      für Current-Step-Mapping benutzt.
///      State pro Card:
///        * **past** — abgeschlossen, gedimmt (60 % Opacity), Häkchen.
///        * **current** — Accent-Border (2 pt), volle Sättigung.
///        * **future** — gedimmt (50 % Opacity), keine Border.
///        * **game** — Slot-Indikator mit Axolotl, „Game"-Label,
///          immer im Past/Future-Style (nie current — Game-Slots sind
///          keine Übungen, der Chain-Pointer überspringt sie).
///
///   2. **Prominenter Timer** unter den Step-Cards. MM:SS in 22-pt
///      Black-Rounded statt der vorherigen 13-pt-Bar — der Timer ist
///      die wichtigste Info im Chain-Header und soll auf einen Blick
///      lesbar sein. Daneben ein dezenter „ÜBUNG X VON Y"-Tag, damit
///      die Schritt-Position nicht verloren geht. Progress-Bar (4 pt)
///      darunter.
///
/// **Urgency-Verhalten** (unverändert von Stufe 4a):
///   * Sekunden ≤ 10 → Sekunden-Zahl rot + leichter Scale-Bounce.
///   * Sekunden = 0 (timerExpired) → Komplettzeile in Warning-Rot
///     („0:00" bleibt persistent sichtbar).
///
/// **Source-Slot → Current-Step-Mapping**: `currentStepIndex` ist
/// 0-basiert in `plannedSteps` (Game-gefiltert). Wir walken
/// `sourceSlots` und zählen Module-Slots, bis `currentStepIndex`
/// erreicht ist — das ist die aktive Source-Position. Past = davor,
/// Future = danach. Game-Slots haben keinen Status.
struct ChainStepTimerBar: View {
    let sourceSlots: [TrainingChainContext.SourceSlotKind]
    let currentStepIndex: Int
    let remainingSeconds: Int
    let totalSeconds: Int

    /// Schwelle für Urgency-Highlight (rote Sekunden-Zahl + Bounce).
    /// Konsistent mit `SpeedRoundTimerCard.isUrgent` (10-s-Konvention).
    private var isUrgent: Bool { remainingSeconds <= 10 && remainingSeconds > 0 }

    /// 0 Sekunden → Soft-Cutoff erreicht. Zeile bleibt sichtbar mit
    /// Progress = 0 und Warning-Rot — das `ChainCutoffModal` (im
    /// Modifier) übernimmt die einmalige Hinweis-Kommunikation.
    private var isExpired: Bool { remainingSeconds <= 0 }

    private var formattedTime: String {
        let mm = remainingSeconds / 60
        let ss = remainingSeconds % 60
        return String(format: "%d:%02d", mm, ss)
    }

    private var foregroundForTime: Color {
        if isExpired { return AppTheme.Colors.error }
        if isUrgent { return AppTheme.Colors.error }
        return AppTheme.Colors.warning
    }

    /// Welche Source-Slot-Position entspricht dem aktuellen `currentStepIndex`?
    /// Walk durch `sourceSlots`, zähle Module-Slots; wenn der Zähler
    /// `currentStepIndex` erreicht, ist das die aktive Position.
    private var activeSourcePosition: Int? {
        var moduleCount = 0
        for (index, slot) in sourceSlots.enumerated() {
            if case .module = slot {
                if moduleCount == currentStepIndex {
                    return index
                }
                moduleCount += 1
            }
        }
        return nil
    }

    /// Zustand pro Source-Slot — entscheidet das visuelle Erscheinungsbild
    /// in `stepCard(_:state:)`.
    private enum SlotState {
        case past
        case current
        case future
        case game
    }

    private func slotState(at index: Int) -> SlotState {
        let slot = sourceSlots[index]
        if case .game = slot { return .game }
        guard let active = activeSourcePosition else {
            // Chain ist über das letzte Modul hinaus (currentStep == nil)
            // — alle Module-Slots sind „past".
            return .past
        }
        if index < active { return .past }
        if index == active { return .current }
        return .future
    }

    var body: some View {
        VStack(spacing: 6) {
            // 1. Step-Cards-Reihe
            HStack(spacing: 6) {
                ForEach(Array(sourceSlots.enumerated()), id: \.offset) { index, slot in
                    stepCard(slot: slot, state: slotState(at: index))
                }
            }

            // 2. Prominenter Timer + Progress-Bar
            timerBlock
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Step Cards

    @ViewBuilder
    private func stepCard(slot: TrainingChainContext.SourceSlotKind, state: SlotState) -> some View {
        switch slot {
        case .module(let module):
            moduleStepCard(module: module, state: state)
        case .game:
            gameStepCard()
        }
    }

    private func moduleStepCard(module: HomeHeroModule, state: SlotState) -> some View {
        VStack(spacing: 2) {
            HomeModuleIconView(
                icon: module.icon,
                size: 22,
                glyphTint: .white
            )
            Text(module.title)
                // **UX-Polish 2026-05-02 (User-Befund „Modul-Namen
                // im Chain-Header zu klein")**: 9 → 11 pt. Card-Höhe
                // bleibt im Soll (~39 pt) — kein Layout-Sprung, weil
                // Vertical-Padding (4) und Icon (22) unverändert.
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(stepCardForeground(state: state))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(module.accent.opacity(state == .current ? 0.18 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    state == .current ? module.accent : Color.clear,
                    lineWidth: 2
                )
        )
        .opacity(stepCardOpacity(state: state))
        .overlay(alignment: .topTrailing) {
            if state == .past {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.success)
                    .padding(2)
            }
        }
    }

    private func gameStepCard() -> some View {
        VStack(spacing: 2) {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            Text("Game")
                // **UX-Polish 2026-05-02** — siehe `moduleStepCard`:
                // 9 → 11 pt für Lesbarkeits-Konsistenz mit den
                // Modul-Cards.
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Colors.warning.opacity(0.06))
        )
        .opacity(0.6)
    }

    private func stepCardForeground(state: SlotState) -> Color {
        switch state {
        case .past, .future, .game:
            return AppTheme.Colors.textSecondary
        case .current:
            return AppTheme.Colors.textPrimary
        }
    }

    private func stepCardOpacity(state: SlotState) -> Double {
        switch state {
        case .past:    return 0.6
        case .current: return 1.0
        case .future:  return 0.5
        case .game:    return 0.6
        }
    }

    // MARK: - Timer Block

    private var moduleStepLabel: String {
        let totalModules = sourceSlots.filter {
            if case .module = $0 { return true }
            return false
        }.count
        guard totalModules > 0 else { return "" }
        let displayStep = min(currentStepIndex + 1, totalModules)
        return "ÜBUNG \(displayStep) VON \(totalModules)"
    }

    private var timerBlock: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(moduleStepLabel)
                    // **UX-Polish 2026-05-02 (User-Befund „Übung X
                    // von Y zu klein")**: 10 → 12 pt. Sitzt
                    // auf der gleichen baseline wie der MM:SS-Timer
                    // (22 pt) — relative Hierarchie bleibt stabil
                    // (Timer dominant, Step-Indikator klar lesbar
                    // aber sekundär).
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                Text(formattedTime)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(foregroundForTime)
                    .monospacedDigit()
                    .scaleEffect(isUrgent ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: remainingSeconds)
            }

            GeometryReader { geo in
                let safeTotal = max(1, CGFloat(totalSeconds))
                let progress = max(0, min(1, CGFloat(remainingSeconds) / safeTotal))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                    Capsule()
                        .fill(foregroundForTime)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.linear(duration: 1.0), value: remainingSeconds)
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())
        }
    }
}

/// **Daily Drop Count-Bar** (Modul 2, 2026-05-23).
///
/// Persistente, schlanke Fortschritts-Bar für den Count-Modus der
/// Trainings-Chain. Ersetzt im `ChainTimerOverlayModifier` die
/// `ChainStepTimerBar`, wenn `chain.isCountMode == true` — zeigt
/// „Übung X von N" + eine Fortschritts-Capsule statt eines Countdowns.
/// Liest `completed`/`total` aus dem `TrainingChainStore` (Singleton),
/// daher persistiert die Bar automatisch über alle Chain-Steps.
struct ChainStepCountBar: View {
    /// Ergebnis je beantworteter Aufgabe (true = richtig). Länge ≤ total.
    let results: [Bool]
    let total: Int

    private var safeTotal: Int { max(1, total) }
    private var completed: Int { min(results.count, safeTotal) }

    /// 1-basierte „aktuelle Übung", gedeckelt auf `total` (am Ende
    /// zeigt die Bar „Übung N von N" statt „N+1").
    private var current: Int { min(completed + 1, safeTotal) }

    /// Segment-Farbe: beantwortet → grün/rot, noch offen → neutral.
    private func segmentColor(at index: Int) -> Color {
        if index < results.count {
            return results[index] ? AppTheme.Colors.success : AppTheme.Colors.error
        }
        return AppTheme.Colors.textSecondary.opacity(0.18)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Übung \(current) von \(safeTotal)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text("\(completed)/\(safeTotal)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }

            // Ein Segment je Aufgabe (grün = richtig, rot = falsch,
            // neutral = noch offen). Capsules teilen sich die Breite
            // gleichmäßig über den HStack.
            HStack(spacing: 3) {
                ForEach(0..<safeTotal, id: \.self) { index in
                    Capsule()
                        .fill(segmentColor(at: index))
                        // **Daily Drop Modul 2.10 (2026-05-23)** — Segment-Höhe
                        // verdoppelt (5 → 10); Capsule rundet automatisch
                        // proportional (kein expliziter Corner-Radius nötig).
                        .frame(height: 10)
                        .animation(.easeOut(duration: 0.25), value: results.count)
                }
            }
        }
        .padding(.horizontal, 12)
        // **Daily Drop Modul 2.12 (2026-05-23)** — mehr Abstand nach oben,
        // damit die Bar nicht an der Statusleiste klebt, sondern tiefer
        // (näher am Modul-Header) sitzt (User-Spec). Unten kompakt belassen.
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}
