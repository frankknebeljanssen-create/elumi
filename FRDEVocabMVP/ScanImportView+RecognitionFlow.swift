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
        // wir nehmen das erste Bild und ignorieren den Rest. Ohne diese
        // Abzweigung würden die übrigen Bilder in `pendingBatchImages`
        // liegenbleiben und beim nächsten Vokabel-Scan fälschlich als
        // Batch-Reste auftauchen.
        //
        // **Pipeline-Symmetrie** (User-Wunsch „sollte alles analog
        // funktionieren"): Galerie-Bilder laufen durch **dieselbe**
        // Pre-Processing-Pipeline wie Kamera-Bilder. Die Pipeline
        // selbst läuft aber nicht hier, sondern in `recognizeText(...)`
        // — erst wenn der User im Preparation-Sheet bestätigt hat,
        // dass er **dieses** Bild analysieren will. Vorher hat das
        // Preparation-Sheet (Crop-Möglichkeit) das Vorrecht. So
        // vermeiden wir auch, dass die UI während der Pipeline mit
        // `isRecognizingImage = true` blockiert wird, was zu einem
        // Dead-End-Zustand führen könnte, falls der Task still
        // fehlschlägt.
        if activeScanMode == .text {
            handleSelectedImage(images[0])
            return
        }

        if images.count == 1 {
            handleSelectedImage(images[0])
            return
        }

        // Multi-select: queue batch, generate thumbnails, process first image normally
        session.pendingBatchImages = Array(images.dropFirst())
        session.batchTotalCount = images.count
        session.batchCurrentIndex = 1
        session.batchThumbnails = images.map { img in
            let maxEdge: CGFloat = 120
            let scale = min(maxEdge / img.size.width, maxEdge / img.size.height, 1.0)
            let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
        }
        handleSelectedImage(images[0])
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
                freierTextPendingImage = FreierTextPendingImage(image: refined)
            }
            return
        }

        #if DEBUG
        print("📷 [VocabList] Starting OCR/AI recognition — scanMode=.list, image=\(Int(image.size.width))×\(Int(image.size.height)) px")
        #endif

        isRecognizingImage = true
        feedbackPlayer.playScanStart()
        startScanProgressFeedback()
        scanRuntimeStage = .ocrPreflight
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
