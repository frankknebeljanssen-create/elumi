import SwiftUI

/// **Globaler Listen-Picker** (Phase 1, 2026-05-04 — vorher
/// `ChainListSelectionSheet`).
///
/// Wiederverwendbarer Listen-Auswahl-Sheet für alle Module
/// (Setup-Modal, Quiz, Karteikarten, Training, Akzente, Word Runner …).
/// Schreibt direkt in die **globale Listen-Auswahl**
/// (`appGlobalSelectedListIDsKey`) via
/// `VocabularyListSelectionResolver.setGlobalSelectedListIDs(...)`
/// und in den globalen `appLernjahrMaxKey` für hierarchische Listen.
///
/// **Toggle-State (R11)**: das Sheet ignoriert
/// `appUseGlobalListSelectionKey` bewusst. Begründung: das ganze
/// System läuft auf Cross-Module-Pool, das ist im Code-Modell genau
/// die globale Auswahl. Wenn der User in Settings den Toggle
/// ausgeschaltet hat, schreibt das Sheet trotzdem in die globale
/// Auswahl — der Side-Effect ist transparent (über Settings sichtbar)
/// und nicht destruktiv für die Per-Modul-Auswahl.
///
/// **Mode-Param `singleSelect`**: bei `true` ersetzt jeder Tap die
/// aktuelle Selection (max ein Eintrag), bei `false` Multi-Select-
/// Toggle. Single-Select-Modus für Akzente und Word Runner.
///
/// **Mode-Param `filter`**: optionaler Pre-Filter auf `allLists`,
/// damit modus-spezifische Subsets möglich sind (z.B. „nur Listen
/// mit Nomen-Items"). Default `nil` = alle Listen.
///
/// **Mode-Param `categoryHeaders`**: `true` zeigt den Section-Header
/// und den Cross-Module-Erklärungstext am Ende. `false` rendert nur
/// die Liste — passend für Modul-Setup-Screens, wo der Kontext
/// schon klar ist.
struct GlobalListPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Alle verfügbaren Listen (built-in + custom). Quelle:
    /// `VocabularyListStore.allLists`.
    let allLists: [VocabularyList]

    /// Initial-Selection beim Sheet-Open. Bei „Abbrechen" gewinnt
    /// dieser Wert; bei „Fertig" wird der lokale `selectedIDs`-State
    /// persistiert.
    let initialSelection: Set<UUID>

    /// Wird nach erfolgreichem „Fertig"-Tap aufgerufen. Parent kann
    /// damit die UI-Card im Setup-Modal aktualisieren ohne separaten
    /// Resolver-Read.
    let onCommit: (Set<UUID>) -> Void

    /// **Phase 1 (2026-05-04)** — Single-Select-Mode für Akzente /
    /// Word Runner. Default `false` = Multi-Select wie bisher.
    var singleSelect: Bool = false

    /// **Phase 1 (2026-05-04)** — optionaler Pre-Filter auf `allLists`.
    /// Wenn gesetzt, wird `allLists` durch den Filter laufen, bevor die
    /// Sortierung passiert. Default `nil` = keine Filterung.
    var filter: ((VocabularyList) -> Bool)? = nil

    /// **Phase 1 (2026-05-04)** — Zeigt Section-Header und Cross-Module-
    /// Erklärungstext. `false` für Modul-Setup-Screens, wo der Kontext
    /// schon klar ist. Default `true` (Setup-Modal-Verhalten).
    var categoryHeaders: Bool = true

    /// Footer-Chrome-Inputs. Pattern aus `ListPickerSheet`. Default
    /// `nil`, damit existing Call-Sites ohne Anpassung funktionieren.
    var feedbackPlayer: FeedbackPlayer? = nil
    var onHome: (() -> Void)? = nil
    /// Settings-Action — analog `ListPickerSheet`. Default nil → Footer-
    /// Button ausgegraut. Wird aus `UnifiedListCategoryPicker` durchgereicht.
    var onSettings: (() -> Void)? = nil
    /// Akzentfarbe für Auswahl-Highlights, „Fertig"-Button und Selection-
    /// Border. Default `primary` für Backward-Kompatibilität. Aufrufer
    /// reichen Modul-Akzent durch (z. B. `accent` in `UnifiedListCategoryPicker`).
    var accent: Color = AppTheme.Colors.primary
    /// Summary-Banner „Tipp eine Liste an" analog `ListPickerSheet`.
    /// Default `true`. `false` für den ChatView-Inline-Kontext, wo der
    /// Banner keinen Sheet-Rahmen hat.
    var showBanner: Bool = true

    /// Lokaler Selection-State während die Sheet sichtbar ist. Wird
    /// in `onAppear` aus `initialSelection` gefüllt.
    @State private var selectedIDs: Set<UUID> = []

    /// Lokaler Mirror der globalen `lernjahrMax`-Einstellung. 0 = alle
    /// Lernjahre, 1...5 = Y_1…Y_n cumulative. Wird in `onAppear` aus
    /// `VocabularyListSelectionResolver.currentLernjahrMax()` gefüllt
    /// (nil → 0) und beim „Fertig"-Tap persistiert.
    @State private var localLernjahrMax: Int = 0

    /// Welche hierarchischen Listen sind aktuell expanded (UI-only,
    /// nicht persistiert). Default geöffnet bei genau einem
    /// hierarchischen Eintrag (V1: Grundwortschatz A1) für bessere
    /// Discoverability — der User sieht direkt die Y1-Y5-Children.
    @State private var expandedListIDs: Set<UUID> = []

    private var sortedLists: [VocabularyList] {
        // Filter zuerst, dann sortieren.
        let filtered = filter.map { allLists.filter($0) } ?? allLists
        // Sort: zuerst Built-In nach Name, dann Custom nach Name.
        // Hierarchische Listen (cumulativeChildren) bekommen ein leichtes
        // Hochsortieren INNERHALB der Built-In-Group, damit die
        // Lernjahr-Auswahl prominent oben steht.
        let builtIn = filtered
            .filter { $0.isBuiltIn }
            .sorted { lhs, rhs in
                if lhs.cumulativeChildren != rhs.cumulativeChildren {
                    return lhs.cumulativeChildren && !rhs.cumulativeChildren
                }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
        let custom = filtered
            .filter { !$0.isBuiltIn }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return builtIn + custom
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showBanner {
                bannerView
            }
            scrollContent
        }
        .animation(.easeInOut(duration: 0.18), value: selectedIDs.isEmpty)
        .background(AppTheme.Colors.background.ignoresSafeArea())
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
                .dismissingFooterActions(dismiss)
            }
        }
        .onAppear {
            selectedIDs = initialSelection
            localLernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax() ?? 0
            // Auto-Expand für die einzige (V1) hierarchische Liste,
            // damit der User die Lernjahr-Auswahl direkt sieht.
            for list in sortedLists where list.cumulativeChildren && list.children != nil {
                expandedListIDs.insert(list.id)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Button("Zurück") {
                dismiss()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)

            Spacer(minLength: 0)

            Text("Lernliste wählen")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer(minLength: 0)

            Button {
                VocabularyListSelectionResolver.setGlobalSelectedListIDs(selectedIDs)
                LearningGoalStore.shared.noteManualListSelection(selectedIDs)
                UserDefaults.standard.set(localLernjahrMax, forKey: appLernjahrMaxKey)
                #if DEBUG
                appDebugLog("📋 [Lernjahr] persist max=\(localLernjahrMax)")
                #endif
                onCommit(selectedIDs)
                dismiss()
            } label: {
                Text("Fertig")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(selectedIDs.isEmpty ? AppTheme.Colors.textSecondary : accent)
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(AppTheme.Colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                .frame(height: 0.5)
        }
    }

    // MARK: - Banner (analog ListPickerSheet)

    /// Runde Mint-Card analog `ListPickerSheet` — statischer Text
    /// „Tipp eine Liste an" (kein dynamischer State, exakt Bild-2-Stil).
    private var bannerView: some View {
        Text("Wähle eine oder mehrere Lernlisten")
            .font(AppTheme.Typography.cardTitle)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.success.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppTheme.Spacing.md)
    }

    // MARK: - Liste

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if categoryHeaders {
                    Text("Lernlisten für Training")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }

                if sortedLists.isEmpty {
                    Text("Keine Lernlisten verfügbar.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                } else {
                    // **2026-05-06 Empty-Selection-Hint** — User-Spec
                    // (Punkt 3): Wenn der User den Picker mit leerer
                    // Auswahl öffnet, soll ein zentrierter, prominenter
                    // Hinweis „Wähle mindestens eine Liste" sichtbar sein.
                    // Verschwindet automatisch sobald die erste Liste
                    // selektiert wird (`selectedIDs.isEmpty == false`).
                    // Im Single-Select-Modus (z. B. Akzente) blenden wir
                    // den Hint aus — dort ist die Auswahl per Natur des
                    // Modus immer eindeutig und kein „leerer Zustand"
                    // vorgesehen.
                    if !singleSelect && selectedIDs.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(accent)
                            Text("Wähle mindestens eine Lernliste")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(accent.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(accent.opacity(0.35), lineWidth: 1)
                        )
                        .padding(.horizontal, 14)
                        .padding(.top, categoryHeaders ? 8 : 14)
                        .padding(.bottom, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(spacing: 6) {
                        if !sectionOwnLists.isEmpty {
                            sectionHeader("📝 Meine Listen")
                            ForEach(sectionOwnLists) { list in row(for: list) }
                        }
                        if !sectionLevelLists.isEmpty {
                            sectionHeader("📚 Wortschatz nach Lernstand")
                            ForEach(sectionLevelLists) { list in row(for: list) }
                        }
                        if !sectionTopicLists.isEmpty {
                            sectionHeader("🏷️ Themen")
                            ForEach(sectionTopicLists) { list in row(for: list) }
                        }
                        if !sectionDictionaryLists.isEmpty {
                            Spacer().frame(height: 12)
                            sectionHeader("📖 Komplettes Wörterbuch")
                            ForEach(sectionDictionaryLists) { list in row(for: list) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, (selectedIDs.isEmpty && !singleSelect) ? 0 : (categoryHeaders ? 0 : 14))
                }

                if categoryHeaders {
                    // **2026-06-09** — Der Lernjahr-Zusatz entfällt,
                    // solange die Auswahl per Flag versteckt ist.
                    Text(
                        FeatureFlags.learningYearSelectionEnabled
                        ? "Die gewählten Lernlisten werden in allen Trainingsmodulen (Karteikarten, Quiz, Word Runner, Training) als gemeinsamer Pool verwendet — analog zur globalen Lernlisten-Auswahl in den Einstellungen. Bei Lernlisten mit Lernjahr-Aufteilung (z. B. Grundwortschatz A1) gilt das gewählte Lernjahr global für alle hierarchischen Lernlisten."
                        : "Die gewählten Lernlisten werden in allen Trainingsmodulen (Karteikarten, Quiz, Word Runner, Training) als gemeinsamer Pool verwendet — analog zur globalen Lernlisten-Auswahl in den Einstellungen."
                    )
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                } else {
                    // Bottom-Padding ohne Erklärungstext, damit die letzte
                    // Row nicht direkt am Sheet-Rand klebt.
                    Spacer().frame(height: 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Section-Grouping (analog ListPickerSheet)

    /// Trennlinie + fettgedruckter Sektionsname — exakt wie `ListPickerSheet`.
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

    /// Eigene (nicht built-in) Listen + Aggregate-Vokabular, ohne Wörterbuch.
    private var sectionOwnLists: [VocabularyList] {
        sortedLists.filter {
            (!$0.isBuiltIn || $0.isAggregateVocabulary)
            && $0.id != VocabularyListStore.dictionaryListID
        }
    }

    /// Built-in Niveau-Listen (A1, A2 …).
    private var sectionLevelLists: [VocabularyList] {
        sortedLists.filter { $0.collectionPreset == .standardLevel }
    }

    /// Built-in Themen-Listen.
    private var sectionTopicLists: [VocabularyList] {
        sortedLists.filter { $0.collectionPreset == .standardTopic }
    }

    /// Wörterbuch-Liste + alle sonstigen built-in Listen ohne Level/Topic-Preset.
    private var sectionDictionaryLists: [VocabularyList] {
        sortedLists.filter {
            $0.id == VocabularyListStore.dictionaryListID
            || ($0.isBuiltIn && !$0.isAggregateVocabulary
                && $0.collectionPreset != .standardLevel
                && $0.collectionPreset != .standardTopic)
        }
    }

    // MARK: - Row-Branching

    /// Routet zwischen flacher und expandable Hierarchie-Row. Listen
    /// mit `cumulativeChildren=true` und nicht-leerer `children`-Liste
    /// bekommen das expandable Pattern aus `ListPickerSheet`.
    ///
    /// **2026-06-09** — Bei deaktivierter Lernjahr-Auswahl
    /// (`FeatureFlags.learningYearSelectionEnabled == false`) fällt auch
    /// die hierarchische Liste auf `flatRow` zurück: der Grundwortschatz
    /// ist dann nur als Ganzes an-/abwählbar, ohne aufklappbare
    /// Lernjahr-Children. `expandableLernjahrRow` bleibt unangetastet
    /// im Code und greift wieder, sobald das Flag auf `true` geht.
    @ViewBuilder
    private func row(for list: VocabularyList) -> some View {
        if FeatureFlags.learningYearSelectionEnabled,
           list.cumulativeChildren,
           let children = list.children,
           !children.isEmpty {
            expandableLernjahrRow(list, children: children)
        } else {
            flatRow(for: list)
        }
    }

    // MARK: - Flat Row

    private func flatRow(for list: VocabularyList) -> some View {
        let isSelected = selectedIDs.contains(list.id)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSelected ? accent : AppTheme.Colors.textSecondary.opacity(0.55))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(list.items.count) Einträge")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            countCapsule(list.items.count)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isSelected: isSelected))
        .overlay(rowBorder(isSelected: isSelected))
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(for: list.id)
        }
    }

    // MARK: - Expandable Lernjahr-Row

    /// Parent-Row für eine hierarchische Liste mit Lernjahr-Children.
    private func expandableLernjahrRow(
        _ list: VocabularyList,
        children: [VocabularyList]
    ) -> some View {
        let isSelected = selectedIDs.contains(list.id)
        let isExpanded = expandedListIDs.contains(list.id)

        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : AppTheme.Colors.textSecondary.opacity(0.55))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)

                        Text(parentSublabel(for: list, children: children, max: localLernjahrMax))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(for: list.id)
                }

                countCapsule(cumulativeItemCount(localLernjahrMax, children: children))
                    .padding(.trailing, 6)

                Button {
                    toggleExpanded(list.id)
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(rowBackground(isSelected: isSelected))
            .overlay(rowBorder(isSelected: isSelected))

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { idx, child in
                        let year = idx + 1
                        lernjahrChildRow(
                            child: child,
                            year: year,
                            parentList: list,
                            max: localLernjahrMax
                        )
                    }
                }
                .padding(.leading, 28)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
        }
    }

    /// Eine Y_n-Children-Row.
    private func lernjahrChildRow(
        child: VocabularyList,
        year: Int,
        parentList: VocabularyList,
        max: Int
    ) -> some View {
        let active = isActive(year: year, max: max)
        let auto = isAuto(year: year, max: max)
        let count = child.items.count
        let isEmpty = count == 0

        return HStack(spacing: 10) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(active ? accent : AppTheme.Colors.textSecondary.opacity(0.45))

            Text(child.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
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

            Text(isEmpty ? "—" : "\(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(active ? accent.opacity(0.06) : AppTheme.Colors.surface.opacity(0.6))
        )
        .opacity(isEmpty ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEmpty else { return }
            handleChildTap(year: year, parent: parentList)
        }
    }

    // MARK: - Helpers

    /// Multi-Select: toggle zwischen in/out der Selection.
    /// Single-Select: Replace-Selection (bei selektierter Liste = clear).
    private func toggleSelection(for id: UUID) {
        if singleSelect {
            if selectedIDs.contains(id) {
                selectedIDs.removeAll()
            } else {
                selectedIDs = [id]
            }
        } else {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedListIDs.contains(id) {
            expandedListIDs.remove(id)
        } else {
            expandedListIDs.insert(id)
        }
    }

    /// Children-Tap-Handler. Cumulative-up-Semantik: jeder Tap auf Y_n
    /// setzt `localLernjahrMax = n`. Auto-Add der Parent-Liste in
    /// Multi-Select; Replace-Selection in Single-Select.
    private func handleChildTap(year: Int, parent: VocabularyList) {
        if singleSelect {
            selectedIDs = [parent.id]
        } else if !selectedIDs.contains(parent.id) {
            selectedIDs.insert(parent.id)
        }
        localLernjahrMax = year
    }

    /// Ist Y_n überhaupt aktiv (auto oder explicit)?
    private func isActive(year: Int, max: Int) -> Bool {
        max == 0 ? true : year <= max
    }

    /// Ist Y_n auto-aktiv (= aktiv weil Y_max darüber liegt)?
    private func isAuto(year: Int, max: Int) -> Bool {
        max == 0 ? false : (year < max)
    }

    /// Sublabel des Parents — analog `ListPickerSheet`: zeigt immer die
    /// Kartenanzahl, damit der User sofort sieht was er aktiviert.
    private func parentSublabel(for list: VocabularyList, children: [VocabularyList], max: Int) -> String {
        if max == 0 {
            return "alle Lernjahre · \(list.items.count) Karten"
        }
        let cnt = cumulativeItemCount(max, children: children)
        return "\(max) von \(children.count) · \(cnt) Karten"
    }

    /// Item-Count über alle bis Y_max eingeschlossenen Children.
    private func cumulativeItemCount(_ max: Int, children: [VocabularyList]) -> Int {
        let active = max == 0 ? children.count : Swift.min(max, children.count)
        return children.prefix(active).reduce(0) { $0 + $1.items.count }
    }

    private func countCapsule(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(AppTheme.Colors.textSecondary.opacity(0.14))
            )
    }

    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? accent.opacity(0.10) : AppTheme.Colors.surface)
    }

    private func rowBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                isSelected ? accent.opacity(0.40) : AppTheme.Colors.textSecondary.opacity(0.12),
                lineWidth: 1
            )
    }
}
