import SwiftUI

extension ScanImportView {

    // MARK: - Neuer Einstiegspunkt (Target-Choice-Flow)

    /// **Neuer Button-Handler** für „Jetzt importieren".
    /// Berechnet die Items aus dem Review, fragt dann via Sheet, wohin
    /// (neue Liste vs. bestehende Liste) importiert werden soll. Erst
    /// danach läuft entweder der bisherige `importScannedText()`-Flow
    /// (neue Liste) oder der neue Merge-Pfad (bestehende Liste).
    func beginImportTargetChoice() {
        commitPreviewEditsAndSyncImportText()
        let items = collectImportableItems()
        guard !items.isEmpty else {
            importMessage = "Keine Paare erkannt. Nutze pro Zeile ein Trennzeichen wie `=` oder `→`."
            return
        }
        pendingImportItems = items
        isShowingImportTargetChoice = true
    }

    /// **Phase B (2026-05-20)** — Entry-Variante, die das Ziel-Wahl-Sheet
    /// AUCH dann öffnet, wenn 0 importable Pairs existieren (aber >0 Pairs
    /// insgesamt) — damit der „Als Entwurf"-Pfad erreichbar bleibt.
    /// Der Neue-/Bestehende-Liste-Pfad nutzt weiterhin nur
    /// `pendingImportItems` (= importable), die hier leer sein dürfen;
    /// `saveAsDraft()` greift dagegen direkt auf ALLE `session.previewPairs`
    /// zu. `commitPreviewEditsAndSyncImportText()` zuerst (wie im Original),
    /// damit in-progress Edits in den previewPairs landen.
    func beginImportTargetChoiceOrDraft() {
        commitPreviewEditsAndSyncImportText()
        let pairs = previewPairs
        guard !pairs.isEmpty else { return }
        pendingImportItems = collectImportableItems()
        isShowingImportTargetChoice = true
    }

    /// **Phase B (2026-05-20)** — Sichert den aktuellen Scan-Review als
    /// `ScanDraft`: ALLE `previewPairs` (auch `isImportable == false`,
    /// Toggle-State konserviert) plus komprimierte Quellbilder. In-place:
    /// Toast + State-Reset, KEIN `goHome()` (User bleibt im Scan-Bereich).
    ///
    /// Non-private (wie die übrigen ImportFlow-Funktionen), weil der
    /// Aufruf cross-file aus `+Presentations` kommt — `private` wäre
    /// datei-scoped und unsichtbar.
    func saveAsDraft() {
        let pairs = session.previewPairs

        guard !pairs.isEmpty else {
            appDebugLog("⚠️ [ScanDraft] saveAsDraft called with empty pairs, abort")
            return
        }

        let draftID = UUID()

        // **Phase B v2 (2026-05-20)** — Bild-Quelle: Multi-Capture nutzt
        // `capturedItems`; ein Single-Scan füllt die NIE (das Bild liegt in
        // `originalScanImage`, das `releaseWorkingImages` bewusst behält) →
        // Fallback. KRITISCHE REIHENFOLGE: Bilder zuerst persistieren, BEVOR
        // der State-Reset `originalScanImage`/`capturedItems` wegräumt.
        let captureImages: [UIImage] =
            session.capturedItems.isEmpty
            ? [session.originalScanImage].compactMap { $0 }
            : session.capturedItems.map(\.originalImage)

        var imageFilenames: [String] = []
        for (idx, image) in captureImages.enumerated() {
            do {
                let filename = try ScanDraftImageStore.save(
                    image,
                    draftID: draftID,
                    index: idx
                )
                imageFilenames.append(filename)
            } catch {
                appDebugLog("⚠️ [ScanDraft] image save failed for index \(idx): \(error)")
                // Soft-Fail: Draft wird auch ohne Bild gespeichert.
            }
        }

        let draft = ScanDraft(
            id: draftID,
            title: ScanDraft.autoTitle(at: .now),
            createdAt: .now,
            updatedAt: .now,
            previewPairs: pairs,
            imageFilenames: imageFilenames
        )

        ScanDraftStore.shared.add(draft)
        appDebugLog("📁 [ScanDraft] saved draft \(draftID) with \(pairs.count) pairs, \(imageFilenames.count) images")

        // In-place Feedback.
        showDraftSavedToast = true

        // `capturedItems` + Selection explizit leeren — der Standard-Reset
        // (applyResetState) fasst `capturedItems` NICHT an.
        session.capturedItems = []
        session.selectedCapturedItemID = nil

        // Standard-Reset über den etablierten Wrapper (korrekte Signatur).
        resetScanInputAfterSuccessfulImport(keepingListName: false)
    }

    /// Sammelt die importierbaren Items aus dem aktuellen Review-State —
    /// **gleiche** Logik wie der bestehende `importScannedText()`, nur
    /// ausgelagert, damit beide Pfade identisch importable items haben.
    func collectImportableItems() -> [VocabularyItem] {
        previewPairs
            .filter(\.isImportable)
            .compactMap { pair in
                scanVocabularyItemFactory.makeVocabularyItem(
                    french: pair.french,
                    german: pair.german,
                    cardType: pair.cardType,
                    sourceLanguage: scanSourceLanguage,
                    wordClass: pair.wordClass
                )
            }
    }

    // MARK: - Pfad 1: neue Liste (bisheriger Flow, unverändert)

    /// Pfad „In neue Liste importieren" — **erweitert** (User-Spec
    /// 2026-04-23 morgens): zeigt zuerst eine Namensabfrage. Erst
    /// danach läuft der bestehende `importScannedText()`-Flow.
    /// Wird vom `ImportTargetChoiceSheet`-Callback gerufen.
    func proceedWithNewListImport() {
        isShowingNewListNameSheet = true
    }

    /// Wird vom `NewListNameSheet`-Callback gerufen, sobald der User
    /// einen Namen gewählt hat (entweder „Liste erstellen" mit Eingabe
    /// oder „Automatisch benennen" mit Zeitstempel). Schreibt den
    /// Namen in den `session.listName` und triggert den bestehenden
    /// Import-Flow.
    func handleNewListNameChosen(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // `listName` ist der gemeinsame Eingabe-Slot, den
        // `importScannedText()` ohnehin schon liest. Wir setzen ihn
        // auf den vom User bestätigten Namen, damit der bestehende
        // Code-Pfad ohne weitere Änderungen den richtigen Namen nutzt.
        session.listName = trimmed
        importScannedText()
    }

    // MARK: - Pfad 2: bestehende Liste (neuer Merge-Pfad)

    /// Pfad „Zu bestehender Liste hinzufügen" — Schritt 1: Picker zeigen.
    /// Gerufen aus `ImportTargetChoiceSheet`-Callback.
    func showExistingListPicker() {
        isShowingExistingListPicker = true
    }

    /// Pfad „Zu bestehender Liste hinzufügen" — Schritt 2: Plan
    /// berechnen, dann je nach Konfliktlage Conflict-Review zeigen
    /// oder direkt apply.
    func handleExistingListChosen(_ listID: UUID) {
        let activeListStore = listStore ?? ensureListStoreReady()
        guard let targetList = activeListStore.customLists.first(where: { $0.id == listID }) else {
            importMessage = "Liste nicht gefunden."
            return
        }
        pendingTargetListID = listID
        let plan = VocabularyListMergePlanner.computePlan(
            incoming: pendingImportItems,
            existingItems: targetList.items
        )
        pendingMergePlan = plan
        if plan.requiresUserDecision {
            isShowingConflictReview = true
        } else {
            applyPendingMergeAndShowCompletion(targetListName: targetList.name)
        }
    }

    /// Conflict-Review-Sheet hat die Resolutions zurückgegeben.
    /// Schreibt sie in den Plan und applied.
    func handleConflictReviewConfirmed(_ resolvedConflicts: [ImportConflict]) {
        guard var plan = pendingMergePlan,
              let listID = pendingTargetListID,
              let targetList = (listStore ?? ensureListStoreReady())
                  .customLists.first(where: { $0.id == listID }) else {
            return
        }
        plan.conflicts = resolvedConflicts
        pendingMergePlan = plan
        applyPendingMergeAndShowCompletion(targetListName: targetList.name)
    }

    /// **Bug-Fix 2026-04-23 abends (Critical Import-Bug)**: vorher
    /// triggerte diese Methode den Apply synchron mit dem Sheet-
    /// Dismiss des Existing-List-Pickers — zwei iOS-Sheets in/out
    /// im selben Frame führten zu UI-Race + schwarzer Screen.
    /// Außerdem wurde Success angezeigt, BEVOR die Persistenz
    /// validiert war.
    ///
    /// Jetzt:
    ///   1. Sheet-Settle abwarten (0,4 s nach Caller-Dismiss)
    ///   2. Atomarer Apply via `applyMergePlan` (synchroner Save +
    ///      Post-Apply-Validierung im Store)
    ///   3. Bei Success → Completion zeigen
    ///   4. Bei Failure → klare Fehlermeldung, scan-input bleibt
    ///      erhalten, User bleibt handlungsfähig
    private func applyPendingMergeAndShowCompletion(targetListName: String) {
        guard let plan = pendingMergePlan, let listID = pendingTargetListID else { return }

        // Sheet-Settle: das vorherige Existing-List-Picker- bzw.
        // Conflict-Review-Sheet braucht ~0,3-0,4s zum Dismissen.
        // Vorher setzten wir `isShowingImportCompletion = true` im
        // selben Tick → SwiftUI versuchte zwei Sheets gleichzeitig
        // in/out zu animieren → schwarzer Screen / Rücksprung.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            performAtomicMergeApply(plan: plan, listID: listID, targetListName: targetListName)
        }
    }

    /// Eigentlicher Apply-Schritt — läuft NACH dem Sheet-Settle-Delay
    /// auf dem MainActor. Validiert das Ergebnis und entscheidet
    /// Success vs. Failure-Branch.
    private func performAtomicMergeApply(plan: MergePlan, listID: UUID, targetListName: String) {
        let activeListStore = listStore ?? ensureListStoreReady()
        let result = activeListStore.applyMergePlan(plan, toListWithID: listID)

        #if DEBUG
        appDebugLog("""
        📋 [applyPendingMerge] Result-Branch
           status=\(result.status)
           isSuccess=\(result.isSuccess)
           added=\(result.added) skipped=\(result.skipped) replaced=\(result.replaced)
        """)
        #endif

        guard result.isSuccess else {
            // **Failure-Pfad** (User-Spec): keine falsche Erfolgsmeldung,
            // keine Navigation, Daten erhalten, Fehler klar zeigen.
            let errorText: String = {
                switch result.status {
                case .targetListMissing:
                    return "Liste nicht gefunden. Bitte erneut wählen."
                case .persistenceMismatch(let expected, let actual):
                    return "Import fehlgeschlagen (erwartet \(expected), gespeichert \(actual)). Bitte erneut versuchen."
                case .success:
                    return ""   // unreachable
                }
            }()
            importMessage = errorText
            // Pendings BEHALTEN, damit der User es wiederholen kann.
            // Kein resetScanInput, kein isShowingImportCompletion.
            #if DEBUG
            appDebugLog("📋 [applyPendingMerge] FAILURE — Pendings erhalten, kein Completion-Wechsel.")
            #endif
            return
        }

        // **Success-Pfad** — alles validiert, sicher zu navigieren.
        importMessage = mergeResultMessage(result, targetListName: targetListName)
        importCompletionContext = ImportCompletionContext(
            importedCount: result.added,
            targetListID: listID,
            targetListName: targetListName,
            language: scanSourceLanguage,
            preferredDirection: scanSourceLanguage.defaultDirectionToGerman,
            cardType: dominantImportedCardType(in: pendingImportItems),
            importedItemIDs: pendingImportItems.map(\.id)
        )
        pendingImportItems = []
        pendingTargetListID = nil
        pendingMergePlan = nil
        resetScanInputAfterSuccessfulImport(keepingListName: false)
        feedbackPlayer.playStudyAchievement()
        isShowingImportCompletion = true
    }

    private func mergeResultMessage(_ result: MergeResult, targetListName: String) -> String {
        var parts: [String] = ["\(result.added) hinzugefügt"]
        if result.skipped > 0 {
            parts.append("\(result.skipped) bereits vorhanden")
        }
        if result.replaced > 0 {
            parts.append("\(result.replaced) ersetzt")
        }
        return "Zur Liste \(targetListName): " + parts.joined(separator: ", ")
    }

    // MARK: - Bestehender „neue Liste"-Flow (unverändert)

    func importScannedText() {
        commitPreviewEditsAndSyncImportText()
        let activeListStore = listStore ?? ensureListStoreReady()
        let items = pendingImportItems.isEmpty ? collectImportableItems() : pendingImportItems
        let importedItemIDs = items.map(\.id)
        let trimmedListName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetListID = activeListStore.ensureCustomList(
            named: trimmedListName.isEmpty ? activeListStore.suggestedListName(from: scanDateBaseName) : trimmedListName,
            collectionPreset: selectedCollectionPreset
        )
        let importedCount = activeListStore.importItems(
            items,
            preferredListID: targetListID,
            suggestedListName: trimmedListName.isEmpty ? scanDateBaseName : trimmedListName,
            collectionPreset: selectedCollectionPreset
        )

        if importedCount == 0 {
            importMessage = "Keine Paare erkannt. Nutze pro Zeile ein Trennzeichen wie `=` oder `→`."
            return
        }

        let targetListName = activeListStore.selectedList.name
        importMessage = "\(importedCount) Einträge in „\(targetListName)“ importiert."
        importCompletionContext = ImportCompletionContext(
            importedCount: importedCount,
            targetListID: targetListID,
            targetListName: targetListName,
            language: scanSourceLanguage,
            preferredDirection: scanSourceLanguage.defaultDirectionToGerman,
            cardType: dominantImportedCardType(in: items),
            importedItemIDs: importedItemIDs
        )
        // Pendings sauber zurücksetzen — falls dieser Pfad aus der
        // neuen Target-Choice-Sheet kam, halten wir keine Stale-Items.
        pendingImportItems = []
        resetScanInputAfterSuccessfulImport(keepingListName: false)
        feedbackPlayer.playStudyAchievement()
        isShowingImportCompletion = true
    }

    func dominantImportedCardType(in items: [VocabularyItem]) -> CardType {
        let phraseCount = items.filter { $0.cardType == .phrases }.count
        let wordCount = items.count - phraseCount
        return phraseCount > wordCount ? .phrases : .words
    }

    func updateScanEvalReport(for result: ScanProviderResult) {
        session.updateEvalReport(for: result)
    }

    func resetScanInputAfterSuccessfulImport(keepingListName: Bool) {
        session.resetInputAfterSuccessfulImport(
            keepingListName: keepingListName,
            fallbackListName: listStore?.suggestedListName(from: scanDateBaseName) ?? scanDateBaseName
        )
    }

    func handleCompletionSelection(_ destination: AppScreen?) {
        guard let destination else {
            // "Ich übe später" — go home
            isShowingImportCompletion = false
            goHome()
            return
        }
        // Navigate to module — Import Completion stays as view state,
        // so "Zurück" from Training returns here automatically
        navigate(destination)
    }
}
