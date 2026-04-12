import SwiftUI

extension ElumiArcadeGameView {
    func spawnSnack() {
        let roll = Double.random(in: 0...1)
        let config = ArcadeRoundConfig(round: round)

        // Never spawn power-ups while one of the same type is on screen or active
        let suctionBlocked = activeSnacks.contains { $0.kind == .saugglocke } || hasActiveSuction()
        let potionBlocked = activeSnacks.contains { $0.kind == .slowMotionPotion } || hasActiveSlowMotion()

        // Guarantee at least 1 suction per round (after 1/3 of snacks caught)
        let thirdCount = config.snacksRequired / 3
        let forceSuction = !roundSuctionSpawned && roundCatchCount >= thirdCount && !suctionBlocked

        let kind: ElumiArcadeDropKind
        if forceSuction {
            kind = .saugglocke
            roundSuctionSpawned = true
        } else if roll < config.slowMotionPotionChance, !potionBlocked {
            kind = .slowMotionPotion
        } else if roll < config.slowMotionPotionChance + config.bonusChance {
            kind = .bonusblase
        } else if roll < config.slowMotionPotionChance + config.bonusChance + config.suctionChance, !suctionBlocked {
            kind = .saugglocke
            roundSuctionSpawned = true
        } else if roll < config.slowMotionPotionChance + config.bonusChance + config.suctionChance + config.falseElumiChance {
            kind = .falseElumi
        } else {
            kind = [.wuermchen, .wasserfloh, .algenkugel].randomElement() ?? .wuermchen
        }

        let querschlaegerChance = config.querschlaegerChance
        let isQuerschlaeger = kind.isSnack && Double.random(in: 0...1) < querschlaegerChance
        let wobbleAmp = isQuerschlaeger
            ? CGFloat.random(in: 0.15...0.25)
            : CGFloat.random(in: 0.01...0.05)
        let wobbleFreq = isQuerschlaeger
            ? Double.random(in: 4.0...6.5)
            : Double.random(in: 1.4...3.1)

        // Power-ups fall slower (easier to catch)
        let fallDuration = kind == .slowMotionPotion
            ? config.fallDuration * 1.3
            : config.fallDuration

        activeSnacks.append(
            ElumiArcadeSnackState(
                kind: kind,
                spawnedAt: gameClock,
                laneX: CGFloat.random(in: 0.12...0.88),
                wobbleAmplitude: wobbleAmp,
                wobbleFrequency: wobbleFreq,
                fallDuration: fallDuration,
                rotationDrift: Double.random(in: -18...18),
                renderScale: spawnRenderScale(for: kind),
                motionPhase: Double.random(in: 0...(Double.pi * 2)),
                points: snackPoints(for: kind)
            )
        )

        // Shimmer sound when a power-up spawns
        if kind == .slowMotionPotion || kind == .bonusblase || kind == .saugglocke {
            feedbackPlayer.playPowerUpSpawn()
        }
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

    func slowMotionSecondsRemaining(at date: Date = Date()) -> Int {
        guard let slowMotionEndsAt else { return 0 }
        return max(0, Int(ceil(slowMotionEndsAt.timeIntervalSince(date))))
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
        // Activation whir, then seamless transition to loop
        feedbackPlayer.playSuctionWhir()
        let loopDelay: TimeInterval = 0.7 // after whir fades
        let duration = suctionDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + loopDelay) {
            self.feedbackPlayer.playSuctionLoop()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.feedbackPlayer.stopSuctionLoop()
        }
    }

    func activateBonusPoints(at date: Date) {
        bonusPointsEndsAt = date.addingTimeInterval(bonusPointsDuration)
        showComboBanner("x2 Punkte aktiv")
        feedbackPlayer.playAchievement()
    }

    func endGame() {
        isGameOver = true
        isPlaying = false
        // Stop all sounds silently
        feedbackPlayer.sp.stop("saugloop")
        feedbackPlayer.sp.stop("bgm_fischfang")
        feedbackPlayer.stopBGM()
        feedbackPlayer.playGameOver()
        // Clear power-up state
        suctionEndsAt = nil
        bonusPointsEndsAt = nil
        slowMotionEndsAt = nil
        // Clear all snacks from screen
        activeSnacks = []
        // Hide Elumi
        withAnimation(.easeOut(duration: 0.25)) {
            elumiVisible = false
        }
    }

    func triggerHazardGameOver() {
        triggerScreenShake()
        gameOverTitle = "Freund gefressen!"
        gameOverSubtitle = "Das war ein Elumi-Freund — lass die vorbeischwimmen!"
        endGame()
    }

    func activateSlowMotion(at date: Date) {
        slowMotionEndsAt = date.addingTimeInterval(slowMotionDuration)
    }

    func activateSlowMotionPotion(at date: Date) {
        slowMotionEndsAt = date.addingTimeInterval(slowMotionPotionDuration)
        showComboBanner("Zeitlupe aktiviert")
        feedbackPlayer.playSlowMotionActivate()
    }

    func advanceGameClock(now: Date) -> Date {
        let previousFrameDate = lastFrameDate ?? now
        let delta = max(0, now.timeIntervalSince(previousFrameDate))
        lastFrameDate = now

        let motionScale = hasActiveSlowMotion(at: now) ? 0.4 : 1.0
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

    func showComboBanner(_ text: String, duration: Int = 900) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            comboBannerText = text
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(duration))
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
        feedbackPlayer.playRoundClear()

        Task { @MainActor in
            // Phase 0: "Runde X geschafft!" für 2s
            try? await Task.sleep(for: .seconds(2))
            guard showingRoundBanner else { return }

            // Bonus round every 3 rounds (after R3, R6, R9...)
            if ArcadeRoundConfig(round: round).isBonusRoundTrigger {
                showingRoundBanner = false
                startBonusRound()
                return
            }

            advanceToNextRound()
        }
    }

    func advanceToNextRound() {
        Task { @MainActor in
            round += 1
            roundCatchCount = 0
            roundSuctionSpawned = false
            roundBannerPhase = 1
            showingRoundBanner = true

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

    // ── BONUS FISH ROUND ──

    func startBonusRound() {
        isBonusRound = true
        bonusFishCaught = 0
        bonusFishSpawned = 0
        activeFish = []
        elumiY = 0.5
        bonusRoundStartedAt = Date()
        bonusRoundWaitingForTap = true
        feedbackPlayer.stopBGM()
        feedbackPlayer.playPowerUpSpawn()
    }

    func handleBonusRoundTap() {
        guard bonusRoundWaitingForTap else { return }

        if bonusFishSpawned == 0 && bonusRoundResultText == nil {
            // Tap to START fishing
            beginBonusFishSpawning()
        } else if bonusRoundResultText != nil {
            // Tap to CONTINUE after result
            bonusRoundWaitingForTap = false
            bonusRoundResultText = nil
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                elumiY = 0.5
            }
            advanceToNextRound()
        }
    }

    func beginBonusFishSpawning() {
        bonusRoundWaitingForTap = false
        feedbackPlayer.sp.loop("bgm_fischfang")

        Task { @MainActor in
            for i in 0..<bonusFishTotal {
                guard isBonusRound, !isGameOver else { break }
                spawnBonusFish()
                bonusFishSpawned = i + 1
                try? await Task.sleep(for: .milliseconds(800))
            }

            try? await Task.sleep(for: .seconds(2.0))
            guard isBonusRound else { return }
            endBonusRound()
        }
    }

    func spawnBonusFish() {
        let fromLeft = Bool.random()
        activeFish.append(BonusFishState(
            spawnedAt: Date(),
            fromLeft: fromLeft,
            normalizedY: CGFloat.random(in: 0.15...0.75),
            speed: Double.random(in: 0.7...1.6),
            wobblePhase: Double.random(in: 0...(Double.pi * 2)),
            renderScale: CGFloat.random(in: 1.0...3.0)
        ))
    }

    func updateBonusRound(now: Date) {
        guard isBonusRound, gameSize != .zero else { return }

        let elumiPos = CGPoint(
            x: elumiPositionX(in: gameSize.width),
            y: elumiPositionY(in: gameSize.height)
        )

        var updated = activeFish
        for i in updated.indices {
            guard !updated[i].isCaught else { continue }
            let fishPos = fishPosition(for: updated[i], at: now, in: gameSize)
            let dist = hypot(fishPos.x - elumiPos.x, fishPos.y - elumiPos.y)
            if dist <= 42 {
                updated[i].isCaught = true
                bonusFishCaught += 1
                feedbackPlayer.playSuccess()
                // Catch animation
                withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                    mouthOpen = true
                    characterScale = 1.06
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        self.mouthOpen = false
                        self.characterScale = 1
                    }
                }
            }
        }

        // Remove fish that left the screen (progress > 1.2)
        updated.removeAll { fish in
            if fish.isCaught { return true }
            let elapsed = now.timeIntervalSince(fish.spawnedAt)
            return elapsed / fish.speed > 1.3
        }

        activeFish = updated
    }

    func endBonusRound() {
        isBonusRound = false
        activeFish = []
        feedbackPlayer.sp.stop("bgm_fischfang")
        feedbackPlayer.startBGM()

        let success = bonusFishCaught >= Int(Double(bonusFishTotal) * 0.8) // 80%

        if success {
            misses = max(0, misses - 1)
            feedbackPlayer.playHighScore()
        } else {
            feedbackPlayer.playRoundClear()
        }

        // Show bonus result — tap to continue
        comboBannerText = nil
        bonusRoundResultText = success
            ? "🎉 +1 Leben! (\(bonusFishCaught)/\(bonusFishTotal) Fische)"
            : "🐟 \(bonusFishCaught)/\(bonusFishTotal) Fische gefangen"
        bonusRoundWaitingForTap = true
    }

    func updateGame(now: Date) {
        guard gameSize != .zero else { return }

        // Bonus round uses its own update logic
        if isBonusRound {
            updateBonusRound(now: now)
            return
        }

        if let suctionEndsAt, suctionEndsAt <= now {
            self.suctionEndsAt = nil
        }
        if let bonusPointsEndsAt, bonusPointsEndsAt <= now {
            self.bonusPointsEndsAt = nil
        }
        if let slowMotionEndsAt, slowMotionEndsAt <= now {
            self.slowMotionEndsAt = nil
            feedbackPlayer.playSlowMotionEnd()
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

            if snack.kind == .slowMotionPotion {
                if isCatchable && horizontalDistance <= 34 {
                    activateSlowMotionPotion(at: now)
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
                feedbackPlayer.playSnackMiss()
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
                if !didBeatHighScore {
                    feedbackPlayer.playHighScore()
                }
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
            gameOverSubtitle = ""
            endGame()
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
        feedbackPlayer.startBGM()
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
        isBonusRound = false
        activeFish = []
        bonusFishCaught = 0
        bonusFishSpawned = 0
        elumiY = 0.5
        bonusRoundStartedAt = nil
        bonusRoundResultText = nil
        bonusRoundWaitingForTap = false
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

