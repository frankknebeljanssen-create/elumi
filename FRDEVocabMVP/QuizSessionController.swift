import Foundation
import SwiftUI

@MainActor
final class QuizSessionController: ObservableObject {
    @Published var selectedListIDs: Set<UUID> = [] {
        didSet { scheduleListIDsPersistence() }
    }

    /// Debounce-Token für `persistSelectedListIDs`. Bei Multi-Select
    /// (mehrere Listen schnell antippen) kollabiert das 5–6 UserDefaults-
    /// Writes auf einen — verhindert kleine Tap-Laggs im Quiz-Setup.
    private var pendingListIDsPersist: DispatchWorkItem?
    @Published var questionCountOption: QuizQuestionCountOption = .five
    @Published var questions: [QuizQuestion] = []
    @Published var cachedMergedItems: [VocabularyItem] = []
    @Published var cachedCandidates: [QuizCandidate] = []
    @Published var currentQuestionIndex = 0
    @Published var answeredResults: [Bool] = []
    @Published var isShowingResult = false
    @Published var isPreparingQuiz = false
    @Published var preparedQuestions: [QuizQuestion] = []
    @Published var plannedQuestionCount = 0
    @Published var isLoadingRemainingQuestions = false

    var quizPreparationGeneration = 0
    var questionPrebuildGeneration = 0
    var quizMergeGeneration = 0
    var reusedCandidateIDs: Set<String> = []
    var lastMergedItemsRequest: MergeRequest?

    /// Combo-Tracking für den ProgressService-Bonus (alle 5 richtig in Folge).
    /// Reset bei `resetToSetup()` und bei falscher Antwort. Läuft zentral
    /// über `SessionStreak` (siehe `SessionStreak.swift`) — Matching/Fill-
    /// Blanks nutzen bereits „any mistake"-Flags, d. h. `firstAttempt` wird
    /// hier implizit über das aufrufende `completeCurrentQuestion` transportiert.
    // Nicht `private(set)` — der Antwort-Pfad lebt in
    // `QuizSessionController+Progress.swift` (eigene File-Extension) und
    // muss den Streak mutieren können.
    var streak = SessionStreak()
    var sessionCurrentCombo: Int { streak.current }
    var sessionLongestCombo: Int { streak.longest }
    /// Schutz gegen doppelte Reward-Vergabe — analog zum Flashcard-Flow.
    var sessionRewardConsumed: Bool = false

    /// **Daily Drop Modul 1 (2026-05-23)** — Atomar-Modus-Flag. Wenn
    /// `true`: Generierung nur MultipleChoice + Tippen, keine
    /// Matching-/Combo-/FillBlanks-Insertion → `questions.count == N`
    /// exakt. Gesetzt aus `QuizLaunchContext.atomicOnly` in
    /// `handleQuizAppear`, VOR `questionCountOption` (Prebuild-Race).
    /// Default `false` → reguläres Quiz unverändert (nil-gated).
    var atomicOnly: Bool = false

    /// **V1b (2026-04-28)** — `lernjahrMax` ist Teil des Equality-Vergleichs.
    /// `refreshMergedItemsIfNeeded` blockiert den Rebuild, wenn die letzte
    /// MergeRequest gleich der aktuellen ist; ohne `lernjahrMax`-Komponente
    /// würde ein Filter-Wechsel (gleiche Listen + gleiche Direction)
    /// fälschlich als „nichts zu tun" durchgewinkt → Stale Pool.
    ///
    /// **Bugfix 2026-08-05** — `itemFingerprint` ergänzt (User-Report:
    /// Quiz mit „Meine Wackelkandidaten" fragte über viele Durchgänge
    /// hinweg immer wieder dieselben ~40 Wörter ab, der Rest der Liste
    /// tauchte nie auf). Ursache: „Meine Wackelkandidaten" behält beim
    /// Neu-Bauen (`rebuildWackelkandidatenList`) dieselbe UUID, auch
    /// wenn sich der komplette Inhalt ändert (Wörter fallen raus,
    /// andere kommen rein). Der bisherige Vergleich nur über
    /// `listIDs` erkannte das nicht — „gleiche Liste" hieß fälschlich
    /// „gleicher Inhalt", `refreshMergedItemsIfNeeded` übersprang den
    /// Rebuild und das Quiz zog aus einem eingefrorenen, veralteten
    /// Kandidaten-Pool vom allerersten Aufruf.
    ///
    /// `itemFingerprint` hasht Listen-ID + Item-Anzahl + alle Item-IDs.
    /// Da `rebuildWackelkandidatenList` (und jede andere Content-
    /// Änderung) neue `VocabularyItem`s mit frischen UUIDs erzeugt,
    /// ändert sich der Fingerprint zuverlässig bei jeder inhaltlichen
    /// Änderung — auch wenn Listen-ID, Direction und Lernjahr gleich
    /// bleiben.
    struct MergeRequest: Equatable {
        let listIDs: [UUID]
        let direction: Direction
        let lernjahrMax: Int?
        let itemFingerprint: Int

        static func fingerprint(for lists: [VocabularyList]) -> Int {
            var hasher = Hasher()
            for list in lists {
                hasher.combine(list.id)
                hasher.combine(list.items.count)
                for item in list.items {
                    hasher.combine(item.id)
                }
            }
            return hasher.finalize()
        }
    }

    /// **Stufe 5 Schritt 2 (2026-04-30)**: Read-Pfad routet jetzt über
    /// `VocabularyListSelectionResolver.effectiveSelectedListIDs(...)`.
    /// Bei Toggle ON liefert der Resolver die globale Auswahl; bei OFF
    /// wird die Per-Modul-Quiz-Selection aus dem alten Key gelesen
    /// (Closure-Fallback) — Verhalten unverändert zur Pre-Stufe-5-Welt.
    func restoreSelectedListIDs() {
        let ids = VocabularyListSelectionResolver.effectiveSelectedListIDs {
            // Per-Modul-Fallback: wie bisher aus dem Quiz-spezifischen Key.
            guard let data = UserDefaults.standard.data(forKey: appQuizSelectedListIDsKey),
                  let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) else {
                return []
            }
            return decoded
        }
        guard !ids.isEmpty else { return }
        selectedListIDs = ids
    }

    /// **Stufe 5 Schritt 2 (2026-04-30)**: Write-Pfad routet jetzt über
    /// `VocabularyListSelectionResolver.persistSelectedListIDs(...)`.
    /// Bei Toggle ON wird in den globalen Slot geschrieben (alle anderen
    /// Module sehen die neue Auswahl); bei OFF in den Per-Modul-Quiz-Key.
    private func persistSelectedListIDs() {
        VocabularyListSelectionResolver.persistSelectedListIDs(selectedListIDs) { ids in
            guard let data = try? JSONEncoder().encode(ids) else { return }
            UserDefaults.standard.set(data, forKey: appQuizSelectedListIDsKey)
        }
    }

    /// Debounce-Wrapper für `persistSelectedListIDs`. Der eigentliche
    /// UserDefaults-Write läuft auf einer Utility-Queue (150 ms
    /// debounce), ohne den Main-Thread zu blockieren. Snapshot der IDs
    /// wird **beim Planen** genommen, damit der spätere Task auf einem
    /// konsistenten Wert arbeitet.
    ///
    /// **Stufe 5 Schritt 2 (2026-04-30)**: nutzt jetzt denselben Routing-
    /// Helper wie der synchrone `persistSelectedListIDs`-Pfad.
    private func scheduleListIDsPersistence() {
        pendingListIDsPersist?.cancel()
        let snapshot = selectedListIDs
        let item = DispatchWorkItem {
            VocabularyListSelectionResolver.persistSelectedListIDs(snapshot) { ids in
                guard let data = try? JSONEncoder().encode(ids) else { return }
                UserDefaults.standard.set(data, forKey: appQuizSelectedListIDsKey)
            }
        }
        pendingListIDsPersist = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15, execute: item)
    }
}
