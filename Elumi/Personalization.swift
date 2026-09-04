import Foundation

/// Zentrale, *minimale* Personalisierungs-Logik. Alle namens-abhängigen
/// Strings kommen von hier — **nicht** verteilt in einzelnen Views.
///
/// Designprinzip: *zurückhaltend*. Der Name erscheint nicht in jeder
/// zweiten Zeile, sondern nur dort, wo er echten Mehrwert liefert
/// (Home-Begrüßung, bedeutungsvolle Meilensteine). Für Session-interne
/// Mikrotexte bleibt die App weiterhin namens-neutral — das wirkt
/// hochwertiger als exzessive Ansprache.
///
/// Alle Funktionen akzeptieren `String?` und haben einen sauberen
/// Fallback für den Fall, dass noch kein Name gesetzt ist. Views müssen
/// keinen eigenen nil-/trim-Check machen.
///
/// Neue personalisierte Stellen bitte als weitere `static`-Funktion
/// hier anhängen, nicht inline in einer View.
enum Personalization {

    // MARK: - Home

    /// Home-Screen-Begrüßung. Zeigt „Salut <Name> !", wenn ein Name gesetzt
    /// ist — sonst ein neutrales „Salut !".
    static func homeGreeting(for name: String?) -> String {
        guard let trimmed = sanitize(name) else {
            return "Salut !"
        }
        return "Salut \(trimmed) !"
    }

    /// Leiser Sekundärtext unter der Begrüßung. Optional einsetzbar, wenn
    /// Views eine zweite Zeile möchten — V1 nutzt das noch nicht überall,
    /// die Hook ist aber da.
    static func homeSubtitle(for name: String?) -> String {
        guard sanitize(name) != nil else {
            return "Schön, dass du da bist."
        }
        return "Schön, dass du wieder da bist."
    }

    // MARK: - Progress Hub

    /// Intro-Zeile unter dem „Fortschritt"-Titel im Progress Hub.
    /// Leicht personalisiert, aber nicht kitschig — Name taucht genau an
    /// dieser einen Stelle auf, der Rest des Screens bleibt namens-neutral.
    static func progressHubIntro(for name: String?) -> String {
        guard let trimmed = sanitize(name) else {
            return "Dein Fortschritt auf einen Blick."
        }
        return "Das ist dein Stand, \(trimmed)."
    }

    // MARK: - Session-Feedback (prepared for later use)

    /// Kurze Erfolgsmeldung nach einer Session — z. B. für Summary-Cards.
    /// Noch nicht überall aktiv, aber die Stelle ist strukturell vorbereitet.
    static func successMessage(for name: String?) -> String {
        guard let trimmed = sanitize(name) else {
            return "Stark gemacht!"
        }
        return "Stark gemacht, \(trimmed)!"
    }

    /// Streak-Meilenstein — z. B. für zukünftige Streak-Banner.
    static func streakMessage(for name: String?, days: Int) -> String {
        let dayLabel = "Tag\(days == 1 ? "" : "e") in Folge"
        guard let trimmed = sanitize(name) else {
            return "\(days) \(dayLabel) — weiter so!"
        }
        return "\(trimmed), \(days) \(dayLabel) — weiter so!"
    }

    /// Quiz-Intro — z. B. für Quiz-Setup-Screen.
    static func quizIntro(for name: String?) -> String {
        guard let trimmed = sanitize(name) else {
            return "Bereit für eine neue Runde?"
        }
        return "Bereit für eine neue Runde, \(trimmed)?"
    }

    // MARK: - Helpers

    /// Normalisiert einen Namens-Input — trimmt Whitespace, gibt `nil` für
    /// leere Strings zurück. Nur intern, damit jede Funktion konsistent
    /// trimmt.
    private static func sanitize(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }
}
