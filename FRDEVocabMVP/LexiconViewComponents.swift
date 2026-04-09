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
        .appCardBackground(sectionStyle, intensity: 0.09)
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
        .appCardBackground(sectionStyle, intensity: 0.09)
    }
}

struct LexiconEntryRowView: View {
    let entry: PreparedLexiconEntry
    let sourceCountryCode: String
    let targetCountryCode: String
    let sourceText: String
    let targetText: String
    let wordClassMarker: LexiconWordClassMarker?
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

                        if let wordClassMarker {
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
            .padding(.vertical, 9)
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

    private func wordClassLabel(isFrench: Bool) -> String {
        let stripped = strippingLeadingFrenchArticle(from: sourceText)
        if StandardVocabularyLoader.isVerb(stripped) { return isFrench ? "Verbe" : "Verb" }
        if StandardVocabularyLoader.isNoun(stripped) { return isFrench ? "Nom" : "Nomen" }
        if let marker = wordClassMarker {
            switch marker {
            case .adjective: return isFrench ? "Adjectif" : "Adjektiv"
            case .verb: return isFrench ? "Verbe" : "Verb"
            }
        }
        if StandardVocabularyLoader.isNonNoun(stripped) {
            return isFrench ? "Adjectif / Adverbe" : "Adjektiv / Adverb"
        }
        return isFrench ? "Nom" : "Nomen"
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

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Source language section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            LexiconFlagBadge(countryCode: sourceCountryCode, compact: false)
                            Spacer()
                            wordClassBadge(isFrench: sourceCountryCode == "FR")
                        }

                        Text(sourceText)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .appCardBackground(sectionStyle, intensity: 0.10)

                    // Target language section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            LexiconFlagBadge(countryCode: targetCountryCode, compact: false)
                            Spacer()
                            wordClassBadge(isFrench: targetCountryCode == "FR")
                        }

                        if targetTexts.count <= 1 {
                            Text(targetTexts.first ?? "")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(sectionStyle.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(targetTexts.enumerated()), id: \.offset) { _, target in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundStyle(sectionStyle.accent)
                                        Text(target)
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
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
                    .appCardBackground(sectionStyle, intensity: 0.10)
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
