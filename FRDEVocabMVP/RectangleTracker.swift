import Foundation
import Vision
import CoreVideo
import QuartzCore

/// Vision-basierter Rechteck-Tracker mit Stabilität und Smoothing.
///
/// Pro Frame:
/// 1. `VNDetectRectanglesRequest` sucht Rechtecke im Bild.
/// 2. Das beste (größtes + konfidenteste) wird gewählt.
/// 3. Es wird über mehrere Frames **geglättet** (exponential moving average),
///    damit das Overlay nicht flackert.
/// 4. Es wird geprüft, ob das Rechteck **stabil** genug ist für Auto-Capture:
///    seit mindestens `stabilityDuration` nur kleine Positions-Varianzen.
///
/// Thread-unsicher — lebt auf der SessionQueue.
final class RectangleTracker {

    /// Lock-Zustand für das UI-Overlay (User-Auftrag: three-way
    /// searching/candidate/locked statt binäres good/bad).
    ///   • `searching` — kein plausibler Kandidat (kein Rechteck oder
    ///     schlechte Qualität).
    ///   • `candidate` — Rechteck erkannt, aber noch nicht stabil
    ///     genug für Lock.
    ///   • `locked`    — stabil über mehrere Frames → UI zeigt den
    ///     Quad in Signal-Blau, Auto-Capture darf feuern.
    enum LockState: Equatable {
        case searching
        case candidate
        case locked
    }

    struct Assessment {
        let smoothedRectangle: VNRectangleObservation?
        /// **Raw Vision Detection** — unsmoothed, frisch vom
        /// `VNDetectRectanglesRequest`. Für Debug-Overlays (roter
        /// Rahmen zeigt Raw-Detection gegen grünen Smoothed-Rahmen).
        let rawRectangle: VNRectangleObservation?
        let quality: SmartScannerGuidance.Quality
        let shouldAutoCapture: Bool
        let lockState: LockState
    }

    /// Tuning-Konfiguration — vorher verteilte `private let`s, jetzt als
    /// Struct auslagerbar. Lässt Kalibrierung pro Device-/User-Profil
    /// von außen zu (Test-Rig, A/B-Tuning). Default-Werte entsprechen
    /// der bisherigen Tracker-Logik — kein Verhaltenswechsel für
    /// Call-Sites, die `RectangleTracker()` ohne Argument nutzen.
    struct Config {
        /// **Position-Smoothing** — wie stark der Mittelpunkt des
        /// detektierten Rechtecks gedämpft wird. Niedriger = schneller
        /// dem realen Ort folgend, höher = stabiler/träger.
        ///
        /// 0.5 (aktuell): ausgewogener Wert, folgt realer Bewegung
        /// schnell, zappelt aber nicht bei Vision-Noise.
        var positionSmoothingFactor: CGFloat = 0.5

        /// **Size-Smoothing** — wie stark die Ausdehnung (Abstand zum
        /// Mittelpunkt pro Ecke) gedämpft wird. Höher = stabiler,
        /// weil Größenänderungen visuell auffälliger sind als
        /// Positionsänderungen und schnelle Flackerei besonders stören.
        ///
        /// 0.8 (aktuell): stark gedämpft — das Rechteck atmet kaum
        /// sichtbar, auch wenn Vision leichte Ecken-Jitter liefert.
        var sizeSmoothingFactor: CGFloat = 0.8

        /// **Legacy-Compound-Factor** — nur noch als Fallback wenn
        /// Code außerhalb auf die alte Single-Factor-API zugreift.
        /// Wird intern nicht mehr benutzt.
        var smoothingFactor: CGFloat {
            get { (positionSmoothingFactor + sizeSmoothingFactor) / 2 }
            set {
                positionSmoothingFactor = newValue
                sizeSmoothingFactor = newValue
            }
        }

        /// Dauer, für die das Rechteck stabil sein muss, bevor der
        /// Lock-State auf `.locked` kippt. 0.5 s fühlt sich für den
        /// User nicht hektisch an.
        var stabilityDuration: CFTimeInterval = 0.5

        /// Maximale erlaubte Ecken-Varianz (normalisiert, 0..1) während
        /// der Stabilitätsperiode. 0.02 = 2 % Bild pro Ecke.
        var stabilityTolerance: CGFloat = 0.02

        /// Mindest-Flächenanteil für „gute Qualität". Unter 28 %
        /// → „näher rangehen".
        var minGoodAreaFraction: CGFloat = 0.28

        /// Vision-Parameter — direkt an `VNDetectRectanglesRequest` weitergereicht.
        var minimumAspectRatio: Float = 0.2
        var maximumAspectRatio: Float = 1.0      // Quadrat als oberes Limit
        var minimumSize: Float = 0.2             // min. relative Boundingbox-Größe
        /// Confidence-Schwelle. 0.60 (Vision-Baseline) ist wieder aktiv
        /// nach User-Report „Overlay total daneben, erkennt nichts" —
        /// 0.72 war zu aggressiv und killte legitime Paper-Kanten bei
        /// normaler Beleuchtung.
        var minimumConfidence: Float = 0.60
        var maximumObservations: Int = 6

        /// Maximale Schief-Toleranz für die **Qualitäts**-Bewertung
        /// (UI-Hinweis „gerader halten"). 25° bleibt, damit Menschen
        /// nicht gezwungen werden, millimetergenau gerade zu halten.
        var maxSkewDegrees: CGFloat = 25

        /// Quadratur-Filter für den Vision-**Detektor**. 20° ist ein
        /// Kompromiss: strenger als der ursprüngliche 25°-Default
        /// (weniger trapezoidale False-Positives), aber locker genug,
        /// dass auch leicht verzogene Handy-Perspektiven noch erkannt
        /// werden. 15° war zu streng — Vision lieferte oft gar nichts.
        var vissionQuadratureTolerance: Float = 20

        /// Region-of-Interest (normalized, Vision-coords: y wächst nach
        /// unten, da wir .up passen). Nil = voller Frame. Default:
        /// zentrale 90 % der Fläche — randnah liegende Rechtecke (z. B.
        /// Notch-Shadow, Finger am Rand) werden ignoriert.
        var regionOfInterest: CGRect? = CGRect(x: 0.05, y: 0.05, width: 0.90, height: 0.90)

        /// Wieviele aufeinanderfolgende „keine Erkennung"-Frames wir
        /// tolerieren, bevor wir den letzten geglätteten Rahmen
        /// verwerfen und auf `.noRectangle` zurückfallen.
        ///
        /// Vorher war das 0 — eine einzige Vision-Aussetzung (die auch
        /// bei stabilem Dokument-Framing gelegentlich vorkommt) genügte,
        /// damit das UI zwischen „Bereit" und „Dokument ins Bild halten"
        /// flackerte. Mit 3 Frames (≈0.3 s bei 10 Hz) bleibt der
        /// Overlay-Rahmen über kurzzeitige Detection-Dropouts stabil
        /// sichtbar, Auto-Capture pausiert aber automatisch (lockState
        /// fällt auf `.candidate` zurück).
        var lostDetectionTolerance: Int = 3

        /// **Area-Bias-Exponent** für die Rechteck-Auswahl (Scoring-
        /// Funktion `score = area^bias × confidence − centerPenalty
        /// × distFromCenter`).
        ///
        /// • 1.0 (default) — linear; gut für Dokument-Scans, wo das
        ///   einzige plausible Rechteck typisch das Papier ist.
        /// • 1.8+ (rectangleAssist) — quadratisch-betont; nötig, weil
        ///   Müslipackungen/Plakate oft viele kleine Innen-Rechtecke
        ///   (Logos, Hinweis-Boxen) haben, die einzeln eine **höhere
        ///   Confidence** liefern als die große Außenkante. Quadratisches
        ///   Area-Gewicht zwingt das Scoring, den großen Umriss
        ///   auszuwählen.
        var areaBias: Float = 1.0

        /// **Center-Penalty** für die Rechteck-Auswahl. Höher = strenger
        /// auf Mittigkeit. 0.1 (default) ist konservativ — verhindert,
        /// dass Buch-Ecken am Rand gewinnen. 0.05 (rectangleAssist) ist
        /// lockerer, weil große Plakate auch nicht-perfekt mittig
        /// gerahmt werden dürfen.
        var centerPenalty: Float = 0.1

        /// **Mindest-Flächenanteil** im `isPlausibleQuad`-Filter.
        /// Quads mit `boundingBox.width × boundingBox.height` <
        /// diesem Wert werden verworfen. 0 (default) deaktiviert den
        /// Floor — Vokabel-Profil. 0.28 (rectangleAssist) verhindert
        /// Sub-Rechteck-False-Positives wie „obere Banderole" einer
        /// Müslipackung.
        var areaFractionFloor: CGFloat = 0.0

        static let `default` = Config()

        /// **Rectangle-Assist-Profil** (FreeText auto/Rahmen-Modus).
        /// Strenge Schwellen für **plausibler Außenrand-Quad** auf
        /// nicht-dokumentartigen Flächen (Plakate, Müslipackungen,
        /// Cover, Schilder).
        ///
        /// **Produkt-Regel** (User-Spec): „wenn kein gutes Rechteck
        /// gefunden wird: fallback auf WYSIWYG". Lieber **gar kein**
        /// Overlay als ein irreführendes — der Manual-Tap-Pfad fängt
        /// das mit Full-Frame-Crop sauber auf.
        ///
        /// Iteration nach Real-Test (Müslipackung): Vorher waren die
        /// Schwellen zu locker (`minimumConfidence=0.35`,
        /// `quadratureTolerance=30°`, `minimumSize=0.18`) und Vision
        /// lieferte degenerate Quads, die nur einen Teil der Packung
        /// abdeckten oder über die Diagonale verzerrt waren.
        ///
        /// Neue Werte:
        ///   • `minimumConfidence = 0.55` — nur klar abgrenzbare
        ///     Außenkanten. Müslipackungs-„Versuche" mit 0.40 fallen
        ///     raus → kein Overlay, Fallback WYSIWYG greift.
        ///   • `vissionQuadratureTolerance = 18°` — Vision-Detector
        ///     selbst muss bereits einen ~rechteckigen Polygon liefern.
        ///     30° ließ extrem schiefe Trapeze durch.
        ///   • `minimumSize = 0.45` — der gefundene Quad muss mind.
        ///     45 % der Frame-Kantenlänge abdecken (`VNDetectRectanglesRequest.minimumSize`
        ///     ist *nicht* Flächenanteil, sondern relative kürzere
        ///     Bounding-Box-Kante!). Filtert die typische „nur obere
        ///     Banderole gefunden"-Müslipackungs-Falle, wo Vision die
        ///     untere echte Packungs-Unterkante wegen 3D-Perspektive
        ///     nicht erkennt und als „Rechteck" das obere Drittel
        ///     samt Banderolen-Bottom liefert.
        ///   • `maxSkewDegrees = 25` — auch im Quality-Hint strenger.
        ///   • Plus zusätzlicher Plausibility-Filter
        ///     (`isPlausibleQuad` + `areaFractionFloor`) gegen Sub-
        ///     Rechtecke, die `VNDetectRectanglesRequest.minimumSize`
        ///     trotzdem schaffen.
        ///
        /// Beibehaltene Hebel (gegen Zittern + falsche Auswahl):
        ///   • `areaBias = 1.8` — wenn doch mehrere Kandidaten kommen,
        ///     gewinnt der größere überproportional.
        ///   • `centerPenalty = 0.05`, `positionSmoothingFactor = 0.30`,
        ///     `sizeSmoothingFactor = 0.85`, `lostDetectionTolerance = 6`.
        static let rectangleAssist = Config(
            positionSmoothingFactor: 0.30,
            sizeSmoothingFactor: 0.85,
            stabilityDuration: 0.7,
            stabilityTolerance: 0.025,
            minGoodAreaFraction: 0.20,
            minimumAspectRatio: 0.2,
            maximumAspectRatio: 1.0,
            minimumSize: 0.45,
            minimumConfidence: 0.55,
            maximumObservations: 8,
            maxSkewDegrees: 25,
            vissionQuadratureTolerance: 18,
            regionOfInterest: CGRect(x: 0.025, y: 0.025, width: 0.95, height: 0.95),
            lostDetectionTolerance: 6,
            areaBias: 1.8,
            centerPenalty: 0.05,
            areaFractionFloor: 0.28
        )
    }

    // MARK: - State

    private let config: Config
    private var smoothed: VNRectangleObservation?
    private var stableSince: CFTimeInterval?
    private var stabilityAnchor: VNRectangleObservation?
    /// Letzter stabiler Lock-Rect (normalisiert). Der Photo-Capture-Pfad
    /// friert diesen Wert ein, damit Manual/Auto-Capture nicht auf dem
    /// gerade-mutierenden Live-Quad arbeitet.
    private(set) var lastLockedRectangle: VNRectangleObservation?

    /// Anzahl aufeinanderfolgender Frames **ohne** Vision-Detection.
    /// Wird auf 0 zurückgesetzt, sobald wieder etwas erkannt wurde.
    /// Gated die Hysterese: solange `missingFrameCount <=
    /// config.lostDetectionTolerance`, behalten wir das letzte
    /// `smoothed`-Rechteck und downgraden `.locked` auf `.candidate`.
    private var missingFrameCount: Int = 0

    /// Letztes Quality-Ergebnis. Nur während der Hysterese-Phase
    /// benötigt — wir behalten die ruhige Anzeige („Ruhig halten" oder
    /// „Bereit — halten") über kurzzeitige Detection-Dropouts hinweg
    /// bei, statt zurück auf „Dokument ins Bild halten" zu flippen.
    private var lastQualityDuringHold: SmartScannerGuidance.Quality?

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Public API

    func process(pixelBuffer: CVPixelBuffer) -> Assessment {
        let observation = detectBestRectangle(in: pixelBuffer)

        // Glätten über Zeit.
        if let obs = observation {
            missingFrameCount = 0
            if let prev = smoothed {
                smoothed = smooth(prev: prev, next: obs, factor: config.smoothingFactor)
            } else {
                smoothed = obs
            }
        } else {
            // Hysterese: kurze Detection-Aussetzer (bis zu
            // `config.lostDetectionTolerance` Frames ≈ 0.3 s bei 10 Hz)
            // dürfen das letzte geglättete Rechteck **nicht** sofort
            // verwerfen — sonst flackert das UI zwischen „Bereit" und
            // „Dokument ins Bild halten" bei minimalen Vision-Misses.
            missingFrameCount += 1
            if let held = smoothed, missingFrameCount <= config.lostDetectionTolerance {
                return Assessment(
                    smoothedRectangle: held,
                    rawRectangle: nil,  // Hysterese: kein frisches raw
                    quality: lastQualityDuringHold ?? .unstable,
                    shouldAutoCapture: false,
                    lockState: .candidate
                )
            }
            // Zu viele Miss-Frames → wirklich verloren.
            smoothed = nil
            lastQualityDuringHold = nil
            resetStability()
            return Assessment(
                smoothedRectangle: nil,
                rawRectangle: nil,
                quality: .noRectangle,
                shouldAutoCapture: false,
                lockState: .searching
            )
        }

        guard let current = smoothed else {
            resetStability()
            return Assessment(
                smoothedRectangle: nil,
                rawRectangle: observation,
                quality: .noRectangle,
                shouldAutoCapture: false,
                lockState: .searching
            )
        }

        // Qualität prüfen.
        let quality = assess(current)

        // Stabilität tracken — nur wenn Qualität auch gut ist.
        let stable = updateStability(with: current, quality: quality)

        // Lock-State ableiten. Reihenfolge ist wichtig:
        //   • `quality == .noRectangle` schon oben abgefangen.
        //   • Schlechte Qualität (tooSmall/tooSkewed) = noch kein
        //     verwertbarer Kandidat → searching.
        //   • Gute Qualität, aber unstable = candidate (gelbes Overlay
        //     empfehlenswert, UI entscheidet farblich).
        //   • Stable + good = locked (blauer Rahmen laut Spec).
        let lockState: LockState
        switch quality {
        case .noRectangle, .tooSmall, .tooSkewed:
            lockState = .searching
        case .unstable:
            lockState = .candidate
        case .good:
            lockState = stable ? .locked : .candidate
        }

        if lockState == .locked {
            lastLockedRectangle = current
        }

        // Quality für die Hysterese-Phase merken — solange wir stabil
        // oder gut detektieren, bleibt dieser Wert als Fallback-Anzeige
        // über kurze Detection-Ausfälle hinweg erhalten.
        lastQualityDuringHold = quality

        return Assessment(
            smoothedRectangle: current,
            rawRectangle: observation,
            quality: quality,
            shouldAutoCapture: stable && quality.isGood,
            lockState: lockState
        )
    }

    // MARK: - Detection

    private func detectBestRectangle(in pixelBuffer: CVPixelBuffer) -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = config.minimumConfidence
        request.minimumAspectRatio = config.minimumAspectRatio
        request.maximumAspectRatio = config.maximumAspectRatio
        request.minimumSize = config.minimumSize
        // Engere Quadratur-Toleranz: nur annähernd rechteckige Shapes
        // werden akzeptiert. Vorher wurde `maxSkewDegrees` (25°)
        // durchgereicht, was der Vision-Detektor als Einladung
        // interpretierte, stark trapezoidale Polygone zu liefern.
        request.quadratureTolerance = config.vissionQuadratureTolerance
        request.maximumObservations = config.maximumObservations
        // Region-of-Interest — randnahe Fragmente (Finger, Notch-Shadow)
        // werden ignoriert. Nil lässt Vision den ganzen Frame scannen.
        if let roi = config.regionOfInterest {
            request.regionOfInterest = roi
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let results = request.results, !results.isEmpty else { return nil }

        // **Plausibility-Pre-Filter**: degenerate Quads, die Vision
        // gelegentlich liefert (zwei Ecken fast deckungsgleich, stark
        // unterschiedliche Diagonalen, konkave Polygone), aussortieren.
        // Erst danach wird gescored. Zwei einfache Tests:
        //   1. Konvexität (cross-products der Kanten alle gleiches
        //      Vorzeichen)
        //   2. Diagonal-Ratio nahe 1 (≥ 0.65) — bei einem echten
        //      Rechteck/leichten Trapez sind beide Diagonalen ähnlich
        //      lang. Bei degenerate Quads (z. B. Bowtie oder fast-
        //      Linie) ist der Quotient klein.
        let plausibles = results.filter { isPlausibleQuad($0) }
        let candidates = plausibles.isEmpty ? results : plausibles

        // Scoring: `area^bias × confidence − centerPenalty × distFromCenter`
        // (siehe `scoreForRectangle`-Doc).
        return candidates.max { a, b in
            scoreForRectangle(a) < scoreForRectangle(b)
        }
    }

    /// Drei Plausibility-Tests gegen Vision-Degenerate-Quads UND
    /// gegen Sub-Rechtecke, die nur einen Teil des Außen-Umrisses
    /// abdecken (User-Bug „Müslipackung — nur oberes Drittel erkannt"):
    ///
    ///   1. **Konvexität** — die vier Cross-Products
    ///      `(P[i+1] − P[i]) × (P[i+2] − P[i+1])` müssen alle
    ///      dasselbe Vorzeichen haben. Andernfalls ist der Quad
    ///      konkav (Bowtie-Form oder Self-Intersection).
    ///
    ///   2. **Diagonal-Ratio ≥ 0.65** — bei einem rechteckigen Polygon
    ///      (auch perspektivisch verzerrt) sind die zwei Diagonalen
    ///      ähnlich lang. Filtert „Linien-mit-Knubbel"-Quads.
    ///
    ///   3. **Bounding-Box-Flächenanteil ≥ 0.28** — der Quad muss
    ///      mind. 28 % der Frame-Fläche abdecken, sonst ist er kein
    ///      plausibler Außen-Umriss eines Plakat-/Cover-/Schild-
    ///      Objekts. Vision's `minimumSize` bezieht sich nur auf die
    ///      kürzere Bounding-Box-Kante (relativ), nicht auf die
    ///      Fläche — wir brauchen den expliziten Flächen-Floor.
    ///      Ein 30-%-Sub-Rechteck der Müslipackung („obere Banderole")
    ///      hat typisch ~10-15 % Flächenanteil → fällt raus.
    private func isPlausibleQuad(_ obs: VNRectangleObservation) -> Bool {
        let tl = obs.topLeft, tr = obs.topRight
        let br = obs.bottomRight, bl = obs.bottomLeft

        // Konvexität: einheitliches Vorzeichen aller Cross-Products
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        let c1 = cross(tl, tr, br)
        let c2 = cross(tr, br, bl)
        let c3 = cross(br, bl, tl)
        let c4 = cross(bl, tl, tr)
        let allPositive = c1 > 0 && c2 > 0 && c3 > 0 && c4 > 0
        let allNegative = c1 < 0 && c2 < 0 && c3 < 0 && c4 < 0
        guard allPositive || allNegative else { return false }

        // Diagonal-Ratio
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            hypot(a.x - b.x, a.y - b.y)
        }
        let d1 = dist(tl, br)
        let d2 = dist(tr, bl)
        guard d1 > 0, d2 > 0 else { return false }
        let ratio = min(d1, d2) / max(d1, d2)
        guard ratio >= 0.65 else { return false }

        // **Bounding-Box-Flächenanteil-Floor** — explizit gegen
        // Sub-Rechteck-False-Positives. Nur für Rectangle-Assist-
        // Profil aktiv (Vokabel-Profil hat ggf. legitim kleinere
        // Dokumente und nutzt den Default 0).
        let areaFraction = obs.boundingBox.width * obs.boundingBox.height
        return areaFraction >= config.areaFractionFloor
    }

    /// Combined score für die Rect-Auswahl. Konfigurierbar über
    /// `Config.areaBias` und `Config.centerPenalty`:
    ///
    ///   score = area^bias × confidence − centerPenalty × distFromCenter
    ///
    /// **Vokabel-Profil** (default, bias=1.0, penalty=0.1): linear in
    /// area, leichte Mittigkeits-Präferenz.
    ///
    /// **Rectangle-Assist-Profil** (bias=1.8, penalty=0.05): stark zu
    /// **größeren Rechtecken** hin gewichtet, weil Plakate/Müslipackungen
    /// oft kleine Innen-Rechtecke (Logos, Hinweis-Boxen) haben, die
    /// einzeln eine höhere Confidence liefern als die große Außenkante.
    /// Beispiel: Packung 0.6 area × 0.4 confidence vs. Logo 0.08 area
    /// × 0.95 confidence:
    ///   • Linear:    0.6 × 0.4 = 0.24  vs.  0.08 × 0.95 = 0.076  → Packung
    ///   • Bias=1.8:  0.6^1.8 × 0.4 = 0.16 vs. 0.08^1.8 × 0.95 = 0.012 → Packung (klarer)
    ///
    /// Bei sehr ungünstiger Confidence-Verteilung (Packung 0.30 vs Logo 0.95):
    ///   • Linear:    0.6 × 0.30 = 0.18  vs.  0.08 × 0.95 = 0.076  → Packung
    ///   • Bias=1.8:  0.6^1.8 × 0.30 = 0.12 vs. 0.08^1.8 × 0.95 = 0.012 → Packung (10× Vorsprung)
    private func scoreForRectangle(_ obs: VNRectangleObservation) -> Float {
        let area = Float(obs.boundingBox.width * obs.boundingBox.height)
        let cx = Float(obs.boundingBox.midX)
        let cy = Float(obs.boundingBox.midY)
        let distFromCenter = sqrtf((cx - 0.5) * (cx - 0.5) + (cy - 0.5) * (cy - 0.5))
        let weightedArea = powf(area, config.areaBias)
        return obs.confidence * weightedArea - config.centerPenalty * distFromCenter
    }

    // MARK: - Smoothing

    /// **Smoothing-Split** — dämpft Position (Mittelpunkt) und Größe
    /// (Offset jeder Ecke vom Mittelpunkt) **unabhängig**. So fühlt
    /// sich der Overlay lebendig an, aber die Ecken flackern nicht.
    ///
    /// Algorithmus pro Ecke:
    ///   1. Zerlege prev + next in center + offset
    ///   2. Glätte center mit `positionSmoothingFactor`
    ///   3. Glätte offset mit `sizeSmoothingFactor`
    ///   4. Baue Ecke neu zusammen aus geglättetem Center + Offset
    private func smooth(
        prev: VNRectangleObservation,
        next: VNRectangleObservation,
        factor: CGFloat  // ungenutzt, für API-Kompatibilität
    ) -> VNRectangleObservation {
        _ = factor  // silenced
        let posF = config.positionSmoothingFactor
        let sizeF = config.sizeSmoothingFactor

        let prevCenter = averageCenter(prev)
        let nextCenter = averageCenter(next)
        let smoothedCenter = lerp(prevCenter, nextCenter, factor: posF)

        func smoothedCorner(
            prevCorner: CGPoint,
            nextCorner: CGPoint
        ) -> CGPoint {
            let prevOffset = CGPoint(x: prevCorner.x - prevCenter.x, y: prevCorner.y - prevCenter.y)
            let nextOffset = CGPoint(x: nextCorner.x - nextCenter.x, y: nextCorner.y - nextCenter.y)
            let smoothedOffset = lerp(prevOffset, nextOffset, factor: sizeF)
            return CGPoint(
                x: smoothedCenter.x + smoothedOffset.x,
                y: smoothedCenter.y + smoothedOffset.y
            )
        }

        return VNRectangleObservation(
            requestRevision: next.requestRevision,
            topLeft: smoothedCorner(prevCorner: prev.topLeft, nextCorner: next.topLeft),
            bottomLeft: smoothedCorner(prevCorner: prev.bottomLeft, nextCorner: next.bottomLeft),
            bottomRight: smoothedCorner(prevCorner: prev.bottomRight, nextCorner: next.bottomRight),
            topRight: smoothedCorner(prevCorner: prev.topRight, nextCorner: next.topRight)
        )
    }

    private func averageCenter(_ rect: VNRectangleObservation) -> CGPoint {
        CGPoint(
            x: (rect.topLeft.x + rect.topRight.x + rect.bottomLeft.x + rect.bottomRight.x) / 4,
            y: (rect.topLeft.y + rect.topRight.y + rect.bottomLeft.y + rect.bottomRight.y) / 4
        )
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, factor: CGFloat) -> CGPoint {
        CGPoint(
            x: a.x * factor + b.x * (1 - factor),
            y: a.y * factor + b.y * (1 - factor)
        )
    }

    // MARK: - Qualitäts-Bewertung

    private func assess(_ rect: VNRectangleObservation) -> SmartScannerGuidance.Quality {
        let area = rect.boundingBox.width * rect.boundingBox.height

        // Zu klein → „näher rangehen"
        if area < config.minGoodAreaFraction {
            return .tooSmall
        }

        // Schiefe → über den max. Winkel-Abweichungen an den Ecken
        let skew = maxCornerDeviation(rect)
        if skew > config.maxSkewDegrees {
            return .tooSkewed
        }

        // Stabilität erst im nächsten Schritt geprüft.
        if stableSince == nil {
            return .unstable
        }

        return .good
    }

    /// Max. Abweichung eines Ecken-Winkels von 90° in Grad.
    private func maxCornerDeviation(_ rect: VNRectangleObservation) -> CGFloat {
        func angle(at p: CGPoint, from a: CGPoint, to b: CGPoint) -> CGFloat {
            let v1 = CGPoint(x: a.x - p.x, y: a.y - p.y)
            let v2 = CGPoint(x: b.x - p.x, y: b.y - p.y)
            let dot = v1.x * v2.x + v1.y * v2.y
            let mag = sqrt(v1.x * v1.x + v1.y * v1.y) * sqrt(v2.x * v2.x + v2.y * v2.y)
            guard mag > 0 else { return 0 }
            let cosAngle = max(-1, min(1, dot / mag))
            return acos(cosAngle) * 180 / .pi
        }

        let angles = [
            angle(at: rect.topLeft, from: rect.bottomLeft, to: rect.topRight),
            angle(at: rect.topRight, from: rect.topLeft, to: rect.bottomRight),
            angle(at: rect.bottomRight, from: rect.topRight, to: rect.bottomLeft),
            angle(at: rect.bottomLeft, from: rect.bottomRight, to: rect.topLeft)
        ]
        return angles.map { abs($0 - 90) }.max() ?? 0
    }

    // MARK: - Stabilität

    /// Prüft, ob das Rechteck in einem Zeitfenster stabil ist (geringe
    /// Varianz an den Ecken). Liefert true, sobald die Stabilitätsperiode
    /// erfüllt ist. Setzt den Anchor zurück bei zu großer Abweichung.
    private func updateStability(with rect: VNRectangleObservation, quality: SmartScannerGuidance.Quality) -> Bool {
        // Nur bei brauchbarer Qualität tracken wir Stabilität.
        guard quality != .tooSmall, quality != .tooSkewed, quality != .noRectangle else {
            resetStability()
            return false
        }

        let now = CACurrentMediaTime()

        if let anchor = stabilityAnchor {
            let dev = maxCornerDelta(anchor, rect)
            if dev > config.stabilityTolerance {
                // Zu großer Sprung — Anchor neu setzen.
                stabilityAnchor = rect
                stableSince = now
                return false
            }
        } else {
            stabilityAnchor = rect
            stableSince = now
            return false
        }

        guard let since = stableSince else { return false }
        return (now - since) >= config.stabilityDuration
    }

    private func maxCornerDelta(_ a: VNRectangleObservation, _ b: VNRectangleObservation) -> CGFloat {
        let deltas = [
            hypot(a.topLeft.x - b.topLeft.x, a.topLeft.y - b.topLeft.y),
            hypot(a.topRight.x - b.topRight.x, a.topRight.y - b.topRight.y),
            hypot(a.bottomLeft.x - b.bottomLeft.x, a.bottomLeft.y - b.bottomLeft.y),
            hypot(a.bottomRight.x - b.bottomRight.x, a.bottomRight.y - b.bottomRight.y)
        ]
        return deltas.max() ?? 0
    }

    private func resetStability() {
        stabilityAnchor = nil
        stableSince = nil
    }
}
