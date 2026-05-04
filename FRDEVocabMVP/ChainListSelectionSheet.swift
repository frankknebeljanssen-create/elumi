import SwiftUI

/// **Trainings-Chain — Listen-Auswahl-Sheet** (Stufe 1c, 2026-04-30,
/// Branch `feature/training-session-flow`).
///
/// Multi-Select-Sheet, in dem der User die Listen für den Trainings-
/// Chain im Elumi-Tab Setup-Modal wählt. Schreibt direkt in die
/// **globale Listen-Auswahl** (`appGlobalSelectedListIDsKey`) via
/// `VocabularyListSelectionResolver.setGlobalSelectedListIDs(...)`
/// und in den globalen `appLernjahrMaxKey` für hierarchische Listen.
///
/// **Toggle-State (R11)**: das Sheet ignoriert
/// `appUseGlobalListSelectionKey` bewusst. Begründung: die Chain
/// braucht einen Cross-Module-Pool, das ist im Code-Modell genau die
/// globale Auswahl. Wenn der User in Settings den Toggle ausgeschaltet
/// hat, schreibt das Sheet trotzdem in die globale Auswahl — der
/// Side-Effect ist transparent (über Settings sichtbar) und nicht
/// destruktiv für die Per-Modul-Auswahl.
///
/// **Listenquelle**: `listStore.allLists` — sowohl `customLists`
/// als auch Built-In-Listen (Niveau-Listen, Themen-Listen).
///
/// **UI-Pattern**: angelehnt an `ListPickerSheet` für Look-Konsistenz —
/// `ScrollView + VStack` statt `List`, weil iOS 26 List-Rows bei
/// Button-Wrapper aggressiv mit Accent-Tint überzieht. Multi-Select
/// über manuelle Toggle-Logik im Row-onTap.
///
/// **Lernjahr-Hierarchie** (Stufe 1c-Erweiterung): Listen mit
/// `cumulativeChildren=true` (V1: nur „Grundwortschatz A1") werden als
/// **expandable Rows** gerendert. Children Y1-Y5 erscheinen unter dem
/// Parent, Tap auf Y_n setzt den **globalen `lernjahrMax`** (wirkt
/// für ALLE hierarchischen Listen, nicht per-Liste). Multi-Select-
/// Toggle und Lernjahr-Auswahl sind voneinander getrennt: Tap auf
/// Parent-Row toggled die Selection (in/out), Tap auf Y_n in den
/// Children setzt den Lernjahr-Wert global.
///
/// **Auto-Add bei Children-Tap**: wenn der User auf Y_n einer NICHT
/// selektierten hierarchischen Liste tippt, wird die Liste auch in die
/// Selection aufgenommen — User-Mental-Model: „ich tappe Y3 bei
/// Grundwortschatz, also will ich den auch trainieren".
struct ChainListSelectionSheet: View {
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

    /// **Bug-Fix Footer-Layout (2026-05-04, Punkt 1)** — optionale
    /// Footer-Chrome-Inputs. Pattern aus `ListPickerSheet`. Default
    /// `nil`, damit existing Call-Sites ohne Anpassung funktionieren.
    var feedbackPlayer: FeedbackPlayer? = nil
    var onHome: (() -> Void)? = nil

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
        // Sort: zuerst Built-In nach Name, dann Custom nach Name.
        // Hierarchische Listen (cumulativeChildren) bekommen ein leichtes
        // Hochsortieren INNERHALB der Built-In-Group, damit die
        // Lernjahr-Auswahl prominent oben steht.
        let builtIn = allLists
            .filter { $0.isBuiltIn }
            .sorted { lhs, rhs in
                if lhs.cumulativeChildren != rhs.cumulativeChildren {
                    return lhs.cumulativeChildren && !rhs.cumulativeChildren
                }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
        let custom = allLists
            .filter { !$0.isBuiltIn }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        return builtIn + custom
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            scrollContent
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        // **Bug-Fix Footer-Layout (2026-05-04, Punkt 1)** — siehe
        // `ListSelectionSheet`. Wenn der Caller `feedbackPlayer + onHome`
        // mitliefert, behält der User den `AppBottomBar`-Footer auch
        // während der Listen-Auswahl-Sheet aktiv ist.
        .appLocalChrome(enabled: feedbackPlayer != nil && onHome != nil) {
            EmptyView()
        } bottomBar: {
            if let player = feedbackPlayer, let homeAction = onHome {
                AppBottomBar(
                    feedbackPlayer: player,
                    onHome: { dismiss(); homeAction() },
                    onFavorite: nil,
                    onScan: nil,
                    onSettings: nil
                )
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
            Button("Abbrechen") {
                dismiss()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer(minLength: 0)

            Text("Aktive Listen")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer(minLength: 0)

            Button {
                VocabularyListSelectionResolver.setGlobalSelectedListIDs(selectedIDs)
                // Lernjahr global persistieren — Pattern aus
                // ListsView+Presentations.swift, das beim
                // `onLernjahrMaxChange` `@AppStorage(appLernjahrMaxKey)`
                // schreibt. Hier äquivalent direkt auf UserDefaults.
                UserDefaults.standard.set(localLernjahrMax, forKey: appLernjahrMaxKey)
                onCommit(selectedIDs)
                dismiss()
            } label: {
                Text("Fertig")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(selectedIDs.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.primary)
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

    // MARK: - Liste

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Listen für Training")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                if sortedLists.isEmpty {
                    Text("Keine Listen verfügbar.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                } else {
                    VStack(spacing: 6) {
                        ForEach(sortedLists) { list in
                            row(for: list)
                        }
                    }
                    .padding(.horizontal, 14)
                }

                Text("Die gewählten Listen werden in allen Trainingsmodulen (Karteikarten, Quiz, Word Runner, Training) als gemeinsamer Pool verwendet — analog zur globalen Listen-Auswahl in den Einstellungen. Bei Listen mit Lernjahr-Aufteilung (z. B. Grundwortschatz A1) gilt das gewählte Lernjahr global für alle hierarchischen Listen.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Row-Branching

    /// Routet zwischen flacher und expandable Hierarchie-Row. Listen
    /// mit `cumulativeChildren=true` und nicht-leerer `children`-Liste
    /// bekommen das expandable Pattern aus `ListPickerSheet`
    /// (adaptiert für Multi-Select).
    @ViewBuilder
    private func row(for list: VocabularyList) -> some View {
        if list.cumulativeChildren, let children = list.children, !children.isEmpty {
            expandableLernjahrRow(list, children: children)
        } else {
            flatRow(for: list)
        }
    }

    // MARK: - Flat Row (Multi-Select)

    private func flatRow(for list: VocabularyList) -> some View {
        let isSelected = selectedIDs.contains(list.id)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary.opacity(0.55))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(list.isBuiltIn ? "Vorlage" : "Eigene Liste")
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
    /// Tap-Bereiche getrennt:
    ///   • Hauptzeile (links/Mitte) → Multi-Select-Toggle
    ///   • Chevron rechts → Expand/Collapse der Children
    private func expandableLernjahrRow(
        _ list: VocabularyList,
        children: [VocabularyList]
    ) -> some View {
        let isSelected = selectedIDs.contains(list.id)
        let isExpanded = expandedListIDs.contains(list.id)

        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                // Multi-Select-Toggle (Tap auf den linken Bereich).
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary.opacity(0.55))
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

                // Cumulative-Count rechts vom Sublabel.
                countCapsule(cumulativeItemCount(localLernjahrMax, children: children))
                    .padding(.trailing, 6)

                // Chevron — separater Tap-Bereich für Expand/Collapse.
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

    /// Eine Y_n-Children-Row. Tap setzt globalen `localLernjahrMax`
    /// und auto-add die Parent-Liste zur Selection (User-Mental-Model:
    /// „Y3 bei Grundwortschatz tappen heißt: Liste wählen + Y3 setzen").
    private func lernjahrChildRow(
        child: VocabularyList,
        year: Int,
        parentList: VocabularyList,
        max: Int
    ) -> some View {
        let active = isActive(year: year, max: max)
        let auto = isAuto(year: year, max: max)

        return HStack(spacing: 10) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(active ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary.opacity(0.45))

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

            Text("\(child.items.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(active ? AppTheme.Colors.primary.opacity(0.06) : AppTheme.Colors.surface.opacity(0.6))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleChildTap(year: year, parent: parentList)
        }
    }

    // MARK: - Helpers

    private func toggleSelection(for id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedListIDs.contains(id) {
            expandedListIDs.remove(id)
        } else {
            expandedListIDs.insert(id)
        }
    }

    /// Children-Tap-Handler. Adaptiert aus ListPickerSheet, aber für
    /// Multi-Select erweitert: tippt der User auf Y_n einer nicht-
    /// selektierten Liste, wird die Liste zur Selection hinzugefügt
    /// (Auto-Add). Tippt er Y_n auf einer selektierten Liste, wirkt
    /// nur die Lernjahr-Logic (kumulative Toggle mit α-Rule).
    private func handleChildTap(year: Int, parent: VocabularyList) {
        // Auto-Add: wenn die Liste noch nicht in der Selection ist,
        // dazu hinzufügen. So matcht das Tap-Verhalten den User-Erwartung
        // „ich tappe Y3 bei Grundwortschatz, also will ich den auch
        // trainieren".
        if !selectedIDs.contains(parent.id) {
            selectedIDs.insert(parent.id)
            localLernjahrMax = year
            return
        }

        let effective = localLernjahrMax == 0 ? 5 : localLernjahrMax
        if year > effective {
            // Y_n nicht aktiv → aktiviere Y_n + alle darunter.
            localLernjahrMax = year
        } else {
            // Y_n aktiv → deselektiere Y_n + alle darüber.
            // **α-Rule**: Y1 + max==1 → no-op (Y1 nicht abwählbar — sonst
            // hätte die Liste 0 Items und der User wäre verwirrt).
            if year == 1 && localLernjahrMax == 1 {
                return
            }
            localLernjahrMax = year - 1
        }
    }

    /// Ist Y_n überhaupt aktiv (auto oder explicit)?
    private func isActive(year: Int, max: Int) -> Bool {
        max == 0 ? true : year <= max
    }

    /// Ist Y_n auto-aktiv (= aktiv weil Y_max darüber liegt)?
    private func isAuto(year: Int, max: Int) -> Bool {
        max == 0 ? false : (year < max)
    }

    /// Sublabel des Parents — entweder „alle Lernjahre · X Karten"
    /// oder „N von 5 · X Karten". Source: ListPickerSheet-Pattern.
    private func parentSublabel(for list: VocabularyList, children: [VocabularyList], max: Int) -> String {
        if max == 0 {
            return "alle Lernjahre"
        }
        return "Y1–Y\(max) (cumulative)"
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
            .fill(isSelected ? AppTheme.Colors.primary.opacity(0.10) : AppTheme.Colors.surface)
    }

    private func rowBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                isSelected ? AppTheme.Colors.primary.opacity(0.40) : AppTheme.Colors.textSecondary.opacity(0.12),
                lineWidth: 1
            )
    }
}
