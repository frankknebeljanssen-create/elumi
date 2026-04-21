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
                // Icon auf 54 pt — weiter gewachsen gegenüber 48, damit die
                // Hero-Card optisch dominanter bleibt als die Kategorie-
                // Cards darunter.
                HomeModuleIconView(icon: .listen, size: 54)

                // Titel +1 pt (22 → 23) — kräftigere Hierarchie gegenüber
                // den Kategorie-Cards (deren Titel 17 → 18 mitgewachsen
                // sind).
                Text("Alle Listen")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                // Count-Text mit der Card mitgewachsen (14 → 15) — bleibt
                // sekundär, aber nicht mehr winzig gegenüber dem größeren
                // Titel.
                Text(countLabel(listStore.allLists.count, singular: "Liste", plural: "Listen"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
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
                // Bounding-Box 46pt — etwas größer als vorher (40), damit die
                // Kategorie-Illustrationen auch in der Row sichtbar „atmen".
                Image(appIcon: iconAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)

                // Titel +1pt (17 → 18) — besser lesbar auf der gewachsenen
                // Card, bleibt aber klar unterhalb des Alle-Listen-Titels.
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)

                // Count ebenfalls +1pt (16 → 17) — skaliert mit dem Titel.
                Text("\(count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
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
                            .fill(sectionStyle.accent.opacity(AppTheme.CardIntensity.whisper))
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
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(sectionStyle.accent)
                    } else {
                        // Icon synchron zum Alle-Listen-Icon gewachsen
                        // (48 → 54), damit beide Hero-Icons auf dem Screen
                        // dieselbe Gewichtung haben.
                        Image(appIcon: "ListIconNeueListe")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
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
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }
}
