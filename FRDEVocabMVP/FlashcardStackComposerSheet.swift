import SwiftUI

struct FlashcardStackComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let style: AppSectionStyle
    let lists: [VocabularyList]
    let selectedListIDs: Set<UUID>
    let language: StudyLanguage
    let cardTypeFilter: CardType?
    /// **Empty-Pool-Hint (2026-04-29)**: optionale Pre-Save-Validierung.
    /// Wird beim „Fertig"-Tap VOR `onSave` aufgerufen. Gibt der Closure
    /// einen non-nil String zurück, bleibt das Sheet offen und zeigt
    /// den String als Inline-Fehler unter der Info-Card. Returnt sie
    /// nil (oder ist die Validierung gar nicht gesetzt), läuft der
    /// bisherige Pfad: `onSave` + `dismiss`. Default `nil` =
    /// keine Validation, vollständig backward-kompatibel zu Callern,
    /// die keine Empty-Pool-Bedingung prüfen müssen (Quiz-/Karteikarten-
    /// Standard-Picker setzen nur eine Selection-Variable).
    let validate: ((Set<UUID>) -> String?)?
    let onSave: (Set<UUID>) -> Void

    /// Expliziter Init mit Default für `validate` — Swifts auto-
    /// memberwise-Init übernimmt `let`-mit-Default nicht als Parameter,
    /// daher hier ausgeschrieben. Backward-Kompat zu existierenden
    /// Callern, die `validate` weglassen (Quiz, Karteikarten-Setup).
    init(
        style: AppSectionStyle,
        lists: [VocabularyList],
        selectedListIDs: Set<UUID>,
        language: StudyLanguage,
        cardTypeFilter: CardType?,
        validate: ((Set<UUID>) -> String?)? = nil,
        onSave: @escaping (Set<UUID>) -> Void
    ) {
        self.style = style
        self.lists = lists
        self.selectedListIDs = selectedListIDs
        self.language = language
        self.cardTypeFilter = cardTypeFilter
        self.validate = validate
        self.onSave = onSave
    }

    @State private var localSelection: Set<UUID> = []
    /// Inline-Fehler unter der Info-Card. Quelle: `validate`-Closure
    /// vom Caller. Wird beim nächsten Selection-Change zurückgesetzt,
    /// damit der User nicht den alten Fehler liest, während er bereits
    /// eine andere Auswahl trifft.
    @State private var errorMessage: String? = nil

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
                    // Empty-Pool-Hint (2026-04-29): wenn der Caller eine
                    // Validierung mitgeschickt hat, fragen wir die zuerst.
                    // Non-nil Return = Fehler → Sheet bleibt offen, Inline-
                    // Hint erscheint. Sonst Standard-Pfad.
                    if let validate, let error = validate(localSelection) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            errorMessage = error
                        }
                        return
                    }
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

            // Empty-Pool-Hint Inline-Fehler (2026-04-29). Erscheint NUR
            // wenn der Caller eine Validierung gesetzt hat UND diese
            // beim letzten „Fertig"-Tap einen Fehler zurückgegeben hat.
            // Wird beim nächsten Selection-Change zurückgesetzt
            // (`onChange(of: localSelection)` weiter unten), damit der
            // User nicht den alten Fehler liest, während er bereits
            // eine andere Liste tippt.
            if let errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(AppTheme.Colors.warning)
                    Text(errorMessage)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(AppTheme.Colors.surface.opacity(0.98))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(AppTheme.Colors.warning.opacity(0.3), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
        .onChange(of: localSelection) { _, _ in
            // Empty-Pool-Hint (2026-04-29): bestehenden Fehler verwerfen,
            // sobald der User eine andere Auswahl trifft. Sonst klebt
            // der alte „keine Karten"-Hint, während die neue Auswahl
            // bereits gültig wäre.
            if errorMessage != nil {
                withAnimation(.easeInOut(duration: 0.22)) {
                    errorMessage = nil
                }
            }
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
            .appCardBackground(style, intensity: localSelection.contains(list.id) ? AppTheme.CardIntensity.selected : AppTheme.CardIntensity.whisper, cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(localSelection.contains(list.id) ? style.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func cardCount(for list: VocabularyList) -> Int {
        // **V1b (2026-04-28)** — Composer-Card-Count respektiert den
        // globalen Lernjahr-Filter; konsistent zu dem was nach
        // „Auswählen" tatsächlich in den Stack einfließt.
        let effective = VocabularyListSelectionResolver.effectiveItems(
            for: list,
            lernjahrMax: VocabularyListSelectionResolver.currentLernjahrMax()
        )
        return effective.filter {
            $0.sourceLanguage == language &&
            (cardTypeFilter == nil || $0.cardType == cardTypeFilter)
        }.count
    }
}
