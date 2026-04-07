import AVFoundation

enum FeedbackArcadeWaveform {
    case sine
    case square
    case triangle
}

struct FeedbackArcadeSegment {
    let startFrequency: Double
    let endFrequency: Double
    let duration: Double
    let amplitude: Double
    let waveform: FeedbackArcadeWaveform
    let noiseMix: Double
}

extension FeedbackPlayer {
    static func makeArcadeBuffer(
        format: AVAudioFormat?,
        sampleRate: Double,
        segments: [FeedbackArcadeSegment]
    ) -> AVAudioPCMBuffer? {
        guard let format else { return nil }

        let totalFrames = segments.reduce(0) { partialResult, segment in
            partialResult + Int(segment.duration * sampleRate)
        }

        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(totalFrames)
              ),
              let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        var frameIndex = 0
        for segment in segments {
            let segmentFrames = Int(segment.duration * sampleRate)
            guard segmentFrames > 0 else { continue }

            for sampleIndex in 0..<segmentFrames {
                let progress = Double(sampleIndex) / Double(segmentFrames)
                let attack = min(progress * 18, 1)
                let release = min((1 - progress) * 7, 1)
                let envelope = attack * release
                let time = Double(sampleIndex) / sampleRate
                let frequency = segment.startFrequency + ((segment.endFrequency - segment.startFrequency) * progress)
                let phase = 2 * Double.pi * frequency * time
                let tone: Double

                switch segment.waveform {
                case .sine:
                    tone = sin(phase)
                case .square:
                    tone = sin(phase) >= 0 ? 1 : -1
                case .triangle:
                    tone = (2 / Double.pi) * asin(sin(phase))
                }

                let noise = Double.random(in: -1...1) * segment.noiseMix
                let sample = (tone * (1 - segment.noiseMix) + noise) * segment.amplitude * envelope
                channelData[frameIndex] = Float(sample)
                frameIndex += 1
            }
        }

        buffer.frameLength = AVAudioFrameCount(frameIndex)
        return buffer
    }
}
