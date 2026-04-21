import SwiftUI
import UIKit

struct ManualCropSheet: View {
    let image: UIImage
    let accent: Color
    let onCancel: () -> Void
    let onApply: (UIImage, Bool) -> Void

    @State private var cropRect: CGRect = .zero
    @State private var dragStartRect: CGRect?
    @State private var lastImageFrame: CGRect = .zero

    /// **Rotations-Counter** (Anzahl 90°-CW-Schritte). 0…3.
    /// 0 = Original, 1 = 90°, 2 = 180°, 3 = 270°.
    @State private var rotationSteps: Int = 0
    /// **Feinrotation** in Grad — User-Slider für minimal schiefe
    /// Captures (z. B. wenn das Buch ganz leicht schief gehalten wurde).
    /// Bereich −15…+15 °. Wird **zusätzlich** zur 90°-Step-Rotation
    /// angewandt: Gesamtwinkel = `rotationSteps × 90 + fineRotation`.
    @State private var fineRotation: Double = 0
    /// Cache-Key des aktuell gerenderten `rotatedImageCache`.
    /// Zwingt Re-Render nur, wenn sich Steps ODER Fine-Winkel geändert
    /// haben — nicht bei jedem View-Update.
    @State private var rotatedImageCache: UIImage? = nil
    @State private var lastRenderedRotationKey: String? = nil

    private let minimumCropSize: CGFloat = 80
    /// Maximaler Slider-Bereich für die Feinrotation (±).
    private let maxFineRotationDegrees: Double = 15

    /// Effektives Bild nach Rotation. Das gesamte Sheet (Vorschau,
    /// Crop, Apply) arbeitet auf diesem Image.
    private var displayImage: UIImage { rotatedImageCache ?? image }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            HStack {
                // **Drehen-Button** (User-Wunsch): rotiert das Bild
                // 90° im Uhrzeigersinn. Crop-Rect wird zurückgesetzt,
                // weil sich Bild-Aspect-Ratio ändert.
                Button {
                    rotate90CW()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rotate.right")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Drehen")
                            .font(AppTheme.Typography.button)
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(accent.opacity(0.14))
                    )
                    .overlay(
                        Capsule().stroke(accent.opacity(0.45), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bild drehen")

                Spacer()

                Text("Zuschneiden")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer()

                // Symmetrie-Filler — Drehen-Button ist links, hier
                // halten wir die Mittel-Headline visuell zentriert.
                Color.clear.frame(width: 86, height: 28)
            }
            .padding(.top, 12)

            GeometryReader { geometry in
                let imageFrame = fittedImageFrame(for: displayImage.size, in: geometry.size)

                ZStack {
                    Color.clear

                    Image(uiImage: displayImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear {
                            initializeCropRectIfNeeded(imageFrame: imageFrame)
                        }
                        .onChange(of: geometry.size) { _, _ in
                            initializeCropRectIfNeeded(imageFrame: imageFrame, force: true)
                        }
                        .onChange(of: rotationSteps) { _, _ in
                            updateRotatedImage()
                            initializeCropRectIfNeeded(imageFrame: imageFrame, force: true)
                        }
                        .onChange(of: fineRotation) { _, _ in
                            updateRotatedImage()
                            initializeCropRectIfNeeded(imageFrame: imageFrame, force: true)
                        }

                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .mask(
                            Rectangle()
                                .overlay(alignment: .topLeading) {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .frame(width: cropRect.width, height: cropRect.height)
                                        .offset(x: cropRect.minX, y: cropRect.minY)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                                .luminanceToAlpha()
                        )
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent, lineWidth: 3)
                        .frame(width: cropRect.width, height: cropRect.height)
                        .position(x: cropRect.midX, y: cropRect.midY)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if dragStartRect == nil { dragStartRect = cropRect }
                                    guard let startRect = dragStartRect else { return }
                                    cropRect = movedCropRect(
                                        startRect,
                                        translation: value.translation,
                                        within: imageFrame
                                    )
                                    lastImageFrame = imageFrame
                                }
                                .onEnded { _ in
                                    dragStartRect = nil
                                }
                        )

                    ForEach(CropHandle.allCases, id: \.self) { handle in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(accent, lineWidth: 3)
                            )
                            .position(position(for: handle, in: cropRect))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if dragStartRect == nil { dragStartRect = cropRect }
                                        guard let startRect = dragStartRect else { return }
                                        cropRect = resizedCropRect(
                                            startRect,
                                            handle: handle,
                                            translation: value.translation,
                                            within: imageFrame
                                        )
                                        lastImageFrame = imageFrame
                                    }
                                    .onEnded { _ in
                                        dragStartRect = nil
                                    }
                            )
                    }
                }
            }

            // **Fein-Rotations-Slider** (User-Wunsch: „minimal
            // korrigieren"). ±15 ° um den 90°-Step herum. Reset-Tap
            // auf den Wert-Label setzt zurück auf 0.
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "rotate.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Slider(
                        value: $fineRotation,
                        in: -maxFineRotationDegrees...maxFineRotationDegrees,
                        step: 0.5
                    )
                    .tint(accent)
                    Image(systemName: "rotate.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Button {
                        fineRotation = 0
                    } label: {
                        Text(String(format: "%+.1f°", fineRotation))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(fineRotation == 0 ? AppTheme.Colors.textSecondary : accent)
                            .frame(minWidth: 56)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Feinrotation zurücksetzen")
                }
                .padding(.horizontal, 4)
            }

            Text("Zieh den Rahmen oder die Ecken, damit nur die Buchseite übrig bleibt.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .appScreenBackground(.scan)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Button("Abbrechen") {
                    onCancel()
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textPrimary))

                HStack(spacing: 12) {
                    Button("Übernehmen") {
                        if let cropped = croppedImage(from: displayImage, imageFrame: lastImageFrame, cropRect: cropRect) {
                            onApply(cropped, false)
                        } else {
                            onCancel()
                        }
                    }
                    .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textPrimary))

                    Button("Übernehmen + Analysieren") {
                        if let cropped = croppedImage(from: displayImage, imageFrame: lastImageFrame, cropRect: cropRect) {
                            onApply(cropped, true)
                        } else {
                            onCancel()
                        }
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.surface.opacity(0.98))
        }
    }

    private func initializeCropRectIfNeeded(imageFrame: CGRect, force: Bool = false) {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return }
        if force || cropRect == .zero || lastImageFrame != imageFrame {
            cropRect = imageFrame.insetBy(dx: imageFrame.width * 0.08, dy: imageFrame.height * 0.08)
            lastImageFrame = imageFrame
        }
    }

    private func fittedImageFrame(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let imageRatio = imageSize.width / imageSize.height
        let containerRatio = containerSize.width / max(containerSize.height, 1)

        if imageRatio > containerRatio {
            let width = containerSize.width
            let height = width / imageRatio
            return CGRect(x: 0, y: (containerSize.height - height) / 2, width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageRatio
            return CGRect(x: (containerSize.width - width) / 2, y: 0, width: width, height: height)
        }
    }

    private func movedCropRect(_ rect: CGRect, translation: CGSize, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: translation.width, dy: translation.height)

        if moved.minX < bounds.minX { moved.origin.x = bounds.minX }
        if moved.maxX > bounds.maxX { moved.origin.x = bounds.maxX - moved.width }
        if moved.minY < bounds.minY { moved.origin.y = bounds.minY }
        if moved.maxY > bounds.maxY { moved.origin.y = bounds.maxY - moved.height }

        return moved
    }

    private func resizedCropRect(
        _ rect: CGRect,
        handle: CropHandle,
        translation: CGSize,
        within bounds: CGRect
    ) -> CGRect {
        var updated = rect

        switch handle {
        case .topLeft:
            updated.origin.x += translation.width
            updated.origin.y += translation.height
            updated.size.width -= translation.width
            updated.size.height -= translation.height
        case .topRight:
            updated.origin.y += translation.height
            updated.size.width += translation.width
            updated.size.height -= translation.height
        case .bottomLeft:
            updated.origin.x += translation.width
            updated.size.width -= translation.width
            updated.size.height += translation.height
        case .bottomRight:
            updated.size.width += translation.width
            updated.size.height += translation.height
        }

        if updated.width < minimumCropSize {
            switch handle {
            case .topLeft, .bottomLeft:
                updated.origin.x = rect.maxX - minimumCropSize
            default:
                break
            }
            updated.size.width = minimumCropSize
        }

        if updated.height < minimumCropSize {
            switch handle {
            case .topLeft, .topRight:
                updated.origin.y = rect.maxY - minimumCropSize
            default:
                break
            }
            updated.size.height = minimumCropSize
        }

        if updated.minX < bounds.minX {
            let delta = bounds.minX - updated.minX
            updated.origin.x += delta
            updated.size.width -= delta
        }

        if updated.minY < bounds.minY {
            let delta = bounds.minY - updated.minY
            updated.origin.y += delta
            updated.size.height -= delta
        }

        if updated.maxX > bounds.maxX {
            updated.size.width = bounds.maxX - updated.minX
        }

        if updated.maxY > bounds.maxY {
            updated.size.height = bounds.maxY - updated.minY
        }

        updated.size.width = max(updated.width, minimumCropSize)
        updated.size.height = max(updated.height, minimumCropSize)

        return updated
    }

    private func position(for handle: CropHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// Rotiert das Quellbild um weitere 90° im Uhrzeigersinn.
    /// Crop-Rect wird per `onChange(of: rotationSteps)` automatisch
    /// zurückgesetzt; das gerenderte Cache-Image baut `updateRotatedImage()`.
    private func rotate90CW() {
        rotationSteps = (rotationSteps + 1) % 4
    }

    /// (Re-)Rendert `rotatedImageCache` basierend auf
    /// `rotationSteps` + `fineRotation`. Idempotent — wenn der
    /// Rotation-Key gleich bleibt, passiert nichts.
    private func updateRotatedImage() {
        let key = "\(rotationSteps)|\(fineRotation)"
        guard key != lastRenderedRotationKey else { return }
        lastRenderedRotationKey = key

        if rotationSteps == 0, fineRotation == 0 {
            rotatedImageCache = nil
            return
        }
        let totalDegrees = Double(rotationSteps) * 90.0 + fineRotation
        rotatedImageCache = ManualCropSheet.rotated(image, byDegrees: totalDegrees)
    }

    /// Rotiert ein UIImage um beliebige Grade im Uhrzeigersinn.
    /// Liefert ein neues UIImage mit Pixel-Rotation (`imageOrientation
    /// = .up`). Bei Nicht-90°-Vielfachen wird die Output-Canvas auf
    /// die Bounding-Box des rotierten Rechtecks erweitert; freie Ecken
    /// bleiben transparent (Crop-Tool kann sie der User dann
    /// rauscroppen).
    private static func rotated(_ image: UIImage, byDegrees degrees: Double) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let radians = CGFloat(degrees) * .pi / 180

        let srcW = CGFloat(cg.width)
        let srcH = CGFloat(cg.height)
        // Bounding-Box des rotierten Rechtecks
        let rotatedBox = CGRect(x: 0, y: 0, width: srcW, height: srcH)
            .applying(CGAffineTransform(rotationAngle: radians))
        let outW = abs(rotatedBox.width)
        let outH = abs(rotatedBox.height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outW, height: outH), format: format)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.translateBy(x: outW / 2, y: outH / 2)
            cgCtx.rotate(by: radians)
            cgCtx.translateBy(x: -srcW / 2, y: -srcH / 2)
            // CG y-axis flippen für upright drawing.
            cgCtx.translateBy(x: 0, y: srcH)
            cgCtx.scaleBy(x: 1, y: -1)
            cgCtx.draw(cg, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))
        }
    }

    private func croppedImage(from image: UIImage, imageFrame: CGRect, cropRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage, imageFrame.width > 0, imageFrame.height > 0 else { return nil }

        let scaleX = CGFloat(cgImage.width) / imageFrame.width
        let scaleY = CGFloat(cgImage.height) / imageFrame.height

        let crop = CGRect(
            x: (cropRect.minX - imageFrame.minX) * scaleX,
            y: (cropRect.minY - imageFrame.minY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        ).integral

        guard crop.width > 10, crop.height > 10,
              let cropped = cgImage.cropping(to: crop) else { return nil }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }
}

private enum CropHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}
