import SwiftUI

extension ListsView {
    var listsPrimaryContent: some View {
        VStack(spacing: 14) {
            // **2026-08-04** — „Meine Lernlisten" → „Lernlisten" (User-
            // Spec): der Screen zeigt „Alle Lernlisten" UND „Meine
            // Lernlisten" als eigene Kategorien darunter — der
            // Screen-Titel „Meine..." kollidierte mit der „Alle..."-Card
            // direkt drunter. Neutraler Titel grenzt „Meine Lernlisten"
            // als eigene, klar abgesetzte Kategorie ab.
            ModuleHeaderCard(
                icon: .listen,
                title: "Lernlisten",
                accent: sectionStyle.accent,
                onBack: { dismiss() }
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
                Text("Alle Lernlisten")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                // Count-Text mit der Card mitgewachsen (14 → 15) — bleibt
                // sekundär, aber nicht mehr winzig gegenüber dem größeren
                // Titel.
                Text(countLabel(listStore.allLists.count, singular: "Lernliste", plural: "Lernlisten"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            // **Polish 2026-05-10** — Card flacher (~10%): vertical
            // padding 20 → 14. Nähert die Card-Höhe an die Kategorie-
            // Cards an und kompaktiert den Listen-Screen ohne den
            // Hero-Charakter zu verlieren.
            .padding(.vertical, 14)
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
            // Meine Listen
            if !ownLists.isEmpty {
                listsCategoryRow(
                    title: "Meine Lernlisten",
                    iconAsset: "ListIconEigene",
                    count: ownLists.count
                ) {
                    listPickerFilter = .own
                }
            }

            // Nach Lernstand
            if !levelLists.isEmpty {
                listsCategoryRow(
                    title: "Nach Lernstand",
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
        // **Extrahiert (2026-05-22)** — die „Meine Listen"-Optik lebt jetzt
        // in der geteilten `ListCategoryRow`-Komponente (Listenpicker-
        // Vereinheitlichung). ListsView reicht nur die Sektionsfarbe herein;
        // die drei Aufrufseiten bleiben unverändert, das Rendering 1:1.
        ListCategoryRow(
            title: title,
            iconAsset: iconAsset,
            count: count,
            accent: sectionStyle.accent,
            action: action
        )
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
                        Image("ListIconNeueListe")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                    }
                    // **Naming-Sweep 2026-05-06** — „Neue Liste
                    // anlegen" → „+ Neue Liste". Plus-Icon im Text
                    // betont das Hinzufügen-Pattern.
                    Text("+ Neue Lernliste anlegen")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                // **Polish 2026-05-10** — flacher (~10%): inner
                // vertical padding 6 → 4.
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if showingCreateListForm {
                // **2026-04-24 Vereinfachung**: Sammlung-Picker raus.
                // Vorerst nur Namensfeld + Anlegen. Der interne
                // `newListCollectionPreset`-Default `.schoolbook` bleibt
                // erhalten (gesetzt in ListsView.swift Zeile 19) — die
                // Datenkompatibilität ist damit unverändert, der UI-
                // Block ist nur ausgeblendet.
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name der Lernliste", text: $newListName)
                        .textFieldStyle(.roundedBorder)

                    Button("Lernliste erstellen") {
                        createNewList()
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                    .frame(maxWidth: .infinity, alignment: .center)
                    // Erstellen-Button nur aktiv, wenn nach Trim ein
                    // nicht-leerer Name vorliegt (User-Spec).
                    .disabled(
                        newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .opacity(
                        newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? 0.55 : 1.0
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // **Polish 2026-05-10** — Card flacher (~10%): outer padding
        // 16 → 14. Synchron zum allListsCard + Kategorie-Card-Sweep.
        .padding(14)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }
}
