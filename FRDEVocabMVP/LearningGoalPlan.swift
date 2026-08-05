import Foundation

// LearningGoalPlan.swift
// **Ziel-System (2026-08-05)** — das Modell hinter „Was steht bei dir an?"
//
// Zwei Ebenen, bewusst getrennt, weil sie mechanisch verschieden sind:
//
//   • **Rhythmusziel** (`weeklyTargetDays`) — hat JEDER Nutzer, ist Pflicht
//     im Onboarding. Kein Ende, resettet wöchentlich. Fortschritt =
//     geübte Tage / Zielzahl.
//   • **Inhaltsziel** (`content`) — optional. Hat einen Bestand (Liste) und
//     optional eine Deadline. Endlich und abschließbar. Fortschritt =
//     starke Vokabeln / Gesamt.
//
// Der Versuch, beides in EINE Zahl zu pressen, macht beides
// unverständlich — deshalb rechnen sie getrennt und werden auch getrennt
// angezeigt (Rhythmus im Chrome/Home-Balken, Inhalt als eigene Karte).
//
// **Kein neues Tracking**: Der Inhalts-Fortschritt wird vollständig aus
// `ItemLearningStatusStore` abgeleitet (welche Vokabel ist `.strong`),
// der Rhythmus-Fortschritt aus einem schlanken Tages-Set. Es gibt keine
// zweite Buchführung über Lernerfolge.

// MARK: - Anlass

/// Warum der Schüler gerade übt. Bewusst in **Anlässen** formuliert, nicht
/// in Metriken — ein Schüler denkt „Freitag ist Schulaufgabe", nicht
/// „ich möchte meine Retention steigern".
///
/// Die Reihenfolge ist die Anzeigereihenfolge im Onboarding.
enum LearningOccasion: String, Codable, CaseIterable, Identifiable {
    /// Klassenarbeit / Schulaufgabe / Klausur steht an → Deadline + Liste.
    case exam = "exam"
    /// Ein Kapitel bzw. eine Unit aus dem Schulbuch → Liste, keine Deadline.
    case chapter = "chapter"
    /// Vokabeln aus dem eigenen Vokabelheft festigen → Liste (meist per Scan).
    case notebook = "notebook"
    /// Gezielt das wegräumen, was noch wackelt → nutzt die bestehende
    /// „Meine Wackelkandidaten"-Liste, braucht keine eigene Zuordnung.
    case shakyItems = "shaky_items"
    /// Kein konkreter Anlass — nur dranbleiben. Erzeugt ein reines
    /// Rhythmusziel ohne Inhaltsteil.
    case stayOnTrack = "stay_on_track"

    var id: String { rawValue }

    /// Karten-Titel im Onboarding. Schülersprache, keine Fachbegriffe.
    ///
    /// **2026-08-05** — "steht an"/"festigen" entfernt (User-Spec): die
    /// Frage darüber ("Was steht bei dir an?") sagt das schon, die
    /// Wiederholung in der Karte war redundant. "Unit" → "Unité"
    /// (korrekte französische Schreibweise, so im Schulbuch benannt).
    /// "Vokabeln aus meinem Heft üben" → "Vokabeln üben": die Vokabeln
    /// können ebenso gut aus einem Buch stammen, "Heft" war eine
    /// falsche Festlegung.
    var title: String {
        switch self {
        case .exam:        return "Schulaufgabe oder Klausur"
        case .chapter:     return "Ein Kapitel oder eine Unité üben"
        case .notebook:    return "Vokabeln üben"
        case .shakyItems:  return "Meine Wackelkandidaten wegräumen"
        case .stayOnTrack: return "Einfach dranbleiben"
        }
    }

    /// Emoji statt SF-Symbol: Die Onboarding-Karten sollen warm und
    /// jugendlich wirken, nicht wie ein Systemdialog.
    var emoji: String {
        switch self {
        case .exam:        return "📚"
        case .chapter:     return "📖"
        case .notebook:    return "✏️"
        case .shakyItems:  return "💪"
        case .stayOnTrack: return "🙂"
        }
    }

    /// Ob dieser Anlass einen Vokabel-Bestand braucht, um messbar zu sein.
    /// `.stayOnTrack` ist rein rhythmisch, `.shakyItems` zieht seinen
    /// Bestand automatisch aus dem Lernstatus — beide brauchen im
    /// Onboarding also KEINEN Listen-Auswahl-Schritt.
    var requiresListSelection: Bool {
        switch self {
        case .exam, .chapter, .notebook: return true
        case .shakyItems, .stayOnTrack:  return false
        }
    }

    /// Ob nach einem Termin gefragt wird. Nur die Schulaufgabe hat einen
    /// echten externen Stichtag — bei „Kapitel üben" wäre ein erfundenes
    /// Datum nur Druck ohne Anlass.
    var requiresDeadline: Bool { self == .exam }
}

// MARK: - Inhaltsziel

/// Der optionale, endliche Teil eines Ziels: ein Vokabel-Bestand, der
/// „sitzen" soll — optional bis zu einem Stichtag.
struct LearningGoalContent: Codable, Equatable {
    var occasion: LearningOccasion

    /// Listen, aus denen sich der Bestand speist — **mehrere möglich**.
    ///
    /// Das Ziel liest sich damit als „diese Listen sollen sitzen": Ein
    /// Schüler denkt in seinem eigenen Material („Unit 3 und die Wörter
    /// aus dem Heft"), nicht in Mengen („50 Vokabeln"). Eingebaute Listen
    /// sind ebenso erlaubt wie selbst gescannte — wer noch nichts
    /// gescannt hat, soll trotzdem sofort ein Ziel setzen können.
    ///
    /// Leeres Array bedeutet **angelegt, aber noch nicht scharf**: Der
    /// Nutzer hat „später festlegen" gewählt oder der Scan läuft noch.
    /// Gültiger Zustand, kein Fehler — die Home-Karte fordert dann zum
    /// Zuordnen auf. Bei `.shakyItems` bleibt es immer leer, weil der
    /// Bestand dynamisch aus dem Lernstatus kommt.
    var listIDs: [UUID]

    /// Stichtag (nur bei `.exam`). Nach Ablauf wird das Ziel archiviert,
    /// **nicht** als gescheitert markiert — die App weiß nicht, wie die
    /// Schulaufgabe gelaufen ist, und soll nicht so tun.
    var deadline: Date?

    /// Frei gewählte Bezeichnung („Unit 3", „Vokabeltest Freitag").
    /// Optional — leer heißt: der Anlass-Titel wird angezeigt.
    var label: String?

    init(
        occasion: LearningOccasion,
        listIDs: [UUID] = [],
        deadline: Date? = nil,
        label: String? = nil
    ) {
        self.occasion = occasion
        self.listIDs = listIDs
        self.deadline = deadline
        self.label = label
    }

    /// Anzeigename für Karten und Chips.
    var displayTitle: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty {
            return label
        }
        return occasion.title
    }

    /// Ob dem Ziel noch der Vokabel-Bestand fehlt. Treibt den
    /// „Dein Ziel wartet noch auf Vokabeln"-Zustand auf der Home-Karte
    /// und den Rückweg aus dem Scan („Zu deinem Ziel hinzufügen?").
    var isAwaitingList: Bool {
        occasion.requiresListSelection && listIDs.isEmpty
    }

    /// Verbleibende volle Tage bis zur Deadline. `nil` ohne Deadline,
    /// 0 am Stichtag selbst, negativ wenn der Termin vorbei ist.
    func daysRemaining(from reference: Date = Date()) -> Int? {
        guard let deadline else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: reference)
        let end = calendar.startOfDay(for: deadline)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    /// Deadline liegt in der Vergangenheit → Ziel ist reif für den
    /// „Wie lief's?"-Nachlauf.
    func isExpired(at reference: Date = Date()) -> Bool {
        guard let days = daysRemaining(from: reference) else { return false }
        return days < 0
    }
}

// MARK: - Gesamt-Plan

/// Das vollständige Ziel eines Nutzers: Pflicht-Rhythmus plus optionaler
/// Inhalt.
struct LearningGoalPlan: Codable, Equatable {
    /// Wie viele Tage pro Woche geübt werden soll. Pflichtwert — jeder
    /// Nutzer verlässt das Onboarding mit einem davon, damit der
    /// Fortschritt nie einen leeren Zustand zeigen muss.
    var weeklyTargetDays: Int

    /// Optionaler endlicher Teil. `nil` bei „Einfach dranbleiben".
    var content: LearningGoalContent?

    /// Wann das Ziel gesetzt wurde — für „seit X Tagen dabei"-Momente
    /// und um archivierte Ziele zu sortieren.
    var createdAt: Date

    init(
        weeklyTargetDays: Int,
        content: LearningGoalContent? = nil,
        createdAt: Date = Date()
    ) {
        self.weeklyTargetDays = Self.clampWeeklyTarget(weeklyTargetDays)
        self.content = content
        self.createdAt = createdAt
    }

    // MARK: Rhythmus-Optionen

    /// Auswahlwerte im Onboarding. Bewusst nur vier — mehr Auswahl macht
    /// die Entscheidung schwerer, nicht besser.
    static let weeklyTargetOptions: [Int] = [2, 3, 5, 7]

    /// Vorgabe, wenn nichts gewählt wurde. „Solide" statt „ambitioniert" —
    /// ein zu hoher Startwert produziert in Woche 1 ein Misserfolgserlebnis.
    static let defaultWeeklyTargetDays = 3

    static func clampWeeklyTarget(_ value: Int) -> Int {
        min(max(value, 1), 7)
    }

    /// Label für die Rhythmus-Auswahl. **Kein Wert darf sich nach
    /// Versagen anfühlen** — 2 Tage ist ein legitimer Plan, keine
    /// Kapitulation.
    /// **2026-08-05** — "locker" → "easy", "jeden Tag" → "Power User"
    /// (User-Spec: jugendlicher, weniger nüchtern-beschreibend).
    /// **2026-08-06** — "ambitioniert" → "STARK" (User-Spec: "ist für
    /// die Kids nicht gut" — klingt nach Schulnoten-Anspruch statt nach
    /// Zuspruch). "solide" → "COOL" (User-Spec, nach kurzem Hin und Her:
    /// "Easy, Cool, Stark und Power User"). Alle vier jetzt
    /// großgeschrieben mit Ausrufezeichen, konsistent mit "POWER USER"
    /// (User-Spec: "ich würde sie alle großschreiben").
    /// **2026-08-06, Korrektur** — Ausrufezeichen bei allen vier war zu
    /// viel (User-Spec: "das ist zu viel"). Nur bei den beiden stärkeren
    /// Stufen behalten, wo der Ausruf-Charakter tatsächlich passt.
    static func weeklyTargetLabel(for days: Int) -> String {
        switch days {
        case ...2: return "EASY 🙂"
        case 3:    return "COOL 👍"
        case 4...5: return "STARK! 🔥"
        default:   return "POWER USER! 💪"
        }
    }

    // MARK: Codable-Robustheit

    enum CodingKeys: String, CodingKey {
        case weeklyTargetDays, content, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawTarget = try c.decodeIfPresent(Int.self, forKey: .weeklyTargetDays)
            ?? Self.defaultWeeklyTargetDays
        weeklyTargetDays = Self.clampWeeklyTarget(rawTarget)
        content = try c.decodeIfPresent(LearningGoalContent.self, forKey: .content)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - Fortschritts-Werte

/// Fortschritt des Rhythmusziels in der laufenden Woche.
struct WeeklyRhythmProgress: Equatable {
    let practicedDays: Int
    let targetDays: Int

    /// 0…1, gedeckelt — mehr üben als geplant füllt den Balken nicht
    /// über den Rand, sondern erreicht ihn.
    var fraction: Double {
        guard targetDays > 0 else { return 0 }
        return min(Double(practicedDays) / Double(targetDays), 1.0)
    }

    var isReached: Bool { practicedDays >= targetDays }

    /// Noch offene Tage bis zum Wochenziel. 0, wenn erreicht.
    var remainingDays: Int { max(0, targetDays - practicedDays) }
}

/// Fortschritt eines Inhaltsziels — abgeleitet, nie persistiert.
struct ContentGoalProgress: Equatable {
    let strongCount: Int
    let totalCount: Int

    var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return min(Double(strongCount) / Double(totalCount), 1.0)
    }

    var isReached: Bool { totalCount > 0 && strongCount >= totalCount }

    /// Wie viele Vokabeln noch nicht sitzen.
    var remainingCount: Int { max(0, totalCount - strongCount) }

    /// Kein Bestand vorhanden (Liste leer oder noch nicht zugeordnet).
    var isEmpty: Bool { totalCount == 0 }
}
