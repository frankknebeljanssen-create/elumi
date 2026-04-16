import Foundation

/// Lokales, gerätegebundenes Nutzerprofil.
///
/// Bewusst minimal gehalten — trägt nur Identitäts- und Ansprache-Felder,
/// **keine** Fortschrittsdaten und **keine** Auth-Infos. Langfristig ohne
/// Breaking-Change erweiterbar (Cloud-Sync, Multi-Profile, Avatar-Editor,
/// Badges, …).
///
/// Explizit *nicht* enthalten — saubere Trennung der Verantwortungen:
/// • Fortschritt (XP, Credits, Streak, Level) → `ProgressStore`
/// • App-Präferenzen (Sound, Direction, …) → bestehende `@AppStorage`-Keys
/// • Auth/Account (existiert noch nicht, kommt später als eigener Store)
struct LearnerProfile: Codable, Equatable, Identifiable {
    /// Stabile UUID — einmalig lokal generiert, überlebt Namensänderungen.
    /// Relevant für späteren Cloud-Sync (Gerät-zu-Profil-Mapping).
    var id: UUID

    /// Anzeigename — Basis für Begrüßung, Avatar-Initialen, Personalisierung.
    var displayName: String

    /// Optional: freigewähltes persönliches Lernziel (Onboarding Schritt 2).
    var learningGoal: LearningGoal?

    /// Erstelldatum — für spätere „Seit X Tagen bei Elumi"-Moments nutzbar.
    var createdAt: Date

    /// Letzter App-Start mit aktiver Nutzung. Optional bis erstes Update.
    var lastActiveAt: Date?

    // MARK: - Prepared-but-optional Felder

    // Strukturell vorbereitet, in V1 noch nicht überall konsumiert — so
    // können wir später ohne Migrations-Schema-Bruch erweitern. Jedes Feld
    // hat einen sinnvollen Default, damit Codable robust bleibt.

    /// Präferierte Lernmodi (aus Onboarding oder späterem Nutzer-Tuning).
    var preferredModes: [PreferredMode]

    /// Ob der User personalisiertes Feedback sehen möchte. Default: true.
    /// Gate für spätere Feedback-Texte (Streak-Banner, Session-Summary, …).
    var showPersonalizedFeedback: Bool

    /// Avatar-Stil-Identifier — für spätere Varianten (Elumi-Figur, Foto, …)
    /// reserviert. V1: nur `initials`.
    var avatarStyle: AvatarStyle

    init(
        id: UUID = UUID(),
        displayName: String,
        learningGoal: LearningGoal? = nil,
        createdAt: Date = Date(),
        lastActiveAt: Date? = nil,
        preferredModes: [PreferredMode] = [],
        showPersonalizedFeedback: Bool = true,
        avatarStyle: AvatarStyle = .initials
    ) {
        self.id = id
        self.displayName = displayName
        self.learningGoal = learningGoal
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.preferredModes = preferredModes
        self.showPersonalizedFeedback = showPersonalizedFeedback
        self.avatarStyle = avatarStyle
    }

    // MARK: - Codable robustness
    //
    // Decodes mit Defaults, falls das JSON aus einer älteren Version kommt,
    // in der noch nicht alle Felder existierten (Forward-Compat beim Update).

    enum CodingKeys: String, CodingKey {
        case id, displayName, learningGoal, createdAt, lastActiveAt
        case preferredModes, showPersonalizedFeedback, avatarStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName = try c.decode(String.self, forKey: .displayName)
        learningGoal = try c.decodeIfPresent(LearningGoal.self, forKey: .learningGoal)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt)
        preferredModes = try c.decodeIfPresent([PreferredMode].self, forKey: .preferredModes) ?? []
        showPersonalizedFeedback = try c.decodeIfPresent(Bool.self, forKey: .showPersonalizedFeedback) ?? true
        avatarStyle = try c.decodeIfPresent(AvatarStyle.self, forKey: .avatarStyle) ?? .initials
    }
}

/// Lernziel-Auswahl beim Onboarding — „Was möchtest du mit Elumi
/// am meisten üben?"
enum LearningGoal: String, Codable, CaseIterable, Identifiable {
    case vocabulary = "vocabulary"
    case verbs = "verbs"
    case articles = "articles"
    case regularPractice = "regular_practice"

    var id: String { rawValue }

    /// Anzeigename in Onboarding & Profilansicht.
    var title: String {
        switch self {
        case .vocabulary: return "Vokabeln sicher lernen"
        case .verbs: return "Verben besser können"
        case .articles: return "Artikel trainieren"
        case .regularPractice: return "Einfach regelmäßig üben"
        }
    }

    /// SF-Symbol für Onboarding-Karte und Profil-Chip.
    var systemImage: String {
        switch self {
        case .vocabulary: return "character.book.closed.fill"
        case .verbs: return "text.line.first.and.arrowtriangle.forward"
        case .articles: return "textformat.abc"
        case .regularPractice: return "calendar"
        }
    }
}

/// Präferierte Lernmodi — vorbereitend strukturiert. Mapping auf
/// `AppScreen`-Cases passiert bewusst im Call-Site (Home, Routing),
/// damit das Modell Route-agnostisch bleibt.
enum PreferredMode: String, Codable, CaseIterable {
    case vocabulary
    case verbs
    case articles
    case flashcards
    case quiz
    case verbforms
}

/// Avatar-Darstellungsvariante. V1 rendert nur `initials`; `elumi`
/// und weitere Varianten sind als Enum-Case vorbereitet.
enum AvatarStyle: String, Codable, CaseIterable {
    case initials
    case elumi
}
