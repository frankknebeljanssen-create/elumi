import Foundation

extension LexiconViewModel {
    func displaySideGenderInfo(for entry: PreparedLexiconEntry) -> LexiconGenderInfo? {
        guard entry.displayCardType == .words else { return nil }

        switch entry.displayCountryCode {
        case "FR":
            return entry.frenchGender
        case "DE":
            return entry.germanGender
        default:
            return nil
        }
    }

    func targetSideGenderInfo(for entry: PreparedLexiconEntry) -> LexiconGenderInfo? {
        guard entry.displayCardType == .words else { return nil }

        switch entry.displayCountryCode {
        case "FR":
            return entry.germanGender
        case "DE":
            return entry.frenchGender
        default:
            return nil
        }
    }

    func displayedSourceText(for entry: PreparedLexiconEntry) -> String {
        inlineLexiconGenderText(
            entry.sourceText,
            genderInfo: displaySideGenderInfo(for: entry)
        )
    }

    func displayedTargetText(for entry: PreparedLexiconEntry) -> String {
        inlineLexiconGenderText(
            entry.targetText,
            genderInfo: targetSideGenderInfo(for: entry)
        )
    }

    func displayedTargetVariantTexts(for entry: PreparedLexiconEntry) -> [String] {
        let variants = entry.targetVariants.isEmpty ? [entry.targetText] : entry.targetVariants
        let genderInfo = targetSideGenderInfo(for: entry)
        return variants.map { inlineLexiconGenderText($0, genderInfo: genderInfo) }
    }

    func sourceCountryCode(for entry: PreparedLexiconEntry) -> String {
        switch entry.displayCountryCode {
        case "DE":
            return "DE"
        case "FR":
            return "FR"
        default:
            return "FR"
        }
    }

    func targetCountryCode(for entry: PreparedLexiconEntry) -> String {
        switch entry.displayCountryCode {
        case "DE":
            return "FR"
        case "FR":
            return "DE"
        default:
            return "DE"
        }
    }

    func inlineLexiconGenderLabel(_ genderInfo: LexiconGenderInfo?) -> String? {
        guard let genderInfo else { return nil }

        switch genderInfo.gender {
        case .feminine:
            return "f"
        case .masculine:
            return "m"
        case .neuter:
            return "n"
        case .plural:
            return "pl"
        }
    }

    func inlineLexiconGenderText(_ text: String, genderInfo: LexiconGenderInfo?) -> String {
        guard let inlineGender = inlineLexiconGenderLabel(genderInfo),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return text
        }

        return "\(text) (\(inlineGender))"
    }
}
