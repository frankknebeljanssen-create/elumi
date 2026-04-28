import Foundation
import SwiftUI

@MainActor
final class FlashcardsSetupController: ObservableObject {
    @Published var selectedSetupDirection: Direction = .frenchToGerman
    @Published var selectedSetupContent: FlashcardContentSelection = .mixed
    @Published var selectedCardCount: Int = 0
    @Published var isUsingAllCardCount = true
    @Published var customCardCountText = ""
    @Published var isShowingSetup = true
    @Published var shouldAutoStartFromLaunch = false
    @Published var selectedStackListIDs: Set<UUID> = [] {
        didSet {
            guard !isRestoringStackListIDs else { return }
            persistSelectedStackListIDs()
        }
    }
    @Published var selectedStackDictionaryLearningLevel: DictionaryLearningLevel = .beginner
    @Published var showingStackComposer = false
    @Published var loadedDictionaryStackList: VocabularyList?

    /// Wie viele richtige Antworten hintereinander nötig sind, bis die Karte
    /// aus dem Stapel fällt. User-konfigurierbar: 1 (Schnell), 2 (Normal,
    /// Default), 3 (Gründlich), 4 (Intensiv — User-Revision 2026-04-22).
    @Published var masteryThreshold: Int = FlashcardsSetupController.loadMasteryThreshold() {
        didSet {
            let clamped = max(1, min(4, masteryThreshold))
            if clamped != masteryThreshold {
                masteryThreshold = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: appFlashcardsMasteryThresholdKey)
        }
    }

    private static func loadMasteryThreshold() -> Int {
        let raw = UserDefaults.standard.integer(forKey: appFlashcardsMasteryThresholdKey)
        if raw < 1 || raw > 4 { return 2 }
        return raw
    }

    struct DictionaryStackLoadContext: Equatable {
        let learningLevel: DictionaryLearningLevel
        let language: StudyLanguage
    }

    var dictionaryStackLoadGeneration = 0
    var loadedDictionaryContext: DictionaryStackLoadContext?
    var preferredLaunchItemIDs: Set<UUID> = []

    private var isRestoringStackListIDs = false

    /// Lädt die zuletzt persistierte Karteikarten-Listenauswahl aus UserDefaults.
    /// Analog zu `TrainingSessionController.restoreSelectedListIDs`, damit der
    /// User beim erneuten Öffnen des Moduls seine Listen wieder vorfindet.
    func restoreSelectedStackListIDs() {
        guard let data = UserDefaults.standard.data(forKey: appFlashcardsSelectedListIDsKey),
              let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data),
              !ids.isEmpty else { return }
        isRestoringStackListIDs = true
        selectedStackListIDs = ids
        isRestoringStackListIDs = false
    }

    private func persistSelectedStackListIDs() {
        guard let data = try? JSONEncoder().encode(selectedStackListIDs) else { return }
        UserDefaults.standard.set(data, forKey: appFlashcardsSelectedListIDsKey)
    }
}
