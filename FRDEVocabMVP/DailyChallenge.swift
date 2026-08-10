import Foundation

/// Modell einer Tagesaufgabe.
///
/// Phase-5-Retention: genau **eine** Challenge pro Tag, einfach erfüllbar,
/// automatisch generiert. Nach Abschluss gibt es einen klaren Reward
/// (XP + Credit) und der Streak rückt vor.
///
/// Persistenz: `Codable`, wird vom `DailyChallengeStore` als JSON in
/// UserDefaults abgelegt. Der `dayIndex` entscheidet beim App-Start, ob die
/// Challenge noch aktuell ist oder ob eine neue generiert werden muss.
struct DailyChallenge: Codable, Equatable, Identifiable {
    let id: UUID
    /// 6-Uhr-Rollover-Index (siehe `GamificationConfig.currentDayIndex`).
    let dayIndex: Int
    let type: DailyChallengeType
    /// Ziel-Wert der Challenge — kommt bei Erstellung aus `type.defaultTarget`,
    /// wird in einem eigenen Feld gehalten, damit spätere Tuning-Varianten
    /// (z. B. progressive Schwellen) ohne Modellbruch möglich sind.
    let target: Int
    var currentProgress: Int
    var status: DailyChallengeStatus
    let reward: DailyChallengeReward
    var completedAt: Date?

    /// 0…1 — normalisierter Fortschritt, für Progress-Bars in der UI.
    var normalizedProgress: Double {
        guard target > 0 else { return status == .done ? 1.0 : 0.0 }
        return min(1.0, Double(currentProgress) / Double(target))
    }

    /// `true`, wenn die Challenge vollständig erfüllt wurde.
    var isCompleted: Bool { status == .done }
}

/// Zustandsmaschine der Challenge.
enum DailyChallengeStatus: String, Codable {
    case open          // Noch kein Fortschritt gemacht
    case inProgress    // Mindestens ein Fortschritts-Tick passiert
    case done          // Ziel erreicht, Reward wurde vergeben
}

/// Challenge-Typen (V1: drei einfache Varianten, damit das System schlank
/// bleibt und jede Aufgabe innerhalb einer normalen Lern-Session erfüllbar ist).
///
/// Erweiterbar ohne Modellbruch: neue Cases hinzufügen und einen
/// `progressIncrement` + Default-Target implementieren.
enum DailyChallengeType: Codable, Equatable, Hashable {
    /// „Beantworte N Fragen" — zählt richtige + falsche Antworten.
    case answers(target: Int)

    /// „Schließe 1 Session ab" — erfüllt durch *eine* Session, die die
    /// Mindestschwelle ihres Moduls erreicht.
    case completeSession

    /// „Spiele 1 Speed Round" — nur Speed-Round-Sessions zählen.
    case speedRound

    /// Nutzer-sichtbarer Titel (Home, Progress Hub).
    var title: String {
        switch self {
        case .answers(let t): return "Beantworte \(t) Fragen"
        case .completeSession: return "Schließe 1 Session ab"
        case .speedRound: return "Spiele 1 Speed Round"
        }
    }

    /// SF-Symbol für Challenge-Chips/Cards.
    var systemImage: String {
        switch self {
        case .answers: return "text.bubble.fill"
        case .completeSession: return "checkmark.seal.fill"
        case .speedRound: return "hare.fill"
        }
    }

    /// Standard-Ziel-Wert beim Generieren.
    var defaultTarget: Int {
        switch self {
        case .answers(let t): return t
        case .completeSession: return 1
        case .speedRound: return 1
        }
    }

    /// Fortschritts-Beitrag einer abgeschlossenen Session zu dieser Challenge.
    /// Zentrale Stelle, damit Logik **nicht** im Store verteilt liegt.
    func progressIncrement(for session: LearningSession) -> Int {
        switch self {
        case .answers:
            // Jede beantwortete Einheit zählt — egal ob richtig oder falsch.
            return session.correctCount + session.wrongCount
        case .completeSession:
            return session.meetsMinimumThreshold ? 1 : 0
        case .speedRound:
            return (session.origin == .speedRound && session.meetsMinimumThreshold) ? 1 : 0
        }
    }
}

/// Paket, das bei Completion ausgeschüttet wird.
struct DailyChallengeReward: Codable, Equatable {
    let xp: Int
    let credits: Int
}

/// Outcome, das der Store zurückgibt, wenn die Challenge **in diesem Call**
/// abgeschlossen wurde. Trägt die vergebenen Werte, damit das aufrufende
/// `ProgressService` sie in sein `SessionRewardOutcome` falten und die UI
/// (SessionSummary) sie sofort anzeigen kann.
///
/// **2026-08-08** — trägt bewusst KEINE Streak-Info mehr. Der Streak ist
/// vom vollen Tagesziel entkoppelt (siehe `GamificationConfig.streakMiniSessionThreshold`,
/// `ProgressStore.advanceStreakIfNeeded`) — die Daily Challenge ist nur
/// noch eine von mehreren Belohnungsquellen, kein Streak-Gate mehr.
struct DailyChallengeCompletionOutcome: Equatable {
    let xpAwarded: Int
    let creditsAwarded: Int
}
