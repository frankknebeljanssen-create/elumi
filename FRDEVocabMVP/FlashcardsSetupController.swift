import Foundation
import SwiftUI

@MainActor
final class FlashcardsSetupController: ObservableObject {
    @Published var selectedSetupDirection: Direction = .frenchToGerman
    @Published var selectedSetupContent: FlashcardContentSelection = .mixed
    /// **2026-05-08** — Karten-Anzahl persistiert (vorher Session-only,
    /// User-Wahl ging beim Re-Open verloren). Initial-Wert aus
    /// UserDefaults via `loadSelectedCardCount()`; `didSet` schreibt
    /// jede Änderung durch. `0` = „alle Karten" (Default-Slider-Pos).
    @Published var selectedCardCount: Int = FlashcardsSetupController.loadSelectedCardCount() {
        didSet {
            UserDefaults.standard.set(selectedCardCount, forKey: appFlashcardsSelectedCardCountKey)
        }
    }
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

    /// **2026-05-08** — Letzte gewählte Karten-Anzahl aus UserDefaults.
    /// `0` = „alle Karten" (Default). Negative oder unrealistisch hohe
    /// Werte werden auf 0 zurückgeklappt (Hard-Cap 200 wird im Setup-
    /// Slider erzwungen).
    private static func loadSelectedCardCount() -> Int {
        let raw = UserDefaults.standard.integer(forKey: appFlashcardsSelectedCardCountKey)
        guard raw >= 0, raw <= 200 else { return 0 }
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
    ///
    /// **Stufe 5 Schritt 2 (2026-04-30)**: Read-Pfad routet jetzt über
    /// `VocabularyListSelectionResolver.effectiveSelectedListIDs(...)`.
    /// Bei Toggle ON liefert der Resolver die globale Auswahl; bei OFF
    /// wird die Per-Modul-Flashcards-Selection aus dem alten Key geladen
    /// (Closure-Fallback) — Verhalten unverändert zur Pre-Stufe-5-Welt.
    func restoreSelectedStackListIDs() {
        let ids = VocabularyListSelectionResolver.effectiveSelectedListIDs {
            // Per-Modul-Fallback: wie bisher aus dem Flashcards-spezifischen Key.
            guard let data = UserDefaults.standard.data(forKey: appFlashcardsSelectedListIDsKey),
                  let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) else {
                return []
            }
            return decoded
        }
        guard !ids.isEmpty else { return }
        isRestoringStackListIDs = true
        selectedStackListIDs = ids
        isRestoringStackListIDs = false
    }

    /// **Stufe 5 Schritt 2 (2026-04-30)**: Write-Pfad routet jetzt über
    /// `VocabularyListSelectionResolver.persistSelectedListIDs(...)`.
    /// Bei Toggle ON wird in den globalen Slot geschrieben; bei OFF in
    /// den Per-Modul-Flashcards-Key.
    private func persistSelectedStackListIDs() {
        VocabularyListSelectionResolver.persistSelectedListIDs(selectedStackListIDs) { ids in
            guard let data = try? JSONEncoder().encode(ids) else { return }
            UserDefaults.standard.set(data, forKey: appFlashcardsSelectedListIDsKey)
        }
    }
}
