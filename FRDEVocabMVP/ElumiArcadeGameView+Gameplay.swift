import SwiftUI
import AudioToolbox

extension ElumiArcadeGameView {
    func spawnSnack() {
        let roll = Double.random(in: 0...1)

        // Round-specific spawn rates
        let bonusChance: Double
        let falseElumiChance: Double
        let suctionChance: Double

        switch round {
        case 3: // Bonus-Regen: more power-ups
            bonusChance = 0.14
            suctionChance = 0.12
            falseElumiChance = min(0.10, 0.04 + (Double(round - 1) * 0.02))
        case 4: // Doppelgänger: many false Elumis
            bonusChance = 0.055
            suctionChance = 0.07
            falseElumiChance = 0.20
        default: // Round 1, 2, 5+
            bonusChance = round >= 5 ? 0.10 : 0.055
            suctionChance = round >= 5 ? 0.10 : 0.07
            falseElumiChance = round >= 5 ? 0.16 : min(0.12, 0.04 + (Double(round - 1) * 0.02))
        }

        // Guarantee at least 1 suction per round (halfway through)
        let halfwayCount = snacksForRound(round) / 2
        let forceSuction = !roundSuctionSpawned && roundCatchCount >= halfwayCount

        let kind: ElumiArcadeDropKind
        if forceSuction {
            kind = .saugglocke
            roundSuctionSpawned = true
        } else if roll < bonusChance {
            kind = .bonusblase
        } else if roll < bonusChance + suctionChance {
            kind = .saugglocke
            roundSuctionSpawned = true
        } else if roll < bonusChance + suctionChance + falseElumiChance {
            kind = .falseElumi
        } else {
            kind = [.wuermchen, .wasserfloh, .algenkugel].randomElement() ?? .wuermchen
        }

        // Round 2+: Querschläger — aggressive zigzag across the screen
        let querschlaegerChance: Double = round == 2 ? 0.35 : (round >= 3 ? 0.25 : 0)
        let isQuerschlaeger = kind.isSnack && Double.random(in: 0...1) < querschlaegerChance
        let wobbleAmp = isQuerschlaeger
            ? CGFloat.random(in: 0.15...0.25)
            : CGFloat.random(in: 0.01...0.05)
        let wobbleFreq = isQuerschlaeger
            ? Double.random(in: 4.0...6.5)
            : Double.random(in: 1.4...3.1)

        activeSnacks.append(
            ElumiArcadeSnackState(
                kind: kind,
                spawnedAt: gameClock,
                laneX: CGFloat.random(in: 0.12...0.88),
                wobbleAmplitude: wobbleAmp,
                wobbleFrequency: wobbleFreq,
                fallDuration: currentFallDuration(),
                rotationDrift: Double.random(in: -18...18),
                renderScale: spawnRenderScale(for: kind),
                motionPhase: Double.random(in: 0...(Double.pi * 2)),
                points: snackPoints(for: kind)
            )
        )
    }

    func startGame() {
        guard showingStartOverlay else { return }
        feedbackPlayer.playLaunch()
        showingStartOverlay = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            elumiVisible = true
        }
        gameSeed = UUID()
    }

    func restartGame() {
        showingStartOverlay = false
        elumiVisible = true
        gameSeed = UUID()
    }

    func triggerCatchAnimation() {
        withAnimation(.easeInOut(duration: 0.1)) {
            mouthOpen = true
            characterScale = 1.08
            characterRotation = -3
            sparkleBurst = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.spring(response: 0.24, dampingFraction: 0.74)) {
                mouthOpen = false
                characterScale = 1
                characterRotation = 2
            }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.14)) {
                sparkleBurst = false
                characterRotation = 0
            }
        }
    }

    func hasActiveSuction(at date: Date = Date()) -> Bool {
        guard let suctionEndsAt else { return false }
        return suctionEndsAt > date
    }

    func hasActiveBonusPoints(at date: Date = Date()) -> Bool {
        guard let bonusPointsEndsAt else { return false }
        return bonusPointsEndsAt > date
    }

    func hasActiveSlowMotion(at date: Date = Date()) -> Bool {
        guard let slowMotionEndsAt else { return false }
        return slowMotionEndsAt > date
    }

    func suctionSecondsRemaining(at date: Date = Date()) -> Int {
        guard let suctionEndsAt else { return 0 }
        return max(0, Int(ceil(suctionEndsAt.timeIntervalSince(date))))
    }

    func bonusPointsSecondsRemaining(at date: Date = Date()) -> Int {
        guard let bonusPointsEndsAt else { return 0 }
        return max(0, Int(ceil(bonusPointsEndsAt.timeIntervalSince(date))))
    }

    func activateSuction(at date: Date) {
        // Dock-in animation: scale Elumi up briefly
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            suctionDockScale = 1.25
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                suctionDockScale = 1.0
            }
        }

        activateSlowMotion(at: date)
        suctionEndsAt = date.addingTimeInterval(suctionDuration)
        showComboBanner("Saugstrahl aktiviert")
        feedbackPlayer.playSuctionWhir()

        // Humming sound during suction (system vibration pattern)
        startSuctionHumming()
    }

    func startSuctionHumming() {
        suctionHummingTimer?.invalidate()
        // Fast whirring: alternating haptic patterns for suction feel
        var tick = 0
        suctionHummingTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
            // Alternate between two haptic intensities for whirring effect
            AudioServicesPlaySystemSound(tick % 3 == 0 ? 1519 : 1520)
            tick += 1
        }
        let duration = suctionDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.suctionHummingTimer?.invalidate()
            self.suctionHummingTimer = nil
        }
    }

    func activateBonusPoints(at date: Date) {
        bonusPointsEndsAt = date.addingTimeInterval(bonusPointsDuration)
        showComboBanner("x2 Punkte aktiv")
        feedbackPlayer.playAchievement()
    }

    func triggerHazardGameOver() {
        triggerScreenShake()
        gameOverTitle = "Falscher Elumi"
        gameOverSubtitle = "Den musst du vorbeischwimmen lassen."
        isGameOver = true
        isPlaying = false
        feedbackPlayer.playGameOver()
    }

    func activateSlowMotion(at date: Date) {
        slowMotionEndsAt = date.addingTimeInterval(slowMotionDuration)
    }

    func advanceGameClock(now: Date) -> Date {
        let previousFrameDate = lastFrameDate ?? now
        let delta = max(0, now.timeIntervalSince(previousFrameDate))
        lastFrameDate = now

        let motionScale = hasActiveSlowMotion(at: now) ? 0.28 : 1.0
        gameClock = gameClock.addingTimeInterval(delta * motionScale)
        return gameClock
    }

    func triggerScreenShake() {
        Task { @MainActor in
            let sequence: [CGFloat] = [13, -11, 8, -6, 4, -2, 0]
            for offset in sequence {
                withAnimation(.easeOut(duration: 0.045)) {
                    screenShakeOffset = offset
                }
                try? await Task.sleep(for: .milliseconds(38))
            }
            screenShakeOffset = 0
        }
    }

    func pointsForCaughtSnack(_ snack: ElumiArcadeSnackState, at date: Date) -> Int {
        let isComboCatch: Bool
        if let lastCatchDate {
            isComboCatch = date.timeIntervalSince(lastCatchDate) <= 1.1
        } else {
            isComboCatch = false
        }

        comboCount = isComboCatch ? comboCount + 1 : 1
        bestCombo = max(bestCombo, comboCount)
        lastCatchDate = date
        totalCaught += 1

        let comboBonus = comboCount >= 3 ? min(12, (comboCount - 2) * 2) : 0
        if comboCount >= 3 {
            let multiplierLabel = hasActiveBonusPoints(at: date) ? " · x2" : ""
            let prefix = comboCount >= 5 ? "Mega-Combo" : "Combo"
            showComboBanner("\(prefix) x\(comboCount) · +\(comboBonus)\(multiplierLabel)")
        }

        let rawPoints = snack.points + comboBonus
        return hasActiveBonusPoints(at: date) ? rawPoints * 2 : rawPoints
    }

    func showComboBanner(_ text: String) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            comboBannerText = text
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard comboBannerText == text else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                comboBannerText = nil
            }
        }
    }

    func resetCombo() {
        comboCount = 0
        lastCatchDate = nil
    }

    func triggerRoundComplete() {
        showingRoundBanner = true
        roundBannerPhase = 0
        readyBlinkVisible = true
        activeSnacks = []
        feedbackPlayer.playAchievement()

        Task { @MainActor in
            // Phase 0: "Runde X geschafft!" für 2s
            try? await Task.sleep(for: .seconds(2))
            guard showingRoundBanner else { return }

            // Phase 1: "Ready?" + "Runde X+1" mit Blinken
            round += 1
            roundCatchCount = 0
            roundSuctionSpawned = false
            roundBannerPhase = 1

            for _ in 0..<3 {
                withAnimation(.easeInOut(duration: 0.25)) { readyBlinkVisible = false }
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeInOut(duration: 0.25)) { readyBlinkVisible = true }
                try? await Task.sleep(for: .milliseconds(300))
            }

            try? await Task.sleep(for: .milliseconds(200))
            guard showingRoundBanner else { return }
            showingRoundBanner = false
        }
    }

    func updateGame(now: Date) {
        guard gameSize != .zero else { return }
        if let suctionEndsAt, suctionEndsAt <= now {
            self.suctionEndsAt = nil
        }
        if let bonusPointsEndsAt, bonusPointsEndsAt <= now {
            self.bonusPointsEndsAt = nil
        }
        if let slowMotionEndsAt, slowMotionEndsAt <= now {
            self.slowMotionEndsAt = nil
        }

        let motionNow = advanceGameClock(now: now)

        var survivors: [ElumiArcadeSnackState] = []
        var earnedPoints = 0
        var missedAnySnack = false
        var caughtSnackCount = 0
        let elumiXPosition = elumiPositionX(in: gameSize.width)
        let suctionActive = hasActiveSuction(at: now)

        for snack in activeSnacks {
            let progress = snackProgress(for: snack, at: motionNow)
            let position = snackPosition(for: snack, at: motionNow, in: gameSize)
            let catchLineY = gameSize.height - 158
            let isCatchable = position.y >= catchLineY
            let horizontalDistance = abs(position.x - elumiXPosition)
            let isInSuctionBeam = suctionActive &&
                snack.kind.isSnack &&
                position.y < catchLineY &&
                abs(position.x - elumiXPosition) <= suctionBeamHalfWidth

            if snack.kind == .falseElumi {
                if isCatchable && horizontalDistance <= 34 {
                    triggerHazardGameOver()
                    return
                }

                if progress >= 1.04 {
                    continue
                }

                survivors.append(snack)
                continue
            }

            if snack.kind == .saugglocke {
                if isCatchable && horizontalDistance <= 34 {
                    activateSuction(at: now)
                    triggerCatchAnimation()
                    continue
                }

                if progress >= 1.04 {
                    continue
                }

                survivors.append(snack)
                continue
            }

            if snack.kind == .bonusblase {
                if isCatchable && horizontalDistance <= 34 {
                    activateBonusPoints(at: now)
                    triggerCatchAnimation()
                    continue
                }

                if progress >= 1.04 {
                    continue
                }

                survivors.append(snack)
                continue
            }

            if isInSuctionBeam || (isCatchable && horizontalDistance <= 34) {
                earnedPoints += pointsForCaughtSnack(snack, at: now)
                caughtSnackCount += 1
                continue
            }

            if progress >= 1.04 {
                misses += 1
                missedAnySnack = true
                AudioServicesPlaySystemSound(1053) // Short "miss" sound
                continue
            }

            survivors.append(snack)
        }

        activeSnacks = survivors

        if caughtSnackCount > 0 {
            triggerCatchAnimation()
            if comboCount >= 3 || caughtSnackCount >= 2 {
                feedbackPlayer.playArcadeCombo()
            } else {
                feedbackPlayer.playSuccess()
            }
        }

        if earnedPoints > 0 {
            score += earnedPoints
            if score > highScore {
                didBeatHighScore = true
                highScore = score
            }
        }

        if caughtSnackCount > 0 {
            roundCatchCount += caughtSnackCount
            if roundCatchCount >= snacksForRound(round) && !showingRoundBanner {
                triggerRoundComplete()
            }
        }

        if missedAnySnack {
            resetCombo()
        }

        if misses >= maxMisses {
            gameOverTitle = "Game Over"
            gameOverSubtitle = "Alle Leben verbraucht."
            feedbackPlayer.playGameOver()
            isGameOver = true
            isPlaying = false
        }
    }

    @MainActor
    func resetGameState() {
        activeSnacks = []
        score = 0
        misses = 0
        elumiX = 0.5
        isPlaying = true
        isGameOver = false
        comboCount = 0
        totalCaught = 0
        bestCombo = 0
        lastCatchDate = nil
        gameClock = Date()
        lastFrameDate = nil
        comboBannerText = nil
        didBeatHighScore = false
        suctionEndsAt = nil
        bonusPointsEndsAt = nil
        slowMotionEndsAt = nil
        screenShakeOffset = 0
        gameOverTitle = "Game Over"
        gameOverSubtitle = ""
        mouthOpen = false
        characterScale = 1
        characterRotation = 0
        sparkleBurst = false
        round = 1
        roundCatchCount = 0
        roundSuctionSpawned = false
        showingRoundBanner = false
        roundBannerPhase = 0
        readyBlinkVisible = true
    }

    func runGameLoops() async {
        guard await MainActor.run(body: { !self.showingStartOverlay }) else { return }

        await MainActor.run {
            resetGameState()
            // Show "Runde 1 / Ready?" at game start
            showingRoundBanner = true
            roundBannerPhase = 1
            readyBlinkVisible = true
        }

        // Ready blink sequence
        for _ in 0..<3 {
            await MainActor.run { withAnimation(.easeInOut(duration: 0.25)) { readyBlinkVisible = false } }
            try? await Task.sleep(for: .milliseconds(300))
            await MainActor.run { withAnimation(.easeInOut(duration: 0.25)) { readyBlinkVisible = true } }
            try? await Task.sleep(for: .milliseconds(300))
        }
        try? await Task.sleep(for: .milliseconds(200))
        await MainActor.run { showingRoundBanner = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                while await MainActor.run(body: { self.isPlaying && !self.isGameOver }) {
                    let delay = await MainActor.run { currentSpawnDelay() }
                    try? await Task.sleep(for: .seconds(delay))
                    guard await MainActor.run(body: { self.isPlaying && !self.isGameOver }) else { break }
                    let isBannerUp = await MainActor.run { self.showingRoundBanner }
                    guard !isBannerUp else { continue }
                    await MainActor.run {
                        spawnSnack()
                    }
                }
            }

            group.addTask {
                while await MainActor.run(body: { self.isPlaying && !self.isGameOver }) {
                    await MainActor.run {
                        updateGame(now: Date())
                    }
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }
        }
    }
}

