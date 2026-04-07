import SwiftUI

struct SplashAlgenkugelRoller: View {
    let size: CGFloat
    let travelWidth: CGFloat

    private let duration: Double = 6.0
    private let mintLight = Color(hex: "#3DD4B9")
    private let green = Color(hex: "#23A06A")
    private let tentacleDark = Color(hex: "#149B85")
    private let tentacleLight = Color(hex: "#39D2BA")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = positiveFraction(context.date.timeIntervalSinceReferenceDate / duration)
            let fullTravelWidth = travelWidth + (size * 1.8)
            let x = (fullTravelWidth * 0.5) - (fullTravelWidth * CGFloat(phase))
            let rotation = -720 * phase
            let sway1 = sin(context.date.timeIntervalSinceReferenceDate * 2.7)
            let sway2 = sin(context.date.timeIntervalSinceReferenceDate * 2.1 + 0.8)
            let sway3 = sin(context.date.timeIntervalSinceReferenceDate * 2.45 + 1.4)
            let tentacleSway = sin(context.date.timeIntervalSinceReferenceDate * 2.6)
            let tentacleSwaySecondary = sin(context.date.timeIntervalSinceReferenceDate * 2.15 + 0.9)
            let shadowStretch = 1 + (sin(phase * .pi * 2) * 0.035)

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: size * 0.68 * shadowStretch, height: size * 0.14)
                    .blur(radius: 1.3)
                    .offset(x: x, y: size * 0.38)

                ZStack {
                    ZStack {
                        algenTentacle(
                            startX: size * 0.26,
                            baseY: size * 0.82,
                            controlX: size * (0.15 + tentacleSway * 0.03),
                            controlY: size * 1.02,
                            endX: size * (0.18 + tentacleSway * 0.05),
                            endY: size * 1.22,
                            color: tentacleDark,
                            lineWidth: size * 0.05
                        )

                        algenTentacle(
                            startX: size * 0.41,
                            baseY: size * 0.85,
                            controlX: size * (0.36 + tentacleSwaySecondary * 0.04),
                            controlY: size * 1.04,
                            endX: size * (0.33 + tentacleSwaySecondary * 0.06),
                            endY: size * 1.27,
                            color: tentacleLight.opacity(0.95),
                            lineWidth: size * 0.046
                        )

                        algenTentacle(
                            startX: size * 0.58,
                            baseY: size * 0.84,
                            controlX: size * (0.64 - tentacleSway * 0.04),
                            controlY: size * 1.03,
                            endX: size * (0.68 - tentacleSway * 0.06),
                            endY: size * 1.24,
                            color: tentacleDark.opacity(0.92),
                            lineWidth: size * 0.048
                        )

                        algenTentacle(
                            startX: size * 0.74,
                            baseY: size * 0.8,
                            controlX: size * (0.82 - tentacleSwaySecondary * 0.035),
                            controlY: size * 1.0,
                            endX: size * (0.86 - tentacleSwaySecondary * 0.055),
                            endY: size * 1.19,
                            color: tentacleLight.opacity(0.88),
                            lineWidth: size * 0.042
                        )
                    }
                    .offset(y: size * 0.03)

                    Circle()
                        .fill(green)
                        .frame(width: size, height: size)

                    ZStack {
                        Path { path in
                            path.move(to: CGPoint(x: size * 0.18, y: size * 0.1))
                            path.addQuadCurve(
                                to: CGPoint(x: size * 0.18, y: size * 0.9),
                                control: CGPoint(x: 0, y: size * (0.5 + sway1 * 0.06))
                            )
                        }
                        .stroke(AppTheme.Colors.elumiMint.opacity(0.85), style: StrokeStyle(lineWidth: size * 0.062, lineCap: .round))

                        Path { path in
                            path.move(to: CGPoint(x: size * 0.44, y: size * 0.06))
                            path.addQuadCurve(
                                to: CGPoint(x: size * 0.47, y: size * 0.94),
                                control: CGPoint(x: size * 0.62, y: size * (0.5 + sway2 * 0.06))
                            )
                        }
                        .stroke(mintLight.opacity(0.75), style: StrokeStyle(lineWidth: size * 0.062, lineCap: .round))

                        Path { path in
                            path.move(to: CGPoint(x: size * 0.7, y: size * 0.1))
                            path.addQuadCurve(
                                to: CGPoint(x: size * 0.74, y: size * 0.9),
                                control: CGPoint(x: size * 0.9, y: size * (0.5 + sway3 * 0.06))
                            )
                        }
                        .stroke(AppTheme.Colors.elumiMint.opacity(0.75), style: StrokeStyle(lineWidth: size * 0.062, lineCap: .round))

                        Path { path in
                            path.move(to: CGPoint(x: size * 0.88, y: size * 0.18))
                            path.addQuadCurve(
                                to: CGPoint(x: size * 0.84, y: size * 0.9),
                                control: CGPoint(x: size, y: size * 0.52)
                            )
                        }
                        .stroke(mintLight.opacity(0.6), style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .rotationEffect(.degrees(rotation))

                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: size * 0.41, height: size * 0.41)
                        .offset(x: -size * 0.2, y: -size * 0.22)

                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: size * 0.22, height: size * 0.22)
                        .offset(x: -size * 0.28, y: -size * 0.3)

                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: size * 0.1, height: size * 0.1)
                        .offset(x: -size * 0.12, y: -size * 0.38)

                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: size * 0.024)
                        .frame(width: size, height: size)
                }
                .frame(width: size, height: size)
                .offset(x: x)
            }
        }
        .frame(width: travelWidth + size * 2.2, height: size * 1.95)
    }

    private func positiveFraction(_ value: Double) -> Double {
        let fraction = value.truncatingRemainder(dividingBy: 1)
        return fraction >= 0 ? fraction : fraction + 1
    }

    private func algenTentacle(
        startX: CGFloat,
        baseY: CGFloat,
        controlX: CGFloat,
        controlY: CGFloat,
        endX: CGFloat,
        endY: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) -> some View {
        Path { path in
            path.move(to: CGPoint(x: startX, y: baseY))
            path.addQuadCurve(
                to: CGPoint(x: endX, y: endY),
                control: CGPoint(x: controlX, y: controlY)
            )
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size * 1.42)
    }
}
