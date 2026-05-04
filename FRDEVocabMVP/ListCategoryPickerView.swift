import SwiftUI

/// **V1b (2026-04-28)** — file-private Honesty-Helper. Liefert die
/// effektive Item-Anzahl einer Liste unter Berücksichtigung des
/// aktuellen `lernjahrMax`. Wird von allen 3 Structs in dieser Datei
/// genutzt (`ListCategoryPickerView`, `ListSelectionSheet`,
/// `TrainingCategoryListSheet`). Hierarchische Listen liefern ihren
/// Y_max-Slice-Count; flache Listen ihre items.count unverändert.
fileprivate func effectiveCount(for list: VocabularyList) -> Int {
    VocabularyListSelectionResolver.effectiveItems(
        for: list,
        lernjahrMax: VocabularyListSelectionResolver.currentLernjahrMax()
    ).count
}

/// Shared list selection component used across Training, Flashcards, and Quiz setup screens.
/// Shows selected lists + "Liste auswählen" button that opens the category picker.
///
/// **Format-Angleichung (System-Master):**
/// Dieser Picker rendert visuell identisch zu den Custom-Cards in
/// `FlashcardsView+Layout.flashcardsListSelectionCard` und
/// `TrainingView+Layout.verbformsListSelectionCard` (Icon + Listen-Rows
/// mit „X Einträge" + Summary-Zeile + Stift-Pill). Frühere
/// POS-Breakdown-Zeile und die Spacer-Lines-Fixhöhen-Logik sind
/// entfallen — Quiz und Vokabeln sehen jetzt wie alle anderen Module aus.
struct ListCategoryPickerView: View {
    let availableLists: [VocabularyList]
    let selectedListIDs: Set<UUID>
    let accent: Color
    let style: AppSectionStyle
    let feedbackPlayer: FeedbackPlayer
    /// Kompatibilitäts-Param aus der Pre-Master-Zeit — aktuell nicht mehr
    /// gerendert (der Picker baut Titel + Summary selbst aus den gewählten
    /// Listen, einheitlich mit den Training-/Karteikarten-Cards).
    let summaryText: String
    var itemLabel: String = "Karten"
    let onSelectionChanged: (Set<UUID>) -> Void
    /// **Bug-Fix Footer-Layout (2026-05-04, Punkt 1)** — wird in das
    /// `ListSelectionSheet` durchgereicht, damit der AppBottomBar-Footer
    /// auch in der Listen-Kategorie-Sheet sichtbar bleibt. Default `nil`,
    /// damit existing Call-Sites ohne Anpassung weiterhin funktionieren.
    var onHome: (() -> Void)? = nil

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

    var body: some View {
        let hasSelection = !selectedLists.isEmpty
        let totalItems = selectedLists.reduce(0) { $0 + effectiveCount(for: $1) }

        Button {
            feedbackPlayer.playTabSwitch()
            activeCategory = .own
        } label: {
            // Master-Format: Header GANZ links oben, darunter eine HStack
            // aus Modul-Icon (links) · Listen+Summary (Mitte) · Stift-Pill
            // (rechts). Identisch mit `flashcardsListSelectionCard` und
            // `verbformsListSelectionCard` — keine visuellen Ausreißer mehr.
            VStack(alignment: .leading, spacing: 8) {
                Text("AUSGEWÄHLTE LISTEN")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(AppTheme.Colors.cardLabel)

                HStack(alignment: .center, spacing: 14) {
                    // Home-Listen-Icon — identisch zur "Listen"-Kachel auf
                    // dem Home-Screen (Asset `HomeIconListen`). Systemweit
                    // identisches Icon für „Ausgewählte Listen" statt des
                    // früheren SF-Symbols `list.bullet.rectangle.fill`.
                    HomeModuleIconView(icon: .listen, size: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        if hasSelection {
                            // Pro-Liste-Row: nur der Listen-Name. Der
                            // frühere Right-Side-Badge mit „N Einträge"
                            // in Accent-Farbe wurde entfernt — die
                            // Summary-Zeile unten weist die Gesamtzahl
                            // in Blau aus, doppelte Info war redundant.
                            ForEach(selectedLists.prefix(AppLayout.maxSelectableLists)) { list in
                                Text(list.name)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // Summary-Zeile — einheitliches Format
                            // „X Listen · N Einträge gesamt" über alle Module.
                            Text("\(selectedLists.count) Liste\(selectedLists.count == 1 ? "" : "n") · \(totalItems) \(itemLabel) gesamt")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.elumiBlue)
                                .padding(.top, 2)
                        } else {
                            Text("Keine Liste gewählt")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text("Tippe zum Auswählen")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.elumiBlue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Stift in rundem Pill — Größe 16/38. Der äußere
                    // `frame(maxHeight: .infinity)` stellt sicher, dass
                    // der Pill in der vollen HStack-Höhe zentriert sitzt,
                    // auch wenn die VStack nebenan durch Padding oder
                    // mehrzeiliger Content eine asymmetrische Höhen-
                    // verteilung hat (`HStack(alignment: .center)` allein
                    // reichte nicht, weil die Summary-Zeile `padding(.top, 2)`
                    // den Optischen Mittelpunkt verschob).
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(accent.opacity(0.18))
                        )
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
        }
        .buttonStyle(.plain)
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
                },
                feedbackPlayer: feedbackPlayer,
                onHome: onHome
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

    /// **Bug-Fix Footer-Layout (2026-05-04, Punkt 1)** — optionale
    /// Footer-Chrome-Inputs. Wenn beide gesetzt sind, rendert das Sheet
    /// einen `AppBottomBar` über `appLocalChrome` und der User behält
    /// den Tab-Bar-Footer auch in der Listen-Auswahl-Sheet — Pattern
    /// aus `ListPickerSheet`. Default `nil`, damit existing Call-Sites
    /// ohne Anpassung weiterhin funktionieren.
    var feedbackPlayer: FeedbackPlayer? = nil
    var onHome: (() -> Void)? = nil

    @State private var localSelection: Set<UUID> = []
    /// Reihenfolge der Selection — nötig, damit wir bei Erreichen des
    /// `maxSelectableLists`-Limits die **älteste** Auswahl durch die neue
    /// ersetzen können (statt den Tap stumm zu verwerfen, wie früher).
    @State private var selectionOrder: [UUID] = []

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
        // **Bug-Fix Footer-Layout (2026-05-04, Punkt 1)** — Footer-Chrome
        // mirror Pattern aus `ListPickerSheet`: wenn der Caller
        // `feedbackPlayer + onHome` mitliefert, rendern wir den
        // `AppBottomBar` direkt im Sheet, damit der Tab-Bar nicht durch
        // die `.sheet`-Präsentation verdeckt wirkt.
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
            localSelection = selectedListIDs
            selectionOrder = Array(selectedListIDs)
        }
    }

    private func toggleSelection(for list: VocabularyList) {
        let isSelected = localSelection.contains(list.id)
        if list.isAggregateVocabulary {
            localSelection = isSelected ? [] : [list.id]
            selectionOrder = isSelected ? [] : [list.id]
            return
        }
        localSelection.remove(VocabularyListStore.allCustomVocabularyListID)
        selectionOrder.removeAll { $0 == VocabularyListStore.allCustomVocabularyListID }
        if isSelected {
            localSelection.remove(list.id)
            selectionOrder.removeAll { $0 == list.id }
            return
        }
        // Beim Limit NICHT mehr stumm abbrechen — die älteste Auswahl wird
        // ersetzt. User sieht sofort Feedback (Häkchen wandert), statt zu
        // denken der Tap sei kaputt (Bug in Artikel/Verbformen-Setup).
        if localSelection.count >= AppLayout.maxSelectableLists,
           let oldest = selectionOrder.first {
            localSelection.remove(oldest)
            selectionOrder.removeFirst()
        }
        localSelection.insert(list.id)
        selectionOrder.append(list.id)
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
        // Kein `Button` mehr — bei eng gestapelten Zeilen in einer
        // `ScrollView` kann SwiftUI den Button-Tap an die Scroll-Gesture
        // verlieren, sodass das Label-Rendering zwar aktualisiert wird,
        // das Tap-Event aber nie die action-Closure erreicht. Ein
        // explizites `onTapGesture` mit `contentShape(Rectangle())` umgeht
        // das und macht die komplette Zeilen-Box zuverlässig tappbar.
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(effectiveCount(for: list)) Einträge")
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
        .appCardBackground(style, intensity: isSelected ? AppTheme.CardIntensity.selected : AppTheme.CardIntensity.whisper, cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(for: list)
        }
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

    /// **Bug-Fix Footer-Layout (2026-05-04, Punkt 1)** — siehe
    /// `ListSelectionSheet`. Optional, default `nil`.
    var feedbackPlayer: FeedbackPlayer? = nil
    var onHome: (() -> Void)? = nil

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
        // **Bug-Fix Footer-Layout (2026-05-04, Punkt 1)** — siehe
        // `ListSelectionSheet`.
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
            .appCardBackground(style, intensity: isSelected ? AppTheme.CardIntensity.selected : AppTheme.CardIntensity.whisper, cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
