import Foundation
import SwiftUI

func germanDisplayText(_ text: String, cardType: CardType, sourceHint: String? = nil) -> String {
    _ = cardType
    _ = sourceHint
    // Casing: zentrale Regelwerk-Engine (TextNormalizationEngine).
    // Satzzeichen-Inferenz und Text-Sanitization bleiben hier lokal.
    let cleaned = cleanedQuizDisplayText(text)
    guard !cleaned.isEmpty else { return cleaned }

    let normalized = TextNormalizationEngine.normalize(cleaned, language: .german)

    let preserved = preservingTerminalSentencePunctuation(
        from: text,
        in: normalized,
        style: .neutral,
        cardType: cardType
    )
    if detectedTerminalSentencePunctuation(from: preserved) != nil {
        return preserved
    }
    if let inferred = inferredGermanTerminalSentencePunctuation(preserved, cardType: cardType) {
        return applyingTerminalSentencePunctuation(inferred, to: preserved, style: .neutral)
    }
    return preserved
}

func formattedGermanLexiconDisplayText(
    _ text: String,
    cardType: CardType,
    germanGender: LexiconGenderInfo? = nil,
    frenchGender: LexiconGenderInfo? = nil,
    sourceHint: String? = nil
) -> String {
    _ = germanGender
    _ = frenchGender
    // Zentrale Engine übernimmt Casing. Keine Zusatzheuristik (Gender/NonNoun) —
    // deterministische Ausgabe gleich wie überall in der App.
    return germanDisplayText(text, cardType: cardType, sourceHint: sourceHint)
}

func bootstrappedGermanText(_ text: String, cardType: CardType, sourceHint: String? = nil) -> String {
    _ = cardType
    _ = sourceHint
    let cleaned = cleanedQuizDisplayText(text)
    guard !cleaned.isEmpty else { return cleaned }
    return TextNormalizationEngine.normalize(cleaned, language: .german)
}

func capitalizingGermanNounsInPhrase(_ text: String) -> String {
    // Einziger Einstiegspunkt: zentrale Engine.
    return TextNormalizationEngine.normalize(text, language: .german)
}


func looksLikeGermanDisplayText(_ text: String) -> Bool {
    let tokens = normalizedLookupText(text).split(separator: " ").map(String.init)
    guard !tokens.isEmpty else { return false }

    let germanMatches = tokens.filter { DataStore.germanLexiconWordSet.contains($0) }.count
    let ratio = Double(germanMatches) / Double(tokens.count)

    return startsWithGermanArticle(text) || ratio >= 0.45
}

func quizVisibleText(
    _ text: String,
    languageCode: String,
    category: String,
    sourceHint: String? = nil
) -> String {
    _ = category
    _ = sourceHint
    let cleaned = cleanedQuizDisplayText(text)
    let language: NormalizationLanguage = (languageCode == "de-DE") ? .german : .french
    return TextNormalizationEngine.normalize(cleaned, language: language)
}

/// German quiz casing — delegiert an die zentrale Engine.
func quizGermanWordCasing(_ text: String, sourceHint: String?) -> String {
    _ = sourceHint
    return TextNormalizationEngine.normalize(text, language: .german)
}

// **Bug-A-Fix (2026-05-02) — Fragezeichen-Render systemweit einheitlich.**
// Vorher: nur `cleanedQuizDisplayText`, der trailing `?!.` per Regex strippt.
// Folge: französische Phrasen wie „Comment ça va ?" verloren das `?`,
// deutsche Phrasen wie „Wie geht es dir?" ebenso. Karteikarten waren
// bereits korrekt via `synchronizedPairTerminalSentencePunctuation`,
// Quiz und Lexicon-Beispiele blieben kaputt → asymmetrisches Bild.
//
// Neu: Dispatch nach erkannter Sprache. Beide Ziel-Helper machen
// preserve+infer intern (wie Karteikarten):
//   * `germanDisplayText` → `preservingTerminalSentencePunctuation` plus
//     `inferredGermanTerminalSentencePunctuation`
//   * `sourceDisplayText(.french)` → analog für FR
// Spracherkennung via `looksLikeGermanDisplayText` (existierender Heuristik
// auf Basis von `germanLexiconWordSet` + `startsWithGermanArticle`).
// `category` → `CardType`-Mapping ist trivial (`"Phrase"` → `.phrases`).
private func quizCardType(for category: String) -> CardType {
    return category == CardType.phrases.categoryName ? .phrases : .words
}

func visibleQuizPromptText(_ text: String, category: String) -> String {
    let cardType = quizCardType(for: category)
    if looksLikeGermanDisplayText(text) {
        return capitalizingSentenceStartIfTerminated(germanDisplayText(text, cardType: cardType))
    }
    return capitalizingSentenceStartIfTerminated(sourceDisplayText(text, sourceLanguage: .french))
}

func visibleQuizAnswerText(_ text: String, category: String) -> String {
    let cardType = quizCardType(for: category)
    if looksLikeGermanDisplayText(text) {
        return capitalizingSentenceStartIfTerminated(germanDisplayText(text, cardType: cardType))
    }
    return capitalizingSentenceStartIfTerminated(sourceDisplayText(text, sourceLanguage: .french))
}

/// **2026-06-09** — Anzeige eines zusammengehörenden Paars (Frage +
/// Antwort) im Quiz.
///
/// Beide Seiten bekommen dasselbe Satzendzeichen, weil sie derselbe Satz
/// in zwei Sprachen sind. Vorher entschied jede Seite für sich, wodurch
/// links „tu veux un dessert." und rechts „…Dessert?" stehen konnte.
/// `synchronizedPairTerminalSentencePunctuation` löst das bereits
/// korrekt auf (Frage gewinnt vor Aussage) — sie wurde im Quiz nur nie
/// benutzt, obwohl Karteikarten sie längst verwenden.
///
/// Danach greift die Satzanfang-Großschreibung: Was als Satz endet,
/// beginnt groß.
func visibleQuizPairTexts(
    prompt: String,
    answer: String,
    category: String
) -> (prompt: String, answer: String) {
    let cardType = quizCardType(for: category)
    let promptIsGerman = looksLikeGermanDisplayText(prompt)

    let displayedPrompt = promptIsGerman
        ? germanDisplayText(prompt, cardType: cardType)
        : sourceDisplayText(prompt, sourceLanguage: .french)
    let displayedAnswer = looksLikeGermanDisplayText(answer)
        ? germanDisplayText(answer, cardType: cardType)
        : sourceDisplayText(answer, sourceLanguage: .french)

    // `source` ist immer die französische Seite — die Funktion leitet
    // daran ihre Sprachlogik ab.
    let synchronized = promptIsGerman
        ? synchronizedPairTerminalSentencePunctuation(
            source: displayedAnswer, target: displayedPrompt,
            sourceLanguage: .french, cardType: cardType)
        : synchronizedPairTerminalSentencePunctuation(
            source: displayedPrompt, target: displayedAnswer,
            sourceLanguage: .french, cardType: cardType)

    let syncedPrompt = promptIsGerman ? synchronized.target : synchronized.source
    let syncedAnswer = promptIsGerman ? synchronized.source : synchronized.target

    return (
        capitalizingSentenceStartIfTerminated(syncedPrompt),
        capitalizingSentenceStartIfTerminated(syncedAnswer)
    )
}

func canonicalGermanQuizText(
    prompt: String,
    promptLanguageCode: String,
    answer: String,
    category: String,
    sourceHint: String? = nil
) -> String {
    _ = promptLanguageCode
    _ = category
    _ = sourceHint
    _ = prompt
    let cleanedAnswer = cleanedQuizDisplayText(answer)
    guard !cleanedAnswer.isEmpty else { return cleanedAnswer }
    return TextNormalizationEngine.normalize(cleanedAnswer, language: .german)
}

func looksLikeGermanNounList(_ text: String) -> Bool {
    let cleaned = cleanedQuizDisplayText(text)
    guard !cleaned.isEmpty else { return false }

    let normalized = normalizedLookupText(cleaned)
    guard !normalized.isEmpty else { return false }

    let separators = CharacterSet(charactersIn: "/|,;")
    let segments = cleaned.components(separatedBy: separators)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !segments.isEmpty, segments.count <= 4 else { return false }

    return segments.allSatisfy { segment in
        let words = normalizedLookupText(segment).split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 2 else { return false }
        return !segment.contains("(") && !segment.contains(")")
    }
}

func quizPromptTypography(for prompt: String, category: String) -> Font {
    let cleaned = cleanedQuizDisplayText(prompt)
    let wordCount = cleaned.split(whereSeparator: \.isWhitespace).count
    let characterCount = cleaned.count

    if category == CardType.phrases.categoryName {
        if wordCount >= 6 || characterCount >= 34 {
            return AppTheme.Typography.cardTitle
        }
        if wordCount >= 4 || characterCount >= 24 {
            return AppTheme.Typography.screenTitle
        }
    }

    return AppTheme.Typography.largeTitle
}

func quizPromptLineLimit(for prompt: String, category: String) -> Int {
    let cleaned = cleanedQuizDisplayText(prompt)
    let wordCount = cleaned.split(whereSeparator: \.isWhitespace).count
    let characterCount = cleaned.count

    if category == CardType.phrases.categoryName, wordCount >= 4 || characterCount >= 24 {
        return 4
    }

    return 3
}

func quizPromptMinimumScale(for prompt: String, category: String) -> CGFloat {
    let cleaned = cleanedQuizDisplayText(prompt)
    let wordCount = cleaned.split(whereSeparator: \.isWhitespace).count
    let characterCount = cleaned.count

    if category == CardType.phrases.categoryName {
        if wordCount >= 6 || characterCount >= 34 {
            return 0.72
        }
        if wordCount >= 4 || characterCount >= 24 {
            return 0.8
        }
    }

    return 0.9
}
