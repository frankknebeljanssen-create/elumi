import AVFoundation

extension FeedbackPlayer {
    var arcadeFormat: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    }

    // ── UI / NAVIGATION ──

    func makeCardFlipBuffer() -> AVAudioPCMBuffer? {
        // cardflip: Soft swoosh G4 + airy D6 tail (from Tone.js FMSynth)
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 392, endFrequency: 440, duration: 0.05, amplitude: 0.14, waveform: .sine, noiseMix: 0.03),
                FeedbackArcadeSegment(startFrequency: 1174, endFrequency: 1250, duration: 0.04, amplitude: 0.08, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makeScanStartBuffer() -> AVAudioPCMBuffer? {
        // scanstart: Camera shutter click — short percussive snap
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 1800, endFrequency: 800, duration: 0.02, amplitude: 0.20, waveform: .sine, noiseMix: 0.30),
                FeedbackArcadeSegment(startFrequency: 600, endFrequency: 300, duration: 0.03, amplitude: 0.12, waveform: .sine, noiseMix: 0.15),
            ]
        )
    }

    func makeScanDoneBuffer() -> AVAudioPCMBuffer? {
        // scandone: Bright result ping — ascending E5→A5
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.06, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 880, endFrequency: 880, duration: 0.10, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
            ]
        )
    }

    func makeAppStartBuffer() -> AVAudioPCMBuffer? {
        // appstart: Warm welcome jingle — short C5→E5→G5
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 523, endFrequency: 523, duration: 0.06, amplitude: 0.12, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.06, amplitude: 0.13, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.10, amplitude: 0.11, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makeToggleBuffer() -> AVAudioPCMBuffer? {
        // toggle: Subtle soft click — very short sine pop
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 1200, endFrequency: 900, duration: 0.02, amplitude: 0.10, waveform: .sine, noiseMix: 0.0),
            ]
        )
    }

    func makeTabSwitchBuffer() -> AVAudioPCMBuffer? {
        // tabswitch: Quick light tap — slightly higher than toggle
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 1400, endFrequency: 1100, duration: 0.02, amplitude: 0.08, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makeListActionBuffer() -> AVAudioPCMBuffer? {
        // listaction: Soft confirmation swoosh
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 600, endFrequency: 800, duration: 0.04, amplitude: 0.12, waveform: .sine, noiseMix: 0.02),
                FeedbackArcadeSegment(startFrequency: 800, endFrequency: 700, duration: 0.06, amplitude: 0.08, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makeFavStarBuffer() -> AVAudioPCMBuffer? {
        // favstar: Sparkly star ping — bright and tiny
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 1568, endFrequency: 1568, duration: 0.03, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 2093, endFrequency: 2200, duration: 0.05, amplitude: 0.10, waveform: .sine, noiseMix: 0.02),
            ]
        )
    }

    // ── SPIELABLAUF ──

    func makeLaunchBuffer() -> AVAudioPCMBuffer? {
        // gamestart: Ascending warm FM notes C4→E4→G4→C5→E5 + bright chord
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 262, endFrequency: 262, duration: 0.06, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 330, endFrequency: 330, duration: 0.06, amplitude: 0.17, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 392, endFrequency: 392, duration: 0.06, amplitude: 0.18, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 523, endFrequency: 523, duration: 0.06, amplitude: 0.19, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.07, amplitude: 0.20, waveform: .sine, noiseMix: 0.0),
                // Bright chord bloom
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.05, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1046, endFrequency: 1046, duration: 0.05, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1318, duration: 0.12, amplitude: 0.12, waveform: .triangle, noiseMix: 0.01),
            ]
        )
    }

    func makeSuccessBuffer() -> AVAudioPCMBuffer? {
        // snackcatch: Crystal bell A5 + tiny shimmer E6
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 880, endFrequency: 880, duration: 0.06, amplitude: 0.20, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1400, duration: 0.08, amplitude: 0.14, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makeErrorBuffer() -> AVAudioPCMBuffer? {
        // wrong: Gentle descending minor — soft disappointment
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 392, endFrequency: 370, duration: 0.08, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 349, endFrequency: 330, duration: 0.10, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 262, endFrequency: 247, duration: 0.14, amplitude: 0.12, waveform: .sine, noiseMix: 0.02),
            ]
        )
    }

    func makeAchievementBuffer() -> AVAudioPCMBuffer? {
        // bonusbubble: Bright fanfare E5→G5→B5→E6 + bloom chord
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.055, amplitude: 0.18, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.055, amplitude: 0.19, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 988, endFrequency: 988, duration: 0.06, amplitude: 0.20, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1318, duration: 0.08, amplitude: 0.21, waveform: .sine, noiseMix: 0.0),
                // Bloom sustain
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.06, amplitude: 0.10, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 831, endFrequency: 831, duration: 0.06, amplitude: 0.10, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 988, endFrequency: 988, duration: 0.14, amplitude: 0.08, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    // ── LERN-APP / QUIZ / FLASHCARDS ──

    func makeFlashcardSuccessBuffer() -> AVAudioPCMBuffer? {
        // correct: Warm ascending C5→E5→G5
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 523, endFrequency: 523, duration: 0.08, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.10, amplitude: 0.18, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.14, amplitude: 0.15, waveform: .sine, noiseMix: 0.0),
            ]
        )
    }

    func makeFlashcardErrorBuffer() -> AVAudioPCMBuffer? {
        // wrong: Gentle descending G4→F4
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 392, endFrequency: 370, duration: 0.08, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 349, endFrequency: 330, duration: 0.12, amplitude: 0.12, waveform: .sine, noiseMix: 0.0),
            ]
        )
    }

    func makeFlashcardAchievementBuffer() -> AVAudioPCMBuffer? {
        // stackcomplete / streak: Ascending C5→E5→G5→B5
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 523, endFrequency: 523, duration: 0.07, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.08, amplitude: 0.18, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.09, amplitude: 0.19, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 988, endFrequency: 988, duration: 0.16, amplitude: 0.16, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makeQuizCoinBuffer() -> AVAudioPCMBuffer? {
        // xpgain: Crystal bell — same character as snackcatch but higher
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 1046, endFrequency: 1046, duration: 0.05, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1568, endFrequency: 1660, duration: 0.07, amplitude: 0.14, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makeArcadeComboBuffer() -> AVAudioPCMBuffer? {
        // combo: Rapid ascending scale E5→G5→A5→B5→D6→E6 + sparkle peak
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.03, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.03, amplitude: 0.17, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 880, endFrequency: 880, duration: 0.03, amplitude: 0.18, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 988, endFrequency: 988, duration: 0.03, amplitude: 0.18, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1174, endFrequency: 1174, duration: 0.035, amplitude: 0.19, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1318, duration: 0.04, amplitude: 0.20, waveform: .sine, noiseMix: 0.0),
                // Sparkle at peak
                FeedbackArcadeSegment(startFrequency: 3136, endFrequency: 3322, duration: 0.06, amplitude: 0.12, waveform: .sine, noiseMix: 0.02),
            ]
        )
    }

    func makeGameOverBuffer() -> AVAudioPCMBuffer? {
        // gameover: Gentle descending minor pads Em→Dm→Cm
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                // Em chord
                FeedbackArcadeSegment(startFrequency: 330, endFrequency: 330, duration: 0.12, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 392, endFrequency: 392, duration: 0.12, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
                // Dm chord
                FeedbackArcadeSegment(startFrequency: 294, endFrequency: 294, duration: 0.12, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 349, endFrequency: 349, duration: 0.12, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
                // Cm chord — final sadness
                FeedbackArcadeSegment(startFrequency: 262, endFrequency: 262, duration: 0.14, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 311, endFrequency: 311, duration: 0.14, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 392, endFrequency: 350, duration: 0.20, amplitude: 0.10, waveform: .sine, noiseMix: 0.02),
            ]
        )
    }

    func makeSlowMotionActivateBuffer() -> AVAudioPCMBuffer? {
        // slowmostart: Descending G5→120Hz sweep + warbly D5→80Hz + deep C2 sub
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                // Main descending sweep
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 300, duration: 0.18, amplitude: 0.20, waveform: .sine, noiseMix: 0.0),
                // Warbly layer
                FeedbackArcadeSegment(startFrequency: 587, endFrequency: 150, duration: 0.15, amplitude: 0.14, waveform: .triangle, noiseMix: 0.03),
                // Deep sub tone arriving
                FeedbackArcadeSegment(startFrequency: 120, endFrequency: 65, duration: 0.12, amplitude: 0.18, waveform: .sine, noiseMix: 0.0),
            ]
        )
    }

    func makeSlowMotionEndBuffer() -> AVAudioPCMBuffer? {
        // Ascending speed-up: low → high, world snapping back to normal speed
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 200, endFrequency: 500, duration: 0.06, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 500, endFrequency: 900, duration: 0.08, amplitude: 0.18, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 900, endFrequency: 1400, duration: 0.10, amplitude: 0.20, waveform: .triangle, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1400, endFrequency: 1800, duration: 0.06, amplitude: 0.16, waveform: .triangle, noiseMix: 0.02),
            ]
        )
    }

    func makeSnackMissBuffer() -> AVAudioPCMBuffer? {
        // Dull "bonk" — low thud, short and punchy
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 98, endFrequency: 72, duration: 0.06, amplitude: 0.28, waveform: .sine, noiseMix: 0.15),
                FeedbackArcadeSegment(startFrequency: 72, endFrequency: 50, duration: 0.10, amplitude: 0.18, waveform: .sine, noiseMix: 0.25),
            ]
        )
    }

    func makeRoundClearBuffer() -> AVAudioPCMBuffer? {
        // Mini fanfare: G5→B5→D6→G6 ascending triumph
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.07, amplitude: 0.18, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 988, endFrequency: 988, duration: 0.07, amplitude: 0.19, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1174, endFrequency: 1174, duration: 0.08, amplitude: 0.20, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1568, endFrequency: 1568, duration: 0.12, amplitude: 0.21, waveform: .triangle, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1568, endFrequency: 1760, duration: 0.18, amplitude: 0.16, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makeHighScoreBuffer() -> AVAudioPCMBuffer? {
        // Grand fanfare: C5→E5→G5→C6→E6→G6 with sparkle tail
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 523, endFrequency: 523, duration: 0.05, amplitude: 0.17, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.05, amplitude: 0.18, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.05, amplitude: 0.19, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1046, endFrequency: 1046, duration: 0.06, amplitude: 0.20, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1318, duration: 0.06, amplitude: 0.20, waveform: .triangle, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1568, endFrequency: 1568, duration: 0.08, amplitude: 0.21, waveform: .triangle, noiseMix: 0.0),
                // Sparkle shimmer tail
                FeedbackArcadeSegment(startFrequency: 2637, endFrequency: 2794, duration: 0.05, amplitude: 0.14, waveform: .sine, noiseMix: 0.02),
                FeedbackArcadeSegment(startFrequency: 3136, endFrequency: 3520, duration: 0.06, amplitude: 0.10, waveform: .sine, noiseMix: 0.03),
                FeedbackArcadeSegment(startFrequency: 2093, endFrequency: 2349, duration: 0.12, amplitude: 0.12, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makePowerUpSpawnBuffer() -> AVAudioPCMBuffer? {
        // Magical shimmer: twinkling high bells E6→G6→B6→E7
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1400, duration: 0.04, amplitude: 0.12, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1568, endFrequency: 1660, duration: 0.04, amplitude: 0.13, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1975, endFrequency: 2093, duration: 0.04, amplitude: 0.14, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 2637, endFrequency: 2794, duration: 0.06, amplitude: 0.12, waveform: .triangle, noiseMix: 0.01),
                FeedbackArcadeSegment(startFrequency: 3136, endFrequency: 3322, duration: 0.08, amplitude: 0.10, waveform: .triangle, noiseMix: 0.02),
            ]
        )
    }

    func makeShieldActivateBuffer() -> AVAudioPCMBuffer? {
        // Glass ping: bright crystalline E6 with harmonic overtone
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1318, duration: 0.03, amplitude: 0.20, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1975, endFrequency: 1975, duration: 0.04, amplitude: 0.16, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 3951, endFrequency: 3951, duration: 0.05, amplitude: 0.10, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1200, duration: 0.20, amplitude: 0.08, waveform: .sine, noiseMix: 0.01),
            ]
        )
    }

    func makeShieldAbsorbBuffer() -> AVAudioPCMBuffer? {
        // Dull crack/knack: low impact + glass resonance
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 110, endFrequency: 70, duration: 0.03, amplitude: 0.30, waveform: .sine, noiseMix: 0.35),
                FeedbackArcadeSegment(startFrequency: 523, endFrequency: 440, duration: 0.08, amplitude: 0.14, waveform: .sine, noiseMix: 0.08),
                FeedbackArcadeSegment(startFrequency: 440, endFrequency: 350, duration: 0.12, amplitude: 0.08, waveform: .sine, noiseMix: 0.04),
            ]
        )
    }

    func makeSuctionLoopBuffer() -> AVAudioPCMBuffer? {
        // saugloop: Continuous humming drone D3 with LFO-like shimmer + pink noise texture
        guard let format = arcadeFormat else { return nil }
        let duration = 0.8 // Seamless loop segment
        let totalFrames = Int(duration * sampleRate)
        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(totalFrames)
              ),
              let channelData = buffer.floatChannelData?[0] else { return nil }

        let baseFreq = 147.0    // D3
        let shimmerFreq = 880.0 // A4 shimmer layer
        let amplitude = 0.18
        let noiseMix = 0.20

        for i in 0..<totalFrames {
            let time = Double(i) / sampleRate
            // LFO modulation on modulation index (simulates Tone.js LFO)
            let lfo = sin(2 * Double.pi * 3.0 * time) * 0.3 + 1.0
            let dronePhase = 2 * Double.pi * baseFreq * time
            let drone = sin(dronePhase) * 0.7 * lfo
            let shimmerPhase = 2 * Double.pi * shimmerFreq * time
            let shimmer = sin(shimmerPhase) * 0.15
            let noise = Double.random(in: -1...1) * noiseMix
            let sample = (drone + shimmer + noise) * amplitude
            channelData[i] = Float(sample)
        }

        buffer.frameLength = AVAudioFrameCount(totalFrames)
        return buffer
    }

    func makeSuctionWindDownBuffer() -> AVAudioPCMBuffer? {
        // saugend: Pitch drop A4→50Hz + air release + final thud
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                // Sweep down
                FeedbackArcadeSegment(startFrequency: 440, endFrequency: 120, duration: 0.30, amplitude: 0.20, waveform: .sine, noiseMix: 0.20),
                // Air release noise
                FeedbackArcadeSegment(startFrequency: 120, endFrequency: 60, duration: 0.25, amplitude: 0.14, waveform: .sine, noiseMix: 0.45),
                // Final low thud
                FeedbackArcadeSegment(startFrequency: 65, endFrequency: 40, duration: 0.10, amplitude: 0.22, waveform: .sine, noiseMix: 0.15),
            ]
        )
    }

    // ── BGM ──

    func makeBGMBuffer() -> AVAudioPCMBuffer? {
        guard let format = arcadeFormat else { return nil }

        let bpm = 90.0
        let beatDuration = 60.0 / bpm
        let sixteenthDuration = beatDuration / 4.0
        let barDuration = beatDuration * 4
        let totalDuration = barDuration * 4
        let totalFrames = Int(totalDuration * sampleRate)

        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(totalFrames)
              ),
              let channelData = buffer.floatChannelData?[0] else { return nil }

        for i in 0..<totalFrames { channelData[i] = 0 }

        func timeOfs(bar: Int, beat: Int, sixteenth: Int = 0) -> Double {
            Double(bar) * barDuration + Double(beat) * beatDuration + Double(sixteenth) * sixteenthDuration
        }

        let noteFreqs: [String: Double] = [
            "C2": 65.4, "E2": 82.4, "F2": 87.3, "G2": 98.0, "A2": 110.0,
            "A3": 220.0, "B3": 246.9, "C4": 261.6, "D4": 293.7, "E4": 329.6,
            "F3": 174.6, "G3": 196.0,
            "C5": 523.3, "D5": 587.3, "E5": 659.3, "G5": 784.0, "A5": 880.0, "B5": 987.8,
        ]

        let rhythmDurs: [String: Double] = [
            "4n": beatDuration, "4n.": beatDuration * 1.5, "8n": beatDuration * 0.5,
            "8n.": beatDuration * 0.75, "2n": beatDuration * 2, "1m": barDuration,
        ]

        func addNote(freq: Double, start: Double, dur: Double, amp: Double,
                     atk: Double = 0.06, dec: Double = 0.3, sus: Double = 0.2, rel: Double = 0.6) {
            let sf = Int(start * sampleRate)
            let nf = Int((dur + rel) * sampleRate)
            let df = Int(dur * sampleRate)
            let af = Int(atk * sampleRate)
            let dcf = Int(dec * sampleRate)
            for i in 0..<nf {
                let fi = sf + i
                guard fi >= 0, fi < totalFrames else { continue }
                let t = Double(i) / sampleRate
                let tone = sin(2 * Double.pi * freq * t)
                let env: Double
                if i < af { env = Double(i) / Double(max(1, af)) }
                else if i < af + dcf { env = 1.0 - (1.0 - sus) * Double(i - af) / Double(max(1, dcf)) }
                else if i < df { env = sus }
                else { env = sus * max(0, 1.0 - Double(i - df) / Double(max(1, Int(rel * sampleRate)))) }
                channelData[fi] += Float(tone * amp * env)
            }
        }

        // Melody
        for m in [
            ("E5","4n",0,0,0),("G5","8n",0,1,0),("A5","8n.",0,1,2),("E5","4n",0,2,2),("D5","8n",0,3,2),
            ("C5","4n",1,0,0),("E5","8n",1,1,0),("G5","4n.",1,1,2),("A5","4n",1,3,0),
            ("B5","4n",2,0,0),("A5","8n",2,1,0),("G5","4n",2,1,2),("E5","4n.",2,3,0),
            ("D5","4n",3,0,0),("E5","8n",3,1,0),("G5","4n",3,1,2),("A5","2n",3,2,2),
        ] as [(String,String,Int,Int,Int)] {
            addNote(freq: noteFreqs[m.0] ?? 440, start: timeOfs(bar: m.2, beat: m.3, sixteenth: m.4),
                    dur: rhythmDurs[m.1] ?? beatDuration, amp: 0.10, atk: 0.06, dec: 0.3, sus: 0.2, rel: 0.6)
        }

        // Pad chords
        for (notes, bar) in [(["C4","E4","G5"],0),(["A3","C4","E4"],1),(["F3","A3","C4"],2),(["G3","B3","D4"],3)] as [([String],Int)] {
            for n in notes {
                addNote(freq: noteFreqs[n] ?? 440, start: timeOfs(bar: bar, beat: 0),
                        dur: barDuration, amp: 0.05, atk: 0.3, dec: 0.8, sus: 0.4, rel: 1.2)
            }
        }

        // Bass
        for (n, bar, beat) in [("C2",0,0),("G2",0,2),("A2",1,0),("E2",1,2),("F2",2,0),("C2",2,2),("G2",3,0),("G2",3,2)] as [(String,Int,Int)] {
            addNote(freq: noteFreqs[n] ?? 65, start: timeOfs(bar: bar, beat: beat),
                    dur: beatDuration * 2, amp: 0.08, atk: 0.05, dec: 0.3, sus: 0.3, rel: 0.5)
        }

        // Soft limiter
        for i in 0..<totalFrames {
            channelData[i] = min(0.9, max(-0.9, channelData[i]))
        }

        buffer.frameLength = AVAudioFrameCount(totalFrames)
        return buffer
    }

    // ── SAUGGLOCKE ──

    func makeSuctionWhirBuffer() -> AVAudioPCMBuffer? {
        // saugstart: Ascending FM vortex sweep C3→800Hz + swirl + filtered whoosh
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                // Ascending vortex whir
                FeedbackArcadeSegment(startFrequency: 130, endFrequency: 400, duration: 0.15, amplitude: 0.20, waveform: .sine, noiseMix: 0.15),
                FeedbackArcadeSegment(startFrequency: 400, endFrequency: 800, duration: 0.25, amplitude: 0.24, waveform: .sine, noiseMix: 0.25),
                // Swirl peak
                FeedbackArcadeSegment(startFrequency: 392, endFrequency: 600, duration: 0.15, amplitude: 0.16, waveform: .triangle, noiseMix: 0.20),
                // Filtered whoosh tail
                FeedbackArcadeSegment(startFrequency: 600, endFrequency: 900, duration: 0.20, amplitude: 0.14, waveform: .sine, noiseMix: 0.40),
            ]
        )
    }
}
