import SwiftUI
import AVFoundation

extension FeedbackPlayer {
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

    func playSuctionWhir() {
        guard areSoundsEnabled, let buffer = suctionWhirBuffer else { return }

        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {}

        configureEngineIfNeeded(for: buffer.format)
        guard let loopPlayerNode else { return }
        startEngineIfNeeded()
        loopPlayerNode.stop()
        loopPlayerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        loopPlayerNode.play()
    }

    func stopSuctionWhir() {
        loopPlayerNode?.stop()
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
        showSoundToggleToast(
            message: newValue ? "Ton an" : "Ton aus",
            systemImage: newValue ? "speaker.wave.2.fill" : "speaker.slash.fill"
        )
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
        } catch {
            // If audio session setup fails, skip reconfiguration and still attempt playback.
        }

        configureEngineIfNeeded(for: buffer.format)
        guard let playerNode else { return }
        startEngineIfNeeded()
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        playerNode.play()
    }

    func configureEngineIfNeeded(for format: AVAudioFormat) {
        guard !isConfigured else { return }
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let loopNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.attach(loopNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.connect(loopNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        self.engine = engine
        self.playerNode = playerNode
        self.loopPlayerNode = loopNode
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
