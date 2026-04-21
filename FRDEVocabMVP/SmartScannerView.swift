import SwiftUI
import AVFoundation
import UIKit
import Vision
import Combine

/// Smart Scanner — Live-Kamera mit Rechteckerkennung, Guidance-Overlay,
/// Auto/Manual-Capture und Preview-Screen.
///
/// Flow:
/// 1. **Capture-Stage**: Live-Feed + Overlay-Rahmen (grau → grün) + dynamische
///    Hinweistexte + Auslöse-Button (im Manual-Modus) bzw. Auto-Capture bei
///    Stabilität (Auto-Modus).
/// 2. **Processing-Stage**: kurzer „Wird korrigiert…"-Spinner während
///    `SmartDocumentProcessor.processAsync(...)` läuft.
/// 3. **Preview-Stage**: korrigiertes Bild + „Neu aufnehmen"/„Verwenden".
///
/// Wird aus beiden Scan-Flows (Vokabel + Freier Text) genutzt. Das
/// Processing-Profil (`Config`) kommt vom Aufrufer.
struct SmartScannerView: View {
    /// Callback mit dem finalen (korrigierten) Bild + Diagnose-Metadata.
    /// Nur gesetzt wenn der Nutzer „Verwenden" tippt.
    let onUse: (UIImage, ImageQualityAnalyzer.Report?, UUID?) -> Void

    /// **Multi-Shot Callback** (User-Spec: nur in vocabularyList).
    /// Wird aufgerufen, wenn der User in der Vokabelliste mehrere
    /// Captures hintereinander gemacht und dann „Fertig" getippt hat.
    /// Nutzt denselben Pfad wie der Galerie-Multi-Select (Batch-Queue
    /// mit thumbnails + sequential processing).
    /// In FreeText nie aktiv — dort bleibt es immer single-shot.
    var onUseBatch: (([UIImage]) -> Void)? = nil
    /// Callback wenn der Nutzer abbricht (Close-Button oben rechts).
    /// Callback wenn der Nutzer abbricht (Close-Button oben rechts).
    let onCancel: () -> Void

    /// Capture-Profil — single source of truth für alle Use-Case-
    /// Unterschiede zwischen Dokument-Scan (Vokabelheft, Arbeitsblatt,
    /// Schulbuch) und Scene-Scan (Müslipackung, Poster, Zeitungsartikel).
    /// Steuert Auto-Capture, Live-Quad-Overlay, und (via
    /// `processorConfig`) die Post-Capture-Pipeline.
    ///
    /// **Binding statt let** (Feature C — Swipe-Switching): der User
    /// kann im Camera-Screen durch horizontale Wischen zwischen
    /// Vokabel- und FreeText-Modus wechseln. Damit die Mode-Änderung
    /// auch an den Parent-Screen (`ScanImportView`) zurückfließt,
    /// nutzen wir ein Binding — der Parent mirror'd den Wert in
    /// seinen `scanModeOverride`.
    @Binding var profile: ScanCaptureProfile

    /// Optional: Processor-Profil explizit überschreiben. Default kommt
    /// aus `profile.processorConfig` — in praxi nur nötig, wenn ein
    /// Aufrufer feinkörnig Padding/Enhancement justieren will, ohne das
    /// Capture-Profil zu wechseln. Nicht gesetzt → Profile-Default.
    var configOverride: SmartDocumentProcessor.Config? = nil

    /// Effektive Processor-Config, die in die Pipeline fließt.
    private var effectiveConfig: SmartDocumentProcessor.Config {
        configOverride ?? profile.processorConfig
    }

    // MARK: - State
    //
    // **AP1-Refactor**: vorher war der View-Stage ein separates @State
    // `enum Stage { .capture / .processing / .preview }` parallel zur
    // `ScanCaptureMachine.state`. Zwei Wahrheiten → Drift-Risiko bei
    // jedem neuen Feature. Jetzt leitet sich der View-State (sichtbare
    // Sub-Seite) aus `controller.captureMachine.state` ab.
    //
    // Der Controller lebt ebenfalls hier (vorher in `SmartScannerCaptureView`
    // als @StateObject) — damit kann der Machine-State außerhalb der
    // Capture-Sub-View überleben, was für die Processing/Preview-Phasen
    // nötig ist.

    /// Erkennungspräsentation — welche Sub-View sichtbar ist. Reine
    /// Projektion der Machine-States auf drei UI-Stages.
    private enum ViewState: Equatable {
        case capture      // idle / searching / candidate / locked / capturing / captureFailed
        case processing   // refining
        case preview      // reviewReady
    }

    private func viewState(from state: ScanCaptureState) -> ViewState {
        switch state {
        case .idle, .searching, .candidate, .locked, .capturing, .captureFailed:
            return .capture
        case .refining:
            return .processing
        case .reviewReady:
            return .preview
        }
    }

    @StateObject private var controller = SmartScannerController()

    // Default kommt vom Profil — FreeText startet **ohne** Auto-Capture,
    // weil Müslipackungen/Poster keine stabile Dokumentfläche haben und
    // Auto-Capture auf zufälligen Polygonen nervt. User kann weiter
    // manuell umschalten.
    @State private var autoCaptureEnabled: Bool = true

    /// Handle auf die laufende Processing-Pipeline. Wird beim Shutter
    /// gesetzt und beim Back-Button-Tap während der Processing-Phase
    /// gecancelt, damit der User nicht zwangsweise auf das Ergebnis
    /// einer Aufnahme warten muss, die er gar nicht mehr will.
    ///
    /// Cancellation ist in Swift cooperativ — `runProcessing` prüft an
    /// den `await`-Punkten via `Task.isCancelled` und bricht dann
    /// geordnet ab. Laufende CIImage-/Vision-Operationen werden nicht
    /// hart abgewürgt, aber ihr Output landet nirgends.
    @State private var processingTask: Task<Void, Never>?

    /// Text-Dense-Signal für die Processing-UI. Wird in `runProcessing`
    /// gesetzt, sobald `TextDensityDetector` das Bild klassifiziert hat —
    /// triggert den Hinweis „Text erkannt — optimierte Analyse" und
    /// relaxt den Qualitäts-Check (Skew/Size/Completeness sind bei
    /// Full-Frame-Captures ohnehin bedeutungslos).
    @State private var isTextDenseProcessing: Bool = false

    /// **Preview-Manual-Crop**: Resultat der vom User manuell
    /// angewendeten Crop-Geste im Preview-Stage. Überschreibt das
    /// pipeline-refinierte Bild für Anzeige + finales `onUse`. Wird
    /// bei „Neu aufnehmen" zurückgesetzt.
    ///
    /// Die Machine-State-Transition `reviewReady → reviewReady` ist
    /// nicht legal, deshalb halten wir den User-Crop als separate
    /// @State statt ihn in die Machine zu verdrahten. Die Machine-
    /// Payload (`corrected`) bleibt als Fallback und als Retake-Baseline.
    @State private var userCroppedImage: UIImage?
    @State private var showingCropSheet: Bool = false
    /// Capture-ID der letzten abgeschlossenen Photo-Verarbeitung.
    /// Wird in `runProcessing` gesetzt und an `onUse(...)` weitergereicht,
    /// damit Downstream (OCR/AI/Analyse) die gleiche ID benutzen kann
    /// wie unsere Capture-Identity-Logs.
    @State private var lastCaptureID: UUID? = nil

    /// **Multi-Shot Sammlung** für vocabularyList. Jeder Capture wird
    /// hier gesammelt; der User sieht im Capture-Stage-Footer einen
    /// Thumbnail-Strip + „Fertig"-Button. Nur in vocabularyList
    /// befüllt — in FreeText bleibt das Array leer und der Single-
    /// Shot-Pfad gewinnt.
    ///
    /// Lebt im Parent (SmartScannerView), damit die `runProcessing`-
    /// MainActor-Logik direkt darauf schreibt. Die Child-View
    /// (`SmartScannerCaptureView`) bekommt Read+Write-Zugang via
    /// `@Binding`.
    @State private var batchCapturedImages: [UIImage] = []
    /// Maximum für die Batch-Größe (UI-Sanity-Check). Apple-PHPicker
    /// erlaubt 10 — wir folgen demselben Limit.
    private let batchMaxImages: Int = 10

    /// Aktueller Quality-Report aus dem `Machine.reviewReady`-State.
    /// Wird an `onUse(...)` weitergereicht, damit die Analyse-Pipeline
    /// die Bewertung mitbekommt (z. B. niedrigere AI-Confidence-
    /// Schwelle bei `.poor`-Captures).
    private var currentReport: ImageQualityAnalyzer.Report? {
        if case .reviewReady(_, let report) = controller.captureMachine.state {
            return report
        }
        return nil
    }

    // MARK: - Auto-Optimierung (Hintergrund-Pass + Smart-Vorschlag)
    //
    // Wenn `runProcessing` mit der Quality-Analyse durch ist, läuft im
    // Hintergrund **ein adaptiv ausgewähltes EnhancementProfile** auf
    // dem korrigierten Bild. Wir vergleichen Original- und Optimiert-
    // Score; wenn die Verbesserung relevant ist, blenden wir eine
    // Smart-Vorschlags-Card unter dem Quality-Banner ein.
    //
    // **Mode-Logik** (Vokabel = konservativ, FreeText = aggressiv):
    //   • Verbesserung > 0.05 → Vorschlag (beide Profile)
    //   • Verbesserung > 0.15 UND Profil = .freeText → automatisch
    //     anwenden (User sieht kurz die Info-Pille)
    //
    // Der User kann jederzeit dismissen oder explizit anwenden.
    /// Ergebnis der Hintergrund-Optimierung (nil bis Background-Pass
    /// fertig oder Verbesserung zu klein).
    @State private var optimizedVariant: OptimizedVariant?
    /// `true` wenn der User die Optimierung angewendet hat — entweder
    /// per Tap auf „Auto optimieren" oder automatisch (FreeText +
    /// große Verbesserung).
    @State private var optimizationApplied: Bool = false

    /// Behälter für ein optimiertes Variant-Bild plus Bewertung.
    /// Lokal in der View — die Optimierung ist eine reine UI-
    /// Hilfsschicht und braucht nicht in die Machine.
    struct OptimizedVariant {
        let image: UIImage
        let report: ImageQualityAnalyzer.Report
        /// Score-Delta (`optimized.overallScore - original.overallScore`).
        /// Positiv = besser. Wir zeigen die Card erst ab > 0.05.
        let improvement: Double
        /// Welches Profil angewandt wurde (für die Anzeige in der Card
        /// und für Debug-Logs).
        let profile: ImageQualityAnalyzer.EnhancementProfile
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            let machineState = controller.captureMachine.state
            switch viewState(from: machineState) {
            case .capture:
                captureStage
            case .processing:
                if case .refining(let raw) = machineState {
                    processingStage(raw: raw)
                }
            case .preview:
                if case .reviewReady(let corrected, let report) = machineState {
                    previewStage(corrected: corrected, report: report)
                }
            }
        }
        .onAppear {
            controller.captureProfile = profile
            autoCaptureEnabled = (profile.defaultCaptureMode == .auto)
            controller.autoCaptureEnabled = autoCaptureEnabled
            controller.onCapture = { raw, frozenQuad, frozenAttentionBox, previewLayerSize, captureID in
                // Vorherige Task defensiv canceln — sollte nie passieren
                // (Button-Guard im Controller schließt Doppel-Captures
                // aus), aber schützt gegen sehr seltene Race-Conditions.
                processingTask?.cancel()
                processingTask = Task {
                    await runProcessing(
                        raw: raw,
                        frozenQuad: frozenQuad,
                        frozenAttentionBox: frozenAttentionBox,
                        previewLayerSize: previewLayerSize,
                        captureID: captureID
                    )
                }

                // **Refining-Timeout-Fallback** (User-Bug „wird
                // korrigiert hängt"): wenn die Processing-Pipeline
                // länger als 30 s in `.refining` bleibt (Vision-/
                // CoreImage-Hang, async-Deadlock), schubsen wir die
                // Machine in `.captureFailed`, damit der User die
                // Retry-Card sieht statt einer eingefrorenen UI.
                let captureGenSnapshot = captureID
                DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                    if case .refining = controller.captureMachine.state,
                       lastCaptureID == captureGenSnapshot {
                        #if DEBUG
                        print("❌ [Processing] Timeout after 30s — forcing failure (refining never finished, id=\(captureGenSnapshot.shortID))")
                        #endif
                        processingTask?.cancel()
                        controller.captureMachine.transition(to: .captureFailed(.captureFailed))
                    }
                }
            }
            controller.start()
        }
        .onDisappear {
            processingTask?.cancel()
            processingTask = nil
            controller.stop()
        }
    }

    // MARK: - Capture-Stage

    private var captureStage: some View {
        SmartScannerCaptureView(
            controller: controller,
            profile: profile,
            autoCaptureEnabled: $autoCaptureEnabled,
            onCancel: onCancel,
            onSwitchMode: { requested in
                handleModeSwitchRequest(to: requested)
            },
            batchCapturedImages: $batchCapturedImages,
            onFinalizeBatch: { finalizeBatch() }
        )
    }

    /// Sammelt-Bilder aus dem Multi-Shot-Buffer entweder als Single
    /// (`onUse`) oder als Batch (`onUseBatch`) raus. Leert den Buffer.
    private func finalizeBatch() {
        let images = batchCapturedImages
        batchCapturedImages = []
        guard !images.isEmpty else { return }
        if images.count == 1 {
            onUse(images[0], nil, lastCaptureID)
        } else if let batchHandler = onUseBatch {
            batchHandler(images)
        } else {
            // Defensiver Fallback: kein Batch-Handler registriert →
            // erstes Bild durchschieben (sollte nicht vorkommen, weil
            // ScanImportView den Handler immer setzt).
            onUse(images[0], nil, lastCaptureID)
        }
    }

    /// Mode-Switch-Handler (Feature C). Wird von der Capture-View bei
    /// horizontalem Swipe aufgerufen. Wir validieren hier — die View
    /// erkennt die Geste, aber darf während Capturing/Refining nicht
    /// wechseln (User würde Foto/Analyse abbrechen).
    private func handleModeSwitchRequest(to requested: ScanCaptureProfile) {
        // Identität ignorieren — kein Noise-Log, kein Haptic.
        guard requested != profile else { return }
        // Nur in „live"-Stages erlauben. `.capturing`/`.refining`
        // würden beim Switch auf inkonsistente Zustände führen.
        let state = controller.captureMachine.state
        guard state.isLiveStage || state == .idle else {
            #if DEBUG
            print("🔁 [ModeSwitch] blocked — machine in \(state.debugLabel)")
            #endif
            return
        }
        #if DEBUG
        print("🔁 [ModeSwitch] \(profile == .vocabularyList ? "list" : "text") → \(requested == .vocabularyList ? "list" : "text")")
        #endif
        profile = requested
        // AutoCapture-Default neu setzen, sonst behält der User den
        // alten Auto/Manual-Zustand — im FreeText gibt's keinen Auto-
        // Shutter, also wollen wir den Default des neuen Profils.
        autoCaptureEnabled = (requested.defaultCaptureMode == .auto)
        controller.autoCaptureEnabled = autoCaptureEnabled
        // **Multi-Shot-Buffer beim Profil-Wechsel leeren**: gesammelte
        // Vokabel-Bilder gehören nicht in einen FreeText-Pfad.
        if requested != .vocabularyList { batchCapturedImages = [] }
    }

    // MARK: - Processing-Stage

    private func processingStage(raw: UIImage) -> some View {
        ZStack {
            // Hintergrund: das Rohbild dezent, damit der User sieht was verarbeitet wird.
            // `.frame(…) + .clipped()` vor `ignoresSafeArea()` verhindert,
            // dass `scaledToFill` die Pixelbreite des Rohfotos (3000+ px)
            // an den ZStack durchreicht — ohne diesen Clamp expandierte
            // der Spacer in der Top-HStack auf Foto-Breite und schob die
            // Mode-Pille rechts aus dem Screen.
            Image(uiImage: raw)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.55))

            // Back-Button oben links (User-Auftrag: „Zurück während
            // KI-Analyse muss reagieren"). Bricht die laufende
            // Processing-Pipeline via `processingTask.cancel()` ab und
            // verlässt den Scanner. Cancellation ist cooperativ: die
            // Task-Checkpoints in `runProcessing` bauen das sauber ab,
            // parallel laufende CIImage-/Vision-Operationen werden
            // nicht hart abgewürgt — ihr Output landet aber ohnehin
            // nirgends, weil die View in dem Moment schon weg ist.
            //
            // Rechts neben dem Close-Button: Mode-Badge (Feature A).
            //
            // **Pill-Overflow-Fix**: Ohne `.frame(maxWidth: .infinity)`
            // erbte der VStack die Breite seiner HStack-Kinder (Button +
            // Spacer + Badge). Mit dem `scaledToFill`-Image darunter
            // konnte die ZStack-Breite an der Pixelbreite des Rohfotos
            // hängen — der Spacer expandierte dann auf die Foto-Breite,
            // und die „Vokabeln scannen"-Pille wanderte weit rechts aus
            // dem Screen raus. Explizit auf Screen-Breite pinnen.
            VStack {
                HStack {
                    Button(action: cancelProcessing) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Abbrechen")
                    Spacer()
                    ScanModeBadge(profile: profile, variant: .overlay)
                        .fixedSize()
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, AppTheme.Spacing.sm)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack(spacing: AppTheme.Spacing.md) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.4)
                Text("Wird korrigiert…")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(.white)

                // Text-Dense-Hinweis (TODO 5): zeigt dem User an,
                // dass wir den Full-Frame-Text-Pfad nehmen statt
                // Rectangle-Detection. Reduziert das Gefühl „warum
                // ist da kein Rahmen?"-Verwirrung beim Screenshot-
                // Scan.
                if isTextDenseProcessing {
                    HStack(spacing: 6) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Text erkannt — optimierte Analyse")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.white.opacity(0.12))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isTextDenseProcessing)
        }
    }

    /// User-initiated cancellation der laufenden Processing-Pipeline.
    /// Bricht die Task ab und verlässt den Scanner (konsistent zum
    /// Back-Button im Capture- und Review-Stage, die ebenfalls
    /// `onCancel()` triggern).
    private func cancelProcessing() {
        #if DEBUG
        print("🚫 [Processing] user cancelled during AI analysis")
        #endif
        processingTask?.cancel()
        processingTask = nil
        onCancel()
    }

    private func runProcessing(
        raw: UIImage,
        frozenQuad: VNRectangleObservation?,
        frozenAttentionBox: CGRect?,
        previewLayerSize: CGSize?,
        captureID: UUID
    ) async {
        let geometryPolicy = CaptureGeometryPolicy.from(
            profile: profile,
            autoCaptureEnabled: autoCaptureEnabled
        )
        #if DEBUG
        let attBoxStr = frozenAttentionBox.map { String(format: "(%.2f,%.2f,%.2f,%.2f)", $0.minX, $0.minY, $0.width, $0.height) } ?? "nil"
        let plsStr = previewLayerSize.map { String(format: "(%.0f×%.0f)", $0.width, $0.height) } ?? "nil"
        print("🟤 [Processing \(captureID.shortID)] runProcessing started " +
              "policy=\(geometryPolicy.debugLabel) " +
              "raw=\(Int(raw.size.width))×\(Int(raw.size.height)) " +
              "frozenQuad=\(frozenQuad != nil ? "yes" : "nil") " +
              "attBox=\(attBoxStr) " +
              "previewLayerSize=\(plsStr)")
        #endif

        // **Pipeline-Routing nach `CaptureGeometryPolicy`**:
        //
        //   • .documentCropAndPerspective  (vocabularyList auto)
        //     → raw → SmartDocumentProcessor(.vocabularyOCR) mit
        //       Quad-Detection + Perspective + documentStrong-Enhancement.
        //
        //   • .documentPerspectiveIfPlausible (vocabularyList manual)
        //     → identisch zur auto-Variante — Vokabelblätter sind
        //       typisch flach und rechteckig, Pipeline darf laufen.
        //
        //   • .rectangleAssistWithFallback (freeText auto/Rahmen)
        //     → erst SmartDocumentProcessor(.freierTextRectangleAssist);
        //       bei Erfolg perspektivkorrigiertes Bild übernehmen,
        //       sonst Fallback auf WYSIWYG (cropToAspectFill).
        //
        //   • .wysiwygNoPerspective (freeText manual) — **NEU/Slice C**
        //     → KEIN SmartDocumentProcessor, KEIN Perspective.
        //       Direkter analytischer aspectFill-Crop des Photos auf
        //       die Sucher-Container-Aspect. Quality-Analyse läuft
        //       direkt auf dem Crop. Keine automatische Bild-Verbesserung
        //       (User kann „Auto optimieren"-Button im Review nutzen).
        //
        // `attentionCropApplied` bleibt auf `false` — Attention-Tracker
        // bestimmt nie automatisch den Crop.
        let attentionCropApplied = false
        var usedPreviewVisibleCrop = false
        var usedQuadAssist = false

        // **Slice C — wysiwygNoPerspective**: kompletter Bypass der
        // Document-Pipeline. Direkter Crop + Quality-Report.
        if geometryPolicy == .wysiwygNoPerspective {
            let pipelineImage: UIImage = {
                guard let pls = previewLayerSize,
                      let cropped = ImageCropper.cropToAspectFill(raw, containerSize: pls)
                else { return raw }
                usedPreviewVisibleCrop = true
                #if DEBUG
                print("✂️ [WYSIWYG] freeText manual " +
                      "raw=\(Int(raw.size.width))×\(Int(raw.size.height)) → " +
                      "cropped=\(Int(cropped.size.width))×\(Int(cropped.size.height))")
                #endif
                return cropped
            }()
            let report = await ImageQualityAnalyzer.analyzeAsync(
                image: pipelineImage,
                rectangleMetrics: nil,
                hints: .init(isTextDense: false)
            )
            if Task.isCancelled { return }
            await MainActor.run {
                controller.markReviewReady(corrected: pipelineImage, report: report)
                lastCaptureID = captureID
                optimizedVariant = nil
                optimizationApplied = false
                #if DEBUG
                print("📋 [Capture-Identity \(captureID.shortID)] mode=freeText/manual " +
                      "policy=\(geometryPolicy.debugLabel) " +
                      "trigger=manual " +
                      "fullDim=\(Int(raw.size.width))×\(Int(raw.size.height)) " +
                      "finalDim=\(Int(pipelineImage.size.width))×\(Int(pipelineImage.size.height)) " +
                      "usedPreviewVisibleCrop=\(usedPreviewVisibleCrop ? "yes" : "no") " +
                      "usedQuadAssist=no " +
                      "documentCorrectionApplied=no " +
                      "perspectiveCorrectionApplied=no " +
                      "attBox=\(attBoxStr) attentionCropApplied=no enhAuto=no")
                #endif
            }
            await runBackgroundOptimization(
                base: pipelineImage,
                originalReport: report,
                rectangleMetrics: nil,
                denseFlag: false
            )
            return
        }

        // **Andere Policies**: laufen weiterhin durch
        // SmartDocumentProcessor.
        let preprocessed: UIImage = raw
        let useFreeTextRectangleAssist = (geometryPolicy == .rectangleAssistWithFallback)

        // **Text-Dense-Check** nur in vocabularyList (kein freeText
        // mehr in diesem Pfad). Wäre obsolet weil vocabularyList nie
        // text-dense ist; `denseFlag = false` als sicherer Default.
        let config: SmartDocumentProcessor.Config
        var denseFlag = false
        if useFreeTextRectangleAssist {
            config = .freierTextRectangleAssist
        } else {
            config = effectiveConfig  // vocabularyOCR
        }

        // UI-Flag auf MainActor setzen, damit der Text-Hinweis
        // erscheinen kann, BEVOR die teuren Pipeline-Schritte laufen.
        await MainActor.run { isTextDenseProcessing = denseFlag }

        let result = await SmartDocumentProcessor.processAsync(
            preprocessed,
            config: config,
            fallbackQuad: frozenQuad
        )
        if Task.isCancelled { return }

        // **Item 11 — Smart-Region-Post-Capture (Opt-in)**: Power-User
        // können in den Settings den Smart-Text-Region-Crop einschalten.
        // Wenn aktiv UND Profil `.freeText`, läuft eine zusätzliche
        // Text-Region-Detection auf dem korrigierten Bild; erfolgreiche
        // Crops ersetzen das Bild vor Quality-Check & Review. Default
        // ist aus — die meisten User wollen das volle Foto behalten.
        var pipelineImage = result.image
        // **freeText auto/Rahmen-Fallback**: wenn der Quad-Pfad
        // nichts plausibles gefunden hat (`didCorrectPerspective ==
        // false`), greifen wir auf WYSIWYG zurück. Damit fühlt sich
        // der Modus nie schlechter als der Manual-Pfad an, selbst wenn
        // das Motiv keine klare Rectangle-Fläche hat.
        if useFreeTextRectangleAssist {
            if result.didCorrectPerspective {
                usedQuadAssist = true
                #if DEBUG
                print("📐 [freeText auto] Quad gefunden → perspective-corrected " +
                      "(\(Int(pipelineImage.size.width))×\(Int(pipelineImage.size.height)))")
                #endif
            } else if let pls = previewLayerSize,
                      let cropped = ImageCropper.cropToAspectFill(raw, containerSize: pls) {
                pipelineImage = cropped
                usedPreviewVisibleCrop = true
                #if DEBUG
                print("✂️ [freeText auto] kein stabiler Quad → Fallback WYSIWYG " +
                      "(\(Int(cropped.size.width))×\(Int(cropped.size.height)))")
                #endif
            } else {
                #if DEBUG
                print("📷 [freeText auto] kein Quad + kein PreviewLayerSize → raw full-frame durchgereicht")
                #endif
            }
        }

        if profile == .freeText, ScanSettings.smartRegionCropEnabled {
            if let cropped = await SmartTextRegionDetector.detectCropAsync(pipelineImage) {
                #if DEBUG
                print("✂️ [Scan-SmartRegion] opt-in crop applied " +
                      "(\(Int(pipelineImage.size.width))×\(Int(pipelineImage.size.height)) → " +
                      "\(Int(cropped.size.width))×\(Int(cropped.size.height)))")
                #endif
                pipelineImage = cropped
            } else {
                #if DEBUG
                print("✂️ [Scan-SmartRegion] opt-in active but no crop produced — keeping full frame")
                #endif
            }
            if Task.isCancelled { return }
        }

        // Qualitätscheck lokal — kein API-Call, ~50ms auf Background-Queue.
        //
        // **TODO 4 — Text-Dense-Relaxation**: bei Full-Frame-Captures
        // (Screenshots/Menüs) sind Skew/Size/Completeness bedeutungslos
        // (es gibt kein Rechteck) und Glare ist systembedingt
        // (Display-Reflexionen). Analyzer kriegt daher einen Hint, der
        // die Rect-Metriken neutralisiert und die Glare-Schwelle
        // absenkt. Sharpness und Kontrast werden weiterhin geprüft —
        // unscharfe Screenshots gibt es auch.
        let report = await ImageQualityAnalyzer.analyzeAsync(
            image: pipelineImage,
            rectangleMetrics: result.rectangleMetrics,
            hints: .init(isTextDense: denseFlag)
        )
        if Task.isCancelled { return }

        #if DEBUG
        print("📷 [Scan-Quality] \(report.debugSummary)")
        #endif

        await MainActor.run {
            // **Multi-Shot-Verzweigung für vocabularyList** (User-Spec
            // „ganzes Kapitel in einem Rutsch"): nach jedem Capture
            // sammeln wir das korrigierte Bild und springen direkt
            // zurück zur Live-Camera, statt Preview/Review zu zeigen.
            // Der User triggert weitere Captures, drückt am Ende
            // „Fertig" → `onUseBatch` mit allen gesammelten Bildern.
            // FreeText bleibt **single-shot** (Spec): zeigt Preview
            // wie bisher.
            if profile == .vocabularyList && batchCapturedImages.count < batchMaxImages {
                batchCapturedImages.append(pipelineImage)
                lastCaptureID = captureID
                #if DEBUG
                print("📸 [Multi-Shot] vocabularyList capture #\(batchCapturedImages.count) appended (id=\(captureID.shortID))")
                #endif
                controller.resetToLive()
                return
            }

            controller.markReviewReady(corrected: pipelineImage, report: report)
            lastCaptureID = captureID
            // **Auto-Optimization-State zurücksetzen** für jeden neuen
            // Capture — sonst würde ein alter Vorschlag fälschlich
            // weiterleben.
            optimizedVariant = nil
            optimizationApplied = false
            #if DEBUG
            // **Capture-Identitäts-Log** (FreeText-Stabilisierungs-Slice).
            // Eine Zeile pro fertigem Capture mit allen Größen, die für
            // Diagnose/Verifikation gebraucht werden:
            //   • mode        — vocabularyList | freeText
            //   • trigger     — manual | auto
            //   • fullFrame   — yes | no  (= NICHT perspective-corrected)
            //   • attBox      — Vision-Box-Dim, „nil" wenn nicht vorhanden
            //   • cropApplied — ob runProcessing einen Attention-Crop
            //                   anwendete (Slice: immer no für FreeText)
            //   • finalDim    — pixel dims des Bildes, das in Review geht
            //   • docCorr     — ob SmartDocumentProcessor perspektiv-korrigiert
            //   • enhAuto     — Auto-Optimization angewendet (immer no
            //                   am Ende von runProcessing, kann sich
            //                   später per User-Tap ändern)
            let attBoxStr = frozenAttentionBox.map {
                String(format: "(%.2f,%.2f,%.2f,%.2f)", $0.minX, $0.minY, $0.width, $0.height)
            } ?? "nil"
            let cropApplied = attentionCropApplied ? "yes" : "no"
            let pvcUsed = usedPreviewVisibleCrop ? "yes" : "no"
            let qaUsed = usedQuadAssist ? "yes" : "no"
            let rawDim = "\(Int(raw.size.width))×\(Int(raw.size.height))"
            let finalDim = "\(Int(pipelineImage.size.width))×\(Int(pipelineImage.size.height))"
            let docCorr = result.didCorrectPerspective ? "yes" : "no"
            let perspectiveCorr = result.didCorrectPerspective ? "yes" : "no"
            // FreeText auto/Rahmen = manual trigger (kein Auto-Shutter).
            let triggerLabel: String = {
                if profile == .freeText { return "manual" }
                return autoCaptureEnabled ? "auto" : "manual"
            }()
            let modeLabel: String = {
                if profile == .freeText {
                    return autoCaptureEnabled ? "freeText/auto-Rahmen" : "freeText/manual"
                }
                return autoCaptureEnabled ? "vocabularyList/auto" : "vocabularyList/manual"
            }()
            print("📋 [Capture-Identity \(captureID.shortID)] mode=\(modeLabel) " +
                  "policy=\(geometryPolicy.debugLabel) " +
                  "trigger=\(triggerLabel) " +
                  "fullDim=\(rawDim) finalDim=\(finalDim) " +
                  "usedPreviewVisibleCrop=\(pvcUsed) " +
                  "usedQuadAssist=\(qaUsed) " +
                  "documentCorrectionApplied=\(docCorr) " +
                  "perspectiveCorrectionApplied=\(perspectiveCorr) " +
                  "attBox=\(attBoxStr) attentionCropApplied=\(cropApplied) enhAuto=no")
            #endif
        }

        // **Background-Auto-Optimization** — adaptiv ausgewähltes
        // Profil parallel anwenden, Original/Optimiert vergleichen,
        // Vorschlag nur bei messbarer Verbesserung.
        await runBackgroundOptimization(
            base: pipelineImage,
            originalReport: report,
            rectangleMetrics: result.rectangleMetrics,
            denseFlag: denseFlag
        )
    }

    /// Optimierungs-Hintergrund-Pass: wendet das `EnhancementProfile.recommended(for:)`
    /// auf das korrigierte Bild an, analysiert das Resultat erneut und
    /// entscheidet, ob ein Vorschlag (oder Auto-Apply) angezeigt wird.
    ///
    /// Edge Cases (NICHT anbieten):
    ///   • Verbesserung ≤ 0.05 (zu klein für sichtbaren Mehrwert)
    ///   • Bild bereits `.good` UND Verbesserung < 0.10 (kaum nötig)
    ///   • Optimierung verschlechtert (negative Improvement)
    ///
    /// Auto-Apply (FreeText only):
    ///   • Verbesserung > 0.15 → setzt `optimizationApplied = true`
    ///     direkt, User sieht das optimierte Bild ohne Tap.
    private func runBackgroundOptimization(
        base: UIImage,
        originalReport: ImageQualityAnalyzer.Report,
        rectangleMetrics: ImageQualityAnalyzer.RectangleMetrics?,
        denseFlag: Bool
    ) async {
        let recommendedProfile = ImageQualityAnalyzer.EnhancementProfile.recommended(for: originalReport.issues)

        // CIFilter-Pass auf Background-Queue.
        let optimized = await ImageEnhancer.optimizeAsync(base, profile: recommendedProfile)
        if Task.isCancelled { return }

        // Gleicher Quality-Pass mit gleichen Hints — sonst wäre der
        // Vergleich apples-to-oranges (z. B. text-dense neutralisiert
        // Skew/Size).
        let optimizedReport = await ImageQualityAnalyzer.analyzeAsync(
            image: optimized,
            rectangleMetrics: rectangleMetrics,
            hints: .init(isTextDense: denseFlag)
        )
        if Task.isCancelled { return }

        let improvement = optimizedReport.overallScore - originalReport.overallScore

        #if DEBUG
        print(String(
            format: "🪄 [Auto-Opt] profile=%@ improvement=%+.3f (orig=%.2f → opt=%.2f)",
            recommendedProfile.debugLabel, improvement,
            originalReport.overallScore, optimizedReport.overallScore
        ))
        #endif

        await MainActor.run {
            // **Cancellation-Gate**: wenn der parent-Task zwischen
            // dem letzten `Task.isCancelled`-Check und dem MainActor-
            // Hop gecanceled wurde (z. B. User-Retake während
            // `optimizeAsync` lief), darf der State NICHT überschrieben
            // werden. Sonst würde eine veraltete Variante aus einem
            // verworfenen Capture beim neuen Capture als Vorschlag
            // erscheinen.
            guard !Task.isCancelled else {
                #if DEBUG
                print("🪄 [Auto-Opt] cancelled — skipping state update")
                #endif
                return
            }

            // Edge Cases — NICHT anbieten.
            guard improvement > 0.05 else { return }
            if originalReport.level == .good && improvement < 0.10 { return }

            optimizedVariant = OptimizedVariant(
                image: optimized,
                report: optimizedReport,
                improvement: improvement,
                profile: recommendedProfile
            )

            // **FreeText-Auto-Apply** bei großer Verbesserung. Vokabel-
            // Modus bleibt konservativ → User entscheidet selbst.
            if profile == .freeText && improvement > 0.15 {
                optimizationApplied = true
                #if DEBUG
                print("🪄 [Auto-Opt] auto-applied (FreeText + improvement > 0.15)")
                #endif
            }
        }
    }

    // MARK: - Preview-Stage

    private func previewStage(corrected: UIImage, report: ImageQualityAnalyzer.Report) -> some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: Mode-Badge links, Close oben rechts.
                // Feature A: Badge bleibt auch im Preview-Screen
                // sichtbar, damit der User den Modus auch vor dem
                // „Verwenden"-Tap nachvollziehen kann. `.card`-Variante,
                // weil der Preview-Hintergrund hell ist (nicht Kamera).
                HStack {
                    ScanModeBadge(profile: profile, variant: .card)
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(AppTheme.Colors.secondarySurface))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, AppTheme.Spacing.md)

                // Quality-Banner nur bei mittlerer/schlechter Qualität.
                if report.level != .good {
                    qualityBanner(report: report)
                        .padding(.horizontal, AppTheme.Layout.screenPadding)
                        .padding(.top, AppTheme.Spacing.sm)
                }

                Spacer()

                // **DisplayImage-Auflösung** (Reihenfolge):
                //   1. User-Crop (manuelle Bearbeitung gewinnt immer)
                //   2. Auto-Optimiertes Variant-Bild (wenn applied)
                //   3. Pipeline-refinierter Original-Crop
                let displayImage: UIImage = {
                    if let cropped = userCroppedImage { return cropped }
                    if optimizationApplied, let opt = optimizedVariant?.image { return opt }
                    return corrected
                }()
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .stroke(AppSectionStyle.scan.accent.opacity(0.35), lineWidth: 1.2)
                    )
                    .padding(.horizontal, AppTheme.Layout.screenPadding)
                    // Sanfte Überblendung beim Apply der Auto-Opt
                    // (User-Spec „kurzer Fade / leichte Helligkeits-
                    // änderung" als visuelles Apply-Feedback).
                    .animation(.easeInOut(duration: 0.30), value: optimizationApplied)

                Spacer()

                // Buttons — simplifiziertes Schema (AP4):
                //   • gut/mittel: „Verwenden" primär, „Neu" sekundär
                //   • schlecht:   „Neu" primär, „Trotzdem verwenden" sekundär
                //
                // **Zwischen Bild und Primary/Secondary**: neuer
                // „Zuschneiden"-Button (User-Wunsch). Öffnet
                // `ManualCropSheet` — Ergebnis ersetzt `displayImage`,
                // ohne die Machine-Payload anzufassen. So kann der User
                // verfeinern, ohne „Neu aufnehmen" zu müssen.
                VStack(spacing: AppTheme.Spacing.sm) {
                    // **Auto-Optimieren** (Card-Slot): zeigt entweder
                    // den „Auto optimieren"-Button (Standard) ODER —
                    // wenn die Optimierung gerade aktiv ist — die
                    // Apply-Pille mit „Original"-Toggle.
                    //
                    // **Wichtig** (User-Auftrag „darf sich nicht
                    // verschieben durch das Erscheinen"): beide
                    // Varianten leben im gleichen Card-Slot und haben
                    // identisches Padding. Es entsteht KEIN neuer
                    // Platz oben → das Bild bleibt in seiner Position,
                    // nur der Card-Inhalt wechselt.
                    if shouldShowAutoOptimizeButton(report: report) || optimizationApplied {
                        autoOptimizeCardSlot(report: report)
                    }
                    // „Zuschneiden"-Karte in **beiden** Modi (User-
                    // Wunsch): auch Vokabel-Listen-Scans profitieren
                    // gelegentlich vom manuellen Nachjustieren, wenn
                    // die automatische Perspektivkorrektur den Rand
                    // zu eng oder zu weit gewählt hat.
                    cropAdjustButton(source: displayImage)
                    if report.level == .poor {
                        retakePrimaryButton
                        useSecondaryButton(corrected: displayImage, label: "Trotzdem verwenden")
                    } else {
                        usePrimaryButton(corrected: displayImage, label: "Verwenden")
                        retakeSecondaryButton
                    }
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
        .fullScreenCover(isPresented: $showingCropSheet) {
            // **Preview-Manual-Crop-Sheet**: greift sich das aktuell
            // angezeigte Bild (userCroppedImage ?? corrected) und lässt
            // den User sauber ziehen. Ergebnis landet in
            // `userCroppedImage` und wird sofort im Preview reflektiert.
            let baseImage = userCroppedImage ?? corrected
            ManualCropSheet(
                image: baseImage,
                accent: AppSectionStyle.scan.accent,
                onCancel: {
                    showingCropSheet = false
                },
                onApply: { croppedImage, _ in
                    userCroppedImage = croppedImage
                    showingCropSheet = false
                    #if DEBUG
                    print("✂️ [Preview-Crop] user applied crop: " +
                          "\(Int(baseImage.size.width))×\(Int(baseImage.size.height)) → " +
                          "\(Int(croppedImage.size.width))×\(Int(croppedImage.size.height)))")
                    #endif
                }
            )
        }
    }

    /// „Zuschneiden"-Card — gleiche Größe wie die Verwenden-/Neu-
    /// Buttons, aber in einem Tint-Style, der sich visuell zwischen
    /// beiden einordnet: App-Blau mit sanftem Fill + klarer Border,
    /// statt voll deckender CTA-Farbe oder neutralem Dark-Secondary.
    private func cropAdjustButton(source: UIImage) -> some View {
        let tint = AppTheme.Colors.elumiBlue
        return Button {
            showingCropSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "crop")
                    .font(.system(size: 15, weight: .bold))
                Text("Zuschneiden")
                    .font(AppTheme.Typography.button)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.Layout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(tint.opacity(0.55), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bild zuschneiden")
        .accessibilityHint("Öffnet den manuellen Zuschneide-Editor für das aktuelle Bild")
    }

    // MARK: - Preview Helpers

    /// Banner über dem Bild bei schlechter/mittlerer Qualität.
    /// Farbcodiert: gelb (mittel) / rot (schlecht).
    @ViewBuilder
    private func qualityBanner(report: ImageQualityAnalyzer.Report) -> some View {
        let accent: Color = report.level == .poor ? AppTheme.Colors.moduleHearts : AppTheme.Colors.warning
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: report.level == .poor ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                Text(report.headline)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                // Numeric Score (Slice 6): gibt dem User einen
                // greifbaren Vergleichswert („71 %" statt nur Headline).
                Text(report.scoreDisplay)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(accent.opacity(0.18))
                    )
            }
            // AP13: priorisierte, kombinierte Anzeige — max 2 Hinweise,
            // sortiert nach Aktions-Dringlichkeit, mit „ • " getrennt.
            // Spart eine ganze Zeile pro Issue + rangiert den
            // wichtigsten Hinweis zuerst.
            if !report.combinedMessage.isEmpty {
                Text(report.combinedMessage)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .fill(accent.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                .stroke(accent.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Auto-Optimierungs-UI

    /// **Sichtbarkeits-Logik für den Auto-Optimieren-Button** (User-
    /// Auftrag „Jeder Hinweis muss eine Aktion haben"):
    ///   • Report enthält ein auto-fixbares Issue (lowContrast/blurry/
    ///     glare/tooDark) → Button anbieten.
    ///   • ODER Background-Optimierung lieferte bereits eine
    ///     verbesserte Variante (auch bei `.good`-Bildern kann das
    ///     vorkommen, z. B. via `.default`-Profil) → Button anbieten.
    ///   • Sobald der User den Button geklickt hat (`optimizationApplied
    ///     == true`), übernimmt die Apply-Pille das Feedback.
    private func shouldShowAutoOptimizeButton(report: ImageQualityAnalyzer.Report) -> Bool {
        if report.hasAutoFixableIssue { return true }
        if optimizedVariant != nil    { return true }
        return false
    }

    /// **Card-Slot für Auto-Optimieren**. In-place-Wechsel zwischen
    /// zwei Zuständen — beide haben identisches Padding/Layout, sodass
    /// das Drüber liegende Bild beim Tap **nicht** verschoben wird:
    ///
    ///   • **Inactive** — „Auto optimieren"-Button (App-Blau, soft-fill)
    ///   • **Active**   — Status-Card mit Modus-Pille + „Original"-Toggle
    ///
    /// Beide Varianten haben dieselbe Höhe (`AppTheme.Layout.buttonHeight`),
    /// damit der Slot keine Layout-Sprünge erzeugt.
    @ViewBuilder
    private func autoOptimizeCardSlot(report: ImageQualityAnalyzer.Report) -> some View {
        if optimizationApplied, let variant = optimizedVariant {
            autoOptimizedActiveCard(variant: variant)
        } else {
            autoOptimizeInactiveButton(report: report)
        }
    }

    /// **Inactive-Zustand des Card-Slots** — der „Auto optimieren"-Button.
    /// Wendet die bg-Variante an oder triggert On-Demand-Optimization.
    @ViewBuilder
    private func autoOptimizeInactiveButton(report: ImageQualityAnalyzer.Report) -> some View {
        let tint = AppTheme.Colors.elumiBlue
        Button {
            applyAutoOptimization(report: report)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 15, weight: .bold))
                Text("Auto optimieren")
                    .font(AppTheme.Typography.button)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.Layout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(tint.opacity(0.55), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto-Optimierung anwenden")
        .accessibilityHint("Verbessert Schärfe, Kontrast oder Helligkeit automatisch")
    }

    /// **Active-Zustand des Card-Slots** — Status der laufenden Auto-
    /// Optimierung mit „Original"-Toggle. Tap auf „Original" setzt
    /// `optimizationApplied = false`; der Slot zeigt wieder den Button.
    @ViewBuilder
    private func autoOptimizedActiveCard(variant: OptimizedVariant) -> some View {
        let tint = AppTheme.Colors.elumiBlue
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
            Text("Aktiv: \(profileShortLabel(for: variant.profile))")
                .font(AppTheme.Typography.button)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Button {
                withAnimation(.easeInOut(duration: 0.30)) {
                    optimizationApplied = false
                }
            } label: {
                Text("Original")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(AppTheme.Colors.secondarySurface)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Original anzeigen")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: AppTheme.Layout.buttonHeight)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(tint.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(tint.opacity(0.55), lineWidth: 1.5)
        )
    }

    /// Action-Handler für „Auto optimieren". Bevorzugt bereits
    /// berechnete Background-Variante; fällt auf On-Demand-Computation
    /// zurück, wenn diese noch nicht fertig ist.
    private func applyAutoOptimization(report: ImageQualityAnalyzer.Report) {
        // Schnellpfad: bg-Variante existiert → direkt anwenden.
        if optimizedVariant != nil {
            withAnimation(.easeInOut(duration: 0.30)) {
                optimizationApplied = true
            }
            return
        }

        // On-Demand-Pfad: Variante noch nicht fertig (oder
        // background-pass hatte improvement < 0.05 und keinen
        // Variant gespeichert). Wir berechnen jetzt mit dem
        // empfohlenen Profil und wenden direkt an — der User hat
        // explizit gefragt, also nicht in den Edge-Case-Skip rennen.
        guard case .reviewReady(let corrected, _) = controller.captureMachine.state
        else { return }

        let recommendedProfile = ImageQualityAnalyzer.EnhancementProfile.recommended(for: report.issues)
        Task {
            let optimized = await ImageEnhancer.optimizeAsync(corrected, profile: recommendedProfile)
            await MainActor.run {
                let variant = OptimizedVariant(
                    image: optimized,
                    report: report,         // gleicher Report — wir kennen den optimized score nicht ohne 2. Pass
                    improvement: 0,         // unbekannt; egal, weil User explizit gewählt hat
                    profile: recommendedProfile
                )
                optimizedVariant = variant
                withAnimation(.easeInOut(duration: 0.30)) {
                    optimizationApplied = true
                }
            }
        }
    }

    /// Kompaktes Label für die Auto-Apply-Pille.
    private func profileShortLabel(for profile: ImageQualityAnalyzer.EnhancementProfile) -> String {
        if profile == .glare       { return "Reflex-Modus" }
        if profile == .blurry      { return "Schärfe-Modus" }
        if profile == .lowContrast { return "Kontrast-Modus" }
        if profile == .tooDark     { return "Aufhellungs-Modus" }
        return "Standard-Modus"
    }

    private func usePrimaryButton(corrected: UIImage, label: String) -> some View {
        Button {
            onUse(corrected, currentReport, lastCaptureID)
        } label: {
            Text(label)
                .font(AppTheme.Typography.button)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.Layout.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppTheme.Colors.cta)
                )
        }
        .buttonStyle(.plain)
    }

    private func useSecondaryButton(corrected: UIImage, label: String) -> some View {
        Button {
            onUse(corrected, currentReport, lastCaptureID)
        } label: {
            Text(label)
                .font(AppTheme.Typography.button)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.Layout.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppTheme.Colors.secondarySurface)
                )
        }
        .buttonStyle(.plain)
    }

    private var retakePrimaryButton: some View {
        Button {
            // AP1: Machine-driven — Machine auf `.searching` zurück,
            // View folgt automatisch via `viewState(from:)`.
            // Auch User-Crop und Text-Dense-Flag zurücksetzen, damit
            // die neue Aufnahme frisch startet.
            isTextDenseProcessing = false
            userCroppedImage = nil
            // Auto-Optimization-State zurücksetzen — neuer Capture
            // beginnt mit frischem Vorschlags-State.
            optimizedVariant = nil
            optimizationApplied = false
            controller.resetToLive()
        } label: {
            Text("Neu aufnehmen")
                .font(AppTheme.Typography.button)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.Layout.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppTheme.Colors.cta)
                )
        }
        .buttonStyle(.plain)
    }

    private var retakeSecondaryButton: some View {
        Button {
            isTextDenseProcessing = false
            userCroppedImage = nil
            // Auto-Optimization-State zurücksetzen — neuer Capture
            // beginnt mit frischem Vorschlags-State.
            optimizedVariant = nil
            optimizationApplied = false
            controller.resetToLive()
        } label: {
            Text("Neu aufnehmen")
                .font(AppTheme.Typography.button)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.Layout.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(AppTheme.Colors.secondarySurface)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Capture-Subview

/// Teilt die Capture-Stage ab, weil sie viel State + einen eigenen
/// SessionDelegate braucht. Zurück an den Parent per onCapture/onCancel.
private struct SmartScannerCaptureView: View {
    /// Controller + Machine leben jetzt im Parent `SmartScannerView` —
    /// wir erhalten sie als `@ObservedObject`, damit State über die
    /// Stage-Transitionen hinweg stabil bleibt (AP1).
    @ObservedObject var controller: SmartScannerController
    /// Capture-Profil — steuert Live-Quad-Overlay und Auto-Capture-
    /// Default. Wird über den Controller auch an `SmartScannerSession`
    /// weitergereicht, damit Auto-Capture in freeText-Szenen nicht auf
    /// zufällige Polygone feuert.
    let profile: ScanCaptureProfile
    @Binding var autoCaptureEnabled: Bool
    let onCancel: () -> Void
    /// **Feature C**: Horizontaler Swipe löst diesen Callback mit
    /// dem gewünschten Zielprofil aus. Parent (`SmartScannerView`)
    /// validiert gegen den Machine-State und aktualisiert dann das
    /// Profile-Binding.
    let onSwitchMode: (ScanCaptureProfile) -> Void
    /// **Multi-Shot Buffer** (Binding zum Parent). Nur befüllt im
    /// vocabularyList-Profil. Footer rendert Thumbnail-Strip + „Fertig"-
    /// Button, Tap auf Thumbnail entfernt einen Eintrag, „Fertig"
    /// triggert `onFinalizeBatch`.
    @Binding var batchCapturedImages: [UIImage]
    /// Callback aus dem Multi-Shot-Footer. Parent leert intern den
    /// Buffer und routet zu `onUse` (single) bzw. `onUseBatch` (multi).
    let onFinalizeBatch: () -> Void

    // MARK: - Pinch-to-Zoom State (Feature B)

    /// Basis-Faktor beim Start eines Pinch-Gestures. `scale` der
    /// `MagnificationGesture` ist **relativ** (1.0 = Start), daher
    /// multiplizieren wir mit der Basis, um absoluten Zoom zu
    /// bekommen.
    @State private var pinchBaseZoom: CGFloat = 1.0
    /// True während eines aktiven Pinch-Gestures — triggert die
    /// Einblendung des Zoom-Indikators.
    @State private var isPinching: Bool = false
    /// True, wenn der Zoom-Indikator gerade sichtbar ist. Wird bei
    /// Gesture-Ende auf ein Fade-Out getimed (~1.5s sichtbar, dann
    /// weg).
    @State private var zoomIndicatorVisible: Bool = false
    /// Token für den Fade-Out-Timer — frische UUID pro Gesture-
    /// End-Event, sodass ein neuer Pinch den alten Fade-Timer
    /// invalidiert.
    @State private var zoomIndicatorFadeToken = UUID()

    /// Nach Pinch-Ende 1.5s sichtbar lassen, dann ausblenden. Jeder
    /// neue Pinch-Ende-Event überschreibt das Token und startet einen
    /// frischen Timer, sodass sich die Indikator-Anzeige wie ein
    /// „läuft so lange wie der User pinscht, plus 1.5s Nachklang"
    /// verhält.
    private func scheduleZoomIndicatorFadeOut() {
        zoomIndicatorVisible = true
        let token = UUID()
        zoomIndicatorFadeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard zoomIndicatorFadeToken == token else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                zoomIndicatorVisible = false
            }
        }
    }

    // MARK: - Mode Switch via Swipe (Feature C)

    /// Mindestabstand (pt), den ein Drag horizontal zurücklegen muss,
    /// um als Mode-Switch-Swipe zu zählen. Groß genug, um versehentliche
    /// Schwenk-Bewegungen (z. B. beim Zielen der Kamera) zu filtern,
    /// klein genug, um absichtlich fließend auslösbar zu sein.
    private let swipeSwitchThreshold: CGFloat = 60

    /// Haptic beim Mode-Wechsel — light, damit's spürbar ist aber
    /// nicht so kräftig wie der Shutter.
    @State private var modeSwitchHaptic: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    /// Wertet die Drag-Translation aus und fordert ggf. einen Mode-
    /// Switch an. Horizontale Bewegung dominiert — wenn vertikal
    /// mehr als horizontal, ignorieren (vermutlich Scroll-Versuch).
    private func evaluateSwipe(_ translation: CGSize) {
        guard abs(translation.width) > abs(translation.height) else { return }
        guard abs(translation.width) >= swipeSwitchThreshold else { return }
        let requested: ScanCaptureProfile
        if translation.width < 0 {
            // Swipe links → Freier Text
            requested = .freeText
        } else {
            // Swipe rechts → Vokabeln
            requested = .vocabularyList
        }
        guard requested != profile else { return }
        modeSwitchHaptic.prepare()
        modeSwitchHaptic.impactOccurred()
        onSwitchMode(requested)
    }

    var body: some View {
        ZStack {
            // Live-Kamera-Feed.
            //
            // NOTE: Slice 5 hatte hier ein `onTapGesture` für
            // Tap-to-Focus. Das Gesture mit `contentShape(Rectangle())`
            // + `ignoresSafeArea()` hat die Taps auf den Manual-
            // Auslöser-Button abgefangen — User-Bug „Auslöser lässt
            // sich nicht bedienen". Entfernt. Tap-to-Focus wird
            // in einem späteren Slice neu aufgezogen (z. B. als
            // expliziter Fokusring-Tap-Layer, der Touch-Pointer-
            // Weitergabe an Views darüber explizit zulässt).
            CameraPreviewLayerView(layer: controller.previewLayer)
                .ignoresSafeArea()

            // **Gesten-Layer**: transparente Fläche über dem Kamera-
            // Preview, die drei Gesten entgegennimmt:
            //   • Tap (1 Finger, <20pt Bewegung)   → Tap-to-Lock
            //     (nur FreeText)
            //   • Pinch (2 Finger)                 → Zoom
            //     (nur FreeText, Hardware-Zoom des Capture-Device)
            //   • Horizontal-Drag (1 Finger, ≥20pt) → Mode-Switch
            //     (beide Modi)
            //
            // Die UI-Buttons weiter oben im ZStack (Close, Toggle,
            // Shutter, Reset, Auto-Pille) fangen ihre eigenen Taps
            // ab — SwiftUI-Hit-Testing ist Top-Down. Dieser Layer
            // bekommt also nur Gesten, die auf der freien Preview-
            // Fläche passieren.
            //
            // Die Gesten sind immer **registriert**; profile-spezifische
            // Side-Effects werden intern in den Handlern per Guard
            // gefiltert. Dadurch existiert nur **eine** Gesten-Layer,
            // und der Mode-Switch-Drag funktioniert auch in
            // VocabularyList (wo die anderen Gesten inert sind).
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // **Tap-to-Focus** (FreeText) — setzt Hardware-
                    // Fokus + Belichtung am Tap-Punkt (iOS-Kamera-
                    // Standard) und zeigt einen kurz aufploppenden
                    // Fokus-Ring. **Kein** Lock-Overlay, **keine**
                    // Region-Wahl: der vorherige Tap-to-Lock hatte
                    // funktional keinen Effekt mehr und wirkte
                    // willkürlich platziert.
                    guard profile.showsAttentionOverlay else { return }
                    controller.tapToFocus(atLayerPoint: location)
                }
                .gesture(
                    MagnificationGesture(minimumScaleDelta: 0.01)
                        .onChanged { scale in
                            guard profile.showsAttentionOverlay else { return }
                            let target = pinchBaseZoom * scale
                            controller.updateZoom(to: target)
                            if !isPinching { isPinching = true }
                        }
                        .onEnded { _ in
                            guard profile.showsAttentionOverlay else { return }
                            pinchBaseZoom = controller.currentZoomFactor
                            isPinching = false
                            scheduleZoomIndicatorFadeOut()
                        }
                )
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onEnded { value in
                            evaluateSwipe(value.translation)
                        }
                )

            // Overlay-Rahmen — Farbe + Stärke kommen vom Drei-Stufen-
            // Lock-State (User-Auftrag „Fix A UI-Overlay"):
            //   • searching  → weiß, 30 % Deckkraft, dünn (Suchzustand)
            //   • candidate  → weiß, 80 % Deckkraft, mittel (Kandidat)
            //   • locked     → App-Akzent (blau), voll, dick + grün wenn Quality = good
            //
            // Overlay nur im `.vocabularyList`-Profil: freeText-Szenen
            // (Müslipackungen, Poster) haben typisch kein dominantes
            // Dokument; der zappelnde Quad-Rahmen ist hier irreführend
            // und nervig. Pro `ScanCaptureProfile.showsLiveQuadOverlay`.
            // **Debug-Raw-Overlay** (rot) — zeigt die **ungeglättete**
            // Vision-Detection direkt. Liegt der grüne (smoothed)
            // Overlay daneben vs. dem roten, weiß man: Smoothing
            // lagt. Liegen beide daneben vom Motiv, weiß man: Mapper
            // liefert falsche Koordinaten.
            //
            // **Bewusst ohne `#if DEBUG`**: der User testet gerade
            // das Overlay-Sync-Problem, das Debug-Overlay muss auch
            // in Release-Builds sichtbar sein, um Diagnose zu
            // ermöglichen. Entfernen sobald Overlay-Alignment stimmt.
            // **Sichtbarkeit der Quad-Overlays**:
            //   • vocabularyList → immer (showsLiveQuadOverlay = true)
            //   • freeText auto/Rahmen → wenn der User „Auto" gewählt
            //     hat (Rectangle-Assistenz für Plakat/Cover/Schild)
            //   • freeText manual → kein Quad-Overlay
            let showsQuadOverlay = profile.showsLiveQuadOverlay
                || (profile == .freeText && autoCaptureEnabled)
            if showsQuadOverlay, let raw = controller.rawCorners {
                QuadrilateralOverlay(
                    corners: raw,
                    color: .red,
                    lineWidth: 1.5
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // **FreeText-Attention-Overlay**: weicher RoundedRectangle-
            // Rahmen auf dem zentralen Text-/Saliency-Bereich. Im
            // Gegensatz zum harten Dokument-Quad der Vokabel-Liste
            // bewusst dezent (opacity 0.25 + leichter Glow) —
            // signalisiert dem User, wo die Kamera „hinzielt", ohne
            // sich als verbindliche Rahmen-Zusage zu lesen.
            //
            // **Locked-Variante** (Tap-to-Lock): sobald der User
            // tippt, wechselt der Overlay auf App-Blau, stärkere
            // Deckkraft, mit einem Lock-Icon oben links. Der Overlay
            // bleibt stabil auf dem gewählten Bereich, bis der User
            // die Auto-Reset-Pille tippt.
            //
            // **KEIN Auto-Capture**: selbst wenn der Bereich stabil
            // ist, löst das Overlay nicht aus. FreeText bleibt Manual-
            // only (Produkt-Entscheidung).
            // **Manual-Mode-Sichtbarkeits-Regel**:
            //   • Auto-Modus: Overlay zeigt die erkannte Region.
            //   • Manual-Modus: kein Overlay (User hat volle visuelle
            //     Kontrolle, Tap-to-Focus zeigt nur kurz einen
            //     Fokus-Ring).
            let showOverlay: Bool = profile.showsAttentionOverlay && autoCaptureEnabled
            if showOverlay, let region = controller.attentionRegion {
                AttentionRegionOverlay(
                    region: region,
                    isLocked: false   // Lock-Variante deaktiviert
                )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.2), value: controller.attentionRegion)
            }

            // **Tap-to-Focus-Ring** — kurz aufploppender Kreis am
            // letzten Tap-Punkt. Animiert sich selbst (siehe
            // `FocusRingPulse`).
            if profile.showsAttentionOverlay, let pt = controller.lastTapFocusPoint {
                FocusRingPulse(token: controller.lastTapFocusToken, accent: AppSectionStyle.scan.accent)
                    .position(pt)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                // **Belichtungs-Slider** — vertikaler Sun-Slider rechts
                // neben dem Tap-Punkt. iOS-Kamera-Standard: drag rauf =
                // heller, drag runter = dunkler. Auto-Fade nach 3 s
                // ohne Touch (Token-getriggert wie der Ring).
                ExposureSliderOverlay(
                    token: controller.lastTapFocusToken,
                    bias: Binding(
                        get: { controller.currentExposureBias },
                        set: { newValue in
                            controller.setExposureBias(newValue)
                        }
                    ),
                    range: SmartScannerController.exposureBiasRange,
                    accent: AppSectionStyle.scan.accent
                )
                .position(x: pt.x + 60, y: pt.y)
                .ignoresSafeArea()
            }

            // Smoothed Quad-Overlay — gleiche Sichtbarkeitsregel wie
            // der Raw-Debug-Overlay oben.
            if showsQuadOverlay, let corners = controller.currentCorners {
                QuadrilateralOverlay(
                    corners: corners,
                    color: overlayColor(for: controller.lockState, quality: controller.currentQuality),
                    lineWidth: overlayLineWidth(for: controller.lockState)
                )
                // **Wichtig**: muss exakt denselben Koordinatenraum
                // nutzen wie `CameraPreviewLayerView` (beide full-
                // screen via `ignoresSafeArea()`). Ohne diesen Modifier
                // rechnete der Overlay in Safe-Area-Koordinaten, der
                // Preview-Layer aber in Full-Screen-Koordinaten — die
                // Quads erschienen ~Status-Bar-Höhe zu weit unten
                // („Rectangle sitzt nicht auf dem Motiv sondern weit
                // darunter"). Der finale Foto-Crop war korrekt, weil
                // der arbeitet mit Vision-Koordinaten direkt auf dem
                // Still — dieser Fix gilt nur für die Live-Preview-
                // Darstellung.
                .ignoresSafeArea()
                // **AP12** — Pre-Fire-Puls: kurz vor dem Auto-Shutter
                // kommt der Controller in den `isAutoCaptureReady`-
                // State (≈0.3 s Vorwarnzeit). Overlay skaliert dezent
                // auf 1.03x → 1.0x und signalisiert „gleich passiert's".
                .scaleEffect(controller.isAutoCaptureReady ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: controller.lockState)
                .animation(.easeInOut(duration: 0.15), value: controller.currentQuality.isGood)
                .animation(.easeInOut(duration: 0.25), value: controller.isAutoCaptureReady)
                .allowsHitTesting(false)
            }

            // Top: Close-Button + Auto/Manual-Toggle
            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schließen")

                    Spacer()

                    // Oben rechts: Auto/Manual-Toggle (beide Profile,
                    // siehe `showsCaptureModeToggle`). Tap-to-Focus
                    // braucht keine Reset-UI mehr — der nächste Tap
                    // setzt den Hardware-Fokus an die neue Stelle,
                    // automatisch.
                    if profile.showsCaptureModeToggle {
                        autoManualToggle
                    }
                }
                .padding(.horizontal, AppTheme.Layout.screenPadding)
                .padding(.top, AppTheme.Spacing.sm)

                Spacer()
            }

            // Mitte-oben: Mode-Badge + Hinweistext + optionaler Zoom-
            // Indikator.
            //
            // **Feature A — ScanModeBadge**: zeigt auf jedem Scan-
            // Screen, in welchem Modus der User sich befindet.
            // **Feature B — Zoom-Indikator**: während/direkt nach
            // einem Pinch zeigt eine kleine „1.5x"-Pille den aktuellen
            // Zoom-Faktor. Fade-Out nach 1.5s Inaktivität, damit das
            // UI im Normalbetrieb ruhig bleibt.
            VStack(spacing: 10) {
                Spacer()
                    .frame(height: 72)
                ScanModeBadge(profile: profile, variant: .overlay)
                if profile.showsAttentionOverlay && (isPinching || zoomIndicatorVisible) {
                    zoomIndicatorPill
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
                // **Hint-Banner nur in Profilen mit Dokument-Quad**.
                // FreeText hat kein Dokument-Quad → keine Quad-bezogenen
                // Live-Hinweise wie „Näher rangehen", „Gerader halten".
                // Das weiche Attention-Overlay (gelb/grün, je nach Lock-
                // Status) ist dort die einzige sichtbare Rückmeldung.
                // (User-Feedback: in Manual ist jede Live-Meldung
                // störend, in Auto war „Näher rangehen" zudem falsch.)
                if !profile.showsAttentionOverlay {
                    guidanceHintView
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: zoomIndicatorVisible)
            .animation(.easeInOut(duration: 0.2), value: isPinching)

            // Unten: Manual-Auslöser (nur im Manual-Modus) +
            // Multi-Shot-„Fertig"-Pille (vocabularyList).
            VStack {
                Spacer()
                if !autoCaptureEnabled {
                    manualShutterButton
                        .padding(.bottom, AppTheme.Spacing.xl)
                }
                // **Multi-Shot-Footer** (vocabularyList only): zeigt
                // den Counter + „Fertig"-Button, sobald mind. 1 Bild
                // gesammelt wurde. „Fertig" sendet alle Bilder via
                // `onUseBatch` raus und leert den Buffer.
                if profile == .vocabularyList && !batchCapturedImages.isEmpty {
                    multiShotFooter
                        .padding(.bottom, AppTheme.Spacing.xl)
                }
            }

            // Retry-Overlay (Slice 2): bei Session-Fehlern (Kamera
            // nicht autorisiert, Setup gescheitert, Capture gescheitert)
            // zeigt die View jetzt eine kleine Karte statt still zu
            // loggen. Über die `ScanCaptureMachine` kann sich die View
            // eindeutig auf den Fehler-State stützen.
            if case .captureFailed(let error) = controller.captureMachine.state {
                captureFailedOverlay(error: error)
            }

            // **Capture-Flash-Overlay** (Bug 3 — Shutter-Reaktivität):
            // sobald die FSM auf `.capturing` ist (was sofort beim
            // Tap passiert, noch bevor AVFoundation das Photo liefert),
            // legen wir ein dunkles Flash + Spinner über die Live-
            // Preview. Damit hat der User in den ~200-400 ms bis zum
            // Photo-Delivery (`photoQualityPrioritization=.balanced`)
            // ein klares „es wird gerade aufgenommen"-Feedback,
            // statt scheinbar reaktionsloser Live-Preview.
            if controller.captureMachine.state == .capturing {
                captureFlashOverlay
            }
        }
        // AP1: controller.start() / .stop() / .onCapture werden jetzt
        // vom Parent-View (`SmartScannerView`) gehandelt — dort lebt
        // der Controller-StateObject. Hier bleiben nur lokale
        // onChange-Bindings für die Toggle-UI.
        .onChange(of: autoCaptureEnabled) { _, newValue in
            controller.autoCaptureEnabled = newValue
        }
        .onChange(of: profile) { _, newValue in
            controller.captureProfile = newValue
        }
    }

    // MARK: Auto/Manual-Toggle

    private var autoManualToggle: some View {
        HStack(spacing: 0) {
            toggleButton(title: "Auto", isActive: autoCaptureEnabled) {
                autoCaptureEnabled = true
            }
            toggleButton(title: "Manuell", isActive: !autoCaptureEnabled) {
                autoCaptureEnabled = false
            }
        }
        .background(
            Capsule().fill(Color.black.opacity(0.5))
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    private func toggleButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isActive ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isActive ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Zoom-Indicator Pill (Feature B — Pinch-to-Zoom)

    /// Zeigt den aktuellen Zoom-Faktor als Pille — „1.5x", „2.0x" usw.
    /// Wird bei Tap auf 1x zurückgesetzt (mit animiertem Ramp). Nur
    /// sichtbar während + kurz nach einem Pinch-Gesture.
    private var zoomIndicatorPill: some View {
        Button {
            controller.resetZoomToIdentity()
            pinchBaseZoom = 1.0
            scheduleZoomIndicatorFadeOut()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%.1fx", controller.currentZoomFactor))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if controller.currentZoomFactor > 1.05 {
                    // „× zurücksetzen" als dezenter Hinweis, wenn der
                    // User aus dem 1x-Bereich gezoomt hat — kommuniziert,
                    // dass die Pille tap-bar ist.
                    Text("•  1x")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.black.opacity(0.55))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom \(String(format: "%.1f-fach", controller.currentZoomFactor))")
        .accessibilityHint("Tippen, um auf 1-fach zurückzusetzen")
    }

    // MARK: - Focus Auto-Reset Pill (Tap-to-Lock)

    /// Pille „Auto" oben rechts, wenn der User einen Lock-Bereich
    /// gesetzt hat. Tap → `controller.resetFocusToAuto()` → Overlay
    /// wechselt zurück in den Auto-Detect-Modus.
    ///
    /// Visuell absichtlich leise (kein hartes CTA-Farbschema): der
    /// Reset ist **jederzeit** erreichbar, soll aber nicht über den
    /// Bildinhalt dominieren.
    private var focusAutoResetPill: some View {
        Button {
            controller.resetFocusToAuto()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11, weight: .bold))
                Text("Auto")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.black.opacity(0.5))
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fokus zurücksetzen")
    }

    // MARK: Hinweistext

    private var guidanceHintView: some View {
        HStack(spacing: 6) {
            if controller.currentQuality.isGood {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
            }
            Text(controller.currentQuality.hintText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.black.opacity(0.5))
        )
        .animation(.easeInOut(duration: 0.2), value: controller.currentQuality.hintText)
    }

    // MARK: Manueller Shutter

    /// Vorgeladener Taptic-Generator. **Einmal** pro View-Lifecycle
    /// instanziert und regelmäßig `.prepare()`-ed, damit der erste Tap
    /// ohne Generator-Bootstrap-Latenz (20-40 ms) auslöst.
    @State private var shutterHaptic: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        return g
    }()

    private var manualShutterButton: some View {
        Button {
            // Direkter Pfad — kein async-Hop, keine Animation-Frame-
            // Wait. SwiftUI rendert den Button-Pressed-State sowieso
            // synchron durch den Button-Style selbst. Die vorherige
            // `withAnimation` + `DispatchQueue.main.async`-Kette hat
            // den Tap spürbar verzögert (User-Report „fühlt sich
            // nicht direkt an").
            //
            // Direkt-Path:
            //   1. Pre-prepared Haptic feuert sync (kein Bootstrap-Lag)
            //   2. controller.capturePhoto() sofort — AVFoundation
            //      nimmt die Capture-Anforderung entgegen und signet
            //      die Session-Queue; das eigentliche Photo-Delivery
            //      kommt später, aber die Scene-Preview friert sofort
            //      ein (via `isCapturing`-Guard in `emitGuidance`).
            #if DEBUG
            print("🟢 [UI] Capture button tapped")
            #endif
            shutterHaptic.impactOccurred()
            shutterHaptic.prepare()  // für den nächsten Tap
            controller.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 4)
                    .frame(width: 82, height: 82)
            }
        }
        // Native SwiftUI Button-Press-Animation (Scale/Opacity) —
        // läuft synchron im Render-Pass des Tap-Events, braucht keine
        // explicit `@State` und schafft spürbares Direkt-Feedback.
        .buttonStyle(ShutterPressStyle())
        .accessibilityLabel("Aufnehmen")
    }

    // MARK: - Multi-Shot Footer (vocabularyList)

    /// Footer mit Thumbnail-Strip + „Fertig"-Button. Erscheint im
    /// vocabularyList-Profil, sobald mind. 1 Bild im Batch ist.
    /// Tap auf Thumbnail → entfernt diesen Eintrag (User-Korrektur).
    /// Tap auf „Fertig" → sendet alle gesammelten Bilder als Batch
    /// raus (Galerie-Multi-Pfad in `ScanImportView` übernimmt dann
    /// das sequentielle Per-Bild-Processing).
    @ViewBuilder
    private var multiShotFooter: some View {
        VStack(spacing: 10) {
            // Thumbnail-Strip — letzte 5 Bilder, mit Index. Tap entfernt.
            if batchCapturedImages.count > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(batchCapturedImages.enumerated()), id: \.offset) { index, img in
                            Button {
                                batchCapturedImages.remove(at: index)
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                        )
                                    // Lösch-Indikator
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.white)
                                        .background(Circle().fill(Color.black.opacity(0.55)))
                                        .offset(x: 4, y: -4)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bild \(index + 1) entfernen")
                        }
                    }
                    .padding(.horizontal, AppTheme.Layout.screenPadding)
                }
                .frame(height: 64)
            }

            // Counter + Fertig-Button
            HStack(spacing: 12) {
                Text("\(batchCapturedImages.count) Bild\(batchCapturedImages.count == 1 ? "" : "er")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                Button {
                    finalizeBatch()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text("Fertig")
                            .font(AppTheme.Typography.button)
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppTheme.Colors.cta))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Multi-Shot fertig — alle Bilder verwenden")
            }
        }
    }

    /// Sendet die gesammelten Bilder zum Parent-Callback raus.
    /// Parent-View entscheidet, ob single (`onUse`) oder batch
    /// (`onUseBatch`) — die Verzweigung lebt in `SmartScannerView.finalizeBatch()`.
    private func finalizeBatch() {
        onFinalizeBatch()
    }

    // MARK: - Tap-to-Focus Ring

    /// **iOS-Style Tap-to-Focus-Indikator** — gelbes Quadrat mit
    /// kurzer Pulse-Animation (Apple-Kamera-Standard).
    /// Token-getriggert: jeder neue Tap startet die Animation erneut.
    private struct FocusRingPulse: View {
        let token: UUID
        /// Der `accent` wird zum Tinten der Drag-Linie / Slider drum
        /// rum genutzt. Das Quadrat selbst ist iOS-typisch gelb.
        let accent: Color

        @State private var scale: CGFloat = 1.4
        @State private var opacity: Double = 0.0

        var body: some View {
            // 80×80 ist iOS-Default für den Fokus-Indikator
            // (gelbes Quadrat, 1.5pt Border, abgerundete Ecken).
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.yellow, lineWidth: 1.5)
                .frame(width: 80, height: 80)
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 1)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear { animate() }
                .onChange(of: token) { _, _ in animate() }
        }

        private func animate() {
            // iOS-Pattern: Start groß+transparent → snap auf 1.0+sichtbar → fade out.
            scale = 1.4
            opacity = 0.0
            withAnimation(.easeOut(duration: 0.18)) {
                scale = 1.0
                opacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeIn(duration: 0.32)) {
                    opacity = 0.0
                }
            }
        }
    }

    // MARK: - Exposure-Slider Overlay

    /// **Vertikaler Belichtungs-Slider** neben dem Tap-Punkt.
    /// iOS-Kamera-Style: Sun-Icon oben/unten, vertikale Drag-Bahn,
    /// kleiner Thumb. Auto-Fade nach 3 s ohne Touch — neuer Tap
    /// (`token`-Wechsel) startet die Sichtbarkeit erneut.
    private struct ExposureSliderOverlay: View {
        let token: UUID
        @Binding var bias: Float
        let range: ClosedRange<Float>
        let accent: Color

        @State private var visible: Bool = true
        @State private var fadeWorkItem: DispatchWorkItem? = nil

        // Layout-Konstanten
        private let trackHeight: CGFloat = 140
        private let trackWidth: CGFloat = 4
        private let thumbDiameter: CGFloat = 22
        private let iconSize: CGFloat = 12

        var body: some View {
            ZStack {
                // Sun-Icon oben (heller)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(y: -trackHeight / 2 - 12)
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: trackWidth, height: trackHeight)
                    .overlay(
                        // Aktiv-Strich von Mitte zum Thumb (zeigt Richtung)
                        Capsule()
                            .fill(accent.opacity(0.85))
                            .frame(width: trackWidth, height: abs(thumbOffset))
                            .offset(y: thumbOffset / 2)
                    )
                // Sun-Icon unten (dunkler)
                Image(systemName: "sun.min.fill")
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(.white.opacity(0.65))
                    .offset(y: trackHeight / 2 + 12)
                // Thumb (Drag-Handle) — wird per Gesture verschoben
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(
                        Circle().stroke(accent.opacity(0.85), lineWidth: 2.0)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                    .offset(y: thumbOffset)
                    .gesture(dragGesture)
            }
            .frame(width: 44, height: trackHeight + 36)
            .opacity(visible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.25), value: visible)
            .onAppear { resetVisibility() }
            .onChange(of: token) { _, _ in resetVisibility() }
        }

        /// Pixel-Offset des Thumbs aus der Mitte. Bias-Range linear
        /// auf ±(trackHeight/2) gemappt.
        private var thumbOffset: CGFloat {
            let mid = (range.lowerBound + range.upperBound) / 2
            let half = (range.upperBound - range.lowerBound) / 2
            let normalized = CGFloat(bias - mid) / CGFloat(half)   // -1 ... +1
            // Y wächst nach unten in SwiftUI → negieren, damit Drag
            // nach oben = heller (positives Bias).
            return -normalized * (trackHeight / 2)
        }

        private var dragGesture: some Gesture {
            DragGesture()
                .onChanged { value in
                    visible = true
                    fadeWorkItem?.cancel()
                    let halfTrack = trackHeight / 2
                    // value.location relativ zum Thumb-Center → in Bias umrechnen.
                    // Wir nutzen die translation pro Drag-Event.
                    let yOffset = value.location.y - thumbDiameter / 2
                    let clampedY = max(-halfTrack, min(halfTrack, yOffset))
                    let normalized = -clampedY / halfTrack   // up = positive
                    let mid = (range.lowerBound + range.upperBound) / 2
                    let half = (range.upperBound - range.lowerBound) / 2
                    let newBias = mid + Float(normalized) * half
                    bias = max(range.lowerBound, min(range.upperBound, newBias))
                }
                .onEnded { _ in
                    scheduleFadeOut()
                }
        }

        private func resetVisibility() {
            visible = true
            scheduleFadeOut()
        }

        private func scheduleFadeOut() {
            fadeWorkItem?.cancel()
            let work = DispatchWorkItem { visible = false }
            fadeWorkItem = work
            // 3 s ohne Touch → ausblenden.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        }
    }

    // MARK: - Capture-Flash-Overlay (Bug-3-Reaktivität)

    /// Halbtransparenter dunkler Flash + Spinner. Wird so lange gezeigt,
    /// wie die FSM `.capturing` ist (Shutter-Tap → Photo-Delivery).
    /// Ziel: User-perceived „App reagiert sofort", auch wenn AVFoundation
    /// noch ein paar 100 ms braucht.
    private var captureFlashOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.2)
                Text("Aufnehmen…")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Native-Press-Style für Shutter

    /// SwiftUI-Button-Style, der Scale + Opacity synchron im Render-
    /// Pass des Tap-Events triggert — keine Animation-Defer, keine
    /// async-Queue-Hops. User sieht den Press sofort, noch bevor
    /// das Photo-Delivery startet.
    private struct ShutterPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.84 : 1.0)
                .opacity(configuration.isPressed ? 0.72 : 1.0)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }

    // MARK: - Fehler-Overlay (Slice 2)

    /// Semi-transparenter Full-Screen-Hintergrund + Karte mit Text
    /// und zwei Aktionen (Nochmal, Schließen). Wird nur gezeigt, wenn
    /// `captureMachine.state == .captureFailed`.
    private func captureFailedOverlay(error: SmartScannerError) -> some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.white)

                Text("Aufnahme fehlgeschlagen")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(error.localizedDescription)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                HStack(spacing: 12) {
                    Button {
                        // Retry: Machine zurück in den Live-Flow.
                        // `controller.start()` ist idempotent — die
                        // AVCaptureSession läuft im
                        // `.notAuthorized`-Fall ggf. nicht weiter,
                        // aber der User kriegt das Feedback aus dem
                        // Auth-Alert-Pfad.
                        controller.resetToLive()
                    } label: {
                        Text("Nochmal")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.22)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onCancel()
                    } label: {
                        Text("Schließen")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.85))
            )
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Overlay-Farbe

    /// Bildet den Tracker-Lock-State auf die Overlay-Farbe ab.
    ///
    /// Im **locked**-Zustand übernimmt zusätzlich `quality`: hat der
    /// Tracker das Rechteck gelockt **und** ist die Quality „good"
    /// (nicht tooSmall/tooSkewed/etc.), schalten wir auf Grün — das
    /// ist das Auto-Capture-Signal, das der User aus der vorherigen
    /// Version kennt. Sonst: App-Blau (Akzent).
    private func overlayColor(
        for state: RectangleTracker.LockState,
        quality: SmartScannerGuidance.Quality
    ) -> Color {
        switch state {
        case .searching:
            return Color.white.opacity(0.30)
        case .candidate:
            return Color.white.opacity(0.80)
        case .locked:
            return quality.isGood ? Color.green : AppTheme.Colors.elumiBlue
        }
    }

    /// Linienstärke pro Lock-State — je konfidenter, desto dicker.
    private func overlayLineWidth(for state: RectangleTracker.LockState) -> CGFloat {
        switch state {
        case .searching: return 1.5
        case .candidate: return 2.5
        case .locked:    return 4
        }
    }
}

// MARK: - Preview Layer Host

/// UIViewRepresentable, der das AVCaptureVideoPreviewLayer in die
/// SwiftUI-Hierarchie einbettet. Ein reines Hosting-View.
private struct CameraPreviewLayerView: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer = layer
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        // Frame-Updates übernimmt PreviewHostView via layoutSubviews.
    }

    final class PreviewHostView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}

// MARK: - Quadrilateral Overlay

/// Zeichnet ein 4-Eck aus den Rectangle-Koordinaten. Wird bei guter
/// Erkennung grün eingefärbt, sonst weiß/transparent.
private struct QuadrilateralOverlay: View {
    let corners: RectangleCorners
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Path { path in
            path.move(to: corners.topLeft)
            path.addLine(to: corners.topRight)
            path.addLine(to: corners.bottomRight)
            path.addLine(to: corners.bottomLeft)
            path.closeSubpath()
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
    }
}

// MARK: - FreeText Attention Overlay

/// Weicher Rahmen um den erkannten zentralen Text-/Saliency-Bereich.
///
/// **Konzeptioneller Unterschied zum `QuadrilateralOverlay`**:
/// Der Quad-Rahmen ist eine **verbindliche Aussage** — „ich habe das
/// Dokument gelockt, hier wird gleich abgeschnitten". Der Attention-
/// Rahmen ist ein **orientierendes Zeichen** — „hier sehe ich den
/// zentralen Content". User weiß: Foto nimmt den gesamten Frame auf,
/// der Rahmen ist nur UX-Feedback.
///
/// **Zwei Varianten**:
///   • **Auto** (`isLocked == false`) — weiß, Opacity 0.6 Border,
///     Fill 0.08, subtiler Glow. Der Rahmen folgt dem Attention-
///     Tracker-Output.
///   • **Locked** (`isLocked == true`) — App-Blau, Opacity 0.85
///     Border, Fill 0.14, Lock-Icon oben links.
///
/// **Rendering via Path** (User-Bug „Lock sitzt an ganz anderer
/// Position"): Die frühere Version nutzte `.position(x:y:)`, das in
/// SwiftUI die **Parent-Coord-Space** verwendet. Wenn der Parent
/// safe-area-restricted ist (wie hier), kommt ein Top-Offset von
/// ~47pt dazu — der Locked-Rect wanderte entsprechend nach unten.
/// Path-basiertes Rendering nutzt die **eigene** Coord-Space der
/// View, die mit `.ignoresSafeArea()` auf Full-Screen expandiert ist
/// — dieselbe Semantik wie beim `QuadrilateralOverlay`, der genau
/// deshalb korrekt sitzt.
private struct AttentionRegionOverlay: View {
    let region: CGRect
    let isLocked: Bool

    private var borderColor: Color {
        isLocked ? AppTheme.Colors.elumiBlue : Color.white
    }
    private var borderOpacity: Double {
        isLocked ? 0.85 : 0.6
    }
    private var fillColor: Color {
        isLocked ? AppTheme.Colors.elumiBlue : Color.white
    }
    private var fillOpacity: Double {
        isLocked ? 0.14 : 0.08
    }
    private var glowColor: Color {
        isLocked ? AppTheme.Colors.elumiBlue : Color.white
    }
    private var lineWidth: CGFloat {
        isLocked ? 2.5 : 2
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Fill + Stroke als zwei separate Paths — beide beziehen
            // sich auf die View-eigene Coord-Space (full-screen mit
            // `.ignoresSafeArea()` außen), keine safe-area-Drift.
            Path(roundedRect: region, cornerSize: CGSize(width: 12, height: 12))
                .fill(fillColor.opacity(fillOpacity))
            Path(roundedRect: region, cornerSize: CGSize(width: 12, height: 12))
                .stroke(
                    borderColor.opacity(borderOpacity),
                    style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round)
                )

            // Lock-Icon oben links — nur im Locked-State. Offset gegen
            // den Region-Origin, damit die Pille innerhalb der Box
            // sitzt (8pt Padding).
            if isLocked {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Gesperrt")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(borderColor.opacity(0.85))
                )
                .offset(x: region.minX + 8, y: region.minY + 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .shadow(color: glowColor.opacity(isLocked ? 0.45 : 0.35), radius: 8, x: 0, y: 0)
    }
}

// MARK: - Controller

/// SwiftUI-Brücke zum `SmartScannerSession`-Delegate. Hält den Published-
/// State (currentCorners, currentQuality) für die UI bereit und leitet
/// Capture-Events nach oben weiter.
@MainActor
private final class SmartScannerController: ObservableObject {
    let previewLayer: AVCaptureVideoPreviewLayer
    private let session: SmartScannerSession

    @Published var currentCorners: RectangleCorners?
    /// Raw Vision Detection für das Debug-Overlay (rot).
    @Published var rawCorners: RectangleCorners?
    @Published var currentQuality: SmartScannerGuidance.Quality = .noRectangle
    /// Drei-Stufen-Lock-State vom Tracker — searching/candidate/locked.
    /// Steuert die Overlay-Farbe: searching dezent, candidate stärker,
    /// locked in App-Akzent (blau/pink).
    @Published var lockState: RectangleTracker.LockState = .searching

    /// **AP12** — true, wenn der AutoCaptureController in der Ready-
    /// Phase ist (≈0.3 s vor dem Shutter-Fire). UI nutzt das, um einen
    /// kurzen Puls auf dem Overlay zu zeigen.
    @Published var isAutoCaptureReady: Bool = false

    /// **FreeText-Attention**: weiches Overlay-Rect in View-Layer-
    /// Koordinaten. Nur im FreeText-Profil belegt (vocabularyList
    /// nutzt Rectangle-Tracker). Nil, wenn aktuell weder Text noch
    /// Saliency einen hinreichend zentralen Bereich liefert.
    @Published var attentionRegion: CGRect?

    /// **Tap-to-Lock**: aktueller Fokus-Modus. Default `.auto`
    /// (Attention-Tracker bestimmt Overlay-Position). Wechselt zu
    /// `.locked(rect)`, wenn der User im FreeText-Capture-View auf
    /// eine Stelle tippt — ab dann bleibt der Overlay dort stabil,
    /// bis der User den Reset-Button tippt.
    @Published var focusMode: FocusMode = .auto

    /// **Pinch-to-Zoom**: aktueller Zoom-Faktor. Läuft über das
    /// AVCaptureDevice-Zoom (hardware-seitig) — Range 1.0 bis 5.0.
    /// Die View zeigt einen Indikator basierend auf diesem Wert.
    @Published var currentZoomFactor: CGFloat = 1.0

    /// **Tap-to-Focus**: Layer-Position des letzten Taps. View nutzt
    /// das, um den Fokus-Ring an dieser Stelle zu rendern. Bleibt
    /// nach dem Fade-Out bestehen — `lastTapFocusToken` zwingt die
    /// Animation bei jedem neuen Tap zu re-starten.
    @Published var lastTapFocusPoint: CGPoint? = nil
    @Published var lastTapFocusToken: UUID = UUID()

    /// **Belichtungs-Korrektur** (Slider neben Tap-Punkt).
    /// User-Bereich −2.0 … +2.0 EV; Default 0. Bei jedem neuen Tap-
    /// to-Focus wird der Wert auf 0 zurückgesetzt (frische Stelle =
    /// frische Auto-Belichtung). View ruft `setExposureBias(_:)`
    /// während des Drag auf, der die Session direkt durchsticht.
    @Published var currentExposureBias: Float = 0

    /// User-Range für den Slider (Apple's `device.minExposureTargetBias`
    /// liegt typisch bei -8 EV, das wäre für unsere Use-Cases zu viel).
    static let exposureBiasRange: ClosedRange<Float> = -2.0...2.0

    /// Haptic für den Lock-Event — etwas kräftiger als Auto-Capture-
    /// Ready, damit der User den Lock als **bewusste Aktion** wahrnimmt.
    private let focusLockHaptic = UIImpactFeedbackGenerator(style: .medium)

    /// Explizite State Machine (Slice 2). Läuft heute **parallel** zu
    /// den oben genannten Flags; künftige Slices konsolidieren die
    /// Flags auf die Machine. `captureStateLabel` ist das Read-Only-
    /// Projection-Field für SwiftUI-`value:`-Animationen.
    let captureMachine = ScanCaptureMachine()

    var autoCaptureEnabled: Bool {
        get { session.autoCaptureEnabled }
        set { session.autoCaptureEnabled = newValue }
    }

    /// Capture-Profil — propagiert in die Session, die damit
    /// `allowsAutoCapture` gated und weitere Slice-2-Features an das
    /// Profil binden wird (Tracker-Config, CaptureStateMachine).
    var captureProfile: ScanCaptureProfile {
        get { session.captureProfile }
        set { session.captureProfile = newValue }
    }

    /// Setzen vom Parent — feuert mit dem aufgenommenen UIImage
    /// plus dem zur Shutter-Zeit gelockten Live-Quad (nil falls nie
    /// gelockt). Der Quad ist Fallback fürs Post-Capture-Refinement.
    var onCapture: ((UIImage, VNRectangleObservation?, CGRect?, CGSize?, UUID) -> Void)?

    /// Haptic-Feedback beim Auto-Capture.
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    /// Generation-Counter für Capture-Timeouts (AP Capture-Determinismus).
    /// Jeder `capturePhoto()`-Aufruf bekommt eine frische Generation;
    /// der zugehörige 1.5s-Timeout cancelt sich selbst, sobald eine
    /// neuere Capture läuft oder das Photo-Delivery schon erfolgt ist.
    /// Verhindert "Zombie"-Timeouts, die den Machine-State einer
    /// bereits abgeschlossenen Runde fälschlich auf `.captureFailed`
    /// setzen würden.
    private var captureGeneration: Int = 0

    /// **Nested-ObservableObject-Fix**: `ScanCaptureMachine` ist ein
    /// eigenes `ObservableObject`, das eigene `@Published`-Events sendet.
    /// SwiftUI-Views subscriben aber nur auf **diesen** Controller
    /// (`@StateObject`), nicht transitiv auf die Machine. Wenn die
    /// Machine ihren State ändert (z. B. `.locked → .capturing` beim
    /// Shutter-Tap) und keine andere `@Published`-Property auf dem
    /// Controller gleichzeitig fires, bleibt der View stumm.
    ///
    /// Symptom (User-Report „ausgelöst aber nichts passiert in freier
    /// Modus"): in freeText ist `runsLiveDetection == false`, der
    /// Tracker feuert nie `smartScannerDidUpdateGuidance` → keine
    /// @Published-Änderungen auf Controller-Seite → Machine
    /// transitioniert, View sieht es nicht, Preview/Processing werden
    /// nie gerendert.
    ///
    /// Fix: Controller leitet die `objectWillChange`-Events der
    /// Machine auf sein **eigenes** `objectWillChange` weiter.
    /// Damit re-rendert die View bei jedem Machine-Event.
    private var machineSubscription: AnyCancellable?

    init() {
        self.session = SmartScannerSession()
        self.previewLayer = session.previewLayer
        session.delegate = self
        haptic.prepare()

        machineSubscription = captureMachine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    func start() {
        // idle → searching beim ersten Start; Session beginnt asynchron,
        // tracker-Updates überschreiben searching → candidate → locked.
        captureMachine.transition(to: .searching)
        session.start()
    }

    /// Tap-to-Focus (Slice 5). Die View reicht uns den Layer-Point aus
    /// dem `onTapGesture` — die Session rechnet intern um.
    func tapToFocus(at layerPoint: CGPoint) {
        session.tapToFocus(atLayerPoint: layerPoint)
    }
    func stop() {
        session.stop()
        captureMachine.reset()
    }
    func capturePhoto() {
        // Button-Guard (Capture-Determinismus): wenn bereits ein
        // Capture läuft (Machine == .capturing oder .refining), neue
        // Taps verwerfen. Verhindert Double-Trigger durch nervöse
        // Taps oder Auto-Capture-Überlapp.
        let currentState = captureMachine.state
        if currentState == .capturing {
            #if DEBUG
            print("📷 [Capture] Duplicate tap ignored — already capturing")
            #endif
            return
        }
        if case .refining = currentState {
            #if DEBUG
            print("📷 [Capture] Tap ignored — refining in progress")
            #endif
            return
        }

        // Shutter gedrückt: Machine auf `.capturing`. Vermeidet Re-
        // Entry über Tracker-Updates und erlaubt der UI, ein
        // Shutter-Feedback-Overlay zu zeigen.
        captureMachine.transition(to: .capturing)
        session.capturePhoto()

        // **Capture-Determinismus** — Timeout-Fallback (2.0s).
        // Wenn AVFoundation den Delegate aus unerwarteten Gründen
        // nicht feuert (z. B. Hardware-Fehler ohne Error-Return),
        // würde die Machine ewig in `.capturing` hängen und die UI
        // einfrieren. Der Timeout zwingt nach 2s in einen
        // definierten Fehlerzustand → User sieht Retry-Card.
        captureGeneration += 1
        let gen = captureGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.captureGeneration == gen else { return }
            if self.captureMachine.state == .capturing {
                #if DEBUG
                print("❌ [Capture] Timeout after 2.0s — forcing failure (delegate never fired)")
                #endif
                self.captureMachine.transition(to: .captureFailed(.captureFailed))
            }
        }
    }

    // MARK: - View-gesteuerte Transitionen

    /// Wird aus `SmartScannerView.runProcessing` aufgerufen, sobald das
    /// Still-Photo angekommen und die Pipeline startet.
    func markRefining(raw: UIImage) {
        captureMachine.transition(to: .refining(raw: raw))
    }

    /// Pipeline fertig — Review-Stage kann zeigen.
    func markReviewReady(corrected: UIImage, report: ImageQualityAnalyzer.Report) {
        captureMachine.transition(to: .reviewReady(corrected: corrected, report: report))
    }

    /// User hat „Neu aufnehmen" getippt — zurück in den Live-Flow.
    /// Setzt auch den Fokus-Modus zurück, damit der neue Scan ohne
    /// vorselektierten Lock startet.
    func resetToLive() {
        captureMachine.transition(to: .searching)
        if focusMode.isLocked {
            focusMode = .auto
            session.focusMode = .auto
        }
    }

    // MARK: - Tap-to-Lock (FreeText)

    /// Nimmt einen Tap-Punkt in Layer-Koordinaten entgegen und lockt
    /// eine Region um diesen Punkt als Fokus-Bereich.
    /// Haptik-Feedback signalisiert dem User, dass der Lock sitzt.
    ///
    /// **Tap-to-Focus** (FreeText) — setzt Hardware-Fokus + Belichtung
    /// am Tap-Punkt (iOS-Kamera-Standard) und triggert einen kurz
    /// aufploppenden Fokus-Ring an der View-Position. Kein Lock-Box-
    /// Overlay, keine Region-Wahl — der Tap ist nur ein Hardware-
    /// Hint an die Kamera.
    ///
    /// Ersetzt die frühere `lockFocus(atLayerPoint:)`-Logik, die
    /// funktional keinen Effekt mehr hatte (nach dem Stabilisierungs-
    /// Slice wurde der Attention-basierte Crop entfernt).
    func tapToFocus(atLayerPoint layerPoint: CGPoint) {
        // 1) Hardware-Fokus (über die Session, die das CaptureDevice hält).
        session.tapToFocus(atLayerPoint: layerPoint)
        // 2) Visueller Ring — UI rendert ihn an `lastTapFocusPoint` und
        //    fadet nach 0.6 s aus (siehe `FocusRingPulse`-View).
        lastTapFocusPoint = layerPoint
        lastTapFocusToken = UUID()
        // 3) Belichtungs-Korrektur **zurück auf 0 EV** — neuer Tap =
        //    frische Auto-Belichtung am neuen Punkt. Wenn der User
        //    danach am Slider zieht, baut er auf dem frischen Auto-
        //    Wert auf statt auf dem alten Bias.
        currentExposureBias = 0
        session.setExposureBias(0)
        // 4) Haptic-Feedback (gleicher Generator wie früherer Lock-Tap).
        focusLockHaptic.prepare()
        focusLockHaptic.impactOccurred()
        #if DEBUG
        print(String(
            format: "🎯 [TapToFocus] layer=(%.1f,%.1f)",
            layerPoint.x, layerPoint.y
        ))
        #endif
    }

    /// Reset auf Auto-Detect — User hat den „Auto"-Button getippt oder
    /// doppelt-getippt (je nach UI-Entscheidung).
    func resetFocusToAuto() {
        focusMode = .auto
        session.focusMode = .auto
        #if DEBUG
        print("🎯 [FocusLock] reset → .auto")
        #endif
    }

    // MARK: - Pinch-to-Zoom (Feature B)

    /// Setzt den Zoom-Faktor hart — aufgerufen aus der
    /// MagnificationGesture während des Pinchs. Spiegelt den Ist-
    /// Wert (nach Clamping im Session-Code) zurück in `currentZoomFactor`,
    /// damit die UI (Zoom-Indikator) den echten Wert anzeigt.
    func updateZoom(to factor: CGFloat) {
        let applied = session.updateZoom(to: factor)
        currentZoomFactor = applied
    }

    /// **Belichtungs-Korrektur** (Slider-Drag). Aktualisiert den
    /// Published-Wert (UI bleibt synchron) und reicht ihn in die
    /// Session durch (Hardware-Bias).
    func setExposureBias(_ bias: Float) {
        currentExposureBias = bias
        session.setExposureBias(bias)
    }

    /// Reset auf 1x mit animiertem Übergang (Ramp statt Hard-Set).
    func resetZoomToIdentity() {
        session.rampZoom(to: 1.0, rate: 4.0)
        currentZoomFactor = 1.0
    }
}

extension SmartScannerController: SmartScannerSessionDelegate {
    func smartScannerDidUpdateGuidance(_ guidance: SmartScannerGuidance) {
        self.currentCorners = guidance.corners
        self.rawCorners = guidance.rawCorners
        self.currentQuality = guidance.quality
        self.lockState = guidance.lockState
        self.isAutoCaptureReady = guidance.isAutoCaptureReady
        self.attentionRegion = guidance.attentionRegion

        // Tracker-Updates nur dann auf die Machine durchreichen, wenn
        // wir in einer Live-Stufe sind. Während `.capturing` oder
        // `.refining` bleibt das Overlay eingefroren — Tracker-Updates
        // hier würden nur Inkonsistenz erzeugen.
        if captureMachine.state.isLiveStage || captureMachine.state == .idle {
            let next: ScanCaptureState
            switch guidance.lockState {
            case .searching: next = .searching
            case .candidate: next = .candidate
            case .locked:    next = .locked
            }
            if next != captureMachine.state {
                captureMachine.transition(to: next)
            }
        }
    }

    func smartScannerDidCapturePhoto(
        _ image: UIImage,
        frozenQuad: VNRectangleObservation?,
        frozenAttentionBox: CGRect?,
        previewLayerSize: CGSize?,
        captureID: UUID
    ) {
        #if DEBUG
        let pxW = Int(image.size.width * image.scale)
        let pxH = Int(image.size.height * image.scale)
        let attBoxText = frozenAttentionBox.map { String(format: "(%.2f,%.2f,%.2f,%.2f)", $0.minX, $0.minY, $0.width, $0.height) } ?? "nil"
        let plsText = previewLayerSize.map { String(format: "(%.0f×%.0f)", $0.width, $0.height) } ?? "nil"
        print("🟣 [Controller \(captureID.shortID)] received image \(pxW)×\(pxH), frozenQuad=\(frozenQuad != nil ? "yes" : "nil"), frozenAttention=\(attBoxText), previewLayerSize=\(plsText)")
        #endif
        haptic.impactOccurred()
        // **AP1-Fix**: Auto-Capture-Pfad geht direkt von der Session
        // aus (`emitGuidance` → `session.capturePhoto()`) ohne vorher
        // den Controller's `capturePhoto()` zu traversieren. Dadurch
        // fehlt die Machine-Transition `.locked → .capturing`, die
        // `canTransition` aber erwartet, bevor `.refining` legal ist.
        //
        // Normalisierung: wenn wir nicht schon in `.capturing` sind,
        // transitionieren wir first dort hin (legal aus .locked) und
        // dann nach `.refining`. So funktioniert sowohl Manual-
        // Capture (Machine war schon auf `.capturing`, Transition ist
        // legal identitätsfunktion) als auch Auto-Capture.
        if captureMachine.state != .capturing {
            captureMachine.transition(to: .capturing)
        }
        captureMachine.transition(to: .refining(raw: image))
        onCapture?(image, frozenQuad, frozenAttentionBox, previewLayerSize, captureID)
    }

    func smartScannerDidFail(_ error: SmartScannerError) {
        // Fail-Handling: Machine markiert den Fehler, die View zeigt
        // die Retry-Karte. Kein stilles `print` mehr — der User
        // bekommt jetzt klares Feedback.
        #if DEBUG
        print("📷 [SmartScanner] Fehler: \(error.localizedDescription)")
        #endif
        captureMachine.transition(to: .captureFailed(error))
    }
}
