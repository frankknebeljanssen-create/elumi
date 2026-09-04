import SwiftUI

struct SplashWormFrontGreetingIllustration: View {
    let size: CGFloat
    let blinkPhase: CGFloat

    private var blinkScale: CGFloat {
        if blinkPhase > 0.9 && blinkPhase < 0.97 {
            let distance = abs(blinkPhase - 0.935) / 0.035
            return max(0.08, distance)
        }
        return 1
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: size * 0.92, height: size * 0.16)
                .blur(radius: 1.4)
                .offset(y: size * 0.46)

            Ellipse()
                .fill(AppTheme.Colors.elumiPink)
                .frame(width: size * 0.92, height: size * 1.02)
                .overlay(
                    Ellipse()
                        .fill(AppTheme.Colors.elumiRose.opacity(0.28))
                        .frame(width: size * 0.7, height: size * 0.8)
                        .offset(y: size * 0.05)
                )
                .overlay(
                    Ellipse()
                        .stroke(Color.black.opacity(0.14), lineWidth: max(1.4, size * 0.026))
                )

            Ellipse()
                .fill(Color.white.opacity(0.18))
                .frame(width: size * 0.42, height: size * 0.28)
                .offset(x: -size * 0.1, y: -size * 0.18)

            wormEye(offsetX: -size * 0.18, offsetY: -size * 0.04, blinkScale: blinkScale, pupilShift: -size * 0.012)
            wormEye(offsetX: size * 0.18, offsetY: -size * 0.04, blinkScale: blinkScale, pupilShift: size * 0.012)

            Ellipse()
                .fill(AppTheme.Colors.elumiBlush.opacity(0.74))
                .frame(width: size * 0.18, height: size * 0.1)
                .offset(x: -size * 0.28, y: size * 0.12)

            Ellipse()
                .fill(AppTheme.Colors.elumiBlush.opacity(0.74))
                .frame(width: size * 0.18, height: size * 0.1)
                .offset(x: size * 0.28, y: size * 0.12)

            Path { path in
                path.move(to: CGPoint(x: -size * 0.16, y: size * 0.14))
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.16, y: size * 0.14),
                    control: CGPoint(x: 0, y: size * 0.3)
                )
            }
            .stroke(AppTheme.Colors.elumiNavy, style: StrokeStyle(lineWidth: max(2.2, size * 0.035), lineCap: .round))

            frontAntenna(left: true, size: size)
            frontAntenna(left: false, size: size)
        }
        .frame(width: size * 1.1, height: size * 1.45)
        .drawingGroup()
    }

    @ViewBuilder
    private func wormEye(offsetX: CGFloat, offsetY: CGFloat, blinkScale: CGFloat, pupilShift: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: size * 0.24, height: size * 0.24 * blinkScale)
            Circle()
                .fill(AppTheme.Colors.elumiNavy)
                .frame(width: size * 0.12, height: size * 0.12 * blinkScale)
                .offset(x: pupilShift, y: size * 0.01)
            Circle()
                .fill(Color.white.opacity(0.94))
                .frame(width: size * 0.04, height: size * 0.04 * blinkScale)
                .offset(x: size * 0.03, y: -size * 0.035)
        }
        .offset(x: offsetX, y: offsetY)
    }

    @ViewBuilder
    private func frontAntenna(left: Bool, size: CGFloat) -> some View {
        let direction: CGFloat = left ? -1 : 1
        let tipColor = left ? AppTheme.Colors.elumiRose : AppTheme.Colors.elumiBlush

        Path { path in
            path.move(to: CGPoint(x: direction * size * 0.12, y: -size * 0.3))
            path.addQuadCurve(
                to: CGPoint(x: direction * size * 0.28, y: -size * 0.56),
                control: CGPoint(x: direction * size * 0.2, y: -size * 0.48)
            )
        }
        .stroke(tipColor, style: StrokeStyle(lineWidth: max(2.2, size * 0.028), lineCap: .round))
        .overlay(
            Circle()
                .fill(tipColor)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: direction * size * 0.28, y: -size * 0.56)
        )
    }
}

struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY * 0.36)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY),
            control: CGPoint(x: rect.maxX - rect.width * 0.34, y: rect.maxY * 0.36)
        )
        path.closeSubpath()
        return path
    }
}
