import SwiftUI

struct LexiconInfoCard: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    let tint: Color
    let secondaryTextColor: Color
    let sectionStyle: AppSectionStyle
    var showsProgress = false

    var body: some View {
        HStack(spacing: 14) {
            if showsProgress {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(tint)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }
}

struct LexiconSearchCardView: View {
    @Binding var searchText: String
    let accentColor: Color
    let secondaryTextColor: Color
    let sectionStyle: AppSectionStyle
    let searchFocus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accentColor)

            TextField("Französisch oder Deutsch suchen", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .focused(searchFocus)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(secondaryTextColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }
}

struct LexiconEntryRowView: View {
    let entry: PreparedLexiconEntry
    let sourceCountryCode: String
    let targetCountryCode: String
    let sourceText: String
    let targetText: String
    let wordClassMarker: LexiconWordClassMarker?
    /// Vollständiger Wortart-Badge-Text (zentrale Quelle: FrenchLemmaFormatter.wordClassLabel).
    /// Alle Wortarten bekommen einen Badge — Pronomen, Konjunktion, Adverb, Adjektiv etc.
    var wordClassBadge: String? = nil
    let accentColor: Color
    let secondaryTextColor: Color
    let rowBackgroundColor: Color
    let rowBorderColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        LexiconFlagBadge(countryCode: sourceCountryCode, compact: true)
                            .padding(.top, 1)

                        Text(sourceText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)

                        if let badge = wordClassBadge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(accentColor.opacity(0.14))
                                .clipShape(Capsule())
                        } else if let wordClassMarker {
                            Text(wordClassMarker.rawValue)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(accentColor)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(alignment: .top, spacing: 6) {
                        LexiconFlagBadge(countryCode: targetCountryCode, compact: true)
                            .padding(.top, 1)

                        Text(targetText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(3)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(secondaryTextColor)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(rowBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(rowBorderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LexiconDetailSheetView: View {
    let entry: PreparedLexiconEntry
    let sourceCountryCode: String
    let targetCountryCode: String
    let sourceText: String
    let targetTexts: [String]
    let wordClassMarker: LexiconWordClassMarker?
    let sectionStyle: AppSectionStyle
    let onDone: () -> Void

    /// **Wörterbuch-Audio (Phase 8)**: eigener Speaker pro Detail-Sheet.
    /// `@StateObject` hält die Instanz über das Leben der Sheet-Präsentation,
    /// damit der AVSpeechSynthesizer nicht bei jedem Re-Render neu erzeugt
    /// wird (sonst schluckt der erste Tap manchmal das Audio).
    @StateObject private var speaker = Speaker()

    /// Country-Code → BCP-47-Sprachcode. Gleiche Mapping-Logik wie in den
    /// bestehenden `speaker.speak(…)`-Aufrufern (Training, Flashcards,
    /// Akzente). Fallback auf Französisch, weil das Wörterbuch primär
    /// FR↔DE abdeckt.
    private func languageCode(for countryCode: String) -> String {
        switch countryCode.uppercased() {
        case "FR": return "fr-FR"
        case "DE": return "de-DE"
        case "EN", "GB", "US": return "en-US"
        case "IT": return "it-IT"
        case "ES": return "es-ES"
        default:    return "fr-FR"
        }
    }

    /// Entfernt Genus-Marker in Klammern aus dem gesprochenen Text —
    /// „(m)", „(f)", „(n)", „(m/f)", „(pl)" werden nicht mitgesprochen,
    /// weil TTS sie sonst als „Klammer auf m Klammer zu" vokalisieren
    /// oder komisch betonen würde. Die Marker bleiben auf dem Screen
    /// sichtbar — nur die Audio-Pipeline bereinigt sie.
    private static func stripGenusMarkers(from text: String) -> String {
        var cleaned = text
        // Muster: ` ? ( ? m|f|n|pl [ ? / ? m|f|n|pl ]* ? ) ? `
        // Bewusst klein gehalten — nur Genus-/Numerus-Marker, keine
        // anderen Klammer-Inhalte (Beispielsätze können Klammern enthalten).
        let pattern = #"\s*\(\s*(?:m|f|n|pl)(?:\s*/\s*(?:m|f|n|pl))?\s*\)"#
        cleaned = cleaned.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
        // Mehrfachleerzeichen einsammeln, die durch das Entfernen entstehen.
        cleaned = cleaned.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lautsprecher-Button (Sprecher-Kopf-Icon). Tap spricht das
    /// übergebene Wort einmal im korrekten Sprachcode aus. Während der
    /// Wiedergabe ist er disabled, damit Doppel-Taps keine Überlagerung
    /// erzeugen. `isCompact` rendert eine kleinere Variante (z. B. für
    /// Beispielsätze), `isCompact = false` die große Header-Variante.
    @ViewBuilder
    private func speakerButton(
        for text: String,
        countryCode: String,
        isCompact: Bool = false
    ) -> some View {
        let code = languageCode(for: countryCode)
        let isBusy = speaker.isSpeaking
        let diameter: CGFloat = isCompact ? 26 : 32
        let iconSize: CGFloat = isCompact ? 12 : 15
        Button {
            let spoken = Self.stripGenusMarkers(from: text)
            guard !spoken.isEmpty else { return }
            speaker.speak(text: spoken, languageCode: code)
        } label: {
            Image(systemName: isBusy ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(sectionStyle.accent)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle().fill(sectionStyle.accent.opacity(isBusy ? 0.28 : 0.16))
                )
                .overlay(
                    Circle().stroke(sectionStyle.accent.opacity(isCompact ? 0.25 : 0.35),
                                    lineWidth: isCompact ? 0.75 : 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityLabel("Vorsprechen")
    }

    /// Alle Beispielsätze aller Einträge dieser Gruppe, deduped via example_id,
    /// sortiert: bevorzugt `example_order = 1` zuerst.
    private var allExamples: [DictionaryExample] {
        var seen = Set<Int>()
        var combined: [DictionaryExample] = []
        for lexEntry in entry.entries {
            guard let entryID = lexEntry.entryID else { continue }
            for ex in SupplementalFreeDictLexicon.examples(forEntryID: entryID) {
                if seen.insert(ex.id).inserted {
                    combined.append(ex)
                }
            }
        }
        return combined.sorted { lhs, rhs in
            let lo = lhs.order > 0 ? lhs.order : 999
            let ro = rhs.order > 0 ? rhs.order : 999
            if lo != ro { return lo < ro }
            return lhs.id < rhs.id
        }
    }

    private func wordClassLabel(isFrench: Bool) -> String {
        // Zentrale Single-Source-of-Truth: FrenchLemmaFormatter.
        // Marker hat Vorrang (für Direktanzeige im französischen Raum), sonst LexiconEntry-Lookup.
        if let marker = wordClassMarker {
            switch marker {
            case .noun:      return isFrench ? "Nom"        : "Nomen"
            case .adjective: return isFrench ? "Adjectif"   : "Adjektiv"
            case .verb:      return isFrench ? "Verbe"      : "Verb"
            case .phrase:    return isFrench ? "Expression" : "Redewendung"
            }
        }
        guard let firstEntry = entry.entries.first else {
            return isFrench ? "Nom" : "Nomen"
        }
        let germanLabel = FrenchLemmaFormatter.wordClassLabel(forLexiconEntry: firstEntry)
        if !isFrench { return germanLabel }
        // Französische Übersetzung der deutschen Bezeichnung
        return FrenchLemmaFormatter.frenchLabel(forGermanLabel: germanLabel)
    }

    private func translationGroupCard(countryCode: String?, badge: String?, translations: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let cc = countryCode {
                    LexiconFlagBadge(countryCode: cc, compact: false)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(sectionStyle.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(sectionStyle.accent.opacity(0.14))
                        .clipShape(Capsule())
                }
                // **Wörterbuch-Audio (Phase 8)**: Lautsprecher rechts oben.
                // Spricht die erste/primäre Übersetzung in der Zielsprache
                // aus — bei mehreren bulleted-Alternativen gewinnt die erste,
                // weil sie im UI am prominentesten dargestellt wird.
                if let primary = translations.first, !primary.isEmpty,
                   let cc = countryCode {
                    speakerButton(for: primary, countryCode: cc)
                }
            }

            if translations.count == 1 {
                Text(translations[0])
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(sectionStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(translations.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(sectionStyle.accent)
                            Text(text)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(sectionStyle.accent)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }

    private func wordClassBadge(isFrench: Bool) -> some View {
        Text(wordClassLabel(isFrench: isFrench))
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(sectionStyle.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(sectionStyle.accent.opacity(0.14))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func examplesCard(_ examples: [DictionaryExample]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(examples.count == 1 ? "Beispiel" : "Beispiele")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Text("\(examples.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(sectionStyle.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(sectionStyle.accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(examples) { ex in
                    // **Wörterbuch-Audio Phase 8 (Beispiele)**: pro Beispiel-
                    // Zeile jeweils ein kleiner Lautsprecher rechts — für
                    // Französisch immer, für Deutsch nur wenn vorhanden.
                    // Kompakt-Variante (`isCompact: true`), damit die Beispiele
                    // nicht optisch von den großen Header-Buttons dominiert
                    // werden.
                    VStack(alignment: .leading, spacing: 4) {
                        // **Bug-A-Fix (2026-05-02) — Fragezeichen-Render einheitlich.**
                        // Vorher: `Text(ex.french)` / `Text(ex.german)` raw —
                        // ohne Helper im Pfad. Trailing `?` aus DB blieb zwar
                        // erhalten (kein Cleaning), aber Inferenz für Einträge
                        // ohne explizites `?` (DB-Asymmetrie: 36% DE / 83% FR
                        // mit `?`) fehlte. Jetzt durchgereicht über die
                        // preserve+infer-Helfer wie überall sonst — gleiche
                        // Render-Pipeline wie Karteikarten / Quiz.
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(sourceDisplayText(ex.french, sourceLanguage: .french))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            speakerButton(for: ex.french, countryCode: "FR", isCompact: true)
                        }
                        if !ex.german.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(germanDisplayText(ex.german, cardType: .phrases, sourceHint: ex.french))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                speakerButton(for: ex.german, countryCode: "DE", isCompact: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.gentle)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Source language section — Flag + Speaker oben in einer
                    // Zeile, Quellwort darunter groß. **Wörterbuch-Audio
                    // Phase 8**: Lautsprecher rechts oben, Spiegel-Logik zur
                    // Target-Card, damit beide Sprachen konsistent klickbar
                    // sind.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            LexiconFlagBadge(countryCode: sourceCountryCode, compact: false)
                            Spacer()
                            if !sourceText.isEmpty {
                                speakerButton(for: sourceText, countryCode: sourceCountryCode)
                            }
                        }

                        Text(sourceText)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)

                    // Target language section — use targetTexts which respect direction
                    let badgeText: String? = {
                        guard let marker = wordClassMarker else { return nil }
                        switch marker {
                        case .noun: return targetCountryCode == "FR" ? "Nom" : "Nomen"
                        case .adjective: return targetCountryCode == "FR" ? "Adj" : "Adj"
                        case .verb: return targetCountryCode == "FR" ? "Verbe" : "Verb"
                        case .phrase: return targetCountryCode == "FR" ? "Expression" : "Redewendung"
                        }
                    }()

                    translationGroupCard(
                        countryCode: targetCountryCode,
                        badge: badgeText,
                        translations: targetTexts
                    )

                    // Beispiele (aus examples-Tabelle, mehrere pro Eintrag möglich,
                    // sortiert nach example_order; `order=1` zuerst)
                    let examples = allExamples
                    if !examples.isEmpty {
                        examplesCard(examples)
                    }
                }
                .padding(AppLayout.screenPadding)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .appScreenBackground(sectionStyle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        onDone()
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct LexiconFlagBadge: View {
    let countryCode: String
    let compact: Bool

    var body: some View {
        StraightFlagBadge(
            countryCode: countryCode,
            width: compact ? 24 : 34,
            height: compact ? 16 : 22,
            labelFontSize: compact ? 8 : 11
        )
    }
}
