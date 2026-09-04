import SwiftUI

struct SplashWormCrawler: View {
    struct WormPose {
        let locomotionPhase: CGFloat
        let blinkPhase: CGFloat
        let horizontalOffset: CGFloat
        let verticalDrift: CGFloat
        let compaction: CGFloat
        let greetingVisibility: CGFloat
        let turnDegrees: Double
        let turnScale: CGFloat
    }

    let size: CGFloat
    let travelWidth: CGFloat
    let crawlDuration: Double
    let leftToRight: Bool
    var greetingText: String? = nil
    var greetingPauseDuration: Double = 0
    var frontFacingGreeting = false
    var onGreetingStart: (() -> Void)? = nil

    private let locomotionDuration: Double = 0.65
    private let blinkDuration: Double = 3.5

    @State private var startDate = Date()
    @State private var didTriggerGreeting = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let pose = wormPose(at: context.date)
            let shouldTriggerGreeting = pose.greetingVisibility > 0.72

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.15))
                    .frame(
                        width: size * (1.44 - (pose.compaction * 0.18)),
                        height: size * (0.15 - (pose.compaction * 0.03))
                    )
                    .blur(radius: 1.5)
                    .offset(
                        x: pose.horizontalOffset - size * 0.72,
                        y: size * 0.42 + pose.verticalDrift * 0.2
                    )
                    .opacity(0.16 - (pose.compaction * 0.04))

                if let greetingText, pose.greetingVisibility > 0.02 {
                    wormGreetingBubble(text: greetingText, size: size)
                        .scaleEffect(0.9 + (pose.greetingVisibility * 0.1))
                        .opacity(pose.greetingVisibility)
                        .offset(
                            x: pose.horizontalOffset + (leftToRight ? size * 0.34 : -size * 0.34),
                            y: -size * 0.92
                        )
                }

                ZStack {
                    SplashWormIllustration(
                        size: size,
                        locomotionPhase: pose.locomotionPhase,
                        blinkPhase: pose.blinkPhase
                    )
                    .scaleEffect(
                        x: (leftToRight ? 1 : -1) * pose.turnScale,
                        y: 1 + (pose.greetingVisibility * 0.04),
                        anchor: .center
                    )
                    .rotation3DEffect(.degrees(pose.turnDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                    .rotationEffect(.degrees((leftToRight ? -5 : 5) * Double(pose.greetingVisibility)))
                    .opacity(frontFacingGreeting ? max(0, 1 - (pose.greetingVisibility * 1.35)) : 1)

                    if frontFacingGreeting {
                        SplashWormFrontGreetingIllustration(
                            size: size * 1.32,
                            blinkPhase: pose.blinkPhase
                        )
                        .scaleEffect(0.84 + (pose.greetingVisibility * 0.28))
                        .opacity(min(1, pose.greetingVisibility * 1.25))
                        .offset(y: -size * 0.08)
                    }
                }
                .offset(
                    x: pose.horizontalOffset,
                    y: pose.verticalDrift
                )
                .shadow(color: AppTheme.Colors.primary.opacity(0.18), radius: 10, x: 0, y: 6)
            }
            .onChange(of: shouldTriggerGreeting) { _, isActive in
                guard isActive, !didTriggerGreeting else { return }
                didTriggerGreeting = true
                onGreetingStart?()
            }
        }
        .frame(width: travelWidth + size * 3.6, height: size * 2.2)
        .onAppear {
            startDate = Date()
            didTriggerGreeting = false
        }
    }

    private func wormPose(at date: Date) -> WormPose {
        let elapsed = max(0, date.timeIntervalSince(startDate))
        let greetingEnabled =
            greetingPauseDuration > 0 &&
            (
                !(greetingText?.isEmpty ?? true) ||
                frontFacingGreeting ||
                onGreetingStart != nil
            )
        let greetingPauseStart = crawlDuration * 0.42
        let greetingPauseEnd = greetingPauseStart + (greetingEnabled ? greetingPauseDuration : 0)
        let totalDuration = crawlDuration + (greetingEnabled ? greetingPauseDuration : 0)
        let travelProgress: Double
        let locomotionElapsed: Double
        let greetingVisibility: CGFloat

        if greetingEnabled {
            if elapsed < greetingPauseStart {
                travelProgress = 0.5 * min(elapsed / max(greetingPauseStart, 0.001), 1)
                locomotionElapsed = elapsed
                greetingVisibility = 0
            } else if elapsed < greetingPauseEnd {
                travelProgress = 0.5
                locomotionElapsed = greetingPauseStart
                let fadeDuration = min(0.24, greetingPauseDuration * 0.22)
                let fadeIn = min(max((elapsed - greetingPauseStart) / max(fadeDuration, 0.001), 0), 1)
                let fadeOut = min(max((greetingPauseEnd - elapsed) / max(fadeDuration, 0.001), 0), 1)
                greetingVisibility = CGFloat(min(fadeIn, fadeOut))
            } else {
                let tailDuration = max(totalDuration - greetingPauseEnd, 0.001)
                travelProgress = 0.5 + (0.5 * min((elapsed - greetingPauseEnd) / tailDuration, 1))
                locomotionElapsed = greetingPauseStart + (elapsed - greetingPauseEnd)
                greetingVisibility = 0
            }
        } else {
            travelProgress = min(elapsed / crawlDuration, 1)
            locomotionElapsed = elapsed
            greetingVisibility = 0
        }

        let locomotionPhase = CGFloat((locomotionElapsed / locomotionDuration).truncatingRemainder(dividingBy: 1))
        let blinkPhase = CGFloat((locomotionElapsed / blinkDuration).truncatingRemainder(dividingBy: 1))
        let pathStartFactor: CGFloat = greetingEnabled ? -0.78 : -0.72
        let baseHorizontalOffset = (travelWidth * pathStartFactor) + (travelWidth * 1.56 * CGFloat(travelProgress))
        let horizontalOffset = leftToRight ? baseHorizontalOffset : -baseHorizontalOffset
        let verticalDrift = splashWormBob(for: locomotionPhase) * size * 0.18 * (1 - (greetingVisibility * 0.9))
        let compaction = splashWormCompaction(for: locomotionPhase)
        let turnDegrees = (leftToRight ? -58.0 : 58.0) * Double(greetingVisibility)
        let turnScale = 1 - (greetingVisibility * 0.16)

        return WormPose(
            locomotionPhase: locomotionPhase,
            blinkPhase: blinkPhase,
            horizontalOffset: horizontalOffset,
            verticalDrift: verticalDrift,
            compaction: compaction,
            greetingVisibility: greetingVisibility,
            turnDegrees: turnDegrees,
            turnScale: turnScale
        )
    }

    private func wormGreetingBubble(text: String, size: CGFloat) -> some View {
        VStack(spacing: -1) {
            Text(text)
                .font(.system(size: max(12, size * 0.82), weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.elumiMidnight)
                .padding(.horizontal, max(10, size * 0.42))
                .padding(.vertical, max(7, size * 0.24))
                .background(
                    Capsule()
                        .fill(AppTheme.Colors.elumiCream.opacity(0.96))
                )
                .overlay(
                    Capsule()
                        .stroke(AppTheme.Colors.elumiRose.opacity(0.36), lineWidth: 1)
                )

            SpeechBubbleTail()
                .fill(AppTheme.Colors.elumiCream.opacity(0.96))
                .frame(width: max(12, size * 0.34), height: max(8, size * 0.2))
                .overlay(
                    SpeechBubbleTail()
                        .stroke(AppTheme.Colors.elumiRose.opacity(0.24), lineWidth: 1)
                )
                .rotationEffect(.degrees(leftToRight ? -10 : 10))
                .offset(x: leftToRight ? size * 0.16 : -size * 0.16, y: -1)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 4)
    }

    private func splashWormCompaction(for phase: CGFloat) -> CGFloat {
        switch phase {
        case 0..<0.25:
            return phase / 0.25 * 0.72
        case 0.25..<0.5:
            return 0.72 + ((phase - 0.25) / 0.25 * 0.28)
        case 0.5..<0.75:
            return 1 - ((phase - 0.5) / 0.25 * 0.58)
        default:
            return max(0, 0.42 - ((phase - 0.75) / 0.25 * 0.42))
        }
    }

    private func splashWormBob(for phase: CGFloat) -> CGFloat {
        if phase < 0.25 {
            return -(phase / 0.25) * 0.9
        } else if phase < 0.75 {
            let normalized = (phase - 0.25) / 0.5
            return -0.9 + (normalized * 0.62)
        } else {
            return -0.28 + (((phase - 0.75) / 0.25) * 0.28)
        }
    }
}
