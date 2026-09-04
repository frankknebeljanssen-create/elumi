import AVFoundation

// BGM is the only programmatically generated buffer (10s loop, too large as WAV asset).
// All other sounds use WAV files via SoundPlayer.

extension FeedbackPlayer {
    var arcadeFormat: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    }

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

        for m in [
            ("E5","4n",0,0,0),("G5","8n",0,1,0),("A5","8n.",0,1,2),("E5","4n",0,2,2),("D5","8n",0,3,2),
            ("C5","4n",1,0,0),("E5","8n",1,1,0),("G5","4n.",1,1,2),("A5","4n",1,3,0),
            ("B5","4n",2,0,0),("A5","8n",2,1,0),("G5","4n",2,1,2),("E5","4n.",2,3,0),
            ("D5","4n",3,0,0),("E5","8n",3,1,0),("G5","4n",3,1,2),("A5","2n",3,2,2),
        ] as [(String,String,Int,Int,Int)] {
            addNote(freq: noteFreqs[m.0] ?? 440, start: timeOfs(bar: m.2, beat: m.3, sixteenth: m.4),
                    dur: rhythmDurs[m.1] ?? beatDuration, amp: 0.10, atk: 0.06, dec: 0.3, sus: 0.2, rel: 0.6)
        }

        for (notes, bar) in [(["C4","E4","G4"],0),(["A3","C4","E4"],1),(["F3","A3","C4"],2),(["G3","B3","D4"],3)] as [([String],Int)] {
            for n in notes {
                addNote(freq: noteFreqs[n] ?? 440, start: timeOfs(bar: bar, beat: 0),
                        dur: barDuration, amp: 0.05, atk: 0.3, dec: 0.8, sus: 0.4, rel: 1.2)
            }
        }

        for (n, bar, beat) in [("C2",0,0),("G2",0,2),("A2",1,0),("E2",1,2),("F2",2,0),("C2",2,2),("G2",3,0),("G2",3,2)] as [(String,Int,Int)] {
            addNote(freq: noteFreqs[n] ?? 65, start: timeOfs(bar: bar, beat: beat),
                    dur: beatDuration * 2, amp: 0.08, atk: 0.05, dec: 0.3, sus: 0.3, rel: 0.5)
        }

        for i in 0..<totalFrames {
            channelData[i] = min(0.9, max(-0.9, channelData[i]))
        }

        buffer.frameLength = AVAudioFrameCount(totalFrames)
        return buffer
    }
}
