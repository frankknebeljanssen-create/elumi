import Foundation

func answerVariants(for normalizedText: String, answerLanguageCode: String) -> Set<String> {
    let alternatives = splitAnswerAlternatives(from: normalizedText)
    var variants = Set(alternatives.isEmpty ? [normalizedText] : alternatives)

    if answerLanguageCode == "de-DE" {
        for alternative in Array(variants) {
            variants.formUnion(germanGenderAnswerVariants(for: alternative))
        }
    }

    return Set(variants.map {
        $0.replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty })
}

func splitAnswerAlternatives(from normalizedText: String) -> [String] {
    let collapsedSeparators = normalizedText
        .replacingOccurrences(of: #"\s+(?:oder|bzw)\s+"#, with: "|", options: .regularExpression)
        .replacingOccurrences(of: #"\s*\/\s*"#, with: "|", options: .regularExpression)
        .replacingOccurrences(of: #"\s*\|\s*"#, with: "|", options: .regularExpression)

    return collapsedSeparators
        .components(separatedBy: "|")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func germanGenderAnswerVariants(for normalizedText: String) -> Set<String> {
    let words = normalizedText.split(separator: " ").map(String.init)
    guard let lastWord = words.last else { return [normalizedText] }

    let prefix = words.dropLast().joined(separator: " ")
    let baseWordVariants = germanGenderWordVariants(for: lastWord)

    return Set(baseWordVariants.map { variant in
        prefix.isEmpty ? variant : "\(prefix) \(variant)"
    })
}

func germanGenderWordVariants(for word: String) -> Set<String> {
    var variants: Set<String> = [word]
    guard word.count >= 4 else { return variants }

    if word.hasSuffix("in") {
        let masculineBase = String(word.dropLast(2))
        if isLikelyGermanRoleWord(masculineBase) {
            variants.insert(masculineBase)
        }
    } else if isLikelyGermanRoleWord(word) {
        variants.insert(word + "in")
    }

    return variants
}

func isLikelyGermanRoleWord(_ word: String) -> Bool {
    let roleEndings = [
        "er", "or", "ent", "ant", "ist", "oge", "nom", "eur", "iker",
        "ling", "at", "ar", "är", "et", "ot", "d", "t", "nd", "nt",
        "cht", "rt", "ld"
    ]

    return roleEndings.contains { word.hasSuffix($0) }
}

// MARK: - Geteilter Antwort-Vergleich (Bug #4 Fix, 2026-05-23)

/// Einheitlicher Approximate-Match für ALLE getippten Antwort-Pfade
/// (Vokabel `isApproximateMatch`, Quiz `submitTyping`, Karteikarte
/// `isApproximateMatch`). Ersetzt drei vorher identisch duplizierte
/// Implementierungen — Fix an EINER Stelle, kein Auseinanderdriften.
///
/// Reihenfolge (erste drei unverändert übernommen):
///   1. **exakt** gleich
///   2. **Wort-Set** gleich (gleiche Wörter, beliebige Reihenfolge, ≥2 Wörter)
///   3. **Levenshtein-ratio ≤ 0.25** (Tippfehler-Toleranz)
///   4. **Substring — längen-geschützt** (Bug-#4-Fix): Containment zählt nur,
///      wenn der kürzere String ≥ 4 Zeichen UND ≥ 50 % des längeren ist. So
///      rutscht z. B. nur „das" NICHT mehr als „das schwimmbad" durch, aber
///      ein Nomen ohne Artikel („schwimmbad" ↔ „das schwimmbad") wird
///      weiterhin akzeptiert.
///
/// Erwartet bereits normalisierte Strings (lowercase, Diakritika gefoldet).
func approximateAnswerMatch(got: String, expected: String) -> Bool {
    if got == expected { return true }

    let gotWords = Set(got.split(separator: " ").map(String.init))
    let expectedWords = Set(expected.split(separator: " ").map(String.init))
    if gotWords.count >= 2, gotWords == expectedWords { return true }

    let distance = answerLevenshtein(got, expected)
    let maxLength = max(got.count, expected.count)
    let ratio = maxLength == 0 ? 0 : Double(distance) / Double(maxLength)
    if ratio <= 0.25 { return true }

    // Substring NUR mit Längen-Schutz (Bug #4).
    if got.contains(expected) || expected.contains(got) {
        let shorter = min(got.count, expected.count)
        let longer = max(got.count, expected.count)
        if shorter >= 4, longer > 0, Double(shorter) / Double(longer) >= 0.5 {
            return true
        }
    }

    return false
}

/// Freie Levenshtein-Distanz für `approximateAnswerMatch`. Die bisherigen
/// `levenshtein`-Implementierungen lagen als View-/Controller-Instanz-
/// Methoden vor — diese freie Variante macht den geteilten Vergleich
/// unabhängig davon.
func answerLevenshtein(_ lhs: String, _ rhs: String) -> Int {
    let a = Array(lhs)
    let b = Array(rhs)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count { dist[i][0] = i }
    for j in 0...b.count { dist[0][j] = j }
    for i in 1...a.count {
        for j in 1...b.count {
            dist[i][j] = a[i - 1] == b[j - 1]
                ? dist[i - 1][j - 1]
                : min(dist[i - 1][j], dist[i][j - 1], dist[i - 1][j - 1]) + 1
        }
    }
    return dist[a.count][b.count]
}

// MARK: - Geteilte zulässige Antworten (Wertung #3, 2026-05-23)

/// Sammelt ALLE zulässigen Antwort-Varianten für eine Prompt-Seite — über
/// drei Quellen:
///   1. **Geschwister-Einträge** im aktiven Pool mit gleicher Prompt-Seite
///      (z. B. „un peu" → „ein wenig" UND „ein bisschen" als zwei Einträge),
///   2. deren `answerVariants` (Trennzeichen-/Genus-Varianten),
///   3. **Lexikon-Synonyme** (`SupplementalFreeDictLexicon`), wenn der Prompt
///      französisch ist.
///
/// Damit akzeptiert die Wertung mehrere gültige Übersetzungen, nicht nur die
/// EINE hinterlegte. Der Aufrufer prüft `got` gegen das zurückgegebene Set
/// via `approximateAnswerMatch` (diese Funktion bleibt unverändert — das
/// Multi-Expected sitzt hier im Aufrufer-Set).
///
/// `pool` ist die aktive Auswahl als `(french, german)`-Paare (Quiz:
/// `cachedMergedItems`, Vokabel: `preparedTrainingItems`, Karteikarte:
/// `session.cards`). `promptIsFrench` bestimmt, welche Seite die Prompt- bzw.
/// Antwort-Seite ist. `normalize` ist die Normalisierung des Aufrufers
/// (damit das Set zu dessen `got` passt). Geschwister-Match läuft über
/// `normalizedLookupText` (dieselbe Normalisierung wie der Dedup-Key).
func acceptedAnswerVariants(
    forPrompt prompt: String,
    answerLanguageCode: String,
    promptIsFrench: Bool,
    pool: [(french: String, german: String)],
    normalize: (String) -> String
) -> Set<String> {
    let promptKey = normalizedLookupText(prompt)
    var accepted = Set<String>()

    for entry in pool {
        let entryPrompt = promptIsFrench ? entry.french : entry.german
        guard normalizedLookupText(entryPrompt) == promptKey else { continue }
        let entryAnswer = promptIsFrench ? entry.german : entry.french
        accepted.formUnion(answerVariants(for: normalize(entryAnswer), answerLanguageCode: answerLanguageCode))
    }

    if promptIsFrench {
        for translation in SupplementalFreeDictLexicon.exactTranslations(for: prompt) {
            accepted.formUnion(answerVariants(for: normalize(translation), answerLanguageCode: answerLanguageCode))
        }
    }

    return accepted
}
