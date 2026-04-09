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

            VStack(spacing: 14) {
                ElumiArcadeCharacter(
                    mouthOpen: false,
                    scale: 1.04,
                    rotation: 0,
                    sparkleBurst: true
                )
                .frame(width: 64, height: 64)

                Text("Elumi Arcade")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    arcadeRuleRow(icon: "hand.draw.fill", text: "Zieh Elumi zum Futter")
                    arcadeRuleRow(icon: "heart.fill", text: "3 Leben — verpasstes Futter = -1")
                    arcadeRuleRow(icon: "xmark.octagon.fill", text: "Falscher Elumi = Game Over", tint: AppTheme.Colors.error)
                    arcadeRuleRow(icon: "bolt.fill", text: "Runden werden schneller")
                }
                .padding(.horizontal, 4)

                HStack(spacing: 16) {
                    ElumiSnackIcon(.wuermchen, size: 24)
                    ElumiSnackIcon(.wasserfloh, size: 22)
                    ElumiSnackIcon(.algenkugel, size: 20)
                }

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.warning)
                    Text("\(arcadeCredits) Credit\(arcadeCredits == 1 ? "" : "s")")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.warning)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.Colors.warning.opacity(0.14))
                .clipShape(Capsule())

                if arcadeCredits >= ArcadeCreditSystem.gamesCost {
                    Button {
                        arcadeCredits -= ArcadeCreditSystem.gamesCost
                        startGame()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Los geht's!")
                                .font(AppTheme.Typography.button)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                } else {
                    VStack(spacing: 6) {
                        Text("Keine Credits")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Text("Erst lernen, dann spielen!")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(AppTheme.Colors.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                }
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
            .offset(y: 30)
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

                Text("\(score)")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .shadow(color: AppTheme.Colors.warning.opacity(0.3), radius: 8, x: 0, y: 2)

                HStack(spacing: 8) {
                    gameOverStat(title: "Runde", value: "\(round)")
                    gameOverStat(title: "Gefangen", value: "\(totalCaught)")
                    gameOverStat(title: "Verpasst", value: "\(misses)")
                    gameOverStat(title: "Highscore", value: "\(max(highScore, score))")
                }

                if arcadeCredits >= ArcadeCreditSystem.gamesCost {
                    HStack(spacing: 12) {
                        Button("Schließen") {
                            dismiss()
                        }
                        .buttonStyle(AppSecondaryButtonStyle())

                        Button {
                            arcadeCredits -= ArcadeCreditSystem.gamesCost
                            restartGame()
                        } label: {
                            Text("Nochmal")
                        }
                        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                    }

                    Text("\(arcadeCredits) Credit\(arcadeCredits == 1 ? "" : "s") übrig")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                } else {
                    Text("Keine Credits mehr — erst lernen!")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.warning)
                        .padding(.vertical, 4)

                    Button("Schließen") {
                        dismiss()
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

    var roundCompleteBanner: some View {
        VStack(spacing: 12) {
            if roundBannerPhase == 0 {
                Text("Runde \(round) geschafft!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .transition(.opacity)
            } else {
                Text("Runde \(round)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .transition(.opacity)

                Text(roundSubtitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text("Ready?")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .opacity(readyBlinkVisible ? 1 : 0)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: roundBannerPhase)
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(AppTheme.Colors.surface.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.Colors.warning.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: AppTheme.Colors.warning.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    func arcadeLegendRow<Icon: View>(icon: () -> Icon, label: String, detail: String, tint: Color? = nil) -> some View {
        HStack(spacing: 12) {
            icon()
                .frame(width: 32, height: 32)

            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Spacer(minLength: 0)

            Text(detail)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(tint ?? AppTheme.Colors.warning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppTheme.Colors.secondarySurface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func arcadeRuleRow(icon: String, text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint ?? AppTheme.Colors.textSecondary)
                .frame(width: 22)

            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? AppTheme.Colors.textPrimary)
        }
    }
}

