import Foundation

// MARK: - Akzent-Typen

/// Die Grundformen, die das MVP-Modul abdeckt. Zusätzliche Typen (à, ù,
/// ë, ï, ô …) sind strukturell vorgesehen, werden aber in der ersten
/// Version nicht aktiv priorisiert.
enum AccentType: String, Codable, Hashable, CaseIterable {
    case aigu          // é
    case grave         // è (primär), auch à, ù
    case circonflexe   // ê (primär), auch â, î, ô, û
    case cedille       // ç
    case trema         // ë, ï, ü — vorbereitet, MVP nicht aktiv
    case none          // Kein Akzent (für Distraktoren relevant)

    /// Kurzer deutscher Name für UI/Feedback.
    var germanLabel: String {
        switch self {
        case .aigu:        return "Accent aigu"
        case .grave:       return "Accent grave"
        case .circonflexe: return "Accent circonflexe"
        case .cedille:     return "Cédille"
        case .trema:       return "Tréma"
        case .none:        return "Ohne Akzent"
        }
    }

    /// Repräsentatives Zeichen (z. B. für Badges / Lern-Karten).
    var representativeGlyph: String {
        switch self {
        case .aigu:        return "é"
        case .grave:       return "è"
        case .circonflexe: return "ê"
        case .cedille:     return "ç"
        case .trema:       return "ë"
        case .none:        return "e"
        }
    }

    /// Nur die MVP-aktiven Typen. Wird im UI für Lern-Karten und
    /// Distraktor-Auswahl genutzt.
    static var mvpActive: [AccentType] {
        [.aigu, .grave, .circonflexe, .cedille]
    }
}

// MARK: - Schwierigkeitsstufen

enum AccentDifficulty: String, Codable, Hashable {
    case easy
    case medium
    case hard
}

// MARK: - Ein einzelnes Aufgabe-Item

/// Generisches Aufgaben-Modell für alle drei MVP-Übungstypen.
/// Je nach `kind` werden `options` (Variante A) oder `letterVariants`
/// (Variante B) konsumiert. So bleibt die Session-Engine unabhängig
/// von der konkreten Übungsform.
struct AccentExercise: Identifiable, Hashable, Codable {
    let id: UUID
    let kind: Kind
    let difficulty: AccentDifficulty

    /// Ausgangsform (z. B. "ecole", "garcon"). Das, was der Nutzer sieht.
    let baseWord: String
    /// Korrekte Form (z. B. "école", "garçon").
    let correctWord: String
    /// Haupt-Akzenttyp der Aufgabe (bestimmt Feedback-Text, evtl. Badge).
    let accentType: AccentType
    /// Position des betroffenen Zeichens in `baseWord` — für Variante B
    /// (Buchstabe antippen). Für Variante A optional.
    let targetCharacterIndex: Int?
    /// Plausible Distraktoren (ohne die korrekte Form). Max. 3 für Stay-
    /// Tight-UI. Nur bei Variante A relevant.
    let options: [String]
    /// Zeichen-Varianten für Variante B (z. B. ["e", "é", "è", "ê"]).
    let letterVariants: [String]
    /// Optionale kurze Erklärung — wird nach falscher Antwort gezeigt.
    let explanation: String?

    enum Kind: String, Codable, Hashable {
        /// Variante A — der Nutzer wählt aus mehreren komplett
        /// geschriebenen Wörtern die richtige Version.
        case pickCorrectWord
        /// Variante B — der Nutzer wählt für das betroffene Zeichen die
        /// richtige Akzent-Form (z. B. e / é / è / ê oder c / ç).
        case chooseAccent
        /// Variante C (V3, Audio) — der Nutzer **hört** das Wort via TTS
        /// und wählt aus mehreren Schreibweisen die korrekte aus. UI
        /// analog zu pickCorrectWord, nur mit Play-Button statt sichtbarem
        /// Wort.
        case listenAndPick

        /// Hat diese Kind-Variante eine Audio-Komponente? Wird fürs
        /// Result-Screen-Breakdown (visuell vs. Audio) genutzt.
        var isAudio: Bool {
            self == .listenAndPick
        }
    }

    /// Die Länge der Optionen zur Laufzeit — wir ordnen A-Optionen
    /// zufällig an, ohne das Model zu mutieren.
    func shuffledOptions() -> [String] {
        var all = options + [correctWord]
        all.shuffle()
        return all
    }

    /// Variante B: zufällig gemischt. Die korrekte Variante steckt
    /// bereits in `letterVariants` drin.
    func shuffledLetterVariants() -> [String] {
        var all = letterVariants
        all.shuffle()
        return all
    }
}

// MARK: - Einzel-Antwort (fürs Result)

struct AccentAnswerRecord: Hashable, Codable {
    let exerciseID: UUID
    /// Korrekter Akzenttyp dieser Aufgabe.
    let accentType: AccentType
    let wasCorrect: Bool
    /// Der Akzenttyp, den der Nutzer **stattdessen** gewählt hat, falls
    /// die Antwort falsch war — also die Verwechslung. Für „é statt è"-
    /// Analysen wichtig. Nil wenn Antwort richtig oder Typ nicht
    /// eindeutig ableitbar.
    let chosenWrongAccentType: AccentType?
    /// War die Aufgabe Audio-basiert? Fürs Result-Screen-Split
    /// (visuell vs. Audio).
    let isAudioExercise: Bool
}

// MARK: - Session-Modus

enum AccentMode: String, Codable, Hashable {
    case lernen
    case uben
    /// Der zeitbegrenzte Kurzmodus. Historisch hieß der Case `challenge` —
    /// appweit nutzen alle anderen Module den Begriff „Speed Round", und
    /// Akzente ist seit der Vereinheitlichung Teil derselben Mechanik
    /// (gleicher Timer, gleiche Summary, gleicher Reward-Pfad). Der
    /// `rawValue` bleibt absichtlich `"challenge"`, damit persistierte
    /// Launch-Contexts aus Bestandsnutzer-Sessions weiter lesbar sind.
    case speedRound = "challenge"

    var title: String {
        switch self {
        case .lernen:     return "Lernen"
        case .uben:       return "Üben"
        // Zentrale Terminologie — ein späterer globaler Rename läuft
        // ausschließlich über `SpeedRoundTerminology.name`, nicht hier.
        case .speedRound: return SpeedRoundTerminology.name
        }
    }

    var subtitle: String {
        switch self {
        case .lernen:     return "Akzente entspannt kennenlernen"
        case .uben:       return "Trainieren mit direktem Feedback"
        case .speedRound: return "Gemischte Kurz-Session"
        }
    }

    /// Anzahl Aufgaben — nur für Üben / Speed Round relevant.
    /// Speed Round läuft als zeitbegrenzter Kurzmodus: wir generieren
    /// großzügig viele Exercises, damit der Timer (nicht die Queue) die
    /// Session beendet. Typisch schafft ein User 15–25 Aufgaben in einer
    /// 45-Sekunden-Runde — bei abweichender Einstellung skaliert
    /// `AccentContentBuilder` die Seed-Länge implizit mit.
    var sessionLength: Int {
        switch self {
        case .lernen:     return 0
        case .uben:       return 10
        case .speedRound: return 35
        }
    }

    /// Welche Aufgaben-Kinds darf die Session generieren?
    /// V3: Audio (`.listenAndPick`) läuft als dritter Exercise-Type in
    /// Üben und Speed Round mit — ca. 25–30 % der Session sind Audio.
    var allowedKinds: [AccentExercise.Kind] {
        switch self {
        case .lernen:     return [.pickCorrectWord]
        case .uben:       return [.pickCorrectWord, .chooseAccent, .listenAndPick]
        case .speedRound: return [.pickCorrectWord, .chooseAccent, .listenAndPick]
        }
    }
}

// MARK: - Session-Finish Payload

/// Alles, was der `onFinish`-Callback von der Session an den Entry-View
/// zurückgibt — gebündelt damit spätere Erweiterungen die Signatur
/// nicht brechen. Enthält genug Daten für ProgressService, Adaptive-
/// Store-Update und den Result-Screen-Breakdown.
struct AccentSessionFinishPayload {
    let correct: Int
    let total: Int
    let breakdown: [(type: AccentType, correct: Int, total: Int)]
    let audioVisualSplit: (audioCorrect: Int, audioTotal: Int, visualCorrect: Int, visualTotal: Int)
    let answerRecords: [AccentAnswerRecord]
}

// MARK: - Launch Context

/// Wird vom Home-Tile durchgereicht. `preferredListID` bindet den Akzent-
/// Flow an eine konkrete Nutzer-Liste, `shouldAutoStart` startet (falls
/// gesetzt) direkt einen Modus — für MVP nicht genutzt, strukturell
/// vorbereitet wie bei Quiz/Train.
struct AccentsLaunchContext: Hashable {
    let preferredListID: UUID?
    let preferredMode: AccentMode?
    let shouldAutoStart: Bool
    /// **Stufe 1 (2026-04-30, Branch `feature/training-session-flow`)**:
    /// optionaler Chain-Context, gesetzt wenn Akzente als Step einer
    /// auto-verketteten Trainings-Sequenz gestartet wird. Stufe 2 nutzt
    /// das Feld im Done-CTA zum Weiter-Springen.
    let chainContext: TrainingChainContext?

    init(
        preferredListID: UUID? = nil,
        preferredMode: AccentMode? = nil,
        shouldAutoStart: Bool = false,
        chainContext: TrainingChainContext? = nil
    ) {
        self.preferredListID = preferredListID
        self.preferredMode = preferredMode
        self.shouldAutoStart = shouldAutoStart
        self.chainContext = chainContext
    }
}
