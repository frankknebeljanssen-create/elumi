import SwiftUI
import AVFoundation

extension FeedbackPlayer {

    private func playIfEnabled(_ name: String, volume: Float = 1.0) {
        guard areSoundsEnabled else { return }
        sp.play(name, volume: volume)
    }

    // ── UI / Navigation ──

    func playCardFlip() { playIfEnabled("cardflip") }
    func playScanStart() { playIfEnabled("scanstart", volume: 0.85) }
    func playScanProcessLoop() { guard areSoundsEnabled else { return }; sp.loop("scanprocess", volume: 0.16, rate: 0.5) }
    func stopScanProcessLoop() { sp.stop("scanprocess") }
    func playScanDone() { stopScanProcessLoop(); playIfEnabled("scandone", volume: 0.7) }
    func playAppStart() { playIfEnabled("appstart") }
    func playToggle() { playIfEnabled("toggle") }
    func playTabSwitch() { playIfEnabled("tabswitch") }
    func playListAction() { playIfEnabled("listaction") }
    func playFavStar() { playIfEnabled("favstar") }

    // ── Quiz ──

    func playQuizCorrect() { playIfEnabled("correct") }
    func playStudySuccess() { playIfEnabled("correct") }
    /// Sanft, deutlich leiser. User-Prinzip (Gamification-Auftrag):
    /// Fehler nicht bestrafen, nur sanft lenken. Lautstärke zentral
    /// aus `FeedbackConfig.negativeSoundVolume` — wenn später komplett
    /// stumm gewünscht ist, reicht das Flag `negativeSoundEnabled = false`
    /// und die Call-Site muss nichts ändern (siehe `playSoftError`).
    func playStudyError() {
        guard FeedbackConfig.negativeSoundEnabled else { return }
        playIfEnabled("wrong", volume: FeedbackConfig.negativeSoundVolume)
    }
    /// Expliziter Alias für Call-Sites, die klar machen wollen, dass sie
    /// den **weichen** Error-Ton wollen. Verhalten = `playStudyError`,
    /// nur anders benannt für selbst-dokumentierende Aufrufe.
    func playSoftError() { playStudyError() }
    func playStudyAchievement() { playIfEnabled("quizcomplete") }
    func playStreak() { playIfEnabled("streak") }
    func playLevelUp() { playIfEnabled("levelup") }

    // ── Flashcards ──

    func playFlashcardSuccess() { playIfEnabled("cardright") }
    func playFlashcardError() { playIfEnabled("cardwrong") }
    func playFlashcardAchievement() { playIfEnabled("stackcomplete") }

    // ── General ──

    func playSuccess() { playIfEnabled("snackcatch") }
    func playError() { playIfEnabled("error") }
    func playLaunch() { playIfEnabled("gamestart") }
    func playAchievement() { playIfEnabled("bonusbubble") }

    // ── Arcade ──

    func playArcadeCombo() { playIfEnabled("combo") }
    func playGameOver() { playIfEnabled("gameover") }
    func playSnackMiss() { playIfEnabled("snackmiss") }
    func playRoundClear() { playIfEnabled("roundclear") }
    func playHighScore() { playIfEnabled("highscore") }
    func playPowerUpSpawn() { playIfEnabled("powerupspawn") }
    func playSlowMotionActivate() { playIfEnabled("slowmostart") }
    func playSlowMotionEnd() { playIfEnabled("slowmoend") }
    func playShieldActivate() { playIfEnabled("shieldactivate") }
    func playShieldAbsorb() { playIfEnabled("shieldabsorb") }

    // ── Giftqualle ──

    func playJellyfishAppear() { playIfEnabled("jellyfish_appear", volume: 0.6) }
    func playJellyfishAmbientLoop() { guard areSoundsEnabled else { return }; sp.loop("jellyfish_ambient", volume: 0.25) }
    func stopJellyfishAmbient() { sp.stop("jellyfish_ambient") }
    func playTentacleDrop() { playIfEnabled("tentacle_drop", volume: 0.5) }
    func playTentacleSting() { playIfEnabled("tentacle_sting", volume: 0.7) }

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
