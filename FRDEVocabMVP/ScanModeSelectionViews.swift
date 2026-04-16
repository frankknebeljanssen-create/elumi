import SwiftUI

private struct ScanSelectionButtonCard: View {
    let systemImage: String
    let title: String
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : accent)

            Text(title)
                .font(AppTheme.Typography.body)
                .foregroundStyle(isSelected ? Color.white : AppTheme.Colors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 50, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accent : AppTheme.Colors.secondarySurface)

                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? Color.white.opacity(0.24) : AppTheme.Colors.border,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .scaleEffect(isSelected ? 1.015 : 1)
        .shadow(
            color: isSelected ? accent.opacity(0.34) : .clear,
            radius: isSelected ? 16 : 0,
            x: 0,
            y: isSelected ? 8 : 0
        )
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

struct ScanModeSelectionCardView: View {
    let activeMode: ScanMode
    let sectionStyle: AppSectionStyle
    let onSelect: (ScanMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Was möchtest du scannen?")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            HStack(spacing: 10) {
                ForEach(ScanMode.allCases) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        ScanSelectionButtonCard(
                            systemImage: mode.systemImage,
                            title: mode.title,
                            isSelected: activeMode == mode,
                            accent: sectionStyle.accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }
}

struct ScanInputMethodOptionsCardView: View {
    let isRecognizingImage: Bool
    let isCameraAvailable: Bool
    let selectedMethod: ScanInputMethod?
    let sectionStyle: AppSectionStyle
    let onCamera: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 10) {
                Button(action: onCamera) {
                    ScanSelectionButtonCard(
                        systemImage: "camera.fill",
                        title: "Kamera",
                        isSelected: selectedMethod == .camera,
                        accent: sectionStyle.accent
                    )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!isRecognizingImage && isCameraAvailable)
                .opacity(isCameraAvailable ? 1 : 0.5)

                Button(action: onLibrary) {
                    ScanSelectionButtonCard(
                        systemImage: "photo.on.rectangle.fill",
                        title: "Foto-Album",
                        isSelected: selectedMethod == .library,
                        accent: sectionStyle.accent
                    )
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!isRecognizingImage)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.sm)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }
}
