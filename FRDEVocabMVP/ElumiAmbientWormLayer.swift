import SwiftUI

private struct AmbientScreenWormPass {
    let size: CGFloat
    let verticalPosition: CGFloat
    let opacity: Double
    let duration: Double
    let delay: Double
    let leftToRight: Bool
    let isVisible: Bool

    static func random(for style: AppSectionStyle) -> AmbientScreenWormPass {
        let positions = verticalPositions(for: style)

        return AmbientScreenWormPass(
            size: CGFloat.random(in: 18...22),
            verticalPosition: positions.randomElement() ?? 0.84,
            opacity: Double.random(in: 0.5...0.68),
            duration: Double.random(in: 10.5...14.0),
            delay: Double.random(in: 0.8...3.0),
            leftToRight: Bool.random(),
            isVisible: Double.random(in: 0...1) < 0.72
        )
    }

    private static func verticalPositions(for style: AppSectionStyle) -> [CGFloat] {
        switch style {
        case .hearts:
            return [0.14, 0.18, 0.82, 0.87]
        case .lists:
            return [0.16, 0.22, 0.84, 0.89]
        case .scan:
            return [0.18, 0.24, 0.86, 0.9]
        case .lexicon:
            return [0.2, 0.86]
        case .home, .train, .trainNouns, .trainArticles, .trainVerbs, .trainVerbforms, .flashcards, .quiz, .accents:
            return [0.18, 0.84]
        }
    }
}

struct AmbientScreenWormLayer: View {
    let style: AppSectionStyle

    @State private var startDate = Date()
    @State private var pass = AmbientScreenWormPass.random(for: .home)

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startDate))
                let activeTime = elapsed - pass.delay
                let progress = min(max(activeTime / pass.duration, 0), 1)
                let wormTravelDistance = geometry.size.width + (pass.size * 3.2)
                let baseX = (-pass.size * 1.6) + (wormTravelDistance * progress)
                let travelX = pass.leftToRight ? baseX : geometry.size.width - baseX
                let locomotionPhase = CGFloat((max(activeTime, 0) / 0.7).truncatingRemainder(dividingBy: 1))
                let blinkPhase = CGFloat((max(activeTime, 0) / 3.8).truncatingRemainder(dividingBy: 1))
                let bob = sin(max(activeTime, 0) * 1.05) * pass.size * 0.12
                let isActive = pass.isVisible && activeTime >= 0 && progress < 1

                ZStack {
                    if isActive {
                        SplashWormIllustration(
                            size: pass.size,
                            locomotionPhase: locomotionPhase,
                            blinkPhase: blinkPhase
                        )
                        .scaleEffect(x: pass.leftToRight ? 1 : -1, y: 1, anchor: .center)
                        .opacity(pass.opacity)
                        .offset(
                            x: travelX,
                            y: (geometry.size.height * pass.verticalPosition) + bob
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startDate = Date()
            pass = AmbientScreenWormPass.random(for: style)
        }
    }
}
