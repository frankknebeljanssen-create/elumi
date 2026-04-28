import SwiftUI

extension ElumiArcadeGameView {
    func suctionBeam(at date: Date, in size: CGSize) -> some View {
        // **Unified-PowerUp-Palette** (User-Spec): Sauger bekommt die
        // offizielle Vacuum-Farbfamilie #A78BFA/#E9D5FF/#C4B5FD —
        // signalisiert „magnetisch, besonders, leicht technisch" und
        // hebt den Sauger visuell klar von der Schutz-Bubble (blau-
        // türkis) ab. Vorher war der Beam gemischt primary/warning
        // (gelb-blau), was nicht zum einheitlichen System passte.
        let cfg = ArcadePowerUps.config(for: .vacuum)
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
            // Trapezoid shape: narrow at bottom (Elumi), wide at top.
            // Primary → Secondary-Gradient für den magnetisch-lichten
            // Look.
            TrapezoidShape(topWidth: topWidth, bottomWidth: bottomWidth)
                .fill(
                    LinearGradient(
                        colors: [
                            cfg.primaryColor.opacity(0.18),
                            cfg.accentColor.opacity(0.25),
                            cfg.primaryColor.opacity(0.10),
                            cfg.secondaryColor.opacity(0.06)
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
                            cfg.accentColor.opacity(0.14),
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

            // **Sog-Wellen** (User-Spec „horizontale, leicht gebogene
            // Wellenlinien, bewegen sich Richtung Sauger"): konzentrisch
            // nach OBEN (Richtung Elumi) animierte Wellen, damit das
            // Auge sofort die Fließrichtung liest.
            suctionWavesOverlay(
                accent: cfg.accentColor,
                topWidth: topWidth,
                bottomWidth: bottomWidth,
                beamHeight: beamHeight,
                date: date
            )

            // **Partikel** (User-Spec „kleine Partikel fließen
            // Richtung Sauger"): deterministisch seeded, damit sie
            // bei Frame-N keine Re-Layout-Kosten verursachen. 12
            // Partikel reichen für den Effekt ohne Performance-
            // Einschnitt (mobile 60fps stabil).
            suctionParticlesOverlay(
                primary: cfg.primaryColor,
                accent: cfg.accentColor,
                topWidth: topWidth,
                bottomWidth: bottomWidth,
                beamHeight: beamHeight,
                date: date
            )

            TrapezoidShape(topWidth: topWidth, bottomWidth: bottomWidth)
                .stroke(cfg.primaryColor.opacity(0.42), lineWidth: 1.8)
        }
        .frame(width: topWidth, height: beamHeight)
        .scaleEffect(x: 1, y: beamProgress, anchor: .bottom)
        .opacity(Double(beamProgress))
        .position(x: elumiPositionX(in: size.width), y: beamHeight / 2)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    /// Konzentrische horizontale Wellenlinien, die Richtung Sauger
    /// (nach oben) wandern. Verstärkt das „Sog"-Gefühl visuell.
    @ViewBuilder
    fileprivate func suctionWavesOverlay(
        accent: Color,
        topWidth: CGFloat,
        bottomWidth: CGFloat,
        beamHeight: CGFloat,
        date: Date
    ) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        // 4 Wellen-Linien, jede mit eigenem Phasen-Offset. Die
        // y-Koordinate jedes Streifens wandert von unten (1.0) nach
        // oben (0.0) und spawnt dann neu → Fließbewegung.
        ForEach(0..<4, id: \.self) { index in
            let phaseOffset = Double(index) * 0.25
            let rawProgress = (t * 0.55 + phaseOffset).truncatingRemainder(dividingBy: 1.0)
            // 1.0 = unten (Saugglocken-Basis), 0.0 = oben
            // (Sauger-Spitze). Anker-Progress anpassen an
            // Trapezoid-Geometrie:
            let lineY = (1.0 - CGFloat(rawProgress)) * beamHeight - beamHeight / 2
            let widthAtY = bottomWidth + (topWidth - bottomWidth) * CGFloat(1.0 - rawProgress)
            // Fade-In beim Spawn, Fade-Out kurz vor Ziel
            let fade: Double = {
                if rawProgress < 0.15 { return rawProgress / 0.15 }
                if rawProgress > 0.85 { return (1.0 - rawProgress) / 0.15 }
                return 1.0
            }()
            Capsule()
                .fill(accent.opacity(0.42 * fade))
                .frame(width: widthAtY * 0.55, height: 2.0)
                .offset(y: lineY)
        }
    }

    /// Deterministisch gesetzte Partikel, die den Beam hinauffliegen.
    /// Jedes Partikel hat einen festen Lane-Offset + seeded Phase, damit
    /// sie bei Re-Layout nicht „springen", sondern stabil animieren.
    @ViewBuilder
    fileprivate func suctionParticlesOverlay(
        primary: Color,
        accent: Color,
        topWidth: CGFloat,
        bottomWidth: CGFloat,
        beamHeight: CGFloat,
        date: Date
    ) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        ForEach(0..<12, id: \.self) { index in
            // Seeded Lane: gleichmäßig zwischen −0.45 und +0.45.
            let laneFraction = CGFloat(index % 6) / 5.0 - 0.5
            // Verschiedene Geschwindigkeiten — User-Spec-Punkt.
            let speed = 0.6 + Double(index % 3) * 0.25
            let phase = Double(index) * 0.0833
            let rawProgress = (t * speed + phase).truncatingRemainder(dividingBy: 1.0)
            let progress = CGFloat(rawProgress)
            // Y-Pos: bewegt sich von unten nach oben (Sog).
            let particleY = (1.0 - progress) * beamHeight - beamHeight / 2
            // X-Pos: Intensitätszone — näher am Sauger (oben) werden
            // Partikel Richtung Mitte gesaugt. Verzerrungseffekt: je
            // höher, desto kleiner der Lane-Offset.
            let widthAtY = bottomWidth + (topWidth - bottomWidth) * (1.0 - progress)
            let xOffset = widthAtY * laneFraction * (1.0 - progress * 0.6)
            // Fade am Rand.
            let fade: Double = {
                if rawProgress < 0.08 { return rawProgress / 0.08 }
                if rawProgress > 0.92 { return (1.0 - rawProgress) / 0.08 }
                return 1.0
            }()
            Circle()
                .fill(
                    index.isMultiple(of: 2)
                        ? accent.opacity(0.85 * fade)
                        : primary.opacity(0.70 * fade)
                )
                .frame(
                    width: 3.5 - CGFloat(index % 3) * 0.6,
                    height: 3.5 - CGFloat(index % 3) * 0.6
                )
                .offset(x: xOffset, y: particleY)
                .blur(radius: 0.4)
        }
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
    /// **Start-Overlay** (Phase 7.5 — Start-Flow-Unification +
    /// Layout-Nach-Fix).
    ///
    /// Struktur (User-Spec):
    ///   1. Icon
    ///   2. Name
    ///   3. Große Card (Credits)
    ///   4. Spielregeln-Dropdown
    ///   5. CTA
    ///
    /// **Entfallen**: Subline „Spiele und lerne" und der kleine
    /// Info-Pill „1 Runde · 1 Credit". Der Credit-Preis steht schon
    /// in der Credit-Card selbst („1 Runde kostet …").
    var startOverlay: some View {
        let hasCredits = arcadeCredits >= ArcadeCreditSystem.gamesCost
        return GameStartScreen(
            title: "Elumi Spiel",
            subline: nil,
            infoLine: nil,
            primaryCTALabel: hasCredits ? "Spiel starten" : "Lernen starten",
            primaryCTAIcon: hasCredits ? "play.fill" : "book.fill",
            primaryCTAEnabled: true,
            hint: hasCredits ? nil : "Lernen bringt Credits — dann wieder spielen",
            onPrimaryCTA: {
                if hasCredits {
                    arcadeCredits -= ArcadeCreditSystem.gamesCost
                    startGame()
                } else {
                    exitArcadeSilently()
                    dismiss()
                }
            },
            onBack: {
                exitArcadeSilently()
                dismiss()
            },
            icon: {
                ElumiArcadeCharacter(
                    mouthOpen: false,
                    scale: 1.04,
                    rotation: 0,
                    sparkleBurst: true
                )
            },
            extraContent: {
                VStack(spacing: 14) {
                    startCreditHeroCard
                    startRulesDisclosure
                }
            }
        )
        .transition(.opacity)
        // **Audio-Session-Warmup** (Phase 7.6 — User-Report
        // „Elumi-Musik startet erst nach SFX-Trigger"): Session beim
        // Erscheinen des Start-Overlays aktivieren, damit der
        // Musik-Start beim Tap nicht den ersten Session-Setup
        // abwarten muss. Sonst bleibt `player.play()` stumm, bis
        // ein SFX-Event die Session vollends aktiviert.
        .onAppear {
            feedbackPlayer.sp.ensureAudioSession()
        }
    }

    /// Credit-Hero: großer Credit-Wert + Verbindung zum Lernsystem.
    /// Icon bewusst `circle.hexagongrid.fill` (gleiche Sprache wie in der
    /// Home-Balanced-Bar), damit der User „Credits" über alle Screens
    /// mit demselben Symbol wiedererkennt.
    ///
    /// **Phase 7.5 Nachsatz** — Leben-Row unter „1 Runde kostet …":
    /// dieselben Mini-Elumi-Icons, die während des Spiels oben rechts
    /// den Leben-Stand anzeigen. Damit sieht der User schon vor dem
    /// Start, wie viele Leben er pro Runde bekommt.
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

                Text(arcadeCredits == 1 ? "Spiel" : "Spiele")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(hasCredits
                    ? "1 Runde kostet \(ArcadeCreditSystem.gamesCost) Spiel"
                    : "Lernen bringt Spiele — dann spielen")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            // Leben-Row (Phase 7.5) — 4 Mini-Elumis analog zum HUD
            // oben rechts während des Spielens. „4 Leben"-Label +
            // Icon-Zeile, damit der Spieler weiß, was ihn erwartet.
            HStack(spacing: 8) {
                Text("\(ElumiArcadeGameView.maxMisses) Leben")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                HStack(spacing: 3) {
                    ForEach(0..<ElumiArcadeGameView.maxMisses, id: \.self) { _ in
                        Image("SplashCharacter")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.top, 2)
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

    // Der frühere `startCTASection` ist in die shared `GameStartScreen`-
    // Komponente gewandert (Phase 7.5 — Unification). Credit-Abzug +
    // `startGame()` passieren jetzt im `onPrimaryCTA`-Closure in
    // `startOverlay` oben; „Lernen starten" ebenso über den gleichen
    // CTA-Slot (Label/Icon wechseln je nach Credit-Status).

    /// Regeln einklappbar — Platz nicht mehr durch Gameplay-Regeln dominiert.
    var startRulesDisclosure: some View {
        VStack(spacing: 10) {
            Button {
                // Phase 7.6 — systemweite State-Animation.
                withAnimation(AppMotion.state) {
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

    /// **Game-Over-Overlay** (Phase 7.5 — Ende-Flow-Unification).
    ///
    /// Nutzt jetzt die shared `GameSummaryView`-Komponente — identisch
    /// zu Word Runner. Elumi-spezifische Daten:
    ///   - Hero = `score` (Punkte)
    ///   - Stats = Runde / Gefangen / Verpasst / Highscore
    ///   - Badge = „Neuer Highscore" wenn `didBeatHighScore`
    ///   - Primär-CTA „Nochmal" nur bei ausreichend Credits — mit
    ///     Hint über Rest-Credits. Ohne Credits: Label wird zu
    ///     „Lernen starten", führt zurück zum Home.
    var gameOverOverlay: some View {
        let hasCredits = arcadeCredits >= ArcadeCreditSystem.gamesCost
        return GameSummaryView(
            headline: gameOverTitle,
            subtitle: gameOverSubtitle.isEmpty ? nil : gameOverSubtitle,
            badge: didBeatHighScore ? "Neuer Highscore" : nil,
            heroValue: "\(score)",
            heroValueLabel: "Punkte",
            heroValueColor: AppTheme.Colors.warning,
            stats: [
                .init(title: "Runde",     value: "\(round)"),
                .init(title: "Gefangen",  value: "\(totalCaught)"),
                .init(title: "Verpasst",  value: "\(misses)"),
                .init(title: "Highscore", value: "\(max(highScore, score))")
            ],
            primaryCTALabel: hasCredits ? "Noch eine Runde" : "Lernen starten",
            primaryCTAIcon: hasCredits ? "arrow.clockwise" : "book.fill",
            primaryCTAEnabled: true,
            primaryCTAHint: hasCredits
                ? "\(arcadeCredits) Credit\(arcadeCredits == 1 ? "" : "s") übrig"
                : "0 Credits — Lernen bringt Credits",
            onPrimaryCTA: {
                if hasCredits {
                    arcadeCredits -= ArcadeCreditSystem.gamesCost
                    restartGame()
                } else {
                    exitArcadeSilently()
                    dismiss()
                }
            },
            secondaryCTALabel: "Zur Startseite",
            onSecondaryCTA: {
                exitArcadeSilently()
                dismiss()
            },
            icon: {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.primary.opacity(0.16))
                    ElumiSnackCluster(count: max(1, min(totalCaught, 3)), size: 38)
                }
            }
        )
        .transition(.opacity)
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

