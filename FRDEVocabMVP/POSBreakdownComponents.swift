import SwiftUI

// MARK: - Tappable Wortart-Breakdown
//
// Wiederverwendbare UI-Komponente für die Wortarten-Statistik einer Liste.
// Der „X Verben"-Bereich ist tappable — öffnet ein Sheet mit den Verb-Lemmata
// (+ deutsche Übersetzung, falls verfügbar).

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

    @State private var showingVerbSheet: Bool = false

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
        .sheet(isPresented: $showingVerbSheet) {
            VerbLemmaListSheet(lemmas: stats.verbLemmas)
        }
    }

    // MARK: - Parts

    private enum PartKind {
        case noun, verb, adjective, adverb, interjection
    }

    private struct Part: Identifiable {
        let id: String
        let text: String
        let color: Color
        let tap: (() -> Void)?
        init(kind: String, text: String, color: Color, tap: (() -> Void)? = nil) {
            self.id = kind
            self.text = text
            self.color = color
            self.tap = tap
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
                    out.append(Part(kind: "noun", text: "\(stats.uniqueNounCount) Nomen", color: baseColor))
                }
            case .verb:
                if stats.uniqueVerbCount > 0 {
                    out.append(Part(kind: "verb", text: "\(stats.uniqueVerbCount) Verben", color: verbColor) {
                        showingVerbSheet = true
                    })
                }
            case .adjective:
                if stats.uniqueAdjectiveCount > 0 {
                    let label = layout == .twoLines ? "Adjektive" : "Adj."
                    out.append(Part(kind: "adj", text: "\(stats.uniqueAdjectiveCount) \(label)", color: baseColor))
                }
            case .adverb:
                if stats.uniqueAdverbCount > 0 {
                    out.append(Part(kind: "adv", text: "\(stats.uniqueAdverbCount) Adverbien", color: baseColor))
                }
            case .interjection:
                if stats.uniqueInterjectionCount > 0 {
                    let label = layout == .twoLines ? "Interjektionen" : "Interj."
                    out.append(Part(kind: "interj", text: "\(stats.uniqueInterjectionCount) \(label)", color: baseColor))
                }
            }
        }
        return out
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
                if let action = part.tap {
                    Button(action: action) {
                        Text(part.text)
                            .font(font)
                            .foregroundStyle(part.color)
                            .underline()
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(part.text)
                        .font(font)
                        .foregroundStyle(part.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sheet: Verb-Lemma-Liste

struct VerbLemmaListSheet: View {
    let lemmas: [String]
    @Environment(\.dismiss) private var dismiss

    /// Deutsche Übersetzung pro Lemma (lazy geladen, gecached)
    @State private var translations: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(lemmas, id: \.self) { lemma in
                        HStack {
                            Text(lemma)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(FrenchLemmaFormatter.verbAccentColor)
                            Spacer()
                            if let de = translations[lemma] {
                                Text(de)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("\(lemmas.count) \(lemmas.count == 1 ? "Verb" : "Verben") in dieser Liste")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Verben")
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

    private func loadTranslations() async {
        // Lookup im Hintergrund, damit das Sheet sofort aufgeht
        var map: [String: String] = [:]
        await Task.detached(priority: .userInitiated) {
            var result: [String: String] = [:]
            for lemma in lemmas {
                if let de = SupplementalFreeDictLexicon.germanTranslation(
                    forFrenchLemma: lemma,
                    wordClassHint: "verb"
                ) {
                    result[lemma] = de
                }
            }
            map = result
        }.value
        translations = map
    }
}
