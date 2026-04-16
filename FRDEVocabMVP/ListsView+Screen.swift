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
                HomeModuleIconView(icon: .listen, size: 40)

                Text("Alle Listen")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(countLabel(listStore.allLists.count, singular: "Liste", plural: "Listen"))
                    .font(AppTheme.Typography.caption)
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
                    systemImage: "person.fill",
                    count: ownLists.count
                ) {
                    listPickerFilter = .own
                }
            }

            // Nach Niveau
            if !levelLists.isEmpty {
                listsCategoryRow(
                    title: "Nach Niveau",
                    systemImage: "chart.bar.fill",
                    count: levelLists.count
                ) {
                    listPickerFilter = .level
                }
            }

            // Nach Themen
            if !topicLists.isEmpty {
                listsCategoryRow(
                    title: "Nach Themen",
                    systemImage: "tag.fill",
                    count: topicLists.count
                ) {
                    listPickerFilter = .topic
                }
            }
        }
    }

    private func listsCategoryRow(
        title: String,
        systemImage: String,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
                    .frame(width: 32)

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
                    Image(systemName: showingCreateListForm ? "chevron.up.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
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
