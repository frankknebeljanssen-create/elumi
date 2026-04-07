import Foundation

private let plusNamePlaceholderToken = "elumiplusnameplaceholder"
private let plusNomPlaceholderToken = "elumiplusnomplaceholder"
private let plusPrenomPlaceholderToken = "elumiplusprenomplaceholder"

private func protectingPlaceholderMarkers(in text: String) -> String {
    text
        .replacingOccurrences(
            of: #"(?iu)\+\s*name\b"#,
            with: " \(plusNamePlaceholderToken) ",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"(?iu)\+\s*nom\b"#,
            with: " \(plusNomPlaceholderToken) ",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"(?iu)\+\s*pr[ée]nom\b"#,
            with: " \(plusPrenomPlaceholderToken) ",
            options: .regularExpression
        )
}

private func restoringPlaceholderMarkers(in text: String) -> String {
    text
        .replacingOccurrences(of: plusNamePlaceholderToken, with: "+ Name")
        .replacingOccurrences(of: plusNomPlaceholderToken, with: "+ nom")
        .replacingOccurrences(of: plusPrenomPlaceholderToken, with: "+ prénom")
}

func cleanedQuizDisplayText(_ text: String) -> String {
    restoringPlaceholderMarkers(in:
        protectingPlaceholderMarkers(in: text)
        .replacingOccurrences(of: #"\[[^\[\]]+\]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\/[^\/]+\/"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*\[[^\]]*$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)(^|\s)\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ'’\-\.\,]+\b"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ\s'’\-\.\,]+\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)\s+\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ\s'’\-\.\,]+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ\s'’\-\.\,]+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*[\[/][^\s]+\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*[^\s]*[ˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ][^\s]*\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)^\s*[\[\]/]+|[\[\]/]+\s*$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)[*†‡•●▪◦※§]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)(^|\s)[~^_#]+(?=\s|$)"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)(^|\s)['’`]+(?=\p{L})"#, with: "$1", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)^['’`]+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)['’`]+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)(^|\s)[^\p{L}\p{M}\p{N}'’\-]+(?=\s|$)"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)^[^\p{L}\p{M}\p{N}]+|[^\p{L}\p{M}\p{N}]+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

func restoringFrenchElisions(_ text: String) -> String {
    let cleaned = cleanedQuizDisplayText(text)
    guard !cleaned.isEmpty else { return cleaned }

    let apostropheVowels = "aeiouyhàâäæéèêëîïôöœùûü"
    let singleLetterPattern = "(?iu)\\b([cdjlmnst])\\s+(?=[\(apostropheVowels)])"
    let quPattern = "(?iu)\\b(qu|jusqu|lorsqu|puisqu)\\s+(?=[\(apostropheVowels)])"

    return cleaned
        .replacingOccurrences(of: singleLetterPattern, with: "$1’", options: .regularExpression)
        .replacingOccurrences(of: quPattern, with: "$1’", options: .regularExpression)
}

func strippingTrailingFrenchQuestionMark(from text: String) -> String {
    text
        .replacingOccurrences(of: #"\s*\?$"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func normalizedLookupText(_ text: String) -> String {
    cleanedQuizDisplayText(text)
        .folding(options: .diacriticInsensitive, locale: .current)
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func compactLookupKey(_ text: String) -> String {
    normalizedLookupText(text).replacingOccurrences(of: " ", with: "")
}

func normalizedLookupWords(_ text: String) -> [String] {
    normalizedLookupText(text)
        .split(separator: " ")
        .map(String.init)
}
