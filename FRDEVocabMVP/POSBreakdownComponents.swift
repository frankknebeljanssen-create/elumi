import SwiftUI

// MARK: - Tappable Wortart-Breakdown
//
// Wiederverwendbare UI-Komponente für die Wortarten-Statistik einer Liste.
// **Alle** Wortarten sind seit Bestandsaufnahme tappable — nicht nur
// Verben, wie ursprünglich: Nomen, Verben, Adjektive, Adverbien und
// Interjektionen öffnen ein Sheet mit den jeweiligen Lemmata (+ deutsche
// Übersetzung, falls verfügbar). Semantik identisch zum früheren Verb-
// Sheet, nur pro Wortart mit passendem Titel und Akzentfarbe.

struct POSBreakdownLine: View {
    let stats: ListPOSStatistics
    var font: Font = .system(size: 11, weight: .semibold, design: .rounded)
    var baseColor: Color = AppTheme.Colors.textSecondary
    var verbColor: Color = FrenchLemmaFormatter.verbAccentColor
    var layout: Layout = .oneLine

    enum Layout {
        case oneLine     // Alle Teile in einer Zeile
        case twoLines    // Nomen/Verben auf Zeile 1, Rest auf Zeile 2
    }

    /// Welche Wortart ist gerade im Detail-Sheet sichtbar. `nil` = kein
    /// Sheet offen. Wird pro Tap gesetzt; ein einziger `.sheet(item:)`-
    /// Modifier reicht aus, statt fünf Einzel-Bools.
    @State private var sheetKind: PartKind?

    var body: some View {
        Group {
            switch layout {
            case .oneLine:
                breakdownHStack(parts: allParts)
            case .twoLines:
                VStack(alignment: .leading, spacing: 2) {
                    let line1Parts = partsForLine(indices: [.noun, .verb])
                    let line2Parts = partsForLine(indices: [.adjective, .adverb, .interjection])
                    if !line1Parts.isEmpty { breakdownHStack(parts: line1Parts) }
                    if !line2Parts.isEmpty { breakdownHStack(parts: line2Parts) }
                }
            }
        }
        .sheet(item: $sheetKind) { kind in
            POSLemmaListSheet(
                title: kind.sheetTitle,
                lemmas: lemmas(for: kind),
                accentColor: accentColor(for: kind),
                wordClassHint: kind.wordClassHint
            )
        }
    }

    // MARK: - Parts

    /// PartKind ist jetzt `Identifiable` — das `.sheet(item:)`-Pattern
    /// arbeitet darauf. Identität = rawValue, damit zwei gleiche Taps
    /// keine doppelten Sheet-Präsentationen triggern.
    enum PartKind: String, Identifiable, CaseIterable {
        case noun, verb, adjective, adverb, interjection

        var id: String { rawValue }

        /// Sheet-Titel — jeweils passend zum Wortart-Plural.
        var sheetTitle: String {
            switch self {
            case .noun:         return "Nomen"
            case .verb:         return "Verben"
            case .adjective:    return "Adjektive"
            case .adverb:       return "Adverbien"
            case .interjection: return "Interjektionen"
            }
        }

        /// Hint für das Lexikon-Lookup der deutschen Übersetzung. Mapping
        /// analog zu bestehenden `SupplementalFreeDictLexicon`-Calls.
        var wordClassHint: String {
            switch self {
            case .noun:         return "noun"
            case .verb:         return "verb"
            case .adjective:    return "adjective"
            case .adverb:       return "adverb"
            case .interjection: return "interjection"
            }
        }
    }

    private struct Part: Identifiable {
        let id: String
        let kind: PartKind
        let text: String
        let color: Color
        init(kind: PartKind, text: String, color: Color) {
            self.id = kind.rawValue
            self.kind = kind
            self.text = text
            self.color = color
        }
    }

    private var allParts: [Part] {
        partsForLine(indices: [.noun, .verb, .adjective, .adverb, .interjection])
    }

    private func partsForLine(indices: [PartKind]) -> [Part] {
        var out: [Part] = []
        for k in indices {
            switch k {
            case .noun:
                if stats.uniqueNounCount > 0 {
                    out.append(Part(kind: .noun, text: "\(stats.uniqueNounCount) Nomen", color: baseColor))
                }
            case .verb:
                if stats.uniqueVerbCount > 0 {
                    // Verben behalten ihre Akzentfarbe als historisches
                    // Signal für „trainierbare Wortart" — alle anderen
                    // bleiben im Sekundär-Grau, bekommen aber dieselbe
                    // Unterstreichung im Tap-State.
                    out.append(Part(kind: .verb, text: "\(stats.uniqueVerbCount) Verben", color: verbColor))
                }
            case .adjective:
                if stats.uniqueAdjectiveCount > 0 {
                    let label = layout == .twoLines ? "Adjektive" : "Adj."
                    out.append(Part(kind: .adjective, text: "\(stats.uniqueAdjectiveCount) \(label)", color: baseColor))
                }
            case .adverb:
                if stats.uniqueAdverbCount > 0 {
                    out.append(Part(kind: .adverb, text: "\(stats.uniqueAdverbCount) Adverbien", color: baseColor))
                }
            case .interjection:
                if stats.uniqueInterjectionCount > 0 {
                    let label = layout == .twoLines ? "Interjektionen" : "Interj."
                    out.append(Part(kind: .interjection, text: "\(stats.uniqueInterjectionCount) \(label)", color: baseColor))
                }
            }
        }
        return out
    }

    /// Liefert die zur Wortart gehörenden Lemmata — Zentrale Dispatch-
    /// Funktion, damit das Sheet nur eine Property lesen muss.
    private func lemmas(for kind: PartKind) -> [String] {
        switch kind {
        case .noun:         return stats.nounLemmas
        case .verb:         return stats.verbLemmas
        case .adjective:    return stats.adjectiveLemmas
        case .adverb:       return stats.adverbLemmas
        case .interjection: return stats.interjectionLemmas
        }
    }

    /// Akzentfarbe pro Wortart fürs Sheet — Verben behalten ihre
    /// bekannte Farbe, alle anderen teilen sich die Home-Akzentfarbe
    /// als ruhige, neutrale Linien-Farbe im Sheet-Header.
    private func accentColor(for kind: PartKind) -> Color {
        switch kind {
        case .verb: return verbColor
        default:    return AppSectionStyle.home.accent
        }
    }

    @ViewBuilder
    private func breakdownHStack(parts: [Part]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                if index > 0 {
                    Text("\u{00B7}")
                        .font(font)
                        .foregroundStyle(baseColor.opacity(0.7))
                }
                // Alle Parts sind jetzt tappable — die Unterstreichung
                // signalisiert dem User „dahinter kommt etwas". Kein
                // Part bleibt stumm.
                Button {
                    sheetKind = part.kind
                } label: {
                    Text(part.text)
                        .font(font)
                        .foregroundStyle(part.color)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sheet: Lemma-Liste pro Wortart (generisch)

/// Wortart-agnostische Variante des ehemaligen `VerbLemmaListSheet`.
/// Zeigt eine Liste von Lemmata mit deutscher Übersetzung (falls im
/// Supplemental-Lexikon auffindbar). Die Wortart wird nur noch als
/// `wordClassHint` an den Lexikon-Lookup weitergereicht und bestimmt
/// Titel + Akzentfarbe.
struct POSLemmaListSheet: View {
    let title: String
    let lemmas: [String]
    let accentColor: Color
    /// Lexikon-Hint für Translation-Lookup — „verb", „noun", „adjective" usw.
    let wordClassHint: String

    @Environment(\.dismiss) private var dismiss
    @State private var translations: [String: String] = [:]

    /// Für Nomen: pro Lemma die französische (le/la/l') und deutsche
    /// (der/die/das) Artikel-/Genus-Information. Wird nur für
    /// `wordClassHint == "noun"` befüllt; alle anderen Wortarten
    /// bleiben unverändert ohne Artikel-Annotation.
    @State private var nounArticles: [String: (french: String?, german: String?)] = [:]

    private var showsGender: Bool { wordClassHint == "noun" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(lemmas, id: \.self) { lemma in
                        HStack {
                            // Französisches Lemma: Artikel davor, wenn
                            // als Nomen erkannt (z. B. „le chat", „la
                            // maison", „l'école"). Bei anderen Wortarten
                            // nur das Lemma.
                            Text(frenchDisplay(for: lemma))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(accentColor)
                            Spacer()
                            if let de = translations[lemma] {
                                // Deutsche Übersetzung analog mit
                                // Artikel (der/die/das), wenn verfügbar.
                                Text(germanDisplay(translation: de, for: lemma))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(headerLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadTranslations()
        }
    }

    // MARK: - Noun-Display-Helpers

    /// Liefert den französischen Anzeigetext — für Nomen inklusive
    /// vorangestelltem Artikel (le/la/l'), für andere Wortarten nur
    /// das Lemma. Wenn das Lemma bereits mit einem Artikel beginnt
    /// (selten bei Scan-Imports, aber möglich), wird nichts dupliziert.
    private func frenchDisplay(for lemma: String) -> String {
        guard showsGender else { return lemma }
        if startsWithFrenchArticle(lemma) { return lemma }
        guard let article = nounArticles[lemma]?.french, !article.isEmpty else {
            return lemma
        }
        // „l'" wird ohne Leerzeichen angesetzt, alle anderen Artikel
        // mit Leerzeichen. Diese Konvention folgt der französischen
        // Schulbuch-Notation.
        if article == "l'" {
            return article + lemma
        }
        return "\(article) \(lemma)"
    }

    /// Liefert die deutsche Anzeige — für Nomen inklusive Artikel
    /// (der/die/das). Bereits enthaltenen Artikel nicht duplizieren.
    private func germanDisplay(translation: String, for lemma: String) -> String {
        guard showsGender else { return translation }
        if startsWithGermanArticle(translation) { return translation }
        guard let article = nounArticles[lemma]?.german, !article.isEmpty else {
            return translation
        }
        return "\(article) \(translation)"
    }

    private func startsWithFrenchArticle(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("l'") || lower.hasPrefix("l’") { return true }
        for art in ["le ", "la ", "les ", "un ", "une ", "des "] where lower.hasPrefix(art) {
            return true
        }
        return false
    }

    private func startsWithGermanArticle(_ text: String) -> Bool {
        let lower = text.lowercased()
        for art in ["der ", "die ", "das ", "den ", "dem ", "ein ", "eine ", "einer ", "einen "] where lower.hasPrefix(art) {
            return true
        }
        return false
    }

    /// Header formuliert Singular/Plural automatisch aus dem Titel. Für
    /// die deutsche Grammatik sind Plurale der Wortarten („Nomen",
    /// „Verben", „Adjektive" …) als Titel bereits gesetzt — der Header
    /// kombiniert nur noch Count + Titel.
    private var headerLabel: String {
        "\(lemmas.count) \(lemmas.count == 1 ? singularFromTitle : title) in dieser Lernliste"
    }

    private var singularFromTitle: String {
        switch title {
        case "Nomen":         return "Nomen"           // Nomen ist invariant
        case "Verben":        return "Verb"
        case "Adjektive":     return "Adjektiv"
        case "Adverbien":     return "Adverb"
        case "Interjektionen": return "Interjektion"
        default:              return title
        }
    }

    private func loadTranslations() async {
        var map: [String: String] = [:]
        var articleMap: [String: (french: String?, german: String?)] = [:]
        let shouldResolveGender = (wordClassHint == "noun")
        await Task.detached(priority: .userInitiated) {
            var resultTranslations: [String: String] = [:]
            var resultArticles: [String: (french: String?, german: String?)] = [:]
            for lemma in lemmas {
                // Deutsche Übersetzung — wie bisher.
                let translation = SupplementalFreeDictLexicon.germanTranslation(
                    forFrenchLemma: lemma,
                    wordClassHint: wordClassHint
                )
                if let translation {
                    resultTranslations[lemma] = translation
                }

                // Genus/Artikel nur für Nomen auflösen — sonst sparen
                // wir uns die Lookups.
                if shouldResolveGender {
                    let frInfo = frenchGenderInfo(for: lemma, cardType: .words)
                    let deInfo: LexiconGenderInfo? = {
                        guard let t = translation else { return nil }
                        return germanGenderInfo(for: t, cardType: .words)
                    }()
                    let frArticle = frInfo?.article ?? suggestedFrenchArticleString(for: frInfo?.gender)
                    let deArticle = deInfo?.article ?? suggestedGermanArticleString(for: deInfo?.gender)
                    if frArticle != nil || deArticle != nil {
                        resultArticles[lemma] = (french: frArticle, german: deArticle)
                    }
                }
            }
            map = resultTranslations
            articleMap = resultArticles
        }.value
        translations = map
        nounArticles = articleMap
    }

    /// Fallback: wenn der LexiconGenderInfo keinen expliziten `article`
    /// hat (z. B. weil nur eine heuristische Gender-Erkennung vorliegt),
    /// leiten wir den „Default-Artikel" aus dem Genus ab. Für die
    /// Sheet-Anzeige ist es besser, „le chat" zu zeigen als nur „chat"
    /// zu belassen — der Artikel ist die gewünschte Zusatzinfo.
    private nonisolated func suggestedFrenchArticleString(for gender: LexiconNounGender?) -> String? {
        guard let gender else { return nil }
        switch gender {
        case .masculine: return "le"
        case .feminine:  return "la"
        case .plural:    return "les"
        case .neuter:    return nil  // existiert im Französischen nicht
        }
    }

    private nonisolated func suggestedGermanArticleString(for gender: LexiconNounGender?) -> String? {
        guard let gender else { return nil }
        switch gender {
        case .masculine: return "der"
        case .feminine:  return "die"
        case .neuter:    return "das"
        case .plural:    return "die"
        }
    }
}

// MARK: - Backwards-Compat

/// Alter Alias — die frühere `VerbLemmaListSheet` wird noch von
/// anderen Stellen referenziert (alter Code im Training-Layout
/// ruft sie direkt auf). Der Alias delegiert an die generische
/// Variante, damit die alten Call-Sites weiter funktionieren, ohne
/// angefasst werden zu müssen.
struct VerbLemmaListSheet: View {
    let lemmas: [String]

    var body: some View {
        POSLemmaListSheet(
            title: "Verben",
            lemmas: lemmas,
            accentColor: FrenchLemmaFormatter.verbAccentColor,
            wordClassHint: "verb"
        )
    }
}
