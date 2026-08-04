import SwiftUI

extension ElumiArcadeGameView {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                arcadeBackground

                arcadeBubbles

                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let motionDate = gameClock

                    ZStack {
                        if hasActiveSuction(at: context.date) {
                            suctionBeam(at: context.date, in: geometry.size)
                        }

                        ForEach(activeSnacks) { snack in
                            let position = snackPosition(for: snack, at: motionDate, in: geometry.size)

                            fallingObjectView(for: snack, at: motionDate)
                                .rotationEffect(.degrees(snack.rotationDrift * (1 - snackProgress(for: snack, at: motionDate))))
                                .position(position)
                                .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 2)
                        }

                        // Jellyfish
                        if let jelly = activeJellyfish {
                            jellyfishView(for: jelly, at: context.date, in: geometry.size)
                                .position(jellyfishPosition(for: jelly, at: context.date, in: geometry.size))
                        }

                        // Falling tentacles
                        ForEach(activeTentacles) { tentacle in
                            fallingTentacleView(for: tentacle, at: context.date)
                                .position(tentaclePosition(for: tentacle, at: context.date, in: geometry.size))
                        }

                        // Ambient Sea-Creature (Fish-School / Shark) —
                        // rein visuell, gleitet einmal pro Runde durch.
                        // Niedriger Z-Index (vor Background, hinter
                        // Snacks + Elumi), damit es atmosphärisch
                        // wirkt, aber Gameplay nicht verdeckt.
                        //
                        // **Fade-Out** (User-Spec „sauber aus dem Screen
                        // schwimmen, nicht abrupt"): in den letzten
                        // 20 % der Crossing-Zeit fadet die Kreatur
                        // linear von 1.0 → 0.0. Kombiniert mit dem
                        // natürlichen Off-Screen-Exit wirkt sie sanft
                        // verblassend statt hart verschwindend.
                        if let creature = ambientSeaCreature {
                            let elapsed = context.date.timeIntervalSince(creature.spawnedAt)
                            let fadeProgress: Double = {
                                let fadeStart = creature.speed * 0.80
                                guard elapsed >= fadeStart else { return 0 }
                                let fadeWindow = creature.speed - fadeStart
                                guard fadeWindow > 0 else { return 0 }
                                return min(1, (elapsed - fadeStart) / fadeWindow)
                            }()
                            let verticalVel = ambientSeaCreatureVerticalVelocity(
                                for: creature,
                                at: context.date
                            )
                            AmbientSeaCreatureView(
                                creature: creature,
                                now: context.date,
                                verticalVelocity: verticalVel
                            )
                                .position(ambientSeaCreaturePosition(for: creature, at: context.date, in: geometry.size))
                                .allowsHitTesting(false)
                                .opacity(1.0 - fadeProgress)
                                .zIndex(-1)
                        }

                        ElumiArcadeCharacter(
                            mouthOpen: mouthOpen,
                            scale: characterScale,
                            rotation: characterRotation,
                            sparkleBurst: sparkleBurst
                        )
                        .scaleEffect(elumiVisible ? suctionDockScale : 0.4)
                        // **Quick-Fix 2026-04-30 — 2. Iteration**: Opacity-
                        // Hit-Multiplier für das Lebens-Verlust-Feedback.
                        // `characterOpacityHit` wird in `triggerLifeLossVisual()`
                        // kurz auf 0.40 gepulst und zurück auf 1.0 — der
                        // Charakter wirkt für einen kurzen Moment „blass/
                        // getroffen". Multiplikativ mit der Visibility-Logik:
                        // wenn der Charakter aus anderen Gründen unsichtbar
                        // ist (Suction-Hide), bleibt er das.
                        .opacity(elumiVisible ? characterOpacityHit : 0)
                        .overlay {
                            // Sting flash overlay
                            if jellyfishStingCount > 0 {
                                let blinkFreq: Double = jellyfishStingCount >= 2 ? 6.0 : 3.0
                                let blinkOn = sin(context.date.timeIntervalSinceReferenceDate * blinkFreq) > 0
                                Circle()
                                    .fill(Color.red.opacity(blinkOn ? 0.45 : 0))
                                    .frame(width: 80, height: 80)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay {
                            // **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`,
                            // 2. Iteration)** — Lebens-Verlust-Flash + Bolt-
                            // Icon. Dauer ~0.8s (vorher 0.5s zu kurz, User-
                            // Report: „noch zu schwach"). Größerer Flash-
                            // Kreis (140pt statt 100pt) deckt den Charakter
                            // komplett ab. Plus ein zucker-Bolt-Icon
                            // („bolt.fill") als Damage-Symbol mit Scale-In/
                            // Out-Animation in der ersten Hälfte des Flashes.
                            if let lostAt = lifeLostFlashAt {
                                let elapsed = context.date.timeIntervalSince(lostAt)
                                if elapsed < 0.8 {
                                    let circleOpacity = max(0, 0.7 - elapsed * 0.875)
                                    Circle()
                                        .fill(Color.red.opacity(circleOpacity))
                                        .frame(width: 140, height: 140)
                                        .allowsHitTesting(false)
                                }
                                if elapsed < 0.6 {
                                    // Bolt-Icon: scale-in (0..0.15s),
                                    // halten (0.15..0.40s), scale-out
                                    // (0.40..0.60s).
                                    let boltScale: CGFloat = {
                                        if elapsed < 0.15 {
                                            return CGFloat(elapsed / 0.15) * 1.4
                                        } else if elapsed < 0.40 {
                                            return 1.4
                                        } else {
                                            let t = (elapsed - 0.40) / 0.20
                                            return 1.4 * CGFloat(1.0 - t)
                                        }
                                    }()
                                    let boltOpacity = max(0, 1.0 - (elapsed / 0.6))
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 42, weight: .black))
                                        .foregroundStyle(.yellow)
                                        .shadow(color: .red.opacity(0.6), radius: 8, x: 0, y: 0)
                                        .scaleEffect(boltScale)
                                        .opacity(boltOpacity)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .overlay {
                            // **Schutz-Bubble Aktiv-Zustand**: weiche
                            // Seifenblasen-Hülle um den Spieler.
                            // Rendert sich direkt als Overlay auf den
                            // Character, skaliert mit `shieldBubbleDockScale`
                            // (Pickup-Impuls + Kollisions-Bounces). Nur
                            // sichtbar, solange der Aktiv-Timer läuft.
                            if hasActiveShieldBubble(at: context.date) {
                                shieldBubbleActiveOverlay(at: context.date)
                                    .scaleEffect(shieldBubbleDockScale)
                                    .allowsHitTesting(false)
                                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                            }
                        }
                        .overlay(alignment: .top) {
                            // **Sauger-Andock-Zustand**: Während der
                            // Sauger aktiv ist, sitzt das Trichter-
                            // Power-Up sichtbar über Elumi's Kopf
                            // (zentriert, leicht schwebend). Signalisiert
                            // User-Spec „Illumi + Sauger = ein System".
                            // Der eigentliche Saugstrahl läuft weiterhin
                            // als separates Overlay (`suctionBeam` in
                            // Layout.swift davor).
                            if hasActiveSuction(at: context.date) {
                                ArcadeSaugerFunnel(
                                    size: 42,
                                    animationDate: context.date,
                                    energyIntensity: 1.2,
                                    phase: .docked
                                )
                                .scaleEffect(suctionDockScale)
                                .offset(y: -58)
                                .allowsHitTesting(false)
                                // **Dock-Transition von oben** (User-
                                // Spec: „gerade runterkommen und sich
                                // dann auf Elumis Kopf setzen"). Der
                                // Sauger materialisiert ~48 pt über
                                // seiner Ruheposition und sinkt in
                                // Position — wirkt wie das Landen
                                // auf Elumis Kopf nach dem Einsammeln.
                                .transition(
                                    .move(edge: .top)
                                        .combined(with: .scale(scale: 0.6))
                                        .combined(with: .opacity)
                                )
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: hasActiveSuction())
                        .animation(.easeInOut(duration: 0.2), value: hasActiveShieldBubble())
                        .position(
                            x: elumiPositionX(in: geometry.size.width),
                            y: elumiPositionY(in: geometry.size.height)
                        )
                        // Smooth Follow — Elumi folgt dem Finger mit
                        // leichtem Spring-Ease statt pixelgenau zu
                        // kleben. Wichtig für das neue Y-Spiel (User-
                        // Spec „smooth und flüssig"): schnelle Drags
                        // ergeben einen weichen Bogen statt harten
                        // Sprüngen. 220 ms Response mit hohem Damping
                        // reagiert flott, überschwingt aber nicht.
                        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: elumiX)
                        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: elumiY)

                        // Bonus round fish
                        if isBonusRound {
                            ForEach(activeFish.filter({ !$0.isCaught })) { fish in
                                let pos = fishPosition(for: fish, at: context.date, in: geometry.size)
                                bonusFishView(for: fish, at: context.date, in: geometry.size)
                                    .position(pos)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Phase 7.5: HeaderBar (X-Close + Score + Leben)
                    // NUR sichtbar, solange das Spiel tatsächlich
                    // läuft — auf dem Start-Screen hat der User bereits
                    // den Chevron aus `GameStartScreen`, ein zusätzliches
                    // X oben wäre doppelte Chrome (User-Report).
                    // Während Game-Over übernimmt das gameOverOverlay
                    // das Chrome-Feedback ohnehin vollständig.
                    if !showingStartOverlay && !isGameOver {
                        headerBar
                    }
                    Spacer(minLength: 0)
                    footerHint
                }
                .padding(.horizontal, 18)
                .padding(.top, 58)
                .padding(.bottom, 28)
                .zIndex(showingStartOverlay ? 3 : 1)

                if isGameOver {
                    // **Play-Credits-Rescue-Prompt** (2026-04-24):
                    // Fängt das Game-Over ab, solange der Nutzer
                    // Credits hat und noch nicht entschieden hat.
                    // Greift der Rescue, läuft das Spiel nahtlos
                    // weiter. Lehnt der Nutzer ab, übernimmt das
                    // reguläre `gameOverOverlay`.
                    if shouldShowRescueOffer {
                        playCreditsRescueOverlay
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(6)
                    } else {
                        gameOverOverlay
                    }
                }

                if showingStartOverlay {
                    startOverlay
                }

                if showingRoundBanner && !isGameOver {
                    roundCompleteBanner
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(4)
                }

                if bonusRoundWaitingForTap {
                    Group {
                        if bonusRoundResultText != nil {
                            bonusRoundResult
                        } else {
                            bonusRoundAnnouncement
                        }
                    }
                    .onTapGesture { handleBonusRoundTap() }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(5)
                }

                if let comboBannerText, !comboBannerText.isEmpty, !isGameOver, !showingStartOverlay, !showingRoundBanner {
                    comboBanner(text: comboBannerText)
                        .padding(.top, 102)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // **2026-06-09** — Arcade-Zäsur nach einem Lebens-Verlust.
                // Zustandsgesteuert statt über `context.date`: dieser
                // ZStack liegt außerhalb der TimelineView-Closure. Die
                // eigene Zeitachse für den „Bereit?"-Wechsel bringt das
                // Overlay selbst mit.
                if lifeLostPauseUntil != nil, !isGameOver {
                    lifeLostPauseOverlay()
                        .zIndex(6)
                }
            }
            .offset(x: screenShakeOffset)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if isBonusRound {
                            updateElumiPosition2D(to: value.location, in: geometry.size)
                        } else {
                            // Neu: 2D-Update auch in normalen Runden,
                            // aber mit begrenzter Y-Range (1 Icon nach
                            // oben, 0.5 Icon nach unten — siehe
                            // `updateElumiArcadePosition2D`). Spieler
                            // kann jetzt auch vertikal ausweichen.
                            updateElumiArcadePosition2D(
                                to: value.location,
                                in: geometry.size
                            )
                        }
                    }
            )
            .onAppear {
                gameSize = geometry.size
                // Zentrale Sound-Hook einmalig initialisieren, falls
                // noch nicht gesetzt (first-mount). Wird beim nächsten
                // Mount reused via `@State`.
                if arcadeSFX == nil {
                    arcadeSFX = ArcadeSFX(feedbackPlayer: feedbackPlayer)
                }
                // **Phase 7.5 — Start-Flow-Unification**:
                // `autoStart` wird bewusst NICHT mehr respektiert.
                // Jeder Einstieg (Footer-Icon, GameHub-Button) zeigt
                // zuerst das Start-Overlay. Credit-Abzug + `startGame()`
                // passieren jetzt ausschließlich im `GameStartScreen`-
                // CTA-Closure. Der Parameter bleibt nur zur Laufzeit-
                // Kompatibilität der Navigation-Route bestehen.
                _ = autoStart   // silence unused-warning, see doc above

                // **Phase 7.6** — Start-Sound beim Aufruf des Start-
                // Screens (User-Spec „start sound nur zum aufruf").
                // Feuert genau einmal, wenn der User auf Elumi
                // navigiert (Footer-Icon / GameHub-CTA). Beim
                // tatsächlichen Run-Start im Overlay kommt dafür
                // die Musik sofort — kein zweiter SFX.
                feedbackPlayer.playLaunch()
                // Audio-Session gleich warm machen, damit der Musik-
                // Start ohne Anlauf-Delay geht.
                feedbackPlayer.sp.ensureAudioSession()
                // Nächsten Arcade-Track preloaden, sodass `play()`
                // im `startGame()` ohne Decoder-Anlauf startet.
                ArcadeMusicPlayer.shared.preloadNextTrack()
            }
            .onChange(of: showingStartOverlay) { _, isShowing in
                // Sobald der User im Start-Overlay „Spiel starten" drückt
                // (oder das Overlay anderweitig dismissed wird), wird
                // Immersive aktiv und der globale Footer blendet aus.
                setImmersiveArcade?(!isShowing)
            }
            .onChange(of: geometry.size) { _, newSize in
                gameSize = newSize
            }
        }
        .ignoresSafeArea()
        // Phase 7.5 — System-Nav-Back-Button ausblenden. Der
        // `GameStartScreen` im Overlay rendert einen eigenen Chevron
        // oben links; die System-Chrome würde sonst darüber einen
        // zweiten Chevron zeigen (User-Report „doppelter chevron").
        .toolbar(.hidden, for: .navigationBar)
        .task(id: gameSeed) {
            await runGameLoops()
        }
        .onDisappear {
            // Spiel endgültig beenden — egal auf welchem Weg der Screen
            // dismissed wurde (X-Button, Footer-Wechsel, System-Geste).
            // Musik, BGM, Loops und Ambient müssen zuverlässig verstummen,
            // und der Immersive-Flag zurückgesetzt werden, damit der
            // globale Footer auf der zurückkehrenden View wieder erscheint.
            exitArcadeSilently()
            setImmersiveArcade?(false)
        }
    }

    private var arcadeBackground: some View {
        LinearGradient(
            colors: [
                AppTheme.Colors.elumiMidnight,
                AppTheme.Colors.background,
                AppTheme.Colors.elumiMint.opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [
                    AppTheme.Colors.elumiMint.opacity(0.14),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 340
            )
        )
    }

    private var arcadeBubbles: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            ZStack {
                arcadeBubble(seed: 0.13, size: 8, drift: 10, duration: 5.8, delay: 0.0, time: t)
                arcadeBubble(seed: 0.24, size: 5, drift: -8, duration: 4.9, delay: 1.0, time: t)
                arcadeBubble(seed: 0.38, size: 9, drift: 12, duration: 6.1, delay: 0.3, time: t)
                arcadeBubble(seed: 0.55, size: 6, drift: -6, duration: 5.2, delay: 1.6, time: t)
                arcadeBubble(seed: 0.71, size: 10, drift: 14, duration: 6.4, delay: 0.9, time: t)
                arcadeBubble(seed: 0.86, size: 7, drift: -9, duration: 5.6, delay: 1.3, time: t)
            }
        }
        .allowsHitTesting(false)
    }

    private var headerBar: some View {
        VStack(spacing: 8) {
            // Top row: close button, score, lives
            HStack(spacing: 0) {
                Button {
                    // Explizit: erst Audio + Spielzustand stoppen, dann dismiss.
                    // `onDisappear` ruft das gleiche, aber dieser direkte Weg
                    // sorgt dafür, dass es zuverlässig vor dem Cover-Close passiert.
                    exitArcadeSilently()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .background(AppTheme.Colors.surface.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // Score
                VStack(spacing: 0) {
                    Text("Punkte")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text("\(score)")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.warning)
                }
                    .shadow(color: AppTheme.Colors.warning.opacity(0.3), radius: 8, x: 0, y: 2)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: score)

                Spacer(minLength: 0)

                // Lives as mini Elumis
                HStack(spacing: 3) {
                    ForEach(0..<maxMisses, id: \.self) { index in
                        let alive = index < maxMisses - misses
                        Image("SplashCharacter")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())
                            .saturation(alive ? 1.0 : 0.0)
                            .opacity(alive ? 1.0 : 0.3)
                    }
                }
            }

            // Stats row: Round, Caught, Missed
            HStack(spacing: 0) {
                arcadeStatPill(icon: "flag.fill", label: "Runde \(round)", tint: AppTheme.Colors.primary)
                Spacer(minLength: 0)
                arcadeStatPill(icon: "checkmark.circle.fill", label: "Gefangen \(totalCaught)", tint: AppTheme.Colors.success)
                Spacer(minLength: 0)
                arcadeStatPill(icon: "xmark.circle.fill", label: "Verloren \(misses)", tint: AppTheme.Colors.error)
            }

            // **Tickets-Row** (2026-04-24, Pool-Vereinheitlichung
            // 2026-04-30 Stufe 1b): kleine, dezente Zeile mit
            // aktuellem Credit-Stand + Skip-Button. Nur sichtbar,
            // solange Credits > 0 ODER Skip-fähig ist (sonst nimmt
            // die Zeile unnötig Platz im HUD). Quelle: `arcadeCredits`
            // (vorher `playCredits.credits` aus dem entfernten
            // `ElumiCreditsStore`).
            if arcadeCredits > 0 || playCreditsSkipEnabled {
                HStack(spacing: 8) {
                    playCreditsHUDChip
                    Spacer(minLength: 0)
                    // **2026-06-09** — Skip nur zeigen, wenn er auch
                    // benutzbar ist. Vorher stand er dauerhaft da und
                    // sah im deaktivierten Zustand genauso aus wie im
                    // aktiven — ein Knopf, der auf Tippen nicht
                    // reagiert, wirkt kaputt (User-Report).
                    if playCreditsSkipEnabled {
                        playCreditsSkipChip
                    }
                }
            }

            // Power-up chips
            HStack(spacing: 6) {
                if hasActiveSuction() {
                    arcadeStatusChip(
                        icon: "sparkles",
                        label: "Saugstrahl",
                        tint: AppTheme.Colors.primary
                    )
                }
                if hasActiveBonusPoints() {
                    arcadeStatusChip(
                        icon: "star.fill",
                        label: "x2 Punkte",
                        tint: AppTheme.Colors.warning
                    )
                }
                if hasActiveSlowMotion() && slowMotionSecondsRemaining() > 0 {
                    arcadeStatusChip(
                        icon: "tortoise.fill",
                        label: "Zeitlupe",
                        tint: .blue
                    )
                }
                if isBonusRound {
                    arcadeStatusChip(
                        icon: "fish.fill",
                        label: "🐟 \(bonusFishCaught)/\(bonusFishTotal)",
                        tint: .cyan
                    )
                }
                if comboCount >= 3 && !isGameOver {
                    arcadeStatusChip(
                        icon: "flame.fill",
                        label: "x\(comboCount)",
                        tint: AppTheme.Colors.success
                    )
                }
            }
        }
    }

    private func arcadeStatPill(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.Colors.surface.opacity(0.85))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var footerHint: some View {
        if showingStartOverlay {
            EmptyView()
        }
    }
}
