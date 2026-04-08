import SwiftUI

struct ListPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let style: AppSectionStyle
    let lists: [VocabularyList]
    let selectedListID: UUID
    let onSelect: (UUID) -> Void
    let onDelete: (VocabularyList) -> Void

    @State private var listPendingDeletion: VocabularyList?

    private var displayedLists: [VocabularyList] {
        lists.sorted { lhs, rhs in
            let lhsIsDictionary = lhs.id == VocabularyListStore.dictionaryListID
            let rhsIsDictionary = rhs.id == VocabularyListStore.dictionaryListID
            if lhsIsDictionary != rhsIsDictionary {
                return lhsIsDictionary
            }
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return !lhs.isBuiltIn
            }
            if lhs.isAggregateVocabulary != rhs.isAggregateVocabulary {
                return lhs.isAggregateVocabulary
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

    private var selectedList: VocabularyList? {
        displayedLists.first(where: { $0.id == selectedListID })
    }

    private var summaryText: String {
        if let selected = selectedList {
            return "\(selected.name) · \(selected.items.count) Einträge"
        }
        return "Keine Liste ausgewählt"
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Liste wählen",
                leadingTint: style.accent,
                onLeading: { dismiss() }
            )

            Text(summaryText)
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppTheme.Spacing.md)
                .background(AppTheme.Colors.success.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(displayedLists) { list in
                        Button {
                            onSelect(list.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(list.name)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text("\(listCollectionSummary(for: list)) · \(list.items.count) Einträge")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: list.id == selectedListID ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(list.id == selectedListID ? style.accent : AppTheme.Colors.textDisabled)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .appCardBackground(style, intensity: list.id == selectedListID ? 0.22 : 0.05, cornerRadius: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(list.id == selectedListID ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
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
        .alert("Wirklich löschen?", isPresented: Binding(
            get: { listPendingDeletion != nil },
            set: { if !$0 { listPendingDeletion = nil } }
        )) {
            Button("Nein", role: .cancel) {
                listPendingDeletion = nil
            }
            Button("Ja", role: .destructive) {
                if let listPendingDeletion {
                    onDelete(listPendingDeletion)
                    self.listPendingDeletion = nil
                }
            }
        } message: {
            Text(listPendingDeletion.map { "„\($0.name)“ wird gelöscht." } ?? "")
        }
    }
}

