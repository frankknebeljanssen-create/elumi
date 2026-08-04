import SwiftUI

struct IdentifiableUUID: Identifiable {
    let id: UUID
    init(_ uuid: UUID) { self.id = uuid }
}

struct ReviewPairEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var french: String
    @State var german: String
    @State var wordClass: String
    let onSave: (String, String, String?) -> Void

    private let wordClassOptions: [(key: String, label: String)] = [
        ("noun", "Nomen"),
        ("verb", "Verb"),
        ("adjective", "Adjektiv"),
        ("adverb", "Adverb"),
        ("preposition", "Pr\u{00E4}position"),
        ("pronoun", "Pronomen"),
        ("conjunction", "Konjunktion"),
        ("", "Andere"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Franz\u{00F6}sisch")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    TextField("Franz\u{00F6}sisch", text: $french)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Deutsch")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    TextField("Deutsch", text: $german)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wortart")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(wordClassOptions, id: \.key) { option in
                                Button {
                                    wordClass = option.key
                                } label: {
                                    Text(option.label)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .foregroundStyle(wordClass == option.key ? .white : AppTheme.Colors.textPrimary)
                                        .background(wordClass == option.key ? AppTheme.Colors.primary : AppTheme.Colors.secondarySurface)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Eintrag bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        onSave(french, german, wordClass.isEmpty ? nil : wordClass)
                    }
                    .bold()
                    .disabled(french.trimmingCharacters(in: .whitespaces).isEmpty || german.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

extension ScanImportView {
    // ── FULLSCREEN REVIEW SCREEN ──

    var scanFullscreenReview: some View {
        VStack(spacing: 0) {
            // Fixed header
            HStack {
                Button {
                    isShowingFullscreenReview = false
                } label: {
                    Label("Zurück", systemImage: "arrow.left")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(sectionStyle.accent)

                Spacer()

                Text("\(previewPairs.count) Einträge")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.vertical, 14)
            .background(AppTheme.Colors.surface.opacity(0.95))

            Divider().opacity(0.3)

            // Scrollable review list
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(previewPairs) { pair in
                        HStack(spacing: 6) {
                            // Warning badge for unsure entries
                            if !pair.isImportable {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(AppTheme.Colors.warning)
                                    .frame(width: 24)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(pair.french)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                        .lineLimit(2)
                                    Text(reviewWordClassLabel(for: pair))
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(reviewWordClassForeground(for: pair))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(reviewWordClassBackground(for: pair))
                                        .clipShape(Capsule())
                                }
                                Text(pair.german)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(pair.isImportable ? AppTheme.Colors.textSecondary : AppTheme.Colors.warning)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)

                            // OK button — confirms unsure entry as importable
                            if !pair.isImportable {
                                Button {
                                    if let idx = previewPairs.firstIndex(where: { $0.id == pair.id }) {
                                        previewPairs[idx] = ImportPreviewPair(
                                            id: pair.id,
                                            french: pair.french,
                                            german: pair.german,
                                            cardType: pair.cardType,
                                            learningCategory: pair.learningCategory,
                                            note: pair.note,
                                            isImportable: true,
                                            isReviewed: true
                                        )
                                    }
                                } label: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(AppTheme.Colors.success)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                reviewEditingPairID = IdentifiableUUID(pair.id)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(sectionStyle.accent)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            Button {
                                previewPairs.removeAll { $0.id == pair.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(AppTheme.Colors.error.opacity(0.7))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(pair.isImportable ? AppTheme.Colors.surface : AppTheme.Colors.warning.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(pair.isImportable ? AppTheme.Colors.border : AppTheme.Colors.warning.opacity(0.5), lineWidth: pair.isImportable ? 1 : 2)
                        )
                    }
                }
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.vertical, 12)
            }

            Divider().opacity(0.3)

            // Fixed footer — Import button only.
            // **2026-04-22 Abend V**: ruft jetzt `beginImportTargetChoice()`
            // statt direkt `importScannedText()`. Der User sieht zuerst
            // ein Sheet mit der Wahl „neue Liste" vs. „bestehende Liste".
            // **Phase B (2026-05-20)**: → `beginImportTargetChoiceOrDraft()`,
            // damit das Sheet auch bei 0 importable Pairs (aber >0 Pairs)
            // erreichbar bleibt — für den „Als Entwurf"-Pfad.
            VStack(spacing: 0) {
                Button {
                    isShowingFullscreenReview = false
                    session.batchCompleted = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        beginImportTargetChoiceOrDraft()
                    }
                } label: {
                    Label("Als Lernliste speichern", systemImage: "square.and.arrow.down.fill")
                        .font(AppTheme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                .disabled(completePreviewPairCount == 0)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, 10)
                // **Phase B v3 (2026-05-20)** — kleiner CTA-Eigenabstand; die
                // TabBar-Höhe reserviert jetzt der `.safeAreaInset` am
                // scanFullscreenReview-Container (siehe unten, gespiegelt von
                // RootContentView:187-192). Der v1-Versuch mit
                // `usesGlobalChrome ? 0 : …` war falsch — bei aktivem Global-
                // Chrome wurde 0 gewählt → CTA komplett unter die TabBar.
                .padding(.bottom, 16)
            }
            .background(AppTheme.Colors.surface)
        }
        .toolbar(.hidden, for: .navigationBar)
        .appScreenBackground(sectionStyle)
        // **Erstnutzer-Hint (2026-06-09)** — am Screen-Root eingehängt,
        // damit der Dim-Scrim den ganzen Review-Screen abdeckt.
        // scanFullscreenReview ist der TATSÄCHLICH live genutzte
        // Review-Screen (nicht `previewCard`/`previewListContent` in
        // ScanImportView+ReviewCards.swift — die sind toter Code).
        .hintBubble(
            id: "scan_result",
            // Ein Satz pro Zeile (User-Spec Lesbarkeit für Kinder).
            text: """
            Cool, oder?
            Ich hab die Wörter von deiner Seite gelesen.
            Schau kurz drüber, ob alles passt.
            Dann speicherst du sie als eigene Liste und kannst sie üben.
            """
        )
        // **Phase B v3 (2026-05-20)** — TabBar-Höhe reservieren. Spiegelt
        // RootContentView:187-192: nested `navigationDestination(isPresented:)`-
        // Pushes erben WEDER den globalen Footer-safeAreaInset (Z.230) NOCH
        // den per-AppScreen-Destination-Spacer (Z.187) → ohne diese
        // Reservierung zeichnen Liste UND CTA unter die globale TabBar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if usesGlobalChrome {
                Color.clear.frame(
                    height: AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom
                )
            }
        }
        .sheet(item: $reviewEditingPairID) { wrapper in
            if let index = previewPairs.firstIndex(where: { $0.id == wrapper.id }) {
                ReviewPairEditSheet(
                    french: previewPairs[index].french,
                    german: previewPairs[index].german,
                    wordClass: resolvedWordClass(for: previewPairs[index]) ?? ""
                ) { newFrench, newGerman, newWordClass in
                    previewPairs[index] = ImportPreviewPair(
                        id: previewPairs[index].id,
                        french: newFrench,
                        german: newGerman,
                        cardType: previewPairs[index].cardType,
                        learningCategory: previewPairs[index].learningCategory,
                        note: previewPairs[index].note,
                        isImportable: true,
                        isReviewed: true,
                        wordClass: newWordClass
                    )
                    reviewEditingPairID = nil
                }
            }
        }
    }

    var scanResultUnsureCount: Int {
        previewPairs.filter { !$0.isImportable }.count
    }

    /// Didactic word class overrides for common words misclassified in DB
    private static let wordClassOverrides: [String: String] = [
        // Interjektionen
        "voil\u{00E0}": "interjection", "voila": "interjection",
        "merci": "interjection", "salut": "interjection",
        "bonjour": "interjection", "bonsoir": "interjection",
        "bravo": "interjection", "h\u{00E9}las": "interjection",
        "oui": "interjection", "non": "interjection",
        "pardon": "interjection", "attention": "interjection",
        // Adverbien
        "l\u{00E0}": "adverb",
        "ici": "adverb", "comment": "adverb",
        "bien": "adverb", "mal": "adverb",
        "tr\u{00E8}s": "adverb", "tres": "adverb",
        "aussi": "adverb", "encore": "adverb",
        "toujours": "adverb", "jamais": "adverb",
        "d\u{00E9}j\u{00E0}": "adverb", "deja": "adverb",
        "beaucoup": "adverb", "peu": "adverb",
        "da": "adverb",
        // Präpositionen
        "de": "preposition",
        // Artikel
        "le/la": "article", "le / la": "article",
        // Phrasen (feste Ausdrücke)
        "c'est": "phrase", "ce sont": "phrase",
        "il y a": "phrase", "s'il vous pla\u{00EE}t": "phrase",
        "s'il te pla\u{00EE}t": "phrase",
    ]

    /// French stopwords that should be skipped in word-by-word lookup
    private static let frenchStopwords: Set<String> = [
        "le", "la", "les", "l", "un", "une", "des", "du", "d",
        "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "me", "te", "se", "ce", "c", "ne", "pas", "n", "y", "en",
        "et", "ou", "mais", "que", "qui", "est", "a", "au", "aux",
        "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses",
        "notre", "votre", "leur", "leurs",
    ]

    /// Wortart eines ImportPreviewPair — delegiert an die zentrale FrenchEntryAnalyzer-Pipeline.
    /// Ergebnis ist konsistent mit Listen-Detail, Wörterbuch und Training.
    /// Nutzer-gesetzte `pair.wordClass` hat Vorrang.
    private func resolvedWordClass(for pair: ImportPreviewPair) -> String? {
        if let wc = pair.wordClass, !wc.isEmpty { return wc }

        let result = FrenchListStatisticsAggregator.cachedAnalyze(pair.french)
        // Sonderkategorien (interjection, presentationWord, particle, formulaic):
        // strukturiert in eigener Achse, hier auf String mappen für Display-Konsistenz.
        if let special = result.specialCategory {
            switch special {
            case .interjection, .presentationWord: return "interjection"
            case .particle:                        return "particle"
            case .formulaic:                       return "phrase"
            case .other:                           return "other"
            }
        }
        switch result.primaryPos {
        case .verb:      return "verb"
        case .noun:      return "noun"
        case .adjective: return "adjective"
        case .adverb:    return "adverb"
        case .phrase:    return "phrase"
        case .sentence:  return "phrase"
        case .unknown:
            // Direct DB lookup fallback (Pronomen, Konjunktion etc.)
            return result.directWordClass
        }
    }

    var batchCompleteSummary: some View {
        let pageCount = max(session.batchTotalCount, 1)
        let totalPairs = previewPairs.count
        let unsureCount = scanResultUnsureCount

        // Word class counts — uses resolvedWordClass (with stopword filter)
        var nounCount = 0
        var verbCount = 0
        var adjCount = 0
        for pair in previewPairs {
            let wc = resolvedWordClass(for: pair)
            if wc == "noun" { nounCount += 1 }
            else if wc == "verb" { verbCount += 1 }
            else if wc == "adjective" { adjCount += 1 }
        }
        let otherCount = totalPairs - nounCount - verbCount - adjCount

        return VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(AppTheme.Colors.success)

            Text("Analyse abgeschlossen")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(pageCount == 1 ? "1 Seite analysiert" : "\(pageCount) Seiten analysiert")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            // Total count big
            Text("\(totalPairs) Vokabeln erkannt")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            // Word class breakdown — 2-zeilig pills
            HStack(spacing: 10) {
                if nounCount > 0 {
                    // Nomen ist im Deutschen invariant — kein Singular/
                    // Plural-Unterschied nötig.
                    wordClassBadge(count: nounCount, label: "Nomen", color: AppTheme.Colors.moduleNomen)
                }
                if verbCount > 0 {
                    // **2026-06-09** — Singular/Plural-Fix: bei genau
                    // 1 Verb muss es „Verb" heißen, nicht „Verben".
                    wordClassBadge(count: verbCount, label: verbCount == 1 ? "Verb" : "Verben", color: AppTheme.Colors.moduleVerbs)
                }
                if adjCount > 0 {
                    wordClassBadge(count: adjCount, label: adjCount == 1 ? "Adjektiv" : "Adjektive", color: AppTheme.Colors.moduleQuiz)
                }
                if otherCount > 0 {
                    wordClassBadge(count: otherCount, label: "Andere", color: AppTheme.Colors.textSecondary)
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.primary)
                    Text("\(completePreviewPairCount) Eintr\u{00E4}ge bereit zum Import")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                }

                if unsureCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.warning)
                        // **2026-06-09** — Singular/Plural-Fix: bei genau
                        // 1 Eintrag muss es „unsicherer Eintrag" heißen,
                        // nicht „unsichere Einträge".
                        Text(unsureCount == 1 ? "1 unsicherer Eintrag" : "\(unsureCount) unsichere Eintr\u{00E4}ge")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.warning)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 4)


            Button {
                isShowingFullscreenReview = true
            } label: {
                Label("Jetzt überprüfen", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: sectionStyle.accent))
            .padding(.top, 2)
        }
        .padding(16)
        // Scan-Modul-Tint additiv unter der semantischen Success-Border —
        // Hero-Card liest sich als Scan-Akzent-Card, Success-Green bleibt
        // aber als klares „Analyse abgeschlossen"-Signal erhalten.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(sectionStyle.accent.opacity(AppTheme.CardIntensity.medium))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.Colors.success.opacity(0.3), lineWidth: 1.5)
                )
        )
    }

    // Internal (nicht private), damit der Inline-Review-Row-Wrapper
    // (ScanImportView+ReviewRows.swift) ebenfalls auf das Label + Color
    // zugreifen kann — gleiche Verb-Infinitiv-Anzeige im Inline + Sheet.
    func reviewWordClassLabel(for pair: ImportPreviewPair) -> String {
        let wc = resolvedWordClass(for: pair)
        if wc == nil && pair.cardType == .phrases { return "Phrase" }
        switch wc {
        case "noun": return "Nomen"
        case "verb":
            if let inf = resolvedInfinitive(for: pair) {
                return "Verb (\(inf))"
            }
            return "Verb"
        case "adjective": return "Adjektiv"
        case "adverb": return "Adverb"
        case "preposition": return "Pr\u{00E4}position"
        case "conjunction": return "Konjunktion"
        case "pronoun": return "Pronomen"
        case "interjection": return "Interjektion"
        case "phrase": return "Phrase"
        case "article": return "Artikel"
        default: return "Wort"
        }
    }

    /// Find the infinitive for a scan entry — checks individual words
    private func resolvedInfinitive(for pair: ImportPreviewPair) -> String? {
        let french = pair.french.lowercased()
        // Direct lookup
        if let inf = StandardVocabularyLoader.infinitive(for: french) { return inf }
        // Word-by-word (skip stopwords)
        let words = french
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "\u{2019}", with: " ")
            .split(separator: " ").map(String.init)
            .filter { !Self.frenchStopwords.contains($0) && $0.count > 1 }
        for word in words {
            if let inf = StandardVocabularyLoader.infinitive(for: word) { return inf }
        }
        return nil
    }

    func reviewWordClassColor(for pair: ImportPreviewPair) -> Color {
        let wc = resolvedWordClass(for: pair)
        if wc == nil && pair.cardType == .phrases { return AppTheme.Colors.textSecondary }
        return Self.wordClassColor(wc)
    }

    // MARK: - Pill-Kontrast (Fix 2026-04-25)
    //
    // Vorher: `foreground = tintColor`, `background = tintColor.opacity(0.15)`
    // — bei dunkelblauen Tint-Farben (`moduleVerbs`, `modulePractice`)
    // erzeugte das im Dark-Mode-ähnlichen Kontext blau-auf-blau-Pills,
    // die kaum lesbar waren.
    //
    // Jetzt: Wortklassen mit DUNKLEN Tints (aktuell `verb` + `adverb`)
    // bekommen eine **solide** Background-Füllung und **weißen** Text —
    // maximaler Kontrast. Helle/mittlere Tints behalten das bisherige
    // „tinted-background + colored-text"-Schema.
    //
    // Diese Zweiteilung ist bewusst klein gehalten — keine neue
    // Farbsemantik, nur Lesbarkeits-Fix.

    /// True, wenn die Pill für diese Wortklasse einen dunklen Hintergrund
    /// + weißen Text bekommen soll. Aktuell `verb` und `adverb` (beide
    /// nutzen tiefe Blau-Töne, die mit Text in derselben Farbe keinen
    /// Kontrast liefern).
    private func shouldUseSolidDarkPill(for pair: ImportPreviewPair) -> Bool {
        switch resolvedWordClass(for: pair) {
        case "verb", "adverb":
            return true
        default:
            return false
        }
    }

    /// Foreground-Farbe für den Pill-Text. Weiß auf dunklen Tints,
    /// sonst der Tint selbst (bisheriges Verhalten).
    func reviewWordClassForeground(for pair: ImportPreviewPair) -> Color {
        shouldUseSolidDarkPill(for: pair) ? .white : reviewWordClassColor(for: pair)
    }

    /// Background-Farbe für den Pill. Für dunkle Tints solide (volle
    /// Farbe mit leichtem Dämpfer), sonst 15%-tint wie bisher.
    func reviewWordClassBackground(for pair: ImportPreviewPair) -> Color {
        let base = reviewWordClassColor(for: pair)
        return shouldUseSolidDarkPill(for: pair)
            ? base.opacity(0.88)
            : base.opacity(0.15)
    }

    static func wordClassColor(_ wc: String?) -> Color {
        switch wc {
        case "noun": return AppTheme.Colors.moduleNomen
        case "verb": return AppTheme.Colors.moduleVerbs
        case "adjective": return AppTheme.Colors.moduleQuiz
        case "adverb": return AppTheme.Colors.modulePractice
        case "preposition", "conjunction": return AppTheme.Colors.moduleScan
        case "interjection": return AppTheme.Colors.warning
        default: return AppTheme.Colors.textSecondary
        }
    }

    private func wordClassBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 20, weight: .black, design: .rounded))
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .frame(minWidth: 60)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    var scanStatusMessageView: some View {
        // Initial-Auswahl-State (keine Bild + keine Preview) bleibt clean —
        // der Intro-Footer-Text war auf dem leeren Screen visuell „lost".
        // Status erscheint erst, wenn tatsächlich gescannt wird oder
        // eine Vorschau existiert.
        if !isRecognizingImage,
           !session.batchCompleted,
           (selectedImage != nil || !previewPairs.isEmpty) {
            Text(importMessage)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    func scanRootContent(proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: AppTheme.Spacing.sm) {
                // **Modul-Header-Card** (Phase 7.6+): farbige Identitäts-
                // Card oben im Body — visueller Wiedererkennungsanker
                // zum Home-Tap auf „Scan".
                //
                // **Back-Verhalten kontext-abhängig** (User-Spec:
                // „Chevron während Analyse → vorheriger Screen, nicht
                // Home"):
                //   • Draft aktiv (Bild gewählt / Analyse läuft /
                //     Preview-Paare vorhanden) → zurück zum Scan-
                //     Setup (Choice-Screen innerhalb der ScanImport-
                //     View, via `returnToScanSetup()`). User verliert
                //     nichts aus der Session, kann aber neu wählen.
                //   • Keine aktive Session → `dismiss()` verlässt den
                //     ganzen Scan-Screen (klassisches Zurück zu
                //     Home / vorherigem Screen).
                ModuleHeaderCard(
                    icon: .scan,
                    title: "Scan",
                    accent: sectionStyle.accent,
                    onBack: {
                        if hasActiveScanDraft {
                            returnToScanSetup()
                        } else {
                            dismiss()
                        }
                    }
                )

                // Separater „Zurück"-Button raus (User-Spec): der
                // Back-Chevron in der `ModuleHeaderCard` oben ruft
                // bereits `dismiss()` und liefert die gewohnte Zurück-
                // Geste. Ein zweiter Button direkt darunter war
                // redundant und nahm Platz auf dem Analyse-Screen weg.
                // `returnToScanSetup()` bleibt als Methode erhalten —
                // wird perspektivisch für andere Entry-Points genutzt.

                if session.batchCompleted && !previewPairs.isEmpty {
                    // Summary: nur Summary zentriert, keine Auswahl-Buttons
                    Spacer(minLength: 8)
                    batchCompleteSummary
                    Spacer(minLength: 8)
                } else {
                ScrollView(showsIndicators: false) {
                    // VStack-Spacing 16 → 10: enger zwischen Labels,
                    // Cards und Folge-Blöcken (User-Wunsch „padding
                    // zwischen Wähle-Labels und Cards + zwischen
                    // Kamera & Foto-Album kleiner").
                    VStack(alignment: .leading, spacing: 10) {
                        // Choice-Screen NUR zeigen, wenn nichts läuft —
                        // sobald ein Bild gewählt / die Erkennung läuft /
                        // bereits Preview-Einträge da sind, fokussieren wir
                        // den Analyse/Review-Bereich (vorher waren die
                        // 4 Choice-Cards weiter sichtbar und der User
                        // musste nach unten scrollen, um den Status zu sehen).
                        let isOnChoiceScreen = !isRecognizingImage
                            && selectedImage == nil
                            && previewPairs.isEmpty
                            && session.batchThumbnails.isEmpty

                        // **Scan-Redesign (2026-05-21)** — Choice-Screen-Header
                        // („Was möchtest du scannen?" + Maskottchen) entfernt
                        // (User-Wunsch + Platz für „Meine Scans" above-the-fold).
                        // ScanScreenHeader ist dadurch ungenutzt (wie ScanHeroCard).
                        // Im Review-State bleibt das ScanModeBadge erhalten.
                        if !isOnChoiceScreen {
                            // **Feature A — ScanModeBadge im Review-State**:
                            // Sobald ein Bild vorliegt oder Preview-Paare
                            // existieren, zeigt das Badge oben, in welchem
                            // Modus der aktuelle Scan läuft. Wichtig weil
                            // das Review-Layout für Liste und Freitext
                            // leicht unterschiedlich ist und der User
                            // jederzeit sehen soll, welchen Pfad er nimmt.
                            // **Zentriert** (User-Spec): Badge sitzt mittig
                            // über dem Content, statt linksbündig wie
                            // früher. Zusätzliches `.padding(.bottom, 14)`,
                            // damit die grüne Pille nicht direkt auf dem
                            // Bild-/Thumbnail-Block sitzt — das wirkte
                            // gedrückt. 14 pt plus VStack-Spacing (10 pt)
                            // ergeben ~24 pt Luft bis zur Analyse-Card
                            // darunter.
                            ScanModeBadge(mode: activeScanMode, variant: .card)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)
                                .padding(.bottom, 14)
                        }

                        if isOnChoiceScreen {

                            // ─────── Schritt 1 — MODUS ───────
                            // Selection-Toggles (kein Navigations-Element).
                            // Tap ändert nur den Modus, User bleibt auf dem Screen.
                            // Padding 28 → 10 → 14: Schritt 1 rückt
                            // minimal wieder runter (User-Nachjustierung),
                            // Block darunter folgt.
                            // **Naming-Sweep 2026-05-06** — „Wähle den
                            // Modus" → „Was scannst du?" (Du-Ansatz,
                            // direkter, weniger Beamten-Sprache).
                            ScanSectionLabel(stepNumber: 1, title: "Was scannst du?")
                                // Mehr Abstand über Schritt 1 (2026-05-21): 8 → 16.
                                .padding(.top, 16)

                            HStack(spacing: 12) {
                                ScanModeSelectionCard(
                                    illustrationName: "ScanIconVokabelliste",
                                    title: "Vokabeln",
                                    isSelected: activeScanMode == .list,
                                    accent: sectionStyle.accent
                                ) {
                                    selectScanMode(.list)
                                }

                                ScanModeSelectionCard(
                                    illustrationName: "ScanIconFreierText",
                                    // **Naming-Sweep 2026-05-06** —
                                    // „Freier Text" → „Eigener Text"
                                    // (besitzergreifend, kindgerechter
                                    // als der bürokratische
                                    // „freier Text"-Term).
                                    title: "Eigener Text",
                                    isSelected: activeScanMode == .text,
                                    accent: sectionStyle.accent
                                ) {
                                    selectScanMode(.text)
                                }
                            }

                            // ─────── Schritt 2 — QUELLE ───────
                            // Action-Buttons. Tap startet Kamera/Galerie
                            // mit dem aktuell gewählten Modus. +24pt Luft
                            // zwischen den Blöcken — klarer Hierarchie-Bruch.
                            // **Naming-Sweep 2026-05-06** — „Wähle die
                            // Quelle" → „Woher?" (kompakte
                            // Frage statt Ankündigung).
                            ScanSectionLabel(stepNumber: 2, title: "Woher?")
                                // Scan-Redesign: einheitlicher Section-Abstand (war 24).
                                .padding(.top, 8)

                            // **Scan-Redesign (2026-05-21)** — Kamera + Foto-Album
                            // nebeneinander (2 Spalten), gespiegelt vom WAS-Pattern
                            // (`HStack(spacing: 12)`); beide `.frame(maxWidth: .infinity)`
                            // → symmetrisch.
                            HStack(spacing: 12) {
                                ScanChoiceCard(
                                    illustrationName: "ScanIconKamera",
                                    title: "Kamera",
                                    accent: sectionStyle.accent,
                                    isPriority: true,
                                    // Kamera-Tint: dunkles Grün (moduleNomen-Ton).
                                    baseTint: Color(hex: "#059669")
                                ) {
                                    guard !isRecognizingImage else { return }
                                    guard isCameraCaptureAvailable else { return }
                                    shouldAppendNextScan = false
                                    selectedScanInputMethod = .camera
                                    openCameraScanner()
                                }

                                ScanChoiceCard(
                                    illustrationName: "ScanIconFotoAlbum",
                                    title: "Foto-Album",
                                    accent: sectionStyle.accent,
                                    // Foto-Album-Tint: dezentes Violett (moduleVerbs-Ton).
                                    baseTint: Color(hex: "#8B5CF6")
                                ) {
                                    guard !isRecognizingImage else { return }
                                    shouldAppendNextScan = false
                                    selectedScanInputMethod = .library
                                    showingPhotoLibrary = true
                                }
                            }

                            // **Phase C (2026-05-20)** — „Meine Scans"-Sektion:
                            // gespeicherte Scan-Entwürfe unter den Capture-
                            // Optionen. Blendet sich selbst aus, wenn keine
                            // Drafts existieren.
                            ScanDraftsSectionView(
                                onOpenDraft: { id in
                                    navigate(.scanDraftDetail(id))
                                },
                                selectedDraftIDs: $selectedDraftIDs
                            )
                        }

                        if !session.batchCompleted {
                            if session.batchThumbnails.count > 1 {
                                // Multi-page: thumbnail strip
                                ScanBatchThumbnailCardView(
                                    thumbnails: session.batchThumbnails,
                                    currentIndex: session.batchCurrentIndex,
                                    isRecognizing: isRecognizingImage,
                                    progressText: scanProgressText,
                                    stage: scanRuntimeStage,
                                    sectionStyle: sectionStyle,
                                    inputMethod: session.selectedScanInputMethod
                                )
                            } else if let selectedImage {
                                // Single page
                                ScanSelectedImageCardView(
                                    image: selectedImage,
                                    isRecognizingImage: isRecognizingImage,
                                    progressText: scanProgressText,
                                    stage: scanRuntimeStage,
                                    sectionStyle: sectionStyle,
                                    onTap: {
                                        showingImagePreview = true
                                    },
                                    inputMethod: session.selectedScanInputMethod
                                )
                            }
                        }

                        scanStatusMessageView
                    }
                    // **Footer-Clearance-Fix 2026-05-07** — vorher
                    // `8 + kbInset` → die Foto-Album-Card am Ende des
                    // Choice-Screens wurde von der globalen Footer-Bar
                    // verdeckt (User-Befund).
                    //
                    // **2026-05-08 Padding-Cleanup** — `footerHeight +
                    // insetBottom` Reservierung entfernt; nach der
                    // Footer-Migration zu `.safeAreaInset(.bottom)`
                    // reserviert das System diese Höhe automatisch.
                    // 16 pt Margin + Keyboard-Inset bleiben.
                    .padding(.bottom, 16 + scanKeyboardBottomPadding)
                }
                .scrollDismissesKeyboard(.interactively)
            } // else (nicht batchCompleted)
            }

            if isShowingScanToast {
                scanToastView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.bottom, 74)
            }
        }
        .onChange(of: reviewScrollTrigger) { _, _ in
            guard !previewPairs.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                proxy.scrollTo(Self.reviewAnchorID, anchor: .top)
            }
        }
        .onChange(of: focusedReviewField) { _, focus in
            guard let focus else {
                commitPreviewEditsAndSyncImportText()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(
                        reviewFieldScrollID(for: focus),
                        anchor: reviewFieldScrollAnchor(for: focus)
                    )
                }
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if isShowingImportCompletion, let ctx = importCompletionContext {
                    importCompletionScreen(context: ctx)
                } else {
                    applyingScanPresentationModifiers(
                        to: applyingScanRootModifiers(
                            to: ScrollViewReader { proxy in
                                scanRootContent(proxy: proxy)
                            }
                            // **Phase E (2026-05-20)** — Multi-Select-Action-Bar
                            // am Boden der Choice-Screen-Scrollfläche, ÜBER der
                            // (lokalen/globalen) Footer-Chrome. Nur bei Auswahl.
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                if !filteredSelection.isEmpty {
                                    multiDraftActionBar
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: filteredSelection.count)
                        )
                    )
                }
            }

            // **Phase B v3 (2026-05-20)** — Draft-Save-Success-Toast als
            // Root-ZStack-Layer (über allen Content-Swaps / Chrome / Sheets /
            // Pop-Timing). Größer + auffällig: gefülltes Success-Badge (weiß
            // auf elumiMint), mid-top via `.padding(.top, 140)`, Pop-In-
            // Transition. `allowsHitTesting(false)` → Taps gehen durch.
            // Auto-Dismiss via `.task(id:)`.
            if showDraftSavedToast {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Als Entwurf gespeichert")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(
                    AppTheme.Colors.success,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                )
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                .padding(.top, 140)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
                .zIndex(999)
            }

            // **Phase E (2026-05-20)** — Bulk-Action-Toast (Delete/Merge),
            // dynamischer Text. Gleiche Optik wie der Draft-Save-Toast oben;
            // äußeres `.padding(.horizontal, 24)` hält längere Messages von den
            // Rändern weg.
            if showBulkActionToast {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(bulkActionMessage)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(
                    AppTheme.Colors.success,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                )
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                .padding(.top, 140)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
                .zIndex(999)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showDraftSavedToast)
        .task(id: showDraftSavedToast) {
            guard showDraftSavedToast else { return }
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled {
                showDraftSavedToast = false
            }
        }
        // **Phase E** — Bulk-Action-Toast (auto-dismiss) + Bulk-Delete-Confirm.
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showBulkActionToast)
        .task(id: showBulkActionToast) {
            guard showBulkActionToast else { return }
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled {
                showBulkActionToast = false
            }
        }
        .alert("Entwürfe löschen?", isPresented: $isShowingBulkDeleteConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                let count = filteredSelection.count
                draftStore.remove(ids: filteredSelection)
                selectedDraftIDs.removeAll()
                bulkActionMessage = "\(count) \(count == 1 ? "Entwurf" : "Entwürfe") gelöscht"
                showBulkActionToast = true
            }
        } message: {
            Text("\(filteredSelection.count) \(filteredSelection.count == 1 ? "Entwurf wird" : "Entwürfe werden") unwiderruflich gelöscht.")
        }
        // **Phase E Commit 3** — Bulk-Merge Sheet-Kette (Reuse der Phase-D-v2-
        // Sheets; Settle-Delays 0.4s; Reentrance über den Coordinator).
        .sheet(isPresented: $isShowingBulkTargetChoice) {
            ImportTargetChoiceSheet(
                importableCount: multiDraftCoordinator.aggregatedItems.count,
                onChooseNewList: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isShowingBulkNewListName = true
                    }
                },
                onChooseExistingList: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isShowingBulkExistingListPicker = true
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingBulkNewListName) {
            NewListNameSheet(onCreate: { listName in
                let result = multiDraftCoordinator.executeImportToNewList(name: listName, listStore: listStore)
                if result.success, let listID = multiDraftCoordinator.pendingTargetListID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showBulkMergeCompletion(
                            draftCount: multiDraftCoordinator.sourceDraftCount,
                            listName: listName,
                            listID: listID,
                            addedCount: result.addedCount
                        )
                        selectedDraftIDs.removeAll()
                        multiDraftCoordinator.reset()
                    }
                }
            })
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingBulkExistingListPicker) {
            if let listStore {
                ExistingListPickerSheet(
                    store: listStore,
                    importableCount: multiDraftCoordinator.aggregatedItems.count,
                    onConfirm: { listID in handleBulkExistingListChosen(listID) },
                    onFallbackToNewList: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            isShowingBulkNewListName = true
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingBulkConflictReview) {
            if let plan = multiDraftCoordinator.pendingMergePlan {
                ScanImportConflictReviewSheet(
                    workingConflicts: plan.conflicts,
                    safeAddCount: plan.safeAdds.count,
                    duplicateCount: plan.exactDuplicatesToSkip.count,
                    targetListName: multiDraftCoordinator.pendingTargetListName,
                    onConfirm: { resolved in handleBulkConflictReviewConfirmed(resolved) }
                )
            }
        }
        .alert("Hinzufügen fehlgeschlagen", isPresented: $isShowingBulkImportFailureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bulkImportFailureMessage)
        }
    }

    // MARK: - Phase E — Multi-Select Action-Bar

    /// Stale-ID-Defense: nur IDs, die noch als Draft existieren (ein Draft
    /// kann zwischenzeitlich einzeln gelöscht worden sein).
    var filteredSelection: Set<UUID> {
        let validIDs = Set(draftStore.drafts.map(\.id))
        return selectedDraftIDs.intersection(validIDs)
    }

    /// Action-Bar: erscheint via `safeAreaInset`, sobald ≥1 Draft gewählt ist.
    /// Zwei Buttons nebeneinander — kein „Abbrechen" (User toggelt Checkboxen
    /// weg). **Aktionen noch ungewired** (Commit 2/3); enabled-Look bei Auswahl,
    /// manuelles `.opacity` fürs Disabled-Feedback (Custom-Styles auto-grauen nicht).
    @ViewBuilder
    var multiDraftActionBar: some View {
        let count = filteredSelection.count
        let isEmpty = filteredSelection.isEmpty
        HStack(spacing: 12) {
            // „Löschen" — destruktiver gefüllter CTA (rot-solid, weißer Text);
            // gleiche Höhe (54) + zentriertes Label wie der Primary daneben.
            Button(role: .destructive) {
                isShowingBulkDeleteConfirm = true
            } label: {
                Text("Löschen (\(count))")
                    // -1pt ggü. Typography.button (17→16); zentriert, damit der
                    // Counter bei Umbruch mittig in der 2. Zeile sitzt.
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(AppDestructiveButtonStyle())
            .opacity(isEmpty ? 0.5 : 1.0)
            .disabled(isEmpty)

            // „Zusammenführen" — primärer CTA (amber), dominante Aktion.
            Button {
                let selectedDrafts = draftStore.drafts.filter { filteredSelection.contains($0.id) }
                multiDraftCoordinator.reset()
                multiDraftCoordinator.sourceDraftCount = selectedDrafts.count
                let items = multiDraftCoordinator.aggregateAndDedupe(drafts: selectedDrafts)
                multiDraftCoordinator.aggregatedItems = items
                // Edge-Case: nur Drafts mit 0 aktiven Pairs gewählt → nichts tun.
                guard !items.isEmpty else { return }
                isShowingBulkTargetChoice = true
            } label: {
                Text("Zusammenführen (\(count))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .opacity(isEmpty ? 0.5 : 1.0)
            .disabled(isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.surface)
    }

    // MARK: - Phase E — Bulk-Merge Handler

    /// Bestehende Liste gewählt → Plan berechnen, ggf. ConflictReview, sonst
    /// direkt mergen. Settle-Delays 0.4s (Sheet erst sauber dismissen lassen).
    private func handleBulkExistingListChosen(_ listID: UUID) {
        guard let listStore else { return }
        guard let targetList = listStore.customLists.first(where: { $0.id == listID }) else {
            bulkImportFailureMessage = "Lernliste nicht gefunden."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isShowingBulkImportFailureAlert = true
            }
            return
        }
        guard let plan = multiDraftCoordinator.prepareMergeIntoExisting(
            listID: listID,
            listName: targetList.name,
            listStore: listStore
        ) else { return }

        if plan.requiresUserDecision {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isShowingBulkConflictReview = true
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                executeBulkMergeAndToast()
            }
        }
    }

    private func handleBulkConflictReviewConfirmed(_ resolved: [ImportConflict]) {
        multiDraftCoordinator.applyResolvedConflicts(resolved)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            executeBulkMergeAndToast()
        }
    }

    private func executeBulkMergeAndToast() {
        let result = multiDraftCoordinator.executeMerge(listStore: listStore)
        if result.success, let listID = multiDraftCoordinator.pendingTargetListID {
            showBulkMergeCompletion(
                draftCount: multiDraftCoordinator.sourceDraftCount,
                listName: multiDraftCoordinator.pendingTargetListName,
                listID: listID,
                addedCount: result.addedCount
            )
            selectedDraftIDs.removeAll()
            multiDraftCoordinator.reset()
        } else {
            bulkImportFailureMessage = result.errorMessage ?? "Unbekannter Fehler."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isShowingBulkImportFailureAlert = true
            }
        }
    }

    /// **Phase D v3 Commit 2** — Bulk-Merge-Erfolg zeigt jetzt die
    /// ImportCompletionView (CTAs) statt eines Toasts. Reused: das bestehende
    /// `isShowingImportCompletion` + `importCompletionContext` + Content-Swap +
    /// `handleCompletionSelection` aus dem Standard-Scan-Flow („Später" →
    /// goHome). `draftCount` bleibt im Vertrag (Caller-Parität), wird im Context
    /// nicht gebraucht. `importedItemIDs: []` (Merge → ganze Liste).
    private func showBulkMergeCompletion(draftCount: Int, listName: String, listID: UUID, addedCount: Int) {
        let context = ImportCompletionContext(
            importedCount: addedCount,
            targetListID: listID,
            targetListName: listName,
            language: .french,
            preferredDirection: StudyLanguage.french.defaultDirectionToGerman,
            cardType: dominantImportedCardType(in: multiDraftCoordinator.aggregatedItems),
            importedItemIDs: []
        )
        importCompletionContext = context
        isShowingImportCompletion = true
    }

    private func importCompletionScreen(context: ImportCompletionContext) -> some View {
        ImportCompletionView(
            context: context,
            onTrain: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .vocabulary,
                    shouldAutoStart: true
                )))
            },
            onNomen: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .nouns,
                    shouldAutoStart: true
                )))
            },
            onArticles: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .articles,
                    shouldAutoStart: true
                )))
            },
            onVerbs: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .verbs,
                    shouldAutoStart: true
                )))
            },
            onVerbforms: {
                handleCompletionSelection(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .verbforms,
                    shouldAutoStart: false
                )))
            },
            onFlashcards: {
                handleCompletionSelection(.flashcards(context.flashcardLaunchContext))
            },
            onQuiz: {
                handleCompletionSelection(.quiz(context.quizLaunchContext))
            },
            onAccents: {
                handleCompletionSelection(.accents(nil))
            },
            onViewList: {
                handleCompletionSelection(.lists(context.listLaunchContext))
            },
            onLater: {
                handleCompletionSelection(nil)
            }
        )
    }
}
