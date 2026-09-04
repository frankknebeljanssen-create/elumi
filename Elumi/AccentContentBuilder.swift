import Foundation

/// Baut aus Seed-Wörtern (oder Wörtern aus einer Nutzer-Liste) eine
/// konkrete Session-Queue aus `AccentExercise`-Items.
///
/// Pipeline:
/// 1. Quellen-Wörter zusammensuchen — aus der gewählten Nutzer-Liste und
///    **nur** aus ihr. Der Built-in-Katalog greift ausschließlich, wenn
///    gar keine Liste gewählt ist (siehe `gatherSeeds`).
/// 2. Pro Wort wird das Exercise-Objekt generiert — je nach Modus/Kind:
///    - `pickCorrectWord` → korrekte Form + 3 plausible Distraktoren
///    - `chooseAccent`    → Letter-Varianten für die betroffene Stelle
/// 3. Reihenfolge gemischt, auf `sessionLength` gekürzt.
enum AccentContentBuilder {

    // MARK: - Public API

    /// Baut die Session-Queue für einen bestimmten Modus.
    ///
    /// V3-Erweiterungen:
    ///   • Adaptive Gewichtung: Akzenttypen mit niedriger Confidence
    ///     (aus `AccentAdaptiveStore`) bekommen **mehr** Aufgaben,
    ///     sichere Typen bekommen weniger.
    ///   • Audio-Exercises (`.listenAndPick`) fließen bei Üben + Speed Round
    ///     mit ca. 25–30 % in die Session ein — jede 4. Aufgabe ist Audio.
    ///
    /// - Parameters:
    ///   - list: Die aktuell ausgewählte Vokabel-Liste (optional).
    ///   - adaptiveStore: Confidence-Store — wird für die Gewichtung
    ///     abgefragt. Kann `nil` sein (z. B. in Tests), dann kommt
    ///     reines Round-Robin ohne Adaptiv-Anteil.
    @MainActor
    static func buildSession(mode: AccentMode, from list: VocabularyList?, adaptiveStore: AccentAdaptiveStore? = nil) -> [AccentExercise] {
        let targetCount = mode.sessionLength > 0 ? mode.sessionLength : 12

        // Seed-Supply mindestens so groß wie die gewünschte Queue —
        // sonst müsste der Round-Robin mit zu wenig Material arbeiten
        // (wichtig für den Speed-Round-Modus mit ~35 Exercises pro Runde).
        let rawSeeds = gatherSeeds(from: list, minSupply: targetCount + 5)

        // Confidences **vor** prepareSeeds einmal einsammeln, damit
        // prepareSeeds selbst nicht mehr Actor-isoliert sein muss.
        var confidences: [AccentType: Double] = [:]
        if let store = adaptiveStore {
            for type in AccentType.mvpActive {
                confidences[type] = store.confidence(for: type)
            }
        }

        // Seeds vorbereiten: Round-Robin + Difficulty-Filter + adaptive
        // Gewichtung nach Confidence.
        let preparedSeeds = prepareSeeds(rawSeeds, mode: mode, target: targetCount, confidences: confidences)

        // Je nach erlaubten Kinds die passenden Exercises generieren.
        let kinds = mode.allowedKinds
        var exercises: [AccentExercise] = []

        for (idx, seed) in preparedSeeds.enumerated() {
            if exercises.count >= targetCount { break }

            let pickedKind = pickKind(at: idx, from: kinds, mode: mode)
            if let exercise = makeExercise(from: seed, kind: pickedKind) {
                exercises.append(exercise)
            }
        }

        return Array(exercises.prefix(targetCount))
    }

    /// Wählt den Exercise-Kind je Position in der Queue. Speed Round
    /// alterniert deterministisch durch alle erlaubten Kinds; Üben
    /// streut zufällig, bevorzugt aber die visuellen Formen (Audio ca.
    /// jede 4. Aufgabe, damit das Modul nicht zu Ton-lastig wird).
    private static func pickKind(at index: Int, from kinds: [AccentExercise.Kind], mode: AccentMode) -> AccentExercise.Kind {
        guard kinds.count > 1 else { return kinds.first ?? .pickCorrectWord }

        if mode == .speedRound {
            return kinds[index % kinds.count]
        }

        // Üben: jede 4. Position ist Audio (sofern erlaubt), Rest wird
        // zufällig zwischen pickCorrectWord + chooseAccent gemischt.
        if index % 4 == 3, kinds.contains(.listenAndPick) {
            return .listenAndPick
        }
        let nonAudio = kinds.filter { $0 != .listenAndPick }
        return nonAudio.randomElement() ?? .pickCorrectWord
    }

    /// Bereitet Seeds für die Session vor:
    /// 1. Speed Round bevorzugt `medium`/`hard`-Seeds.
    /// 2. Akzenttypen werden adaptiv gewichtet — schwächere Typen bekommen
    ///    zusätzliche Slots in der Rotation.
    /// 3. Round-Robin über die gewichtete Typ-Reihenfolge — Cédille kommt
    ///    auch dann sinnvoll dran, wenn im Katalog mehr é-Wörter drin sind.
    private static func prepareSeeds(_ seeds: [AccentWordCatalog.SeedEntry], mode: AccentMode, target: Int, confidences: [AccentType: Double]) -> [AccentWordCatalog.SeedEntry] {
        // 1) Difficulty-Filter bei Speed Round — aber nur wenn genug Material da.
        let candidatesForDifficulty: [AccentWordCatalog.SeedEntry] = {
            if mode == .speedRound {
                let harder = seeds.filter { $0.difficulty != .easy }
                if harder.count >= target { return harder }
            }
            return seeds
        }()

        // 2) Nach Akzenttyp gruppieren und pro Gruppe gemischt.
        var buckets: [AccentType: [AccentWordCatalog.SeedEntry]] = [:]
        for seed in candidatesForDifficulty.shuffled() {
            buckets[seed.accentType, default: []].append(seed)
        }

        // 3) Gewichtete Typ-Reihenfolge — niedrige Confidence = mehr
        //    Slots in der Rotation. Beispiel: wenn „ê" Confidence 0.3 hat
        //    und alle anderen 0.8, taucht ê häufiger in der Rotation auf.
        let typeOrder = weightedTypeOrder(confidences: confidences)

        var result: [AccentWordCatalog.SeedEntry] = []
        var rotation = 0
        while result.count < target {
            let type = typeOrder[rotation % typeOrder.count]
            rotation += 1
            if var bucket = buckets[type], !bucket.isEmpty {
                result.append(bucket.removeFirst())
                buckets[type] = bucket
            }
            if buckets.values.allSatisfy({ $0.isEmpty }) { break }
        }

        // Fallback falls durchs Round-Robin noch Platz ist.
        if result.count < target {
            let rest = buckets.values.flatMap { $0 }
            result.append(contentsOf: rest.prefix(target - result.count))
        }

        return result
    }

    /// Liefert die Typ-Reihenfolge für die Round-Robin-Rotation,
    /// **gewichtet** nach Confidence. Jeder Typ bekommt 1–3 Slots:
    ///   • Confidence ≥ 0.8 → 1 Slot  (sitzt gut)
    ///   • 0.5–0.8         → 2 Slots (noch üben)
    ///   • <  0.5          → 3 Slots (Schwerpunkt — mehr Aufgaben)
    /// Ohne Confidences bleibt es bei gleichmäßigen 1 Slot je Typ.
    private static func weightedTypeOrder(confidences: [AccentType: Double]) -> [AccentType] {
        let types = AccentType.mvpActive
        guard !confidences.isEmpty else { return types }
        var order: [AccentType] = []
        for type in types {
            let c = confidences[type] ?? 0.6
            let slots: Int
            if c >= 0.8 { slots = 1 }
            else if c >= 0.5 { slots = 2 }
            else { slots = 3 }
            order.append(contentsOf: Array(repeating: type, count: slots))
        }
        return order
    }

    // **Stufe 6 (2026-05-02)** — `buildLearningCards()` und
    // `LearningCard` (siehe unten) wurden mit dem Lernen-Modus
    // entfernt; siehe `AccentMode`-Doc-Kommentar zum Cut.

    // MARK: - Seeds sammeln

    /// Sammelt die Akzent-Wörter für eine Session.
    ///
    /// **Strikte Listen-Bindung (2026-09-03)** — User-Report: „bei
    /// Akzenten kommen Wörter, die gar nicht in der gewählten Liste
    /// stehen". Vorher galt: Bringt die Liste weniger als 5 brauchbare
    /// Treffer, wurde still aus dem Built-in-Katalog aufgefüllt, bis
    /// `minSupply` erreicht war — bei einer Liste mit 3 Akzent-Wörtern
    /// bestand die Runde also fast vollständig aus fremdem Material.
    /// Das ist derselbe Fehler wie zuvor im Artikel-Training (stiller
    /// A1-Fallback) und wird genauso behandelt: Ist eine Lernliste
    /// gewählt, kommen **ausschließlich** deren Wörter dran. Reicht das
    /// nicht für eine volle Runde, wird die Runde kürzer — aufgefüllt
    /// wird nicht.
    ///
    /// Der Built-in-Katalog greift nur noch dort, wo gar keine Liste
    /// gewählt ist (Setup-Card „Standard-Wörter").
    ///
    /// **Dedup**: Jedes Wort darf nur **einmal** in der finalen Seed-
    /// Liste stehen — sonst würde dasselbe Wort zweimal in derselben
    /// Runde abgefragt.
    private static func gatherSeeds(from list: VocabularyList?, minSupply: Int = 12) -> [AccentWordCatalog.SeedEntry] {
        guard let list else {
            // Keine Liste gewählt → Built-in-Katalog.
            return Array(AccentWordCatalog.mvpActive.shuffled().prefix(minSupply))
        }
        return listSeeds(from: list)
    }

    /// Wie viele Wörter einer Liste sich überhaupt fürs Akzent-Training
    /// eignen. Der Setup-Screen zeigt diese Zahl an, damit vor dem Start
    /// sichtbar ist, wie lang die Runde werden kann.
    static func usableWordCount(in list: VocabularyList?) -> Int {
        guard let list else { return AccentWordCatalog.mvpActive.count }
        return listSeeds(from: list).count
    }

    /// Unterhalb dieser Anzahl lohnt sich keine Runde — der Setup-Screen
    /// blockt den Start und sagt, woran es liegt, statt eine Zwei-Fragen-
    /// Session zu starten oder still nichts zu tun.
    static let minimumUsableWords = 4

    /// Alle brauchbaren Akzent-Seeds einer Liste — dedupliziert, unter
    /// Beachtung des globalen Lernjahr-Filters.
    private static func listSeeds(from list: VocabularyList) -> [AccentWordCatalog.SeedEntry] {
        var seen: Set<String> = []
        var fromList: [AccentWordCatalog.SeedEntry] = []

        // **V1b Lernjahr-Filter (2026-04-28)** — Akzente respektiert
        // den globalen Lernjahr-Max. Hierarchische Listen (A1 mit
        // cumulativeChildren) liefern nur den Y_1...Y_max-Slice;
        // klassische Listen ihre vollen items unverändert.
        let effective = VocabularyListSelectionResolver.effectiveItems(
            for: list,
            lernjahrMax: VocabularyListSelectionResolver.currentLernjahrMax()
        )
        for item in effective {
            let word = item.french
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !word.isEmpty else { continue }
            guard let seed = makeSeedFromUserWord(word) else { continue }
            let key = seed.correctWord.lowercased()
            if seen.insert(key).inserted {
                fromList.append(seed)
            }
        }

        return fromList
    }

    /// Versucht aus einem User-Wort (mit Akzent) ein SeedEntry zu machen.
    /// Nur **einzelne Wörter** mit einem der MVP-Akzente kommen durch:
    /// Mehrwort-Phrasen, Sätze und Wort-Kombos werden verworfen, weil
    /// das Akzent-Training auf Einzelwort-Ebene operiert. Ein Eintrag
    /// wie „se présenter et autres" wäre hier sinnlos.
    private static func makeSeedFromUserWord(_ word: String) -> AccentWordCatalog.SeedEntry? {
        // 1) Muss ein Einzelwort sein — keine Spaces, kein Bindestrich-
        //    Gruppierung (apostrophe sind OK: l'école).
        guard !word.contains(" ") else { return nil }

        // 2) Vernünftige Länge — unter 3 Zeichen kaum Akzent-Trainings-Wert,
        //    über 18 Zeichen wird's auf dem Screen unleserlich.
        guard word.count >= 3, word.count <= 18 else { return nil }

        // 3) Nur Buchstaben + Akzente + optional Apostroph/Bindestrich.
        //    Keine Zahlen, keine Satzzeichen wie „?,.!".
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: "'’-"))
        guard word.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

        // 4) Enthält einen MVP-Akzent?
        guard let (accentType, index) = primaryAccent(in: word) else { return nil }

        return AccentWordCatalog.SeedEntry(
            correctWord: word,
            accentType: accentType,
            targetIndex: index,
            difficulty: .medium
        )
    }

    /// Gibt den ersten gefundenen MVP-Akzent und dessen Char-Index
    /// zurück. Nil, wenn keiner drin ist.
    private static func primaryAccent(in word: String) -> (AccentType, Int)? {
        for (i, char) in word.enumerated() {
            switch char {
            case "é": return (.aigu, i)
            case "è": return (.grave, i)
            case "ê": return (.circonflexe, i)
            case "ç": return (.cedille, i)
            default: continue
            }
        }
        return nil
    }

    // MARK: - Exercise-Generierung

    private static func makeExercise(from seed: AccentWordCatalog.SeedEntry, kind: AccentExercise.Kind) -> AccentExercise? {
        switch kind {
        case .pickCorrectWord:
            return makePickExercise(seed: seed)
        case .chooseAccent:
            return makeAccentExercise(seed: seed)
        case .listenAndPick:
            // Audio-Variante teilt die Distraktor-Logik mit pickCorrectWord.
            // Unterschied: das Wort wird dem User **nicht** visuell gezeigt,
            // sondern per TTS vorgelesen. Die Options sind dieselben.
            guard var base = makePickExercise(seed: seed) else { return nil }
            base = AccentExercise(
                id: base.id,
                kind: .listenAndPick,
                difficulty: base.difficulty,
                baseWord: base.baseWord,
                correctWord: base.correctWord,
                accentType: base.accentType,
                targetCharacterIndex: base.targetCharacterIndex,
                options: base.options,
                letterVariants: base.letterVariants,
                explanation: base.explanation
            )
            return base
        }
    }

    /// Variante A: korrekte Form + 3 plausible Distraktoren.
    /// Distraktoren = dieselbe Form, aber mit anderem Akzent am selben
    /// Zeichen (z. B. école → ecole / ècole / êcole).
    private static func makePickExercise(seed: AccentWordCatalog.SeedEntry) -> AccentExercise? {
        // Safety-Net: Falls `targetIndex` aus dem Catalog auf ein Nicht-
        // akzentuiertes Zeichen zeigt, berechne ihn automatisch neu.
        // Schützt vor Catalog-Tippfehlern, die sonst das falsche Zeichen
        // in der UI markieren / demaskieren würden.
        guard let effectiveIndex = sanitizedTargetIndex(for: seed) else { return nil }

        let base = removingAccent(from: seed.correctWord, at: effectiveIndex)

        // Distraktoren: die anderen möglichen Akzent-Varianten am Target-Index.
        let distractorChars = distractorCharacters(for: seed.accentType, baseChar: baseChar(for: seed.accentType))
        var distractors: [String] = []
        for char in distractorChars {
            if let replaced = replaceCharacter(in: seed.correctWord, at: effectiveIndex, with: char) {
                if replaced != seed.correctWord {
                    distractors.append(replaced)
                }
            }
        }
        // Immer auch die Base (ohne Akzent) als Distraktor mitführen — ist
        // didaktisch der wichtigste Fall.
        if !distractors.contains(base) {
            distractors.insert(base, at: 0)
        }

        // Auf max. 3 kürzen, Reihenfolge mischen.
        let finalDistractors = Array(distractors.shuffled().prefix(3))

        return AccentExercise(
            id: UUID(),
            kind: .pickCorrectWord,
            difficulty: seed.difficulty,
            baseWord: base,
            correctWord: seed.correctWord,
            accentType: seed.accentType,
            targetCharacterIndex: effectiveIndex,
            options: finalDistractors,
            letterVariants: [],
            explanation: explanation(for: seed.accentType, correctWord: seed.correctWord)
        )
    }

    /// Prüft den deklarierten `targetIndex` eines Seeds gegen das
    /// tatsächliche Zeichen im `correctWord`. Wenn das Zeichen an diesem
    /// Index **nicht** zum deklarierten Akzenttyp passt (z. B. Index
    /// zeigt auf „t" statt „ê"), sucht die Methode automatisch den
    /// ersten passenden Akzent im Wort und korrigiert den Index.
    /// Nil nur, wenn das Wort gar kein Zeichen des Akzenttyps enthält.
    private static func sanitizedTargetIndex(for seed: AccentWordCatalog.SeedEntry) -> Int? {
        let chars = Array(seed.correctWord)
        // Alle gültigen Zielzeichen für diesen Akzenttyp.
        let validChars: Set<Character> = {
            switch seed.accentType {
            case .aigu:        return ["é"]
            case .grave:       return ["è", "à", "ù"]
            case .circonflexe: return ["ê", "â", "î", "ô", "û"]
            case .cedille:     return ["ç"]
            case .trema:       return ["ë", "ï", "ü"]
            case .none:        return []
            }
        }()

        // 1) Wenn der deklarierte Index bereits stimmt → behalten.
        if seed.targetIndex >= 0, seed.targetIndex < chars.count,
           validChars.contains(chars[seed.targetIndex]) {
            return seed.targetIndex
        }

        // 2) Auto-Detect: den ersten passenden Akzent im Wort finden.
        for (idx, c) in chars.enumerated() where validChars.contains(c) {
            return idx
        }

        // 3) Kein passender Akzent im Wort vorhanden → Seed ist kaputt.
        return nil
    }

    /// Variante B: Nutzer wählt das richtige Zeichen an der Target-Position.
    /// Die Letter-Varianten hängen vom Akzenttyp ab:
    ///   - é/è/ê  → ["e", "é", "è", "ê"]
    ///   - ç      → ["c", "ç"]
    private static func makeAccentExercise(seed: AccentWordCatalog.SeedEntry) -> AccentExercise? {
        guard let effectiveIndex = sanitizedTargetIndex(for: seed) else { return nil }
        let base = removingAccent(from: seed.correctWord, at: effectiveIndex)

        // Für Variante B wird das **tatsächliche Zeichen am
        // effectiveIndex** als Korrektheits-Referenz genutzt — sicherer
        // als ein abgeleitetes `correctCharacter(for: accentType)`, weil
        // bei circonflexe auch â/ô/î/û vorkommen können.
        let correctChar = String(Array(seed.correctWord)[effectiveIndex])

        let variants: [String]
        switch seed.accentType {
        case .cedille:
            variants = ["c", "ç"]
        case .aigu, .grave, .circonflexe:
            // Für Buchstaben-basierte Akzente bieten wir immer alle 4
            // e-Varianten an. Wenn der Akzent auf â/ô/î/û sitzt,
            // passt `variants` nicht — dann machen wir chooseAccent
            // hier nicht sinnvoll und fallen aus dem Kind raus.
            if ["ê", "é", "è", "e"].contains(correctChar) {
                variants = ["e", "é", "è", "ê"]
            } else {
                // â/ô/î/û → chooseAccent-Variante B hier nicht sinnvoll;
                // Seed kann trotzdem als pickCorrectWord genutzt werden.
                return nil
            }
        case .trema, .none:
            return nil
        }

        guard variants.contains(correctChar) else { return nil }

        return AccentExercise(
            id: UUID(),
            kind: .chooseAccent,
            difficulty: seed.difficulty,
            baseWord: base,
            correctWord: seed.correctWord,
            accentType: seed.accentType,
            targetCharacterIndex: effectiveIndex,
            options: [],
            letterVariants: variants,
            explanation: explanation(for: seed.accentType, correctWord: seed.correctWord)
        )
    }

    // MARK: - Zeichen-Helfer

    /// Das Akzent-Zeichen, das zum Typ gehört.
    private static func correctCharacter(for type: AccentType) -> Character {
        switch type {
        case .aigu: return "é"
        case .grave: return "è"
        case .circonflexe: return "ê"
        case .cedille: return "ç"
        case .trema: return "ë"
        case .none: return "e"
        }
    }

    /// Das Basis-Zeichen ohne Akzent (e für e-Akzente, c für cédille).
    private static func baseChar(for type: AccentType) -> Character {
        switch type {
        case .cedille: return "c"
        case .aigu, .grave, .circonflexe, .trema: return "e"
        case .none: return "e"
        }
    }

    /// Welche Akzent-Zeichen kommen als Distraktoren in Frage?
    /// Bewusst nur die MVP-Akzente — keine exotischen Optionen, die den
    /// Nutzer verwirren.
    private static func distractorCharacters(for type: AccentType, baseChar: Character) -> [Character] {
        if baseChar == "c" {
            // Cédille → nur c vs ç — das reicht.
            return ["c"]
        }
        // Für e-Akzente: die drei anderen Formen.
        switch type {
        case .aigu: return ["è", "ê"]
        case .grave: return ["é", "ê"]
        case .circonflexe: return ["é", "è"]
        default: return ["è", "ê"]
        }
    }

    /// Ersetzt das Zeichen an `index` (Unicode-sicher).
    private static func replaceCharacter(in word: String, at index: Int, with char: Character) -> String? {
        guard index >= 0, index < word.count else { return nil }
        let stringIndex = word.index(word.startIndex, offsetBy: index)
        var chars = Array(word)
        chars[index] = char
        _ = stringIndex
        return String(chars)
    }

    /// Entfernt den Akzent am Target-Index — daraus wird `baseWord`.
    private static func removingAccent(from word: String, at index: Int) -> String {
        guard index >= 0, index < word.count else { return word }
        var chars = Array(word)
        let originalChar = chars[index]
        let stripped: Character
        switch originalChar {
        case "é", "è", "ê", "ë": stripped = "e"
        case "à", "â": stripped = "a"
        case "î", "ï": stripped = "i"
        case "ô": stripped = "o"
        case "ù", "û", "ü": stripped = "u"
        case "ç": stripped = "c"
        default: stripped = originalChar
        }
        chars[index] = stripped
        return String(chars)
    }

    // MARK: - Feedback-Texte

    /// Kurze Erklärung, die nach einer falschen Antwort gezeigt wird.
    /// Bewusst knapp und motivierend gehalten.
    private static func explanation(for type: AccentType, correctWord: String) -> String {
        switch type {
        case .aigu:
            return "\(correctWord) — hier wird aus e ein é (accent aigu)."
        case .grave:
            return "\(correctWord) — der accent grave (è) ist hier gefragt."
        case .circonflexe:
            return "\(correctWord) — der accent circonflexe (ê) gehört dazu."
        case .cedille:
            return "\(correctWord) — aus c wird hier eine cédille (ç)."
        case .trema:
            return "\(correctWord) — Tréma (ë / ï)."
        case .none:
            return "\(correctWord) — kein Akzent nötig."
        }
    }

    // **Stufe 6 (2026-05-02)** — `LearningCard` mit dem Lernen-Modus
    // entfernt.
}
