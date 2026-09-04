import SwiftUI

struct SplashWormIllustration: View {
    let size: CGFloat
    let locomotionPhase: CGFloat
    let blinkPhase: CGFloat

    private let baseWidth: CGFloat = 220
    private let baseHeight: CGFloat = 96
    private let baseY: CGFloat = 45
    private let headX: CGFloat = 178

    var body: some View {
        let compaction = wormCompaction
        let blinkScale = wormBlinkScale
        let stretch = 1 - (compaction * 0.19)
        let wiggle = sin(locomotionPhase * .pi * 2)
        let leftAntennaBase = CGPoint(x: 186, y: 26)
        let leftAntennaTip = CGPoint(x: 180 + (wiggle * 2.8), y: 11 - abs(wiggle) * 1.4)
        let rightAntennaBase = CGPoint(x: 198, y: 26)
        let rightAntennaTip = CGPoint(x: 207 - (wiggle * 2.2), y: 12 - abs(wiggle) * 1.1)

        ZStack {
            Path { path in
                let smileStart = CGPoint(x: 184, y: 49)
                path.move(to: smileStart)
                path.addQuadCurve(
                    to: CGPoint(x: 199, y: 50),
                    control: CGPoint(x: 191.5, y: 58)
                )
            }
            .stroke(AppTheme.Colors.elumiNavy, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            Path { path in
                path.addPath(wormBodyPath(stretch: stretch, compaction: compaction))
            }
            .stroke(Color.black.opacity(0.22), style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
            .offset(x: 1.2, y: 4)

            Path { path in
                path.addPath(wormBodyPath(stretch: stretch, compaction: compaction))
            }
            .stroke(AppTheme.Colors.elumiPink, style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))

            Path { path in
                path.addPath(wormBodyPath(stretch: stretch, compaction: compaction))
            }
            .stroke(
                AppTheme.Colors.elumiRose,
                style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round, dash: [9, 18], dashPhase: -26 * compaction)
            )

            Path { path in
                path.addPath(wormHighlightPath(stretch: stretch, compaction: compaction))
            }
            .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

            Circle()
                .fill(AppTheme.Colors.elumiPink)
                .frame(width: 22, height: 22)
                .position(x: 170, y: baseY)

            Circle()
                .fill(AppTheme.Colors.elumiPink)
                .frame(width: 36, height: 36)
                .position(x: 193, y: baseY - 1)

            Ellipse()
                .fill(Color.white.opacity(0.13))
                .frame(width: 20, height: 16)
                .position(x: 188, y: baseY - 10)

            Circle()
                .fill(.white)
                .frame(width: 20, height: 20 * blinkScale)
                .position(x: 193, y: baseY - 9)

            Circle()
                .fill(AppTheme.Colors.elumiNavy)
                .frame(width: 13, height: 13 * blinkScale)
                .position(x: 195.5, y: baseY - 10)

            Circle()
                .fill(.white)
                .frame(width: 4.8, height: 4.8 * blinkScale)
                .position(x: 198.5, y: baseY - 12.3)

            Circle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 2.6, height: 2.6 * blinkScale)
                .position(x: 191.5, y: baseY - 6)

            Ellipse()
                .fill(AppTheme.Colors.elumiBlush.opacity(0.68))
                .frame(width: 13, height: 7)
                .position(x: 204, y: baseY + 6)

            Group {
                Path { path in
                    path.move(to: leftAntennaBase)
                    path.addQuadCurve(
                        to: leftAntennaTip,
                        control: CGPoint(
                            x: (leftAntennaBase.x + leftAntennaTip.x) * 0.5 - 1.5,
                            y: (leftAntennaBase.y + leftAntennaTip.y) * 0.5 - 2.2
                        )
                    )
                }
                .stroke(AppTheme.Colors.elumiRose, style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
                Circle()
                    .fill(AppTheme.Colors.elumiRose)
                    .frame(width: 8.6, height: 8.6)
                    .position(x: leftAntennaTip.x - 0.6, y: leftAntennaTip.y - 1.4)
            }

            Group {
                Path { path in
                    path.move(to: rightAntennaBase)
                    path.addQuadCurve(
                        to: rightAntennaTip,
                        control: CGPoint(
                            x: (rightAntennaBase.x + rightAntennaTip.x) * 0.5 + 1.4,
                            y: (rightAntennaBase.y + rightAntennaTip.y) * 0.5 - 2.0
                        )
                    )
                }
                .stroke(AppTheme.Colors.elumiBlush, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                Circle()
                    .fill(AppTheme.Colors.elumiBlush)
                    .frame(width: 7.8, height: 7.8)
                    .position(x: rightAntennaTip.x + 0.5, y: rightAntennaTip.y - 1.3)
            }
        }
        .frame(width: baseWidth, height: baseHeight)
        .drawingGroup()
        .scaleEffect(size / 58)
    }

    private var wormCompaction: CGFloat {
        switch locomotionPhase {
        case 0..<0.25:
            return locomotionPhase / 0.25 * 0.72
        case 0.25..<0.5:
            return 0.72 + ((locomotionPhase - 0.25) / 0.25 * 0.28)
        case 0.5..<0.75:
            return 1 - ((locomotionPhase - 0.5) / 0.25 * 0.58)
        default:
            return max(0, 0.42 - ((locomotionPhase - 0.75) / 0.25 * 0.42))
        }
    }

    private var wormBlinkScale: CGFloat {
        if blinkPhase > 0.9 && blinkPhase < 0.97 {
            let distance = abs(blinkPhase - 0.935) / 0.035
            return max(0.07, distance)
        }
        return 1
    }

    private func wormBodyPath(stretch: CGFloat, compaction: CGFloat) -> Path {
        let xOffsets: [CGFloat] = [0, 34, 64, 96, 126, 160]
        let yOffsets: [CGFloat] = [
            0,
            -19 * compaction,
            -8 * compaction,
            15 * compaction,
            10 * compaction,
            0
        ]

        let points = zip(xOffsets, yOffsets).map { xOffset, yOffset in
            CGPoint(x: headX - (xOffset * stretch), y: baseY + yOffset)
        }

        var path = Path()
        path.move(to: points[0])

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let controlX = (previous.x + current.x) * 0.5
            path.addCurve(
                to: current,
                control1: CGPoint(x: controlX, y: previous.y),
                control2: CGPoint(x: controlX, y: current.y)
            )
        }

        return path
    }

    private func wormHighlightPath(stretch: CGFloat, compaction: CGFloat) -> Path {
        let xOffsets: [CGFloat] = [0, 34, 64, 96, 126]
        let yOffsets: [CGFloat] = [
            -4,
            (-4) - (10 * compaction),
            (-4) - (5 * compaction),
            (-3) + (8 * compaction),
            (-4) + (4 * compaction)
        ]

        let points = zip(xOffsets, yOffsets).map { xOffset, yOffset in
            CGPoint(x: headX - (xOffset * stretch), y: baseY + yOffset)
        }

        var path = Path()
        path.move(to: points[0])

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let controlX = (previous.x + current.x) * 0.5
            path.addCurve(
                to: current,
                control1: CGPoint(x: controlX, y: previous.y),
                control2: CGPoint(x: controlX, y: current.y)
            )
        }

        return path
    }
}
