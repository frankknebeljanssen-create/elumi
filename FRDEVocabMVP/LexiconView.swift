import SwiftUI

struct LexiconView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @AppStorage(appDirectionKey) private var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    @ObservedObject var listStore: VocabularyListStore
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void

    private let sectionStyle: AppSectionStyle = .lexicon

    @StateObject private var model = LexiconViewModel()
    @FocusState private var isSearchFieldFocused: Bool
    @State private var lexiconFilterMode: LexiconFilterMode = .both
    /// Zweite Filter-Achse: Wortart. Ergänzt die Richtungs-Filter-Zeile
    /// darüber — beide Filter wirken zusammen (Logik-AND). Default `.all`,
    /// damit das Wörterbuch per Default das volle Ergebnisset zeigt.
    @State private var wordClassFilter: WordClassFilter = .all

    enum LexiconFilterMode: String, CaseIterable {
        case both, frenchToGerman, germanToFrench
    }

    /// Wortart-Filter für die Ergebnisliste. Die Kategorien mappen wir aus
    /// dem vorhandenen `LexiconWordClassMarker`:
    ///   • `.nouns`   ← `.noun`
    ///   • `.verbs`   ← `.verb`
    ///   • `.others`  ← `.adjective`, `.phrase` oder `nil` (alles ohne
    ///                  eindeutige Nomen-/Verb-Klassifikation)
    /// So müssen wir keine neue Wortklassen-Logik parallel aufbauen und
    /// bleiben konsistent mit dem Detail-Sheet, das den gleichen Marker
    /// anzeigt.
    enum WordClassFilter: String, CaseIterable, Identifiable {
        case all
        case nouns
        case verbs
        case others

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Alle"
            case .nouns: return "Nomen"
            case .verbs: return "Verben"
            case .others: return "Sonstige"
            }
        }
    }

    private var selectedLexiconDirection: Direction {
        (Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    private var lexiconTopBarSpacing: CGFloat {
        AppLayout.topBarInsetTop + AppTheme.Spacing.xs
    }

    private var lexiconBottomBarSpacing: CGFloat {
        AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
    }

    private var lexiconScrollBottomInset: CGFloat {
        AppTheme.Layout.footerHeight + lexiconBottomBarSpacing + AppTheme.Spacing.xl
    }

    private var lexiconAccentColor: Color {
        AppTheme.Colors.warning
    }

    private var lexiconSecondaryTextColor: Color {
        AppTheme.Colors.elumiBlush.opacity(0.9)
    }

    private var lexiconRowBackgroundColor: Color {
        AppTheme.Colors.secondarySurface.opacity(0.98)
    }

    private var lexiconRowBorderColor: Color {
        AppTheme.Colors.borderStrong.opacity(0.8)
    }

    private var hasActiveSearch: Bool {
        model.hasActiveSearch
    }

    private var allEntries: [PreparedLexiconEntry] {
        // Erste Achse: Richtungs-Filter (FR-only, DE-only, beide).
        let directionFiltered: [PreparedLexiconEntry]
        switch lexiconFilterMode {
        case .both:
            directionFiltered = model.allEntries
        case .frenchToGerman:
            directionFiltered = model.allEntries.filter { $0.displayCountryCode == "FR" }
        case .germanToFrench:
            directionFiltered = model.allEntries.filter { $0.displayCountryCode == "DE" }
        }

        // Zweite Achse: Wortart-Filter (Alle / Nomen / Verben / Sonstige).
        // Default `.all` → keine zusätzliche Reduktion. Bei spezifischer
        // Wortart filtern wir über den vorhandenen `lexiconWordClassMarker`
        // — so ist die Klassifikation synchron zu dem, was auch im
        // Detail-Sheet als Label angezeigt wird.
        guard wordClassFilter != .all else { return directionFiltered }
        return directionFiltered.filter { entry in
            let marker = model.lexiconWordClassMarker(for: entry)
            switch wordClassFilter {
            case .all:
                return true
            case .nouns:
                return marker == .noun
            case .verbs:
                return marker == .verb
            case .others:
                // Alles, was nicht eindeutig Nomen oder Verb ist — inkl.
                // Adjektive, Phrasen und unklassifizierte Einträge. So
                // verschwindet nichts aus der Suche, auch wenn wir die
                // Wortart nicht eindeutig bestimmen können.
                return marker != .noun && marker != .verb
            }
        }
    }

    private var trimmedSearchText: String {
        model.trimmedSearchText
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
                // **Modul-Header identisch zu Spielen/Fortschritt**
                // (User-Spec „exakt wie"). Sitzt **vor** dem Sticky-
                // Header-Block, damit der User ihn oben auf dem Screen
                // sieht — genau wie bei Spielen/Fortschritt. Scrollt
                // mit dem Content mit (kein Sticky-Inset mehr).
                ModuleHeaderCard(
                    systemImage: "book.closed.fill",
                    title: "Wörterbuch",
                    accent: sectionStyle.accent,
                    onBack: { dismiss() }
                )
                // Etwas mehr Luft zwischen Modul-Header-Card und
                // Content/Sticky-Search darunter (User-Request
                // „etwas mehr padding bei Wörterbuch").
                .padding(.bottom, AppTheme.Spacing.xs)

                // Suche + Filter direkt im Scroll-Content — früher per
                // `safeAreaInset(edge: .top)` oben gepinnt, was den
                // Modul-Header unterhalb der Suche landen ließ. Jetzt
                // im natürlichen Fluss; identisch zur Spielen- und
                // Fortschritt-Layout-Hierarchie.
                stickyLexiconHeader

                if hasActiveSearch {
                    if model.isLoadingLexiconEntries && model.allEntries.isEmpty {
                        LexiconInfoCard(
                            systemImage: "book.closed.fill",
                            title: "Wörterbuch wird geladen",
                            subtitle: nil,
                            tint: lexiconAccentColor,
                            secondaryTextColor: lexiconSecondaryTextColor,
                            sectionStyle: sectionStyle,
                            showsProgress: true
                        )
                    } else {
                        if model.isSearchingLexicon {
                            LexiconInfoCard(
                                systemImage: "magnifyingglass",
                                title: "Suche läuft ...",
                                subtitle: nil,
                                tint: lexiconAccentColor,
                                secondaryTextColor: lexiconSecondaryTextColor,
                                sectionStyle: sectionStyle,
                                showsProgress: true
                            )
                        }

                        if !allEntries.isEmpty {
                            searchResultSummaryCard

                            LazyVStack(spacing: 6) {
                                ForEach(allEntries) { entry in
                                    LexiconEntryRowView(
                                        entry: entry,
                                        sourceCountryCode: model.sourceCountryCode(for: entry),
                                        targetCountryCode: model.targetCountryCode(for: entry),
                                        sourceText: model.displayedSourceText(for: entry),
                                        targetText: model.displayedTargetText(for: entry),
                                        wordClassMarker: model.lexiconWordClassMarker(for: entry),
                                        wordClassBadge: model.lexiconWordClassBadgeText(for: entry),
                                        accentColor: lexiconAccentColor,
                                        secondaryTextColor: lexiconSecondaryTextColor,
                                        rowBackgroundColor: lexiconRowBackgroundColor,
                                        rowBorderColor: lexiconRowBorderColor,
                                        onTap: {
                                            model.selectedEntry = entry
                                        }
                                    )
                                }
                            }
                        } else if !model.isSearchingLexicon {
                            LexiconInfoCard(
                                systemImage: "exclamationmark.magnifyingglass",
                                title: "Keine Treffer gefunden",
                                subtitle: "Versuche es mit der Grundform oder ohne Artikel.",
                                tint: lexiconAccentColor,
                                secondaryTextColor: lexiconSecondaryTextColor,
                                sectionStyle: sectionStyle
                            )
                        }
                    }
                }
            }
            // Padding-Block **identisch zu GameHub + TrophyView**
            // (User-Spec „exakt gleiche Position für diesen
            // Header-Typ"). Einzige Quelle der Wahrheit:
            //   • `screenHeaderTopPadding` oben (Header sitzt auf
            //     derselben vertikalen Linie wie Fortschritt/Spielen).
            //   • `screenPadding` horizontal.
            //   • `Spacing.xxl` unten (für Bottom-Bar-Clearance).
            // Das frühere `.padding(.top, Spacing.xxs)` im VStack +
            // zusätzliches `.padding(.top, screenHeaderTopPadding)` am
            // ScrollView ergaben zusammen ~6–8 pt mehr — genau der
            // Offset, den der User beim Umschalten bemerkt hat.
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, lexiconTopBarSpacing)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: { openSettings() }
            )
        }
        .sheet(item: $model.selectedEntry) { entry in
            LexiconDetailSheetView(
                entry: entry,
                sourceCountryCode: model.sourceCountryCode(for: entry),
                targetCountryCode: model.targetCountryCode(for: entry),
                sourceText: model.displayedSourceText(for: entry),
                targetTexts: model.displayedTargetVariantTexts(for: entry),
                wordClassMarker: model.lexiconWordClassMarker(for: entry),
                sectionStyle: sectionStyle,
                onDone: {
                    model.selectedEntry = nil
                }
            )
        }
        // Passive Suche (bewusst kein Auto-Fokus beim Erscheinen):
        // Screen öffnet ruhig, Footer bleibt stabil, Tastatur erscheint
        // erst bei Tap ins Suchfeld. Der User entscheidet — das ist
        // konsistent mit unserem „freie Wahl"-Prinzip und vermeidet das
        // Layout-Springen, das beim Erzwungenen Fokus auftrat.
        .toolbar {
            // „Fertig"-Button nur sichtbar, während die Tastatur offen
            // ist — schneller Exit ohne dass der User außerhalb tappen muss.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    isSearchFieldFocused = false
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(sectionStyle.accent)
            }
        }
        .task(id: model.searchText) {
            let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                model.preparedEntries = []
                model.isSearchingLexicon = false
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if model.mergedEntries.isEmpty {
                await model.reloadEntries(
                    customLists: listStore.customLists,
                    selectedDirection: selectedLexiconDirection,
                    showLoadingState: true
                )
                // reloadEntries already calls performSearch internally
            } else {
                await model.performSearch(
                    for: model.searchText,
                    customLists: listStore.customLists,
                    selectedDirection: selectedLexiconDirection
                )
            }
        }
        .onChange(of: selectedLexiconDirection) { _, _ in
            model.mergedEntries = []
        }
    }

    private var stickyLexiconHeader: some View {
        // Sticky-Header enthält jetzt nur noch Such-Card + Filter-Rows.
        // Der Modul-Header (`ModuleHeaderCard`) wanderte in den
        // Scroll-Content, damit das Wörterbuch denselben Header-
        // Lifecycle wie Spielen/Fortschritt hat (scrollt mit, keine
        // eigene Background-Ebene).
        VStack(spacing: 10) {
            LexiconSearchCardView(
                searchText: $model.searchText,
                accentColor: lexiconAccentColor,
                secondaryTextColor: lexiconSecondaryTextColor,
                sectionStyle: sectionStyle,
                searchFocus: $isSearchFieldFocused
            )

            // Wortart-Filter direkt unter der Suchleiste — refiniert das
            // Ergebnisset nach Nomen / Verben / Sonstiges. Sitzt bewusst
            // zwischen Suchzeile und Richtungs-Filter: „Was zeigen wir"
            // (Wortart) gehört logisch zur Suche, „In welche Richtung
            // zeigen wir es" (FR/DE) ist die darauffolgende Konfiguration.
            wordClassFilterRow

            lexiconDirectionCard
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.bottom, 2)
        .background(AppTheme.Colors.surface)
    }

    /// Horizontale Chip-Zeile: Alle / Nomen / Verben / Sonstige.
    /// Visuelle Höhe und Card-Umrahmung sind **identisch** zu
    /// `lexiconDirectionCard` (selbes `minHeight: 44`, selbe Card-Padding
    /// `horizontal 4 / vertical 8`, selber `appCardBackground(…)`),
    /// damit die beiden Filter-Zeilen im Sticky-Header zu einer
    /// konsistenten Einheit verschmelzen — Wortart-Filter oben, Richtungs-
    /// Filter direkt darunter, beide im selben optischen Rhythmus.
    private var wordClassFilterRow: some View {
        HStack(spacing: 8) {
            ForEach(WordClassFilter.allCases) { option in
                let isSelected = wordClassFilter == option
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        wordClassFilter = option
                    }
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .foregroundStyle(isSelected ? .white : AppTheme.Colors.textPrimary)
                        .background(isSelected ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wortart-Filter \(option.title)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private var lexiconDirectionCard: some View {
        HStack(spacing: 8) {
            lexiconFilterButton(.both) {
                HStack(spacing: 6) {
                    StraightFlagBadge(countryCode: "FR", width: 24, height: 16, labelFontSize: 8)
                    StraightFlagBadge(countryCode: "DE", width: 24, height: 16, labelFontSize: 8)
                }
            }

            lexiconFilterButton(.frenchToGerman) {
                HStack(spacing: 6) {
                    StraightFlagBadge(countryCode: "FR", width: 28, height: 19, labelFontSize: 9)
                    Text("→")
                        .font(.system(size: 14, weight: .black))
                    StraightFlagBadge(countryCode: "DE", width: 28, height: 19, labelFontSize: 9)
                }
            }

            lexiconFilterButton(.germanToFrench) {
                HStack(spacing: 6) {
                    StraightFlagBadge(countryCode: "DE", width: 28, height: 19, labelFontSize: 9)
                    Text("→")
                        .font(.system(size: 14, weight: .black))
                    StraightFlagBadge(countryCode: "FR", width: 28, height: 19, labelFontSize: 9)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    private func lexiconFilterButton<Content: View>(_ mode: LexiconFilterMode, @ViewBuilder content: () -> Content) -> some View {
        Button {
            lexiconFilterMode = mode
        } label: {
            content()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(lexiconFilterMode == mode ? .white : AppTheme.Colors.textPrimary)
                .background(lexiconFilterMode == mode ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var searchResultSummaryCard: some View {
        HStack {
            Text(model.preparedEntries.count == 1 ? "1 Treffer" : "\(model.preparedEntries.count) Treffer")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Spacer(minLength: 0)
            if hasActiveSearch {
                Text("für „\(trimmedSearchText)”")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(lexiconAccentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }
}
