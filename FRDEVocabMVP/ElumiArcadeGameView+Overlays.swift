import SwiftUI

extension ElumiArcadeGameView {
    func suctionBeam(at date: Date, in size: CGSize) -> some View {
        let pulse = 0.94 + (0.08 * CGFloat(sin(date.timeIntervalSinceReferenceDate * 9)))
        let topWidth = suctionBeamHalfWidth * 2.55 * pulse
        let bottomWidth = topWidth * 0.25
        let beamHeight = max(140, size.height - 146)
        let stripeShift = CGFloat(sin(date.timeIntervalSinceReferenceDate * 12)) * 10

        // Build up from Elumi, collapse back at end
        let rampDuration: TimeInterval = 0.4
        let beamProgress: CGFloat = {
            guard let suctionEndsAt else { return 0 }
            let startedAt = suctionEndsAt.addingTimeInterval(-suctionDuration)
            let elapsed = date.timeIntervalSince(startedAt)
            let remaining = suctionEndsAt.timeIntervalSince(date)
            let rampUp = min(elapsed / rampDuration, 1.0)
            let rampDown = min(remaining / rampDuration, 1.0)
            return CGFloat(max(0, min(rampUp, rampDown)))
        }()

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
        .scaleEffect(x: 1, y: beamProgress, anchor: .bottom)
        .opacity(Double(beamProgress))
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
    // Phase 4 – Game Screen Start-Overlay (Redesign):
    // Hierarchie klar: Credit-Status ist Hero → CTA ist Haupt-Aktion →
    // Regeln sind einklappbar und nehmen keine visuelle Priorität mehr.
    // Die Verbindung Lernen → Credits → Spiel wird explizit im Hero-Card
    // und (wenn leer) im Empty-State kommuniziert.
    var startOverlay: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Vertikale Zentrierung: ScrollView sitzt in einem VStack mit
            // flexiblen Spacern — so bleibt das Card vertikal in der Mitte,
            // selbst wenn die Regeln ausgeklappt werden. Bei sehr kleinen
            // Geräten kann der User trotzdem scrollen, falls nötig.
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        VStack(spacing: 16) {
                            ElumiArcadeCharacter(
                                mouthOpen: false,
                                scale: 1.04,
                                rotation: 0,
                                sparkleBurst: true
                            )
                            .frame(width: 64, height: 64)

                            Text("Elumi Spiel")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)

                            startCreditHeroCard

                            startCTASection

                            startRulesDisclosure
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 24)
                        .frame(maxWidth: 340)
                        .background(AppTheme.Colors.surface.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppTheme.Colors.cta.opacity(0.22), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 12)
                        .padding(.horizontal, 24)

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: geo.size.height)
                }
            }
        }
        .transition(.opacity)
    }

    /// Credit-Hero: großer Credit-Wert + Verbindung zum Lernsystem.
    /// Icon bewusst `circle.hexagongrid.fill` (gleiche Sprache wie in der
    /// Home-Balanced-Bar), damit der User „Credits" über alle Screens
    /// mit demselben Symbol wiedererkennt.
    var startCreditHeroCard: some View {
        let hasCredits = arcadeCredits >= ArcadeCreditSystem.gamesCost
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(hasCredits ? AppTheme.Colors.cta : AppTheme.Colors.textSecondary)

                Text("\(arcadeCredits)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()

                Text(arcadeCredits == 1 ? "Credit" : "Credits")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(hasCredits
                    ? "1 Runde kostet \(ArcadeCreditSystem.gamesCost) Credit"
                    : "Lernen bringt Credits — dann spielen")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    (hasCredits ? AppTheme.Colors.cta : AppTheme.Colors.border).opacity(hasCredits ? 0.35 : 1),
                    lineWidth: 1
                )
        )
    }

    /// CTA-Sektion: Haupt-Button „Spiel starten" (hat Credits) oder
    /// „Lernen starten" (keine Credits → führt zurück zum Home).
    var startCTASection: some View {
        let hasCredits = arcadeCredits >= ArcadeCreditSystem.gamesCost
        return VStack(spacing: 0) {
            if hasCredits {
                Button {
                    arcadeCredits -= ArcadeCreditSystem.gamesCost
                    startGame()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Spiel starten")
                            .font(AppTheme.Typography.button)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            } else {
                Button {
                    exitArcadeSilently()
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Lernen starten")
                            .font(AppTheme.Typography.button)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            }
        }
    }

    /// Regeln einklappbar — Platz nicht mehr durch Gameplay-Regeln dominiert.
    var startRulesDisclosure: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isShowingArcadeRules.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isShowingArcadeRules ? "Spielregeln ausblenden" : "Spielregeln anzeigen")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Image(systemName: isShowingArcadeRules ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 32)
            }
            .buttonStyle(.plain)

            if isShowingArcadeRules {
                arcadeRulesBlock
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Die alten Regel-Zeilen — gleicher Content, visuell entspannter (11/13pt,
    /// kleinere Icons, engere Line-Height), damit sie in der Disclosure nicht
    /// wieder den Raum dominieren.
    var arcadeRulesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Zieh Elumi zum Futter")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                ElumiSnackIcon(.wuermchen, size: 16)
                ElumiSnackIcon(.wasserfloh, size: 18)
                ElumiSnackIcon(.algenkugel, size: 16)
            }

            HStack(spacing: 6) {
                Text("4 Leben")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                ForEach(0..<4, id: \.self) { _ in
                    ArcadeElumiAvatar(size: 16, withShadow: false)
                }
            }

            Text("Verpasstes Futter = −1 Leben")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            HStack(spacing: 8) {
                ArcadeHazardElumiAvatar(size: 20)
                Text("Elumi-Freund fressen = −1 Leben")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.cyan)
            }

            Text("Bonus-Runde Fische fangen = +1 Extra Leben")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            HStack(spacing: 8) {
                ArcadeSuctionIconStandalone(size: 22)
                Text("Saugglocke: zieht Snacks heran")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            HStack(spacing: 8) {
                ArcadeSlowMotionIconStandalone(size: 22)
                Text("Zeitlupe-Trank: 5 Sek. Slow-Motion")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface.opacity(0.55))
        )
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

                    if !gameOverSubtitle.isEmpty {
                        Text(gameOverSubtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                VStack(spacing: 2) {
                    Text("Punkte")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text("\(score)")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.warning)
                        .shadow(color: AppTheme.Colors.warning.opacity(0.3), radius: 8, x: 0, y: 2)
                }

                HStack(spacing: 8) {
                    gameOverStat(title: "Runde", value: "\(round)")
                    gameOverStat(title: "Gefangen", value: "\(totalCaught)")
                    gameOverStat(title: "Verpasst", value: "\(misses)")
                    gameOverStat(title: "Highscore", value: "\(max(highScore, score))")
                }

                if arcadeCredits >= ArcadeCreditSystem.gamesCost {
                    HStack(spacing: 12) {
                        Button("Schließen") {
                            exitArcadeSilently()
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

                    // Credit-Rest im gleichen Icon-Vokabular wie Start-Overlay
                    // und Home-Balanced-Bar — konsistente Credit-Identität.
                    HStack(spacing: 5) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.cta.opacity(0.85))
                        Text("\(arcadeCredits) Credit\(arcadeCredits == 1 ? "" : "s") übrig")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                } else {
                    // Empty-State: klarer Call-zum-Lernen, nicht nur Schließen.
                    HStack(spacing: 6) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Text("0 Credits — Lernen bringt Credits")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .padding(.vertical, 4)

                    Button {
                        exitArcadeSilently()
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "book.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Lernen starten")
                                .font(AppTheme.Typography.button)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
            .frame(maxWidth: 344)
            .background(AppTheme.Colors.surface.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    var bonusRoundAnnouncement: some View {
        VStack(spacing: 14) {
            Text("🐟")
                .font(.system(size: 48))

            Text("Bonus-Runde!")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 6) {
                Text("Fische fliegen vorbei —")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text("fang 80% für ein Extra-Leben!")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
            }

            HStack(spacing: 6) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("Zieh Elumi frei über den Screen")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.7))
            .padding(.top, 4)

            Text("▶  Tippen zum Starten")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.Colors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1.5)
                )
        )
        .shadow(color: .cyan.opacity(0.2), radius: 20, x: 0, y: 8)
    }

    var bonusRoundResult: some View {
        VStack(spacing: 14) {
            if let result = bonusRoundResultText {
                Text(result.contains("+1") ? "🎉" : "🐟")
                    .font(.system(size: 48))

                Text(result)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(result.contains("+1") ? .cyan : .white)
                    .multilineTextAlignment(.center)
            }

            Text("▶  Weiterspielen")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.Colors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1.5)
                )
        )
        .shadow(color: .cyan.opacity(0.2), radius: 20, x: 0, y: 8)
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func arcadeRuleRow(icon: String, text: String, tint: Color? = nil, iconSize: CGFloat = 14) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(tint ?? AppTheme.Colors.textSecondary)
                .frame(width: 26)

            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? AppTheme.Colors.textPrimary)
        }
    }
}

