import SwiftUI
import UIKit

/// **Trainings-Chain End-Summary** (Stufe 5, 2026-05-02,
/// Branch `feature/training-session-flow`).
///
/// Ersetzt die `TrainingChainCompletePlaceholderView` aus Stufe 3.
/// Wird gepusht, wenn der letzte Chain-Step über „Training abschließen"
/// abgeschlossen ist (`AppDestinationHost`-Wiring,
/// `case .trainingChainComplete`).
///
/// **Inhalts-Reihenfolge (von oben nach unten):**
///
///   • Block A — inline Chain-Step-Cards (alle mit Häkchen, alle Steps
///     sind erledigt). Nutzt das gleiche Card-Rendering wie der
///     `ChainStepTimerBar`-Header während aktiver Chain (Pattern-Mirror,
///     damit der User die Continuity sieht). Kein Timer mehr — Chain
///     ist durch.
///
///   • Block B — Hero. Headline „Geschafft!" plus animierter
///     Gesamt-XP-Counter (zählt von 0 hoch, ~1.5 s Dauer). XP =
///     Summe aller `stepOutcomes.totalXP`.
///
///   • Block C — Stats-Liste. Pro Modul-Step eine Mini-Card mit Modul-
///     Icon + Title + „N von M richtig" + Häkchen. Plus Aggregates:
///     Korrekt-Quote-Total, Streak (falls heute hochgesetzt), Tickets
///     (aus dem Slot-Spin via `chain.sourceCenterSymbolKinds`),
///     Level-Up-Badge (nur wenn ein `stepOutcome.leveledUp == true`).
///
///   • Block D — Feier. `ConfettiBurst` als Overlay (Canvas +
///     TimelineView, 60 Partikel, 2.5 s Lifetime). `playStudySuccess()`
///     + `UINotificationFeedbackGenerator(.success)` einmalig on appear.
///     Kein Maskottchen-Animation — gespart für Stufe 6 (Jackpot).
///
///   • Block E — CTAs. Primary „Noch eine Runde" pulsiert (Pattern wie
///     Block-2-CTA-Pulse), führt zurück zum ELUMI-Tab + räumt Chain.
///     Secondary „Zur Startseite" → Home + Chain-Clear.
///
/// **Daten-Quellen:**
///   • `chainStore.currentChain.sourceCenterSymbolKinds` — die drei
///     Slot-Resultate (Module + Game-Slots) für Block A
///   • `chainStore.stepOutcomes` — pro Modul-Step das `SessionRewardOutcome`
///     mit XP, Korrekt-Anzahl, Streak/Level-Up. Reihenfolge entspricht
///     Step-Index in `chain.plannedSteps` (Game-Slots gefiltert).
///   • `slotCreditGrantTable[gameSlotCount]` — Tickets aus dem Slot
///     (1×Game = 1, 2×Game = 3, 3×Game = 6).
///
/// **Navigations-Verhalten:**
///   • Primary CTA: `onPlayAgain()` — Caller (AppDestinationHost) räumt
///     Chain ab und navigiert zurück zur ELUMI-Tab (Slot-Machine-Re-Spin).
///   • Secondary CTA: `onGoHome()` — Caller räumt Chain ab und navigiert
///     zum Home-Tab.
///   • Back-Chevron (Header / Footer-Home): Chain wird via `clear()`
///     in `AppNavigationCoordinator.goHome()` (Hot-Fix vom 2026-05-02)
///     ohnehin geräumt.
struct TrainingChainCompleteSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    @ObservedObject private var chainStore = TrainingChainStore.shared
    @ObservedObject var feedbackPlayer: FeedbackPlayer

    /// Caller-Hook für Primary-CTA „Noch eine Runde". Soll Chain
    /// abräumen + zur Slot-Machine (ELUMI-Tab) zurückkehren.
    let onPlayAgain: () -> Void
    /// Caller-Hook für Secondary-CTA „Zur Startseite". Soll Chain
    /// abräumen + Home navigieren.
    let onGoHome: () -> Void
    let openSettings: () -> Void

    @State private var displayedTotalXP: Int = 0
    @State private var hasAppeared: Bool = false
    @State private var ctaVisible: Bool = false
    @State private var confettiStartDate: Date = Date()
    @State private var showConfetti: Bool = false

    private let sectionStyle: AppSectionStyle = .home

    // MARK: - Aggregierte Stats

    private var stepOutcomes: [SessionRewardOutcome] {
        chainStore.stepOutcomes
    }

    /// Gesamt-XP aller abgeschlossenen Steps.
    private var totalXP: Int {
        stepOutcomes.reduce(0) { $0 + $1.totalXP }
    }

    /// Gesamt-richtig über alle Steps.
    private var totalCorrect: Int {
        stepOutcomes.reduce(0) { $0 + $1.session.correctCount }
    }

    /// Gesamt-Versuche (richtig + falsch) über alle Steps.
    private var totalAttempts: Int {
        stepOutcomes.reduce(0) { $0 + $1.session.correctCount + $1.session.wrongCount }
    }

    /// Wurde in der Chain ein Level-Up erreicht? Wenn ja, der höchste
    /// `newLevel`-Wert aus den Outcomes.
    private var levelUpInfo: (didLevelUp: Bool, newLevel: Int) {
        for outcome in stepOutcomes where outcome.leveledUp {
            return (true, outcome.newLevel)
        }
        return (false, 0)
    }

    /// Wurde der Streak heute hochgesetzt? Liefert dann den finalen
    /// `newStreak`-Wert.
    private var streakInfo: (increasedToday: Bool, newStreak: Int) {
        // Letzter Outcome reflektiert finalen State — wenn irgendein
        // Step die Streak erhöht hat, ist `streakIncreasedToday` dort
        // true. `newStreak` propagiert kumulativ.
        guard let last = stepOutcomes.last else { return (false, 0) }
        return (last.streakIncreasedToday, last.newStreak)
    }

    /// Tickets aus dem Slot-Spin (1×Game = 1, 2×Game = 3, 3×Game = 6).
    /// Mirror der Logik aus `TrainingChainOverviewView.ticketsFromGameSlots`.
    private var ticketsFromSlot: Int {
        guard let chain = chainStore.currentChain else { return 0 }
        let gameCount = chain.sourceCenterSymbolKinds.filter { kind in
            if case .game = kind { return true }
            return false
        }.count
        switch gameCount {
        case 1: return 1
        case 2: return 3
        case 3: return 6
        default: return 0
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    chainStepHeader
                    heroBlock
                    statsSection
                    ctaBlock
                }
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.screenHeaderTopPadding)
                // **2026-05-08 Padding-Cleanup** — `footerHeight +
                // insetBottom + lg` → `Spacing.lg`. Footer per
                // safeAreaInset reserviert.
                .padding(.bottom, AppTheme.Spacing.lg)
                .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            // Block D — Konfetti-Overlay über allem.
            if showConfetti {
                ConfettiBurst(startDate: confettiStartDate)
                    .allowsHitTesting(false)
            }
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            // Kein expliziter Back-Chevron — User soll via CTAs raus,
            // nicht zurück in einen abgeschlossenen Chain-Step. Info-
            // Button bleibt für Konsistenz mit anderen Screens.
            AppTopBar(onBack: nil, onInfo: nil)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { onGoHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: openSettings
            )
        }
        .onAppear {
            triggerCelebration()
        }
    }

    // MARK: - Block A — Chain-Step-Cards (alle erledigt)

    /// Inline-Replikat der `ChainStepTimerBar`-Logik, aber ohne Timer
    /// und mit allen Source-Slots im „past"-State (Häkchen). Nutzt
    /// `currentStepIndex == sourceSlots.count`, damit der Walk-
    /// Algorithmus keinen aktiven Slot findet → alle Module-Slots
    /// fallen automatisch auf `.past`. Game-Slots bleiben `.game`.
    @ViewBuilder
    private var chainStepHeader: some View {
        if let chain = chainStore.currentChain, !chain.sourceCenterSymbolKinds.isEmpty {
            ChainStepTimerBar(
                sourceSlots: chain.sourceCenterSymbolKinds,
                currentStepIndex: chain.totalStepCount,
                remainingSeconds: 0,
                totalSeconds: max(1, chain.perStepDurationMin * 60)
            )
            .background(
                AppTheme.Colors.background.opacity(0.92)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Block B — Hero

    private var heroBlock: some View {
        VStack(spacing: 8) {
            Text("Geschafft!")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("+\(displayedTotalXP)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.cta)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("XP")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.cta.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // Animierter XP-Counter — copy aus `SessionSummaryView.task`.
        .task(id: totalXP) {
            let target = totalXP
            guard target > 10 else {
                displayedTotalXP = target
                return
            }
            displayedTotalXP = 0
            let steps = min(28, target)
            guard steps > 0 else { return }
            let totalDuration: Double = 1.5
            let tick = UInt64((totalDuration / Double(steps)) * 1_000_000_000)
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: tick)
                await MainActor.run {
                    displayedTotalXP = min(target, Int(round(Double(target) * Double(i) / Double(steps))))
                }
            }
            await MainActor.run { displayedTotalXP = target }
        }
    }

    // MARK: - Block C — Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Per-Modul-Liste
            VStack(spacing: 8) {
                ForEach(Array(stepOutcomes.enumerated()), id: \.offset) { _, outcome in
                    moduleStatRow(for: outcome)
                }
            }

            // Total-Korrekt-Quote
            if totalAttempts > 0 {
                aggregateStatRow(
                    icon: "target",
                    iconColor: AppTheme.Colors.success,
                    title: "\(totalCorrect) von \(totalAttempts) Fragen richtig",
                    subtitle: nil,
                    isHero: true
                )
            }

            // Streak
            if streakInfo.increasedToday, streakInfo.newStreak > 0 {
                aggregateStatRow(
                    icon: "flame.fill",
                    iconColor: Color(hex: "#FF9F40"),
                    title: "Streak: \(streakInfo.newStreak) \(streakInfo.newStreak == 1 ? "Tag" : "Tage")",
                    subtitle: "Heute gesichert",
                    isHero: false
                )
            }

            // Tickets aus Slot-Spin
            if ticketsFromSlot > 0 {
                // **Block 3.6 (2026-05-03)** — Wording: „X neue
                // Tickets" statt „+N Ticket aus dem Slot". Klarere
                // Direkt-Aussage was der User bekommen hat. Subtitle
                // entfernt — die Information „aus dem Slot" ist auf
                // dem Chain-End-Screen kontextuell klar (User kommt
                // direkt vom Spin). Plus `isHero: true` für die
                // gleiche Font-Größe wie Total-Korrekt-Quote und
                // Level-Up — Tickets sind ein Reward-Highlight,
                // sollen nicht im Subtle-Slot verschwinden.
                aggregateStatRow(
                    icon: "ticket.fill",
                    iconColor: AppTheme.Colors.warning,
                    title: "\(ticketsFromSlot) \(ticketsFromSlot == 1 ? "neues Ticket" : "neue Tickets")",
                    subtitle: nil,
                    isHero: true
                )
            }

            // Level-Up
            if levelUpInfo.didLevelUp {
                aggregateStatRow(
                    icon: "arrow.up.circle.fill",
                    iconColor: AppTheme.Colors.cta,
                    title: "Level \(levelUpInfo.newLevel) erreicht!",
                    subtitle: nil,
                    isHero: true
                )
            }
        }
    }

    /// Pro-Modul-Stat-Card mit Icon + Name + „N von M" + Häkchen.
    private func moduleStatRow(for outcome: SessionRewardOutcome) -> some View {
        let module = homeHeroModule(for: outcome.session.origin)
        let attempts = outcome.session.correctCount + outcome.session.wrongCount
        return HStack(spacing: 12) {
            if let module {
                HomeModuleIconView(icon: module.icon, size: 32)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.cta)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.session.origin.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if attempts > 0 {
                    // **Block 3.6 (2026-05-03)** — Korrekt-Quote pro
                    // Modul auf 14 pt + bold (vorher 12 pt medium).
                    // Lesbarkeit-Bump damit der wichtigste Stat-Punkt
                    // (Anzahl-Richtig) nicht im Subtitle-Slot
                    // verschwindet.
                    Text("\(outcome.session.correctCount) von \(attempts) richtig")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.Colors.success)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
    }

    /// Generische Aggregate-Stat-Card (Total-Quote / Streak / Tickets /
    /// Level-Up). `isHero` sorgt für stärkere Akzent-Tönung.
    /// **Block 3.6 (2026-05-03)** — Title-Font 16/14 → 20/16 pt für
    /// alle Aggregate-Cards. Hero-Cards (Total-Quote, Level-Up) sind
    /// damit ~20 pt black, normale Cards (Streak/Tickets) ~16 pt.
    /// User-Spec „bisschen dicker und größer" — Korrekt-Quote +
    /// Tickets sollen aus dem Card-Whitespace klar heraustreten.
    private func aggregateStatRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String?,
        isHero: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: isHero ? 26 : 22, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: isHero ? 20 : 16, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(iconColor.opacity(isHero ? 0.14 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(iconColor.opacity(isHero ? 0.32 : 0.15), lineWidth: 1)
        )
    }

    /// Mappt `LearningSession.Origin` auf das passende `HomeHeroModule`
    /// für Icon-Rendering. `training` und `speedRound` haben keinen
    /// klaren 1:1-Mapper — wir nehmen ein Default-Vokabeln-Icon, weil
    /// die Mehrheit der Training-Origins aus dem Vokabeln-Mode kommt
    /// (Nomen/Articles/Verben sind alle `.training`).
    private func homeHeroModule(for origin: LearningSession.Origin) -> HomeHeroModule? {
        switch origin {
        case .flashcards: return .karteikarten
        case .quiz:       return .quiz
        case .training:   return .vokabeln
        case .speedRound: return .vokabeln
        case .verbforms:  return .verbformen
        case .accents:    return .akzente
        case .wordRunner: return nil
        }
    }

    // MARK: - Block E — CTAs

    private var ctaBlock: some View {
        VStack(spacing: 10) {
            Button {
                onPlayAgain()
            } label: {
                Text("Noch eine Runde")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            // Pulse-Pattern wie Block 2 (CTA-Pulse auf Done-Card).
            .pulsing(active: ctaVisible, glowColor: AppTheme.Colors.cta)

            Button {
                onGoHome()
            } label: {
                Text("Zur Startseite")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
            }
            .buttonStyle(
                AppSecondaryButtonStyle(
                    tint: AppTheme.Colors.cta,
                    foreground: AppTheme.Colors.textPrimary
                )
            )
        }
        .opacity(ctaVisible ? 1 : 0)
        .offset(y: ctaVisible ? 0 : 8)
        .allowsHitTesting(ctaVisible)
        .padding(.top, 8)
    }

    // MARK: - Celebration Trigger

    private func triggerCelebration() {
        guard !hasAppeared else { return }
        hasAppeared = true

        // Konfetti starten — fester Startpunkt, damit das TimelineView
        // einen Anchor hat.
        confettiStartDate = Date()
        showConfetti = true

        // Sound + Haptik einmalig.
        feedbackPlayer.playLevelUp()
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)

        // CTA mit kleinem Delay einblenden — gleicher Pattern wie
        // SessionSummaryView (User soll erst die Belohnung wahrnehmen).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.35)) {
                ctaVisible = true
            }
        }

        // Konfetti automatisch nach 2.5 s deaktivieren — hält das
        // TimelineView nicht endlos aktiv.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            showConfetti = false
        }
    }
}

// MARK: - ConfettiBurst (extracted)
// `ConfettiBurst` lebt in `ConfettiBurst.swift` (Block 5, 2026-05-03).
// Wird hier mit Default-Density 60 + Lifetime 2.5 s verwendet.
