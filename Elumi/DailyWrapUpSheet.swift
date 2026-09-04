import SwiftUI

// DailyWrapUpSheet.swift
// **Tagesabschluss (2026-08-06)** — die Oberfläche. Konzept, Begründung
// und die Erinnerungs-Logik stehen in `DailyWrapUp.swift`.
//
// Zwei Abschnitte auf einem Screen, bewusst nicht auf zwei aufgeteilt:
// der Rückblick ist die Belohnung, die Frage nach morgen kostet einen
// Tap. Ein zweiter Screen dafür wäre eine Hürde am Ende, wo der Nutzer
// gerade aufhören will.
struct DailyWrapUpSheet: View {
    /// Wie viele Aufgaben heute bearbeitet wurden (`DailyStatsStore`).
    let actionsToday: Int
    /// Ob heute schon etwas Korrektes beantwortet wurde.
    let didPracticeToday: Bool
    /// Tagesziel-Fortschritt für die Zeile darunter.
    let daily: DailyGoalProgress
    let streakDays: Int
    let onClose: () -> Void

    @ObservedObject private var wrapUpStore = DailyWrapUpStore.shared
    @State private var selectedSlot: DailyReminderSlot?

    private static let mascotSize: CGFloat = 76

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppTheme.Spacing.lg) {
                mascot

                VStack(spacing: 8) {
                    Text(headline)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subline)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Bei null Aufgaben wäre die Karte eine Zeile „0 Aufgaben"
                // plus zwei unveränderte Nullwerte — sie sagt dann nichts,
                // was der Text darüber nicht schon gesagt hat.
                if !didNothingToday {
                    summaryCard
                }

                reminderSection

                // **2026-08-06, zweite Runde** — gilt jetzt für den
                // gesamten "heute zählt noch nicht"-Fall, nicht nur für
                // null Aufgaben (siehe `needsMoreToday`).
                if needsMoreToday {
                    // **2026-08-06** — Weg zurück ins Üben als primäre
                    // Aktion (User-Spec: "willst du nicht ein bisschen
                    // üben? Vielleicht hast du zehn Minuten"). Schließt
                    // die Sheet, ohne den Tag abzuschließen: der Nutzer
                    // landet wieder auf Home und sucht sich eine Übung.
                    Button {
                        onClose()
                    } label: {
                        Text(didNothingToday ? "Na gut, kurz üben" : "Noch eine kurze Runde")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 54)
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

                    // Der ehrliche Ausweg, klar beschriftet. Wer gehen
                    // will, soll gehen können, ohne sich durch eine Hürde
                    // tippen zu müssen — sonst wird aus dem Zwinkern eine
                    // Nötigung, und genau davor warnt die Recherche.
                    Button {
                        wrapUpStore.completeToday(slot: selectedSlot)
                        onClose()
                    } label: {
                        Text("Nein, für heute reicht's")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        wrapUpStore.completeToday(slot: selectedSlot)
                        onClose()
                    } label: {
                        // **2026-08-06** — Winke-Hand ergänzt (User-Spec).
                        Text(selectedSlot == nil ? "Tschüss! 👋" : "Bis morgen! 👋")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 54)
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

                    // **2026-08-06** — Rückweg ins Üben (User-Spec: "ich
                    // würde noch 'n CTA drunter machen, doch noch
                    // weitermachen"). Schließt nur die Sheet, ohne den
                    // Tag abzuschließen — der Nutzer landet wieder da,
                    // wo er herkam, und kann weiterüben.
                    Button {
                        onClose()
                    } label: {
                        Text("Doch noch weiter")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.background)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Zuletzt gewählte Zeit vorschlagen — wer immer abends übt,
            // soll das nicht jedes Mal neu antippen.
            selectedSlot = wrapUpStore.reminderSlot
        }
    }

    private var mascot: some View {
        ZStack {
            Image("SplashCharacter")
                .resizable()
                .scaledToFit()
                .frame(width: Self.mascotSize, height: Self.mascotSize)
            SplashCharacterBlinkOverlay(size: Self.mascotSize, startDate: .now)
                .frame(width: Self.mascotSize, height: Self.mascotSize)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
    }

    // MARK: - Rückblick

    /// **2026-08-06** — Ob heute überhaupt noch nichts passiert ist.
    /// Steuert eine eigene Variante des ganzen Screens (User-Report:
    /// "ich habe direkt nach dem Start ohne eine Übung zu machen auf
    /// fertig für heute getippt, und dann kommt 'Stark gemacht'. Das ist
    /// natürlich sinnlos").
    private var didNothingToday: Bool { actionsToday == 0 }

    /// **2026-08-06, zweite Runde** — `didNothingToday` allein reichte
    /// nicht (User-Report: "obwohl ich gar keine Übung gemacht habe …
    /// schon wieder kommt stark gemacht"). Ursache: `actionsToday` zählt
    /// den **ganzen Tag**. Wer morgens geübt und abends die App nur kurz
    /// aufgemacht hat, ist nicht bei null — bekam aber trotzdem das volle
    /// Lob, obwohl in dieser Runde nichts passiert ist.
    ///
    /// Richtige Bezugsgröße ist deshalb nicht "hat er überhaupt etwas
    /// getan", sondern "**zählt der heutige Tag fürs Tagesziel**"
    /// (`didPracticeToday` — gesetzt erst ab dem Session-Minimum, siehe
    /// `GamificationConfig.SessionMinimum`). Nur dann ist Lob verdient.
    /// Darunter: aufmunternde Rückfrage statt Applaus — und derselbe
    /// bequeme Weg zurück ins Üben wie im Null-Fall.
    private var needsMoreToday: Bool { !didPracticeToday }

    /// **Nie tadeln, aber ruhig zwinkern.** Der Null-Fall bekommt keinen
    /// Vorwurf — ein Vorwurf beim Verlassen ist der zuverlässigste Weg,
    /// dass jemand nicht wiederkommt (siehe Doku in `DailyWrapUp.swift`).
    /// Aber ein Lob für nichts ist genauso falsch: es entwertet das Lob
    /// an allen anderen Tagen. Deshalb hier eine augenzwinkernde
    /// Rückfrage plus ein bequemer Weg zurück ins Üben.
    private var headline: String {
        if didNothingToday { return "Schon Schluss? 🤨" }
        if needsMoreToday { return "Schon fertig? 🤔" }
        if daily.isReached { return "Tagesziel geschafft! 🎉" }
        return "Stark gemacht!"
    }

    private var subline: String {
        if didNothingToday {
            return "Heute war noch keine einzige Übung dabei. Zehn Minuten hätten wir doch noch, oder?"
        }
        if needsMoreToday {
            return "Für heute hat's noch nicht ganz gereicht — eine kurze Runde, und der Tag zählt."
        }
        if daily.isReached {
            return "Du hast heute alles geschafft, was du dir vorgenommen hast."
        }
        let remaining = daily.remainingItems
        return remaining == 1
            ? "Noch 1 Vokabel, dann steht dein Tagesziel."
            : "Noch \(remaining) Vokabeln, dann steht dein Tagesziel."
    }

    private var summaryCard: some View {
        VStack(spacing: 8) {
            summaryRow(
                emoji: "✏️",
                label: "Heute geübt",
                value: actionsToday == 1 ? "1 Aufgabe" : "\(actionsToday) Aufgaben"
            )
            summaryRow(
                emoji: didPracticeToday ? "✅" : "⏳",
                label: "Dein Tagesziel",
                value: "\(daily.doneItems) von \(daily.targetItems) Vokabeln"
            )
            if streakDays > 0 {
                summaryRow(
                    emoji: "🔥",
                    label: "Deine Serie",
                    value: streakDays == 1 ? "1 Tag" : "\(streakDays) Tage"
                )
            }
        }
    }

    private func summaryRow(emoji: String, label: String, value: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(emoji)
                .font(.system(size: 26))
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.Colors.cardLabel)
                Text(value)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
    }

    // MARK: - Wenn-Dann

    /// **Der eigentliche Wirkstoff dieses Screens** (siehe Doku in
    /// `DailyWrapUp.swift`): den nächsten Übungsmoment vorher konkret
    /// benennen. Deshalb steht hier eine Frage nach dem WANN, nicht ein
    /// Schalter „Erinnerung an/aus" — das Benennen ist der Hebel, die
    /// Notification nur die Zugabe.
    ///
    /// **2026-08-06** — vorher drei Kacheln plus ein separater Textlink
    /// „Lieber nicht festlegen" darunter (User-Spec: "das müssten vier
    /// so Flächen sein... nicht festlegen als vierte"). Jetzt eine
    /// gleichwertige vierte Kachel im selben Grid statt einem visuell
    /// abgesetzten Opt-out — "keine Erinnerung" ist eine ebenso legitime
    /// Wahl wie die drei Zeitfenster, keine, die man erst suchen muss.
    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wann übst du morgen?")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            // **2026-08-06** — 2×2-Raster statt Viererreihe: nebeneinander
            // blieben für „Nachmittags" und „Weiß noch nicht" auf
            // schmalen Geräten nur ~80 pt, der Text wurde auf 80 %
            // heruntergestaucht. Übereinander haben alle vier ihre volle
            // Beschriftung.
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(DailyReminderSlot.allCases) { slot in
                    slotChip(slot)
                }
                skipChip
            }
        }
    }

    private func slotChip(_ slot: DailyReminderSlot) -> some View {
        reminderTile(
            emoji: slot.emoji,
            title: slot.title,
            isSelected: selectedSlot == slot
        ) {
            selectedSlot = slot
        }
    }

    private var skipChip: some View {
        reminderTile(
            emoji: DailyReminderSlot.skipEmoji,
            title: DailyReminderSlot.skipTitle,
            isSelected: selectedSlot == nil
        ) {
            selectedSlot = nil
        }
    }

    private func reminderTile(
        emoji: String,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(
                        isSelected ? AppTheme.Colors.moduleNomen : AppTheme.Colors.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(AppCardPressStyle())
    }
}
