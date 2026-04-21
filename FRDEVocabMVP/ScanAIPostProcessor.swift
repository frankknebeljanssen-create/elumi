import Foundation

/// Post-Processing für die vom LLM gelieferten Scan-Ergebnisse.
///
/// Zwei Aufgaben, beide User-getrieben:
///
/// 1. **Mirrored-Target-Scrub** — der User berichtete, dass bei
///    unsicheren Einträgen der französische Text 1:1 im deutschen
///    Übersetzungs-Feld landete. Kann passieren, wenn das LLM
///    keine sichere Übersetzung kennt und die Quelle als Fallback
///    echo-iert. Wir leeren das target-Feld in diesem Fall und
///    markieren den Eintrag als `isImportable: false`, damit der
///    User im Review die Übersetzung ergänzt statt den falschen
///    Echo zu importieren.
///
/// 2. **Dual-Form-Split** — Einträge wie „l'ami/l'amie" /
///    „der Freund/die Freundin" waren bisher EIN Entry mit Schrägstrich.
///    User-Wunsch: jede Form einzeln lernbar machen → zwei Entries.
///    Wir splitten nur, wenn source UND target je einen Schrägstrich
///    enthalten und beide Seiten dieselbe Anzahl Teile liefern (sonst
///    ist das Mapping nicht eindeutig).
enum ScanAIPostProcessor {

    /// **AP10** — Telemetrie über einen einzelnen Scan. Wird pro
    /// `apply(to:)`-Aufruf aggregiert und am Ende zusammengefasst
    /// geloggt. Ziel: Verhalten messbar machen, Debug vereinfachen.
    struct ScanMetrics {
        var inputCount: Int = 0
        var scrubbedTargetCount: Int = 0
        var splitCount: Int = 0          // zusätzliche Einträge durch Split
        var splitSkippedCount: Int = 0   // potenzielle Splits unter threshold
        var mergeCount: Int = 0          // eingesparte Einträge durch Merge
        var filteredCount: Int = 0
        var contextOverrideCount: Int = 0
        var abbreviationExpansionCount: Int = 0
        var finalCount: Int = 0
    }

    /// Wendet alle Safety-Passes auf das Payload an.
    ///
    /// Mode-abhängig (Produkt-Entscheidung):
    ///   • `.list` (vocabularyList): nur Split + Scrub. Alles
    ///     Eingescannte bleibt erhalten, keine smarten Merges oder
    ///     Filter — das ist bewusst ausgewähltes Lernmaterial.
    ///   • `.text` (freeText): zusätzlich vorsichtige Context-
    ///     Refinement (AP8), **begrenzter** Merge (AP7, nur
    ///     Artikel+Nomen) und **safer** Filter (AP9).
    static func apply(to payload: ScanAIResponsePayload) -> ScanAIResponsePayload {
        var metrics = ScanMetrics()
        metrics.inputCount = payload.entries.count

        // Common Safety-Passes: gelten für beide Modi.
        let scrubbed = payload.entries.map { entry -> ScanAIResponseEntry in
            let after = scrubMirroredTarget(entry)
            if after.target != entry.target { metrics.scrubbedTargetCount += 1 }
            return after
        }
        let expanded = scrubbed.flatMap { entry -> [ScanAIResponseEntry] in
            let parts = splitDualForm(entry)
            if parts.count > 1 { metrics.splitCount += parts.count - 1 }
            return parts
        }

        // FreeText-only: zusätzliche intelligente Schichten.
        let processedEntries: [ScanAIResponseEntry]
        if payload.mode == .text {
            processedEntries = processFreeText(entries: expanded, metrics: &metrics)
        } else {
            processedEntries = expanded
        }

        // **Abkürzungs-Normalisierung** — in **beiden** Modi, aber
        // mit unterschiedlicher Policy:
        //   • FreeText  → `.exactAndInline` (auch „Köln Hbf" →
        //     „Köln Hauptbahnhof (Hbf)" mitten im Text).
        //   • VocabList → `.exactOnly` (vollständiges Target =
        //     Abkürzung wird erweitert; Teilstrings bleiben stehen,
        //     weil der Lehrer die Wahl bewusst getroffen haben könnte).
        let expansionPolicy: GermanAbbreviationExpander.Policy =
            (payload.mode == .text) ? .exactAndInline : .exactOnly
        let finalEntries = processedEntries.map { entry -> ScanAIResponseEntry in
            let expanded = applyAbbreviationExpansion(
                entry: entry,
                policy: expansionPolicy
            )
            if expanded.target != entry.target {
                metrics.abbreviationExpansionCount += 1
            }
            return expanded
        }

        metrics.finalCount = finalEntries.count

        #if DEBUG
        print("""
        📊 [Scan Summary]
          mode: \(payload.mode.rawValue)
          input: \(metrics.inputCount)
          scrubbed (target=source): \(metrics.scrubbedTargetCount)
          splits (added): \(metrics.splitCount)
          splits skipped (low-confidence): \(metrics.splitSkippedCount)
          merges (removed): \(metrics.mergeCount)
          filtered (noise/dupes): \(metrics.filteredCount)
          context overrides: \(metrics.contextOverrideCount)
          abbreviation expansions: \(metrics.abbreviationExpansionCount)
          final: \(metrics.finalCount)
        """)
        #endif

        return ScanAIResponsePayload(
            documentType: payload.documentType,
            mode: payload.mode,
            sourceLanguage: payload.sourceLanguage,
            entries: finalEntries,
            warnings: payload.warnings,
            summary: payload.summary,
            importMessage: payload.importMessage,
            confidence: payload.confidence,
            usedColumnPairing: payload.usedColumnPairing,
            recognizedLineCount: payload.recognizedLineCount
        )
    }

    // MARK: - FreeText-Pipeline (AP2 + AP7 + AP8 + AP9)

    /// FreeText-spezifische Post-Processing-Kaskade (nur bei
    /// `mode == .text`).
    ///
    /// Ordnung nach AP2:
    ///   1. Context-Refinement (AP8: soft — nur bei niedriger Confidence
    ///      oder klarem Konflikt)
    ///   2. Selective Merge (AP7: nur Artikel+Nomen, keine Gender-
    ///      Varianten-/Sing-Plu-Merges im Scan-Flow — zu aggressiv)
    ///   3. Light Filter (AP9: nachbar-context-aware, entfernt nur
    ///      echten OCR-Müll, nicht potenziell valide Kurzwörter)
    static func processFreeText(
        entries: [ScanAIResponseEntry],
        metrics: inout ScanMetrics
    ) -> [ScanAIResponseEntry] {
        var result = entries
        result = applyContextRefinement(result, metrics: &metrics)
        let preMerge = result.count
        result = applySelectiveMerge(result)
        metrics.mergeCount += max(0, preMerge - result.count)
        let preFilter = result.count
        result = applyLightFilter(result)
        metrics.filteredCount += max(0, preFilter - result.count)
        return result
    }

    /// **AP8 — Context-Classifier als Soft-Correction**.
    ///
    /// Override nur, wenn eine der beiden Bedingungen greift:
    ///   • `entry.confidence < 0.7` — das LLM war selbst unsicher
    ///   • Classifier-Signal **widerspricht** dem aktuellen `word_class`
    ///     (Conflict-Detection)
    ///
    /// Bei hoher LLM-Confidence und nicht-widersprechendem Kontext
    /// lassen wir die ursprüngliche Klassifikation stehen — sie war
    /// bereits vom Prompt-aware LLM gesetzt und kennt den Bildkontext,
    /// den wir auf der Post-Processing-Ebene nicht mehr haben.
    static func applyContextRefinement(
        _ entries: [ScanAIResponseEntry],
        metrics: inout ScanMetrics
    ) -> [ScanAIResponseEntry] {
        var overrides = 0
        let result = entries.map { entry -> ScanAIResponseEntry in
            guard let refined = VocabContextClassifier.refinedWordClass(
                french: entry.source,
                german: entry.target,
                storedWordClass: entry.wordClass
            ) else {
                return entry
            }
            let currentLabel = entry.wordClass?.lowercased()
            let refinedLabel = refined.rawWordClass
            // Nichts zu ändern, wenn der Classifier denselben Label liefert.
            guard refinedLabel != currentLabel else { return entry }

            // AP8-Gate: nur anwenden bei Konflikt UND entweder
            // niedriger LLM-Confidence oder klarem Widerspruch.
            let lowConfidence = entry.confidence < 0.7
            let hasConflict = (currentLabel != nil && refinedLabel != currentLabel)

            guard lowConfidence || hasConflict else {
                #if DEBUG
                print("🔖 [FreeText-Context] skip \"\(entry.source)\": high confidence (\(entry.confidence)), no conflict")
                #endif
                return entry
            }

            overrides += 1
            #if DEBUG
            print("🔖 [FreeText-Context] override \"\(entry.source)\"/\"\(entry.target)\": \(currentLabel ?? "nil") → \(refinedLabel) (conf=\(entry.confidence), conflict=\(hasConflict))")
            #endif
            return ScanAIResponseEntry(
                source: entry.source,
                target: entry.target,
                cardType: entry.cardType,
                sourcePhonetic: entry.sourcePhonetic,
                targetPhonetic: entry.targetPhonetic,
                confidence: entry.confidence,
                reviewMetadata: entry.reviewMetadata,
                notes: entry.notes,
                wordClass: refinedLabel
            )
        }
        metrics.contextOverrideCount += overrides
        return result
    }

    /// **AP7 — Selective Merge (Artikel+Nomen only)**.
    ///
    /// Im Live-FreeText-Flow mergen wir **nur** Artikel+Nomen-
    /// Fragmente (die eine klare Fehlparsung darstellen: „le" +
    /// „ami" sollte „l'ami" sein). Gender-Varianten (ami/amie) und
    /// Singular/Plural (école/écoles) bleiben **separat** —
    /// die sind granulares Lernmaterial, das der User mit hoher
    /// Wahrscheinlichkeit einzeln lernen will.
    ///
    /// Voller Merge (mit Varianten-Array) bleibt der Migration
    /// bestehender Listen vorbehalten, wo der User explizit Bestands-
    /// Aufräumung wollte.
    static func applySelectiveMerge(_ entries: [ScanAIResponseEntry]) -> [ScanAIResponseEntry] {
        let items = entries.map { entry in
            VocabularyItem(
                rawFrench: entry.source,
                rawGerman: entry.target,
                cardType: entry.cardType,
                wordClass: entry.wordClass
            )
        }
        let merged = VocabDualFormMerger.mergeArticleNounOnly(items)
        guard merged.count != items.count else { return entries }

        // Rückkonvertierung: Original-Entries bevorzugen (erhält
        // Metadata); neue merged-Items bekommen Default-Metadata.
        return merged.map { item in
            if let match = entries.first(where: {
                $0.source == item.french && $0.target == item.german
            }) {
                return match
            }
            return ScanAIResponseEntry(
                source: item.french,
                target: item.german,
                cardType: item.cardType,
                sourcePhonetic: nil,
                targetPhonetic: nil,
                confidence: 0.85,
                reviewMetadata: ScanEntryReviewMetadata(
                    learningCategory: nil,
                    note: nil,
                    isImportable: true
                ),
                notes: [],
                wordClass: item.wordClass
            )
        }
    }

    /// **AP9 — Safer Filter (nachbar-context-aware)**.
    ///
    /// Entfernt nur „echten Müll":
    ///   • Komplett leere Einträge
    ///   • Echte Duplikate
    ///   • Isolierte Artikel **nur wenn** kein Nachbar auf einen
    ///     Wortzusammenhang hinweist
    ///   • 1-Zeichen-Wörter **nur wenn** sie isoliert stehen (kein
    ///     inhaltlicher Nachbar mit verwandtem Stem/Thema)
    ///
    /// Für die Nachbar-Context-Bestimmung reicht uns der Listen-
    /// Index: ein Eintrag hat „Nachbar-Kontext", wenn direkt davor
    /// oder dahinter ein Eintrag **mit** richtigem Text liegt.
    static func applyLightFilter(_ entries: [ScanAIResponseEntry]) -> [ScanAIResponseEntry] {
        var seenKeys = Set<String>()
        var result: [ScanAIResponseEntry] = []
        for (index, entry) in entries.enumerated() {
            let src = entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
            let tgt = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)

            // Komplett leer → raus.
            if src.isEmpty && tgt.isEmpty { continue }

            // Nachbar-Kontext prüfen (AP9): gibt es einen validen
            // Nachbar-Eintrag direkt davor oder dahinter?
            let prev = index > 0 ? entries[index - 1] : nil
            let next = index < entries.count - 1 ? entries[index + 1] : nil
            let hasNeighborContext = (prev?.source.isEmpty == false)
                                    || (next?.source.isEmpty == false)

            if isRemovable(entry: entry, hasNeighborContext: hasNeighborContext) {
                continue
            }

            // Dedup (exakte source+target+class-Trios).
            let key = "\(src.lowercased())|\(tgt.lowercased())|\(entry.wordClass ?? "")"
            if !seenKeys.insert(key).inserted { continue }
            result.append(entry)
        }
        #if DEBUG
        let removed = entries.count - result.count
        if removed > 0 {
            print("🧹 [FreeText-Filter] \(removed)/\(entries.count) Einträge entfernt (echter Noise/Duplikate, context-aware)")
        }
        #endif
        return result
    }

    /// Entfernungs-Heuristik pro Eintrag (AP9). Konservativ: entfernen
    /// nur, wenn der Eintrag klar Noise ist UND kein Nachbar-Kontext
    /// seine Gültigkeit stützt.
    static func isRemovable(
        entry: ScanAIResponseEntry,
        hasNeighborContext: Bool
    ) -> Bool {
        let src = entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
        // 1-Zeichen: nur entfernen, wenn isoliert (kein Nachbar-Kontext).
        //   „a" allein in OCR-Output → Noise
        //   „a" zwischen zwei validen Zeilen → evtl. bewusste
        //   Einzel-Kurz-Vokabel (Indefinitartikel), behalten
        if src.count < 2 {
            return !hasNeighborContext
        }
        // Isolierter Artikel: nur entfernen, wenn ohne Nachbar-Kontext.
        //   „le" allein und nichts drumrum → Noise
        //   „le" mitten in einer Liste → evtl. Teil der Artikel-
        //   Übung, behalten
        if isIsolatedArticle(src) {
            return !hasNeighborContext
        }
        return false
    }

    /// Ist der Eintrag ein alleinstehender Artikel (ohne Nomen)?
    /// Typisch bei OCR-Fragmenten oder fehlgeleiteten Scan-Zeilen.
    private static func isIsolatedArticle(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let articles: Set<String> = [
            "le", "la", "les", "l'", "l’",
            "un", "une", "des", "du", "de",
            "mon", "ma", "mes", "ton", "ta", "tes",
            "son", "sa", "ses", "notre", "votre", "leur"
        ]
        return articles.contains(lower)
    }

    // MARK: - Mirrored-Target-Scrub

    /// Prüft, ob das LLM den Source-Text im Target-Feld echo-iert hat
    /// (direktes Matchen oder nach Normalisierung). Wenn ja: target
    /// leeren und Metadata auf `isImportable: false` setzen — der User
    /// muss im Review die Übersetzung eintragen.
    static func scrubMirroredTarget(_ entry: ScanAIResponseEntry) -> ScanAIResponseEntry {
        guard !entry.target.isEmpty else { return entry }
        if targetEchoesSource(source: entry.source, target: entry.target) {
            return ScanAIResponseEntry(
                source: entry.source,
                target: "",
                cardType: entry.cardType,
                sourcePhonetic: entry.sourcePhonetic,
                targetPhonetic: entry.targetPhonetic,
                confidence: min(entry.confidence, 0.3),
                reviewMetadata: ScanEntryReviewMetadata(
                    learningCategory: entry.reviewMetadata.learningCategory,
                    note: entry.reviewMetadata.note ?? "Übersetzung fehlt — bitte ergänzen",
                    isImportable: false
                ),
                notes: entry.notes,
                wordClass: entry.wordClass
            )
        }
        return entry
    }

    /// Prüft auf Echo mit leichter Toleranz — lowercase-vergleich +
    /// ohne führende Artikel. So erkennen wir auch „le chat" vs „chat"
    /// als Echo.
    private static func targetEchoesSource(source: String, target: String) -> Bool {
        let normalizedSource = normalize(source)
        let normalizedTarget = normalize(target)
        if normalizedSource == normalizedTarget { return true }
        let bareSource = dropLeadingFrenchArticle(normalizedSource)
        let bareTarget = dropLeadingFrenchArticle(normalizedTarget)
        if !bareSource.isEmpty, bareSource == bareTarget { return true }
        return false
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    private static func dropLeadingFrenchArticle(_ s: String) -> String {
        let articles = ["le ", "la ", "les ", "l'", "un ", "une ", "des ", "du ", "de la ", "de l'"]
        for a in articles where s.hasPrefix(a) {
            return String(s.dropFirst(a.count))
        }
        return s
    }

    // MARK: - Dual-Form-Split

    /// Delegiert an den shared `VocabDualFormSplitter` — gleiche
    /// Confidence-Logik wie für Bestands-Listen-Migration.
    static func splitDualForm(_ entry: ScanAIResponseEntry) -> [ScanAIResponseEntry] {
        let decision = VocabDualFormSplitter.attemptSplit(source: entry.source, target: entry.target)
        guard let parts = decision.parts else {
            #if DEBUG
            if decision.confidence < VocabDualFormSplitter.autoApplyThreshold,
               decision.confidence > 0.0,
               (entry.source.contains("/") || entry.source.contains(",")) {
                print("📡 [Scan] DualForm nicht gesplittet (\"\(entry.source)\"): \(decision.rationale)")
            }
            #endif
            return [entry]
        }
        return parts.map { part in
            ScanAIResponseEntry(
                source: part.source,
                target: part.target,
                cardType: entry.cardType,
                sourcePhonetic: entry.sourcePhonetic,
                targetPhonetic: entry.targetPhonetic,
                confidence: entry.confidence,
                reviewMetadata: entry.reviewMetadata,
                notes: entry.notes,
                wordClass: entry.wordClass
            )
        }
    }

    // MARK: - Abkürzungs-Normalisierung (AP: Smart Expansion)

    /// Wendet `GermanAbbreviationExpander` auf das Target-Feld eines
    /// Entries an. Entscheidet anhand der `wordClass`, ob ein Artikel
    /// automatisch eingefügt werden soll.
    ///
    /// - Parameters:
    ///   - entry: Zu normalisierender Eintrag
    ///   - policy: Exact-only vs exact+inline (je nach Scan-Modus)
    /// - Returns: Eintrag mit ggf. normalisiertem Target. Quelle und
    ///   alle anderen Felder bleiben unverändert — wir verändern nur
    ///   die Zielsprache-Darstellung, nicht die Semantik des
    ///   Lerninhalts.
    static func applyAbbreviationExpansion(
        entry: ScanAIResponseEntry,
        policy: GermanAbbreviationExpander.Policy
    ) -> ScanAIResponseEntry {
        let isNoun = (entry.wordClass?.lowercased() == "noun")
        let (normalized, didChange) = GermanAbbreviationExpander.expand(
            entry.target,
            isNoun: isNoun,
            policy: policy
        )
        guard didChange else { return entry }
        return ScanAIResponseEntry(
            source: entry.source,
            target: normalized,
            cardType: entry.cardType,
            sourcePhonetic: entry.sourcePhonetic,
            targetPhonetic: entry.targetPhonetic,
            confidence: entry.confidence,
            reviewMetadata: entry.reviewMetadata,
            notes: entry.notes,
            wordClass: entry.wordClass
        )
    }
}
