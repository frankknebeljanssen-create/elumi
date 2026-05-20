// ScanDraftStore.swift
// **Meine Scans — Phase A (2026-05-20)** — Observable Store für
// `ScanDraft`s. Spiegelt das `VocabularyListStore`-Pattern:
//   • @MainActor ObservableObject mit @Published-Collection
//   • debounced didSet-Save (0.3 s, DispatchWorkItem)
//   • `isApplyingStoredState`-Guard gegen Save-während-Load
//   • Per-Account-Namespace-Key + Reload auf `AccountStore.didSwitchAccount`
//   • Persistenz delegiert an `ScanDraftStoreRepository`
//
// **Architektur-Entscheidung (Pattern-Match-Default, Phase-A-Spec):**
// `VocabularyListStore` ist im Projekt KEIN echtes Singleton (es wird
// per Runtime-Container injiziert). Da Phase A bewusst KEIN Auto-Wire
// enthält, der Store aber später (Phase B/C) erreichbar sein muss,
// ist `ScanDraftStore.shared` hier — wie in der Auftrags-Spec gefordert —
// als geteiltes Singleton angelegt. Die Wiring-Entscheidung
// (Injection vs. shared) kann in einer späteren Phase angeglichen werden.

import Foundation
import SwiftUI

@MainActor
final class ScanDraftStore: ObservableObject {
    static let shared = ScanDraftStore()

    @Published var drafts: [ScanDraft] = [] {
        didSet {
            guard !isApplyingStoredState else { return }
            scheduleSave()
        }
    }

    private let repository: ScanDraftStoreRepository
    private var isApplyingStoredState = false
    private var pendingSaveWorkItem: DispatchWorkItem?

    /// Per-Account-Namespace-Key (analog `VocabularyListStore.customListsKey`).
    var draftsKey: String { AccountStore.shared.namespacedKey("FRDEVocabMVP.scanDrafts.v1") }

    init(repository: ScanDraftStoreRepository = ScanDraftStoreRepository()) {
        self.repository = repository
        loadState()

        // Auf Account-Switch reagieren (analog Vorbild). Singleton-artig,
        // deshalb kein removeObserver nötig.
        NotificationCenter.default.addObserver(
            forName: AccountStore.didSwitchAccount,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadForCurrentAccount()
            }
        }
    }

    // MARK: - Public API

    /// Fügt einen neuen Draft hinzu (triggert debounced Save).
    func add(_ draft: ScanDraft) {
        drafts.append(draft)
    }

    /// Entfernt einen Draft inkl. seiner Bild-Dateien.
    func remove(_ draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        try? ScanDraftImageStore.deleteAll(forDraftID: draftID)
        drafts.remove(at: index)
    }

    /// Ersetzt einen vorhandenen Draft und setzt `updatedAt = .now`.
    func update(_ draft: ScanDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        var updated = draft
        updated.updatedAt = .now
        drafts[index] = updated
    }

    func draft(byID id: UUID) -> ScanDraft? {
        drafts.first(where: { $0.id == id })
    }

    // MARK: - Persistence-Glue

    func loadState() {
        repository.setCurrentAccount(AccountStore.shared.currentAccountID)
        let loaded = repository.loadDrafts(legacyKey: draftsKey)
        apply(loaded)
    }

    /// Wird nach einem Account-Wechsel gerufen — Cache invalidieren +
    /// Drafts des neuen Accounts laden.
    func reloadForCurrentAccount() {
        repository.invalidateCache()
        loadState()
    }

    private func apply(_ loaded: [ScanDraft]) {
        isApplyingStoredState = true
        drafts = loaded
        isApplyingStoredState = false
    }

    private func scheduleSave() {
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveDrafts()
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func saveDrafts() {
        repository.setCurrentAccount(AccountStore.shared.currentAccountID)
        repository.persistDrafts(drafts, key: draftsKey)
    }
}
