import SwiftUI

struct ListPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let style: AppSectionStyle
    let lists: [VocabularyList]
    let selectedListID: UUID
    let onSelect: (UUID) -> Void
    let onDelete: (VocabularyList) -> Void
    var onView: ((VocabularyList) -> Void)? = nil
    var onRename: ((VocabularyList) -> Void)? = nil

    @State private var listPendingDeletion: VocabularyList?
    @State private var localSelectedID: UUID?

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

    private var currentSelectedID: UUID {
        localSelectedID ?? selectedListID
    }

    private var selectedList: VocabularyList? {
        displayedLists.first(where: { $0.id == currentSelectedID })
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
                trailingTitle: "Fertig",
                leadingTint: style.accent,
                trailingTint: style.accent,
                onLeading: { dismiss() },
                onTrailing: {
                    onSelect(currentSelectedID)
                    dismiss()
                }
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
                VStack(spacing: 6) {
                    if !ownLists.isEmpty {
                        sectionHeader("📝 Meine Listen")
                        ForEach(ownLists) { list in listRow(list) }
                    }

                    if !levelLists.isEmpty {
                        sectionHeader("📚 Wortschatz nach Niveau")
                        ForEach(levelLists) { list in listRow(list) }
                    }

                    if !topicLists.isEmpty {
                        sectionHeader("🏷️ Wortschatz nach Thema")
                        ForEach(topicLists) { list in listRow(list) }
                    }

                    Spacer().frame(height: 12)
                    sectionHeader("📖 Komplettes Wörterbuch")
                    ForEach(dictionaryLists) { list in listRow(list) }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(style.accent)
        .appScreenBackground(style)
        .onAppear { localSelectedID = selectedListID }
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

    // MARK: - Grouped Lists

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

    private var dictionaryLists: [VocabularyList] {
        displayedLists.filter {
            $0.id == VocabularyListStore.dictionaryListID
            || ($0.isBuiltIn && !$0.isAggregateVocabulary && $0.collectionPreset != .standardLevel && $0.collectionPreset != .standardTopic)
        }
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
            localSelectedID = list.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(list.name)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if !list.isBuiltIn, onRename != nil {
                            Button {
                                onRename?(list)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(style.accent.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !list.isBuiltIn {
                        wordClassBreakdownText(for: list)
                    } else {
                        Text("\(list.items.count) Eintr\u{00E4}ge")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                if !list.isBuiltIn {
                    if onView != nil {
                        Button {
                            onView?(list)
                        } label: {
                            Image(systemName: "eye")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(style.accent.opacity(0.7))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        listPendingDeletion = list
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.error.opacity(0.7))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                } else if onView != nil {
                    Button {
                        onView?(list)
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(style.accent.opacity(0.7))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: list.id == currentSelectedID ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(list.id == currentSelectedID ? style.accent : AppTheme.Colors.textDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .appCardBackground(style, intensity: list.id == currentSelectedID ? 0.22 : 0.05, cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(list.id == currentSelectedID ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func wordClassBreakdownText(for list: VocabularyList) -> some View {
        let items = list.items
        var nouns = 0
        var verbs = 0
        var adj = 0
        for item in items {
            // 1. Stored wordClass
            if let wc = item.wordClass, !wc.isEmpty {
                if wc == "noun" { nouns += 1 }
                else if wc == "verb" { verbs += 1 }
                else if wc == "adjective" { adj += 1 }
                continue
            }
            // 2. Lookup full term
            if let wc = StandardVocabularyLoader.wordClass(for: item.french) {
                if wc == "noun" { nouns += 1 }
                else if wc == "verb" { verbs += 1 }
                else if wc == "adjective" { adj += 1 }
                continue
            }
            // 3. Fallback: check individual words (for phrases like "je ne sais pas")
            let words = item.french.lowercased()
                .replacingOccurrences(of: "'", with: " ")
                .replacingOccurrences(of: "\u{2019}", with: " ")
                .split(separator: " ").map(String.init)
            if let wc = words.compactMap({ StandardVocabularyLoader.wordClass(for: $0) }).first {
                if wc == "noun" { nouns += 1 }
                else if wc == "verb" { verbs += 1 }
                else if wc == "adjective" { adj += 1 }
            }
        }

        let other = items.count - nouns - verbs - adj
        var line1Parts: [String] = []
        if nouns > 0 { line1Parts.append("\(nouns) Nomen") }
        if verbs > 0 { line1Parts.append("\(verbs) Verben") }
        var line2Parts: [String] = []
        if adj > 0 { line2Parts.append("\(adj) Adjektive") }
        if other > 0 { line2Parts.append("\(other) Andere") }

        let allParts = line1Parts + line2Parts

        return VStack(alignment: .leading, spacing: 1) {
            if allParts.isEmpty {
                Text("\(items.count) Eintr\u{00E4}ge")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                if !line1Parts.isEmpty {
                    Text(line1Parts.joined(separator: " \u{00B7} "))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                if !line2Parts.isEmpty {
                    Text(line2Parts.joined(separator: " \u{00B7} "))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }
}

