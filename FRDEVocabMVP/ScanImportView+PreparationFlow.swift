import SwiftUI
import UIKit

extension ScanImportView {
    func confirmListNameEntry() {
        listName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        isListNameFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        withAnimation(.easeInOut(duration: 0.12)) {
            isListNamePulseActive = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeInOut(duration: 0.16)) {
                isListNamePulseActive = false
            }
        }
    }

    func openCameraScanner() {
        guard !isRecognizingImage else { return }
        showingAdditionalScanOptions = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingCamera = true
        }
    }

    func restartCurrentScan() {
        // **Bug-Fix 2026-06-09** — Beide Guards brachen vorher stumm ab.
        // Nach einem KI-Fehler tippte man auf „Nochmal versuchen", es
        // passierte nichts, und der Screen blieb leer zurück (User-
        // Bugreport): `prepareForRescanDisplay()` hatte die Vorschau
        // schon geleert, der Neustart lief aber nie an. Jetzt wird der
        // Grund benannt, statt ihn zu verschlucken.
        guard !isRecognizingImage else {
            presentScanAIInfo("Die Analyse läuft noch. Bitte einen Moment warten.")
            return
        }
        // `originalScanImage` explizit als letzte Rückfallebene:
        // `releaseWorkingImages()` behält es bewusst genau für diesen
        // Fall, während `preparedScanImage` verworfen wird.
        guard let imageToAnalyze = scanPreparationPreviewImage
                ?? selectedImage
                ?? originalScanImage else {
            presentScanAIInfo("Das Bild steht nicht mehr zur Verfügung. Bitte neu scannen.")
            return
        }
        shouldAppendNextScan = false
        prepareForRescanDisplay()
        // Abschluss-Zustand des fehlgeschlagenen Laufs zurücksetzen —
        // sonst bleibt der Screen in der Ergebnis-Ansicht ohne Ergebnis
        // hängen, also leer.
        session.batchCompleted = false
        recognizeText(from: imageToAnalyze)
    }

    func retryCurrentScanAfterAIAlert() {
        isShowingScanAIInfoAlert = false
        scanAIInfoMessage = ""
        restartCurrentScan()
    }

    func prepareForRescanDisplay() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        focusedReviewField = nil
        previewEditSyncWorkItem?.cancel()
        previewEditSyncWorkItem = nil
        hasPendingPreviewEdits = false
        session.prepareForRescanDisplay()
    }

    var scanPreparationPreviewImage: UIImage? {
        if usePreparedScanImage {
            return preparedScanImage ?? originalScanImage
        }
        return originalScanImage ?? preparedScanImage
    }
}
