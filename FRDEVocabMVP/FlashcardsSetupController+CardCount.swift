import Foundation

extension FlashcardsSetupController {
    var requestedCustomCardCount: Int? {
        let digits = customCardCountText.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    func effectiveSelectedCardCount(for selectedStackCardCount: Int) -> Int {
        guard !isUsingAllCardCount, let requestedCustomCardCount else { return 0 }
        return min(selectedStackCardCount, requestedCustomCardCount)
    }

    func selectedCardCountForSetup(selectedStackCardCount: Int) -> Int {
        isUsingAllCardCount ? selectedStackCardCount : effectiveSelectedCardCount(for: selectedStackCardCount)
    }

    func sanitizeCustomCardCountTextIfNeeded() {
        let digitsOnly = customCardCountText.filter(\.isNumber)
        if digitsOnly != customCardCountText {
            customCardCountText = digitsOnly
        }
        if !digitsOnly.isEmpty {
            isUsingAllCardCount = false
        }
    }

    func confirmCardCountEntry() {
        customCardCountText = customCardCountText.filter(\.isNumber)
    }
}
