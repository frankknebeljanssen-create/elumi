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
            return CGFloat.random(in: 1.0...1.5)
        case .algenkugel:
            return 1.0
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
        let base = max(0.38, 1.05 - (Double(round - 1) * 0.13))
        return hasActiveSlowMotion() ? base * 1.8 : base
    }

    func currentFallDuration() -> Double {
        max(1.45, 4.2 - (Double(round - 1) * 0.4))
    }

    func elumiPositionX(in width: CGFloat) -> CGFloat {
        let minX: CGFloat = 42
        let maxX = max(minX, width - 42)
        return minX + ((maxX - minX) * elumiX)
    }

    func updateElumiPosition(to x: CGFloat, width: CGFloat) {
        let minX: CGFloat = 42
        let maxX = max(minX, width - 42)
        let clampedX = min(max(x, minX), maxX)
        let normalized = (clampedX - minX) / max(maxX - minX, 1)
        elumiX = normalized
    }

    func snackProgress(for snack: ElumiArcadeSnackState, at date: Date) -> CGFloat {
        CGFloat(max(0, date.timeIntervalSince(snack.spawnedAt) / snack.fallDuration))
    }

    func snackPosition(for snack: ElumiArcadeSnackState, at date: Date, in size: CGSize) -> CGPoint {
        let progress = snackProgress(for: snack, at: date)
        let baseX = snack.laneX * size.width
        let elapsed = date.timeIntervalSince(snack.spawnedAt)
        let wobble = sin(elapsed * snack.wobbleFrequency) * snack.wobbleAmplitude * size.width
        let topY: CGFloat = -28
        let bottomY = size.height - 144
        let baseY = topY + ((bottomY - topY) * progress)
        let motionOffset = arcadeMotionOffset(for: snack, at: date, in: size)

        return CGPoint(x: baseX + wobble + motionOffset.width, y: baseY + motionOffset.height)
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

