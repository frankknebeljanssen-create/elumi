import SwiftUI

/// Shared list selection component used across Training, Flashcards, and Quiz setup screens.
/// Shows selected lists + "Liste auswählen" button that opens the category picker.
struct ListCategoryPickerView: View {
    let availableLists: [VocabularyList]
    let selectedListIDs: Set<UUID>
    let accent: Color
    let style: AppSectionStyle
    let feedbackPlayer: FeedbackPlayer
    let summaryText: String
    var itemLabel: String = "Karten"
    let onSelectionChanged: (Set<UUID>) -> Void

    enum Category: Identifiable {
        case own, level, topic
        var id: String {
            switch self {
            case .own: return "own"
            case .level: return "level"
            case .topic: return "topic"
            }
        }
    }

    @State private var activeCategory: Category?

    private var ownLists: [VocabularyList] {
        availableLists.filter { !$0.isBuiltIn || $0.isAggregateVocabulary }
    }

    private var levelLists: [VocabularyList] {
        availableLists.filter { $0.collectionPreset == .standardLevel }
    }

    private var topicLists: [VocabularyList] {
        availableLists.filter { $0.collectionPreset == .standardTopic }
    }

    private var selectedLists: [VocabularyList] {
        availableLists.filter { selectedListIDs.contains($0.id) }
    }

    private var selectedListNames: String {
        let names = selectedLists.map(\.name)
        if names.isEmpty { return "Keine Listen gewählt" }
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names[0]), \(names[1]) +\(names.count - 2)"
    }

    /// Aggregierte POS-Statistik über alle gewählten Listen — zentrale Single Source of Truth.
    private var combinedPOSStatistics: ListPOSStatistics {
        let allItems = selectedLists.flatMap(\.items)
        return FrenchListStatisticsAggregator.cachedStatistics(for: allItems)
    }

    // (wordClassBreakdownText entfernt — `POSBreakdownLine` rendert direkt aus `combinedPOSStatistics`)

    var body: some View {
        // Combined selected-lists card with edit button
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ausgewählte Listen")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.cardLabel)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if selectedLists.isEmpty {
                    Text("Keine Listen gewählt")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textDisabled)
                    // 4 Spacer-Lines, damit die Card auf 4-Zeilen-Höhe bleibt
                    Text(" ").font(.system(size: 13))
                    Text(" ").font(.system(size: 13))
                    Text(" ").font(.system(size: 13))
                    Text(" ").font(.system(size: 11))
                } else {
                    ForEach(selectedLists.prefix(4)) { list in
                        HStack(spacing: 0) {
                            Text(list.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(list.items.count) \(itemLabel)")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent)
                        }
                    }
                    if selectedLists.count > 4 {
                        Text("+\(selectedLists.count - 4) weitere")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    // Spacer-Lines, damit die Card auf 4-Zeilen-Höhe bleibt
                    if selectedLists.count == 1 {
                        Text(" ").font(.system(size: 13))
                        Text(" ").font(.system(size: 13))
                        Text(" ").font(.system(size: 13))
                    } else if selectedLists.count == 2 {
                        Text(" ").font(.system(size: 13))
                        Text(" ").font(.system(size: 13))
                    } else if selectedLists.count == 3 {
                        Text(" ").font(.system(size: 13))
                    }

                    // Aggregierte Wortarten-Übersicht über alle gewählten Listen.
                    // „X Verben" ist tappable — öffnet Sheet mit Verb-Lemmata.
                    POSBreakdownLine(stats: combinedPOSStatistics)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.trailing, 32) // room for edit icon
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selectedLists.isEmpty ? Color.clear : accent.opacity(0.08))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selectedLists.isEmpty ? AppTheme.Colors.border : accent.opacity(0.3), lineWidth: 1)
            )

            // Edit icon — opens category picker
            Button {
                feedbackPlayer.playTabSwitch()
                activeCategory = .own
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(10)
            }
            .buttonStyle(.plain)
        }
        .sheet(item: $activeCategory) { category in
            ListSelectionSheet(
                style: style,
                ownLists: ownLists,
                levelLists: levelLists,
                topicLists: topicLists,
                selectedListIDs: selectedListIDs,
                onSelectionChanged: { updatedSelection in
                    onSelectionChanged(updatedSelection)
                    activeCategory = nil
                }
            )
        }
    }
}

/// Full-screen sheet for list selection with 3 categories
struct ListSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let style: AppSectionStyle
    let ownLists: [VocabularyList]
    let levelLists: [VocabularyList]
    let topicLists: [VocabularyList]
    let selectedListIDs: Set<UUID>
    let onSelectionChanged: (Set<UUID>) -> Void

    @State private var localSelection: Set<UUID> = []

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Liste auswählen",
                trailingTitle: "Fertig",
                leadingTint: style.accent,
                trailingTint: style.accent,
                onLeading: { dismiss() },
                onTrailing: {
                    onSelectionChanged(localSelection)
                    dismiss()
                }
            )

            ScrollView {
                VStack(spacing: 6) {
                    if !ownLists.isEmpty {
                        sectionHeader("📝 Meine Listen")
                        ForEach(ownLists) { list in listRow(list) }
                    }

                    if !levelLists.isEmpty {
                        sectionHeader("📚 Nach Niveau")
                        ForEach(levelLists) { list in listRow(list) }
                    }

                    if !topicLists.isEmpty {
                        sectionHeader("🏷️ Nach Thema")
                        ForEach(topicLists) { list in listRow(list) }
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
        .onAppear { localSelection = selectedListIDs }
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
        let isSelected = localSelection.contains(list.id)
        return Button {
            if list.isAggregateVocabulary {
                localSelection = isSelected ? [] : [list.id]
            } else {
                localSelection.remove(VocabularyListStore.allCustomVocabularyListID)
                if isSelected {
                    localSelection.remove(list.id)
                } else {
                    // App-weites 5er-Limit für Mehrfachauswahl
                    guard localSelection.count < AppLayout.maxSelectableLists else { return }
                    localSelection.insert(list.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(list.items.count) Einträge")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? style.accent : AppTheme.Colors.textDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .appCardBackground(style, intensity: isSelected ? 0.22 : 0.05, cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Single-category list picker sheet used by Training setup
struct TrainingCategoryListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let category: TrainingView.ListPickerCategory
    let style: AppSectionStyle
    let lists: [VocabularyList]
    let selectedListIDs: Set<UUID>
    let onSelectionChanged: (Set<UUID>) -> Void

    @State private var localSelection: Set<UUID> = []

    private var sheetTitle: String {
        switch category {
        case .topic: return "Nach Themen"
        case .level: return "Nach Niveau"
        case .own: return "Eigene Listen"
        case .all: return "Ganzes Wörterbuch"
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: sheetTitle,
                trailingTitle: "Fertig",
                leadingTint: style.accent,
                trailingTint: style.accent,
                onLeading: { dismiss() },
                onTrailing: {
                    onSelectionChanged(localSelection)
                    dismiss()
                }
            )

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(lists) { list in
                        categoryListRow(list)
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
        .onAppear { localSelection = selectedListIDs }
    }

    private func categoryListRow(_ list: VocabularyList) -> some View {
        let isSelected = localSelection.contains(list.id)
        return Button {
            if list.isAggregateVocabulary {
                localSelection = isSelected ? [] : [list.id]
            } else {
                localSelection.remove(VocabularyListStore.allCustomVocabularyListID)
                if isSelected {
                    localSelection.remove(list.id)
                } else {
                    // App-weites 5er-Limit für Mehrfachauswahl
                    guard localSelection.count < AppLayout.maxSelectableLists else { return }
                    localSelection.insert(list.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(list.items.count) Einträge")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isSelected ? style.accent : AppTheme.Colors.textDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .appCardBackground(style, intensity: isSelected ? 0.22 : 0.05, cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
