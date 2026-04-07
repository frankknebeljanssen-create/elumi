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
        model.allEntries
    }

    private var trimmedSearchText: String {
        model.trimmedSearchText
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
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

                            LazyVStack(spacing: 12) {
                                ForEach(allEntries) { entry in
                                    LexiconEntryRowView(
                                        entry: entry,
                                        sourceCountryCode: model.sourceCountryCode(for: entry),
                                        targetCountryCode: model.targetCountryCode(for: entry),
                                        sourceText: model.displayedSourceText(for: entry),
                                        targetText: model.displayedTargetText(for: entry),
                                        wordClassMarker: model.lexiconWordClassMarker(for: entry),
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
                } else {
                    LexiconInfoCard(
                        systemImage: "text.magnifyingglass",
                        title: "Suche direkt nach einem Wort",
                        subtitle: "Französisch oder Deutsch eingeben, dann erscheinen die Treffer sofort.",
                        tint: lexiconAccentColor,
                        secondaryTextColor: lexiconSecondaryTextColor,
                        sectionStyle: sectionStyle
                    )
                }
            }
            .padding(.top, AppTheme.Spacing.xxs)
            .padding(.bottom, lexiconScrollBottomInset)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            stickyLexiconHeader
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.contentTopPadding)
                .padding(.bottom, AppTheme.Spacing.sm)
                .background(AppTheme.Colors.surface.opacity(0.98))
        }
        .padding(.horizontal, AppLayout.screenPadding)
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
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
            }
            await model.performSearch(
                for: model.searchText,
                customLists: listStore.customLists,
                selectedDirection: selectedLexiconDirection
            )
        }
        .onChange(of: selectedLexiconDirection) { _, _ in
            model.mergedEntries = []
        }
    }

    private var stickyLexiconHeader: some View {
        VStack(spacing: 14) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Wörterbuch",
                subtitle: "",
                systemImage: "book.closed.fill"
            )

            LexiconSearchCardView(
                searchText: $model.searchText,
                accentColor: lexiconAccentColor,
                secondaryTextColor: lexiconSecondaryTextColor,
                sectionStyle: sectionStyle,
                searchFocus: $isSearchFieldFocused
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.bottom, 2)
        .background(AppTheme.Colors.surface)
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
        .appCardBackground(sectionStyle, intensity: 0.09)
    }
}
