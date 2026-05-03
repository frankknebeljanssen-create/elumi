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

    /// Aktuelle Lernrichtung der Session. Gelesen direkt aus dem globalen
    /// `appDirectionKey`-State — es gibt keine session-lokale Richtung
    /// (siehe System-Regel „ein zentraler Switch"). Dadurch kann sich
    /// `SessionResult`/`SessionRewardOutcome` den zusätzlichen Direction-
    /// Parameter sparen und bleibt nicht-redundant.
    @AppStorage(appDirectionKey) private var selectedDirectionRaw = Direction.frenchToGerman.rawValue

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

    /// **Block 2 (2026-05-02)** — User-Spec: im Chain-Modus soll der
    /// Primary-CTA „Weiter zu …" / „Training abschließen" pulsieren,
    /// um den User zum Weiter-Tap zu führen. Default `false` für
    /// Non-Chain-Sessions (Home-Tile-Pfad). Caller setzt typisch
    /// `primaryCTAPulses: launchContext?.chainContext != nil`.
    /// Pulse-Defaults aus `PulsingModifier` (1.7 Hz, peak-glow 32 pt,
    /// scale 1.05) — konsistent zu allen anderen App-Pulsen
    /// (Setup-Modal-Cards, Slot-„Maschine starten", Pre-Screen-CTA).
    var primaryCTAPulses: Bool = false

    /// **Block 3.5 (2026-05-03)** — User-Spec: im Chain-Mode-Mid-Step
    /// (nach Step 1, Step 2 — NICHT am Final-Chain-End, der hat seine
    /// eigene `TrainingChainCompleteSummaryView`) soll die Done-Card
    /// drastisch vereinfacht sein. Nur Korrekt-Quote (groß + fett) +
    /// Praise + Primary-CTA. XP, Combos, Richtung, Level, Streak,
    /// Tickets sind raus, weil die Chain-Aggregation am Ende
    /// passiert — pro-Modul-Detail zwischen Steps lenkt vom Pacing ab.
    /// Out-of-Chain (Home → Modul direkt) bleibt mit allen Stats wie
    /// heute (Default `false`).
    var hidesDetailedStats: Bool = false

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

    /// CTA erscheint erst, wenn die Reward-Animationen durchgelaufen sind.
    /// Verhindert den Reflex-Tap „Weiter" direkt nach Session-Ende —
    /// siehe `FeedbackTiming.ctaRevealDelay`.
    @State private var ctaVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Reihenfolge (Phase 9.1 Spec):
            //   1. Ergebnis  2. XP  3. Richtung (NEU)
            //   4. Progress  5. Rewards  6. CTA
            //
            // Direction steht direkt unter XP und vor Progress — dadurch
            // bekommt der User zuerst die Belohnung, dann den Kontext
            // („was hab ich gerade gelernt?"), dann Progress + Rewards.
            //
            // **Block 3.5 (2026-05-03)** — `hidesDetailedStats`-Branch
            // für Chain-Mode-Mid-Step: alles zwischen Header und
            // CTA-Footer ist verborgen, der `header`-Block bekommt
            // einen vergrößerten Korrekt-Quote-Text (siehe
            // `header`-Subview-Doc). Final-Chain-End nutzt eine
            // dedizierte View (`TrainingChainCompleteSummaryView`),
            // ist also nicht von dieser Vereinfachung betroffen.
            header

            if !hidesDetailedStats {
                xpBreakdown

                directionRow

                divider
                levelProgress

                if hasRewards {
                    divider
                    rewardHighlights
                }
            }

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

            // CTA erscheint als Letztes — erst nachdem der User die
            // Belohnung wahrgenommen hat. Timing zentral in `FeedbackTiming`.
            //
            // **Block A.1 (2026-05-03)** — Im Chain-Mode-Mid-Step
            // (`hidesDetailedStats == true`) wird der CTA-Reveal-Delay
            // auf 0 gesetzt: User sieht „X von Y richtig" + Praise +
            // CTA simultan in einem Render-Pass. Der vorherige Delay
            // war an die XP-Hochzähl-/Reward-Animationen gekoppelt
            // (User sollte die Belohnung wahrnehmen bevor er weiter-
            // tappt) — im simplified Mid-Step-Modus gibt's diese
            // Animationen aber nicht, der Delay erzeugt einen
            // gefühlten „toten" Moment vor dem CTA-Erscheinen. Out-
            // of-Chain (Done-Card mit allen Stats) bleibt der Delay
            // wie bisher.
            let ctaDelay: Double = hidesDetailedStats ? 0 : FeedbackTiming.ctaRevealDelay
            withAnimation(
                .easeOut(duration: FeedbackTiming.ctaRevealDuration)
                .delay(ctaDelay)
            ) {
                ctaVisible = true
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

            // Ergebnis-Headline (Phase 3.5):
            //   1. Explizit via `resultHeadline`-Parameter (Call-Site-Override)
            //   2. Fallback: `outcome.session.resultHeadline` — modul-spezifisch,
            //      zentral in `LearningSession` gepflegt, damit jede Summary
            //      automatisch Spec-konform ist ohne Call-Site-Boilerplate.
            //
            // Analog für das Rating:
            //   1. Explizit via `performanceRating`
            //   2. `outcome.session.accuracyRating` (Sehr stark / Stark / …)
            //   3. `isFlawless` → „Fehlerfrei!" (Success-Ton, emotional stärker)
            let effectiveHeadline = resultHeadline ?? outcome.session.resultHeadline
            let effectiveRating = performanceRating ?? outcome.session.accuracyRating
            // **Block 3.5 (2026-05-03)** — Im Chain-Mid-Step ist der
            // Korrekt-Quote-Text das einzige große Stat-Element auf
            // der Card (XP/Streak/etc. sind verborgen). Damit's
            // visuell nicht im Card-Whitespace verloren wirkt, kommt
            // der Headline-Font dort von 22 → 32 pt hoch. Out-of-
            // Chain (regulärer Done-Screen mit allen Stats) bleibt
            // 22 pt — sonst dominiert die Headline die anderen
            // Sektionen zu stark.
            let headlineFontSize: CGFloat = hidesDetailedStats ? 32 : 22
            HStack(spacing: 8) {
                Text(effectiveHeadline)
                    .font(.system(size: headlineFontSize, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let effectiveRating {
                    performanceBadge(text: effectiveRating, tint: AppTheme.Colors.cta)
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

    // MARK: - Direction Row (Phase 9.1)
    //
    // Rein informative, kompakte Zeile — keine Interaktion. Spiegelt die
    // globale Lernrichtung in der gleichen Bildsprache wie Home /
    // Session-Setup (StraightFlagBadge + Pfeil).

    private var sessionDirection: Direction {
        Direction(rawValue: selectedDirectionRaw) ?? .frenchToGerman
    }

    private var directionRow: some View {
        let isFrToDE = sessionDirection == .frenchToGerman
        // Bei einem Level-Up wird die Richtung einen Ticken stärker
        // eingefärbt, damit der „Ich habe gerade in dieser Richtung ein
        // Level erreicht"-Moment sichtbar bleibt — ohne den
        // Haupt-Reward-Chip zu verdrängen.
        let highlight = outcome.leveledUp
        return HStack(spacing: 8) {
            setupCardLabel("RICHTUNG")

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                StraightFlagBadge(
                    countryCode: isFrToDE ? "FR" : "DE",
                    width: 26,
                    height: 17,
                    labelFontSize: 8
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                StraightFlagBadge(
                    countryCode: isFrToDE ? "DE" : "FR",
                    width: 26,
                    height: 17,
                    labelFontSize: 8
                )
            }
            .padding(.horizontal, highlight ? 8 : 4)
            .padding(.vertical, highlight ? 5 : 2)
            .background(
                Capsule()
                    .fill(AppTheme.Colors.cta.opacity(highlight ? 0.14 : 0))
            )
            .overlay(
                Capsule()
                    .stroke(
                        AppTheme.Colors.cta.opacity(highlight ? 0.28 : 0),
                        lineWidth: 1
                    )
            )
            .animation(.easeOut(duration: 0.2), value: highlight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isFrToDE
                ? "Lernrichtung: Französisch nach Deutsch."
                : "Lernrichtung: Deutsch nach Französisch."
        )
    }

    /// True, wenn mindestens **ein** Reward-Chip gezeigt würde — sonst
    /// sparen wir uns den Divider + die leere Section.
    ///
    /// `showsStreakActive` deckt den Spec-Fall „Streak bleibt aktiv" ab
    /// (Session OHNE Streak-Steigerung, aber laufende Streak vorhanden):
    /// der User soll sehen, dass seine Kette heute schon gesichert ist,
    /// auch wenn diese konkrete Session den Counter nicht mehr bewegt.
    private var hasRewards: Bool {
        outcome.totalCredits > 0
            || outcome.leveledUp
            || outcome.streakIncreasedToday
            || outcome.dailyBonusXP > 0
            || outcome.variableReward.hasBonus
            || showsStreakActive
    }

    /// „Streak bleibt aktiv"-Signal: nur wenn diese Session die Streak
    /// nicht hochgesetzt hat (etwa weil die Tagesaufgabe heute bereits
    /// erfüllt war), aber noch eine laufende Kette existiert. Ein laufender
    /// Milestone-Chip würde bereits die Aufmerksamkeit binden — dann
    /// sparen wir uns den Zusatz.
    private var showsStreakActive: Bool {
        !outcome.streakIncreasedToday
            && progress.currentStreak > 0
            && outcome.creditsFromStreakMilestone == 0
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
                // Level-Up-Chip nutzt den **Level-Namen** aus
                // `LevelProgression` (User-Spec: Bedeutung statt Zahl).
                // „Entdecker erreicht" statt „Level 3 erreicht" —
                // emotional stärker, ohne das System zu verändern.
                // Credit-Reward als „+N Spiele", konsistent zum
                // Footer-Badge + GameHub-Hero.
                rewardChip(
                    icon: "arrow.up.circle.fill",
                    title: "\(LevelProgression.name(forLevel: outcome.newLevel)) erreicht",
                    subtitle: "+\(Self.gamesWording(outcome.creditsFromLevelUp))",
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
                        ? "+\(Self.gamesWording(outcome.creditsFromStreakMilestone)) · Meilenstein!"
                        : "weiter so",
                    color: Color(hex: "#FF9F40"),
                    isHero: outcome.creditsFromStreakMilestone > 0 && !outcome.leveledUp,
                    animationDelay: FeedbackTiming.rewardChipStagger[2]
                )
            } else if showsStreakActive {
                // „Streak bleibt aktiv" — Anti-Verlustmoment: die Kette ist
                // heute bereits gesichert, die Session ist ein Zusatz. Dezent
                // gefärbt (nicht hero), damit der Chip die Wahrnehmung nicht
                // stiehlt, aber den User in der Gewohnheit bestärkt.
                rewardChip(
                    icon: "flame",
                    title: "\(progress.currentStreak) Tage Streak aktiv",
                    subtitle: "Heute bereits gesichert",
                    color: Color(hex: "#FF9F40"),
                    isHero: false,
                    animationDelay: FeedbackTiming.rewardChipStagger[2]
                )
            }
            if outcome.creditsFromXP > 0 {
                // Gleiches Wortschatz-Mapping wie beim Level-Up-Chip:
                // „Credits" → „Spiele" (Singular/Plural), Icon auf
                // Gamecontroller, damit Footer/Game-Hub/Session-End
                // dasselbe visuelle Vokabular sprechen.
                rewardChip(
                    icon: "gamecontroller.fill",
                    title: "+\(Self.gamesWording(outcome.creditsFromXP))",
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
    /// Spiele in einem lesbaren Satz zusammen.
    private var dailyChallengeRewardSubtitle: String {
        let xpPart = "+\(outcome.dailyBonusXP) XP"
        if outcome.creditsFromDailyChallenge > 0 {
            return "\(xpPart) · +\(Self.gamesWording(outcome.creditsFromDailyChallenge))"
        }
        return xpPart
    }

    /// User-facing Wortschatz „Credit" → „Spiel" (Single Source of Truth
    /// für Session-End, Footer-Badge, GameHub-Hero). `arcadeCredits` und
    /// `creditsFromXP` bleiben technisch „Credits" (DB-Schicht), aber in
    /// der Anzeige nennen wir sie konsistent „Spiel/Spiele", damit Footer-
    /// Icon (Gamepad), Game-Hub-Titel und Session-End-Chip dieselbe
    /// Sprache sprechen. Nutzt die Tatsache, dass
    /// `ArcadeCreditSystem.gamesCost == 1` → 1 Credit = 1 Spiel.
    static func gamesWording(_ count: Int) -> String {
        count == 1 ? "1 Spiel" : "\(count) Spiele"
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
        // Hülle, die Opacity + Offset + Tap-Sperre bündelt — solange
        // `ctaVisible == false` ist der Footer unsichtbar UND nicht
        // antippbar. Das verhindert, dass ein flinker User die
        // Reward-Animation wegklickt, bevor sie gelaufen ist.
        Group {
            if let primary = onPrimaryCTA {
                VStack(spacing: 8) {
                    Button(action: primary) {
                        Text(primaryCTALabel ?? "Weiter lernen")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                    // **Block 2 (2026-05-02)** — Chain-Mode-Pulse
                    // auf den Primary-CTA. `ctaVisible`-Gate
                    // verhindert, dass der Pulse während der
                    // Reveal-Verzögerung (CTA noch unsichtbar)
                    // unnötig läuft — siehe `ctaRevealDelay`-
                    // Animation im `.onAppear` oben. Secondary-CTA
                    // bleibt absichtlich ohne Pulse (User-Spec
                    // „nur Primary").
                    .pulsing(
                        active: primaryCTAPulses && ctaVisible,
                        glowColor: AppTheme.Colors.cta
                    )

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
        .opacity(ctaVisible ? 1 : 0)
        .offset(y: ctaVisible ? 0 : 8)
        .allowsHitTesting(ctaVisible)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.Colors.setupCardBorder)
            .frame(height: 1)
    }
}
