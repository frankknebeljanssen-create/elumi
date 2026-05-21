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

    /// **Stufe 1 V1a (2026-04-28)** — Cumulative Lernjahr-Max-Selektion.
    /// 0 = alle Lernjahre, 1...5 = Y_1…Y_n. Default 1 = „7. Klasse Gym".
    @AppStorage(appLernjahrMaxKey) var lernjahrMax: Int = 1

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
    @State var listPickerFilter: ListPickerFilter?

    enum ListPickerFilter: Identifiable {
        case all, own, level, topic
        var id: String {
            switch self {
            case .all: return "all"
            case .own: return "own"
            case .level: return "level"
            case .topic: return "topic"
            }
        }
    }
    @State var showingListDetail = false
    @State var showingCreateListForm = false
    @State var shouldRestoreListDetailAfterEditing = false
    @State var listPendingDeletion: VocabularyList?
    @State var toastMessage = ""
    @State var isShowingToast = false
    @State var toastIsSuccess = true
    @State var toastDismissWorkItem: DispatchWorkItem?

    /// **List-Merge Phase 1 (2026-05-21)** — Coordinator für die Merge-Sheet-
    /// Kette (Picker → NewListNameSheet → Merge → Toast). Parameterloser init,
    /// `listStore` wird `performMerge` als Param übergeben (Phase-E-Pattern).
    @StateObject var mergeCoordinator = ListMergeCoordinator()
}
