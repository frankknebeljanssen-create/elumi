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

    private let minimumCropSize: CGFloat = 80

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Text("Zuschneiden")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)

            GeometryReader { geometry in
                let imageFrame = fittedImageFrame(for: image.size, in: geometry.size)

                ZStack {
                    Color.clear

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear {
                            initializeCropRectIfNeeded(imageFrame: imageFrame)
                        }
                        .onChange(of: geometry.size) { _, _ in
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
                        if let cropped = croppedImage(from: image, imageFrame: lastImageFrame, cropRect: cropRect) {
                            onApply(cropped, false)
                        } else {
                            onCancel()
                        }
                    }
                    .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textPrimary))

                    Button("Übernehmen + Analysieren") {
                        if let cropped = croppedImage(from: image, imageFrame: lastImageFrame, cropRect: cropRect) {
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
