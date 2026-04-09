import SwiftUI

extension ElumiArcadeGameView {
    func suctionBeam(at date: Date, in size: CGSize) -> some View {
        let pulse = 0.94 + (0.08 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 9)))
        let topWidth = suctionBeamHalfWidth * 2.55 * pulse
        let bottomWidth = topWidth * 0.25
        let beamHeight = max(140, size.height - 146)
        let stripeShift = CGFloat(sin(date.timeIntervalSinceReferenceDate * 12)) * 10

        return ZStack {
            // Trapezoid shape: narrow at bottom (Elumi), wide at top
            TrapezoidShape(topWidth: topWidth, bottomWidth: bottomWidth)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.primary.opacity(0.14),
                            AppTheme.Colors.warning.opacity(0.22),
                            AppTheme.Colors.primary.opacity(0.08),
                            AppTheme.Colors.warning.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blur(radius: 3)

            TrapezoidShape(topWidth: topWidth * 0.85, bottomWidth: bottomWidth * 0.7)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            AppTheme.Colors.warning.opacity(0.12),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 14) {
                ForEach(0..<10, id: \.self) { index in
                    let rowProgress = CGFloat(index) / 9.0
                    let rowWidth = topWidth * (1.0 - rowProgress * 0.7)
                    Capsule()
                        .fill(Color.white.opacity(index.isMultiple(of: 2) ? 0.16 : 0.08))
                        .frame(width: rowWidth * (0.34 + (CGFloat(index % 3) * 0.08)), height: 2.5)
                        .offset(x: stripeShift * (index.isMultiple(of: 2) ? 1 : -1))
                }
            }

            TrapezoidShape(topWidth: topWidth, bottomWidth: bottomWidth)
                .stroke(AppTheme.Colors.warning.opacity(0.35), lineWidth: 1.8)
        }
        .frame(width: topWidth, height: beamHeight)
        .position(x: elumiPositionX(in: size.width), y: beamHeight / 2)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

}

private struct TrapezoidShape: Shape {
    let topWidth: CGFloat
    let bottomWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let centerX = rect.midX
        var path = Path()
        path.move(to: CGPoint(x: centerX - topWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: centerX + topWidth / 2, y: 0))
        path.addLine(to: CGPoint(x: centerX + bottomWidth / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: centerX - bottomWidth / 2, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension ElumiArcadeGameView {
    var startOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                ElumiArcadeCharacter(
                    mouthOpen: false,
                    scale: 1.04,
                    rotation: 0,
                    sparkleBurst: true
                )
                .frame(width: 128, height: 128)

                VStack(spacing: 8) {
                    Text("Elumi Arcade")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Zieh Elumi unten an den richtigen Ort und schnapp dir die Beute, bevor sie vorbeischwimmt.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                    Text("Saugglocke fangen = Saugstrahl. Anderen Elumi vorbeilassen.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.92))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 16) {
                    ElumiSnackIcon(.wuermchen, size: 34)
                    ElumiSnackIcon(.wasserfloh, size: 32)
                    ElumiSnackIcon(.algenkugel, size: 30)
                }
                .padding(.vertical, 4)

                Button {
                    startGame()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Tippen zum Start")
                            .font(AppTheme.Typography.button)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: 340)
            .background(AppTheme.Colors.surface.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 12)
            .padding(.horizontal, 24)
            .onTapGesture {
                startGame()
            }
        }
        .transition(.opacity)
    }

    var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.primary.opacity(0.16))
                        .frame(width: 92, height: 92)
                    ElumiSnackCluster(count: max(1, min(totalCaught, 3)), size: 38)
                }

                VStack(spacing: 8) {
                    Text(gameOverTitle)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    if didBeatHighScore {
                        Text("Neuer Highscore")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.warning)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.Colors.warning.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    Text(gameOverSubtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Text("Score \(score)")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.warning)

                HStack(spacing: 10) {
                    gameOverStat(title: "Highscore", value: "\(max(highScore, score))")
                    gameOverStat(title: "Bester Combo", value: "x\(max(bestCombo, comboCount))")
                    gameOverStat(title: "Gefressen", value: "\(totalCaught)")
                }

                HStack(spacing: 12) {
                    Button("Schließen") {
                        dismiss()
                    }
                    .buttonStyle(AppSecondaryButtonStyle())

                    Button("Nochmal") {
                        restartGame()
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
            .frame(maxWidth: 344)
            .background(AppTheme.Colors.surface.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .transition(.opacity)
    }

    func gameOverStat(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppTheme.Colors.secondarySurface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func comboBanner(text: String) -> some View {
        HStack(spacing: 8) {
            if comboCount >= 2 {
                ElumiSnackCluster(count: min(max(comboCount, 1), 3), size: 18)
            } else if text.contains("x2") {
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.white)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Color.white)
            }

            Text(text)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(arcadeBannerBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .scaleEffect(comboCount >= 3 ? 1.06 : 1)
        .shadow(color: arcadeBannerShadowColor, radius: comboCount >= 3 ? 18 : 12, x: 0, y: 7)
    }

    var arcadeBannerBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                arcadeBannerShadowColor.opacity(0.92),
                arcadeBannerShadowColor.opacity(comboCount >= 3 ? 0.72 : 0.84)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var arcadeBannerShadowColor: Color {
        if comboCount >= 3 {
            return AppTheme.Colors.success
        }
        if let comboBannerText, comboBannerText.contains("x2") {
            return AppTheme.Colors.warning
        }
        return AppTheme.Colors.primary
    }
}

