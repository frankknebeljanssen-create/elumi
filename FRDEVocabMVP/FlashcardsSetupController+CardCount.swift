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

    /// **User-Revision 2026-04-22**: Flashcard-Sessions sind auf
    /// maximal 200 Karten pro Durchlauf begrenzt (Setup-Card-Cap).
    /// Wer eine Liste mit >200 Einträgen wählt, bekommt automatisch
    /// nur die ersten 200 Karten — das hält die Session verdaulich
    /// und den Streak-Zähler im fairen Rahmen.
    static let maxCardsPerSession: Int = 200

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
