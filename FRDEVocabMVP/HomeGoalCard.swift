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
    let daily: DailyGoalProgress
    /// Fortschritt des Inhaltsziels. `nil`, wenn das Ziel keinen
    /// Inhaltsteil hat (reines Tagesziel).
    let contentProgress: ContentGoalProgress?
    /// **2026-08-05** — Streak-Tage. Die Flamme ist aus dem Header
    /// verschwunden, als die Ziel-Karte dessen Platz übernahm; sie ist
    /// aber ein Symbol, das jeder sofort versteht (User-Spec), deshalb
    /// wandert sie hierher statt ersatzlos wegzufallen. Als Chip rechts
    /// kostet sie keine eigene Zeile.
    let streakDays: Int
    /// **2026-08-08** — wie viele Streak-Joker diesen Monat noch übrig
    /// sind. Nur sichtbar, wenn ein Streak läuft UND mindestens einer
    /// verbraucht ist — sonst wäre die Zahl beim Start ("2 von 2") pure
    /// Zusatz-Information ohne Nutzen. Sichtbarkeit ist hier bewusst
    /// Teil des Wirkmechanismus (Sharif & Shu 2017): der Joker motiviert,
    /// WEIL man seine Knappheit sieht.
    let jokersRemaining: Int
    /// Tap auf die Karte — führt zum Ziel-Detail, wo geändert wird.
    let onTap: () -> Void
    /// **Tagesabschluss (2026-08-06)** — öffnet „Fertig für heute".
    ///
    /// **Warum hier und nicht im Footer** (User-Entscheidung): Der
    /// Abschluss gehört thematisch zum Ziel — er bestätigt genau den
    /// Fortschritt, den diese Karte anzeigt. Der Footer hat zudem schon
    /// fünf Einträge (dieselbe Begründung wie oben zur Platzierung der
    /// Karte selbst).
    let onWrapUp: () -> Void

    private let sectionStyle: AppSectionStyle = .home

    /// **2026-08-06** — Die Karte ist nicht mehr EIN großer Button:
    /// Der obere Teil führt weiterhin ins Ziel-Detail, die Zeile unten
    /// öffnet den Tagesabschluss. Verschachtelte Buttons sind in SwiftUI
    /// unzuverlässig, deshalb zwei getrennte Buttons in einem gemeinsamen
    /// Karten-Hintergrund statt eines Buttons mit Extra-Tap-Bereich.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    dailyProgressBar
                    if let contentLine {
                        Text(contentLine)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppCardPressStyle())

            wrapUpRow
        }
        .padding(.horizontal, 14)
        // **2026-08-06** — 12 → 14 pt (User-Spec: "wir haben nach unten
        // vor Vokabeln scannen und alle Lernlisten noch 'n bisschen
        // Platz... die Karte könnte man noch vergrößern"). Bewusst
        // minimal, nicht auf Kosten der Cards darunter.
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    /// Der Ausstieg. Bewusst zurückhaltend gesetzt — er ist ein Angebot,
    /// keine Aufforderung, und darf mit den Übungs-Karten darunter nicht
    /// um Aufmerksamkeit konkurrieren.
    private var wrapUpRow: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppTheme.Colors.border.opacity(0.4))
                .padding(.top, 12)

            // **2026-08-06** — User-Spec: "seh noch nicht, wo ich den
            // Tagesabschluss eingebe" + "würd das größer machen" + "kein
            // Mondzeichen, sondern sowas wie beim Autorennen, so 'ne
            // Flagge". Von 12/13pt auf 15/15pt, Mond → Zielflagge
            // (`flag.checkered`) — passt besser zum "geschafft"-Moment
            // als der Schlafenszeit-Mond, den man leicht mit "die App
            // schläft jetzt" verwechseln könnte.
            // **2026-08-06, zweite Runde** — User-Spec: "das ist so
            // einfach nur weiß geschrieben wie die anderen Sachen in der
            // Karte, man sieht's noch nicht genau... müsste 'n bisschen
            // visuell auffälliger sein, ich will aber die Main-Seite
            // nicht zuballern". Antwort: keine zusätzliche Fläche und
            // keine zweite Karte — stattdessen bekommt genau diese Zeile
            // eine eigene, abgesetzte Pille mit Amber-Ton (dieselbe
            // `warning`-Farbe wie "Neues Ziel setzen" im Ziel-Detail).
            // Sie hebt sich vom weißen Karten-Text ab, bleibt aber
            // kleiner und ruhiger als die Übungs-Karten darunter.
            Button(action: onWrapUp) {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 15, weight: .bold))
                    Text("Für heute bin ich fertig")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.7)
                }
                .foregroundStyle(AppTheme.Colors.warning)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppTheme.Colors.warning.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(AppTheme.Colors.warning.opacity(0.45), lineWidth: 1.5)
                )
                .padding(.top, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(AppCardPressStyle())
        }
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
    ///
    /// **2026-08-08** — zeigt zusätzlich die Joker-Anzahl, aber NUR wenn
    /// diesen Monat schon einer verbraucht wurde (`jokersRemaining <
    /// StreakJokerStore.maxPerMonth`). Bei vollem Kontingent wäre die
    /// Zahl reine Zusatz-Info ohne Handlungsrelevanz; sie wird erst
    /// interessant, sobald die Knappheit spürbar wird.
    private var streakChip: some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.system(size: 13))
            Text("\(streakDays)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            if jokersRemaining < StreakJokerStore.maxPerMonth {
                Text("· \(jokersRemaining) 🛟")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(AppTheme.Colors.streakAccent.opacity(0.9)))
        .accessibilityLabel(Text("Serie: \(streakDays) \(streakDays == 1 ? "Tag" : "Tage"), \(jokersRemaining) Joker übrig"))
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

    // MARK: - Tagesziel

    private var dailyProgressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(dailyHeadline)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(daily.isReached ? AppTheme.Colors.moduleNomen : AppTheme.Colors.textPrimary)
                Spacer(minLength: 0)
                Text("\(daily.doneItems)/\(daily.targetItems)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                    Capsule()
                        .fill(daily.isReached ? AppTheme.Colors.moduleNomen : sectionStyle.accent)
                        .frame(width: geo.size.width * daily.fraction)
                }
            }
            .frame(height: 7)
        }
    }

    /// **Gewinn-Framing**, siehe Datei-Kommentar oben.
    private var dailyHeadline: String {
        if daily.isReached {
            return "Tagesziel geschafft! 🎉"
        }
        let remaining = daily.remainingItems
        return remaining == 1
            ? "Noch 1 Vokabel heute"
            : "Noch \(remaining) Vokabeln heute"
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
