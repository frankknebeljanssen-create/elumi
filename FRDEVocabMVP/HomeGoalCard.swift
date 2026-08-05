import SwiftUI

// HomeGoalCard.swift
// **Ziel-System Phase 3 (2026-08-05)** — die Heimat des Lernziels in
// der laufenden App.
//
// **Warum es die Karte braucht:** Das Onboarding verspricht am Ende
// "Keine Sorge, du kannst dein Ziel jederzeit ändern!". Bis hierher
// konnte die App das nicht einlösen — das Ziel war ausschließlich über
// die Dev-Card in den Einstellungen erreichbar, für einen echten Nutzer
// also gar nicht (User-Frage: "wo kann der User sein Ziel jederzeit
// ändern?").
//
// **Platzierung** (User-Entscheidung): Home + Fortschritt-Screen, kein
// eigenes Footer-Icon. Der Footer hat bereits fünf Einträge; ein
// sechster macht die Tap-Ziele auf kleinen Geräten eng. Auf Home ist
// das Ziel dafür beim Öffnen der App sofort präsent — genau da, wo der
// Nutzer entscheidet, was er als Nächstes tut.
//
// **Framing bewusst in Gewinn, nicht in Verlust** (Recherche-Befund):
// "Noch 2 Tage diese Woche", niemals "Verlier deine Serie nicht". Der
// what-the-hell-Effekt (Adriaanse 2022) ist gut belegt — ein einzelner
// Ausrutscher unter Verlust-Framing führt nicht zum Nachbessern,
// sondern zum kompletten Abbruch.
struct HomeGoalCard: View {
    let plan: LearningGoalPlan
    let rhythm: WeeklyRhythmProgress
    /// Fortschritt des Inhaltsziels. `nil`, wenn das Ziel keinen
    /// Inhaltsteil hat (reines Rhythmusziel).
    let contentProgress: ContentGoalProgress?
    /// **2026-08-05** — Streak-Tage. Die Flamme ist aus dem Header
    /// verschwunden, als die Ziel-Karte dessen Platz übernahm; sie ist
    /// aber ein Symbol, das jeder sofort versteht (User-Spec), deshalb
    /// wandert sie hierher statt ersatzlos wegzufallen. Als Chip rechts
    /// kostet sie keine eigene Zeile.
    let streakDays: Int
    /// Tap auf die Karte — führt zum Ziel-Detail, wo geändert wird.
    let onTap: () -> Void

    private let sectionStyle: AppSectionStyle = .home

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                header
                rhythmProgressBar
                if let contentLine {
                    Text(contentLine)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSetupCardBackground()
        }
        .buttonStyle(AppCardPressStyle())
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(titleText)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            // Deadline hat Vorrang vor der Flamme — bei nahem Termin
            // ist der Countdown die dringendere Information, und zwei
            // Chips nebeneinander würden die Zeile überladen.
            if let deadlineChip {
                Text(deadlineChip)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.Colors.cta))
            } else if streakDays > 0 {
                streakChip
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    /// Flamme plus Tagezahl, im selben Amber wie die frühere
    /// Header-Pille (`streakAccent`) — der Nutzer erkennt sie wieder.
    private var streakChip: some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.system(size: 13))
            Text("\(streakDays)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(AppTheme.Colors.streakAccent.opacity(0.9)))
        .accessibilityLabel(Text("Serie: \(streakDays) \(streakDays == 1 ? "Tag" : "Tage")"))
    }

    /// **2026-08-05** — immer „Dein Ziel", nie der Anlass-Titel
    /// (User-Spec: "das muss dann dein Ziel heißen, weil das führt auf
    /// dein Ziel"). Vorher stand hier z. B. „Ein Kapitel oder eine
    /// Unité üben", was wie eine weitere Übungs-Karte aussah statt wie
    /// der Einstieg ins Ziel. Der Anlass steht ja im Detail-Screen.
    private var titleText: String { "Dein Ziel" }

    /// Countdown nur bei naher Deadline (≤ 7 Tage). Weiter entfernte
    /// Termine erzeugen nur Dauer-Druck ohne Handlungsrelevanz.
    private var deadlineChip: String? {
        guard let days = plan.content?.daysRemaining(), days >= 0, days <= 7 else { return nil }
        switch days {
        case 0: return "Heute!"
        case 1: return "Noch 1 Tag"
        default: return "Noch \(days) Tage"
        }
    }

    // MARK: - Rhythmus

    private var rhythmProgressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(rhythmHeadline)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(rhythm.isReached ? AppTheme.Colors.moduleNomen : AppTheme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text("\(rhythm.practicedDays)/\(rhythm.targetDays)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                    Capsule()
                        .fill(rhythm.isReached ? AppTheme.Colors.moduleNomen : sectionStyle.accent)
                        .frame(width: geo.size.width * rhythm.fraction)
                }
            }
            .frame(height: 7)
        }
    }

    /// **Gewinn-Framing**, siehe Datei-Kommentar oben.
    private var rhythmHeadline: String {
        if rhythm.isReached {
            return "Wochenziel geschafft! 🎉"
        }
        let remaining = rhythm.remainingDays
        return remaining == 1
            ? "Noch 1 Tag diese Woche"
            : "Noch \(remaining) Tage diese Woche"
    }

    // MARK: - Inhaltsziel

    private var contentLine: String? {
        guard let content = plan.content else { return nil }
        if content.isAwaitingList {
            return "Deinem Ziel fehlen noch die Vokabeln. Tipp hier, um sie hinzuzufügen."
        }
        guard let progress = contentProgress, !progress.isEmpty else { return nil }
        if progress.isReached {
            return "Alle Vokabeln sitzen. Stark!"
        }
        let remaining = progress.remainingCount
        return remaining == 1
            ? "Noch 1 Vokabel, dann sitzt alles."
            : "Noch \(remaining) Vokabeln, dann sitzt alles."
    }
}
