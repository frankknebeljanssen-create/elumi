import SwiftUI
import AVFoundation

extension FeedbackPlayer {

    // ── UI / Navigation ──

    func playCardFlip() { guard areSoundsEnabled else { return }; sp.play("cardflip") }
    func playScanStart() { guard areSoundsEnabled else { return }; sp.play("scanstart", volume: 0.5) }
    func playScanDone() { guard areSoundsEnabled else { return }; sp.play("scandone", volume: 0.35) }
    func playAppStart() { guard areSoundsEnabled else { return }; sp.play("appstart") }
    func playToggle() { guard areSoundsEnabled else { return }; sp.play("toggle") }
    func playTabSwitch() { guard areSoundsEnabled else { return }; sp.play("tabswitch") }
    func playListAction() { guard areSoundsEnabled else { return }; sp.play("listaction") }
    func playFavStar() { guard areSoundsEnabled else { return }; sp.play("favstar") }

    // ── Quiz ──

    func playQuizCorrect() { guard areSoundsEnabled else { return }; sp.play("correct") }
    func playStudySuccess() { guard areSoundsEnabled else { return }; sp.play("correct") }
    func playStudyError() { guard areSoundsEnabled else { return }; sp.play("wrong") }
    func playStudyAchievement() { guard areSoundsEnabled else { return }; sp.play("quizcomplete") }
    func playStreak() { guard areSoundsEnabled else { return }; sp.play("streak") }
    func playLevelUp() { guard areSoundsEnabled else { return }; sp.play("levelup") }

    // ── Flashcards ──

    func playFlashcardSuccess() { guard areSoundsEnabled else { return }; sp.play("cardright") }
    func playFlashcardError() { guard areSoundsEnabled else { return }; sp.play("cardwrong") }
    func playFlashcardAchievement() { guard areSoundsEnabled else { return }; sp.play("stackcomplete") }

    // ── General ──

    func playSuccess() { guard areSoundsEnabled else { return }; sp.play("snackcatch") }
    func playError() { guard areSoundsEnabled else { return }; sp.play("error") }
    func playLaunch() { guard areSoundsEnabled else { return }; sp.play("gamestart") }
    func playAchievement() { guard areSoundsEnabled else { return }; sp.play("bonusbubble") }

    // ── Arcade ──

    func playArcadeCombo() { guard areSoundsEnabled else { return }; sp.play("combo") }
    func playGameOver() { guard areSoundsEnabled else { return }; sp.play("gameover") }
    func playSnackMiss() { guard areSoundsEnabled else { return }; sp.play("snackmiss") }
    func playRoundClear() { guard areSoundsEnabled else { return }; sp.play("roundclear") }
    func playHighScore() { guard areSoundsEnabled else { return }; sp.play("highscore") }
    func playPowerUpSpawn() { guard areSoundsEnabled else { return }; sp.play("powerupspawn") }
    func playSlowMotionActivate() { guard areSoundsEnabled else { return }; sp.play("slowmostart") }
    func playSlowMotionEnd() { guard areSoundsEnabled else { return }; sp.play("slowmoend") }
    func playShieldActivate() { guard areSoundsEnabled else { return }; sp.play("shieldactivate") }
    func playShieldAbsorb() { guard areSoundsEnabled else { return }; sp.play("shieldabsorb") }

    // ── Saugglocke ──

    func playSuctionWhir() { guard areSoundsEnabled else { return }; sp.play("saugstart") }
    func playSuctionLoop() { guard areSoundsEnabled else { return }; sp.loop("saugloop") }
    func stopSuctionLoop() {
        sp.stop("saugloop")
        guard areSoundsEnabled else { return }
        sp.play("saugend")
    }

    // ── BGM (AVAudioEngine — programmatic buffer) ──

    func startBGM() {
        guard areSoundsEnabled, let buffer = bgmBuffer else { return }

        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {}

        configureBGMEngineIfNeeded(for: buffer.format)
        guard let bgmPlayerNode, engine?.isRunning == true else { return }
        bgmPlayerNode.stop()
        bgmPlayerNode.volume = 0.15
        bgmPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        bgmPlayerNode.play()
    }

    func stopBGM() {
        bgmPlayerNode?.stop()
    }

    // ── Engine (only for BGM) ──

    func configureBGMEngineIfNeeded(for format: AVAudioFormat) {
        guard !isBGMConfigured else { return }
        let engine = AVAudioEngine()
        let bgmNode = AVAudioPlayerNode()
        engine.attach(bgmNode)
        engine.connect(bgmNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do { try engine.start() } catch {}
        self.engine = engine
        self.bgmPlayerNode = bgmNode
        isBGMConfigured = true
    }

    // ── Global ──

    func stopAllFeedback() {
        sp.stopAll()
        bgmPlayerNode?.stop()
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
}
