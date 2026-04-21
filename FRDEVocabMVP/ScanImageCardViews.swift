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

    var body: some View {
        VStack(spacing: 10) {
            // Zeile 1: Batch-/Progress-Info („Seite 2/3", „Analysiere…")
            // bewusst klein und unaufdringlich — die Stage-Info
            // darunter ist jetzt der Hauptfokus.
            Text(progressText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
}

struct ScanBatchThumbnailCardView: View {
    let thumbnails: [UIImage]
    let currentIndex: Int
    let isRecognizing: Bool
    let progressText: String
    let stage: ScanRuntimeStage
    let sectionStyle: AppSectionStyle
    var inputMethod: ScanInputMethod? = nil

    var body: some View {
        VStack(spacing: 10) {
            // Thumbnail strip
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, thumb in
                            let pageNum = index + 1
                            let isCurrent = pageNum == currentIndex
                            let isDone = pageNum < currentIndex

                            ZStack {
                                Image(uiImage: thumb)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .opacity(isDone ? 0.5 : 1.0)

                                if isDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(AppTheme.Colors.success)
                                }

                                if isCurrent && isRecognizing {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.black.opacity(0.15))
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                        .scaleEffect(0.8)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isCurrent ? sectionStyle.accent : Color.clear, lineWidth: 2)
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

            // Progress info
            if isRecognizing {
                ScanProgressOverlayCardView(
                    stage: stage,
                    progressText: progressText,
                    inputMethod: inputMethod
                )
            }
        }
        .padding(12)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
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
