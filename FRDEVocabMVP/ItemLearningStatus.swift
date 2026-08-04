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

    var totalAttempts: Int { correctCount + wrongCount }

    /// Trefferquote als [0…1]-Wert. Bei `totalAttempts == 0` liefert 0,
    /// obwohl in dem Fall ohnehin die `.sparse`-Kategorie greift (siehe
    /// `status`) und die UI den Wert nicht als Prozentwert zeigt.
    var accuracy: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(correctCount) / Double(totalAttempts)
    }

    var status: ItemLearningStatusClass {
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
    /// antworten müsste, damit das Wort zu `.strong` wird (User-Spec: „nur
    /// die Anzahl Versuche sagt mir nichts"). Nimmt an, dass ab jetzt kein
    /// weiterer Fehler passiert — ist also die bestmögliche Prognose, kein
    /// Durchschnitt über zukünftiges Rateverhalten.
    ///
    /// Herleitung aus der `.strong`-Schwelle (`totalAttempts >= 5 &&
    /// accuracy >= 0.8`): gesucht ist das kleinste `k >= 0` mit
    /// `(correctCount + k) / (totalAttempts + k) >= 0.8`. Nach `k`
    /// aufgelöst (Multiplikation mit 5 macht 0.8 → 4, ganzzahlig, keine
    /// Rundung nötig): `k >= 4 * totalAttempts - 5 * correctCount`.
    /// Kombiniert mit der Mindest-Versuchszahl (`totalAttempts + k >= 5`)
    /// ergibt sich das Maximum aus beiden Bedingungen.
    var remainingCorrectForStrong: Int {
        guard status != .strong else { return 0 }
        let byAccuracy = 4 * totalAttempts - 5 * correctCount
        let byMinAttempts = 5 - totalAttempts
        return max(0, byAccuracy, byMinAttempts)
    }
}
