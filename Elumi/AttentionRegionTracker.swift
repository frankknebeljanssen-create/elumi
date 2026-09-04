import Foundation
import Vision
import CoreVideo
import CoreGraphics

/// Live-Tracker für den FreeText-Modus. Erkennt den zentralen Text-/
/// Content-Bereich, auf den die Kamera gerade „zielt", und liefert eine
/// EMA-geglättete Bounding-Box zurück.
///
/// **Konzeptionelle Abgrenzung zum `RectangleTracker`**:
/// Der RectangleTracker sucht Dokument-Kanten — „finde das Papier".
/// Der AttentionRegionTracker sucht Aufmerksamkeits-Bereiche — „was
/// ist gerade im Fokus". Für Poster, Müslipackungen, Magazincover,
/// Zeitungsartikel etc. existiert kein klares Rechteck-Objekt; aber
/// es gibt immer einen zentralen Content-Cluster (Überschrift, Logo,
/// Textblock), auf den der User zielt.
///
/// **Strategie** (aus der Produkt-Spec):
///
/// 1. **Text-Detection primär** (`VNRecognizeTextRequest` im Fast-Modus):
///    schnelle Box-Erkennung. Wenn Text-Boxes vorhanden, union über
///    alle → zentraler Text-Bereich.
/// 2. **Saliency-Fallback** (`VNGenerateAttentionBasedSaliencyImageRequest`):
///    wenn kein Text gefunden wird (z. B. reines Produkt-Foto), liefert
///    Saliency die visuell auffälligen Bereiche. Bestes Feld gewinnt.
///
/// **Scoring** (gewichtet nach User-Intuition):
/// ```
/// score = area * 0.7 + centerProximity * 0.3
/// ```
/// Zentrums-Gewichtung, weil der User in aller Regel auf die Mitte
/// zielt. Sehr kleine Randboxen werden dadurch herausgefiltert.
///
/// **Smoothing**: EMA mit Faktor 0.4 (neu) / 0.6 (alt) auf Position
/// UND Größe. Vermeidet Zittern und Springen zwischen Frames.
///
/// **Throttling**: Der Aufrufer (SmartScannerSession) drosselt
/// captureOutput-Frames bereits auf ~10 Hz; dieser Tracker muss selbst
/// nichts zusätzlich dämpfen.
///
/// **Thread-Modell**: `process(...)` läuft auf der sessionQueue und
/// blockiert während der Vision-Request-Perform — akzeptabel, weil
/// der Caller bereits auf einem Background-Thread sitzt und wir keine
/// weiteren Dispatch-Hops wollen.
final class AttentionRegionTracker {

    // MARK: - Ergebnistyp

    struct Region {
        /// Bounding-Box in **Vision-normalisierten Koordinaten**
        /// (0…1 auf beiden Achsen, Ursprung unten links).
        let boundingBox: CGRect
        /// Scoring-Wert (0…1-ish, höher = relevanter). Nur zum Debug.
        let score: Double
        /// Primär Text-Detection oder Saliency-Fallback?
        let source: Source
        /// True, wenn die geglättete Box über mehrere Frames nur noch
        /// marginale Drift zeigt. Signal für den Auto-Capture-Pfad
        /// in FreeText — ersetzt den Rectangle-basierten Lock-State.
        let isStable: Bool

        enum Source {
            case text
            case saliency
        }
    }

    // MARK: - Config

    /// Smoothing-Faktor für die neue Messung. `smoothed = (1-α)*prev + α*new`.
    /// **User-Feedback „Rahmen zuckt hin und her"**: von 0.4 auf 0.22
    /// reduziert. 78 % altes Signal → sichtbar ruhiger, reagiert
    /// dennoch auf Szenenwechsel in ~1.5 s. Zu niedrig wäre <0.15
    /// (Box-Nachlauf wird spürbar träge).
    private let alpha: Double = 0.22

    /// Minimaler Score, damit eine Region überhaupt als „gefunden" gilt.
    /// 0.05 ist tief genug, dass zentrale Boxen immer durchgehen
    /// (centerProximity*0.3 allein ≥ 0.3 bei mittigen Boxen), aber
    /// Randartefakte < 7 % Fläche filtert.
    private let minScoreThreshold: Double = 0.05

    /// Ein Text-Box-Kandidat gilt als Outlier (und wird aus der Union
    /// gefiltert), wenn sein Mittelpunkt weiter als diese Distanz vom
    /// Centroid aller Boxen entfernt ist. Normalisiert (0…~0.7).
    /// Verhindert, dass ein vereinzelter Randtext die Union auf
    /// Bildgröße aufbläht und die Box zwischen Zuständen springt.
    private let textClusterOutlierDistance: Double = 0.30

    /// Minimale Text-Höhe (relative zur Bildhöhe), die als Signal
    /// zählt. Vision liefert teils Mikro-Boxen um Dreck oder
    /// Shadow-Kanten; darunter ist's Rauschen.
    private let minRelativeTextHeight: CGFloat = 0.015

    /// Expansion-Faktor für die Text-Union. Vergrößert die finale
    /// Box so, dass der Overlay das **Objekt** (das den Text trägt),
    /// nicht nur die Schrift umschließt.
    ///
    /// Von 0.25 auf 0.15 reduziert — 25 % pro Seite = 50 % Gesamt-
    /// Zunahme, das ging bei text-nahen Captures (Screenshots mit
    /// randvollem Text) über den Bildrand raus und der Overlay
    /// verschwand visuell. 15 % ist groß genug, um das Motiv um den
    /// Text zu zeigen, bleibt aber im Frame.
    private let textUnionExpansion: CGFloat = 0.15

    /// Minimale Kantenlänge, die der Overlay-Rahmen haben soll
    /// (normalisiert, 0…1). Verhindert winzige Boxen bei sehr
    /// kleinen Text-/Saliency-Clustern — wenn die Detection z. B.
    /// nur eine kurze Zeile findet, würde der Rahmen dem Objekt
    /// nicht helfen. 0.30 = mind. 30 % der Bildkante als Quadrat-
    /// Mindestgröße.
    private let minEdge: CGFloat = 0.30

    /// Sobald wir N Frames in Folge nichts gefunden haben, setzen wir
    /// die geglättete Box zurück. Vorher 8 (~0.8s bei 10 Hz) — das
    /// war bei flackernder Detection zu aggressiv und hat die Box
    /// zu oft auf nil gezogen. 15 Frames (~1.5 s) hält den Overlay
    /// über kurze Detection-Aussetzer hinweg stabil.
    private let resetAfterMissingFrames = 15

    /// **Hysterese**: ein neuer Detection-Fund muss sich über
    /// `minConsecutiveHits` Frames bestätigen, bevor der Overlay
    /// erscheint.
    ///
    /// Von 2 auf 1 reduziert (User-Feedback „gar kein overlay mehr
    /// sichtbar"): 2 Frames = 200 ms verzögerter Erstanzeige. In
    /// Kombination mit der aggressiven Auto-Capture-Pipeline (siehe
    /// Session) war das eine sichtbare Lücke. Single-Frame-False-
    /// Positives werden weiterhin vom EMA-Smoothing + Outlier-
    /// Filter + Score-Schwelle abgefangen — keine Hysterese mehr nötig.
    private let minConsecutiveHits = 1

    /// Stabilität: maximale normalisierte Drift (Mittelpunkt +
    /// halbe Größenänderung), die als „stabil" durchgeht. 0.03 ~
    /// 3 % der Bildkante — erlaubt leichtes Atmen der Box, filtert
    /// echte Bewegung.
    private let stabilityDriftThreshold: Double = 0.03

    /// Wie viele Frames die Box kaum driften muss, um als stabil zu
    /// gelten.
    ///
    /// Von 4 auf 8 erhöht (User-Feedback „Auto-Modus löst aus, bevor
    /// man den Overlay sieht"): 4 Frames = 400 ms Stabilitätsfenster
    /// war zu knapp. Bei 10 Hz = 800 ms. In Kombination mit
    /// AutoCaptureController-Streak (300 ms) + Ready-Phase (300 ms)
    /// kommt man auf ~1.4 s Overlay-Sichtbarkeit bevor der Shutter
    /// feuert — genug, um das Framing wahrzunehmen.
    private let stabilityFramesRequired: Int = 8

    // MARK: - State

    /// Letzte geglättete Box (in Vision-Koordinaten). Nil, wenn zu
    /// viele Frames in Folge nichts gefunden haben.
    private var smoothedBox: CGRect?
    private var missingFrameCount: Int = 0
    private var consecutiveHitCount: Int = 0

    /// Referenz-Box zum aktuellen Stabilitäts-Streak. Wenn die
    /// aktuelle Box zu sehr davon drift, wird die Referenz neu
    /// gesetzt und der Streak zurückgespult.
    private var stabilityReferenceBox: CGRect?
    private var stabilityFrameCount: Int = 0

    // MARK: - API

    /// Verarbeitet einen einzelnen Pixel-Buffer und liefert die aktuell
    /// beste Attention-Region zurück. Lifetime-Ergebnis ist EMA-
    /// geglättet; aufeinanderfolgende Aufrufe sehen also weiche
    /// Bewegungen statt Sprünge.
    ///
    /// Läuft **synchron** — Caller ist die sessionQueue.
    func process(pixelBuffer: CVPixelBuffer) -> Region? {
        // 1. Text-Detection zuerst (fast).
        if let textRegion = detectTextRegion(pixelBuffer: pixelBuffer) {
            return smoothingUpdate(newBox: textRegion.boundingBox,
                                   score: textRegion.score,
                                   source: .text)
        }

        // 2. Saliency-Fallback.
        if let salientRegion = detectSalientRegion(pixelBuffer: pixelBuffer) {
            return smoothingUpdate(newBox: salientRegion.boundingBox,
                                   score: salientRegion.score,
                                   source: .saliency)
        }

        // 3. Nichts gefunden — ggf. zurücksetzen + Hit/Stability-Streaks brechen.
        consecutiveHitCount = 0
        stabilityFrameCount = 0
        stabilityReferenceBox = nil
        missingFrameCount += 1
        if missingFrameCount >= resetAfterMissingFrames {
            smoothedBox = nil
        }
        return nil
    }

    /// Reset beim Profil-Wechsel oder Stop. Sonst bleibt ein alter
    /// Overlay-Rahmen beim nächsten Start sichtbar.
    func reset() {
        smoothedBox = nil
        missingFrameCount = 0
        consecutiveHitCount = 0
        stabilityFrameCount = 0
        stabilityReferenceBox = nil
    }

    // MARK: - Detection: Text

    private struct Candidate {
        let boundingBox: CGRect
        let score: Double
    }

    private func detectTextRegion(pixelBuffer: CVPixelBuffer) -> Candidate? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = Float(minRelativeTextHeight)

        // **Orientation-Fix** (User-Report „findet nichts obwohl Objekt
        // leicht erkennbar"): der RectangleTracker nutzt `.up`, weil
        // die AVCapture-Video-Connection `videoRotationAngle = 90`
        // setzt und Apple den PixelBuffer daher **schon rotiert**
        // ausliefert. Der Attention-Tracker muss dasselbe annehmen;
        // vorher `.right` ließ Vision das Bild nochmals drehen,
        // wodurch Text-Detection am echten Inhalt vorbeisuchte.
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        // Boxes filtern:
        //   1. Zu flache Boxen raus (sub-minRelativeTextHeight, extra
        //      Sicherheit trotz request.minimumTextHeight — Vision
        //      liefert gelegentlich dennoch welche).
        //   2. Outlier-Boxen zum Centroid raus (verhindert, dass ein
        //      vereinzelter Randtext die Union aufs ganze Bild
        //      ausdehnt und den Overlay ruckhaft wandern lässt).
        let filteredBoxes = filterClusteredBoxes(
            observations
                .map { $0.boundingBox }
                .filter { $0.height >= minRelativeTextHeight }
        )
        guard !filteredBoxes.isEmpty else { return nil }

        // Union über den gefilterten Cluster — zusammenhängender
        // Text-Block bleibt eine Box; einzelne Edge-False-Positives
        // sind vorher entfernt.
        guard let union = unionOfBoxes(filteredBoxes) else { return nil }

        // **Object-Padding** (User-Feedback „Rechteck viel kleiner
        // als das erkennbare Objekt"): Die Text-Union deckt meist
        // nur die Schrift, nicht die komplette Packung/Poster.
        // Vergrößern wir sie um einen festen Prozentsatz, wirkt der
        // Overlay so, als umschließe er das **Objekt**, das der
        // Text bewohnt — und die Stabilitäts-Erkennung greift
        // früher (breitere Box = mehr Toleranz).
        let expanded = expandBox(union, byFraction: textUnionExpansion)

        let score = scoreForBox(expanded)
        guard score >= minScoreThreshold else { return nil }
        return Candidate(boundingBox: expanded, score: score)
    }

    /// Expansion, die um eine Box „um das Motiv herum" erweitert. Clampt
    /// auf [0, 1] × [0, 1], damit die Box das Frame nicht verlässt.
    /// Erzwingt zusätzlich eine **Mindestkantenlänge** (`minEdge`) —
    /// wenn die Box nach Padding noch zu klein ist, vergrößern wir
    /// sie um ihren Mittelpunkt bis zur Mindestgröße, damit der User
    /// überhaupt einen greifbaren Rahmen sieht.
    private func expandBox(_ box: CGRect, byFraction fraction: CGFloat) -> CGRect {
        let dx = box.width * fraction
        let dy = box.height * fraction
        var raw = CGRect(
            x: box.minX - dx,
            y: box.minY - dy,
            width: box.width + 2 * dx,
            height: box.height + 2 * dy
        )

        // Mindestgröße durchsetzen: wenn Breite oder Höhe unter
        // `minEdge` liegen, um den Mittelpunkt aufstocken.
        if raw.width < minEdge {
            let cx = raw.midX
            raw.origin.x = cx - minEdge / 2
            raw.size.width = minEdge
        }
        if raw.height < minEdge {
            let cy = raw.midY
            raw.origin.y = cy - minEdge / 2
            raw.size.height = minEdge
        }

        return raw.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Filtert aus einer Menge von Text-Boxen die Outlier heraus:
    /// Boxen, deren Mittelpunkt weiter als `textClusterOutlierDistance`
    /// vom gemeinsamen Centroid entfernt liegt. Wichtig, wenn z. B.
    /// auf einem Müslipackungs-Frame das zentrale Logo UND eine
    /// kleine Strichcode-Zeile am Rand detektiert werden — letztere
    /// soll den Overlay nicht überstrecken.
    private func filterClusteredBoxes(_ boxes: [CGRect]) -> [CGRect] {
        guard boxes.count > 1 else { return boxes }
        // Centroid aller Box-Mittelpunkte.
        var cx = CGFloat(0), cy = CGFloat(0)
        for b in boxes { cx += b.midX; cy += b.midY }
        cx /= CGFloat(boxes.count)
        cy /= CGFloat(boxes.count)
        return boxes.filter { b in
            let dx = Double(b.midX - cx)
            let dy = Double(b.midY - cy)
            return hypot(dx, dy) <= textClusterOutlierDistance
        }
    }

    private func unionOfBoxes(_ boxes: [CGRect]) -> CGRect? {
        guard let first = boxes.first else { return nil }
        var minX = first.minX
        var minY = first.minY
        var maxX = first.maxX
        var maxY = first.maxY
        for box in boxes.dropFirst() {
            minX = min(minX, box.minX)
            minY = min(minY, box.minY)
            maxX = max(maxX, box.maxX)
            maxY = max(maxY, box.maxY)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Detection: Saliency

    private func detectSalientRegion(pixelBuffer: CVPixelBuffer) -> Candidate? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        // Siehe detectTextRegion: PixelBuffer kommt bereits rotiert
        // (videoRotationAngle=90), deshalb `.up`.
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first as? VNSaliencyImageObservation,
              let salientObjects = observation.salientObjects,
              !salientObjects.isEmpty
        else {
            return nil
        }

        // Pro salientem Objekt scoren, bestes behalten. Padding auch
        // hier anwenden, damit Overlay das Objekt sichtbar umschließt.
        let scored = salientObjects.map { obj -> Candidate in
            let expanded = expandBox(obj.boundingBox, byFraction: textUnionExpansion)
            return Candidate(boundingBox: expanded, score: scoreForBox(expanded))
        }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }
        guard best.score >= minScoreThreshold else { return nil }
        return best
    }

    // MARK: - Scoring

    /// Gewichtung `area * 0.7 + centerProximity * 0.3`. User zielt in
    /// aller Regel auf die Mitte — Rand-Artefakte (Tisch, Hand) werden
    /// dadurch systematisch abgewertet.
    private func scoreForBox(_ box: CGRect) -> Double {
        let area = Double(box.width * box.height)          // 0...1
        let cx = Double(box.midX)
        let cy = Double(box.midY)
        // Radialer Abstand vom Bildmittelpunkt (0.5, 0.5). Maximum
        // ≈ 0.707 in den Ecken. Normalisiert auf 0…1.
        let dist = hypot(cx - 0.5, cy - 0.5) / 0.7071
        let centerProximity = max(0, 1 - dist)
        return area * 0.7 + centerProximity * 0.3
    }

    // MARK: - Smoothing

    private func smoothingUpdate(newBox: CGRect, score: Double, source: Region.Source) -> Region? {
        missingFrameCount = 0
        consecutiveHitCount += 1

        let nextBox: CGRect
        if let prev = smoothedBox {
            nextBox = CGRect(
                x: prev.origin.x * (1 - alpha) + newBox.origin.x * alpha,
                y: prev.origin.y * (1 - alpha) + newBox.origin.y * alpha,
                width: prev.size.width * (1 - alpha) + newBox.size.width * alpha,
                height: prev.size.height * (1 - alpha) + newBox.size.height * alpha
            )
        } else {
            // Erster Frame nach Reset — direkt übernehmen, sonst springt
            // die Box von (0,0) ins Ziel und wirkt hässlich.
            nextBox = newBox
        }
        smoothedBox = nextBox

        let stable = updateStability(currentBox: nextBox)

        // Hysterese: erst NACH `minConsecutiveHits` Frames den Overlay
        // an die View emittieren — Single-Frame-False-Positives werden
        // dadurch vom UI ferngehalten. Der Tracker aktualisiert seine
        // EMA-State aber bereits, damit der Overlay beim Erreichen der
        // Hit-Schwelle sofort auf der richtigen Position erscheint.
        guard consecutiveHitCount >= minConsecutiveHits else {
            return nil
        }
        return Region(boundingBox: nextBox, score: score, source: source, isStable: stable)
    }

    /// Stabilitäts-Logik: Wenn die geglättete Box über N Frames nahe
    /// an der Referenz-Box bleibt, gilt sie als stabil. Drift zurück
    /// → Referenz neu, Streak bei 1 neu beginnen.
    private func updateStability(currentBox: CGRect) -> Bool {
        guard let ref = stabilityReferenceBox else {
            stabilityReferenceBox = currentBox
            stabilityFrameCount = 1
            return false
        }
        let drift = hypot(Double(currentBox.midX - ref.midX),
                          Double(currentBox.midY - ref.midY))
        let sizeDelta = abs(Double(currentBox.width - ref.width))
                      + abs(Double(currentBox.height - ref.height))
        let combined = drift + sizeDelta * 0.5
        if combined <= stabilityDriftThreshold {
            stabilityFrameCount += 1
            return stabilityFrameCount >= stabilityFramesRequired
        } else {
            stabilityReferenceBox = currentBox
            stabilityFrameCount = 1
            return false
        }
    }
}
