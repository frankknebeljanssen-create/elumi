import SwiftUI

// MARK: - Standalone Icon-Views (überall in der App nutzbar)

/// Echter Elumi-Avatar — gleiches Asset wie im Footer-Button und im Spiel.
struct ArcadeElumiAvatar: View {
    let size: CGFloat
    var withShadow: Bool = true

    var body: some View {
        Image("SplashCharacter")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: withShadow ? .black.opacity(0.16) : .clear,
                    radius: withShadow ? 4 : 0,
                    x: 0,
                    y: withShadow ? 2 : 0)
    }
}

/// Elumi-Freund (blauer „falscher" Elumi). Statische Version des hazardElumiIcon.
struct ArcadeHazardElumiAvatar: View {
    let size: CGFloat
    private let glowColor = Color(red: 0.2, green: 0.6, blue: 0.9)

    var body: some View {
        let friendSize = size * 1.1
        ZStack {
            Circle()
                .fill(glowColor.opacity(0.22))
                .frame(width: friendSize * 1.15, height: friendSize * 1.15)
                .blur(radius: 5)

            Image("SplashCharacter")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: friendSize * 0.92, height: friendSize * 0.92)
                .saturation(0.85)
                .hueRotation(.degrees(-80))
                .brightness(0.05)
                .clipShape(Circle())

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
}

/// Saugglocke — statische Version des suctionCupIcon.
struct ArcadeSuctionIconStandalone: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.warning.opacity(0.16))
                .frame(width: size * 1.2, height: size * 1.2)
                .blur(radius: 6)

            Circle()
                .stroke(AppTheme.Colors.warning.opacity(0.46), lineWidth: 1.6)
                .frame(width: size * 1.08, height: size * 1.08)

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
        .frame(width: size, height: size)
        .shadow(color: AppTheme.Colors.warning.opacity(0.28), radius: 12, x: 0, y: 5)
    }
}

/// Zeitlupe-Trank — statische Version des slowMotionPotionIcon.
struct ArcadeSlowMotionIconStandalone: View {
    let size: CGFloat

    var body: some View {
        ZStack {
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
        .shadow(color: Color.blue.opacity(0.4), radius: 14, x: 0, y: 4)
    }
}

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
            .scaleEffect(x: fish.fromLeft ? -1 : 1, y: 1)
            .rotationEffect(.degrees(wobble))
            .shadow(color: .cyan.opacity(0.4), radius: 6, x: 0, y: 2)
    }

    // ── Jellyfish ──

    func jellyfishView(for jelly: JellyfishState, at date: Date, in size: CGSize) -> some View {
        let elapsed = date.timeIntervalSince(jelly.spawnedAt)
        let pulse = 0.85 + sin(elapsed * 2.0) * 0.15
        let tentaclePhases: [Double] = [0, 0.8, 1.6, 2.4, 3.2, 4.0, 4.8]

        return ZStack {
            // Outer glow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 50
                    )
                )
                .frame(width: 80, height: 60)
                .scaleEffect(CGFloat(pulse) * 1.2)

            // Bell (dome)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.85, green: 0.5, blue: 1.0).opacity(0.7),
                            Color(red: 0.6, green: 0.2, blue: 0.9).opacity(0.5),
                            Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.25)
                        ],
                        center: .init(x: 0.4, y: 0.3),
                        startRadius: 2,
                        endRadius: 30
                    )
                )
                .frame(width: 52, height: 38)
                .scaleEffect(y: CGFloat(pulse))

            // Inner bell highlight
            Ellipse()
                .fill(Color.white.opacity(0.25))
                .frame(width: 24, height: 14)
                .offset(y: -6)
                .blur(radius: 2)

            // Tentacles
            ForEach(0..<7, id: \.self) { i in
                let phase = tentaclePhases[i]
                let baseX = CGFloat(i - 3) * 6
                let sway = sin(elapsed * 2.8 + phase) * 8
                let length: CGFloat = [40, 55, 48, 60, 45, 52, 38][i]

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.7, green: 0.3, blue: 1.0).opacity(0.6),
                                Color(red: 0.2, green: 0.9, blue: 0.4).opacity(0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: length)
                    .offset(x: baseX + CGFloat(sway), y: 18 + length * 0.5)
                    .rotationEffect(.degrees(sway * 0.4), anchor: .top)
            }
        }
        .opacity(0.88)
        .shadow(color: Color.purple.opacity(0.5), radius: 12, x: 0, y: 4)
        .scaleEffect(x: jelly.fromLeft ? 1 : -1, y: 1)
    }

    func fallingTentacleView(for tentacle: TentacleDropState, at date: Date) -> some View {
        let elapsed = date.timeIntervalSince(tentacle.spawnedAt)
        let progress = elapsed / tentacle.fallDuration
        let pulse = 0.8 + sin(elapsed * 5.0) * 0.2
        let sway = sin(elapsed * 3.0) * 6

        return ZStack {
            // Glow
            Capsule()
                .fill(Color(red: 0.2, green: 0.9, blue: 0.3).opacity(0.3))
                .frame(width: 12, height: 36)
                .blur(radius: 4)
                .scaleEffect(CGFloat(pulse) * 1.1)

            // Tentacle body
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.7, green: 0.2, blue: 1.0).opacity(0.8),
                            Color(red: 0.1, green: 0.9, blue: 0.3).opacity(0.7)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 5, height: 28 + CGFloat(progress) * 8)

            // Poison droplet tip
            Circle()
                .fill(Color(red: 0.1, green: 1.0, blue: 0.3).opacity(0.6))
                .frame(width: 8, height: 8)
                .offset(y: 14 + CGFloat(progress) * 4)
        }
        .rotationEffect(.degrees(sway * 0.5))
        .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.3).opacity(0.5), radius: 6)
    }
}
