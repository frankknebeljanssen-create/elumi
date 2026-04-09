import AVFoundation

extension FeedbackPlayer {
    var arcadeFormat: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    }

    func makeLaunchBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 520, endFrequency: 620, duration: 0.035, amplitude: 0.18, waveform: .square, noiseMix: 0.01),
                FeedbackArcadeSegment(startFrequency: 780, endFrequency: 920, duration: 0.04, amplitude: 0.18, waveform: .square, noiseMix: 0.01),
                FeedbackArcadeSegment(startFrequency: 1180, endFrequency: 1420, duration: 0.05, amplitude: 0.19, waveform: .triangle, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1680, endFrequency: 2140, duration: 0.11, amplitude: 0.2, waveform: .triangle, noiseMix: 0.0)
            ]
        )
    }

    func makeSuccessBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 988, endFrequency: 1046, duration: 0.04, amplitude: 0.2, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1480, duration: 0.05, amplitude: 0.21, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1760, endFrequency: 2093, duration: 0.085, amplitude: 0.18, waveform: .triangle, noiseMix: 0.0)
            ]
        )
    }

    func makeErrorBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 310, endFrequency: 250, duration: 0.05, amplitude: 0.19, waveform: .square, noiseMix: 0.02),
                FeedbackArcadeSegment(startFrequency: 220, endFrequency: 160, duration: 0.085, amplitude: 0.2, waveform: .square, noiseMix: 0.04),
                FeedbackArcadeSegment(startFrequency: 150, endFrequency: 105, duration: 0.13, amplitude: 0.18, waveform: .triangle, noiseMix: 0.07)
            ]
        )
    }

    func makeAchievementBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 1046, endFrequency: 1180, duration: 0.04, amplitude: 0.19, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1318, endFrequency: 1480, duration: 0.045, amplitude: 0.2, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1568, endFrequency: 1760, duration: 0.05, amplitude: 0.2, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1975, endFrequency: 2217, duration: 0.06, amplitude: 0.21, waveform: .triangle, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 2637, endFrequency: 2794, duration: 0.12, amplitude: 0.18, waveform: .triangle, noiseMix: 0.01)
            ]
        )
    }

    func makeFlashcardSuccessBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 523, endFrequency: 523, duration: 0.08, amplitude: 0.038, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.11, amplitude: 0.044, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.16, amplitude: 0.036, waveform: .sine, noiseMix: 0.0)
            ]
        )
    }

    func makeFlashcardErrorBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 392, endFrequency: 370, duration: 0.08, amplitude: 0.035, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 349, endFrequency: 330, duration: 0.12, amplitude: 0.032, waveform: .sine, noiseMix: 0.0)
            ]
        )
    }

    func makeFlashcardAchievementBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 523, endFrequency: 523, duration: 0.075, amplitude: 0.04, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 659, endFrequency: 659, duration: 0.085, amplitude: 0.046, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 784, endFrequency: 784, duration: 0.1, amplitude: 0.05, waveform: .sine, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 988, endFrequency: 988, duration: 0.18, amplitude: 0.042, waveform: .sine, noiseMix: 0.0)
            ]
        )
    }

    func makeQuizCoinBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 1320, endFrequency: 1460, duration: 0.03, amplitude: 0.18, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1760, endFrequency: 1980, duration: 0.045, amplitude: 0.2, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 2280, endFrequency: 2520, duration: 0.055, amplitude: 0.16, waveform: .triangle, noiseMix: 0.0)
            ]
        )
    }

    func makeArcadeComboBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 880, endFrequency: 1046, duration: 0.03, amplitude: 0.16, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1174, endFrequency: 1318, duration: 0.03, amplitude: 0.17, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1396, endFrequency: 1568, duration: 0.032, amplitude: 0.18, waveform: .square, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 1760, endFrequency: 1975, duration: 0.038, amplitude: 0.18, waveform: .triangle, noiseMix: 0.0),
                FeedbackArcadeSegment(startFrequency: 2093, endFrequency: 2349, duration: 0.08, amplitude: 0.17, waveform: .triangle, noiseMix: 0.01)
            ]
        )
    }

    func makeGameOverBuffer() -> AVAudioPCMBuffer? {
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                FeedbackArcadeSegment(startFrequency: 420, endFrequency: 330, duration: 0.045, amplitude: 0.18, waveform: .square, noiseMix: 0.03),
                FeedbackArcadeSegment(startFrequency: 310, endFrequency: 240, duration: 0.06, amplitude: 0.2, waveform: .square, noiseMix: 0.04),
                FeedbackArcadeSegment(startFrequency: 235, endFrequency: 180, duration: 0.075, amplitude: 0.21, waveform: .triangle, noiseMix: 0.05),
                FeedbackArcadeSegment(startFrequency: 172, endFrequency: 120, duration: 0.14, amplitude: 0.18, waveform: .triangle, noiseMix: 0.08)
            ]
        )
    }

    func makeSuctionWhirBuffer() -> AVAudioPCMBuffer? {
        // Whirring suction sound: higher frequencies for phone speaker, heavy noise
        Self.makeArcadeBuffer(
            format: arcadeFormat,
            sampleRate: sampleRate,
            segments: [
                // Startup whir — ramps up
                FeedbackArcadeSegment(startFrequency: 400, endFrequency: 800, duration: 0.25, amplitude: 0.25, waveform: .square, noiseMix: 0.6),
                // Steady suction whir — mostly noise with tonal drone
                FeedbackArcadeSegment(startFrequency: 800, endFrequency: 900, duration: 0.8, amplitude: 0.30, waveform: .square, noiseMix: 0.7),
                FeedbackArcadeSegment(startFrequency: 900, endFrequency: 800, duration: 0.8, amplitude: 0.28, waveform: .square, noiseMix: 0.7),
                FeedbackArcadeSegment(startFrequency: 800, endFrequency: 850, duration: 0.8, amplitude: 0.30, waveform: .square, noiseMix: 0.65),
                FeedbackArcadeSegment(startFrequency: 850, endFrequency: 800, duration: 0.8, amplitude: 0.28, waveform: .square, noiseMix: 0.65),
                // Wind down
                FeedbackArcadeSegment(startFrequency: 800, endFrequency: 300, duration: 0.4, amplitude: 0.20, waveform: .square, noiseMix: 0.5),
            ]
        )
    }
}
