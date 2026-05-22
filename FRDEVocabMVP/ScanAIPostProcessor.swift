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

        // **Bug-Fix 2026-04-24 (Meta-Leak)**: Allererster Pass —
        // Meta-Marker `(m)` / `(f)` / `(pl.)` / `(adj.)` etc. aus
        // source/target rausziehen, BEVOR irgendeine andere
        // Normalisierung läuft. Sonst landen die Marker als
        // sichtbarer Vokabel-Text. Den extrahierten Marker
        // hängen wir defensiv ans `wordClass`-Feld an, falls leer —
        // sichtbare Pill-UI greift schon auf `wordClass` zu.
        let metaStripped = payload.entries.map(stripMetaMarkers)

        // Common Safety-Passes: gelten für beide Modi.
        let scrubbed = metaStripped.map { entry -> ScanAIResponseEntry in
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
        let expandedEntries = processedEntries.map { entry -> ScanAIResponseEntry in
            let expanded = applyAbbreviationExpansion(
                entry: entry,
                policy: expansionPolicy
            )
            if expanded.target != entry.target {
                metrics.abbreviationExpansionCount += 1
            }
            return expanded
        }

        // **Bug-Fix 2026-04-24 (Token-Drop in Phrasen)**: Phrasen-
        // Honorific-Check. Ergänzt fehlende Anreden (`Madame`/
        // `Monsieur`/`Mademoiselle`) im Zieltext per Injection
        // und markiert den Eintrag als review-required.
        let honorificChecked = expandedEntries.map(validatePhraseHonorificPreservation)

        // **Style-Rule 2026-04-25**: Produkt-Style-Vereinheitlichung
        // für typisch deutsche Phrasen. Aktuell nur eine Regel:
        // `wie viel Uhr` → `wieviel Uhr`. Der Pass ist bewusst
        // **phrase-spezifisch** (nicht alle `wie viel`-Vorkommen),
        // um keine unverwandten Sätze zu verändern.
        let styleApplied = honorificChecked.map(applyGermanStyleRules)

        // **Bug-Fix 2026-04-25 (Nomen-Kapitalisierung)**: Letzter Pass —
        // wenn der Eintrag als Nomen klassifiziert ist und das
        // deutsche Ziel klein beginnt, wird der erste Nomen-Token
        // korrekt großgeschrieben. Systemisch über die ganze Scan-
        // Pipeline, nicht nur Migration.
        let finalEntries = styleApplied.map(capitalizeGermanNounTarget)

        metrics.finalCount = finalEntries.count

        #if DEBUG
        appDebugLog("""
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
                appDebugLog("🔖 [FreeText-Context] skip \"\(entry.source)\": high confidence (\(entry.confidence)), no conflict")
                #endif
                return entry
            }

            overrides += 1
            #if DEBUG
            appDebugLog("🔖 [FreeText-Context] override \"\(entry.source)\"/\"\(entry.target)\": \(currentLabel ?? "nil") → \(refinedLabel) (conf=\(entry.confidence), conflict=\(hasConflict))")
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
            appDebugLog("🧹 [FreeText-Filter] \(removed)/\(entries.count) Einträge entfernt (echter Noise/Duplikate, context-aware)")
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
                appDebugLog("📡 [Scan] DualForm nicht gesplittet (\"\(entry.source)\"): \(decision.rationale)")
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

    // MARK: - Bug-Fix 2026-04-24: Meta-Marker-Strip + Phrase-Honorific-Check

    /// **Meta-Marker-Strip** (Bug C): Extrahiert grammatikalische
    /// Annotations-Marker `(m)`, `(f)`, `(pl.)` etc. aus source/target,
    /// damit sie nicht als sichtbarer Vokabel-Text bleiben. Den
    /// extrahierten Marker hängen wir als Note an und füllen
    /// `wordClass` bzw. die strukturelle Note auf, damit das Genus
    /// in der UI als Pill auftauchen kann.
    static func stripMetaMarkers(_ entry: ScanAIResponseEntry) -> ScanAIResponseEntry {
        let sourceResult = ScanMetaMarkerExtractor.extract(from: entry.source)
        let targetResult = ScanMetaMarkerExtractor.extract(from: entry.target)

        // Wenn auf keiner Seite ein Marker → keine Mutation.
        if sourceResult.normalizedMarker == nil && targetResult.normalizedMarker == nil {
            return entry
        }

        // Marker-Notizen sammeln.
        var collectedNotes = entry.notes
        if let sm = sourceResult.normalizedMarker {
            collectedNotes.append("source-marker:\(sm)")
        }
        if let tm = targetResult.normalizedMarker, tm != sourceResult.normalizedMarker {
            collectedNotes.append("target-marker:\(tm)")
        }

        // wordClass auffüllen: wenn leer und Marker einen Genus liefert,
        // setzen wir mindestens „noun". Der separate Genus-Tag landet
        // in den Notes — die Genus-Anzeige (Listen-Pill) konsultiert den
        // DB-Lexikon-Lookup ohnehin selbst.
        let resolvedWordClass: String? = {
            if let existing = entry.wordClass, !existing.isEmpty {
                return existing
            }
            // Marker wie m/f/pl deuten klar auf ein Nomen.
            let genderHints: Set<String> = ["m", "f", "n", "pl"]
            if let sm = sourceResult.normalizedMarker, genderHints.contains(sm) {
                return "noun"
            }
            if let tm = targetResult.normalizedMarker, genderHints.contains(tm) {
                return "noun"
            }
            return entry.wordClass
        }()

        #if DEBUG
        let sm = sourceResult.normalizedMarker ?? "-"
        let tm = targetResult.normalizedMarker ?? "-"
        appDebugLog("📋 [Meta-Strip] '\(entry.source)' -> '\(sourceResult.cleanedText)' (s:\(sm)/t:\(tm))")
        #endif

        return ScanAIResponseEntry(
            source: sourceResult.cleanedText,
            target: targetResult.cleanedText,
            cardType: entry.cardType,
            sourcePhonetic: entry.sourcePhonetic,
            targetPhonetic: entry.targetPhonetic,
            confidence: entry.confidence,
            reviewMetadata: entry.reviewMetadata,
            notes: collectedNotes,
            wordClass: resolvedWordClass
        )
    }

    /// **Phrase-Honorific-Check** (Bug B — 2026-04-25 systemischer
    /// Rewrite):
    ///
    /// Wenn die Quelle Anreden wie `madame`, `monsieur`, `mademoiselle`
    /// enthält und das Ziel KEINE entsprechende Form hat, ist das KEINE
    /// diffuse „Unsicherheit" — es ist ein **konkreter Token-Verlust**.
    ///
    /// Vorher: Der fehlende Token wurde nur als `isImportable: false`
    /// markiert, der Zieltext blieb leer bzw. unvollständig. Der Nutzer
    /// musste manuell nachschreiben.
    ///
    /// Jetzt (User-Spec 2026-04-25):
    ///   1. Detektieren wir fehlende geschützte Anreden (wie vorher).
    ///   2. **Injizieren** die Anrede als deutsches Loanword-Äquivalent
    ///      (`Madame`, `Monsieur`, `Mademoiselle` — kapitalisiert) an
    ///      einer natürlichen Stelle im Zieltext:
    ///        • nach dem ersten Komma (typisches „Entschuldigung, …"-
    ///          Muster bei höflicher Anrede),
    ///        • sonst vor dem Satzendzeichen,
    ///        • sonst am Ende.
    ///   3. Markieren das Ergebnis mit einem strukturellen Note
    ///      `injected-honorific:…` **und** halten es als
    ///      `isImportable: false` fest, sodass der Nutzer die Injektion
    ///      im Review bestätigen kann. Note-Text erklärt explizit, dass
    ///      eine Anrede auto-injiziert wurde — kein pauschales „unsicher".
    ///   4. Senken die Confidence leicht (damit UI-seitige Low-Confidence-
    ///      Filter den Eintrag konsistent behandeln).
    static func validatePhraseHonorificPreservation(_ entry: ScanAIResponseEntry) -> ScanAIResponseEntry {
        // Nur für Phrasen relevant.
        guard entry.cardType == .phrases else { return entry }

        let sourceLower = entry.source.lowercased()
        let targetLower = entry.target.lowercased()

        struct HonorificPair {
            let sourceTokens: [String]
            let targetTokens: [String]
            let injectionForm: String  // Kapitalisierte Form, die in den Zieltext eingefügt wird.
            let label: String
        }

        let pairs: [HonorificPair] = [
            HonorificPair(
                sourceTokens: ["madame"],
                targetTokens: ["frau", "madame", "gnädige frau"],
                injectionForm: "Madame",
                label: "madame"
            ),
            HonorificPair(
                sourceTokens: ["monsieur"],
                targetTokens: ["herr", "monsieur", "mein herr"],
                injectionForm: "Monsieur",
                label: "monsieur"
            ),
            HonorificPair(
                sourceTokens: ["mademoiselle"],
                targetTokens: ["fräulein", "mademoiselle", "junge frau"],
                injectionForm: "Mademoiselle",
                label: "mademoiselle"
            )
        ]

        var missingForInjection: [HonorificPair] = []
        for pair in pairs {
            let inSource = pair.sourceTokens.contains { sourceLower.contains($0) }
            let inTarget = pair.targetTokens.contains { targetLower.contains($0) }
            if inSource && !inTarget {
                missingForInjection.append(pair)
            }
        }

        guard !missingForInjection.isEmpty else { return entry }

        // Injektion durchführen.
        var updatedTarget = entry.target
        for pair in missingForInjection {
            updatedTarget = injectHonorific(pair.injectionForm, into: updatedTarget)
        }

        let missingLabels = missingForInjection.map(\.label)
        var augmentedNotes = entry.notes
        augmentedNotes.append("injected-honorific:\(missingLabels.joined(separator: ","))")

        let augmentedReviewMetadata = ScanEntryReviewMetadata(
            learningCategory: entry.reviewMetadata.learningCategory,
            note: "Anrede(n) '\(missingLabels.joined(separator: ", "))' wurde(n) automatisch ergänzt – bitte prüfen.",
            isImportable: false
        )

        // Confidence leicht senken, damit Low-Confidence-UI-Filter
        // (falls vorhanden) den Eintrag als „auto-korrigiert" einstufen.
        let reducedConfidence = min(entry.confidence, 0.55)

        #if DEBUG
        appDebugLog("🔧 [Honorific-Injection] '\(entry.source)' -> '\(entry.target)' → '\(updatedTarget)' (injected: \(missingLabels))")
        #endif

        return ScanAIResponseEntry(
            source: entry.source,
            target: updatedTarget,
            cardType: entry.cardType,
            sourcePhonetic: entry.sourcePhonetic,
            targetPhonetic: entry.targetPhonetic,
            confidence: reducedConfidence,
            reviewMetadata: augmentedReviewMetadata,
            notes: augmentedNotes,
            wordClass: entry.wordClass
        )
    }

    /// Fügt einen Anrede-Token an einer natürlichen Stelle im deutschen
    /// Zieltext ein. Strategie:
    ///   1. Wenn der Text ein erstes Komma enthält (typisch
    ///      „Entschuldigung, …"), setzen wir die Anrede direkt
    ///      **dahinter** — mit neuem Komma-Trenner:
    ///      „Entschuldigung, **Madame,** wie spät ist es?"
    ///   2. Wenn kein Komma vorhanden, aber ein Satzendzeichen
    ///      (`.`, `?`, `!`), fügen wir vor dem Endzeichen mit
    ///      Komma-Trenner ein: „Wie spät ist es**, Madame?"
    ///   3. Fallback: an den Satz anhängen.
    private static func injectHonorific(_ honorific: String, into target: String) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Leerer Zieltext: nur die Anrede allein ergibt wenig Sinn,
            // aber besser als Leerstring — markiert klar, dass etwas
            // fehlt.
            return honorific
        }

        // Schon drin? (Defensive — sollte durch den Caller-Check
        // eigentlich nicht passieren.)
        if trimmed.lowercased().contains(honorific.lowercased()) {
            return trimmed
        }

        // 1. Erstes Komma.
        if let commaIndex = trimmed.firstIndex(of: ",") {
            let afterComma = trimmed.index(after: commaIndex)
            if afterComma < trimmed.endIndex {
                let head = trimmed[..<commaIndex]
                // `rest` beginnt mit dem Zeichen direkt nach dem Komma
                // — typischerweise ein Whitespace.
                let rest = trimmed[afterComma...].drop(while: { $0 == " " })
                return "\(head), \(honorific), \(rest)"
            }
        }

        // 2. Satzendzeichen.
        let endingPunctuation: Set<Character> = ["?", "!", "."]
        if let last = trimmed.last, endingPunctuation.contains(last) {
            let body = trimmed.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(body), \(honorific)\(last)"
        }

        // 3. Fallback.
        return "\(trimmed), \(honorific)"
    }

    // MARK: - POS-aware German Noun Capitalization

    /// **Nomen-Kapitalisierung** (Bug-Fix 2026-04-25, User-Spec
    /// „montre → Uhr", „question → Frage").
    ///
    /// Wenn der Eintrag als Nomen klassifiziert ist (`wordClass` ∈
    /// {noun, nomen, substantiv}), MUSS das deutsche Ziel korrekt
    /// großgeschrieben sein. Der Pass greift am Ende der
    /// Postprocessing-Kaskade — nach Abkürzungs-Normalisierung und
    /// Honorific-Injection — damit keine spätere Stage das Casing
    /// wieder kaputt macht.
    ///
    /// Regel:
    ///   • Artikel (`der/die/das/ein/…`) bleiben klein.
    ///   • Das ERSTE Nicht-Artikel-Wort wird großgeschrieben (das ist
    ///     bei Nomen-Einträgen im Regelfall das Nomen selbst).
    ///   • Weitere Wörter werden NICHT verändert — kein pauschales
    ///     Title-Case, kein Eingriff bei Adjektiven/Verben in
    ///     komplexeren Targets.
    ///
    /// Greift NUR wenn das Target WIRKLICH kleingeschrieben ist —
    /// bereits korrekt kapitalisierte Einträge werden durchgelassen.
    static func capitalizeGermanNounTarget(_ entry: ScanAIResponseEntry) -> ScanAIResponseEntry {
        // Single Source of Truth: `GermanNounCapitalization` führt die
        // POS-Gate-Regel (`wordClass == noun`) und die Wort-Logik
        // (erstes Nicht-Artikel-Wort groß) in einer Stelle aus.
        let capitalized = GermanNounCapitalization.normalizeGermanNounTarget(
            entry.target,
            wordClass: entry.wordClass
        )
        guard capitalized != entry.target else { return entry }

        #if DEBUG
        appDebugLog("🔠 [Noun-Cap] '\(entry.target)' → '\(capitalized)' (wc=\(entry.wordClass ?? "nil"))")
        #endif

        return ScanAIResponseEntry(
            source: entry.source,
            target: capitalized,
            cardType: entry.cardType,
            sourcePhonetic: entry.sourcePhonetic,
            targetPhonetic: entry.targetPhonetic,
            confidence: entry.confidence,
            reviewMetadata: entry.reviewMetadata,
            notes: entry.notes,
            wordClass: entry.wordClass
        )
    }

    // **Refactor 2026-04-25**: Die frühere lokale Helper-Implementierung
    // (`capitalizeFirstNounWord` + `capitalizeFirstLetterOf`) lebt jetzt
    // zentral in `GermanNounCapitalization.swift`. Dieser Call-Site
    // delegiert über `normalizeGermanNounTarget` an die Utility.

    // MARK: - Deutsche Style-Regeln (2026-04-25)

    /// Produkt-Style-Vereinheitlichung für typisch deutsche Phrasen im
    /// Zieltext. Läuft als eigener Pass zwischen Honorific-Injection und
    /// Nomen-Kapitalisierung.
    ///
    /// **Aktuell nur eine Regel**:
    ///   • `wie viel Uhr` → `wieviel Uhr`
    ///     (case-insensitive Match, behält die Kapitalisierung von
    ///     `Uhr`, falls bereits großgeschrieben; ansonsten übernimmt
    ///     der nachfolgende `capitalizeGermanNounTarget`-Pass das
    ///     korrekte Casing).
    ///
    /// Phrase-spezifisch, damit unverwandte „wie viel"-Vorkommen
    /// (z. B. „wie viel kostet das?") nicht verändert werden.
    static func applyGermanStyleRules(_ entry: ScanAIResponseEntry) -> ScanAIResponseEntry {
        guard !entry.target.isEmpty else { return entry }

        var text = entry.target
        // Regel 1: „wie viel Uhr" → „wieviel Uhr" (case-insensitive).
        // Wir matchen den Whitespace flexibel (`\s+`), damit auch
        // Mehrfach-Spaces oder Umbrüche normalisiert werden.
        if let regex = try? NSRegularExpression(
            pattern: #"\bwie\s+viel(\s+Uhr\b)"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(
                in: text,
                options: [],
                range: range,
                withTemplate: "wieviel$1"
            )
        }

        guard text != entry.target else { return entry }

        #if DEBUG
        appDebugLog("✍️  [GermanStyle] '\(entry.target)' → '\(text)'")
        #endif

        return ScanAIResponseEntry(
            source: entry.source,
            target: text,
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
