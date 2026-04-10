import SwiftUI
import AVFoundation

extension FeedbackPlayer {
    func playCardFlip() {
        guard areSoundsEnabled else { return }
        play(cardFlipBuffer)
    }

    func playScanStart() {
        guard areSoundsEnabled else { return }
        play(scanStartBuffer)
    }

    func playScanDone() {
        guard areSoundsEnabled else { return }
        play(scanDoneBuffer)
    }

    func playAppStart() {
        guard areSoundsEnabled else { return }
        play(appStartBuffer)
    }

    func playToggle() {
        guard areSoundsEnabled else { return }
        play(toggleBuffer)
    }

    func playTabSwitch() {
        guard areSoundsEnabled else { return }
        play(tabSwitchBuffer)
    }

    func playListAction() {
        guard areSoundsEnabled else { return }
        play(listActionBuffer)
    }

    func playFavStar() {
        guard areSoundsEnabled else { return }
        play(favStarBuffer)
    }

    func playSuccess() {
        guard areSoundsEnabled else { return }
        play(successBuffer)
    }

    func playError() {
        guard areSoundsEnabled else { return }
        play(errorBuffer)
    }

    func playLaunch() {
        guard areSoundsEnabled else { return }
        play(launchBuffer)
    }

    func playAchievement() {
        guard areSoundsEnabled else { return }
        play(achievementBuffer)
    }

    func playQuizCorrect() {
        guard areSoundsEnabled else { return }
        play(flashcardSuccessBuffer)
    }

    func playStudySuccess() {
        guard areSoundsEnabled else { return }
        play(flashcardSuccessBuffer)
    }

    func playStudyError() {
        guard areSoundsEnabled else { return }
        play(flashcardErrorBuffer)
    }

    func playStudyAchievement() {
        guard areSoundsEnabled else { return }
        play(flashcardAchievementBuffer)
    }

    func playArcadeCombo() {
        guard areSoundsEnabled else { return }
        play(arcadeComboBuffer)
    }

    func playGameOver() {
        guard areSoundsEnabled else { return }
        play(gameOverBuffer)
    }

    func playSlowMotionActivate() {
        guard areSoundsEnabled else { return }
        play(slowMotionActivateBuffer)
    }

    func playSlowMotionEnd() {
        guard areSoundsEnabled else { return }
        play(slowMotionEndBuffer)
    }

    func playSnackMiss() {
        guard areSoundsEnabled else { return }
        play(snackMissBuffer)
    }

    func playRoundClear() {
        guard areSoundsEnabled else { return }
        play(roundClearBuffer)
    }

    func playHighScore() {
        guard areSoundsEnabled else { return }
        play(highScoreBuffer)
    }

    func playPowerUpSpawn() {
        guard areSoundsEnabled else { return }
        play(powerUpSpawnBuffer)
    }

    func playShieldActivate() {
        guard areSoundsEnabled else { return }
        play(shieldActivateBuffer)
    }

    func playShieldAbsorb() {
        guard areSoundsEnabled else { return }
        play(shieldAbsorbBuffer)
    }

    func playSuctionWhir() {
        // saugstart: one-shot on playerNode (not loopPlayerNode!)
        guard areSoundsEnabled else { return }
        play(suctionWhirBuffer)
    }

    func playSuctionLoop() {
        guard areSoundsEnabled, let buffer = suctionLoopBuffer else { return }

        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {}

        configureEngineIfNeeded(for: buffer.format)
        guard let loopPlayerNode else { return }
        startEngineIfNeeded()
        guard engine?.isRunning == true else { return }
        loopPlayerNode.stop()
        loopPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        loopPlayerNode.play()
    }

    func stopSuctionLoop() {
        loopPlayerNode?.stop()
        // Play wind-down pitch drop on the regular player node
        play(suctionWindDownBuffer)
    }

    func playFlashcardSuccess() {
        guard areSoundsEnabled else { return }
        play(flashcardSuccessBuffer)
    }

    func playFlashcardError() {
        guard areSoundsEnabled else { return }
        play(flashcardErrorBuffer)
    }

    func playFlashcardAchievement() {
        guard areSoundsEnabled else { return }
        play(flashcardAchievementBuffer)
    }

    func toggleSoundsFromQuickAction() {
        let newValue = !areSoundsEnabled
        areSoundsEnabled = newValue
        if newValue { playToggle() }
        showSoundToggleToast(
            message: newValue ? "Ton an" : "Ton aus",
            systemImage: newValue ? "speaker.wave.2.fill" : "speaker.slash.fill"
        )
    }

    func startBGM() {
        guard areSoundsEnabled, let buffer = bgmBuffer else { return }

        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {}

        configureEngineIfNeeded(for: buffer.format)
        guard let bgmPlayerNode else { return }
        startEngineIfNeeded()
        guard engine?.isRunning == true else { return }
        bgmPlayerNode.stop()
        bgmPlayerNode.volume = 0.15
        bgmPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        bgmPlayerNode.play()
    }

    func stopBGM() {
        bgmPlayerNode?.stop()
    }

    func stopAllFeedback() {
        playerNode?.stop()
    }

    func showSoundToggleToast(message: String, systemImage: String) {
        soundToastDismissWorkItem?.cancel()
        soundToggleToast = SoundToggleToast(message: message, systemImage: systemImage)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.soundToggleToast = nil
            }
        }
        soundToastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    func play(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }

        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {}

        configureEngineIfNeeded(for: buffer.format)
        guard let playerNode else { return }
        startEngineIfNeeded()
        guard engine?.isRunning == true else { return }

        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        playerNode.play()
    }

    func configureEngineIfNeeded(for format: AVAudioFormat) {
        guard !isConfigured else { return }
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let loopNode = AVAudioPlayerNode()
        let bgmNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.attach(loopNode)
        engine.attach(bgmNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.connect(loopNode, to: engine.mainMixerNode, format: format)
        engine.connect(bgmNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        self.engine = engine
        self.playerNode = playerNode
        self.loopPlayerNode = loopNode
        self.bgmPlayerNode = bgmNode
        isConfigured = true
    }

    func startEngineIfNeeded() {
        guard let engine else { return }
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            // If the engine fails to start, the app should still function without feedback tones.
        }
    }
}
