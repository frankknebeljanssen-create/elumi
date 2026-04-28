import SwiftUI

/// **Create-Sheet für einen persönlichen Trainings-Stapel** (Phase 8).
/// Zwei Schritte im selben Sheet (kein Navigation-Push): Schritt 1 =
/// Multi-Select-Liste von verfügbaren Vokabel-Listen, Schritt 2 =
/// Stapel-Name festlegen. Bestätigung baut den PersonalDeck und reicht
/// ihn via `onConfirm` an den Aufrufer zurück (der persistiert ihn).
struct CreatePersonalDeckSheet: View {
    /// Alle zur Auswahl stehenden Listen (bereits gefiltert auf die
    /// aktive Sprachrichtung — der Aufrufer reicht `availableStackLists`
    /// durch, damit die Sheet-Logik Schichten-agnostisch bleibt).
    let availableLists: [VocabularyList]
    let sectionStyle: AppSectionStyle
    let nextColorIndex: Int
    /// **Edit-Mode (User-Revision 2026-04-22)**: wenn gesetzt, läuft das
    /// Sheet im Edit-Modus — Listen + Name können für den bestehenden
    /// Stapel geändert werden. On-Confirm gibt ein Deck mit **derselben
    /// `id`** zurück, Listen ggf. aktualisiert und `cardOrder` neu
    /// gemischt, wenn Listen verändert wurden. Wenn nil → Create-Mode
    /// (bisheriges Verhalten, frische UUID).
    let editingDeck: PersonalDeck?
    let onCancel: () -> Void
    /// Callback mit dem fertig gebauten Deck. Der Aufrufer persistiert
    /// ihn und schließt das Sheet.
    let onConfirm: (PersonalDeck) -> Void

    @State private var step: Step = .chooseLists
    @State private var selectedListIDs: Set<UUID> = []
    @State private var deckName: String = ""
    @FocusState private var isNameFocused: Bool

    /// Convenience-Init für Create-Mode (Abwärtskompatibilität).
    init(
        availableLists: [VocabularyList],
        sectionStyle: AppSectionStyle,
        nextColorIndex: Int,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (PersonalDeck) -> Void
    ) {
        self.availableLists = availableLists
        self.sectionStyle = sectionStyle
        self.nextColorIndex = nextColorIndex
        self.editingDeck = nil
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    /// Init für Edit-Mode.
    init(
        availableLists: [VocabularyList],
        sectionStyle: AppSectionStyle,
        editingDeck: PersonalDeck,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (PersonalDeck) -> Void
    ) {
        self.availableLists = availableLists
        self.sectionStyle = sectionStyle
        self.nextColorIndex = editingDeck.colorIndex
        self.editingDeck = editingDeck
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    private enum Step {
        case chooseLists
        case nameDeck
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .appScreenBackground(sectionStyle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        handleBackOrCancel()
                    } label: {
                        Text(step == .chooseLists ? "Abbrechen" : "Zurück")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(editingDeck == nil ? "Neuer Stapel" : "Stapel bearbeiten")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // **Edit-Mode-Preload**: Vor-Auswahl und Name aus dem
            // bestehenden Deck übernehmen, damit der User sieht, was
            // aktuell drin ist und gezielt ergänzen/entfernen kann.
            if let editingDeck, selectedListIDs.isEmpty {
                selectedListIDs = Set(editingDeck.sourceListIDs)
                deckName = editingDeck.name
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .chooseLists:
            chooseListsStep
        case .nameDeck:
            nameDeckStep
        }
    }

    // MARK: - Step 1: Choose Lists

    private var chooseListsStep: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("LISTEN AUSWÄHLEN")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Color(hex: "#5B9CF5"))
                        .padding(.horizontal, AppLayout.screenPadding)
                        .padding(.top, 8)

                    ForEach(availableLists) { list in
                        listRow(list)
                    }
                }
                .padding(.bottom, 110)
            }

            // Sticky Next-Button
            VStack(spacing: 0) {
                Button {
                    goToNameStep()
                } label: {
                    Text("Weiter")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    selectedListIDs.isEmpty
                                        ? Color(hex: "#2EC4A9").opacity(0.3)
                                        : Color(hex: "#2EC4A9")
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(selectedListIDs.isEmpty)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.vertical, 12)
                .background(
                    Rectangle()
                        .fill(AppTheme.Colors.background.opacity(0.92))
                        .ignoresSafeArea(edges: .bottom)
                )
            }
        }
    }

    private func listRow(_ list: VocabularyList) -> some View {
        let isSelected = selectedListIDs.contains(list.id)
        let cardCount = list.items.count

        return Button {
            toggleSelection(for: list.id)
        } label: {
            HStack(spacing: 10) {
                // Checkbox 10×10
                ZStack {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isSelected ? Color(hex: "#2EC4A9") : Color.clear)
                        .frame(width: 14, height: 14)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(
                            isSelected
                                ? Color(hex: "#2EC4A9")
                                : Color.white.opacity(0.3),
                            lineWidth: 1
                        )
                        .frame(width: 14, height: 14)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(cardCount == 1 ? "1 Karte" : "\(cardCount) Karten")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(hex: "#2EC4A9").opacity(0.08)
                            : AppTheme.Colors.surface.opacity(0.5)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color(hex: "#2EC4A9").opacity(0.5)
                            : AppTheme.Colors.border.opacity(0.3),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppLayout.screenPadding)
    }

    // MARK: - Step 2: Name Deck

    private var nameDeckStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NAME")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color(hex: "#5B9CF5"))
                .padding(.top, 16)

            TextField("Name des Stapels", text: $deckName)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .focused($isNameFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.Colors.surface.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Colors.border.opacity(0.3), lineWidth: 1)
                )

            Text(summaryText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                confirmDeckCreation()
            } label: {
                Text("Stapel anlegen")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                deckName.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color(hex: "#2EC4A9").opacity(0.3)
                                    : Color(hex: "#2EC4A9")
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(deckName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, 16)
    }

    private var summaryText: String {
        let listCount = selectedListIDs.count
        let cardCount = selectedLists.reduce(0) { $0 + $1.items.count }
        let lists = listCount == 1 ? "1 Liste" : "\(listCount) Listen"
        let cards = cardCount == 1 ? "1 Karte" : "\(cardCount) Karten"
        return "\(lists) · \(cards) werden gemischt und zu einem Stapel."
    }

    // MARK: - Helpers

    private var selectedLists: [VocabularyList] {
        availableLists.filter { selectedListIDs.contains($0.id) }
    }

    private func toggleSelection(for id: UUID) {
        if selectedListIDs.contains(id) {
            selectedListIDs.remove(id)
        } else {
            selectedListIDs.insert(id)
        }
    }

    private func goToNameStep() {
        // Default-Name aus Listennamen generieren (gekürzt auf 3
        // Listen, damit der Vorschlag nicht explodiert).
        let listNames = selectedLists.prefix(3).map { $0.name }
        let suffix = selectedLists.count > 3 ? " +…" : ""
        deckName = listNames.joined(separator: " · ") + suffix
        step = .nameDeck
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNameFocused = true
        }
    }

    private func handleBackOrCancel() {
        switch step {
        case .chooseLists:
            onCancel()
        case .nameDeck:
            step = .chooseLists
            isNameFocused = false
        }
    }

    private func confirmDeckCreation() {
        let trimmedName = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard !selectedListIDs.isEmpty else { return }

        // **Edit-Mode**: bestehendes Deck aktualisieren — id + createdAt
        // bleiben; Listen + Name updaten. cardOrder wird NUR neu gemischt,
        // wenn sich die Source-Listen geändert haben (sonst bleibt
        // Fortschritt erhalten).
        if let editingDeck {
            let oldLists = Set(editingDeck.sourceListIDs)
            let newLists = selectedListIDs
            let listsChanged = oldLists != newLists

            var updated = editingDeck
            updated.name = trimmedName
            updated.sourceListIDs = Array(newLists)
            if listsChanged {
                // Neue Karten einsammeln + neu shufflen. Fortschritts-
                // Cursor + masteredCardIDs zurücksetzen, weil die
                // alten IDs ggf. nicht mehr in cardOrder stecken.
                let freshCardIDs = availableLists
                    .filter { newLists.contains($0.id) }
                    .flatMap { $0.items.map(\.id) }
                updated.cardOrder = freshCardIDs.shuffled()
                updated.currentIndex = 0
                updated.masteredCardIDs = []
            }
            updated.lastAccessedAt = Date()
            onConfirm(updated)
            return
        }

        // Create-Mode (Default): frisches Deck.
        let allCardIDs = selectedLists.flatMap { $0.items.map(\.id) }
        guard !allCardIDs.isEmpty else { return }
        let shuffled = allCardIDs.shuffled()

        let deck = PersonalDeck(
            name: trimmedName,
            colorIndex: nextColorIndex,
            sourceListIDs: Array(selectedListIDs),
            cardOrder: shuffled,
            currentIndex: 0,
            masteredCardIDs: [],
            lastAccessedAt: Date(),
            createdAt: Date()
        )
        onConfirm(deck)
    }
}
