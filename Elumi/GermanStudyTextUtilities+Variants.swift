import Foundation

func answerVariants(for normalizedText: String, answerLanguageCode: String) -> Set<String> {
    let alternatives = splitAnswerAlternatives(from: normalizedText)
    var variants = Set(alternatives.isEmpty ? [normalizedText] : alternatives)

    if answerLanguageCode == "de-DE" {
        for alternative in Array(variants) {
            variants.formUnion(germanGenderAnswerVariants(for: alternative))
            variants.formUnion(germanSynonymVariants(for: alternative))
            variants.formUnion(germanNumberVariants(for: alternative))
            variants.formUnion(germanDirectionalVariants(for: alternative))
        }
    }

    // **2026-08-06** — Gegenstück zu `germanGenderAnswerVariants` für die
    // französische Seite.
    //
    // Nötig geworden, weil französische Nomen seit heute mit Artikel
    // angezeigt werden („la pizza" statt „pizza", User-Spec). Ohne diese
    // Toleranz wäre ein getipptes „pizza" plötzlich falsch, obwohl die
    // Vokabel gesessen hat — die Anzeige-Änderung hätte die Bewertung
    // verschärft. Der Artikel wird gezeigt und mitgelernt, aber beim
    // Tippen nicht erzwungen.
    if answerLanguageCode == "fr-FR" {
        for alternative in Array(variants) {
            variants.formUnion(frenchArticleAnswerVariants(for: alternative))
        }
    }

    return Set(variants.map {
        $0.replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty })
}

/// Akzeptierte Schreibweisen einer französischen Antwort mit Blick auf den
/// Artikel: „la pizza" gilt auch als „pizza", „l'aéroport" auch als
/// „aéroport". Siehe Begründung in `answerVariants`.
///
/// Nur die Richtung „Artikel weglassen" — die Gegenrichtung (bare → mit
/// Artikel) bräuchte das Genus, das an dieser Stelle nicht vorliegt. Die
/// erwartete Antwort trägt den Artikel ohnehin, damit ist der Fall
/// abgedeckt.
func frenchArticleAnswerVariants(for normalizedText: String) -> Set<String> {
    var variants: Set<String> = [normalizedText]
    let lower = normalizedText.lowercased()

    // Elidierte Formen zuerst prüfen — „l'aéroport" hat kein Leerzeichen
    // und würde von der Wort-Prüfung unten nicht erfasst.
    for prefix in ["l'", "l\u{2019}", "d'", "d\u{2019}"] where lower.hasPrefix(prefix) {
        let bare = String(normalizedText.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !bare.isEmpty { variants.insert(bare) }
    }

    let separated: Set<String> = ["le", "la", "les", "un", "une", "des", "du", "de"]
    let words = normalizedText.split(separator: " ").map(String.init)
    if words.count > 1, let first = words.first, separated.contains(first.lowercased()) {
        let bare = words.dropFirst().joined(separator: " ")
        if !bare.isEmpty { variants.insert(bare) }
    }

    return variants
}

func splitAnswerAlternatives(from normalizedText: String) -> [String] {
    // **Bug-Fix 2026-08-06** — `;` fehlte als Trenner. Die DB nutzt „;"
    // durchgängig als Synonym-Trenner zwischen mehreren Übersetzungen
    // eines Eintrags (z. B. „da; dort" für „là"). Ohne diesen Split
    // wurde „da; dort" als EIN literaler Antworttext behandelt — eine
    // getippte Antwort „da" allein galt dann fälschlich als falsch
    // (User-Report).
    let collapsedSeparators = normalizedText
        .replacingOccurrences(of: #"\s+(?:oder|bzw)\s+"#, with: "|", options: .regularExpression)
        .replacingOccurrences(of: #"\s*\/\s*"#, with: "|", options: .regularExpression)
        .replacingOccurrences(of: #"\s*;\s*"#, with: "|", options: .regularExpression)
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

/// **Kuratierte Synonym-Gruppen (2026-08-04)** — User-Report: „Sie ist
/// ein bisschen schüchtern" wurde als falsch gewertet, obwohl die
/// gespeicherte Antwort „Sie ist etwas schüchtern" bedeutungsgleich
/// ist. Die Bewertung vergleicht sonst nur Text-Ähnlichkeit (exakt/
/// Wortmenge/Tippfehler-Toleranz/Substring) — keine Bedeutung. Statt
/// die generische Fuzzy-Toleranz weiter aufzuweichen (das hätte
/// unabhängig davon zum „Ost wurde als voilà akzeptiert"-Fehlerbild
/// beigetragen), pflegen wir eine **explizite, bewusst kleine** Liste
/// bedeutungsgleicher Wörter/Wendungen. Nur eingetragene Paare zählen
/// als Synonym — kein Rückschluss jenseits dieser Liste. Wächst mit der
/// Zeit, wenn weitere Fälle auftauchen.
///
/// Jede innere Liste ist eine Gruppe austauschbarer Wendungen; findet
/// sich EIN Mitglied als vollständiges Wort/Wendung im Text, werden
/// Varianten mit jedem anderen Gruppenmitglied an derselben Stelle
/// erzeugt.
private let germanSynonymGroups: [[String]] = [
    ["etwas", "ein bisschen", "ein wenig"],
    ["sehr", "total", "echt", "wirklich"],
    ["schnell", "rasch", "zügig"],
    ["schön", "hübsch"],
    ["groß", "riesig"],
    ["klein", "winzig"],
    ["viel", "eine menge"],
    ["oft", "häufig"],
    ["immer", "stets"],
    ["manchmal", "ab und zu"],
    ["sofort", "gleich"],
    ["vielleicht", "eventuell"]
]

/// **2026-08-06** — Richtungsangaben, die im Deutschen gleichwertig sind.
///
/// User-Report: „aller à la bibliothèque" mit „zur Bibliothek gehen"
/// beantwortet, gewertet als falsch, erwartet war „in die Bibliothek
/// gehen". Beides ist korrektes Deutsch — im Französischen steht dafür
/// dasselbe `à la`, eine Unterscheidung existiert dort gar nicht. Wer
/// die Vokabel kann, darf nicht an der deutschen Präposition scheitern.
///
/// **Bewusst übergenerierend.** Ob nach „zum" ein „in den" (maskulin)
/// oder „ins" (neutrum) gehört, verrät der String allein nicht — also
/// werden beide Varianten erzeugt. Das kann grammatisch unsinnige
/// Formen ergeben („zur Berge"), die aber niemand eintippt: Der einzige
/// Effekt wäre ein Fehl-Akzept, und dafür müsste die falsche Antwort
/// exakt so eine Form treffen. Der umgekehrte Fehler — eine richtige
/// Antwort abzulehnen — wiegt hier deutlich schwerer.
func germanDirectionalVariants(for normalizedText: String) -> Set<String> {
    // Jede Zeile: gleichwertige Richtungs-Wendungen. Alle Mitglieder
    // einer Gruppe werden gegeneinander ausgetauscht.
    let groups: [[String]] = [
        ["in die", "zur", "auf die", "an die"],
        ["in den", "zum", "auf den", "an den"],
        ["ins", "zum", "in das"],
        ["zu der", "zur"],
        ["zu dem", "zum"],
        ["nach hause", "heim"]
    ]

    var variants: Set<String> = []
    for group in groups {
        for member in group where containsWholeWordWithFollowingWord(member, in: normalizedText) {
            for replacement in group where replacement != member {
                if let substituted = replacingWholeWordPhrase(
                    member, with: replacement, in: normalizedText
                ) {
                    variants.insert(substituted)
                }
            }
        }
    }
    return variants
}

/// Wie `containsWholeWordPhrase`, verlangt aber zusätzlich ein
/// folgendes Wort. Verhindert, dass eine Wendung am Satzende
/// ausgetauscht wird, wo sie gar keine Richtungsangabe mehr ist
/// („ich gehe rein" bliebe ohne Nomen dahinter unberührt).
private func containsWholeWordWithFollowingWord(_ phrase: String, in text: String) -> Bool {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b\\s+\\S"
    return text.range(of: pattern, options: .regularExpression) != nil
}

func germanSynonymVariants(for normalizedText: String) -> Set<String> {
    var variants: Set<String> = []
    for group in germanSynonymGroups {
        guard let matchedMember = group.first(where: {
            containsWholeWordPhrase($0, in: normalizedText)
        }) else { continue }
        for replacement in group where replacement != matchedMember {
            if let substituted = replacingWholeWordPhrase(
                matchedMember, with: replacement, in: normalizedText
            ) {
                variants.insert(substituted)
            }
        }
    }
    return variants
}

/// Wortgrenzen-sicherer Containment-Check — verhindert, dass z. B.
/// „viel" fälschlich innerhalb von „vielleicht" anschlägt.
private func containsWholeWordPhrase(_ phrase: String, in text: String) -> Bool {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
    return text.range(of: pattern, options: .regularExpression) != nil
}

/// Ersetzt die erste wortgrenzen-sichere Fundstelle von `phrase` durch
/// `replacement`. `nil`, wenn `phrase` nicht als eigenständiges Wort/
/// Wendung vorkommt.
private func replacingWholeWordPhrase(_ phrase: String, with replacement: String, in text: String) -> String? {
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
    guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
    return text.replacingCharacters(in: range, with: replacement)
}

/// **Zahlwort ↔ Ziffer (2026-08-04)** — User-Report: Karteikarte
/// „vingt" (frz. zwanzig), gesprochene Antwort korrekt „zwanzig", aber
/// Spracherkennung transkribiert das als Ziffernfolge „20" — Text-
/// Vergleich gegen die ausgeschriebene Antwort „zwanzig" scheitert.
/// Deckt 0…999 ab (reicht für Alter, Uhrzeiten, Mengen, Daten — der
/// weit überwiegende Teil der Zahlen-Vokabeln). Nur die **ganze**
/// normalisierte Antwort wird geprüft (kein Zahlwort-Erkennen mitten
/// im Satz) — der gemeldete Fall ist eine isolierte Zahl-Karte.
func germanNumberVariants(for normalizedText: String) -> Set<String> {
    var variants: Set<String> = []
    if let n = Int(normalizedText), let word = germanNumberWord(for: n) {
        variants.insert(word)
    }
    if let digits = germanNumberWordToDigits[normalizedText] {
        variants.insert(digits)
    }
    return variants
}

private func germanNumberWord(for n: Int) -> String? {
    guard n >= 0, n <= 999 else { return nil }
    if n == 0 { return "null" }

    let onesStandalone = ["", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun"]
    let onesPrefix = ["", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun"]
    let teens = ["zehn", "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn"]
    let tens = ["", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig"]

    if n < 10 { return onesStandalone[n] }
    if n < 20 { return teens[n - 10] }
    if n < 100 {
        let t = n / 10, o = n % 10
        return o == 0 ? tens[t] : "\(onesPrefix[o])und\(tens[t])"
    }

    let h = n / 100
    let rest = n % 100
    let hundredPart = h == 1 ? "hundert" : "\(onesStandalone[h])hundert"
    guard rest > 0, let restWord = germanNumberWord(for: rest) else { return hundredPart }
    return hundredPart + restWord
}

/// Umkehr-Lookup, einmalig aus `germanNumberWord(for:)` aufgebaut.
private let germanNumberWordToDigits: [String: String] = {
    var map: [String: String] = [:]
    for n in 0...999 {
        if let word = germanNumberWord(for: n) {
            map[word] = String(n)
        }
    }
    return map
}()

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
