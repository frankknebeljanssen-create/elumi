import Foundation
import SwiftUI

@MainActor
final class TrainingSessionController: ObservableObject {
    @Published var selectedTrainingListID: UUID?
    @Published var selectedTrainingListIDs: Set<UUID> = [] {
        didSet {
            guard !isRestoringSelectedListIDs else { return }
            persistSelectedListIDs()
        }
    }
    @Published var direction: Direction = .frenchToGerman
    @Published var cardType: CardType = .words
    @Published var trainingMode: TrainingMode = .vocabulary {
        didSet {
            guard oldValue != trainingMode else { return }
            // Beim Modul-Wechsel die zuletzt aktiven Listen des neuen Moduls laden.
            // Damit bleibt die Auswahl pro Modul stabil (Vokabeln ≠ Verben ≠ Nomen …).
            loadSelectedListIDsForCurrentMode()
        }
    }
    /// Verhindert, dass `restore`-Flows das eigene Schreiben triggern.
    private var isRestoringSelectedListIDs = false
    @Published var isSpeedRound = false
    @Published var speedRoundScore = 0
    // Speed-Round-Dauer kommt appweit aus `SpeedRoundSettings`. Init-Wert
    // ist Fallback bis zum ersten Timer-Start (siehe
    // `TrainingView+SessionFlow.startSpeedRoundTimer`).
    @Published var speedRoundTimeRemaining: Int = SpeedRoundSettings.currentSeconds
    /// Gesamtdauer dieser Speed-Round — gecacht damit die UI die
    /// Progress-Normierung stabil halten kann, auch wenn sich die
    /// Settings während der Runde ändern.
    @Published var speedRoundTotalSeconds: Int = SpeedRoundSettings.currentSeconds

    /// Antwort-Eingabeform für Nomen-Modus (nur dort im UI sichtbar).
    /// `.speech` = Spracheingabe (aktueller Default, sprich das korrekte
    /// Wort ein). `.choice` = Wortauswahl (Auswahlgrid mit 8 Optionen;
    /// die konkrete Matching-Logik ist noch nicht verdrahtet — dieser
    /// State bereitet die Architektur vor, damit Speech/Choice später
    /// als zwei Input-Layer auf einen gemeinsamen Trainings-Kern
    /// aufsetzen können, siehe `NounAnswerMode`).
    ///
    /// Speed Round bleibt orthogonal zu diesem Modus — bei
    /// `isSpeedRound == true` wird der Answer-Mode ignoriert (Speed
    /// Round fährt seine eigene Antwort-Mechanik).
    @Published var nounAnswerMode: NounAnswerMode = .speech
    var speedRoundTimer: Timer?
    @Published var currentTrainingItem: VocabularyItem?
    @Published var hasStartedTraining = false
    @Published var failedAttemptsOnCurrentCard = 0
    @Published var remainingTrainingItems: [VocabularyItem] = []
    @Published var preparedTrainingItems: [VocabularyItem] = []
    @Published var isShowingSetup = true
    @Published var completedRound: Int = 0
    @Published var isShowingRoundComplete = false
    @Published var showingTrainingListPicker = false
    @Published var selectedDictionaryLearningLevel: DictionaryLearningLevel = .beginner
    @Published var loadedDictionaryTrainingList: VocabularyList?

    struct DictionaryTrainingLoadContext: Equatable {
        let learningLevel: DictionaryLearningLevel
        let language: StudyLanguage
    }

    var dictionaryTrainingLoadGeneration = 0
    var loadedDictionaryContext: DictionaryTrainingLoadContext?

    /// Combo-Tracking für ProgressService-Bonus. Läuft über den
    /// zentralen `SessionStreak` (siehe `SessionStreak.swift`) — damit
    /// gilt **appweit** dieselbe Regel: Serie bricht bei jeder falschen
    /// Antwort und auch bei „erst nach Retry richtig" ab. Toast-Auslöser
    /// ist dieselbe Zahl wie die Reward-Combo.
    // Nicht `private(set)` — Mutation passiert aus File-Extensions
    // (z. B. `+SessionFlow` ruft `resetGamificationCounters`, was
    // `streak.reset()` setzt).
    var streak = SessionStreak()

    /// Kompatibilitäts-Shim: externe Call-Sites (`LearningSession`-Builder,
    /// UI-Anzeige) lesen weiterhin `sessionCurrentCombo` / `sessionLongestCombo`.
    /// Schreiben geht ausschließlich über `recordAnswer` → `streak`.
    var sessionCurrentCombo: Int { streak.current }
    var sessionLongestCombo: Int { streak.longest }

    /// Anzahl richtig beantworteter Einheiten in der aktuellen Runde.
    var sessionCorrectCount: Int = 0
    /// Anzahl falscher Antworten in der aktuellen Runde.
    var sessionWrongCount: Int = 0
    /// Schutz vor doppelter Reward-Vergabe pro Session/Runde.
    var sessionRewardConsumed: Bool = false

    /// Zählt eine Antwort für Combo + Reward-Logik. Wird vom Training-
    /// Answer-Flow aufgerufen. `firstAttempt == false` → die laufende Serie
    /// wird wie bei einer falschen Antwort zurückgesetzt (Details siehe
    /// `SessionStreak.recordAnswer`).
    func recordAnswer(correct: Bool, firstAttempt: Bool = true) {
        // Lernstatus-Signal: bevor die Combo/Session-Counter fortgeschrieben
        // werden, das aktuelle Trainings-Item (`currentTrainingItem`) in den
        // globalen Per-Item-Store melden. Funktioniert sowohl für `.vocabulary`
        // als auch für die spezialisierten Modi (Nomen, Artikel, Verben) —
        // alle arbeiten auf demselben `VocabularyItem`-Objekt.
        if let item = currentTrainingItem {
            ItemLearningStatusRecorder.record(
                french: item.french,
                german: item.german,
                cardType: item.cardType,
                correct: correct
            )
        }

        // Serie & Toast laufen zentral über `SessionStreak`.
        streak.recordAnswer(correct: correct, firstAttempt: firstAttempt)

        if correct {
            sessionCorrectCount += 1
        } else {
            sessionWrongCount += 1
        }

        // Nach jeder Antwort Resume-Snapshot aktualisieren, damit
        // selbst ein harter App-Kill den Fortschritt nicht verliert.
        persistResumeSnapshotIfEligible()
    }

    func resetGamificationCounters() {
        streak.reset()
        sessionCorrectCount = 0
        sessionWrongCount = 0
        sessionRewardConsumed = false
    }

    // MARK: - Resume-Snapshot

    /// Speichert den aktuellen Session-Zustand für späteren Resume —
    /// außer im **Speed-Round-Modus**, wo Fortsetzen fachlich nicht
    /// sinnvoll ist (Timer-basierte Runde, nach Unterbrechung verfälscht).
    /// Wird nach jeder Antwort + beim Karten-Wechsel aufgerufen.
    func persistResumeSnapshotIfEligible() {
        guard hasStartedTraining, !isSpeedRound else {
            // Speed Round → kein Snapshot. Falls ein alter Snapshot noch
            // liegt: jetzt aufräumen (sonst würde er beim nächsten normalen
            // Start unpassend greifen).
            return
        }
        guard !preparedTrainingItems.isEmpty else { return }

        let listIDs = Array(selectedTrainingListIDs)
        let state = TrainingSessionResumeState(
            trainingModeRaw: trainingMode.storageKey,
            directionRaw: direction.rawValue,
            cardTypeRaw: cardType.rawValue,
            selectedListIDs: listIDs,
            preparedItems: preparedTrainingItems,
            remainingItems: remainingTrainingItems,
            currentItem: currentTrainingItem,
            failedAttemptsOnCurrentCard: failedAttemptsOnCurrentCard,
            completedRound: completedRound,
            sessionCorrectCount: sessionCorrectCount,
            sessionWrongCount: sessionWrongCount,
            streak: streak,
            configFingerprint: TrainingSessionResumeStore.fingerprint(
                mode: trainingMode.storageKey,
                direction: direction.rawValue,
                cardType: cardType.rawValue,
                selectedListIDs: listIDs
            ),
            lastUpdatedEpoch: Date().timeIntervalSince1970
        )
        // Debounced Background-Write — Hot-Path (pro Antwort + pro
        // Karten-Wechsel) ist nicht mehr Main-Thread-blockierend.
        TrainingSessionResumeStore.scheduleSave(state)
    }

    /// Löscht den Resume-Snapshot — bei Session-Abschluss (Summary
    /// erreicht), Reset, oder inkompatiblem Re-Setup.
    func clearResumeSnapshot() {
        TrainingSessionResumeStore.clear()
    }

    /// Versucht, eine laufende Session aus dem Snapshot wiederherzustellen.
    /// Nur erfolgreich, wenn der aktuelle Setup-Fingerprint zum Snapshot
    /// passt (gleicher Modus, Direction, CardType, gleiche Listen-Auswahl).
    /// Gibt `true` zurück, wenn ein kompatibler Snapshot geladen wurde und
    /// die Session direkt startet — der Caller überspringt dann seinen
    /// normalen Deck-Build.
    @discardableResult
    func tryRestoreResumeSnapshot(
        expectedMode: TrainingMode,
        expectedDirection: Direction,
        expectedCardType: CardType,
        expectedListIDs: [UUID]
    ) -> Bool {
        guard let snapshot = TrainingSessionResumeStore.load() else { return false }

        let expectedFP = TrainingSessionResumeStore.fingerprint(
            mode: expectedMode.storageKey,
            direction: expectedDirection.rawValue,
            cardType: expectedCardType.rawValue,
            selectedListIDs: expectedListIDs
        )
        guard snapshot.configFingerprint == expectedFP else {
            // Setup hat sich geändert → Snapshot ist nicht mehr passend.
            // Stumm verwerfen, der Caller startet eine frische Session.
            TrainingSessionResumeStore.clear()
            return false
        }
        guard !snapshot.preparedItems.isEmpty else {
            TrainingSessionResumeStore.clear()
            return false
        }

        // State zurückspielen — Reihenfolge wichtig: erst die Queues,
        // dann Counter, zuletzt `currentTrainingItem` (damit die UI nicht
        // zwischen alten und neuen Items pendelt).
        preparedTrainingItems = snapshot.preparedItems
        remainingTrainingItems = snapshot.remainingItems
        currentTrainingItem = snapshot.currentItem
            ?? snapshot.remainingItems.first
            ?? snapshot.preparedItems.first
        failedAttemptsOnCurrentCard = snapshot.failedAttemptsOnCurrentCard
        completedRound = max(1, snapshot.completedRound)
        sessionCorrectCount = snapshot.sessionCorrectCount
        sessionWrongCount = snapshot.sessionWrongCount
        streak = snapshot.streak
        sessionRewardConsumed = false
        hasStartedTraining = true
        isShowingSetup = false
        isShowingRoundComplete = false
        isSpeedRound = false
        return true
    }

    func restoreSelectedListIDs() {
        loadSelectedListIDsForCurrentMode()
    }

    /// Lädt die persistierte Listenauswahl für den aktuellen `trainingMode`.
    /// Fällt zurück auf den Legacy-Key (`appTrainingSelectedListIDsKey`), falls für
    /// diesen Modus noch nie eine Auswahl gespeichert wurde — damit Bestandsnutzer
    /// ihren bisherigen Zustand behalten.
    ///
    /// **Stufe 5 Schritt 2 (2026-04-30)**: Read-Pfad routet jetzt über
    /// `VocabularyListSelectionResolver.effectiveSelectedListIDs(...)`.
    /// Bei Toggle ON liefert der Resolver die globale Auswahl — alle 5
    /// Trainings-Modes (vocabulary/nouns/articles/verbs/verbforms)
    /// teilen sich dann ein Set mit Quiz/Flashcards/Word Runner.
    /// Bei OFF läuft der existierende Per-Mode-Pfad unverändert
    /// (mit Legacy-Key-Fallback für Bestandsnutzer).
    private func loadSelectedListIDsForCurrentMode() {
        let restored = VocabularyListSelectionResolver.effectiveSelectedListIDs {
            // Per-Modul-Fallback: bestehende Per-Mode-Logik mit Legacy-Fallback.
            let modeKey = trainingSelectedListIDsKey(for: trainingMode.storageKey)
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: modeKey),
               let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
                return ids
            } else if let legacy = defaults.data(forKey: appTrainingSelectedListIDsKey),
                      let ids = try? JSONDecoder().decode(Set<UUID>.self, from: legacy),
                      !ids.isEmpty {
                return ids
            }
            return []
        }
        guard !restored.isEmpty else {
            // Kein persistierter Zustand → aktuelle Auswahl leeren, sonst bleibt
            // beim Modus-Wechsel fälschlich die vorherige Auswahl stehen.
            if !selectedTrainingListIDs.isEmpty {
                isRestoringSelectedListIDs = true
                selectedTrainingListIDs = []
                isRestoringSelectedListIDs = false
            }
            return
        }
        isRestoringSelectedListIDs = true
        selectedTrainingListIDs = restored
        isRestoringSelectedListIDs = false
    }

    /// **Stufe 5 Schritt 2 (2026-04-30)**: Write-Pfad routet jetzt über
    /// `VocabularyListSelectionResolver.persistSelectedListIDs(...)`.
    /// Bei Toggle ON wird in den globalen Slot geschrieben (alle anderen
    /// Module sehen die neue Auswahl); bei OFF in den Per-Mode-Key des
    /// aktuell aktiven `trainingMode`.
    private func persistSelectedListIDs() {
        VocabularyListSelectionResolver.persistSelectedListIDs(selectedTrainingListIDs) { ids in
            guard let data = try? JSONEncoder().encode(ids) else { return }
            let modeKey = trainingSelectedListIDsKey(for: trainingMode.storageKey)
            UserDefaults.standard.set(data, forKey: modeKey)
        }
    }
}
