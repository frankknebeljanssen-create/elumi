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
                VStack(spacing: 6) {
                    // Section: Eigene Listen
                    if !ownLists.isEmpty {
                        sectionHeader("📝 Meine Listen")
                        ForEach(ownLists) { list in
                            listRow(list)
                        }
                    }

                    if !levelLists.isEmpty {
                        sectionHeader("📚 Wortschatz nach Niveau")
                        ForEach(levelLists) { list in
                            listRow(list)
                        }
                    }

                    // Section: Wortschatz nach Thema
                    if !topicLists.isEmpty {
                        sectionHeader("🏷️ Wortschatz nach Thema")
                        ForEach(topicLists) { list in
                            listRow(list)
                        }
                    }

                    // Komplettes Wörterbuch ganz unten
                    Spacer().frame(height: 12)
                    sectionHeader("📖 Komplettes Wörterbuch")
                    listRow(StandardVocabularyLoader.allInOneList)
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
            // App-weites 5er-Limit für Mehrfachauswahl
            guard localSelection.count < AppLayout.maxSelectableLists else { return }
            localSelection.insert(list.id)
        }
    }

    private var ownLists: [VocabularyList] {
        displayedLists.filter {
            (!$0.isBuiltIn || $0.isAggregateVocabulary)
            && $0.id != VocabularyListStore.dictionaryListID
        }
    }


    private var levelLists: [VocabularyList] {
        displayedLists.filter { $0.collectionPreset == .standardLevel }
    }

    private var topicLists: [VocabularyList] {
        displayedLists.filter { $0.collectionPreset == .standardTopic }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private func listRow(_ list: VocabularyList) -> some View {
        Button {
            toggleSelection(for: list)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(flashcardListDisplayName(list))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if !list.isBuiltIn || list.collectionPreset == .standardLevel || list.collectionPreset == .standardTopic {
                        Text("\(cardCount(for: list)) Einträge")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: localSelection.contains(list.id) ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(localSelection.contains(list.id) ? style.accent : AppTheme.Colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .appCardBackground(style, intensity: localSelection.contains(list.id) ? 0.22 : 0.05, cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(localSelection.contains(list.id) ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func cardCount(for list: VocabularyList) -> Int {
        list.items.filter {
            $0.sourceLanguage == language &&
            (cardTypeFilter == nil || $0.cardType == cardTypeFilter)
        }.count
    }
}
