import Foundation

extension FlashcardsSetupController {
    var isUsingAllCards: Bool {
        selectedCardCount == 0
    }

    var requestedCustomCardCount: Int? {
        let digits = customCardCountText.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    func sanitizeCustomCardCountTextIfNeeded() {
        let digitsOnly = customCardCountText.filter(\.isNumber)
        if digitsOnly != customCardCountText {
            customCardCountText = digitsOnly
        }
    }

    func confirmCardCountEntry() {
        customCardCountText = customCardCountText.filter(\.isNumber)
    }

    /// **User-Revision 2026-04-22**: Flashcard-Sessions sind auf eine
    /// feste Obergrenze pro Durchlauf begrenzt (Setup-Card-Cap). Wer
    /// eine größere Liste wählt, bekommt automatisch nur die ersten
    /// N Karten — das hält die Session verdaulich und den Streak-
    /// Zähler im fairen Rahmen.
    ///
    /// **2026-06-09** — 200 → 100. 200 Karten am Stück sind für die
    /// Zielgruppe zu lang; wer mehr will, macht mehrere Durchläufe.
    /// Single Source of Truth — der Setup-Slider liest diesen Wert,
    /// statt die Zahl ein zweites Mal zu führen.
    static let maxCardsPerSession: Int = 100

    func effectiveSelectedCardCount(for selectedStackCardCount: Int) -> Int {
        let capped = min(selectedStackCardCount, Self.maxCardsPerSession)
        if selectedCardCount == 0 || selectedCardCount >= capped {
            return capped
        }
        return min(selectedCardCount, capped)
    }

    func selectedCardCountForSetup(selectedStackCardCount: Int) -> Int {
        effectiveSelectedCardCount(for: selectedStackCardCount)
    }

    func clampCardCount(to maxCards: Int) {
        if selectedCardCount > maxCards {
            selectedCardCount = 0
        }
    }
}
