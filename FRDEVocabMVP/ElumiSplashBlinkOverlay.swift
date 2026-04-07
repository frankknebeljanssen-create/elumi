import SwiftUI

struct SplashCharacterBlinkOverlay: View {
    private struct EyeSpec {
        let x: CGFloat
        let y: CGFloat
        let diameter: CGFloat
    }

    let size: CGFloat
    let startDate: Date

    private let faceColor = Color(red: 0.966, green: 0.631, blue: 0.694)

    private var eyeSpecs: [EyeSpec] {
        [
            EyeSpec(x: size * 0.334, y: size * 0.513, diameter: size * 0.305),
            EyeSpec(x: size * 0.666, y: size * 0.513, diameter: size * 0.305)
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let blinkAmount = max(
                blinkEnvelope(elapsed: elapsed, center: 1.35, halfWidth: 0.16),
                blinkEnvelope(elapsed: elapsed, center: 3.15, halfWidth: 0.17)
            )

            ZStack {
                ForEach(Array(eyeSpecs.enumerated()), id: \.offset) { _, eye in
                    eyelid(for: eye, amount: blinkAmount)
                }
            }
            .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func eyelid(for eye: EyeSpec, amount: CGFloat) -> some View {
        let topHeight = eye.diameter * min(0.6, amount * 0.62)
        let bottomHeight = eye.diameter * min(0.46, amount * 0.44)
        let lidLineHeight = max(size * 0.008, eye.diameter * 0.055 * amount)
        let lidLineOffset = ((-eye.diameter / 2) + topHeight + (eye.diameter / 2) - bottomHeight) / 2

        ZStack {
            eyelidSegment(diameter: eye.diameter, visibleHeight: topHeight, fromTop: true)
            eyelidSegment(diameter: eye.diameter, visibleHeight: bottomHeight, fromTop: false)

            Capsule()
                .fill(AppTheme.Colors.elumiNavy.opacity(0.96))
                .frame(width: eye.diameter * 0.8, height: lidLineHeight)
                .offset(y: lidLineOffset)
        }
        .frame(width: eye.diameter, height: eye.diameter)
        .position(x: eye.x, y: eye.y)
        .opacity(amount > 0.015 ? 1 : 0)
    }

    private func eyelidSegment(diameter: CGFloat, visibleHeight: CGFloat, fromTop: Bool) -> some View {
        Circle()
            .fill(faceColor)
            .frame(width: diameter, height: diameter)
            .mask {
                Rectangle()
                    .frame(width: diameter, height: max(1, visibleHeight))
                    .offset(y: fromTop ? -(diameter - visibleHeight) / 2 : (diameter - visibleHeight) / 2)
            }
    }

    private func blinkEnvelope(elapsed: TimeInterval, center: TimeInterval, halfWidth: TimeInterval) -> CGFloat {
        let distance = abs(elapsed - center)
        guard distance < halfWidth else { return 0 }
        let normalized = 1 - (distance / halfWidth)
        return CGFloat(sin(normalized * .pi))
    }
}
