import Foundation

/// Qualitative Klassifikation eines einzelnen Vokabel-Eintrags, positiv
/// formuliert — „schwach" heißt **nicht** „schlecht", sondern „braucht
/// noch Aufmerksamkeit". Die Karten im Detail-Screen und die Zahlen auf
/// der Home-Card lesen sich dadurch als Empfehlung, nicht als Bewertung.
///
/// Schwellen (MVP):
///   • `.strong`     — ≥ 5 Versuche **und** ≥ 80 % Trefferquote
///   • `.needsWork`  — ≥ 5 Versuche **und** < 60 % Trefferquote
///   • `.learning`   — alles dazwischen, **solange** ≥ 3 Versuche vorliegen
///   • `.sparse`     — < 3 Versuche insgesamt (noch zu wenig Signal)
///
/// Die Schwellen sind bewusst konservativ: Ein einzelner Fehltreffer in
/// den ersten 5 Versuchen kippt die Vokabel nicht sofort in `.needsWork`,
/// und 3 Treffer reichen nicht, um schon als `.strong` zu gelten — so
/// kommen die UI-Labels nicht verfrüht in eine „fertig"-Stimmung.
enum ItemLearningStatusClass: String, Codable, CaseIterable {
    case strong
    case learning
    case needsWork
    case sparse
}

/// Ein einzelner Tracking-Eintrag im `ItemLearningStatusStore`.
///
/// **Identität**: der `key` ist der kanonisierte Schlüssel aus
/// `(french, german, cardType)` — nicht die `VocabularyItem.id`, da die
/// UUID pro Init neu vergeben wird und somit für das modulübergreifende
/// Tracking nicht stabil ist (siehe ausführliche Notizen in
/// `ItemLearningStatusStore.canonicalText`).
///
/// `displayFrench` / `displayGerman` speichern die zuletzt gesehene
/// Schreibweise, damit der Detail-Screen die Vokabel mit der erwarteten
/// Capitalisierung (z. B. „Apfel") zeigen kann — die Canonicalization
/// unten lowercased-et ausschließlich den Schlüssel.
struct ItemLearningStatus: Codable, Equatable, Hashable, Identifiable {
    var id: String { key }

    /// Stabiler, modulübergreifender Schlüssel. Siehe
    /// `ItemLearningStatusStore.canonicalKey(...)`.
    let key: String

    /// Anzeige-Form der französischen Vokabel (mit Original-Groß-/
    /// Kleinschreibung, getrimmt).
    var displayFrench: String

    /// Anzeige-Form der deutschen Vokabel.
    var displayGerman: String

    /// `.words` oder `.phrases` — die **einzigen** Werte, die `CardType`
    /// in diesem Projekt kennt (nicht Nomen/Verb/Adjektiv, das lebt im
    /// `VocabularyItem.wordClass: String?`).
    var cardType: CardType

    /// Summe aller richtig beantworteten Versuche über **alle** Module
    /// hinweg (Karteikarten, Training, Verbformen, Quiz).
    var correctCount: Int

    /// Summe aller falsch beantworteten Versuche.
    var wrongCount: Int

    /// Zeitpunkt des zuletzt eingegangenen Signals — nach `Date()`
    /// sortiert liefert der Detail-Screen „was wurde zuletzt geübt".
    var lastSeen: Date

    /// **2026-08-04** — Serie ununterbrochen richtiger Antworten, über
    /// **alle** Module hinweg (nicht auf eine Übungsrunde beschränkt —
    /// „dreimal richtig in verschiedenen Übungen" laut User-Spec zählt
    /// genauso). Steigt bei jeder richtigen Antwort um 1, springt bei
    /// jeder falschen Antwort sofort auf 0 zurück. Treibt den primären
    /// Weg zu `.strong` (siehe `status`) — realistischer als die reine
    /// Gesamt-Trefferquote, die bei einer schlechten Vorgeschichte
    /// unrealistisch hohe „noch X richtig"-Zahlen produzierte (User-
    /// Report: „noch 12x" / „noch 13x" — das übt kein Schüler).
    ///
    /// `decodeIfPresent` mit Default 0 in `init(from:)`, damit bereits
    /// gespeicherte Einträge ohne dieses Feld nicht am Decodieren
    /// scheitern (Migration bestehender Nutzerdaten).
    var currentStreak: Int

    init(
        key: String,
        displayFrench: String,
        displayGerman: String,
        cardType: CardType,
        correctCount: Int,
        wrongCount: Int,
        lastSeen: Date,
        currentStreak: Int = 0
    ) {
        self.key = key
        self.displayFrench = displayFrench
        self.displayGerman = displayGerman
        self.cardType = cardType
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.lastSeen = lastSeen
        self.currentStreak = currentStreak
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        displayFrench = try container.decode(String.self, forKey: .displayFrench)
        displayGerman = try container.decode(String.self, forKey: .displayGerman)
        cardType = try container.decode(CardType.self, forKey: .cardType)
        correctCount = try container.decode(Int.self, forKey: .correctCount)
        wrongCount = try container.decode(Int.self, forKey: .wrongCount)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
    }

    var totalAttempts: Int { correctCount + wrongCount }

    /// Trefferquote als [0…1]-Wert. Bei `totalAttempts == 0` liefert 0,
    /// obwohl in dem Fall ohnehin die `.sparse`-Kategorie greift (siehe
    /// `status`) und die UI den Wert nicht als Prozentwert zeigt.
    var accuracy: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(correctCount) / Double(totalAttempts)
    }

    /// **2026-08-04** — Ab dieser Streak-Länge gilt ein Wort als „stark",
    /// unabhängig von der Gesamt-Vorgeschichte (User-Spec: „dreimal
    /// richtig hintereinander... dann passt das"). Ersetzt NICHT die
    /// alte Quoten-Schwelle (bleibt als zweiter, unabhängiger Weg
    /// erhalten — siehe `status`), sondern ergänzt sie um einen
    /// erreichbaren, vorwärtsgerichteten Pfad für Wörter mit
    /// schlechter Historie.
    static let strongStreakThreshold = 3

    var status: ItemLearningStatusClass {
        if currentStreak >= Self.strongStreakThreshold { return .strong }
        guard totalAttempts >= 3 else { return .sparse }
        if totalAttempts >= 5 && accuracy >= 0.8 {
            return .strong
        }
        if totalAttempts >= 5 && accuracy < 0.6 {
            return .needsWork
        }
        return .learning
    }

    /// **2026-08-04** — Wie oft der User ab jetzt **hintereinander richtig**
    /// antworten müsste, damit das Wort zu `.strong` wird. Nimmt den
    /// SCHNELLEREN der beiden unabhängigen Wege zu `.strong`:
    ///   • Streak-Pfad: `strongStreakThreshold - currentStreak` — dank
    ///     des Caps oben nie größer als `strongStreakThreshold` (User-
    ///     Spec „maximal fünfmal in Folge ist das Allerhöchste" ist damit
    ///     strukturell erfüllt, nicht nur in der Anzeige gedeckelt).
    ///   • Quoten-Pfad: die alte Herleitung aus der 80-%-Schwelle — bei
    ///     einem Wort, das schon nah an 80 % liegt, kann das sogar
    ///     kleiner sein als der Streak-Pfad.
    var remainingCorrectForStrong: Int {
        guard status != .strong else { return 0 }
        let byStreak = max(0, Self.strongStreakThreshold - currentStreak)
        let byAccuracy = max(0, 4 * totalAttempts - 5 * correctCount, 5 - totalAttempts)
        return min(byStreak, byAccuracy)
    }
}
