import SwiftUI

/// **V1b (2026-04-28)** — file-private Honesty-Helper. Liefert die
/// effektive Item-Anzahl einer Liste unter Berücksichtigung des
/// aktuellen `lernjahrMax`. Wird von `ListCategoryPickerView` genutzt.
/// Hierarchische Listen liefern ihren Y_max-Slice-Count; flache Listen
/// ihre items.count unverändert.
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

    /// **Gruppe-3-Migration (2026-05-22)** — Push-Override. Wenn gesetzt,
    /// ruft der Card-Button-Tap DIESE Closure (statt den internen Sheet-
    /// Pfad). Aufrufer setzt dabei einen eigenen `Bool`-State, der ein
    /// `.navigationDestination` triggert. Backward-kompatibel: nil (Default)
    /// → altes Sheet-Verhalten (`activeCategory = .own`) bleibt unverändert.
    var onTap: (() -> Void)? = nil

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

    // **Phase 5 (2026-05-04) → B2 (2026-05-06)** — `buildSummary(...)`
    // entfernt. Mit dem Lernjahr-Pill-Refactor wird der Range nicht mehr
    // als String-Konkatenation gebaut, sondern als eigenständige
    // `AppLernjahrPill` in einer HStack gerendert.

    var body: some View {
        let hasSelection = !selectedLists.isEmpty
        let totalItems = selectedLists.reduce(0) { $0 + effectiveCount(for: $1) }

        Button {
            feedbackPlayer.playTabSwitch()
            if let onTap = onTap {
                // Push-Override: Caller steuert die Navigation
                // (z. B. .navigationDestination über externe Bool-State).
                onTap()
            } else {
                // Standard-Sheet-Pfad.
                activeCategory = .own
            }
        } label: {
            // Master-Format: Header GANZ links oben, darunter eine HStack
            // aus Modul-Icon (links) · Listen+Summary (Mitte) · Stift-Pill
            // (rechts). Identisch mit `flashcardsListSelectionCard` und
            // `verbformsListSelectionCard` — keine visuellen Ausreißer mehr.
            VStack(alignment: .leading, spacing: 8) {
                // **Naming-Sweep 2026-05-06** — „AUSGEWÄHLTE
                // LISTEN" → „DEINE LISTEN".
                Text("DEINE LISTEN")
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
                            // „X Listen · [LJ-Pill ·] N Einträge gesamt" über
                            // alle Module.
                            // **Phase 5 (2026-05-04) → B2 (2026-05-06)** —
                            // LJ-Range ist jetzt ein tappbarer
                            // `AppLernjahrPill`. Eligibility identisch zur
                            // alten Plain-Text-Render-Bedingung.
                            let listsText = "\(selectedLists.count) Liste\(selectedLists.count == 1 ? "" : "n")"
                            let totalText = "\(totalItems) \(itemLabel)"
                            let lernjahrRange = VocabularyListSelectionResolver.lernjahrRangeLabel(forSelectedLists: selectedLists)
                            HStack(spacing: 4) {
                                Text("\(listsText) ·")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                                if let range = lernjahrRange {
                                    AppLernjahrPill(label: range, tint: AppTheme.Colors.elumiBlue)
                                    Text("·")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.elumiBlue)
                                }
                                Text(totalText)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                            }
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
        .sheet(item: $activeCategory) { _ in
            // **Phase 2 (2026-05-04)** — Migration auf
            // `GlobalListPickerSheet`. Vorher: `ListSelectionSheet`
            // mit 3-Kategorie-Headern (Eigene/Niveau/Themen).
            // Jetzt: einheitlicher Picker mit Lernjahr-Auswahl.
            // Sort sortiert Built-In hierarchisch zuerst — User sieht
            // Grundwortschatz A1 prominent oben, kann LJ wählen.
            GlobalListPickerSheet(
                allLists: availableLists,
                initialSelection: selectedListIDs,
                onCommit: { updatedSelection in
                    onSelectionChanged(updatedSelection)
                    activeCategory = nil
                },
                categoryHeaders: false,
                feedbackPlayer: feedbackPlayer,
                onHome: onHome
            )
        }
    }
}
