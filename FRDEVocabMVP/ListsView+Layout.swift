import SwiftUI

extension ListsView {
    var selectedList: VocabularyList {
        listStore.selectedList
    }

    var sourceFieldLabel: String {
        selectedList.items.first?.sourceLanguage.rawValue ?? "Französisch"
    }

    var listMetaText: String {
        "\(selectedList.items.count) Einträge · \(listCollectionSummary(for: selectedList))"
    }

    /// When launched from Import Completion, skip showing the lists screen entirely
    private var isDirectListLaunch: Bool {
        launchContext?.preferredListID != nil
    }

    var body: some View {
        applyListsPresentations(to: screenContent)
    }

    var screenContent: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                // **Direct-Launch-Bypass** (Bug-Fix 2026-04-23 abends):
                // wenn der User aus dem Import-Fertig-Screen via
                // „Liste ansehen" kommt, soll NICHT die „Listen
                // verwalten"-Übersicht aufflackern. Vorher zeigte
                // diese Stelle `Color.clear` als Inhalt — der App-
                // Top-/Bottom-Bar (`appLocalChrome`) blieb aber
                // sichtbar und der Header „Listen verwalten" tauchte
                // kurz auf. Lösung: `listsPrimaryContent` einfach
                // gar nicht rendern, sondern eine ruhige
                // Hintergrundfläche, bis das Sheet darüber sitzt.
                if isDirectListLaunch {
                    Color.clear
                } else {
                    listsPrimaryContent
                }

                if isShowingToast {
                    toastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            // Systemweites Top-Padding für Screen-Header — Header sitzt
            // damit auf derselben vertikalen Position wie im Quiz-Setup.
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, AppLayout.screenPadding)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, usesGlobalChrome ? 0 : AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg)
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // **Bug-Fix 2026-04-23**: Bei Direct-Launch (aus Import-Fertig)
        // den lokalen Chrome (TopBar + BottomBar) komplett unterdrücken
        // — sonst flackert der „Listen verwalten"-Header sichtbar auf,
        // bevor das Detail-Sheet sich aufschiebt.
        .appLocalChrome(enabled: !usesGlobalChrome && !isDirectListLaunch) {
            AppTopBar(onBack: { dismiss() }, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: { openSettings() }
            )
        }
        .animation(.easeInOut(duration: 0.22), value: isShowingToast)
        .onAppear {
            if let preferredListID = launchContext?.preferredListID,
               listStore.allLists.contains(where: { $0.id == preferredListID }) {
                listStore.selectedListID = preferredListID
                // From Import Completion → open list detail directly
                showingListDetail = true
            }
            editableListName = selectedList.name
        }
        .onChange(of: listStore.selectedListID) { _, _ in
            editableListName = listStore.selectedList.name
            cancelEditing()
        }
    }
}
