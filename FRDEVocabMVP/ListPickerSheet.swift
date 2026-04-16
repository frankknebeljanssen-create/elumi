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
    var onMerge: ((VocabularyList, VocabularyList) -> Void)? = nil // (source, target)
    /// Optionaler Footer (Standard-AppBottomBar). Nur anzeigen wenn feedbackPlayer + onHome geliefert.
    var feedbackPlayer: FeedbackPlayer? = nil
    var onHome: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil

    @State private var listPendingDeletion: VocabularyList?
    @State private var listPendingMerge: VocabularyList?
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

                    // „Komplettes Wörterbuch" nur zeigen, wenn es solche Listen
                    // im aktuellen Filter-Ausschnitt überhaupt gibt.
                    if !dictionaryLists.isEmpty {
                        Spacer().frame(height: 12)
                        sectionHeader("📖 Komplettes Wörterbuch")
                        ForEach(dictionaryLists) { list in listRow(list) }
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
        // Footer als korrekter Local-Chrome-BottomBar (mit Safe-Area + Surface-Modifier).
        // Nur sichtbar, wenn Aufrufer feedbackPlayer + onHome injiziert.
        .appLocalChrome(enabled: feedbackPlayer != nil && onHome != nil) {
            EmptyView()
        } bottomBar: {
            if let player = feedbackPlayer, let homeAction = onHome {
                AppBottomBar(
                    feedbackPlayer: player,
                    onHome: { dismiss(); homeAction() },
                    onFavorite: nil,
                    onScan: nil,
                    onSettings: onSettings.map { settingsAction in
                        { dismiss(); settingsAction() }
                    }
                )
            }
        }
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
        .sheet(item: $listPendingMerge) { sourceList in
            mergeTargetPicker(source: sourceList)
        }
    }

    private func mergeTargetPicker(source: VocabularyList) -> some View {
        let targets = lists.filter { !$0.isBuiltIn && $0.id != source.id && !$0.isAggregateVocabulary }

        return VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Zusammenf\u{00FC}hren",
                trailingTitle: "",
                leadingTint: style.accent,
                trailingTint: style.accent,
                onLeading: { listPendingMerge = nil },
                onTrailing: {}
            )

            Text("\(source.name) zusammenf\u{00FC}hren mit:")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(targets) { target in
                        Button {
                            onMerge?(source, target)
                            listPendingMerge = nil
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.name)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                    Text("\(target.items.count) Eintr\u{00E4}ge")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(style.accent)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .appCardBackground(style, intensity: 0.05, cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if targets.isEmpty {
                Text("Keine andere eigene Liste vorhanden.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(AppLayout.screenPadding)
        .appScreenBackground(style)
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
        VStack(spacing: 8) {
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(height: 1.5)
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func listRow(_ list: VocabularyList) -> some View {
        Button {
            localSelectedID = list.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(list.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if !list.isBuiltIn, onRename != nil {
                            Button {
                                onRename?(list)
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 18, weight: .semibold))
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
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(style.accent.opacity(0.7))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }

                    if onMerge != nil {
                        Button {
                            listPendingMerge = list
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(style.accent.opacity(0.7))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        listPendingDeletion = list
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.error.opacity(0.7))
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
            .appCardBackground(style, intensity: list.id == currentSelectedID ? 0.22 : 0.05, cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(list.id == currentSelectedID ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func wordClassBreakdownText(for list: VocabularyList) -> some View {
        // Zentraler Aggregator — eine Quelle für Listen-Statistik überall in der App.
        let stats = FrenchListStatisticsAggregator.cachedStatistics(for: list.items)
        let breakdown = FrenchLemmaFormatter.twoLineBreakdown(from: stats)
        return VStack(alignment: .leading, spacing: 1) {
            if breakdown.line1.isEmpty && breakdown.line2.isEmpty {
                Text("\(list.items.count) Eintr\u{00E4}ge")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                if !breakdown.line1.isEmpty {
                    Text(breakdown.line1)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                if !breakdown.line2.isEmpty {
                    Text(breakdown.line2)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }
}

