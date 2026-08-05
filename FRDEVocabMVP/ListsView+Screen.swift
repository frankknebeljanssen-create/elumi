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

    // MARK: - Alle Listen

    /// **2026-08-05** — von einer eigenständigen Hero-Card (54pt-Icon,
    /// eigener Titel-Font, eigenes Padding) auf dieselbe Zeilen-Optik wie
    /// die drei Kategorie-Zeilen umgebaut (User-Spec: „Alle Lernlisten
    /// ist doppelt so groß wie alle anderen, ein bisschen überdimensioniert
    /// … macht das die Seite ausgeglichener"). Man sucht in der Praxis fast
    /// immer gezielt in einer Unterkategorie — „Alle Lernlisten" ist nur
    /// der Überblick und braucht keine visuelle Sonderstellung mehr.
    /// Nutzt dieselbe `ListRowChrome` wie `ListCategoryRow`, damit alle
    /// vier Zeilen (Alle/Meine/Lernstand/Themen) exakt gleich aussehen.
    var allListsCard: some View {
        Button {
            showingListPicker = true
        } label: {
            HStack(spacing: 12) {
                // Home-Listen-Icon — identisch zur Listen-Kachel auf dem
                // Home-Screen und zu den „Ausgewählte Listen"-Cards in den
                // Session-Setups. Auf 46pt runtergezogen, damit es mit den
                // Kategorie-Icons auf einer Höhe liegt.
                HomeModuleIconView(icon: .listen, size: 46)

                Text("Alle Lernlisten")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)

                Text("\(listStore.allLists.count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(sectionStyle.accent)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 70)
            .modifier(ListRowChrome(accent: sectionStyle.accent))
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
                    count: ownLists.count,
                    isActive: ownLists.contains(where: { $0.id == listStore.selectedListID })
                ) {
                    listPickerFilter = .own
                }
            }

            // Nach Lernstand
            if !levelLists.isEmpty {
                listsCategoryRow(
                    title: "Nach Lernstand",
                    iconAsset: "ListIconNiveau",
                    count: levelLists.count,
                    isActive: levelLists.contains(where: { $0.id == listStore.selectedListID })
                ) {
                    listPickerFilter = .level
                }
            }

            // Nach Themen
            if !topicLists.isEmpty {
                listsCategoryRow(
                    title: "Nach Themen",
                    iconAsset: "ListIconThemen",
                    count: topicLists.count,
                    isActive: topicLists.contains(where: { $0.id == listStore.selectedListID })
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
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        // **Extrahiert (2026-05-22)** — die „Meine Listen"-Optik lebt jetzt
        // in der geteilten `ListCategoryRow`-Komponente (Listenpicker-
        // Vereinheitlichung). ListsView reicht nur die Sektionsfarbe herein;
        // die drei Aufrufseiten bleiben unverändert, das Rendering 1:1.
        //
        // **2026-08-05** — `isActive` markiert, in welcher Kategorie die
        // aktuell ausgewählte Liste (`listStore.selectedListID`) liegt
        // (User-Spec: Übersicht, ohne jede Kategorie einzeln aufklappen
        // zu müssen).
        ListCategoryRow(
            title: title,
            iconAsset: iconAsset,
            count: count,
            accent: sectionStyle.accent,
            action: action,
            isActive: isActive
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

    /// **2026-08-05** — Kopfzeile von „Icon oben, Text drunter" auf
    /// dieselbe Zeilen-Optik wie die drei Kategorie-Zeilen umgebaut
    /// (User-Spec, gleicher Anlass wie `allListsCard`). Das alte SVG-Icon
    /// wirkte laut User "'n bisschen zu klein" für eine CTA — ein klarer,
    /// gefüllter Plus-Kreis (SF Symbol) ist prominenter und lesbarer als
    /// Icon-Ersatz, ohne die Zeile aufzublähen.
    var createListSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingCreateListForm.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Expandiert → Chevron-up (klar als „schließen" lesbar).
                    // Collapsed → gefüllter Plus-Kreis, betont das
                    // Hinzufügen-Pattern deutlicher als das vorherige,
                    // kleinteilige SVG-Icon.
                    Image(systemName: showingCreateListForm ? "chevron.up.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                        .frame(width: 46, height: 46)

                    Text("Neue Lernliste anlegen")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 70)
                .modifier(ListRowChrome(accent: sectionStyle.accent))
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
                .padding(14)
                .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // **2026-08-05** — kein äußerer Card-Wrapper mehr um die ganze
        // Section: der Toggle-Button trägt jetzt selbst die
        // Zeilen-Chrome (`ListRowChrome`, wie die drei Kategorie-Zeilen).
        // Ein zusätzlicher äußerer Rahmen hätte eine Card-in-Card-Optik
        // erzeugt. Das aufgeklappte Formular bekommt stattdessen seine
        // eigene, kleinere Card (siehe oben).
    }
}
