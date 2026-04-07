import SwiftUI

extension ElumiArcadeGameView {
    @ViewBuilder
    func fallingObjectView(for snack: ElumiArcadeSnackState, at date: Date) -> some View {
        let renderSize = snackRenderSize(for: snack)
        switch snack.kind {
        case .wuermchen, .wasserfloh, .algenkugel:
            if let snackKind = snack.kind.snackKind {
                ElumiSnackIcon(snackKind, size: renderSize)
                    .scaleEffect(
                        x: arcadeScaleX(for: snack, at: date),
                        y: arcadeScaleY(for: snack, at: date)
                    )
                    .rotationEffect(.degrees(arcadeSnackTilt(for: snack, at: date)))
            }
        case .bonusblase:
            bonusBubbleIcon(size: renderSize, at: date)
        case .saugglocke:
            suctionCupIcon(size: renderSize, at: date)
        case .falseElumi:
            hazardElumiIcon(size: renderSize, at: date)
        }
    }

    var arcadeSnackPointsHUD: some View {
        HStack(spacing: 6) {
            arcadePointsChip(kind: .wuermchen, value: snackPoints(for: .wuermchen))
            arcadePointsChip(kind: .wasserfloh, value: snackPoints(for: .wasserfloh))
            arcadePointsChip(kind: .algenkugel, value: snackPoints(for: .algenkugel))
        }
    }

    func arcadePointsChip(kind: ElumiArcadeDropKind, value: Int) -> some View {
        HStack(spacing: 4) {
            if let snackKind = kind.snackKind {
                ElumiSnackIcon(snackKind, size: kind == .wasserfloh ? 17 : 15)
            }
            Text("+\(value)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(AppTheme.Colors.secondarySurface.opacity(0.92))
        .clipShape(Capsule())
    }

    func arcadeStatusChip(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(AppTheme.Colors.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.22))
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.38), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    func suctionCupIcon(size: CGFloat, at date: Date) -> some View {
        let pulse = 0.94 + (0.08 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 7.2)))

        return ZStack {
            Circle()
                .fill(AppTheme.Colors.warning.opacity(0.16))
                .frame(width: size * 1.2, height: size * 1.2)
                .blur(radius: 6)
                .scaleEffect(pulse)

            Circle()
                .stroke(AppTheme.Colors.warning.opacity(0.46), lineWidth: 1.6)
                .frame(width: size * 1.08, height: size * 1.08)
                .scaleEffect(0.96 + (0.06 * pulse))

            Capsule()
                .fill(AppTheme.Colors.textPrimary.opacity(0.92))
                .frame(width: size * 0.16, height: size * 0.34)
                .offset(y: -size * 0.16)

            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(AppTheme.Colors.warning)
                .frame(width: size * 0.38, height: size * 0.18)
                .offset(y: -size * 0.03)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.elumiMint.opacity(0.88),
                            AppTheme.Colors.primary.opacity(0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.86, height: size * 0.44)
                .overlay(
                    Ellipse()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1.2)
                )
                .offset(y: size * 0.12)

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.18, weight: .black))
                .foregroundStyle(Color.white.opacity(0.92))
                .offset(x: size * 0.18, y: -size * 0.16)
        }
        .shadow(color: AppTheme.Colors.warning.opacity(0.28), radius: 12, x: 0, y: 5)
    }

    func bonusBubbleIcon(size: CGFloat, at date: Date) -> some View {
        let pulse = 0.92 + (0.08 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 6.8)))

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            AppTheme.Colors.warning.opacity(0.96),
                            AppTheme.Colors.primary.opacity(0.78)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.54
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1.2)
                )

            Image(systemName: "star.fill")
                .font(.system(size: size * 0.34, weight: .black))
                .foregroundStyle(Color.white)

            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: size * 0.24, height: size * 0.24)
                .offset(x: -size * 0.18, y: -size * 0.2)
        }
        .scaleEffect(pulse)
        .shadow(color: AppTheme.Colors.warning.opacity(0.34), radius: 12, x: 0, y: 4)
    }

    func hazardElumiIcon(size: CGFloat, at date: Date) -> some View {
        let pulse = 0.92 + (0.09 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 8.5)))

        return ZStack {
            Circle()
                .fill(AppTheme.Colors.error.opacity(0.16))
                .frame(width: size * 1.16, height: size * 1.16)
                .blur(radius: 5)
                .scaleEffect(pulse)

            Circle()
                .stroke(AppTheme.Colors.error.opacity(0.86), lineWidth: 3)
                .frame(width: size * 0.98, height: size * 0.98)
                .overlay(
                    Circle()
                        .stroke(AppTheme.Colors.error.opacity(0.32), lineWidth: 2)
                        .scaleEffect(1.12 + (0.06 * pulse))
                )

            Image("SplashCharacter")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size * 0.9, height: size * 0.9)
                .saturation(0.72)
                .overlay(
                    Circle()
                        .stroke(AppTheme.Colors.error.opacity(0.35), lineWidth: 2)
                        .padding(size * 0.1)
                )

            VStack(spacing: 2) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.18, weight: .black))
                Image(systemName: "exclamationmark")
                    .font(.system(size: size * 0.18, weight: .black))
            }
            .foregroundStyle(Color.white)
            .padding(size * 0.08)
            .background(AppTheme.Colors.error.opacity(0.94))
            .clipShape(Capsule())
            .offset(x: size * 0.24, y: -size * 0.22)
        }
        .shadow(color: AppTheme.Colors.error.opacity(0.34), radius: 14, x: 0, y: 6)
    }
}
