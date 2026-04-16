import SwiftUI

extension ListsView {
    var listsPrimaryContent: some View {
        VStack(spacing: 14) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Listen verwalten",
                subtitle: "",
                systemImage: nil, // kein Icon rechts — klassischer Nav-Bar-Look
                onBack: { dismiss() },
                centeredTitle: true
            )

            allListsCard

            categoryCardsSection

            createListSection

            Spacer(minLength: 0)
        }
    }

    // MARK: - Alle Listen (große Card)

    var allListsCard: some View {
        Button {
            showingListPicker = true
        } label: {
            VStack(spacing: 8) {
                // Home-Listen-Icon — identisch zur Listen-Kachel auf dem
                // Home-Screen und zu den „Ausgewählte Listen"-Cards in den
                // Session-Setups. Ein Icon für „Listen" durch die ganze App.
                // Icon etwas größer gesetzt (48 statt 40), damit es auf der
                // Hero-Card „Alle Listen" mehr Präsenz bekommt.
                HomeModuleIconView(icon: .listen, size: 48)

                Text("Alle Listen")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                // +2 pt gegenüber der Caption-Default-Größe (12 → 14) —
                // besser lesbar im größeren Card-Format, ohne den
                // sekundären Charakter zu verlieren.
                Text(countLabel(listStore.allLists.count, singular: "Liste", plural: "Listen"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .appCardBackground(sectionStyle, intensity: 0.09)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kategorie-Cards (Themen, Niveau, Eigene)

    private var categoryCardsSection: some View {
        let topicLists = StandardVocabularyLoader.topicLists
        let levelLists = StandardVocabularyLoader.levelLists
        let ownLists = listStore.sortedCustomLists

        return VStack(spacing: 10) {
            // Eigene Listen
            if !ownLists.isEmpty {
                listsCategoryRow(
                    title: "Eigene Listen",
                    iconAsset: "ListIconEigene",
                    count: ownLists.count
                ) {
                    listPickerFilter = .own
                }
            }

            // Nach Niveau
            if !levelLists.isEmpty {
                listsCategoryRow(
                    title: "Nach Niveau",
                    iconAsset: "ListIconNiveau",
                    count: levelLists.count
                ) {
                    listPickerFilter = .level
                }
            }

            // Nach Themen
            if !topicLists.isEmpty {
                listsCategoryRow(
                    title: "Nach Themen",
                    iconAsset: "ListIconThemen",
                    count: topicLists.count
                ) {
                    listPickerFilter = .topic
                }
            }
        }
    }

    private func listsCategoryRow(
        title: String,
        iconAsset: String,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Eigenständige SVG-Icons aus dem Catalog (nicht SF-Symbols).
                // Bounding-Box 40pt hält den Text-Anker konsistent und gibt
                // der Illustration genug Platz.
                Image(iconAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(sectionStyle.accent)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            // +10 pt Höhe gegenüber dem natürlichen Inhalt (~68pt) — macht
            // die Kategorie-Cards ruhiger und großzügiger, ohne das
            // Padding zu verändern. Padding.horizontal 18 / vertical 20
            // bleiben explizit identisch.
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(sectionStyle.accent.opacity(0.05))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func filteredListsForPicker(_ filter: ListPickerFilter) -> [VocabularyList] {
        switch filter {
        case .all:
            return listStore.allLists
        case .own:
            return listStore.sortedCustomLists
        case .level:
            return StandardVocabularyLoader.levelLists
        case .topic:
            return StandardVocabularyLoader.topicLists
        }
    }

    var createListSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingCreateListForm.toggle()
                }
            } label: {
                VStack(spacing: 8) {
                    // Expandiert → Chevron-Up (klar als „schließen" lesbar).
                    // Collapsed → neues SVG-Icon für „neue Liste", damit die
                    // CTA-Ansicht visuell zur Listen-Welt gehört.
                    if showingCreateListForm {
                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(sectionStyle.accent)
                    } else {
                        Image("ListIconNeueListe")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                    }
                    Text("Neue Liste anlegen")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if showingCreateListForm {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name der Liste", text: $newListName)
                        .textFieldStyle(.roundedBorder)

                    collectionPresetPicker(
                        selectedPreset: $newListCollectionPreset,
                        includeHeading: true
                    )

                    Button("Anlegen") {
                        createNewList()
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }
}
