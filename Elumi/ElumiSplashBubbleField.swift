import SwiftUI

struct SplashRisingBubbleField: View {
    private struct BubbleSeed {
        let x: CGFloat
        let size: CGFloat
        let drift: CGFloat
        let duration: Double
        let delay: Double
        let opacity: Double
    }

    private let seeds: [BubbleSeed] = [
        BubbleSeed(x: 0.1, size: 8, drift: 10, duration: 4.2, delay: 0.0, opacity: 0.26),
        BubbleSeed(x: 0.18, size: 5, drift: -8, duration: 5.0, delay: 0.7, opacity: 0.18),
        BubbleSeed(x: 0.29, size: 12, drift: 14, duration: 5.6, delay: 1.1, opacity: 0.22),
        BubbleSeed(x: 0.41, size: 6, drift: 6, duration: 4.6, delay: 0.4, opacity: 0.2),
        BubbleSeed(x: 0.52, size: 10, drift: -10, duration: 5.4, delay: 1.8, opacity: 0.24),
        BubbleSeed(x: 0.64, size: 7, drift: 9, duration: 4.8, delay: 1.0, opacity: 0.17),
        BubbleSeed(x: 0.74, size: 11, drift: -12, duration: 5.8, delay: 0.2, opacity: 0.22),
        BubbleSeed(x: 0.86, size: 6, drift: 7, duration: 4.4, delay: 1.5, opacity: 0.16),
        BubbleSeed(x: 0.93, size: 9, drift: -6, duration: 5.2, delay: 0.9, opacity: 0.2)
    ]

    @State private var animate = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(seeds.enumerated()), id: \.offset) { index, seed in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(seed.opacity * 1.25),
                                    Color.white.opacity(seed.opacity * 0.36)
                                ],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: seed.size
                            )
                        )
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(seed.opacity * 0.48), lineWidth: 0.8)
                        }
                        .frame(width: seed.size, height: seed.size)
                        .position(
                            x: geometry.size.width * seed.x + (animate ? seed.drift : -seed.drift * 0.25),
                            y: animate
                                ? -seed.size * 2
                                : geometry.size.height + 40 + CGFloat(index * 22)
                        )
                        .blur(radius: seed.size > 9 ? 0.2 : 0)
                        .animation(
                            .linear(duration: seed.duration)
                                .repeatForever(autoreverses: false)
                                .delay(seed.delay),
                            value: animate
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !animate else { return }
            animate = true
        }
    }
}
