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
    /// **List-Merge (2026-05-21)** — optionaler Multi-Select-Merge-Einstieg.
    /// Nur der „Meine Listen"(.own)-Caller übergibt ihn → der Button erscheint
    /// ausschließlich dort (andere Filter bleiben unverändert, default nil).
    var onStartMerge: (() -> Void)? = nil
    /// **Gesamtzahl-Anzeige (2026-05-21)** — wenn true, wird pro Liste die
    /// Gesamt-Vokabelzahl VOR der Wortart-Aufstellung gezeigt. Nur der
    /// „Meine Listen"(.own)-Caller setzt true (andere Filter: default false).
    var showsTotalCount: Bool = false
    /// Optionaler Footer (Standard-AppBottomBar). Nur anzeigen wenn feedbackPlayer + onHome geliefert.
    var feedbackPlayer: FeedbackPlayer? = nil
    var onHome: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil

    // ─── Stufe 1 V1a (2026-04-28) — Lernjahr-Hierarchie ───
    //
    // Cumulative Lernjahr-Range. 0 = alle Lernjahre, 1...5 = Y_1…Y_n.
    // Wird vom Caller via @AppStorage(appLernjahrMaxKey) gebunden.
    var lernjahrMax: Int = 1
    var onLernjahrMaxChange: (Int) -> Void = { _ in }

    @State private var listPendingDeletion: VocabularyList?
    @State private var listPendingMerge: VocabularyList?
    @State private var localSelectedID: UUID?
    /// Lokaler Mirror — wird auf „Fertig" via `onLernjahrMaxChange`
    /// nach außen gepushed.
    @State private var localLernjahrMax: Int = 1
    /// Welche List-IDs sind aktuell aufgeklappt (UI-only, nicht persistiert).
    @State private var expandedListIDs: Set<UUID> = []

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
        // **Naming-Sweep 2026-05-06** — „Keine Liste ausgewählt" →
        // „Tipp eine Liste an" (kindgerecht-aktiv: zeigt eine
        // Aktion statt eines passiven Status).
        return "Wähle eine oder mehrere Lernlisten"
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            AppSheetHeader(
                title: "Lernliste wählen",
                trailingTitle: "Fertig",
                leadingTint: style.accent,
                trailingTint: style.accent,
                onLeading: { dismiss() },
                onTrailing: {
                    onSelect(currentSelectedID)
                    onLernjahrMaxChange(localLernjahrMax)
                    #if DEBUG
                    appDebugLog("📋 [Lernjahr] persist max=\(localLernjahrMax) (ListPickerSheet)")
                    #endif
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

            // **List-Merge (2026-05-21)** — Merge-Einstieg über der Liste,
            // nur sichtbar wenn der Caller `onStartMerge` liefert (= „Eigene
            // Listen") UND ≥ 2 Listen vorhanden sind. Dezenter Full-Width-Button.
            if let onStartMerge, lists.count >= 2 {
                Button(action: onStartMerge) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Lernlisten zusammenführen")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(AppSecondaryButtonStyle())
            }

            ScrollView {
                VStack(spacing: 6) {
                    if !ownLists.isEmpty {
                        sectionHeader("📝 Meine Listen")
                        ForEach(ownLists) { list in listRow(list) }
                    }

                    if !levelLists.isEmpty {
                        sectionHeader("📚 Wortschatz nach Lernstand")
                        ForEach(levelLists) { list in listRow(list) }
                    }

                    if !topicLists.isEmpty {
                        // **Naming-Sweep 2026-05-06** — „Wortschatz
                        // nach Thema" → „THEMEN" (kürzer, kompakter
                        // Section-Header).
                        sectionHeader("🏷️ Themen")
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
                // **2026-05-04 Footer-Bridge im Sheet-Kontext** — wraps
                // die Environment-basierten Footer-Actions (Elumi,
                // Wörterbuch, …) so dass das Sheet beim Tap erst
                // dismisst und die parent-Navigation sichtbar feuert.
                .dismissingFooterActions(dismiss)
            }
        }
        .onAppear {
            localSelectedID = selectedListID
            localLernjahrMax = lernjahrMax
            // Auto-expand: wenn die ausgewählte Liste hierarchisch ist
            // UND nicht im Default-„alle"-State (max=0), dann öffnen
            // wir sie direkt — der User soll seine Sub-Auswahl sofort
            // sehen.
            if let list = lists.first(where: { $0.id == selectedListID }),
               list.children != nil, list.cumulativeChildren,
               lernjahrMax != 0 {
                expandedListIDs.insert(list.id)
            }
        }
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
                            .appCardBackground(style, intensity: AppTheme.CardIntensity.whisper, cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if targets.isEmpty {
                Text("Keine andere eigene Lernliste vorhanden.")
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

    /// Branch-Punkt: hierarchische Listen mit cumulativeChildren bekommen
    /// das expandable Layout (Stufe 1 V1a). Alle anderen rendern wie
    /// bisher als flache Row.
    ///
    /// **2026-06-09** — Bei deaktivierter Lernjahr-Auswahl
    /// (`FeatureFlags.learningYearSelectionEnabled == false`) rendert
    /// auch die hierarchische Liste als `regularListRow`: nur als Ganzes
    /// wählbar, keine Lernjahr-Children. `expandableLernjahrListRow`
    /// bleibt im Code und greift wieder, sobald das Flag `true` ist.
    @ViewBuilder
    private func listRow(_ list: VocabularyList) -> some View {
        if FeatureFlags.learningYearSelectionEnabled,
           let children = list.children,
           list.cumulativeChildren {
            expandableLernjahrListRow(list, children: children)
        } else {
            regularListRow(list)
        }
    }

    private func regularListRow(_ list: VocabularyList) -> some View {
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
                        wordClassBreakdownText(for: list, showsTotalCount: showsTotalCount)
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
            .appCardBackground(style, intensity: list.id == currentSelectedID ? AppTheme.CardIntensity.selected : AppTheme.CardIntensity.whisper, cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(list.id == currentSelectedID ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expandable Lernjahr-Row (Stufe 1 V1a, 2026-04-28)

    /// Effektive Y-Anzahl, die als „aktiv" zählt (für Halb-Check-
    /// Berechnung etc.). max=0 = alle 5, sonst max=n.
    private func effectiveActiveYearCount(_ max: Int, totalChildren: Int) -> Int {
        max == 0 ? totalChildren : Swift.min(max, totalChildren)
    }

    /// Item-Count über alle bis Y_max eingeschlossenen Children.
    private func cumulativeItemCount(_ max: Int, children: [VocabularyList]) -> Int {
        let active = effectiveActiveYearCount(max, totalChildren: children.count)
        return children.prefix(active).reduce(0) { $0 + $1.items.count }
    }

    /// Sublabel des Parents — entweder „alle Lernjahre · X Karten"
    /// oder „N von 5 · X Karten".
    private func parentSublabel(for list: VocabularyList, children: [VocabularyList], max: Int) -> String {
        if max == 0 {
            return "alle Lernjahre · \(list.items.count) Karten"
        }
        let cnt = cumulativeItemCount(max, children: children)
        return "\(max) von \(children.count) · \(cnt) Karten"
    }

    /// Halb-Check, voller Check, oder leer — basierend auf max.
    private func parentSelectionIcon(_ max: Int, isSelected: Bool, totalChildren: Int) -> String {
        guard isSelected else { return "circle" }
        if max == 0 || max >= totalChildren {
            return "checkmark.circle.fill"
        }
        return "minus.circle.fill"
    }

    /// Parent-Tap-Handler. Toggelt „alles ↔ Y1" für eine bereits
    /// ausgewählte Liste. Auf nicht-ausgewählter Liste: einfach
    /// auswählen (max bleibt was es war).
    private func handleParentTap(for list: VocabularyList) {
        if currentSelectedID != list.id {
            // Nicht-aktive Liste → aktivieren, max bleibt unverändert.
            localSelectedID = list.id
            return
        }
        // Aktive Liste → Toggle alles ↔ Y1. „Nichts" ist in single-
        // select Picker nicht sinnvoll erreichbar.
        if localLernjahrMax == 0 {
            localLernjahrMax = 1
        } else {
            localLernjahrMax = 0
        }
    }

    /// Child-Tap-Handler.
    ///
    /// **2026-05-04 (Punkt 2 Fix)** — siehe Doc in
    /// `ChainListSelectionSheet.handleChildTap`. Semantik vereinfacht
    /// auf cumulative-up only: jeder Tap auf Y_n setzt
    /// `localLernjahrMax = n`. Tap-Pattern „Y1 → Y2 → Y3" hatte vorher
    /// den max-Wert nach unten ratschen lassen. Mit cumulative-up
    /// matcht das Verhalten dem User-Mental-Model: Tap Y3 = Y1+Y2+Y3
    /// aktiv. Wer Y1 zurück will, tippt Y1 → max=1.
    private func handleChildTap(year: Int, list: VocabularyList) {
        if currentSelectedID != list.id {
            localSelectedID = list.id
        }
        localLernjahrMax = year
    }

    /// Ist Y_n explicit gewählt (= der zuletzt vom User getippte)?
    private func isExplicit(year: Int, max: Int) -> Bool {
        max != 0 && year == max
    }

    /// Ist Y_n auto-aktiv (= aktiv weil Y_max darüber liegt)?
    private func isAuto(year: Int, max: Int) -> Bool {
        max == 0 ? false : (year < max)
    }

    /// Ist Y_n überhaupt aktiv (auto oder explicit)?
    private func isActive(year: Int, max: Int) -> Bool {
        max == 0 ? true : year <= max
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedListIDs.contains(id) {
            expandedListIDs.remove(id)
        } else {
            expandedListIDs.insert(id)
        }
    }

    private func expandableLernjahrListRow(
        _ list: VocabularyList,
        children: [VocabularyList]
    ) -> some View {
        let isSelected = (currentSelectedID == list.id)
        let isExpanded = expandedListIDs.contains(list.id)
        let activeMax = isSelected ? localLernjahrMax : 0
        let totalChildren = children.count
        let selectionIcon = parentSelectionIcon(
            activeMax,
            isSelected: isSelected,
            totalChildren: totalChildren
        )
        let sublabel = parentSublabel(for: list, children: children, max: activeMax)

        return VStack(spacing: 6) {
            // ── Parent-Row ──
            HStack(spacing: 12) {
                // Tap-Bereich (außer Chevron) — toggelt Parent.
                Button {
                    handleParentTap(for: list)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.name)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(sublabel)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: selectionIcon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(isSelected ? style.accent : AppTheme.Colors.textDisabled)
                    }
                }
                .buttonStyle(.plain)

                // Chevron — separater Tap, ändert keine Auswahl.
                Button {
                    toggleExpanded(list.id)
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .appCardBackground(
                style,
                intensity: isSelected
                    ? AppTheme.CardIntensity.selected
                    : AppTheme.CardIntensity.whisper,
                cornerRadius: 14
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )

            // ── Children (nur wenn expanded) ──
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { idx, child in
                        let year = idx + 1
                        lernjahrChildRow(child: child, year: year, parentList: list, max: activeMax)
                    }
                }
                .padding(.leading, 22)
                .padding(.top, 2)
            }
        }
    }

    private func lernjahrChildRow(
        child: VocabularyList,
        year: Int,
        parentList: VocabularyList,
        max: Int
    ) -> some View {
        let active = isActive(year: year, max: max)
        let auto = isAuto(year: year, max: max)
        let count = child.items.count

        return Button {
            handleChildTap(year: year, list: parentList)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(active ? style.accent : AppTheme.Colors.textDisabled)

                Text(child.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                if auto {
                    Text("auto")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(AppTheme.Colors.textSecondary.opacity(0.18))
                        )
                }

                Spacer(minLength: 0)

                // **Punkt 3 Fix (2026-05-04)** — leere Lernjahre als
                // „—" statt „0" rendern. Klar kommunizierter „keine
                // Vokabeln vorhanden"-Status, statt einer 0 die wie
                // ein potentiell anwählbarer Counter wirkt. Disabled-
                // State + Opacity-Fade bleibt unverändert.
                Text(count == 0 ? "—" : "\(count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(count == 0 ? 0.5 : 1.0)
        .disabled(count == 0)
    }

    private func wordClassBreakdownText(for list: VocabularyList, showsTotalCount: Bool = false) -> some View {
        // Zentraler Aggregator — eine Quelle für Listen-Statistik überall in der App.
        let stats = FrenchListStatisticsAggregator.cachedStatistics(for: list.items)
        let breakdown = FrenchLemmaFormatter.twoLineBreakdown(from: stats)
        // **Gesamtzahl (2026-05-21, nur .own)** — „X Vokabel(n)" VOR die
        // Wortart-Aufstellung stellen, in dieselbe erste Zeile, „·"-getrennt.
        let total = list.items.count
        let totalText = "\(total) \(total == 1 ? "Vokabel" : "Vokabeln")"
        let firstLine: String = {
            guard showsTotalCount else { return breakdown.line1 }
            return breakdown.line1.isEmpty ? totalText : "\(totalText) · \(breakdown.line1)"
        }()
        return VStack(alignment: .leading, spacing: 1) {
            if firstLine.isEmpty && breakdown.line2.isEmpty {
                Text("\(total) Eintr\u{00E4}ge")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            } else {
                if !firstLine.isEmpty {
                    Text(firstLine)
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

