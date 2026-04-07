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

    var body: some View {
        applyListsPresentations(to: screenContent)
    }

    var screenContent: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .bottom) {
                listsPrimaryContent

                if isShowingToast {
                    toastView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppLayout.screenPadding)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, usesGlobalChrome ? 0 : AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg)
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
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
            }
            editableListName = selectedList.name
        }
        .onChange(of: listStore.selectedListID) { _, _ in
            editableListName = listStore.selectedList.name
            cancelEditing()
        }
    }
}
