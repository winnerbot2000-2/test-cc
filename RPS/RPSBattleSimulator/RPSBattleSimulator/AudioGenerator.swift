import AVFoundation
import Foundation

/// Synthesizes audio samples for conversion pop sounds.
/// Used to bake audio into exported MP4 files.
struct AudioGenerator {
    
    static let sampleRate: Double = 44100
    
    /// Generate a pop sound audio buffer (soft sine chirp, 650Hz -> 220Hz over 80ms).
    /// Returns PCM samples (mono Float32) for one pop sound.
    static func generatePopSamples(amplitude: Float = 0.14) -> [Float] {
        let duration = 0.11  // seconds
        let sampleCount = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: sampleCount)
        
        for i in 0..<sampleCount {
            let t = Double(i) / sampleRate
            // Frequency ramp: 650 -> 220 over 0.08s
            let freqRampDur = 0.08
            let frac = min(t / freqRampDur, 1.0)
            let freq = 650.0 + (220.0 - 650.0) * frac
            
            // Gain envelope: 0.14 -> ~0 over 0.1s
            let gainRampDur = 0.10
            let gainFrac = min(t / gainRampDur, 1.0)
            let gainEnv = Float(Double(amplitude) * exp(-gainFrac * 6.9))
            
            samples[i] = gainEnv * Float(sin(2 * Double.pi * freq * t))
        }
        
        return samples
    }
    
    /// Mix conversion events into an audio PCM buffer.
    static func mixAudio(
        conversionEvents: [(timestamp: Double, count: Int)],
        totalDuration: Double
    ) -> [Float] {
        let totalSamples = max(Int(totalDuration * sampleRate) + 4096, 44100)
        var mixed = [Float](repeating: 0, count: totalSamples)
        
        let popSamples = generatePopSamples()
        
        for event in conversionEvents {
            let startSample = max(0, Int(event.timestamp * sampleRate))
            let amp = Float(min(Double(event.count) * 0.5, 1.0))
            
            for (j, sample) in popSamples.enumerated() {
                let idx = startSample + j
                if idx < mixed.count {
                    mixed[idx] += sample * amp
                }
            }
        }
        
        // Normalize to prevent clipping
        let maxVal = mixed.map { abs($0) }.max() ?? 1.0
        if maxVal > 0.95 {
            let scale = 0.95 / maxVal
            for i in mixed.indices { mixed[i] *= scale }
        }
        
        return mixed
    }
    
    /// Create an AVAudioPCMBuffer from mono Float32 samples.
    static func makePCMBuffer(from samples: [Float], sampleRate: Double = AudioGenerator.sampleRate) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard let fmt = format,
              let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        buffer.frameLength = buffer.frameCapacity
        if let channelData = buffer.floatChannelData?[0] {
            for (i, s) in samples.enumerated() {
                channelData[i] = s
            }
        }
        return buffer
    }
}
