import SwiftUI

extension ListsView {
    var listsPrimaryContent: some View {
        VStack(spacing: 14) {
            // **Naming-Sweep 2026-05-06** — „Listen verwalten" →
            // „Meine Listen". Kürzer, persönlicher, weniger
            // Verwaltungs-Sprache.
            ModuleHeaderCard(
                icon: .listen,
                title: "Meine Listen",
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
                // Stufe 6 Schritt 3 (2026-04-29): nach Set-A-Removal +
                // Imageset-Rename ist der Catalog flach; Asset-Name wird
                // 1:1 verwendet, kein Resolver, kein Suffix.
                Image(iconAsset)
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
            // **Polish 2026-05-10** — Cards flacher (~10%): vertical
            // padding 20 → 14, minHeight 78 → 70. Kategorie-Cards
            // sitzen kompakter, der Listen-Screen wirkt insgesamt
            // ruhiger und schneller scannbar.
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 70)
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
                        Image("ListIconNeueListe")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                    }
                    // **Naming-Sweep 2026-05-06** — „Neue Liste
                    // anlegen" → „+ Neue Liste". Plus-Icon im Text
                    // betont das Hinzufügen-Pattern.
                    Text("+ Neue Liste")
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
                    TextField("Name der Liste", text: $newListName)
                        .textFieldStyle(.roundedBorder)

                    Button("Liste erstellen") {
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
