import SwiftUI
import Vision
import VisionKit
import UIKit

extension ScanImportView {
    func releaseScanWorkingImages() {
        session.releaseWorkingImages()
    }

    func selectScanMode(_ mode: ScanMode) {
        // Mode-Auswahl läuft für Vokabelliste UND Freier Text identisch:
        // `scanModeOverride` wird gesetzt, die Card-Selection reagiert
        // darauf (Checkmark). Unterschied erst später — wenn der Nutzer
        // ein Bild gewählt hat und `recognizeText(from:)` aufgerufen
        // wird: dort divergiert der Pfad. `.list` nimmt die OCR+AI-
        // Pipeline, `.text` routet in den Claude-Vision-Flow. So bleibt
        // das UX vor dem Aufnehmen komplett konsistent („exakt wie bei
        // Vokabel-Scan"), nur der Recognition-Algorithmus ist spezifisch.
        guard activeScanMode != mode else { return }

        scanModeOverride = mode

        if lastRecognizedBoxes.isEmpty {
            importMessage = mode.introMessage
            reviewSummary = "Der Scan ist jetzt auf \(mode.title.lowercased()) eingestellt."
            return
        }

        reprocessLastRecognizedScan()
    }

    func reprocessLastRecognizedScan() {
        guard !lastRecognizedBoxes.isEmpty else { return }
        let analysis = analyzeRecognizedScan(
            from: lastRecognizedBoxes,
            preferredMode: scanModeOverride
        )
        applyRecognizedScanAnalysis(analysis, appending: false)
    }

    func handleSelectedImages(_ images: [UIImage]) {
        guard !images.isEmpty else {
            shouldAppendNextScan = false
            return
        }

        // „Freier Text" analysiert pro Flow genau ein Bild (Claude-Vision-
        // Call). Multi-Select aus der Galerie ist hier nicht sinnvoll —
        // wir nehmen das erste Bild und ignorieren den Rest.
        if activeScanMode == .text {
            handleSelectedImage(images[0])
            return
        }

        // Single-Image-Flow: unverändert.
        if images.count == 1 {
            handleSelectedImage(images[0])
            return
        }

        // **Multi-Capture-Review-Flow** (User-Spec 2026-04-22 Abend VI):
        // statt sofort eine asynchrone Sequenz-Verarbeitung über alle
        // Bilder zu starten (vorheriges Verhalten — UI dead, Captures
        // lost), präsentieren wir den Multi-Capture-Review-Screen.
        // Dort wählt der User ein Bild und tippt „Überprüfen".
        // Die Captures bleiben in `session.capturedItems` erhalten,
        // bis der User sie explizit verwirft.
        //
        // Architektur-Hinweis: die alten `pendingBatchImages` /
        // `batchThumbnails` / `batchTotalCount` werden nicht mehr
        // gefüllt — die haben einen Auto-Sequenz-Pfad in
        // `processNextBatchImage()` getriggert, der genau die
        // 10-Claude-Vision-Calls-Hängerei verursacht hat.
        let now = Date()
        let newItems = images.enumerated().map { idx, img in
            CapturedScanItem(
                originalImage: img,
                createdAt: now.addingTimeInterval(Double(idx) * 0.001)
            )
        }
        session.capturedItems = newItems
        session.selectedCapturedItemID = newItems.first?.id
        // Sicherheits-Reset alter Batch-Felder, damit kein Reststate
        // den UI-Zweig in `ScanImportView+Screen` triggert.
        session.pendingBatchImages = []
        session.batchThumbnails = []
        session.batchTotalCount = 0
        session.batchCurrentIndex = 0
        session.batchCompleted = false
        session.isShowingMultiCaptureReview = true
    }

    /// Wird vom `MultiCaptureReviewView`-„Überprüfen"-CTA aufgerufen:
    /// startet den bestehenden Single-Image-Pfad auf dem ausgewählten
    /// Capture und markiert ihn als analysiert. Die übrigen Captures
    /// bleiben in `session.capturedItems` erhalten — der User kann
    /// jederzeit zurück und ein anderes Bild wählen.
    func reviewSelectedCapturedItem(_ item: CapturedScanItem) {
        if let idx = session.capturedItems.firstIndex(where: { $0.id == item.id }) {
            session.capturedItems[idx].status = .analyzed
        }
        session.isShowingMultiCaptureReview = false
        // Sequenzieller Scan ist hier explizit AUS — wir behandeln
        // genau dieses eine Bild wie ein Single-Capture.
        shouldAppendNextScan = false
        handleSelectedImage(item.originalImage)
    }

    /// Vom „Mehr aufnehmen"-Eintrag im Multi-Review-Menü: schließt
    /// den Review und öffnet den Scanner wieder; bestehende Captures
    /// bleiben erhalten.
    func resumeScanningFromMultiReview() {
        session.isShowingMultiCaptureReview = false
        // Den Scanner wieder öffnen — wir signalisieren das via
        // `selectedScanInputMethod`. Caller-View beobachtet das.
        session.selectedScanInputMethod = .camera
    }

    /// Vom „Alle verwerfen"-Eintrag im Multi-Review-Menü: leert die
    /// Capture-Sammlung **explizit** (User-Aktion, nicht still).
    func discardAllMultiCaptures() {
        session.capturedItems = []
        session.selectedCapturedItemID = nil
        session.isShowingMultiCaptureReview = false
    }

    // MARK: - Galerie-Mehrbild-Review (User-Spec 2026-04-23 nachmittags)

    /// Eigener Pfad für Galerie-Mehrfach-Auswahl. Vorher landeten
    /// Galerie-Images im selben `handleSelectedImages`-Pfad wie
    /// Camera-Multi-Shot — das hat zu falschen Reviews geführt
    /// (kein per-image-State, globaler `optimizedVariant` für alle).
    /// Jetzt: per-image-State in `session.galleryReviewItems`,
    /// neue View mit Big-Preview + Per-Bild-Aktionen.
    func handleSelectedImagesFromGallery(_ images: [UIImage]) {
        guard !images.isEmpty else { return }

        // FreeText-Modus + Single-Image bleiben am alten Pfad — keine
        // semantische Änderung dort.
        if activeScanMode == .text || images.count == 1 {
            handleSelectedImage(images[0])
            return
        }

        // Reihenfolge erhalten — Index 0 ist das ERSTE vom Picker
        // gelieferte Bild.
        let items = images.enumerated().map { idx, img in
            GalleryReviewItem(sourceIndex: idx, originalImage: img)
        }
        session.galleryReviewItems = items
        session.selectedGalleryItemID = items.first?.id
        // Saubere Trennung: alte Batch-Felder leer halten, damit kein
        // Auto-Sequenz-Pfad ausgelöst wird.
        session.pendingBatchImages = []
        session.batchThumbnails = []
        session.batchTotalCount = 0
        session.batchCurrentIndex = 0
        session.batchCompleted = false
        session.isShowingGalleryReview = true
    }

    /// Wird vom `GalleryMultiImageReviewView` als `onSubmitAll`-
    /// Callback gerufen. Sammelt die finalen Bilder (optimiert oder
    /// original) und reicht sie an die existierende Batch-Verarbeitungs-
    /// Pipeline (`pendingBatchImages`/`processNextBatchImage`) weiter,
    /// genau wie der frühere `handleSelectedImages`-Multi-Pfad.
    func submitGalleryReviewToAnalysis(_ submittedItems: [GalleryReviewItem]) {
        session.isShowingGalleryReview = false
        guard !submittedItems.isEmpty else { return }
        let finalImages = submittedItems
            .sorted { $0.sourceIndex < $1.sourceIndex }
            .map(\.finalImage)

        // **Bug-Fix 2026-04-24 (Multi-Image-Submit)**: vorher rief diese
        // Methode am Ende `handleSelectedImage(finalImages[0])` auf —
        // das öffnet den Preparation-/„Bild prüfen"-Sheet erneut für
        // das erste Bild und User landet wieder im Single-Image-Review.
        //
        // Korrekt: für ALLE Bilder den `processNextBatchImage`-Pfad
        // simulieren, der die Preparation-Sheet überspringt und direkt
        // `recognizeText` aufruft. Wir initialisieren den Batch-State
        // genau wie der historische Multi-Image-Pfad und starten das
        // erste Bild SOFORT in `recognizeText`.
        session.pendingBatchImages = Array(finalImages.dropFirst())
        session.batchTotalCount = finalImages.count
        session.batchCurrentIndex = 1
        session.batchThumbnails = finalImages.map { img in
            let maxEdge: CGFloat = 120
            let scale = min(maxEdge / img.size.width, maxEdge / img.size.height, 1.0)
            let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
        }
        // Optimierungs-Status für die Sequenz aufräumen — das
        // Galerie-Review hat schon optimiert.
        session.galleryReviewItems = []
        session.selectedGalleryItemID = nil

        // **Direkt-Pfad** (skip preparation sheet): erstes Bild als
        // Selection-State setzen + sofort `recognizeText`. Identische
        // Logik zu `processNextBatchImage()`. Die folgenden Bilder
        // verarbeitet die bestehende Recognition-Schleife dann
        // automatisch via `processNextBatchImage()` — keine
        // Sheet-Wiedervorlage.
        let firstImage = finalImages[0]
        if !shouldAppendNextScan {
            session.discardDraftForReplacement(
                activeScanMode: activeScanMode,
                currentListName: listName,
                fallbackListName: listStore?.suggestedListName(from: scanDateBaseName) ?? scanDateBaseName
            )
        }
        let selectionState = ScanImageLifecycle.makeSelectedImageState(
            from: firstImage,
            sourcePath: nil,
            maxAnalysisLongEdge: Self.maxOCRLongEdge,
            maxPreviewLongEdge: Self.maxPreviewLongEdge,
            normalizeForProcessing: { image, maxLongEdge in
                normalizedImageForProcessing(image, maxLongEdge: maxLongEdge)
            },
            downscaledForDisplay: { image, maxLongEdge in
                downscaledImageForDisplay(image, maxLongEdge: maxLongEdge)
            }
        )
        ensureSuggestedListName()
        session.applySelectedImageState(selectionState)
        // Append-Modus AN, damit nachfolgende Recognition-Resultate
        // an die Liste angehängt werden statt sie zu ersetzen.
        shouldAppendNextScan = true
        recognizeText(from: selectionState.analysisImage)
    }

    /// Async-Helper für den Galerie-View: berechnet Quality + empfohlenes
    /// Profile pro Item. Wird aus dem View per `task`-Modifier aufgerufen.
    func analyzeGalleryItemQuality(_ item: GalleryReviewItem) async -> (report: ImageQualityAnalyzer.Report, recommendedProfile: ImageQualityAnalyzer.EnhancementProfile?) {
        let report = await ImageQualityAnalyzer.analyzeAsync(
            image: item.originalImage,
            rectangleMetrics: nil,
            hints: .init(isTextDense: false)
        )
        let profile = ImageQualityAnalyzer.EnhancementProfile.recommended(for: report.issues)
        return (report, profile)
    }

    /// Async-Helper für den Galerie-View: führt die Optimierung aus.
    func optimizeGalleryItem(_ item: GalleryReviewItem) async -> UIImage? {
        let profile = item.recommendedProfile
            ?? ImageQualityAnalyzer.EnhancementProfile.recommended(for: item.qualityReport?.issues ?? [])
        return await ImageEnhancer.optimizeAsync(item.originalImage, profile: profile)
    }

    func processNextBatchImage() {
        guard !session.pendingBatchImages.isEmpty else {
            session.batchTotalCount = 0
            session.batchCurrentIndex = 0
            return
        }

        let nextImage = session.pendingBatchImages.removeFirst()
        session.batchCurrentIndex = session.batchTotalCount - session.pendingBatchImages.count

        shouldAppendNextScan = true

        let selectionState = ScanImageLifecycle.makeSelectedImageState(
            from: nextImage,
            sourcePath: nil,
            maxAnalysisLongEdge: Self.maxOCRLongEdge,
            maxPreviewLongEdge: Self.maxPreviewLongEdge,
            normalizeForProcessing: { image, maxLongEdge in
                normalizedImageForProcessing(image, maxLongEdge: maxLongEdge)
            },
            downscaledForDisplay: { image, maxLongEdge in
                downscaledImageForDisplay(image, maxLongEdge: maxLongEdge)
            }
        )
        session.applySelectedImageState(selectionState)

        // Skip preparation sheet — auto-analyze
        recognizeText(from: selectionState.analysisImage)
    }

    /// Pre-Processing-Pipeline für Galerie-Bilder im FreeText-Modus —
    /// symmetrisch zu `SmartScannerView.runProcessing`. Läuft auf
    /// Background-Queues (alle Sub-Aufrufe sind `async`) und liefert
    /// das refinierte Bild zurück.
    ///
    /// Schritte:
    ///   1. `TextDensityDetector` — Screenshot/Menü-Erkennung
    ///   2. `SmartDocumentProcessor` — Perspektivkorrektur +
    ///      profil-spezifisches Enhancement (`textDense` vs
    ///      `freierText`)
    ///   3. `ImageQualityAnalyzer` — Report (nur Debug-Log, blockiert
    ///      den Flow nicht; Quality-Banner erscheint später im
    ///      Review-Stage)
    ///   4. Optional `SmartTextRegionDetector` — wenn der User das
    ///      Smart-Region-Crop-Opt-in eingeschaltet hat
    ///   5. **Auto-Optimization** — symmetrisch zur Kamera-FreeText-
    ///      Pipeline (`SmartScannerView.runBackgroundOptimization`):
    ///      wenn die Quality-Issues ein `EnhancementProfile` empfehlen
    ///      und die Optimierung einen **deutlichen** Score-Boost
    ///      bringt (> 0.15), wird das optimierte Bild still
    ///      übernommen, bevor Claude-Vision es sieht. Schwächere
    ///      Improvements bleiben ungenutzt — wir wollen den User nicht
    ///      überraschen, wenn der Gewinn nicht lohnt.
    ///
    /// Im Fehlerfall (Decode-Probleme, Cancellation) gibt die Methode
    /// das Original zurück, damit der User nie ein leeres Bild sieht.
    @MainActor
    func runFreeTextGalleryPipeline(raw: UIImage) async -> UIImage {
        let dense = await TextDensityDetector.isTextDenseAsync(raw)
        let config: SmartDocumentProcessor.Config = dense ? .textDense : .freierText

        let result = await SmartDocumentProcessor.processAsync(
            raw,
            config: config,
            fallbackQuad: nil
        )

        let report = await ImageQualityAnalyzer.analyzeAsync(
            image: result.image,
            rectangleMetrics: result.rectangleMetrics,
            hints: .init(isTextDense: dense)
        )
        #if DEBUG
        print("📷 [FreeText-Gallery-Pipeline] dense=\(dense) \(report.debugSummary)")
        #endif

        var pipelineImage = result.image
        if ScanSettings.smartRegionCropEnabled {
            if let cropped = await SmartTextRegionDetector.detectCropAsync(pipelineImage) {
                #if DEBUG
                print("✂️ [FreeText-Gallery-Pipeline] smart-region crop applied")
                #endif
                pipelineImage = cropped
            }
        }

        // **Auto-Optimization-Pass** (Feature D) — gleicher Algorithmus
        // wie `SmartScannerView.runBackgroundOptimization` für Kamera-
        // Bilder, hier aber headless (kein User-Vorschlag), weil
        // Galerie→FreeText direkt in Claude-Vision landet. Wir nutzen
        // deshalb die strengere FreeText-Auto-Apply-Schwelle (> 0.15):
        // alles darunter bleibt unangetastet, weil der Score-Gewinn
        // das Risiko einer Over-Enhancement (Contrast-Clipping,
        // Glow-Artefakte) nicht aufwiegt.
        pipelineImage = await autoOptimizeIfWorthwhile(
            base: pipelineImage,
            baseReport: report,
            rectangleMetrics: result.rectangleMetrics,
            denseFlag: dense
        )

        return pipelineImage
    }

    /// Background-Pass: optimiert das Bild mit dem aus den Issues
    /// empfohlenen `EnhancementProfile`, misst das Delta, und ersetzt
    /// das Original **nur**, wenn der Score-Gewinn groß genug ist
    /// (strenger FreeText-Auto-Apply-Threshold > 0.15).
    ///
    /// Warum eigene kleine Funktion statt inline in der Pipeline?
    ///   • Lesbarkeit: die Pipeline-Schritte bleiben überschaubar.
    ///   • Spätere Wiederverwendung: wenn wir den Auto-Opt-Pass in
    ///     andere Gallery-Flows einbauen (Dokument-Scan aus Galerie),
    ///     hängen wir ihn hier ab.
    @MainActor
    private func autoOptimizeIfWorthwhile(
        base: UIImage,
        baseReport: ImageQualityAnalyzer.Report,
        rectangleMetrics: ImageQualityAnalyzer.RectangleMetrics?,
        denseFlag: Bool
    ) async -> UIImage {
        let recommended = ImageQualityAnalyzer.EnhancementProfile.recommended(for: baseReport.issues)

        let optimized = await ImageEnhancer.optimizeAsync(base, profile: recommended)

        let optimizedReport = await ImageQualityAnalyzer.analyzeAsync(
            image: optimized,
            rectangleMetrics: rectangleMetrics,
            hints: .init(isTextDense: denseFlag)
        )

        let improvement = optimizedReport.overallScore - baseReport.overallScore

        #if DEBUG
        print(String(
            format: "🪄 [FreeText-Gallery-AutoOpt] profile=%@ improvement=%+.3f (base=%.2f → opt=%.2f)",
            recommended.debugLabel, improvement,
            baseReport.overallScore, optimizedReport.overallScore
        ))
        #endif

        // Strenge Schwelle: nur übernehmen, wenn die Verbesserung
        // spürbar ist. Alles unter 0.15 lassen wir das Original —
        // Claude-Vision kommt mit mittelmäßigen Bildern meist gut
        // klar; ein Over-Enhanced-Bild mit verschobener Tonalität
        // dagegen kann die Szene-Interpretation stören.
        guard improvement > 0.15 else {
            #if DEBUG
            print("🪄 [FreeText-Gallery-AutoOpt] kept original — improvement below FreeText threshold (0.15)")
            #endif
            return base
        }

        #if DEBUG
        print("🪄 [FreeText-Gallery-AutoOpt] applied — \(recommended.debugLabel) (+\(String(format: "%.2f", improvement)))")
        #endif
        return optimized
    }

    func handleSelectedImage(_ image: UIImage?, sourcePath: String? = nil) {
        guard let image else {
            shouldAppendNextScan = false
            return
        }

        if !shouldAppendNextScan {
            session.discardDraftForReplacement(
                activeScanMode: activeScanMode,
                currentListName: listName,
                fallbackListName: listStore?.suggestedListName(from: scanDateBaseName) ?? scanDateBaseName
            )
        }

        let selectionState = ScanImageLifecycle.makeSelectedImageState(
            from: image,
            sourcePath: sourcePath,
            maxAnalysisLongEdge: Self.maxOCRLongEdge,
            maxPreviewLongEdge: Self.maxPreviewLongEdge,
            normalizeForProcessing: { image, maxLongEdge in
                normalizedImageForProcessing(image, maxLongEdge: maxLongEdge)
            },
            downscaledForDisplay: { image, maxLongEdge in
                downscaledImageForDisplay(image, maxLongEdge: maxLongEdge)
            }
        )
        ensureSuggestedListName()
        session.applySelectedImageState(selectionState)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard manualCropSession == nil else { return }
            showingScanPreparation = true
        }
    }

    func recognizeText(from image: UIImage) {
        // .text-Mode läuft NICHT durch die OCR/AI-Scan-Pipeline — stattdessen
        // direkt in den Claude-Vision-„Freier Text"-Flow. Wir divergieren
        // hier am Eintrittspunkt, nachdem der Nutzer dieselbe Auswahl-
        // Mechanik wie bei Vokabel-Scan durchlaufen hat (Mode-Card + Kamera/
        // Galerie + Preparation-Sheet inkl. Crop). Die komplette Recognition-
        // Session (isRecognizingImage, scanRuntimeStage, progress-feedback)
        // bleibt abgeschaltet — die neue View managed ihr eigenes Loading-UI.
        //
        // Präsentation via `.fullScreenCover(item:)` mit einem Identifiable-
        // Wrapper: SwiftUI koordiniert das Chaining mit dem noch dismissenden
        // Preparation-Sheet automatisch korrekt. Ein explizites
        // `DispatchQueue.main.asyncAfter` hier hatten wir früher — das
        // erzeugte aber Remounts, weil die Binding-Änderung nach dem Defer
        // schon in einer anderen Body-Generation landete (→ `.task` der
        // Processing-View ran zweimal, jeweils cancelled, Nutzer sah nur
        // die Fehler-Alert). Das Setzen des Items reicht, keine Timer.
        if activeScanMode == .text {
            #if DEBUG
            print("🧠 [FreeText] flow started — image=\(Int(image.size.width))×\(Int(image.size.height)) px")
            #endif
            // **Pipeline vor Claude-Call**: Symmetrisch zur Kamera-
            // Pipeline in `SmartScannerView.runProcessing`. Läuft nach
            // der Preparation-Sheet-Bestätigung, damit der User manuell
            // croppen/bearbeiten kann, bevor die Pipeline greift. Die
            // Pipeline-Schritte sind alle async + Error-tolerant: bei
            // Problemen fällt die Methode auf das Original-Image
            // zurück, sodass der Flow nie stehenbleibt.
            Task { @MainActor in
                let refined = await runFreeTextGalleryPipeline(raw: image)
                #if DEBUG
                print("🧠 [FreeText] navigating to processing")
                #endif
                freierTextPendingImage = FreierTextPendingImage(
                    image: refined,
                    inputMethod: session.selectedScanInputMethod
                )
            }
            return
        }

        #if DEBUG
        print("📷 [VocabList] Starting OCR/AI recognition — scanMode=.list, image=\(Int(image.size.width))×\(Int(image.size.height)) px")
        #endif

        isRecognizingImage = true
        feedbackPlayer.playScanStart()
        startScanProgressFeedback()
        // Start der Pipeline: erst die Bild-Vorbereitungs-Stage anzeigen.
        // Das ist **vor** OCR/AI die erste sichtbare Phase; die alte
        // Version sprang direkt auf `.ocrPreflight`, obwohl zwischen
        // Tap und OCR-Start das Bild noch skaliert/rotiert wird — das
        // erste wahrgenommene „halbe Sekunde Nichts" ist jetzt erklärt.
        scanRuntimeStage = .preparingImage
        importMessage = "Text wird erkannt..."
        let appendToExistingPreview = shouldAppendNextScan
        let aiConfiguredForScan = OpenAIResponsesScanAIClient.fromEnvironment() != nil
        let scanStart = CFAbsoluteTimeGetCurrent()
        releaseScanWorkingImages()

        Task(priority: .userInitiated) {
            let analysisImage = await preparedImageForAnalysis(from: image)
            let request = ScanRequest(
                image: analysisImage,
                preparedImage: nil,
                preferredMode: scanModeOverride,
                sourceLanguage: scanSourceLanguage
            )

            let providerResult = await makeScanAnalysisEngine().analyze(request) { stage in
                await MainActor.run {
                    scanRuntimeStage = stage
                }
            }

            // Engine fertig → Ergebnis verarbeiten. Das Parsing in
            // `applyRecognizedScanAnalysis` + das Preview-Aufbauen ist
            // für den User eine eigene sichtbare Phase („Vokabelpaare
            // werden erkannt"). Wir setzen die Stage explizit, damit
            // die Card nicht zwischen „KI analysiert" und „fertig"
            // springt, ohne dass der User merkt, warum.
            await MainActor.run {
                scanRuntimeStage = .parsingResults
            }

            await MainActor.run {
                let isBatchMode = session.batchTotalCount > 1
                if !isBatchMode {
                    isRecognizingImage = false
                    feedbackPlayer.playScanDone()
                    // Show summary screen for single scan too
                    session.batchTotalCount = 1
                }
                session.stopProgressFeedback()
                session.updateEvalReport(for: providerResult)
                session.updateProviderDebugInfo(
                    result: providerResult,
                    aiConfigured: aiConfiguredForScan,
                    durationMS: Int(((CFAbsoluteTimeGetCurrent() - scanStart) * 1000).rounded())
                )
                let gptFallbackInfoMessage = scanAIFallbackPopupMessage(
                    for: providerResult,
                    aiConfigured: aiConfiguredForScan
                )

                guard !providerResult.isEmpty else {
                    importMessage = providerResult.importMessage.isEmpty
                        ? "Der Text konnte aus dem Foto nicht erkannt werden."
                        : providerResult.importMessage
                    lastRecognizedBoxes = []
                    shouldAppendNextScan = false

                    // Continue batch even if one page fails
                    if !session.pendingBatchImages.isEmpty {
                        session.showToast("Seite \(session.batchCurrentIndex) konnte nicht erkannt werden")
                        processNextBatchImage()
                    } else if session.batchTotalCount > 1 {
                        isRecognizingImage = false
                        feedbackPlayer.playScanDone()
                        session.batchCompleted = true
                    } else if let gptFallbackInfoMessage {
                        session.presentScanAIInfo(gptFallbackInfoMessage)
                    }
                    return
                }

                lastRecognizedBoxes = providerResult.recognizedBoxes
                applyRecognizedScanAnalysis(
                    ScanReviewMapper.makeAnalysisResult(from: providerResult),
                    appending: appendToExistingPreview
                )
                shouldAppendNextScan = false
                if let gptFallbackInfoMessage {
                    session.presentScanAIInfo(gptFallbackInfoMessage)
                }

                // Continue batch if more images queued
                if !session.pendingBatchImages.isEmpty {
                    processNextBatchImage()
                } else {
                    // Analysis complete — show summary screen
                    if isBatchMode {
                        isRecognizingImage = false
                        feedbackPlayer.playScanDone()
                    }
                    session.batchCompleted = true
                }
            }
        }
    }
}
