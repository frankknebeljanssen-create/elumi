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

    func effectiveSelectedCardCount(for selectedStackCardCount: Int) -> Int {
        if selectedCardCount == 0 || selectedCardCount >= selectedStackCardCount {
            return selectedStackCardCount
        }
        return selectedCardCount
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
