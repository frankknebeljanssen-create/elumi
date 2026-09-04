import SwiftUI

struct SplashWaterflohSwimmer: View {
    private struct SwimPose {
        let time: Double
        let x: CGFloat
        let y: CGFloat
        let flipX: CGFloat
        let rotation: Double
    }

    let size: CGFloat
    let travelWidth: CGFloat

    private let duration: Double = 5.2
    private let legDuration: Double = 0.28
    private let antennaDuration: Double = 0.9
    private let bubbleDurations: [Double] = [1.6, 2.0, 1.8]
    private let poses: [SwimPose] = [
        SwimPose(time: 0.00, x: -0.46, y: 0.02, flipX: 1, rotation: -5),
        SwimPose(time: 0.12, x: -0.18, y: -0.22, flipX: 1, rotation: -12),
        SwimPose(time: 0.22, x: 0.10, y: -0.34, flipX: 1, rotation: 0),
        SwimPose(time: 0.25, x: 0.18, y: -0.31, flipX: -1, rotation: 0),
        SwimPose(time: 0.38, x: 0.42, y: -0.10, flipX: -1, rotation: 8),
        SwimPose(time: 0.48, x: 0.52, y: 0.14, flipX: -1, rotation: 5),
        SwimPose(time: 0.50, x: 0.53, y: 0.18, flipX: 1, rotation: 5),
        SwimPose(time: 0.62, x: 0.16, y: 0.34, flipX: 1, rotation: 3),
        SwimPose(time: 0.72, x: -0.16, y: 0.22, flipX: 1, rotation: -3),
        SwimPose(time: 0.75, x: -0.22, y: 0.19, flipX: -1, rotation: -3),
        SwimPose(time: 0.88, x: -0.40, y: -0.04, flipX: -1, rotation: -8),
        SwimPose(time: 0.97, x: -0.48, y: 0.03, flipX: -1, rotation: -5),
        SwimPose(time: 1.00, x: -0.46, y: 0.02, flipX: 1, rotation: -5)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let phase = positiveFraction(elapsed / duration)
            let pose = pose(at: phase)
            let bodyX = pose.x * travelWidth
            let bodyY = pose.y * size * 1.8
            let legPhase = positiveFraction(elapsed / legDuration)
            let antennaPhase = positiveFraction(elapsed / antennaDuration)
            let bubblePhases = bubbleDurations.enumerated().map { index, duration in
                positiveFraction((elapsed - (Double(index) * 0.5)) / duration)
            }

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.14))
                    .frame(width: size * 0.7, height: size * 0.12)
                    .blur(radius: 1.2)
                    .offset(
                        x: bodyX,
                        y: size * 0.38
                    )
                    .scaleEffect(
                        x: 0.84 + abs(pose.y) * 0.32,
                        y: 0.72 + max(0, pose.y) * 0.18
                    )

                SplashWaterflohIllustration(
                    size: size,
                    legPhase: legPhase,
                    antennaPhase: antennaPhase,
                    bubblePhases: bubblePhases
                )
                .scaleEffect(x: pose.flipX, y: 1)
                .rotationEffect(.degrees(pose.rotation))
                .offset(
                    x: bodyX,
                    y: bodyY
                )
                .shadow(color: AppTheme.Colors.success.opacity(0.24), radius: 10, x: 0, y: 5)
            }
        }
        .frame(width: travelWidth + size * 1.6, height: size * 2)
    }

    private func pose(at phase: Double) -> SwimPose {
        guard let first = poses.first, let last = poses.last else {
            return SwimPose(time: 0, x: 0, y: 0, flipX: 1, rotation: 0)
        }

        if phase <= first.time {
            return first
        }

        for index in 0..<(poses.count - 1) {
            let start = poses[index]
            let end = poses[index + 1]
            guard phase >= start.time, phase <= end.time else { continue }

            let localProgress = (phase - start.time) / max(end.time - start.time, 0.0001)
            return SwimPose(
                time: phase,
                x: interpolate(start.x, end.x, progress: localProgress),
                y: interpolate(start.y, end.y, progress: localProgress),
                flipX: localProgress < 0.5 ? start.flipX : end.flipX,
                rotation: interpolate(start.rotation, end.rotation, progress: localProgress)
            )
        }

        return last
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, progress: Double) -> CGFloat {
        start + (end - start) * progress
    }

    private func interpolate(_ start: Double, _ end: Double, progress: Double) -> Double {
        start + (end - start) * progress
    }

    private func positiveFraction(_ value: Double) -> Double {
        let fraction = value.truncatingRemainder(dividingBy: 1)
        return fraction >= 0 ? fraction : fraction + 1
    }
}

private struct SplashWaterflohIllustration: View {
    let size: CGFloat
    let legPhase: Double
    let antennaPhase: Double
    let bubblePhases: [Double]

    private let baseWidth: CGFloat = 80
    private let baseHeight: CGFloat = 90
    private let mintDark = Color(hex: "#1E9E87")

    var body: some View {
        let legL1 = alternatingAngle(phase: legPhase, amplitude: 28)
        let legL2 = alternatingAngle(phase: positiveFraction(legPhase + 0.25), amplitude: 22)
        let legL3 = alternatingAngle(phase: positiveFraction(legPhase + 0.5), amplitude: 28)
        let legR1 = alternatingAngle(phase: legPhase, amplitude: 22)
        let legR2 = alternatingAngle(phase: positiveFraction(legPhase + 0.25), amplitude: 28)
        let legR3 = alternatingAngle(phase: positiveFraction(legPhase + 0.5), amplitude: 22)
        let antennaAngle = alternatingAngle(phase: antennaPhase, from: -10, to: 18)

        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.25))
                .frame(width: 40, height: 12)
                .position(point(x: 2, y: 34))

            Ellipse()
                .fill(AppTheme.Colors.elumiMint)
                .frame(width: 42, height: 60)
                .position(point(x: 0, y: 0))

            Ellipse()
                .fill(Color.white.opacity(0.16))
                .frame(width: 26, height: 36)
                .position(point(x: -5, y: -10))

            antenna(base: CGPoint(x: -9, y: -28), tip: CGPoint(x: -22, y: -50), angle: antennaAngle, color: AppTheme.Colors.elumiMint, tipSize: 8)
            antenna(base: CGPoint(x: -6, y: -28), tip: CGPoint(x: -15, y: -50), angle: antennaAngle, color: mintDark, tipSize: 8)

            leg(base: CGPoint(x: -20, y: -6), tip: CGPoint(x: -36, y: 2), angle: legL1, lineWidth: 3, lineColor: AppTheme.Colors.elumiMint, tipColor: mintDark, tipRadius: 2.5)
            leg(base: CGPoint(x: -20, y: 4), tip: CGPoint(x: -36, y: 14), angle: legL2, lineWidth: 3, lineColor: AppTheme.Colors.elumiMint, tipColor: mintDark, tipRadius: 2.5)
            leg(base: CGPoint(x: -20, y: 14), tip: CGPoint(x: -36, y: 26), angle: legL3, lineWidth: 2.5, lineColor: AppTheme.Colors.elumiMint, tipColor: mintDark, tipRadius: 2)

            leg(base: CGPoint(x: 20, y: -6), tip: CGPoint(x: 36, y: 2), angle: legR1, lineWidth: 3, lineColor: AppTheme.Colors.elumiMint, tipColor: mintDark, tipRadius: 2.5)
            leg(base: CGPoint(x: 20, y: 4), tip: CGPoint(x: 36, y: 14), angle: legR2, lineWidth: 3, lineColor: AppTheme.Colors.elumiMint, tipColor: mintDark, tipRadius: 2.5)
            leg(base: CGPoint(x: 20, y: 14), tip: CGPoint(x: 36, y: 26), angle: legR3, lineWidth: 2.5, lineColor: AppTheme.Colors.elumiMint, tipColor: mintDark, tipRadius: 2)

            Path { path in
                path.move(to: point(x: 12, y: 26))
                path.addQuadCurve(to: point(x: 32, y: 22), control: point(x: 30, y: 32))
                path.addQuadCurve(to: point(x: 24, y: 8), control: point(x: 34, y: 12))
            }
            .stroke(mintDark, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))

            Circle()
                .fill(mintDark)
                .frame(width: 6, height: 6)
                .position(point(x: 32, y: 22))

            Circle()
                .fill(.white)
                .frame(width: 26, height: 26)
                .position(point(x: -7, y: -8))

            Circle()
                .fill(AppTheme.Colors.elumiNavy)
                .frame(width: 18, height: 18)
                .position(point(x: -8, y: -9))

            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
                .position(point(x: -5, y: -12))

            Circle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 4, height: 4)
                .position(point(x: -11, y: -4))

            Ellipse()
                .fill(Color.white.opacity(0.22))
                .frame(width: 12, height: 7)
                .position(point(x: -16, y: 4))

            if bubblePhases.indices.contains(0) {
                bubbleTrailBubble(base: CGPoint(x: 24, y: -6), phase: bubblePhases[0], radius: 3.5, opacity: 0.45)
            }
            if bubblePhases.indices.contains(1) {
                bubbleTrailBubble(base: CGPoint(x: 28, y: 4), phase: bubblePhases[1], radius: 2.5, opacity: 0.35)
            }
            if bubblePhases.indices.contains(2) {
                bubbleTrailBubble(base: CGPoint(x: 22, y: 14), phase: bubblePhases[2], radius: 2, opacity: 0.3)
            }
        }
        .frame(width: baseWidth, height: baseHeight)
        .drawingGroup()
        .scaleEffect(size / 52)
    }

    private func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: x + 40, y: y + 52)
    }

    private func positiveFraction(_ value: Double) -> Double {
        let fraction = value.truncatingRemainder(dividingBy: 1)
        return fraction >= 0 ? fraction : fraction + 1
    }

    private func alternatingAngle(phase: Double, amplitude: Double) -> Double {
        alternatingAngle(phase: phase, from: -amplitude, to: amplitude)
    }

    private func alternatingAngle(phase: Double, from: Double, to: Double) -> Double {
        let eased = 0.5 - 0.5 * cos(phase * .pi * 2)
        return from + ((to - from) * eased)
    }

    private func rotatedPoint(_ point: CGPoint, around pivot: CGPoint, angle degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        let translatedX = point.x - pivot.x
        let translatedY = point.y - pivot.y
        let rotatedX = translatedX * cos(radians) - translatedY * sin(radians)
        let rotatedY = translatedX * sin(radians) + translatedY * cos(radians)
        return CGPoint(x: pivot.x + rotatedX, y: pivot.y + rotatedY)
    }

    @ViewBuilder
    private func leg(
        base: CGPoint,
        tip: CGPoint,
        angle: Double,
        lineWidth: CGFloat,
        lineColor: Color,
        tipColor: Color,
        tipRadius: CGFloat
    ) -> some View {
        let rotatedTip = rotatedPoint(tip, around: base, angle: angle)

        ZStack {
            Path { path in
                path.move(to: point(x: base.x, y: base.y))
                path.addLine(to: point(x: rotatedTip.x, y: rotatedTip.y))
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            Circle()
                .fill(tipColor)
                .frame(width: tipRadius * 2, height: tipRadius * 2)
                .position(point(x: rotatedTip.x, y: rotatedTip.y))
        }
    }

    @ViewBuilder
    private func antenna(base: CGPoint, tip: CGPoint, angle: Double, color: Color, tipSize: CGFloat) -> some View {
        let rotatedTip = rotatedPoint(tip, around: base, angle: angle)

        ZStack {
            Path { path in
                path.move(to: point(x: base.x, y: base.y))
                path.addLine(to: point(x: rotatedTip.x, y: rotatedTip.y))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            Circle()
                .fill(color)
                .frame(width: tipSize, height: tipSize)
                .position(point(x: rotatedTip.x, y: rotatedTip.y))
        }
    }

    @ViewBuilder
    private func bubbleTrailBubble(base: CGPoint, phase: Double, radius: CGFloat, opacity: Double) -> some View {
        let progress = CGFloat(phase)
        Circle()
            .fill(Color.white.opacity(opacity * (1 - Double(progress))))
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(1 + progress * 0.5)
            .position(
                x: point(x: base.x + progress * 6, y: base.y - progress * 44).x,
                y: point(x: base.x + progress * 6, y: base.y - progress * 44).y
            )
    }
}
