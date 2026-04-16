import SwiftUI

/// Wiederverwendbare Session-Summary-Card. Wird am Ende jeder Lernsession
/// (Karteikarten, Quiz, Training, Speed Round, Verbformen) angezeigt und
/// fasst die Belohnungen zusammen.
///
/// **Phase 3.5 — Session End Engine:**
/// Die Card ist nun das eigentliche „Belohnungs-Moment" nach jeder Session.
/// Sie liefert:
///   • optionale Ergebnis-Überschrift (z. B. „8 von 10 richtig")
///   • optionales Performance-Badge (z. B. „Stark" / „Sehr gut")
///   • animierten XP-Hochzähler (Count-Up)
///   • animierte Level-Progress-Bar
///   • primäre & sekundäre CTAs (z. B. „Weiter lernen" / „Spiel starten")
///
/// Alle neuen Parameter sind optional — bestehende Call-Sites bleiben ohne
/// Änderung kompatibel und nutzen die alten Defaults.
///
/// Designziel (siehe Auftrag): hochwertig, ruhig, Elumi-konsistent —
/// keine Arcade-Optik. Nutzt die bestehenden Setup-Card-Tokens und
/// das `cardLabel`-Pattern, sodass die Summary visuell nahtlos in den
/// Rest der App passt.
struct SessionSummaryView: View {
    let outcome: SessionRewardOutcome
    let progress: UserProgress
    /// Legacy: einzelner „Weiter"-Button. Wird verdrängt, sobald
    /// `onPrimaryCTA`/`onSecondaryCTA` gesetzt sind.
    var onContinue: (() -> Void)? = nil

    // MARK: - Phase 3.5 optionale Parameter

    /// Ergebnis-Überschrift oben — z. B. „8 von 10 richtig".
    /// Wenn nil, fällt der Header auf den bisherigen „Session geschafft".
    var resultHeadline: String? = nil

    /// Kurz-Bewertung rechts neben dem Headline — z. B. „Stark", „Sehr gut".
    /// Nur in Kombination mit `resultHeadline` sinnvoll.
    var performanceRating: String? = nil

    /// Primär-CTA: der Hauptimpuls „Weiter lernen". Wenn gesetzt, wird
    /// `onContinue` ignoriert.
    var primaryCTALabel: String? = nil
    var onPrimaryCTA: (() -> Void)? = nil

    /// Sekundär-CTA: z. B. „Spiel starten" / „Nochmal". Optional.
    var secondaryCTALabel: String? = nil
    var onSecondaryCTA: (() -> Void)? = nil

    /// Steuert die gestaffelten Einblend-Animationen der Reward-Chips beim
    /// ersten Erscheinen. So wirkt die Summary nicht statisch, sondern
    /// feiert dezent — ohne Arcade-Optik.
    @State private var animateRewards = false
    @State private var highlightPulse = false

    /// Phase 3.5: für den animierten XP-Hochzähler im Hero. Startet bei 0
    /// und rampt auf `outcome.totalXP` hoch.
    @State private var displayedTotalXP: Int = 0

    /// Phase 3.5: für die animierte Progress-Bar. Startet bei 0 und
    /// rampt auf den tatsächlichen `progress.levelProgress`-Wert.
    @State private var animatedLevelProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            xpBreakdown

            if outcome.totalCredits > 0 || outcome.leveledUp || outcome.streakIncreasedToday || outcome.dailyBonusXP > 0 || outcome.variableReward.hasBonus {
                divider
                rewardHighlights
            }

            divider
            levelProgress

            ctaFooter
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
        .onAppear {
            // Gestaffelte Einblendung — klare Reihenfolge: erst Reward-Chips,
            // dann Pulse auf das wichtigste Ereignis (Level-Up > Streak > XP).
            // Timings zentral aus `FeedbackTiming`.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.18)) {
                animateRewards = true
            }
            if outcome.leveledUp || outcome.creditsFromStreakMilestone > 0 {
                withAnimation(
                    .easeInOut(duration: FeedbackTiming.heroPulseDuration)
                    .repeatCount(2, autoreverses: true)
                    .delay(FeedbackTiming.heroPulseDelay)
                ) {
                    highlightPulse = true
                }
            }

            // Phase 3.5: Progress-Bar animiert auf den Endwert rampen.
            withAnimation(.easeOut(duration: FeedbackTiming.progressBarDuration)
                .delay(FeedbackTiming.progressBarAnimationDelay)) {
                animatedLevelProgress = progress.levelProgress
            }
        }
        // Phase 3.5: XP-Hochzähler — Timer-basiert auf `totalXP` hochrampen.
        // Kleine Sessions (≤ 10 XP) überspringen den Ramp, sonst wirkt's
        // künstlich. Dauer aus `FeedbackTiming.xpCountUpDuration`.
        .task(id: outcome.totalXP) {
            let target = outcome.totalXP
            guard target > 10 else {
                displayedTotalXP = target
                return
            }
            displayedTotalXP = 0
            let steps = min(28, target)
            guard steps > 0 else { return }
            let tick = UInt64((FeedbackTiming.xpCountUpDuration / Double(steps)) * 1_000_000_000)
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: tick)
                await MainActor.run {
                    displayedTotalXP = min(target, Int(round(Double(target) * Double(i) / Double(steps))))
                }
            }
            await MainActor.run { displayedTotalXP = target }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            setupCardLabel(outcome.session.origin.displayName)

            // Ergebnis-Headline (Phase 3.5): wenn vom Modul übergeben,
            // zeigt sie die modul-spezifische Ergebnis-Kurzform, z. B.
            // „8 von 10 richtig". Fallback bleibt „Session geschafft".
            HStack(spacing: 8) {
                Text(resultHeadline ?? "Session geschafft")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let performanceRating {
                    performanceBadge(text: performanceRating, tint: AppTheme.Colors.cta)
                } else if outcome.session.isFlawless {
                    performanceBadge(text: "Fehlerfrei!", tint: AppTheme.Colors.success)
                }
            }
        }
    }

    /// Kleines Badge neben der Headline — Performance-Rating oder „Fehlerfrei".
    @ViewBuilder
    private func performanceBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.15)))
    }

    private var xpBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            // XP-Hero: größer, dominanter, mit Count-Up-Animation.
            // `displayedTotalXP` rampt von 0 auf `outcome.totalXP` hoch;
            // `.contentTransition(.numericText())` sorgt für sanften Morph
            // zwischen Zwischenständen, damit der Zähler flüssig wirkt.
            HStack(alignment: .firstTextBaseline) {
                Text("XP")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(AppTheme.Colors.cardLabel)
                Spacer()
                Text("+\(displayedTotalXP)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.cta)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            // Aufschlüsselung — nur Posten zeigen, die > 0 sind
            VStack(alignment: .leading, spacing: 2) {
                xpRow("Richtige Antworten", outcome.baseXP)
                xpRow("Combos", outcome.comboXP)
                xpRow("Gemeisterte Karten", outcome.masteryXP)
                xpRow("Fehlerfrei", outcome.flawlessXP)
                xpRow("Tagesaufgabe", outcome.dailyBonusXP)
            }
        }
    }

    @ViewBuilder
    private func xpRow(_ label: String, _ value: Int) -> some View {
        if value > 0 {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                Spacer()
                Text("+\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
        }
    }

    private var rewardHighlights: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tages-Aufgabe zuerst — ab Phase 5 wird der „Tages-Bonus" hier
            // ausgelöst, wenn die Tagesaufgabe fertig ist. Subtitle trägt
            // XP + Credit sichtbar zusammen, damit der Reward in einem
            // Satz erfahrbar ist.
            if outcome.dailyBonusXP > 0 {
                rewardChip(
                    icon: "sparkles",
                    title: "Tagesaufgabe erledigt",
                    subtitle: dailyChallengeRewardSubtitle,
                    color: AppTheme.Colors.cta,
                    isHero: !outcome.leveledUp,
                    animationDelay: FeedbackTiming.rewardChipStagger[0]
                )
            }
            if outcome.leveledUp {
                rewardChip(
                    icon: "arrow.up.circle.fill",
                    title: "Level \(outcome.newLevel) erreicht",
                    subtitle: "+\(outcome.creditsFromLevelUp) Credits",
                    color: AppTheme.Colors.cta,
                    isHero: true,
                    animationDelay: FeedbackTiming.rewardChipStagger[1]
                )
            }
            if outcome.streakIncreasedToday {
                rewardChip(
                    icon: "flame.fill",
                    title: "\(outcome.newStreak) Tage Streak",
                    subtitle: outcome.creditsFromStreakMilestone > 0
                        ? "+\(outcome.creditsFromStreakMilestone) Credits · Meilenstein!"
                        : "weiter so",
                    color: Color(hex: "#FF9F40"),
                    isHero: outcome.creditsFromStreakMilestone > 0 && !outcome.leveledUp,
                    animationDelay: FeedbackTiming.rewardChipStagger[2]
                )
            }
            if outcome.creditsFromXP > 0 {
                rewardChip(
                    icon: "circle.hexagongrid.fill",
                    title: "+\(outcome.creditsFromXP) Credits",
                    subtitle: "aus XP-Meilensteinen",
                    color: AppTheme.Colors.elumiBlue,
                    isHero: false,
                    animationDelay: FeedbackTiming.rewardChipStagger[3]
                )
            }

            // Phase 7: Variable-Reward-Chip — seltenes Glücksmoment.
            // Erscheint leicht nach den festen Rewards, damit er sich wie
            // ein separater „Glücksmoment" anfühlt, nicht wie ein weiterer
            // Standard-Chip.
            if let variableText = outcome.variableReward.summaryText {
                rewardChip(
                    icon: outcome.variableReward.bonusCredit > 0
                        ? "sparkle"
                        : "star.fill",
                    title: outcome.variableReward.headline,
                    subtitle: variableText,
                    color: AppTheme.Colors.warning,
                    // Hero, wenn der Glückstreffer die spektakulärste Sache
                    // in dieser Session ist (z. B. kein Level-Up, kein
                    // Streak-Milestone).
                    isHero: !outcome.leveledUp && outcome.creditsFromStreakMilestone == 0,
                    animationDelay: FeedbackTiming.rewardChipStagger[3]
                        + FeedbackTiming.variableRewardExtraDelay
                )
            }
        }
    }

    /// Untertitel für den „Tagesaufgabe erledigt"-Chip. Faltet XP + ggf.
    /// Credit in einem lesbaren Satz zusammen.
    private var dailyChallengeRewardSubtitle: String {
        let xpPart = "+\(outcome.dailyBonusXP) XP"
        if outcome.creditsFromDailyChallenge > 0 {
            let creditWord = outcome.creditsFromDailyChallenge == 1 ? "Credit" : "Credits"
            return "\(xpPart) · +\(outcome.creditsFromDailyChallenge) \(creditWord)"
        }
        return xpPart
    }

    /// Reward-Chip — kompakte Zeile; bei `isHero` größer (stärkere Hintergrund-
    /// Tönung, Puls-Effekt), dazu gestaffelte Einblendung via `animationDelay`.
    private func rewardChip(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        isHero: Bool,
        animationDelay: Double
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: isHero ? 22 : 18, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: isHero ? 15 : 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiBlue)
            }
            Spacer()
        }
        .padding(.horizontal, isHero ? 12 : 4)
        .padding(.vertical, isHero ? 10 : 2)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(isHero ? 0.14 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(isHero ? 0.28 : 0), lineWidth: 1)
        )
        .scaleEffect(animateRewards ? (isHero && highlightPulse ? 1.03 : 1.0) : 0.88)
        .opacity(animateRewards ? 1 : 0)
        .animation(
            .spring(response: 0.45, dampingFraction: 0.78).delay(animationDelay),
            value: animateRewards
        )
    }

    private var levelProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Level \(progress.level)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                let nextLevelXP = GamificationConfig.levelEndXP(for: progress.level)
                Text("\(progress.totalXP) / \(nextLevelXP) XP")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiBlue)
            }
            // Progress-Bar animiert auf `animatedLevelProgress` hoch (siehe
            // `.onAppear`) — so sieht der User, dass er *gerade* Fortschritt
            // gemacht hat, nicht nur den aktuellen Stand.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                    Capsule()
                        .fill(AppTheme.Colors.cta)
                        .frame(width: max(0, geo.size.width * animatedLevelProgress))
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            // Phase 3.5: „Noch X XP bis …" als Richtungs-Hinweis unter der
            // Bar. Zeigt das nächste Named-Tier (Champion etc.), matcht die
            // Sprache aus Progress Hub und Home Board.
            if let tagline = nextMilestoneTagline {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text(tagline)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
        }
    }

    /// „Noch X XP bis <Tier>" unter der Progress-Bar. Nutzt die gleiche
    /// Elumi-Tier-Logik wie der Progress Hub, damit der Fortschritt für
    /// den User konsistent lesbar bleibt.
    private var nextMilestoneTagline: String? {
        guard let next = nextElumiLevelTier(for: progress.totalXP) else {
            return nil
        }
        let remaining = max(0, next.threshold - progress.totalXP)
        guard remaining > 0 else { return nil }
        return "Noch \(remaining) XP bis \(next.title)"
    }

    // MARK: - CTA Footer (Phase 3.5)
    //
    // Regel: wenn ein `onPrimaryCTA` gesetzt ist, rendern wir den neuen
    // Primary+Secondary-Pattern. Ist nur `onContinue` gesetzt, bleibt das
    // alte Verhalten („Weiter"-Button) unverändert — Modul-Call-Sites
    // müssen nicht angefasst werden.

    @ViewBuilder
    private var ctaFooter: some View {
        if let primary = onPrimaryCTA {
            VStack(spacing: 8) {
                Button(action: primary) {
                    Text(primaryCTALabel ?? "Weiter lernen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

                if let secondary = onSecondaryCTA, let label = secondaryCTALabel {
                    Button(action: secondary) {
                        Text(label)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.cta))
                }
            }
            .padding(.top, 4)
        } else if let onContinue {
            Button(action: onContinue) {
                Text("Weiter")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .padding(.top, 4)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.Colors.setupCardBorder)
            .frame(height: 1)
    }
}
