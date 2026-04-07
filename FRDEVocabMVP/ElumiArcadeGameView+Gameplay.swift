import SwiftUI

extension ElumiArcadeGameView {
    func spawnSnack() {
        let roll = Double.random(in: 0...1)
        let bonusChance = 0.055
        let falseElumiChance = min(0.12, 0.04 + (Double(level - 1) * 0.01))
        let suctionChance = 0.07

        let kind: ElumiArcadeDropKind
        if roll < bonusChance {
            kind = .bonusblase
        } else if roll < bonusChance + suctionChance {
            kind = .saugglocke
        } else if roll < bonusChance + suctionChance + falseElumiChance {
            kind = .falseElumi
        } else {
            kind = [.wuermchen, .wasserfloh, .algenkugel].randomElement() ?? .wuermchen
        }

        activeSnacks.append(
            ElumiArcadeSnackState(
                kind: kind,
                spawnedAt: gameClock,
                laneX: CGFloat.random(in: 0.12...0.88),
                wobbleAmplitude: CGFloat.random(in: 0.01...0.05),
                wobbleFrequency: Double.random(in: 1.4...3.1),
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
        gameSeed = UUID()
    }

    func restartGame() {
        showingStartOverlay = false
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
        activateSlowMotion(at: date)
        suctionEndsAt = date.addingTimeInterval(suctionDuration)
        showComboBanner("Saugstrahl aktiviert")
        feedbackPlayer.playAchievement()
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

        let comboBonus = comboCount >= 2 ? min(24, (comboCount - 1) * 3) : 0
        if comboCount >= 2 {
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
            let catchLineY = gameSize.height - 126
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
                continue
            }

            survivors.append(snack)
        }

        activeSnacks = survivors

        if caughtSnackCount > 0 {
            triggerCatchAnimation()
            if comboCount >= 2 || caughtSnackCount >= 2 {
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

        if missedAnySnack {
            resetCombo()
        }

        if misses >= maxMisses {
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
        gameOverTitle = "Elumi ist satt"
        gameOverSubtitle = "Ein starker Lauf."
        mouthOpen = false
        characterScale = 1
        characterRotation = 0
        sparkleBurst = false
    }

    func runGameLoops() async {
        guard await MainActor.run(body: { !self.showingStartOverlay }) else { return }

        await MainActor.run {
            resetGameState()
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                while await MainActor.run(body: { self.isPlaying && !self.isGameOver }) {
                    let delay = await MainActor.run { currentSpawnDelay() }
                    try? await Task.sleep(for: .seconds(delay))
                    guard await MainActor.run(body: { self.isPlaying && !self.isGameOver }) else { break }
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

