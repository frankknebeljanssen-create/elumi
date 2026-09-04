import SwiftUI

/// **Scan-Progress-Overlay** — die zentrale, prominente Status-Card, die
/// während eines laufenden Scans (Kamera oder Galerie) über dem Bild
/// liegt. Zeigt auf einen Blick:
///
///   1. Großer Titel („KI analysiert dein Bild", „Text aus dem Bild
///      lesen" …) aus `ScanRuntimeStage.displayTitle`.
///   2. Icon + kleine Sub-Zeile mit menschlicher Erklärung (aus
///      `ScanRuntimeStage.displaySubtitle`).
///   3. Progress-Indikator (Spinner) + animierte „…"-Punkte über dem
///      Titel, damit die Card nicht statisch wirkt.
///   4. Optionale Seiten-Info (1/3, 2/3) bei Batch-Scans — sitzt ganz
///      oben als Mini-Pill, damit sie nicht den Haupttitel überdeckt.
///
/// API-Änderung ggü. der alten Card: statt `progressText` + `runtimeLabel`
/// übernimmt das Overlay jetzt den `stage` direkt und liest Titel/Icon/
/// Tint/Sub-Zeile aus der zentralen `ScanRuntimeStage`-Metadata — die
/// Call-Sites müssen nicht mehr drei einzelne Strings zusammenbauen.
struct ScanProgressOverlayCardView: View {
    let stage: ScanRuntimeStage
    /// Animations-Punkte („Analysiere.", „Analysiere..", …) — die
    /// Call-Site liefert bereits den fertig geformten String inkl.
    /// Batch-Info („Seite 2/3").
    let progressText: String
    /// Optionaler Input-Method-Kontext (Kamera / Galerie). Wird an
    /// `ScanRuntimeStage.displayTitle(for:)` weitergereicht, damit die
    /// `.aiPrimary`-Headline „Foto" (Kamera) oder „Bild" (Galerie)
    /// sagt. `nil` fällt auf „Bild" als neutrale Default-Formulierung.
    var inputMethod: ScanInputMethod? = nil
    /// **Multi-Image-Progress** (User-Spec 2026-04-23 nacht): wenn
    /// gesetzt, rendert die Card am unteren Rand einen segmentierten
    /// Fortschrittsbalken. Bei `nil` oder `totalImageCount <= 1` bleibt
    /// die Card unverändert (Single-Image-Flow nicht anfassen).
    var currentImageIndex: Int? = nil
    var totalImageCount: Int? = nil

    /// Startzeitpunkt für die Laufzeit-Anzeige. Wird beim ersten
    /// Erscheinen der Card gesetzt — die Card lebt genau so lange wie
    /// der laufende Scan.
    @State private var startedAt = Date()

    var body: some View {
        VStack(spacing: 10) {
            // Zeile 1: Batch-/Progress-Info („Seite 2/3", „Analysiere…")
            // bewusst klein und unaufdringlich — die Stage-Info
            // darunter ist jetzt der Hauptfokus.
            Text(progressText)
                .font(AppTheme.Typography.caption)
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .center)

            // Zeile 2: Prominente Stage-Anzeige (Icon + großer Titel).
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(stage.tintColor.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: stage.systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(stage.tintColor)
                }
                Text(stage.displayTitle(for: inputMethod))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(stage.tintColor)
            }

            // Zeile 3: Sub-Zeile — erklärt, was **genau** passiert. Nur
            // zeigen, wenn die Stage einen Subtitle liefert. Zentriert,
            // damit die Card ruhig balanciert wirkt und der Sub-Text
            // optisch unter dem Titel sitzt (vorher links, was bei
            // zweispaltigem Titel/Spinner schief aussah).
            if let subtitle = stage.displaySubtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .transition(.opacity)
            }

            // Zeile 4 (User-Spec 2026-04-23 nacht): Segmentierter
            // Fortschrittsbalken UNTERHALB des Subtitle-Textes. Nur
            // sichtbar bei Mehrbild-Analyse (totalImageCount > 1),
            // damit der Single-Image-Flow visuell gleich bleibt.
            //
            // **2026-04-24**: Farben sind Spec-fix grün/pink/grau in
            // `ScanBatchProgressBar` selbst — daher kein `accent`-
            // Parameter mehr.
            if let total = totalImageCount,
               let current = currentImageIndex,
               total > 1 {
                ScanBatchProgressBar(
                    currentIndex: current,
                    totalCount: total
                )
                .padding(.top, 6)
            }

            // **2026-06-09** — Zeitanzeige + Verlaufsbalken.
            //
            // Vorher liefen nur Spinner und Scanner-Animation in Schleife.
            // Beides wiederholt sich identisch, egal wie lange es dauert —
            // nach einer Weile wirkt das wie ein Absturz (User-Report).
            //
            // Die verstrichene Zeit ist die einzige ehrliche
            // Fortschrittsinformation, die wir haben: Die KI meldet keinen
            // Zwischenstand. Sie läuft sichtbar weiter und zeigt auch bei
            // einem Abbruch, wie weit es kam. Der Balken darüber ist als
            // Schätzung markiert und läuft bewusst NIE ganz voll — sonst
            // stünde er bei 100 %, während noch nichts fertig ist.
            elapsedProgressSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.surface.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(stage.tintColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        // Sanfter Fade beim Stage-Wechsel — Titel/Sub-Zeile wechseln
        // dadurch mit einem weichen Übergang statt hart zu springen.
        .animation(.easeInOut(duration: 0.22), value: stage)
    }

    // MARK: - Zeit + Verlauf

    /// Erwartete Gesamtdauer für die Balken-Schätzung. Bewusst großzügig:
    /// Ein Scan über den KI-Proxy liegt typisch bei 20–60 s, kann aber
    /// deutlich länger brauchen. Der Balken nähert sich diesem Wert
    /// asymptotisch und bleibt bei 92 % stehen.
    private static let expectedDuration: TimeInterval = 60

    @ViewBuilder
    private var elapsedProgressSection: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            // Asymptotisch: schnell auf ~70 %, danach immer langsamer.
            // Erreicht nie 1.0 — fertig ist erst, wenn die Card weg ist.
            let fraction = min(0.92, 1 - exp(-elapsed / (Self.expectedDuration * 0.55)))

            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                        Capsule()
                            .fill(stage.tintColor)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 6)

                HStack(spacing: 6) {
                    Text(elapsedLabel(elapsed))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Text("Kann bis zu 2 Minuten dauern")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))
                }
            }
            .padding(.top, 8)
        }
    }

    private func elapsedLabel(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - ScanBatchProgressBar

/// **Segmentierter Fortschrittsbalken** für die Mehrbild-Analyse-Card.
/// Drei klar getrennte Status-Farben (User-Spec 2026-04-24):
///
///   • **Done** (Index < currentIndex): **GRÜN** (statisch, success-Mint)
///   • **Active** (Index == currentIndex): **PINK** (animiert,
///     `AppTheme.Colors.elumiPink`)
///   • **Pending** (Index > currentIndex): **NEUTRAL/GRAU** (statisch)
///
/// **Wichtig zur Semantik**: Die Farben sind ABSICHTLICH NICHT vom
/// `accent` des Callers abhängig. Done = abgeschlossen = grün ist
/// universell, Active = arbeitet = pink markiert auf einen Blick,
/// welches Segment gerade läuft. Diese Farb-Bindung ist Spec-fix —
/// Caller können den Akzent woanders setzen, der Progress-Bar bleibt
/// grün/pink/grau.
///
/// **Reduce-Motion**: Shimmer wird durch ein dezentes Pulsen ersetzt
/// (gleiche Pink-Farbe, nur statt Lauflicht ein opacity-puls).
///
/// Die Animation läuft NUR auf dem aktiven Segment. Done-Segmente
/// bleiben statisch grün, Pending-Segmente statisch grau. Beim
/// `currentIndex`-Wechsel springt die Animation automatisch auf das
/// neue aktive Segment, das vorherige bleibt grün stehen.
struct ScanBatchProgressBar: View {
    let currentIndex: Int    // 1-basiert
    let totalCount: Int      // ≥ 2 (Caller stellt das sicher)

    @State private var shimmerProgress: CGFloat = 0
    @State private var pulseOn: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let segmentHeight: CGFloat = 6
    private let segmentSpacing: CGFloat = 4

    /// Spec-fix grün für „abgeschlossen". Statisch, keine Animation.
    private var doneColor: Color { AppTheme.Colors.success }
    /// Spec-fix pink für „aktiv arbeitet". Hier läuft die Animation.
    private var activeColor: Color { AppTheme.Colors.elumiPink }
    /// Spec-fix neutral-grau für „noch nicht begonnen". Statisch.
    private var pendingColor: Color { AppTheme.Colors.textSecondary.opacity(0.18) }

    var body: some View {
        HStack(spacing: segmentSpacing) {
            ForEach(1...totalCount, id: \.self) { segmentNumber in
                segmentView(for: segmentNumber)
            }
        }
        .frame(height: segmentHeight)
        .onAppear { triggerActiveAnimation() }
        .onChange(of: currentIndex) { _, _ in triggerActiveAnimation() }
    }

    @ViewBuilder
    private func segmentView(for segmentNumber: Int) -> some View {
        let status = status(for: segmentNumber)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Basis: pending-grauer Track. Wird von Done/Active
                // ggf. vollständig überlagert.
                RoundedRectangle(cornerRadius: segmentHeight / 2, style: .continuous)
                    .fill(pendingColor)

                switch status {
                case .pending:
                    // Bleibt grau (Track allein sichtbar, keine Overlays).
                    EmptyView()

                case .done:
                    // GRÜN, statisch — kein Shimmer, kein Pulsen.
                    // Wichtig: Done-Segmente dürfen NIE animiert sein.
                    RoundedRectangle(cornerRadius: segmentHeight / 2, style: .continuous)
                        .fill(doneColor)

                case .active:
                    // PINK-Basisfläche — ruhig, keine Animation.
                    RoundedRectangle(cornerRadius: segmentHeight / 2, style: .continuous)
                        .fill(activeColor.opacity(0.45))

                    if reduceMotion {
                        // **Reduce-Motion**: ruhiger, langsamer
                        // Opacity-Fade zwischen 0.45 ↔ 0.85, keine
                        // horizontale Bewegung. Signalisiert „aktiv"
                        // ohne hektische Bewegung.
                        RoundedRectangle(cornerRadius: segmentHeight / 2, style: .continuous)
                            .fill(activeColor.opacity(pulseOn ? 0.85 : 0.45))
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: pulseOn
                            )
                    } else {
                        // **Bug-Fix 2026-04-25 (Sweep-Smooth-Pass)**.
                        //
                        // Vorher: `activeShimmerGradient` wurde pro
                        // Frame mit neu berechneten Stop-Positionen
                        // rekonstruiert. SwiftUI kann Gradient-Stops
                        // NICHT zwischen Frames smooth interpolieren —
                        // jedes re-render zeigte einen diskret
                        // unterschiedlichen Gradient. Kombiniert mit
                        // `.blendMode(.plusLighter)` über die volle
                        // Segmentbreite entstand der unruhige Eindruck
                        // („blinkt, schwillt an, ruckelt").
                        //
                        // Jetzt: Rectangle mit FIXEM Gradient, nur
                        // `.offset(x:)` wird animiert. SwiftUI
                        // interpoliert Offset-Werte pixelweise
                        // zwischen Frames → mathematisch stetige,
                        // gleichmäßige Bewegung.
                        //
                        // Geometrie:
                        //   • `sweepWidth = segWidth × 0.55` — der
                        //     helle Streifen ist ca. die halbe
                        //     Segmentbreite.
                        //   • `travelStart = -sweepWidth` (Sweep
                        //     knapp außerhalb links).
                        //   • `travelEnd   = segWidth`  (Sweep knapp
                        //     außerhalb rechts).
                        //   • Bei `repeatForever` springt der Zyklus
                        //     von `travelEnd` zurück auf `travelStart` —
                        //     beide Punkte liegen AUSSERHALB des
                        //     sichtbaren Segments, der Sprung ist also
                        //     unsichtbar.
                        let segWidth = geo.size.width
                        let sweepWidth = max(segWidth * 0.55, 18)
                        let travelStart = -sweepWidth
                        let travelEnd = segWidth
                        let currentX = travelStart + (travelEnd - travelStart) * shimmerProgress

                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            activeColor.opacity(0.0),
                                            activeColor.opacity(0.95),
                                            activeColor.opacity(0.0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: sweepWidth)
                                .offset(x: currentX)
                                .blendMode(.plusLighter)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Clip auf die Segment-Form, damit der Sweep
                        // an den Rändern sauber abschneidet und
                        // außerhalb des Segments unsichtbar bleibt.
                        .clipShape(RoundedRectangle(cornerRadius: segmentHeight / 2, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private enum SegmentStatus {
        case done, active, pending
    }

    private func status(for segmentNumber: Int) -> SegmentStatus {
        if segmentNumber < currentIndex { return .done }
        if segmentNumber == currentIndex { return .active }
        return .pending
    }

    private func triggerActiveAnimation() {
        if reduceMotion {
            pulseOn = false
            withAnimation { pulseOn = true }
        } else {
            shimmerProgress = 0
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerProgress = 1.0
            }
        }
    }

    /// **Volle-Segment-Sweep** (Bug-Fix 2026-04-24 nacht): Linear-
    /// Gradient, der über die GANZE Segment-Breite spannt. Der helle
    /// Spot (Center) wandert via `shimmerProgress` von links (0) nach
    /// rechts (1). Beim Rendern legt SwiftUI auf jedem Frame einen
    /// neuen Gradient an — damit fühlt sich die Animation kontinuierlich
    /// an und füllt das gesamte Segment, statt nur ein 40%-Sub-Band zu
    /// zeigen.
    private var activeShimmerGradient: LinearGradient {
        // Half-Bandwidth: wie weit der helle Spot links/rechts vom
        // Center ausgeschmiert ist. 0.35 = großzügig, deckt fast den
        // halben Segment-Bereich ab.
        let halfBand: CGFloat = 0.35
        let center = shimmerProgress
        // Stops zwingen wir in [0, 1] und in monotoner Reihenfolge.
        let leftStop = max(0, min(1, center - halfBand))
        let centerStop = max(0, min(1, center))
        let rightStop = max(0, min(1, center + halfBand))
        // Sanitize: gleiche Locations sind ok, müssen aber strikt
        // aufsteigend sortiert sein.
        let stops = [
            Gradient.Stop(color: activeColor.opacity(0.0), location: leftStop),
            Gradient.Stop(color: activeColor.opacity(0.95), location: centerStop),
            Gradient.Stop(color: activeColor.opacity(0.0), location: rightStop)
        ]
        return LinearGradient(
            stops: stops,
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct ScanBatchThumbnailCardView: View {
    let thumbnails: [UIImage]
    let currentIndex: Int
    let isRecognizing: Bool
    let progressText: String
    let stage: ScanRuntimeStage
    let sectionStyle: AppSectionStyle
    var inputMethod: ScanInputMethod? = nil
    /// Optionale Failed-Indizes (1-basiert wie `currentIndex`). Wenn gesetzt,
    /// werden diese Thumbnails mit Warnsymbol markiert. Nicht-zwingend —
    /// die Failed-State-Persistierung ist nicht Teil dieses Slice, der
    /// Parameter steht aber bereit für späteren Ausbau.
    var failedPageNumbers: Set<Int> = []

    /// **Per-Thumbnail-Status** (User-Spec 2026-04-23 abends): jedes
    /// Thumbnail in der Mehrbild-Analyse-Reihe hat einen klar
    /// definierten Zustand. Der aktuelle Status wird aus `currentIndex`
    /// + `isRecognizing` abgeleitet — der Mehrbild-Flow hält schon
    /// einen Sequenz-Index, ein eigener State pro Bild ist nicht nötig.
    fileprivate enum ThumbnailStatus {
        case pending     // noch nicht dran
        case analyzing   // KI läuft gerade darauf
        case done        // bereits analysiert
        case failed      // Analyse fehlgeschlagen (zukünftig)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Thumbnail strip
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, thumb in
                            let pageNum = index + 1
                            BatchThumbnailCell(
                                thumbnail: thumb,
                                status: status(for: pageNum)
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: currentIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(max(newIndex - 1, 0), anchor: .leading)
                    }
                }
            }

            // **„Bild X von Y"** — explizite Sequenz-Anzeige unter der
            // Reihe. User-Spec 2026-04-23: „Unter oder bei der Reihe
            // steht klar: KI analysiert Bild X von Y".
            if isRecognizing && thumbnails.count > 1 {
                Text("KI analysiert Bild \(currentIndex) von \(thumbnails.count)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            // Progress info
            if isRecognizing {
                ScanProgressOverlayCardView(
                    stage: stage,
                    progressText: progressText,
                    inputMethod: inputMethod,
                    // **2026-04-23 nacht**: Multi-Image-Progress-Bar
                    // unterhalb der Stage-Card. Caller hat bereits
                    // currentIndex + totalCount in den Parametern.
                    currentImageIndex: currentIndex,
                    totalImageCount: thumbnails.count
                )
            }
        }
        .padding(12)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }

    /// Leitet pro Page-Nummer den `ThumbnailStatus` aus dem flachen
    /// Sequenz-State ab. Pending/Analyzing/Done sind aus
    /// `currentIndex`+`isRecognizing` ableitbar; Failed kommt aus dem
    /// optionalen `failedPageNumbers`-Set.
    fileprivate func status(for pageNumber: Int) -> ThumbnailStatus {
        if failedPageNumbers.contains(pageNumber) { return .failed }
        if pageNumber < currentIndex { return .done }
        if pageNumber == currentIndex {
            return isRecognizing ? .analyzing : .done
        }
        return .pending
    }
}

// MARK: - Cell mit Status + Scanline

/// Einzelnes Thumbnail in der Multi-Image-Analyse-Reihe. Trennung als
/// eigene `View`, damit die Animation pro Cell ihren eigenen
/// State-Subtree hat — sonst würde ein Status-Wechsel die HStack neu
/// rendern und alle Scanlines neu starten.
private struct BatchThumbnailCell: View {
    let thumbnail: UIImage
    let status: ScanBatchThumbnailCardView.ThumbnailStatus

    /// Scanline-Position als Verhältnis (0…1) zur Thumbnail-Höhe.
    @State private var scanProgress: CGFloat = 0
    /// Pulsierender Rahmen (Reduce-Motion-Fallback statt Scanline).
    @State private var pulseOn: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Gemeinsame Cell-Maße (zentral, damit Scanline-Höhe + Frame
    /// nicht auseinanderlaufen).
    private static let cellWidth: CGFloat = 64
    private static let cellHeight: CGFloat = 80
    private static let cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            // Bild — bei done leicht abgeblendet
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: Self.cellWidth, height: Self.cellHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .opacity(status == .done ? 0.5 : 1.0)

            // Status-Overlays
            switch status {
            case .pending:
                EmptyView()

            case .analyzing:
                analyzingOverlay
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))

            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.success)
                    .background(Circle().fill(.white))

            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .background(Circle().fill(.white))
            }
        }
        .frame(width: Self.cellWidth, height: Self.cellHeight)
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: borderLineWidth)
                .opacity(borderOpacity)
        )
        .shadow(color: borderColor.opacity(status == .analyzing ? 0.45 : 0), radius: 6)
        .onAppear { triggerAnimationIfNeeded() }
        .onChange(of: status) { _, _ in triggerAnimationIfNeeded() }
    }

    // MARK: - Analyzing-Overlay

    /// Subtle Dimm + Scanline ODER pulsierender Rahmen (Reduce-Motion).
    @ViewBuilder
    private var analyzingOverlay: some View {
        ZStack {
            // Dezenter Dimm, damit die Scanline gegen das Bild absticht
            Color.black.opacity(0.10)

            if !reduceMotion {
                scanlineLayer
            }
        }
    }

    /// Horizontale Scanline, die ruhig von oben nach unten läuft.
    /// Smooth durch lineare Animation ohne autoreverse → wirkt
    /// kontinuierlich wie ein echter Scanner.
    ///
    /// **Bug-Fix 2026-04-24 (Top-Offset)**: Vorher lief die Line über
    /// eine VStack-mit-Spacer-Konstruktion, wobei die mittlere
    /// `ZStack { Rectangle(2pt), Rectangle(22pt-Glow) }` durch
    /// Default-`.center`-Alignment die 2pt-Linie mittig im 22pt-
    /// Container platzierte. Bei `scanProgress = 0` saß die sichtbare
    /// Linie damit ~10pt UNTER der oberen Thumbnail-Kante statt bei
    /// y=0.
    ///
    /// Jetzt: die Line ist das strukturelle Element (2pt), der 22pt-
    /// Glow liegt als `.overlay` zentriert auf der Linie (klipps
    /// automatisch an den Rändern). Positionierung über
    /// `.offset(y: scanProgress * (cellHeight - 2))`:
    ///   • `scanProgress = 0` → Line bei y=0..2 (exakt an Oberkante)
    ///   • `scanProgress = 1` → Line bei y=cellHeight-2..cellHeight
    ///                          (exakt an Unterkante)
    /// Der Glow überragt oben und unten die sichtbare Kante — das
    /// `.clipped()` der umschließenden ZStack cuttet sauber auf die
    /// Thumbnail-Fläche.
    private var scanlineLayer: some View {
        ZStack(alignment: .top) {
            // Belegt die volle Cell-Fläche, damit das `.top`-Alignment
            // einen definierten Bezug hat.
            Color.clear

            Rectangle()
                .fill(scanLineColor)
                .frame(height: 2)
                .shadow(color: scanLineColor.opacity(0.85), radius: 4, y: 0)
                .overlay(
                    // 22pt-Glow zentriert auf der 2pt-Linie — kein
                    // eigener Container, keine Alignment-Diskrepanz.
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    scanLineColor.opacity(0.0),
                                    scanLineColor.opacity(0.45),
                                    scanLineColor.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 22)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                )
                .offset(y: scanProgress * (Self.cellHeight - 2))
        }
        .frame(width: Self.cellWidth, height: Self.cellHeight)
        .clipped()
        .allowsHitTesting(false)
    }

    // MARK: - Border + Color

    private var borderColor: Color {
        switch status {
        case .analyzing: return scanLineColor
        case .failed:    return AppTheme.Colors.warning
        default:         return .clear
        }
    }

    private var borderLineWidth: CGFloat {
        switch status {
        case .analyzing: return 2.4
        case .failed:    return 1.6
        default:         return 0
        }
    }

    private var borderOpacity: Double {
        // Reduce-Motion: pulsiere die Rahmenopazität als Ersatz für die
        // Scanline-Animation (User-Spec 2026-04-23 abends).
        guard status == .analyzing, reduceMotion else { return 1.0 }
        return pulseOn ? 1.0 : 0.4
    }

    /// Konsistenter Orange-Ton (warmes Akzent) — bewusst hardcoded,
    /// weil keine semantische Token-Variante in AppTheme existiert
    /// und der User explizit „orange" wollte.
    private var scanLineColor: Color {
        Color(hex: "#FF8A4D")
    }

    // MARK: - Animation-Trigger

    /// Startet/stoppt Animationen abhängig vom Status.
    private func triggerAnimationIfNeeded() {
        switch status {
        case .analyzing:
            if reduceMotion {
                scanProgress = 0
                if !pulseOn {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulseOn.toggle()
                    }
                }
            } else {
                pulseOn = false
                scanProgress = 0
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    scanProgress = 1.0
                }
            }
        default:
            scanProgress = 0
            pulseOn = false
        }
    }
}

struct ScanSelectedImageCardView: View {
    let image: UIImage
    let isRecognizingImage: Bool
    let progressText: String
    let stage: ScanRuntimeStage
    let sectionStyle: AppSectionStyle
    let onTap: () -> Void
    var inputMethod: ScanInputMethod? = nil
    @State private var scanLineOffset: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 220, maxHeight: 320)

                if isRecognizingImage {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.12))

                    // Scanner stripe animation
                    GeometryReader { geo in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        sectionStyle.accent.opacity(0),
                                        sectionStyle.accent.opacity(0.6),
                                        sectionStyle.accent.opacity(0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 3)
                            .shadow(color: sectionStyle.accent.opacity(0.5), radius: 6, x: 0, y: 0)
                            .offset(y: scanLineOffset * geo.size.height)
                    }

                    ScanProgressOverlayCardView(
                        stage: stage,
                        progressText: progressText,
                        inputMethod: inputMethod
                    )
                    .frame(maxWidth: 320)
                    .frame(maxWidth: AppTheme.Layout.maxContentWidth)
                    .padding(.horizontal, 18)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
        .onChange(of: isRecognizingImage) { _, recognizing in
            if recognizing {
                scanLineOffset = 0
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: true)) {
                    scanLineOffset = 1.0
                }
            } else {
                withAnimation(.none) {
                    scanLineOffset = 0
                }
            }
        }
    }
}
