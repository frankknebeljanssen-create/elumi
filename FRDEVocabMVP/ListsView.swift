import SwiftUI

struct ListsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    @ObservedObject var listStore: VocabularyListStore
    let launchContext: ListLaunchContext?
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let sectionStyle: AppSectionStyle = .lists

    @State var newListName = ""
    @State var newListCollectionPreset: ListCollectionPreset = .schoolbook
    @State var editableListName = ""
    @State var frenchText = ""
    @State var germanText = ""
    @State var cardType: CardType = .words
    @State var editingItemID: UUID?
    @State var showingEntryEditor = false
    @State var showingRenameDialog = false
    @State var showingListPicker = false
    @State var showingListDetail = false
    @State var showingCreateListForm = false
    @State var shouldRestoreListDetailAfterEditing = false
    @State var listPendingDeletion: VocabularyList?
    @State var toastMessage = ""
    @State var isShowingToast = false
    @State var toastIsSuccess = true
    @State var toastDismissWorkItem: DispatchWorkItem?
}
