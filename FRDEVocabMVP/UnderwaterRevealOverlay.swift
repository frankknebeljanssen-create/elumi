import SwiftUI

struct UnderwaterRevealOverlay: View {
    let progress: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            GeometryReader { geometry in
                ZStack {
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.elumiMint.opacity(0.16 * progress),
                            AppTheme.Colors.background.opacity(0.2 * progress),
                            AppTheme.Colors.elumiCream.opacity(0.08 * progress)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    Ellipse()
                        .fill(AppTheme.Colors.elumiMint.opacity(0.08 * progress))
                        .frame(width: geometry.size.width * 0.92, height: geometry.size.height * 0.22)
                        .blur(radius: 26)
                        .offset(
                            x: sin(time * 0.65) * geometry.size.width * 0.08,
                            y: -geometry.size.height * 0.16
                        )

                    Ellipse()
                        .fill(Color.white.opacity(0.06 * progress))
                        .frame(width: geometry.size.width * 0.78, height: geometry.size.height * 0.16)
                        .blur(radius: 22)
                        .offset(
                            x: cos(time * 0.52) * geometry.size.width * 0.09,
                            y: geometry.size.height * 0.08
                        )

                    ForEach(0..<3, id: \.self) { index in
                        let rippleProgress = CGFloat(((time * (0.18 + Double(index) * 0.03)) + Double(index) * 0.19).truncatingRemainder(dividingBy: 1))
                        Circle()
                            .stroke(
                                Color.white.opacity((0.16 - Double(index) * 0.03) * progress * (1 - Double(rippleProgress))),
                                lineWidth: 1.8 - CGFloat(index) * 0.25
                            )
                            .frame(
                                width: geometry.size.width * (0.16 + rippleProgress * 0.72),
                                height: geometry.size.width * (0.04 + rippleProgress * 0.18)
                            )
                            .position(
                                x: geometry.size.width * (0.28 + CGFloat(index) * 0.22),
                                y: geometry.size.height * (0.26 + CGFloat(index) * 0.14)
                            )
                            .blur(radius: 0.8 + rippleProgress * 1.8)
                    }

                    ForEach(0..<4, id: \.self) { index in
                        Path { path in
                            let baseY = geometry.size.height * (0.22 + CGFloat(index) * 0.18)
                            let amplitude = (14 + CGFloat(index) * 4) * progress
                            let waveLength = geometry.size.width / (1.2 + CGFloat(index) * 0.16)
                            let phaseShift = time * (1.55 + Double(index) * 0.28)

                            path.move(to: CGPoint(x: 0, y: baseY))
                            var x: CGFloat = 0
                            while x <= geometry.size.width + 4 {
                                let y = baseY + sin((x / waveLength) * .pi * 2 + phaseShift) * amplitude
                                path.addLine(to: CGPoint(x: x, y: y))
                                x += 8
                            }
                        }
                        .stroke(
                            index.isMultiple(of: 2)
                                ? AppTheme.Colors.elumiMint.opacity(0.22 * progress)
                                : Color.white.opacity(0.14 * progress),
                            style: StrokeStyle(lineWidth: 1.5 + CGFloat(index) * 0.22, lineCap: .round)
                        )
                        .blur(radius: 1.2 + progress * 2.3)
                    }

                    ForEach(0..<9, id: \.self) { index in
                        let bubbleProgress = CGFloat(((time * (0.16 + Double(index) * 0.018)) + Double(index) * 0.14).truncatingRemainder(dividingBy: 1))
                        Circle()
                            .fill(Color.white.opacity((0.07 - Double(index) * 0.004) * progress))
                            .frame(width: 4 + CGFloat(index % 3) * 2, height: 4 + CGFloat(index % 3) * 2)
                            .position(
                                x: geometry.size.width * (0.08 + CGFloat(index) * 0.1),
                                y: geometry.size.height * (0.9 - bubbleProgress * 0.95)
                            )
                            .blur(radius: 0.6)
                    }
                }
                .blendMode(.screen)
                .ignoresSafeArea()
                .opacity(progress)
            }
        }
        .allowsHitTesting(false)
    }
}
