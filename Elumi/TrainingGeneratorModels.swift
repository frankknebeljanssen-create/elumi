import Foundation

// MARK: - ⚠️ DEPRECATED — Removal-Backlog
//
// **2026-04-30, Branch `feature/training-session-flow`, Stufe 1**:
// Datenstrukturen für den dramaturgischen `TrainingGenerator`-Pfad —
// mit der Chain-Builder-Architektur obsolet. `TrainingExerciseType` /
// `TrainingFocus` / `TrainingBlock` / `GeneratedTrainingSession`
// werden ausschließlich in den 3 Generator-Files referenziert
// (verifiziert 2026-04-30).
//
// Removal als gemeinsamer Backlog-Item mit `TrainingGenerator.swift`
// und `TrainingGeneratorStore.swift` nach Merge des Chain-Branches.

/// **Training-Generator V1** (Phase 8) — datenstrukturelle Basis für den
/// neuen Elumi-Training-Modus. Jede Session besteht aus 2–4
/// `TrainingBlock`-Einheiten mit klarer Dramaturgie (Warmup → Kern →
/// Challenge → optional Wiederholung). Die eigentliche Logik, die aus
/// Dauer + Fokus eine Session baut, lebt in `TrainingGenerator`.
///
/// Designprinzip: das Modell ist bewusst **flach & Codable**, damit die
/// zuletzt generierte Session ohne Schema-Migration in UserDefaults
/// gespeichert werden kann und sich später leicht durch echte Progress-
/// Signale erweitern lässt (`metadata`-Bag bleibt absichtlich offen).

/// Konkrete Übungstypen, die der Generator in Blöcke einbauen darf.
/// **Nur Typen, die im App-Modul-Set heute verfügbar sind** — für
/// spätere Ausbaustufen (z. B. echtes Matching, Schreib-Mode) ist die
/// Enum-Struktur offen.
enum TrainingExerciseType: String, Codable, CaseIterable, Identifiable {
    case warmup
    case flashcards
    case quiz
    case speed
    case articles
    case accents
    case writing
    case match
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmup:     return "Warmup"
        case .flashcards: return "Karteikarten"
        case .quiz:       return "Quiz"
        case .speed:      return "Speed Round"
        case .articles:   return "Artikel-Fokus"
        case .accents:    return "Akzent-Training"
        case .writing:    return "Schreibübung"
        case .match:      return "Matching"
        case .review:     return "Wiederholung"
        }
    }

    var subtitle: String {
        switch self {
        case .warmup:     return "Schneller Einstieg mit bekannten Wörtern"
        case .flashcards: return "Karten durchspielen und festigen"
        case .quiz:       return "Multiple-Choice-Fragen beantworten"
        case .speed:      return "Reagiere schnell und sammle Treffer"
        case .articles:   return "Trainiere die richtigen Artikel"
        case .accents:    return "Akzente sauber setzen"
        case .writing:    return "Tippen & schreiben zur Festigung"
        case .match:      return "Paare zuordnen"
        case .review:     return "Was zuletzt wackelte"
        }
    }

    var systemImage: String {
        switch self {
        case .warmup:     return "flame.fill"
        case .flashcards: return "rectangle.stack.fill"
        case .quiz:       return "questionmark.bubble.fill"
        case .speed:      return "bolt.fill"
        case .articles:   return "textformat.abc"
        case .accents:    return "character.textbox"
        case .writing:    return "pencil"
        case .match:      return "arrow.triangle.2.circlepath"
        case .review:     return "arrow.counterclockwise"
        }
    }

    /// **V1-Anschlussfähigkeit**: Welche Typen der Generator heute
    /// einbauen darf, unabhängig davon ob Navigation am Ende wirklich
    /// funktioniert. `match` und `writing` sind vorbereitet, aber noch
    /// nicht voll integriert — sie dürfen in Sessions auftauchen,
    /// werden aber im Launcher (späterer Ausbau) als Stub behandelt.
    static var generatorPoolV1: [TrainingExerciseType] {
        [.warmup, .flashcards, .quiz, .speed, .articles, .accents, .review]
    }
}

/// Fokus-Auswahl im Setup-Screen. V1 hat nur `mixed` voll aktiv; die
/// anderen Optionen sind strukturell angelegt, damit spätere Ausbaustufen
/// sie mit echter Logik füllen können ohne die View anzupassen.
enum TrainingFocus: String, Codable, CaseIterable, Identifiable {
    case mixed
    case review
    case playful
    case difficult
    case articles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed:     return "Gemischt"
        case .review:    return "Wiederholen"
        case .playful:   return "Schnell & spielerisch"
        case .difficult: return "Schwierige Wörter"
        case .articles:  return "Artikel & Formen"
        }
    }

    var systemImage: String {
        switch self {
        case .mixed:     return "sparkles"
        case .review:    return "arrow.counterclockwise"
        case .playful:   return "bolt.fill"
        case .difficult: return "flame.fill"
        case .articles:  return "textformat.abc"
        }
    }

    /// V1: **nur** `mixed` wird vom Generator voll bedient. Die
    /// anderen Fokus-Typen bekommen eine neutrale Variante des
    /// Mixed-Generators zurück, damit der Flow funktioniert — aber
    /// optisch sind sie im Setup-Screen als „bald"-Optionen markiert.
    var isFullySupportedV1: Bool {
        self == .mixed
    }
}

/// Einzelner Trainings-Block in einer generierten Session.
struct TrainingBlock: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let durationMinutes: Int
    let exerciseType: TrainingExerciseType
    /// Intensität 1…3 — 1 leicht, 2 normal, 3 anspruchsvoll. Aktuell
    /// nur als Signal für die UI (Stern-Anzahl auf der Block-Card
    /// ggf. später); Generator V1 setzt den Wert aus einfachen Regeln.
    let intensity: Int

    init(
        id: UUID = UUID(),
        title: String? = nil,
        subtitle: String? = nil,
        durationMinutes: Int,
        exerciseType: TrainingExerciseType,
        intensity: Int = 1
    ) {
        self.id = id
        self.title = title ?? exerciseType.title
        self.subtitle = subtitle ?? exerciseType.subtitle
        self.durationMinutes = durationMinutes
        self.exerciseType = exerciseType
        self.intensity = max(1, min(3, intensity))
    }
}

/// Komplette Session aus mehreren Blöcken.
struct GeneratedTrainingSession: Codable, Identifiable, Equatable {
    let id: UUID
    var blocks: [TrainingBlock]
    var totalDurationMinutes: Int
    var focus: TrainingFocus
    var createdAt: Date

    init(
        id: UUID = UUID(),
        blocks: [TrainingBlock],
        totalDurationMinutes: Int,
        focus: TrainingFocus,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.blocks = blocks
        self.totalDurationMinutes = totalDurationMinutes
        self.focus = focus
        self.createdAt = createdAt
    }
}
