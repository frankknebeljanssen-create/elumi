import SwiftUI

struct FlashcardStackComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let style: AppSectionStyle
    let lists: [VocabularyList]
    let selectedListIDs: Set<UUID>
    let language: StudyLanguage
    let cardTypeFilter: CardType?
    let onSave: (Set<UUID>) -> Void

    @State private var localSelection: Set<UUID> = []

    private var displayedLists: [VocabularyList] {
        lists.sorted { lhs, rhs in
            let lhsIsDictionary = lhs.id == VocabularyListStore.dictionaryListID
            let rhsIsDictionary = rhs.id == VocabularyListStore.dictionaryListID
            if lhsIsDictionary != rhsIsDictionary {
                return lhsIsDictionary
            }
            if lhs.isAggregateVocabulary != rhs.isAggregateVocabulary {
                return lhs.isAggregateVocabulary
            }
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return !lhs.isBuiltIn
            }
            if lhs.collectionPreset.group.sortOrder != rhs.collectionPreset.group.sortOrder {
                return lhs.collectionPreset.group.sortOrder < rhs.collectionPreset.group.sortOrder
            }
            if lhs.collectionPreset.sortOrder != rhs.collectionPreset.sortOrder {
                return lhs.collectionPreset.sortOrder < rhs.collectionPreset.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var totalSelectedCards: Int {
        displayedLists.reduce(0) { partialResult, list in
            guard localSelection.contains(list.id) else { return partialResult }
            return partialResult + cardCount(for: list)
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Listen auswählen",
                trailingTitle: "Fertig",
                leadingTint: style.accent,
                trailingTint: style.accent,
                onLeading: { dismiss() },
                onTrailing: {
                    onSave(localSelection)
                    dismiss()
                }
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text("\(countLabel(localSelection.count, singular: "Liste", plural: "Listen")) · \(countLabel(totalSelectedCards, singular: "Karte", plural: "Karten"))")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(.white)
                Text("Tippe an, aus welchen Listen dein Stapel bestehen soll.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.success.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(displayedLists) { list in
                        VStack(spacing: 0) {
                            Button {
                                toggleSelection(for: list)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(flashcardListDisplayName(list))
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(AppTheme.Colors.textPrimary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                            .minimumScaleFactor(0.8)

                                        if !list.isBuiltIn {
                                            Text(listCollectionSummary(for: list))
                                                .font(AppTheme.Typography.caption)
                                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer(minLength: 0)

                                    Text(countLabel(cardCount(for: list), singular: "Karte", plural: "Karten"))
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .monospacedDigit()
                                        .multilineTextAlignment(.trailing)
                                        .frame(minWidth: 78, alignment: .trailing)

                                    Image(systemName: localSelection.contains(list.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(localSelection.contains(list.id) ? style.accent : .secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .appCardBackground(style, intensity: localSelection.contains(list.id) ? 0.22 : 0.05, cornerRadius: 18)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(localSelection.contains(list.id) ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)

                            if list.isAggregateVocabulary {
                                Color.clear
                                    .frame(height: 8)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(style.accent)
        .appScreenBackground(style)
        .onAppear {
            localSelection = selectedListIDs
        }
    }

    private func toggleSelection(for list: VocabularyList) {
        if list.isAggregateVocabulary {
            localSelection = localSelection.contains(list.id) ? [] : [list.id]
            return
        }

        localSelection.remove(VocabularyListStore.allCustomVocabularyListID)

        if localSelection.contains(list.id) {
            localSelection.remove(list.id)
        } else {
            localSelection.insert(list.id)
        }
    }

    private func cardCount(for list: VocabularyList) -> Int {
        list.items.filter {
            $0.sourceLanguage == language &&
            (cardTypeFilter == nil || $0.cardType == cardTypeFilter)
        }.count
    }
}
