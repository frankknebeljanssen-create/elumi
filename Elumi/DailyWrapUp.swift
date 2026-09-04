import Foundation
import SwiftUI
import UserNotifications

// DailyWrapUp.swift
// **Tagesabschluss (2026-08-06)** — „Fertig für heute".
//
// **Warum es das braucht** (User-Frage): Die App hatte einen sorgfältig
// gebauten Einstieg (Willkommen → Ziel-Onboarding), aber keinen
// Ausstieg. Wer für heute fertig war, drückte die App einfach weg. Kein
// Abschluss, keine Bestätigung, dass der Tag gezählt hat, und keine
// Brücke zum nächsten Mal.
//
// **Zwei Bausteine, beide aus der Recherche vom 2026-08-05:**
//
//   1. **Abschluss-Moment.** Zeigt, was heute passiert ist, im selben
//      Gewinn-Framing wie `HomeGoalCard` — nie „du hast zu wenig
//      gemacht". Ein Tag mit einer einzigen Übung ist ein guter Tag.
//
//   2. **Wenn-Dann-Trigger.** Eine einzige Frage: „Wann übst du
//      morgen?" Das ist der am besten belegte Hebel aus der ganzen
//      Recherche — Gollwitzer & Sheeran finden für
//      Implementierungsintentionen eine Effektstärke von d = .65. Der
//      Wirkmechanismus ist NICHT die Erinnerung selbst, sondern dass
//      der Nutzer den Moment vorher konkret benennt. Die Notification
//      ist nur die technische Zugabe.
//
// **Bewusst nicht gebaut:** kein Pflicht-Screen beim Verlassen der App,
// keine Streak-Warnung, kein „schade, dass du schon gehst". Verlust-
// Framing beim Ausstieg ist genau der Mechanismus, der laut Recherche
// (what-the-hell-Effekt, Adriaanse 2022) zum kompletten Abbruch führt
// statt zum Nachbessern.

/// Tageszeit-Fenster für die morgige Erinnerung. Bewusst grob — ein
/// Schüler weiß „nach dem Abendessen", nicht „18:47 Uhr". Genaue
/// Uhrzeiten würden eine Präzision vortäuschen, die niemand einhält.
enum DailyReminderSlot: String, CaseIterable, Identifiable {
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning:   return "Vormittags"
        case .afternoon: return "Nachmittags"
        case .evening:   return "Abends"
        }
    }

    var emoji: String {
        switch self {
        case .morning:   return "🌅"
        case .afternoon: return "☀️"
        case .evening:   return "🌙"
        }
    }

    /// **2026-08-06** — Bewusst statt der drei Zeitfenster: "Lieber nicht
    /// festlegen" war vorher ein separater Textlink unter den drei
    /// Kacheln (User-Spec: "das müssten vier so Flächen sein... nicht
    /// festlegen als vierte"). Kein Fall dieses Enums — `nil` bleibt die
    /// Kodierung für "kein Slot gewählt", diese Konstante ist nur für
    /// die einheitliche Kachel-Darstellung im Sheet.
    // **2026-08-06** — „Lieber nicht" → „Weiß nicht" (User-Spec).
    // „Lieber nicht" klingt nach Ablehnung des Übens; gemeint ist aber
    // nur, dass die Tageszeit noch offen ist.
    static let skipTitle = "Weiß nicht"
    static let skipEmoji = "🤷"

    /// Stunde, zu der erinnert wird. Jeweils am Anfang des Fensters, nicht
    /// in der Mitte — eine Erinnerung, die kommt, wenn das Fenster schon
    /// halb vorbei ist, hilft niemandem.
    var hour: Int {
        switch self {
        case .morning:   return 9
        case .afternoon: return 15
        case .evening:   return 19
        }
    }
}

@MainActor
final class DailyWrapUpStore: ObservableObject {
    static let shared = DailyWrapUpStore()

    /// Tages-Index des letzten Abschlusses. Verhindert, dass derselbe Tag
    /// zweimal als „abgeschlossen" gefeiert wird.
    @Published private(set) var lastWrapUpDayIndex: Int?

    /// Zuletzt gewählte Erinnerungszeit. Wird beim nächsten Abschluss
    /// vorausgewählt — wer immer abends übt, soll das nicht jeden Tag neu
    /// antippen müssen.
    @Published private(set) var reminderSlot: DailyReminderSlot?

    private init() {
        load()
    }

    /// Ob der heutige Tag bereits abgeschlossen wurde. Steuert nur die
    /// Beschriftung des Einstiegs, **nicht** dessen Sichtbarkeit — wer
    /// nach dem Abschluss weitermacht und dann nochmal aufhört, soll den
    /// Weg nicht versperrt bekommen.
    var hasWrappedUpToday: Bool {
        lastWrapUpDayIndex == GamificationConfig.currentDayIndex
    }

    // MARK: - Abschluss

    /// Bucht den heutigen Abschluss und plant, falls gewünscht, die
    /// morgige Erinnerung.
    ///
    /// `slot == nil` heißt: der Nutzer hat den Wenn-Dann-Schritt
    /// übersprungen. Dann wird auch keine Erinnerung gestellt und eine
    /// eventuell noch offene aus einem früheren Abschluss verworfen —
    /// sonst käme sie, obwohl er sie gerade abgelehnt hat.
    func completeToday(slot: DailyReminderSlot?) {
        lastWrapUpDayIndex = GamificationConfig.currentDayIndex
        reminderSlot = slot
        persist()

        cancelReminder()
        if let slot {
            scheduleReminder(for: slot)
        }
    }

    // MARK: - Erinnerung

    /// `nonisolated`, weil der Bezeichner aus dem Berechtigungs-Callback
    /// heraus gelesen wird — der läuft außerhalb des Main-Actors.
    private nonisolated static let reminderIdentifier = "elumi.wrapUp.tomorrow"

    /// Fragt die Berechtigung erst hier an, nicht beim App-Start: Der
    /// Nutzer hat gerade selbst eine Tageszeit gewählt, der Systemdialog
    /// kommt also mit erkennbarem Anlass statt aus dem Nichts.
    private func scheduleReminder(for slot: DailyReminderSlot) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Bereit, wenn du bist"
            // Kein Druck, keine Serie, keine Zahl. Nur ein Angebot.
            content.body = "Kurz Französisch üben? Elumi wartet."
            content.sound = .default

            var components = DateComponents()
            components.hour = slot.hour
            components.minute = 0

            // `repeats: true` — die Erinnerung wiederholt sich täglich zur
            // gewählten Zeit, bis der Nutzer beim nächsten Abschluss eine
            // andere Zeit wählt oder überspringt. Eine einmalige
            // Erinnerung wäre genau dann weg, wenn sie am nötigsten ist:
            // nach dem ersten Tag, an dem jemand nicht geübt hat.
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: Self.reminderIdentifier,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func cancelReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }

    // MARK: - Persistenz

    private var dayKey: String {
        AccountStore.shared.namespacedKey(appDailyWrapUpDayKey)
    }
    private var slotKey: String {
        AccountStore.shared.namespacedKey(appDailyWrapUpReminderSlotKey)
    }

    /// Öffentlich wie bei den anderen Singleton-Stores, damit der
    /// Account-Wechsel direkt neu laden kann.
    func load() {
        let defaults = UserDefaults.standard
        lastWrapUpDayIndex = defaults.object(forKey: dayKey) as? Int
        reminderSlot = (defaults.string(forKey: slotKey)).flatMap(DailyReminderSlot.init(rawValue:))
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let lastWrapUpDayIndex {
            defaults.set(lastWrapUpDayIndex, forKey: dayKey)
        } else {
            defaults.removeObject(forKey: dayKey)
        }
        if let reminderSlot {
            defaults.set(reminderSlot.rawValue, forKey: slotKey)
        } else {
            defaults.removeObject(forKey: slotKey)
        }
    }
}
