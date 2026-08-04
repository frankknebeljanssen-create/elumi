import SwiftUI

/// **Pokal / „Dein Fortschritt"** — zentraler Motivations- und
/// Fortschritts-Bereich (Rebuild).
///
/// Fünf Sections in einer ruhigen vertikalen Liste, jede in einer
/// standardisierten Setup-Card (`appSetupCardBackground`):
///
///   1. Hero Progress — Level + Fortschrittsbalken + XP bis nächstes Level
///   2. Streak        — 🔥 X Tage
///   3. Lernstatus    — gelernt · trainiert · gesamt
///   4. Achievements  — Milestone-Badges (aus bestehenden Daten abgeleitet)
///   5. Spiele        — Word-Runner-Freischaltung / „Jetzt spielen"
///
/// (Eine frühere 6. Credits-Card ist entfallen — der Credit-Count
/// lebt prominent im Game-Hub, eine doppelte Anzeige hier war
/// redundant.)
///
/// Header: zentrales `AppTopBar` mit Back-Button + Screen-Titel
/// („Dein Fortschritt"). Kein Custom-Chrome. Horizontales Inset über
/// `AppLayout.screenPadding` — Cards sind **nicht** randlos.
///
/// **Keine neue Logik**: die Sections lesen ausschließlich bestehende
/// Stores (`ItemLearningStatusStore`, `@AppStorage`-Werte) und
/// bestehende Helper (`GamificationConfig`, `LevelProgression`).
struct TrophyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let navigate: (AppScreen) -> Void

    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0
    @AppStorage(appElumiXPKey) private var collectedXP = 0

    @ObservedObject private var itemLearningStatusStore = ItemLearningStatusStore.shared

    private let sectionStyle: AppSectionStyle = .home

    /// XP-Schwelle, ab der Word Runner freigeschaltet ist. Display-seitige
    /// Motivation — das eigentliche Game im Game-Tab läuft unabhängig.
    private static let wordRunnerUnlockXP: Int = 100

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // VStack-Spacing `.md` → `.sm` (User-Spec „padding zwischen
            // allen minimal kleiner"). Zusammen mit den reduzierten
            // vertical-paddings pro Card wirkt der Screen spürbar
            // ruhiger und alle Sektionen passen komfortabler rein.
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                // **Einheitlicher Modul-Header** (User-Spec): Back-
                // Chevron oben + farbige `ModuleHeaderCard` mit Pokal-
                // SF-Symbol als Platzhalter-Icon. Analog zum Spielen-
                // Screen und allen anderen Modulen.
                ModuleHeaderCard(
                    systemImage: "trophy.fill",
                    title: "Fortschritt",
                    accent: sectionStyle.accent,
                    onBack: { dismiss() }
                )
                heroProgressCard
                streakCard
                lernstatusCard
                achievementsCard
                // Word-Runner-Start-Card entfernt — das Spiel sitzt
                // jetzt zentral im Spielen-Screen (GameHub), Doppel-
                // Einstieg auf Fortschritt war redundant.
            }
            .padding(.horizontal, AppLayout.screenPadding)
            // **Chevron-Y-Sweep 2026-05-07** — Auf
            // `headerChevronTopPadding` (= 0) umgezogen, damit der
            // Pokal-Chevron auf TrainingHub-Höhe sitzt — gemeinsam mit
            // Wörterbuch, Spielen, Setup-Screens. `screenHeaderTopPadding`
            // (= 4 pt) ist jetzt rein für Content-Spacing reserviert.
            .padding(.top, AppLayout.headerChevronTopPadding)
            // **2026-05-08 Padding-Cleanup nach safeAreaInset-Migration** —
            // Bottom-Padding `Spacing.xxl` (32) → `Spacing.md` (16).
            // Footer ist über safeAreaInset reserviert; 32 pt waren
            // nun Doppel-Padding und schoben den Content sichtbar hoch.
            .padding(.bottom, AppTheme.Spacing.md)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .dismissKeyboardOnTap()
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
                onSettings: openSettings,
                isTrophyActive: true
            )
        }
        // **Erstnutzer-Hint (2026-06-09)** — am Screen-Root eingehängt,
        // damit der Dim-Scrim den ganzen Screen abdeckt.
        .hintBubble(
            id: "progress_intro",
            // Ein Satz pro Zeile (User-Spec Lesbarkeit für Kinder).
            text: """
            Jedes Wort, das du übst, bringt dir Punkte — und mir was zu futtern. 😋
            Üb lieber jeden Tag ein bisschen, als alles auf einmal.
            So wächst deine Serie und du merkst dir mehr.
            """
        )
    }

    // MARK: - Section 1: Hero Progress (Level + Progressbar + XP-Ziel)

    private var heroProgressCard: some View {
        let level = GamificationConfig.level(forXP: collectedXP)
        let progress = GamificationConfig.progressTowardNextLevel(totalXP: collectedXP)
        let levelEnd = GamificationConfig.levelEndXP(for: level)
        let remaining = max(0, levelEnd - collectedXP)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                levelBadge(level: level)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dein Fortschritt")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.1)
                    Text("Level \(level)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                Spacer(minLength: 0)
            }

            progressBar(progress: progress)

            Text(remaining > 0
                 ? "Noch \(remaining) XP bis Level \(level + 1)"
                 : "Maximum erreicht — weiter so!")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    private func levelBadge(level: Int) -> some View {
        ZStack {
            Circle()
                .fill(sectionStyle.accent.opacity(0.22))
                .frame(width: 54, height: 54)
            Circle()
                .stroke(sectionStyle.accent.opacity(0.45), lineWidth: 1.5)
                .frame(width: 54, height: 54)
            Text("\(level)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(sectionStyle.accent)
                .monospacedDigit()
        }
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                sectionStyle.accent,
                                sectionStyle.accent.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geo.size.width * min(1.0, max(0.0, progress))))
            }
        }
        .frame(height: 10)
    }

    // MARK: - Section 2: Streak

    private var streakCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FF9F40").opacity(0.18))
                    .frame(width: 40, height: 40)
                Text("🔥")
                    .font(.system(size: 20))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(currentStreak == 1 ? "1 Tag Streak" : "\(currentStreak) Tage Streak")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(streakSubline(for: currentStreak))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    private func streakSubline(for days: Int) -> String {
        switch days {
        case 0:       return "Starte heute deine Serie."
        case 1:       return "Ein guter Anfang — morgen weiter."
        case 2...6:   return "Bleib dran, das wird was."
        case 7...13:  return "Eine Woche — stark!"
        case 14...29: return "Zwei Wochen — beeindruckend."
        default:      return "Elite-Zone. Chapeau."
        }
    }

    // MARK: - Section 3: Lernstatus (gelernt · trainiert · gesamt)

    /// **2026-06-09** — Umbenannt von „Lernstatus" (User-Spec: klingt
    /// nach Systembegriff, nicht nach Aussage). Spalten ebenso: „Sitzt"
    /// / „Wackelt noch" / „Gesamt" statt „Geschafft" / „In Arbeit" /
    /// „Insgesamt" — sagen direkter, was sie zeigen.
    ///
    /// Struktur geändert: vorher war die GANZE Card ein Button (Tap
    /// überall → Lernstatus-Detail). Jetzt ist nur der Header tappbar,
    /// und bei `needsWork > 0` kommt eine eigene, hervorgehobene
    /// „Üben"-Zeile dazu — die Handlung, die am meisten bringt, muss
    /// auf dem Hauptscreen stehen, nicht erst eine Ebene tiefer.
    /// **2026-08-05** — Von drei auf zwei Spalten reduziert (User-Spec:
    /// „Gesamt" war redundant und die Zahlen nicht durchschaubar — zwei
    /// unterschiedliche „wackelt"-Werte auf derselben Card, einmal die
    /// Spalte oben (alle Nicht-Stark, hier „trained"), einmal der CTA-
    /// Text darunter (nur `needsWork`). Jetzt zeigt EINE Zahl denselben
    /// Bestand an beiden Stellen: die Spalte oben UND der CTA-Tap führen
    /// zum selben „Wackelkandidaten"-Pool. Labels konjugieren jetzt
    /// korrekt Singular/Plural („sitzt"/„sitzen", „wackelt"/„wackeln
    /// noch"), der CTA-Text wiederholt die Zahl nicht mehr (steht ja
    /// schon in der Spalte drüber), sondern heißt schlicht
    /// „Wackelkandidaten jetzt üben".
    private var lernstatusCard: some View {
        let strong = itemLearningStatusStore.strongItems.count
        let needsWork = itemLearningStatusStore.needsWorkItems.count
        let learning = itemLearningStatusStore.learningItems.count
        let sparse = itemLearningStatusStore.sparseItems.count
        let trained = needsWork + learning + sparse

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                navigate(.lernstatus)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Was du schon kannst")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                lernstatusColumn(
                    icon: "checkmark.seal.fill",
                    tint: Color(hex: "#4ADE80"),
                    label: strong == 1 ? "sitzt" : "sitzen",
                    value: strong
                )
                lernstatusDivider
                lernstatusColumn(
                    icon: "bolt.fill",
                    tint: Color(hex: "#F59E0B"),
                    label: trained == 1 ? "wackelt noch" : "wackeln noch",
                    value: trained
                )
            }

            // **Üben-CTA** — gezielt auf `needsWorkItems` (die Vokabeln
            // mit der niedrigsten Trefferquote), nicht auf die breitere
            // „Wackelt noch"-Summe oben. Das deckt sich mit der „Zum
            // Üben"-Sektion im Lernstatus-Detail, zu der dieser Button
            // führt — dieselbe Zahl, derselbe Bestand.
            if needsWork > 0 {
                Button {
                    navigate(.lernstatus)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "#F59E0B"))
                        Text("Wackelkandidaten jetzt üben")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Spacer(minLength: 0)
                        Text("Üben")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color(hex: "#F59E0B")))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#F59E0B").opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: "#F59E0B").opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(AppCardPressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    private func lernstatusColumn(icon: String, tint: Color, label: String, value: Int) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var lernstatusDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.border.opacity(0.5))
            .frame(width: 1, height: 34)
    }

    // MARK: - Section 4: Achievements

    private struct Achievement: Identifiable {
        let id: String
        let emoji: String
        let title: String
        let unlocked: Bool
        /// 0…1 — wie nah dran, unabhängig von `unlocked`. Bestimmt,
        /// welches gesperrte Abzeichen als „nächstes Ziel" gezeigt wird.
        let progress: Double
        /// Fortschritts-Satz für den gesperrten Zustand, z. B. „Noch 2
        /// Tage bis zur Wochenflamme". `nil`, wenn `progress` nicht
        /// sinnvoll in Worte zu fassen ist (z. B. „Erster Funke").
        let remainingText: String?
    }

    private var achievements: [Achievement] {
        let strong = itemLearningStatusStore.strongItems.count
        let level = GamificationConfig.level(forXP: collectedXP)
        let xpIntoLevel3 = collectedXP - GamificationConfig.levelStartXP(for: 3)
        let xpNeededForLevel3 = GamificationConfig.levelStartXP(for: 3) - GamificationConfig.levelStartXP(for: level)
        return [
            Achievement(
                id: "first-xp", emoji: "🌱", title: "Erster Funke",
                unlocked: collectedXP > 0,
                progress: collectedXP > 0 ? 1 : 0,
                remainingText: "Verdien deine ersten Punkte."
            ),
            Achievement(
                id: "streak-3", emoji: "⚡", title: "3-Tage-Streak",
                unlocked: currentStreak >= 3,
                progress: min(1, Double(currentStreak) / 3),
                remainingText: "Noch \(max(0, 3 - currentStreak)) \(3 - currentStreak == 1 ? "Tag" : "Tage") bis zur 3-Tage-Streak."
            ),
            Achievement(
                id: "streak-7", emoji: "🔥", title: "Wochenflamme",
                unlocked: currentStreak >= 7,
                progress: min(1, Double(currentStreak) / 7),
                remainingText: "Noch \(max(0, 7 - currentStreak)) \(7 - currentStreak == 1 ? "Tag" : "Tage") bis zur Wochenflamme."
            ),
            Achievement(
                id: "level-3", emoji: "⭐", title: "Level 3",
                unlocked: level >= 3,
                progress: level >= 3 ? 1 : min(1, Double(xpIntoLevel3 + xpNeededForLevel3) / Double(max(1, xpNeededForLevel3))),
                remainingText: "Noch \(max(0, GamificationConfig.levelStartXP(for: 3) - collectedXP)) XP bis Level 3."
            ),
            Achievement(
                id: "strong-20", emoji: "💎", title: "20 sichere Wörter",
                unlocked: strong >= 20,
                progress: min(1, Double(strong) / 20),
                remainingText: "Noch \(max(0, 20 - strong)) \(20 - strong == 1 ? "Wort" : "Wörter") bis zu 20 sicheren Wörtern."
            )
        ]
    }

    /// **2026-06-09** — Option A (User-Entscheidung): statt fünf grauer
    /// Symbole, von denen die meisten unerreicht wirken, steht hier NUR
    /// das nächste erreichbare Abzeichen groß — mit einem konkreten
    /// Nahziel statt fünf abstrakten Fernzielen. Ausgewählt wird das
    /// gesperrte Abzeichen mit dem höchsten Fortschritt, nicht das
    /// erste in der Liste — der User soll sehen, was er als Nächstes
    /// wirklich erreicht, nicht was zufällig zuerst kommt.
    private var nextAchievement: Achievement? {
        achievements.filter { !$0.unlocked }.max { $0.progress < $1.progress }
    }

    private var unlockedAchievementCount: Int {
        achievements.filter(\.unlocked).count
    }

    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                // **2026-06-09** — „Erfolge" → „Deine Abzeichen" (User-
                // Spec): wärmer, weniger nach Bewertungssystem.
                Text("Deine Abzeichen")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                Text("\(unlockedAchievementCount) / \(achievements.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }

            if let next = nextAchievement {
                nextAchievementHighlight(next)
            } else {
                // Alle fünf freigeschaltet — eigener Feier-Zustand statt
                // eines leeren „nichts mehr zu zeigen".
                HStack(spacing: 10) {
                    Text("🏆")
                        .font(.system(size: 26))
                    Text("Alle Abzeichen gesammelt — stark!")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    private func nextAchievementHighlight(_ achievement: Achievement) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(sectionStyle.accent.opacity(0.18))
                    .frame(width: 52, height: 52)
                Circle()
                    .stroke(sectionStyle.accent.opacity(0.4), lineWidth: 1)
                    .frame(width: 52, height: 52)
                Text(achievement.emoji)
                    .font(.system(size: 24))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(achievement.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if let remainingText = achievement.remainingText {
                    Text(remainingText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                        Capsule()
                            .fill(sectionStyle.accent)
                            .frame(width: geo.size.width * max(0.04, achievement.progress))
                    }
                }
                .frame(height: 6)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Section 5: Spiele / Word Runner

    private var wordRunnerCard: some View {
        let unlocked = collectedXP >= Self.wordRunnerUnlockXP
        let remaining = max(0, Self.wordRunnerUnlockXP - collectedXP)

        // Im Unlocked-Zustand tappable → `.gameHub`. Im Locked-Zustand
        // bleibt die Card statisch (kein sinnvolles Ziel, solange die
        // XP-Schwelle nicht erreicht ist).
        return Button {
            guard unlocked else { return }
            navigate(.gameHub)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(unlocked
                              ? sectionStyle.accent.opacity(0.22)
                              : AppTheme.Colors.textSecondary.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: unlocked ? "gamecontroller.fill" : "lock.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(unlocked
                                         ? sectionStyle.accent
                                         : AppTheme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Word Runner")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(unlocked
                         ? "Jetzt spielen"
                         : "Freischalten bei \(Self.wordRunnerUnlockXP) XP · noch \(remaining)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                if unlocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSetupCardBackground()
        }
        .buttonStyle(AppCardPressStyle())
        .disabled(!unlocked)
    }

}
