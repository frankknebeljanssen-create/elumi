import SwiftUI

extension ListsView {
    var listsPrimaryContent: some View {
        VStack(spacing: 14) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Listen verwalten",
                subtitle: "",
                systemImage: "list.bullet.rectangle"
            )

            listSelectionSection

            if !showingCreateListForm {
                selectedListSection
            }

            createListSection

            Spacer(minLength: 0)
        }
    }

    var listSelectionSection: some View {
        Button {
            showingListPicker = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listen")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(countLabel(listStore.allLists.count, singular: "Liste", plural: "Listen"))
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .appCardBackground(sectionStyle, intensity: 0.09)
        }
        .buttonStyle(.plain)
    }

    var selectedListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                showingListDetail = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(selectedList.name)
                            .font(AppTheme.Typography.screenTitle)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Text(listMetaText)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .appChipBackground(sectionStyle, intensity: 0.08, cornerRadius: 20)
            }
            .buttonStyle(.plain)

            VStack(spacing: 10) {
                Button {
                    startNewEntry()
                } label: {
                    Text("Neue Vokabeln eingeben")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                .disabled(selectedList.isBuiltIn)

                if !selectedList.isBuiltIn {
                    Button {
                        editableListName = selectedList.name
                        showingRenameDialog = true
                    } label: {
                        Text("Umbenennen")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 38)
                    }
                    .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))
                }

                Button {
                    listPendingDeletion = selectedList
                } label: {
                    Text("Liste löschen")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.error))
                .disabled(selectedList.isBuiltIn)
            }

            if selectedList.isBuiltIn {
                Text("Das Standardpaket bleibt unverändert. Lege für eigene Inhalte eine neue Liste an.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(16)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    var createListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingCreateListForm.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Neue Liste anlegen")
                            .font(AppTheme.Typography.cardTitle)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(showingCreateListForm ? "Name und Sammlung wählen" : "Neue Liste hinzufügen")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: showingCreateListForm ? "chevron.up.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
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
