import SwiftUI

struct ScanProgressOverlayCardView: View {
    let progressText: String
    let runtimeLabel: String
    let runtimeTint: Color
    let runtimeIcon: String

    var body: some View {
        ZStack {
            HStack {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.Colors.textPrimary.opacity(0.92))

                Spacer(minLength: 0)
            }

            VStack(spacing: 4) {
                Text(progressText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .frame(maxWidth: .infinity, alignment: .center)

                Label(runtimeLabel, systemImage: runtimeIcon)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(runtimeTint)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.surface.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

struct ScanSelectedImageCardView: View {
    let image: UIImage
    let isRecognizingImage: Bool
    let progressText: String
    let runtimeLabel: String
    let runtimeTint: Color
    let runtimeIcon: String
    let sectionStyle: AppSectionStyle
    let onTap: () -> Void
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                        progressText: progressText,
                        runtimeLabel: runtimeLabel,
                        runtimeTint: runtimeTint,
                        runtimeIcon: runtimeIcon
                    )
                    .frame(maxWidth: 280)
                    .frame(maxWidth: AppTheme.Layout.maxContentWidth)
                    .padding(.horizontal, 18)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .appCardBackground(sectionStyle, intensity: 0.09)
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
