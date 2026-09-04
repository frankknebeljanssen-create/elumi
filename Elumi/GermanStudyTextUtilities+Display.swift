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
    // **Audit 2026-06-09** — Die Satzanfang-Großschreibung gehört in
    // die Anzeige-Funktion selbst, nicht an die Aufrufer. Vorher lag sie
    // nur im Quiz-Pfad, wodurch dieselbe Phrase je nach Aufrufer anders
    // aussah; die französische Seite macht es seit demselben Audit
    // ebenso. Wer einen neuen Anzeigepfad baut, bekommt es dadurch
    // automatisch richtig.
    if detectedTerminalSentencePunctuation(from: preserved) != nil {
        return capitalizingSentenceStartIfTerminated(preserved)
    }
    if let inferred = inferredGermanTerminalSentencePunctuation(preserved, cardType: cardType) {
        return capitalizingSentenceStartIfTerminated(
            applyingTerminalSentencePunctuation(inferred, to: preserved, style: .neutral)
        )
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
        return germanDisplayText(text, cardType: cardType)
    }
    return sourceDisplayText(text, sourceLanguage: .french)
}

/// **2026-08-06** — auch hier der Schlusspunkt zuletzt weg, aus
/// demselben Grund wie in `visibleQuizPairTexts`: Die beiden
/// Display-Funktionen darunter ergänzen fehlende Satzzeichen selbst,
/// wodurch ein beim Bauen der Frage entfernter Punkt wieder auftauchte.
/// Betrifft die Antwortoptionen im Multiple Choice, wo ein einzelner
/// Punkt die richtige Option verraten hat.
func visibleQuizAnswerText(_ text: String, category: String) -> String {
    let cardType = quizCardType(for: category)
    let isGerman = looksLikeGermanDisplayText(text)
    let displayed = isGerman
        ? germanDisplayText(text, cardType: cardType)
        : sourceDisplayText(text, sourceLanguage: .french)
    return strippingQuizTerminalPeriod(displayed, isGerman: isGerman)
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

    // Die Anzeige-Funktionen kapitalisieren bereits selbst; nach der
    // Paar-Synchronisierung kann eine Seite aber ein Satzzeichen NEU
    // bekommen haben (Frage gewinnt vor Aussage). Deshalb hier noch
    // einmal — idempotent, aber notwendig für genau diesen Fall.
    //
    // **2026-08-06** — Schlusspunkt zuletzt entfernen (User-Report:
    // „Se connecter." / „Sich einloggen." trugen weiterhin Punkte,
    // andere Kacheln nicht).
    //
    // Das Kürzen sitzt bewusst HIER am Ende und nicht beim Bauen der
    // Frage: `germanDisplayText`/`sourceDisplayText` oben ergänzen
    // fehlende Satzzeichen selbst („preserve + infer"), und
    // `synchronizedPairTerminalSentencePunctuation` gleicht sie
    // zwischen beiden Seiten an. Ein früher entfernter Punkt kam auf
    // diesem Weg wieder zurück — genau das war der Fehler.
    //
    // Fragezeichen bleiben: die Synchronisierung sorgt dort dafür, dass
    // beide Seiten dieselbe Satzart tragen, und das Zeichen ist Teil
    // der Aussage.
    return (
        strippingQuizTerminalPeriod(
            capitalizingSentenceStartIfTerminated(syncedPrompt),
            isGerman: promptIsGerman
        ),
        strippingQuizTerminalPeriod(
            capitalizingSentenceStartIfTerminated(syncedAnswer),
            isGerman: !promptIsGerman
        )
    )
}

/// Entfernt einen einzelnen Schlusspunkt für die Quiz-Anzeige **und**
/// nimmt die Großschreibung zurück, die nur wegen dieses Punktes
/// entstanden ist.
///
/// **2026-08-06** — Beides hängt zusammen (User-Screenshot: „Wütend.",
/// „En colère.", „L'élève."). Die Anzeige-Kette oben setzt zuerst ein
/// Satzendzeichen und schreibt dann wegen dieses Zeichens den
/// Satzanfang groß. Entfernt man nur den Punkt, bleibt ein
/// großgeschriebenes Adjektiv stehen — „Wütend" statt „wütend".
///
/// Die Rücknahme greift **nur bei Einzelwörtern**, und für Deutsch nur,
/// wenn das Wort kein bekanntes Nomen ist. Mehrwortige Einträge bleiben
/// unangetastet: dort steht der Großbuchstabe typischerweise an einem
/// echten Satzanfang oder an einem Nomen mit Artikel („der Schüler"),
/// und eine Automatik könnte dort mehr kaputt machen als reparieren.
func strippingQuizTerminalPeriod(_ text: String, isGerman: Bool = true) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasSuffix("."), !trimmed.hasSuffix("..") else { return trimmed }
    let stripped = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)

    guard !stripped.contains(" "),
          let first = stripped.first,
          first.isUppercase
    else { return stripped }

    // Deutsche Nomen bleiben groß — das ist keine Satzanfang-
    // Großschreibung, sondern die richtige Schreibung des Wortes.
    if isGerman, StandardVocabularyLoader.germanNounSet.contains(stripped.lowercased()) {
        return stripped
    }
    return stripped.prefix(1).lowercased() + stripped.dropFirst()
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
