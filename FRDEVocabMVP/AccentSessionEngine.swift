import Foundation
import Combine

/// Zentraler State für eine laufende Akzent-Session (Üben / Speed Round).
/// Hält die Exercise-Queue, den Fortschritt, Antwort-Records und das
/// aktuelle Feedback. Die UI (`AccentsSessionView`) observed diese
/// Klasse und rendert entsprechend.
///
/// V3-Erweiterungen:
///   • Wrong-Type-Detection — wenn der User falsch antwortet, wird
///     versucht den **gewählten falschen** Akzenttyp zu erkennen (für
///     „é statt è"-Analysen und die adaptive Priorisierung).
///   • Soft Re-Insertion — falsch beantwortete Aufgaben werden leicht
///     verändert (Kind gewechselt) später in derselben Session wieder
///     eingemischt. Nicht sofort, sondern mit 2–3 Aufgaben Abstand.
///   • Audio-Kind — `.listenAndPick` wird wie `.pickCorrectWord` bewertet,
///     aber mit isAudioExercise-Flag für das Result-Split-Reporting.
@MainActor
final class AccentSessionEngine: ObservableObject {

    // MARK: - Konstruktion

    let mode: AccentMode

    /// Aktuelle Warteschlange — wird durch Soft-Re-Insertion während der
    /// Session verändert (falsche Aufgaben wandern weiter hinten wieder
    /// rein). Daher nicht mehr `let`.
    private var exercises: [AccentExercise]

    /// Wie oft darf eine einzelne Exercise maximal re-inserted werden?
    /// Ein Schutz gegen unbegrenztes Wiederholen bei wiederholt
    /// falschen Antworten.
    private static let maxReinsertionsPerExercise = 1

    /// Wie viele Aufgaben soll die re-inserted Variante vom Original
    /// Abstand haben? 2 = „nach zwei anderen Aufgaben".
    private static let reinsertionOffset = 2

    /// Zähler pro Exercise-ID — wie oft wurde sie schon re-inserted.
    private var reinsertionCountByID: [UUID: Int] = [:]

    /// Liste-ID wird vom `AccentsEntryView` beim Start durchgereicht — wir
    /// brauchen sie nur für den Resume-Fingerprint (Listen-Wechsel verwirft
    /// einen alten Snapshot). `nil` für den Standard-Wörter-Fallback.
    private let resumeListID: UUID?

    init(mode: AccentMode, exercises: [AccentExercise], resumeListID: UUID? = nil) {
        self.mode = mode
        self.exercises = exercises
        self.totalCount = exercises.count
        self.resumeListID = resumeListID
    }

    /// Alternative Init-Variante für die Wiederherstellung aus einem
    /// Snapshot — übernimmt nicht nur die Queue, sondern auch Index,
    /// Antwortliste und Reinsertion-Tracking. Kommt vom
    /// `AccentsEntryView.startSession(mode: .uben)`-Flow, wenn ein
    /// kompatibler Snapshot gefunden wurde.
    convenience init(restoringFrom snapshot: AccentSessionResumeState, resumeListID: UUID?) {
        self.init(
            mode: AccentMode(rawValue: snapshot.modeRaw) ?? .uben,
            exercises: snapshot.exercises,
            resumeListID: resumeListID
        )
        var startIndex = max(0, min(snapshot.currentIndex, max(snapshot.exercises.count - 1, 0)))

        // Fall: User hat auf die aktuelle Aufgabe bereits geantwortet
        // (answerRecord liegt vor), die Session wurde im Feedback-State
        // geschlossen (vor `advance()`). Ohne diesen Bump würde der User
        // auf derselben Aufgabe landen und sie nochmals beantworten —
        // doppelter Record, verfälschte Statistik. Jump zum nächsten
        // Index, der noch keinen Record hat.
        let answeredIDs = Set(snapshot.answerRecords.map { $0.exerciseID })
        while startIndex < snapshot.exercises.count,
              answeredIDs.contains(snapshot.exercises[startIndex].id) {
            startIndex += 1
        }
        self.currentIndex = startIndex
        self.answerRecords = snapshot.answerRecords
        self.reinsertionCountByID = snapshot.reinsertionCountByID

        // Falls alle Aufgaben abgearbeitet sind → Session sofort beenden
        // (Snapshot war beim letzten Advance geschrieben worden, bevor der
        // User die App schloss).
        if self.currentIndex >= snapshot.exercises.count {
            self.isFinished = true
        }
    }

    // MARK: - Published State

    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var answerRecords: [AccentAnswerRecord] = []
    @Published var feedback: Feedback? = nil
    @Published private(set) var isFinished: Bool = false

    /// Die konkrete Antwort, die der User zuletzt ausgewählt hat — wird
    /// von der UI verwendet, um die **falsche** Auswahl rot zu markieren
    /// (und die korrekte parallel grün). Zurückgesetzt bei `advance()`.
    @Published private(set) var lastChosenAnswer: String? = nil

    // MARK: - Speed Round State (nur Speed Round-Modus)

    /// 3-2-1-Overlay-Wert. Nil = kein Overlay sichtbar. Wird beim
    /// Session-Start auf 3 gesetzt, runter bis 1, dann nil (Session
    /// beginnt). Mirror zum `speedCountdown` in anderen Modulen.
    @Published private(set) var speedCountdown: Int? = nil

    /// Verbleibende Sekunden im Speed-Round-Timer. Wird jede Sekunde
    /// dekrementiert, ab ≤5 s toggelt das Feedback-Beep, bei 0 wird
    /// die Session zwangs-beendet. Initialwert = globale Einstellung
    /// aus `SpeedRoundSettings` (Default `SpeedRoundDuration.defaultDuration`).
    @Published private(set) var speedRoundTimeRemaining: Int = SpeedRoundSettings.currentSeconds

    /// Gesamte Dauer dieser Speed-Round — auf Engine-Ebene festgehalten,
    /// damit die Timer-Bar im UI korrekt normalisieren kann (progress =
    /// remaining / totalSeconds). Wird beim Timer-Start gesetzt und
    /// bleibt während der Runde konstant, auch wenn der User die
    /// Settings mitten drin wechseln würde.
    @Published private(set) var speedRoundTotalSeconds: Int = SpeedRoundSettings.currentSeconds

    /// Ist der Speed-Round-Timer aktiv (d. h. läuft gerade herunter)?
    @Published private(set) var isSpeedRoundActive: Bool = false

    private var speedRoundTimer: Timer?

    // MARK: - Feedback

    struct Feedback: Equatable {
        let isCorrect: Bool
        let headline: String
        let detail: String?

        static let correctPhrases = ["Richtig!", "Genau!", "Stark!"]
    }

    // MARK: - Computed

    /// Aktuelles Exercise — falls die Session vorbei ist, nil.
    var currentExercise: AccentExercise? {
        guard currentIndex < exercises.count else { return nil }
        return exercises[currentIndex]
    }

    /// Fortschritt 0…1 für die Progress-Bar. Basiert auf der **dynamischen**
    /// Queue-Länge (Re-Insertions verlängern die Session minimal).
    var progress: Double {
        let total = max(totalCount, exercises.count)
        guard total > 0 else { return 0 }
        return Double(currentIndex) / Double(total)
    }

    /// Aktuelle Queue-Länge — nützlich fürs UI „X / Y"-Label.
    var currentTotal: Int { max(totalCount, exercises.count) }

    /// Anzahl der bisher richtig beantworteten Aufgaben.
    var correctCount: Int {
        answerRecords.filter { $0.wasCorrect }.count
    }

    // MARK: - Input

    /// Antwort vom User — egal ob Variante A (komplettes Wort), Variante
    /// B (Zeichen) oder Variante C (Audio-pick, intern wie A bewertet).
    func submitAnswer(_ answer: String) {
        guard let exercise = currentExercise, feedback == nil else { return }
        lastChosenAnswer = answer

        let isCorrect: Bool
        switch exercise.kind {
        case .pickCorrectWord, .listenAndPick:
            // Audio- und visuelle Pick-Varianten teilen die Bewertung —
            // der User wählt in beiden Fällen eine komplette Schreibweise.
            isCorrect = answer == exercise.correctWord
        case .chooseAccent:
            guard let idx = exercise.targetCharacterIndex,
                  idx >= 0, idx < exercise.correctWord.count else {
                isCorrect = false
                break
            }
            let correctChar = String(exercise.correctWord[exercise.correctWord.index(exercise.correctWord.startIndex, offsetBy: idx)])
            isCorrect = answer == correctChar
        }

        // Fehler-Klassifikation — nur bei falscher Antwort relevant.
        let chosenWrongType: AccentType? = isCorrect ? nil : inferWrongAccentType(from: answer, exercise: exercise)

        answerRecords.append(AccentAnswerRecord(
            exerciseID: exercise.id,
            accentType: exercise.accentType,
            wasCorrect: isCorrect,
            chosenWrongAccentType: chosenWrongType,
            isAudioExercise: exercise.kind.isAudio
        ))

        // Lernstatus-Signal — systemweit wie in Quiz/Training/Flashcards.
        // Akzente trackt auf Wort-Ebene: `french = correctWord`, german
        // bleibt leer (Accents fokussieren auf die Rechtschreibung, nicht
        // auf Übersetzung). Der canonical Key (french|german|cardType)
        // ist trotzdem eindeutig pro Akzent-Wort, sodass derselbe Eintrag
        // über mehrere Sessions hinweg aufaddiert wird.
        ItemLearningStatusRecorder.record(
            french: exercise.correctWord,
            german: "",
            cardType: .words,
            correct: isCorrect
        )

        if isCorrect {
            feedback = Feedback(
                isCorrect: true,
                headline: Feedback.correctPhrases.randomElement() ?? "Richtig!",
                detail: nil
            )
        } else {
            feedback = Feedback(
                isCorrect: false,
                headline: "Fast!",
                detail: exercise.explanation
            )
            // Soft Re-Insertion — gemerkte Aufgabe taucht ein paar
            // Aufgaben später wieder auf, damit der User die richtige
            // Lösung noch einmal aktiv produzieren kann.
            scheduleReinsertion(of: exercise)
        }
        // Nach jedem Answer-Record den Snapshot aktualisieren — damit
        // ein App-Kill zwischen Antwort-Tap und „Weiter"-Tap trotzdem
        // den aktuellen Antwort-Stand persistiert.
        persistResumeSnapshotIfEligible()
    }

    /// Weiter zur nächsten Aufgabe. Wenn keine mehr da → Session beenden.
    func advance() {
        feedback = nil
        lastChosenAnswer = nil
        if currentIndex + 1 >= exercises.count {
            isFinished = true
            // Session-Ende → Snapshot verwerfen, sonst würde der User
            // beim nächsten Setup in eine scheinbar „laufende" Runde
            // zurückgeworfen.
            AccentSessionResumeStore.clear()
        } else {
            currentIndex += 1
            // Neuer Index → Snapshot aktualisieren, damit ein Resume
            // exakt auf der nächsten ungesehenen Aufgabe landet.
            persistResumeSnapshotIfEligible()
        }
    }

    /// Speichert den aktuellen Session-Stand für spätere Wiederherstellung.
    /// Nur im **Üben-Modus** aktiv — Lernen hat keinen Queue-Fortschritt,
    /// Speed Round (Timer-Runde) würde durch Fortsetzen verfälscht.
    private func persistResumeSnapshotIfEligible() {
        guard mode == .uben else { return }
        guard !exercises.isEmpty else { return }
        let state = AccentSessionResumeState(
            modeRaw: mode.rawValue,
            selectedListID: resumeListID,
            exercises: exercises,
            currentIndex: currentIndex,
            answerRecords: answerRecords,
            reinsertionCountByID: reinsertionCountByID,
            configFingerprint: AccentSessionResumeStore.fingerprint(
                mode: mode,
                selectedListID: resumeListID
            ),
            lastUpdatedEpoch: Date().timeIntervalSince1970
        )
        // Debounced Background-Write — der Hot-Path (submitAnswer +
        // advance) blockiert den Main-Thread nicht mehr mit JSON-Encoding.
        AccentSessionResumeStore.scheduleSave(state)
    }

    /// Pro Akzenttyp: wie viele richtig / gesamt.
    /// Fürs Result-Screen-Breakdown.
    func breakdownByType() -> [(type: AccentType, correct: Int, total: Int)] {
        var counts: [AccentType: (correct: Int, total: Int)] = [:]
        for rec in answerRecords {
            var entry = counts[rec.accentType] ?? (0, 0)
            entry.total += 1
            if rec.wasCorrect { entry.correct += 1 }
            counts[rec.accentType] = entry
        }
        return counts.keys.sorted(by: { $0.rawValue < $1.rawValue }).compactMap { key in
            guard let val = counts[key] else { return nil }
            return (type: key, correct: val.correct, total: val.total)
        }
    }

    // MARK: - Speed Round Control

    /// Startet die 3-2-1-Intro-Sequenz und anschließend den Speed-Round-
    /// Timer (Dauer aus `SpeedRoundSettings`). Wird von der View beim
    /// Speed-Round-Start aufgerufen.
    /// Pattern 1:1 identisch zu `VerbformsSessionController.startSpeedRoundTimer`
    /// und dem Speed-Round-Path in `TrainingView+SessionFlow`.
    func startSpeedRound(feedbackPlayer: FeedbackPlayer) {
        speedCountdown = 3
        feedbackPlayer.playToggle()
        scheduleCountdownTick(after: 1.0) { [weak self] in
            self?.speedCountdown = 2
            feedbackPlayer.playToggle()
        }
        scheduleCountdownTick(after: 2.0) { [weak self] in
            self?.speedCountdown = 1
            feedbackPlayer.playToggle()
        }
        scheduleCountdownTick(after: 3.0) { [weak self] in
            self?.speedCountdown = nil
            feedbackPlayer.playLaunch()
            self?.startSpeedRoundTimer(feedbackPlayer: feedbackPlayer)
        }
    }

    private func scheduleCountdownTick(after delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }

    private func startSpeedRoundTimer(feedbackPlayer: FeedbackPlayer) {
        // Timer-Länge kommt aus der globalen Einstellung — Settings-
        // Änderungen sind damit ohne App-Neustart wirksam. Wert wird
        // einmal am Anfang gecached (`speedRoundTotalSeconds`), damit
        // die Progress-Normierung stabil bleibt, falls der User mitten
        // in der Runde die Settings ändert.
        let duration = SpeedRoundSettings.currentSeconds
        speedRoundTimeRemaining = duration
        speedRoundTotalSeconds = duration
        isSpeedRoundActive = true
        speedRoundTimer?.invalidate()
        speedRoundTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.speedRoundTimeRemaining -= 1
                if self.speedRoundTimeRemaining <= 5, self.speedRoundTimeRemaining > 0 {
                    feedbackPlayer.playToggle()
                }
                if self.speedRoundTimeRemaining <= 0 {
                    feedbackPlayer.playRoundClear()
                    self.finishSpeedRound()
                }
            }
        }
    }

    /// Zwangs-Abschluss der Session — wird aufgerufen wenn der Timer 0
    /// erreicht. Markiert als finished, UI kann darauf reagieren (Result).
    func finishSpeedRound() {
        speedRoundTimer?.invalidate()
        speedRoundTimer = nil
        isSpeedRoundActive = false
        isFinished = true
    }

    /// Räumt den Timer auf, wenn die View abgebaut wird (z. B. User-
    /// Abbruch). Ohne das würde der Timer weiterlaufen und am Ende
    /// versuchen, eine nicht mehr präsentierte View zu beenden.
    func cancelSpeedRound() {
        speedRoundTimer?.invalidate()
        speedRoundTimer = nil
        isSpeedRoundActive = false
        speedCountdown = nil
    }

    /// Audio-vs-visuelle Performance-Split: `(audioCorrect, audioTotal,
    /// visualCorrect, visualTotal)` — Null-Werte wenn kein Split
    /// sinnvoll. Fürs Result-Screen (V3).
    func audioVisualSplit() -> (audioCorrect: Int, audioTotal: Int, visualCorrect: Int, visualTotal: Int) {
        var aC = 0, aT = 0, vC = 0, vT = 0
        for rec in answerRecords {
            if rec.isAudioExercise {
                aT += 1
                if rec.wasCorrect { aC += 1 }
            } else {
                vT += 1
                if rec.wasCorrect { vC += 1 }
            }
        }
        return (aC, aT, vC, vT)
    }

    // MARK: - Soft Re-Insertion

    /// Plant eine falsche Aufgabe für die Wiedereinmischung. Die Aufgabe
    /// wird **leicht verändert** (anderer Kind, sofern sinnvoll), damit
    /// sich der User nicht nur an die Oberfläche erinnert, sondern
    /// den Akzenttyp noch einmal aktiv entscheiden muss.
    private func scheduleReinsertion(of exercise: AccentExercise) {
        let count = reinsertionCountByID[exercise.id] ?? 0
        guard count < Self.maxReinsertionsPerExercise else { return }
        reinsertionCountByID[exercise.id] = count + 1

        let variant = reinsertionVariant(of: exercise)
        let insertIndex = min(currentIndex + Self.reinsertionOffset + 1, exercises.count)
        exercises.insert(variant, at: insertIndex)
    }

    /// Erzeugt eine „verwandte" Aufgabe als Wiederholung. Primär wird
    /// der Kind getauscht (pickCorrectWord ↔ chooseAccent), damit der
    /// User den selben Akzenttyp in einer anderen Interaktionsform
    /// begegnet. Bei Audio bleibt der Kind, weil Audio → visuell-only
    /// das didaktisch Relevante ändern würde.
    private func reinsertionVariant(of exercise: AccentExercise) -> AccentExercise {
        let newID = UUID()
        let newKind: AccentExercise.Kind
        switch exercise.kind {
        case .pickCorrectWord: newKind = .chooseAccent
        case .chooseAccent:    newKind = .pickCorrectWord
        case .listenAndPick:   newKind = .pickCorrectWord  // nach Audio → visuell identifizieren
        }

        // Für chooseAccent brauchen wir letterVariants — falls das
        // Ursprungs-Exercise die nicht hatte (pickCorrectWord-Seed), bauen
        // wir sie anhand des Akzenttyps nach.
        let letterVariants: [String]
        if newKind == .chooseAccent, exercise.letterVariants.isEmpty {
            letterVariants = exercise.accentType == .cedille ? ["c", "ç"] : ["e", "é", "è", "ê"]
        } else {
            letterVariants = exercise.letterVariants
        }

        return AccentExercise(
            id: newID,
            kind: newKind,
            difficulty: exercise.difficulty,
            baseWord: exercise.baseWord,
            correctWord: exercise.correctWord,
            accentType: exercise.accentType,
            targetCharacterIndex: exercise.targetCharacterIndex,
            options: exercise.options,
            letterVariants: letterVariants,
            explanation: exercise.explanation
        )
    }

    // MARK: - Wrong-Type-Detection

    /// Ermittelt, welchen Akzenttyp der User mit seiner **falschen**
    /// Antwort gewählt hat. Dient für „é → è"-Verwechslungs-Analysen.
    /// Bei Variante B ist das einfach: das falsche Zeichen mappt direkt
    /// auf einen Typ. Bei A/C schauen wir ans Target-Zeichen im gewählten
    /// Wort und leiten den Typ daraus ab.
    private func inferWrongAccentType(from answer: String, exercise: AccentExercise) -> AccentType? {
        switch exercise.kind {
        case .chooseAccent:
            return Self.accentType(forCharacter: answer)
        case .pickCorrectWord, .listenAndPick:
            guard let idx = exercise.targetCharacterIndex else { return nil }
            let chars = Array(answer)
            guard idx >= 0, idx < chars.count else { return nil }
            return Self.accentType(forCharacter: String(chars[idx]))
        }
    }

    private static func accentType(forCharacter char: String) -> AccentType? {
        switch char {
        case "é": return .aigu
        case "è": return .grave
        case "ê": return .circonflexe
        case "ç": return .cedille
        case "ë", "ï": return .trema
        case "e", "c": return AccentType.none
        default: return nil
        }
    }
}
