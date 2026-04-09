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

                        ElumiArcadeCharacter(
                            mouthOpen: mouthOpen,
                            scale: characterScale,
                            rotation: characterRotation,
                            sparkleBurst: sparkleBurst
                        )
                        .scaleEffect(elumiVisible ? suctionDockScale : 0.4)
                        .opacity(elumiVisible ? 1 : 0)
                        .position(x: elumiPositionX(in: geometry.size.width), y: geometry.size.height - 118)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    headerBar
                    Spacer(minLength: 0)
                    footerHint
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .zIndex(showingStartOverlay ? 3 : 1)

                if isGameOver {
                    gameOverOverlay
                }

                if showingStartOverlay {
                    startOverlay
                }

                if showingRoundBanner && !isGameOver {
                    roundCompleteBanner
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(4)
                }

                if let comboBannerText, !comboBannerText.isEmpty, !isGameOver, !showingStartOverlay, !showingRoundBanner {
                    comboBanner(text: comboBannerText)
                        .padding(.top, 102)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .offset(x: screenShakeOffset)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateElumiPosition(to: value.location.x, width: geometry.size.width)
                    }
            )
            .onAppear {
                gameSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                gameSize = newSize
            }
        }
        .ignoresSafeArea()
        .task(id: gameSeed) {
            await runGameLoops()
        }
        .onDisappear {
            isPlaying = false
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
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .background(AppTheme.Colors.surface.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                // Score - big and central
                Text("\(score)")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .shadow(color: AppTheme.Colors.warning.opacity(0.3), radius: 8, x: 0, y: 2)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: score)

                Spacer(minLength: 0)

                // Lives
                HStack(spacing: 5) {
                    ForEach(0..<maxMisses, id: \.self) { index in
                        Image(systemName: index < maxMisses - misses ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(index < maxMisses - misses ? AppTheme.Colors.error : AppTheme.Colors.error.opacity(0.25))
                    }
                }
            }

            // Stats row: Round, Caught, Missed
            HStack(spacing: 0) {
                arcadeStatPill(icon: "flag.fill", label: "Runde \(round)", tint: AppTheme.Colors.primary)
                Spacer(minLength: 0)
                arcadeStatPill(icon: "checkmark.circle.fill", label: "\(totalCaught)", tint: AppTheme.Colors.success)
                Spacer(minLength: 0)
                arcadeStatPill(icon: "xmark.circle.fill", label: "\(misses)", tint: AppTheme.Colors.error)
            }

            // Power-up chips
            HStack(spacing: 6) {
                if hasActiveSuction() {
                    arcadeStatusChip(
                        icon: "sparkles",
                        label: "Saugstrahl \(suctionSecondsRemaining())s",
                        tint: AppTheme.Colors.primary
                    )
                }
                if hasActiveBonusPoints() {
                    arcadeStatusChip(
                        icon: "star.fill",
                        label: "x2 \(bonusPointsSecondsRemaining())s",
                        tint: AppTheme.Colors.warning
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
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
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
