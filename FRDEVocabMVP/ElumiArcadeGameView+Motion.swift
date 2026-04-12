import SwiftUI

extension ElumiArcadeGameView {
    func snackRenderSize(for snack: ElumiArcadeSnackState) -> CGFloat {
        let baseSize: CGFloat
        switch snack.kind {
        case .wuermchen:
            baseSize = 32
        case .wasserfloh:
            baseSize = 42
        case .algenkugel:
            baseSize = 26
        case .bonusblase:
            baseSize = 28
        case .saugglocke:
            baseSize = 38
        case .slowMotionPotion:
            baseSize = 34
        case .falseElumi:
            baseSize = 46
        }

        return baseSize * snack.renderScale
    }

    func spawnRenderScale(for kind: ElumiArcadeDropKind) -> CGFloat {
        switch kind {
        case .wuermchen:
            return CGFloat.random(in: 1.0...1.45)
        case .wasserfloh:
            return CGFloat.random(in: 1.0...2.0)
        case .algenkugel:
            return CGFloat.random(in: 1.0...2.0)
        case .bonusblase:
            return 1.0
        case .saugglocke:
            return 1.0
        case .slowMotionPotion:
            return 1.0
        case .falseElumi:
            return 1.0
        }
    }

    func snackPoints(for kind: ElumiArcadeDropKind) -> Int {
        switch kind {
        case .wuermchen:
            return 10
        case .wasserfloh:
            return 14
        case .algenkugel:
            return 18
        case .bonusblase:
            return 0
        case .saugglocke:
            return 0
        case .slowMotionPotion:
            return 0
        case .falseElumi:
            return 0
        }
    }

    func currentSpawnDelay() -> Double {
        let base = ArcadeRoundConfig(round: round).spawnDelay
        return hasActiveSlowMotion() ? base * 1.8 : base
    }

    func currentFallDuration() -> Double {
        ArcadeRoundConfig(round: round).fallDuration
    }

    func elumiPositionX(in width: CGFloat) -> CGFloat {
        let minX: CGFloat = 42
        let maxX = max(minX, width - 42)
        return minX + ((maxX - minX) * elumiX)
    }

    func elumiPositionY(in height: CGFloat) -> CGFloat {
        guard isBonusRound else { return height - 118 }
        let minY: CGFloat = 80
        let maxY = max(minY, height - 80)
        return minY + ((maxY - minY) * elumiY)
    }

    func updateElumiPosition(to x: CGFloat, width: CGFloat) {
        let minX: CGFloat = 42
        let maxX = max(minX, width - 42)
        let clampedX = min(max(x, minX), maxX)
        let normalized = (clampedX - minX) / max(maxX - minX, 1)
        elumiX = normalized
    }

    func updateElumiPosition2D(to point: CGPoint, in size: CGSize) {
        updateElumiPosition(to: point.x, width: size.width)
        let minY: CGFloat = 80
        let maxY = max(minY, size.height - 80)
        let clampedY = min(max(point.y, minY), maxY)
        elumiY = (clampedY - minY) / max(maxY - minY, 1)
    }

    func fishPosition(for fish: BonusFishState, at date: Date, in size: CGSize) -> CGPoint {
        let elapsed = date.timeIntervalSince(fish.spawnedAt)
        let progress = CGFloat(elapsed / fish.speed)

        let startX: CGFloat = fish.fromLeft ? -30 : size.width + 30
        let endX: CGFloat = fish.fromLeft ? size.width + 30 : -30
        let x = startX + (endX - startX) * progress

        let baseY = 80 + (size.height - 160) * fish.normalizedY
        let wobble = sin(elapsed * 5.0 + fish.wobblePhase) * 35
        let y = baseY + CGFloat(wobble)

        return CGPoint(x: x, y: y)
    }

    func snackProgress(for snack: ElumiArcadeSnackState, at date: Date) -> CGFloat {
        CGFloat(max(0, date.timeIntervalSince(snack.spawnedAt) / snack.fallDuration))
    }

    func snackPosition(for snack: ElumiArcadeSnackState, at date: Date, in size: CGSize) -> CGPoint {
        let progress = snackProgress(for: snack, at: date)
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        let topY: CGFloat = -28
        let bottomY = size.height - 144
        let baseY = topY + ((bottomY - topY) * progress)
        let motionOffset = arcadeMotionOffset(for: snack, at: date, in: size)

        let x: CGFloat
        if snack.wobbleAmplitude >= 0.08 {
            // Querschläger: bounce off screen edges using triangle wave
            let minX: CGFloat = 30
            let maxX = size.width - 30
            let range = maxX - minX
            let rawX = snack.laneX * size.width + sin(elapsed * snack.wobbleFrequency) * snack.wobbleAmplitude * size.width * 2
            // Reflect into [minX, maxX] range
            let normalized = ((rawX - minX) / range).truncatingRemainder(dividingBy: 2.0)
            let reflected = normalized < 0 ? -normalized : normalized
            x = minX + (reflected > 1 ? 2 - reflected : reflected) * range
        } else {
            // Normal snack: simple wobble
            let baseX = snack.laneX * size.width
            let wobble = sin(elapsed * snack.wobbleFrequency) * snack.wobbleAmplitude * size.width
            x = baseX + wobble
        }

        return CGPoint(x: x + motionOffset.width, y: baseY + motionOffset.height)
    }

    func arcadeMotionOffset(for snack: ElumiArcadeSnackState, at date: Date, in size: CGSize) -> CGSize {
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        switch snack.kind {
        case .wasserfloh:
            let horizontal = sin(elapsed * 4.8 + snack.motionPhase) * size.width * 0.035 * snack.renderScale
            let vertical = sin(elapsed * 6.2 + snack.motionPhase * 0.8) * 10 * snack.renderScale
            return CGSize(width: horizontal, height: vertical)
        case .wuermchen:
            let horizontal = sin(elapsed * 3.9 + snack.motionPhase) * size.width * 0.022 * snack.renderScale
            let vertical = sin(elapsed * 9.8 + snack.motionPhase * 1.3) * 6 * snack.renderScale
            return CGSize(width: horizontal, height: vertical)
        default:
            return .zero
        }
    }

    func arcadeScaleX(for snack: ElumiArcadeSnackState, at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        switch snack.kind {
        case .wasserfloh:
            let facing: CGFloat = cos(elapsed * 4.8 + snack.motionPhase) >= 0 ? -1 : 1
            let pulse = 0.96 + (0.06 * abs(sin(elapsed * 6.4 + snack.motionPhase)))
            return facing * pulse
        case .wuermchen:
            return 0.92 + (0.12 * ((sin(elapsed * 10.2 + snack.motionPhase) + 1) / 2))
        default:
            return 1
        }
    }

    func arcadeScaleY(for snack: ElumiArcadeSnackState, at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        switch snack.kind {
        case .wasserfloh:
            return 0.97 + (0.05 * abs(cos(elapsed * 5.3 + snack.motionPhase)))
        case .wuermchen:
            return 1.08 - (0.12 * ((sin(elapsed * 10.2 + snack.motionPhase) + 1) / 2))
        default:
            return 1
        }
    }

    func arcadeSnackTilt(for snack: ElumiArcadeSnackState, at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        switch snack.kind {
        case .wasserfloh:
            return sin(elapsed * 5.2 + snack.motionPhase) * 8
        case .wuermchen:
            return sin(elapsed * 10.8 + snack.motionPhase) * 14 + cos(elapsed * 3.6 + snack.motionPhase) * 4
        default:
            return 0
        }
    }

    func arcadeBubble(
        seed: CGFloat,
        size: CGFloat,
        drift: CGFloat,
        duration: Double,
        delay: Double,
        time: Double
    ) -> some View {
        let phase = positiveFraction((time - delay) / duration)
        let x = seed * gameSize.width + (sin(phase * .pi * 2) * drift)
        let y = gameSize.height + 30 - ((gameSize.height + 60) * phase)

        return Circle()
            .fill(Color.white.opacity(0.18))
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            )
            .position(x: x, y: y)
    }

    func positiveFraction(_ value: Double) -> CGFloat {
        let fraction = value.truncatingRemainder(dividingBy: 1)
        return CGFloat(fraction >= 0 ? fraction : fraction + 1)
    }
}

