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
                                        .foregroundStyle(reviewWordClassColor(for: pair))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(reviewWordClassColor(for: pair).opacity(0.15))
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

            // Fixed footer — Import button only
            VStack(spacing: 0) {
                Button {
                    isShowingFullscreenReview = false
                    session.batchCompleted = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        importScannedText()
                    }
                } label: {
                    Label("Jetzt importieren", systemImage: "square.and.arrow.down.fill")
                        .font(AppTheme.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                .disabled(completePreviewPairCount == 0)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 16)
            }
            .background(AppTheme.Colors.surface)
        }
        .toolbar(.hidden, for: .navigationBar)
        .appScreenBackground(sectionStyle)
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
                    wordClassBadge(count: nounCount, label: "Nomen", color: AppTheme.Colors.moduleNomen)
                }
                if verbCount > 0 {
                    wordClassBadge(count: verbCount, label: "Verben", color: AppTheme.Colors.moduleVerbs)
                }
                if adjCount > 0 {
                    wordClassBadge(count: adjCount, label: "Adjektive", color: AppTheme.Colors.moduleQuiz)
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
                        Text("\(unsureCount) unsichere Eintr\u{00E4}ge")
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
                ModuleHeaderCard(
                    icon: .scan,
                    title: "Scan",
                    accent: sectionStyle.accent,
                    onBack: { dismiss() }
                )

                if hasActiveScanDraft {
                    Button {
                        returnToScanSetup()
                    } label: {
                        Label("Zurück", systemImage: "arrow.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))
                    .disabled(isRecognizingImage)
                }

                if session.batchCompleted && !previewPairs.isEmpty {
                    // Summary: nur Summary zentriert, keine Auswahl-Buttons
                    Spacer(minLength: 8)
                    batchCompleteSummary
                    Spacer(minLength: 8)
                } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
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

                        if isOnChoiceScreen {
                            // Kombinierter Header — Modul-Titel + Hauptfrage
                            // + Subtext links, Maskottchen rechts. Ersetzt
                            // die separate ScanHeroCard (war redundant).
                            ScanScreenHeader()
                                .padding(.top, 4)
                        } else {
                            // **Feature A — ScanModeBadge im Review-State**:
                            // Sobald ein Bild vorliegt oder Preview-Paare
                            // existieren, zeigt das Badge oben, in welchem
                            // Modus der aktuelle Scan läuft. Wichtig weil
                            // das Review-Layout für Liste und Freitext
                            // leicht unterschiedlich ist und der User
                            // jederzeit sehen soll, welchen Pfad er nimmt.
                            HStack {
                                ScanModeBadge(mode: activeScanMode, variant: .card)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }

                        if isOnChoiceScreen {

                            // ─────── Schritt 1 — MODUS ───────
                            // Selection-Toggles (kein Navigations-Element).
                            // Tap ändert nur den Modus, User bleibt auf dem Screen.
                            // Padding 28 → 10: Schritt 1 rückt näher an
                            // den Header, Block darunter folgt. Header
                            // selbst und Footer-Positionen bleiben
                            // unverändert (User-Spec).
                            ScanSectionLabel(stepNumber: 1, title: "Wähle den Modus")
                                .padding(.top, 10)

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
                                    title: "Freier Text",
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
                            ScanSectionLabel(stepNumber: 2, title: "Wähle die Quelle")
                                .padding(.top, 24)

                            ScanChoiceCard(
                                illustrationName: "ScanIconKamera",
                                title: "Kamera",
                                accent: sectionStyle.accent,
                                isPriority: true                            ) {
                                guard !isRecognizingImage else { return }
                                guard isCameraCaptureAvailable else { return }
                                shouldAppendNextScan = false
                                selectedScanInputMethod = .camera
                                openCameraScanner()
                            }

                            ScanChoiceCard(
                                illustrationName: "ScanIconFotoAlbum",
                                title: "Foto-Album",
                                accent: sectionStyle.accent                            ) {
                                guard !isRecognizingImage else { return }
                                shouldAppendNextScan = false
                                selectedScanInputMethod = .library
                                showingPhotoLibrary = true
                            }
                        }

                        if !session.batchCompleted {
                            if session.batchThumbnails.count > 1 {
                                // Multi-page: thumbnail strip
                                ScanBatchThumbnailCardView(
                                    thumbnails: session.batchThumbnails,
                                    currentIndex: session.batchCurrentIndex,
                                    isRecognizing: isRecognizingImage,
                                    progressText: scanProgressText,
                                    runtimeLabel: scanProgressRuntimeLabel,
                                    runtimeTint: scanProgressRuntimeTint,
                                    runtimeIcon: scanProgressRuntimeIcon,
                                    sectionStyle: sectionStyle
                                )
                            } else if let selectedImage {
                                // Single page
                                ScanSelectedImageCardView(
                                    image: selectedImage,
                                    isRecognizingImage: isRecognizingImage,
                                    progressText: scanProgressText,
                                    runtimeLabel: scanProgressRuntimeLabel,
                                    runtimeTint: scanProgressRuntimeTint,
                                    runtimeIcon: scanProgressRuntimeIcon,
                                    sectionStyle: sectionStyle,
                                    onTap: {
                                        showingImagePreview = true
                                    }
                                )
                            }
                        }

                        scanStatusMessageView
                    }
                    .padding(.bottom, 8 + scanKeyboardBottomPadding)
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
        Group {
            if isShowingImportCompletion, let ctx = importCompletionContext {
                importCompletionScreen(context: ctx)
            } else {
                applyingScanPresentationModifiers(
                    to: applyingScanRootModifiers(
                        to: ScrollViewReader { proxy in
                            scanRootContent(proxy: proxy)
                        }
                    )
                )
            }
        }
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
            onViewList: {
                handleCompletionSelection(.lists(context.listLaunchContext))
            },
            onLater: {
                handleCompletionSelection(nil)
            }
        )
    }
}
