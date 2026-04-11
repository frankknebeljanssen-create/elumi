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
        case .slowMotionPotion:
            slowMotionPotionIcon(size: renderSize, at: date)
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

    func slowMotionPotionIcon(size: CGFloat, at date: Date) -> some View {
        let pulse = 0.90 + (0.10 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 5.0)))

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.9),
                            Color.blue.opacity(0.85),
                            Color.blue.opacity(0.5)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size * 0.54
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 1.5)
                )

            Text("🧪")
                .font(.system(size: size * 0.48))

            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: size * 0.2, height: size * 0.2)
                .offset(x: -size * 0.16, y: -size * 0.18)
        }
        .frame(width: size, height: size)
        .scaleEffect(pulse)
        .shadow(color: Color.blue.opacity(0.4), radius: 14, x: 0, y: 4)
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
                .frame(width: size, height: size)
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
        .frame(width: size, height: size)
        .scaleEffect(pulse)
        .shadow(color: AppTheme.Colors.warning.opacity(0.34), radius: 12, x: 0, y: 4)
    }

    func hazardElumiIcon(size: CGFloat, at date: Date) -> some View {
        let friendSize = size * 1.1
        let pulse = 0.94 + (0.06 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 5.0)))
        let glowColor = Color(red: 0.2, green: 0.6, blue: 0.9)

        return ZStack {
            // Blue glow
            Circle()
                .fill(glowColor.opacity(0.22))
                .frame(width: friendSize * 1.15, height: friendSize * 1.15)
                .blur(radius: 5)
                .scaleEffect(pulse)

            // Blue Elumi friend
            Image("SplashCharacter")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: friendSize * 0.92, height: friendSize * 0.92)
                .saturation(0.85)
                .hueRotation(.degrees(-80))
                .brightness(0.05)
                .clipShape(Circle())

            // Small blue heart badge
            Circle()
                .fill(Color.cyan)
                .frame(width: friendSize * 0.20, height: friendSize * 0.20)
                .overlay(
                    Image(systemName: "heart.fill")
                        .font(.system(size: friendSize * 0.11, weight: .bold))
                        .foregroundStyle(.white)
                )
                .offset(x: friendSize * 0.3, y: -friendSize * 0.28)
        }
        .shadow(color: glowColor.opacity(0.35), radius: 10, x: 0, y: 4)
    }

    // ── Bonus Fish ──

    func bonusFishView(for fish: BonusFishState, at date: Date, in size: CGSize) -> some View {
        let elapsed = date.timeIntervalSince(fish.spawnedAt)
        let wobble = sin(elapsed * 4.0 + fish.wobblePhase) * 5

        let size = 28 * fish.renderScale

        return Text("🐟")
            .font(.system(size: size))
            .scaleEffect(x: fish.fromLeft ? 1 : -1, y: 1)
            .rotationEffect(.degrees(wobble))
            .shadow(color: .cyan.opacity(0.4), radius: 6, x: 0, y: 2)
    }
}
