import Foundation
import AVFoundation

public enum SynthWaveType: String, Codable, Sendable, CaseIterable, Identifiable {
    case sine
    case square
    case triangle
    case saw
    case whiteNoise

    public var id: String { rawValue }
}

public struct SynthParameters: Codable, Sendable, Equatable {
    public var wave: SynthWaveType
    public var frequency: Float
    public var duration: Double
    public var amplitude: Float

    // Envelope
    public var attack: Double
    public var decay: Double
    public var sustain: Float
    public var release: Double

    // Tone shaping
    public var harmonics: Float
    public var detune: Float
    public var saturation: Float

    // Stereo
    public var stereoWidth: Float
    public var pan: Float

    public init(
        wave: SynthWaveType = .triangle,
        frequency: Float = 440,
        duration: Double = 0.18,
        amplitude: Float = 0.18,
        attack: Double = 0.008,
        decay: Double = 0.040,
        sustain: Float = 0.78,
        release: Double = 0.120,
        harmonics: Float = 0.22,
        detune: Float = 0.003,
        saturation: Float = 1.20,
        stereoWidth: Float = 0.06,
        pan: Float = 0
    ) {
        self.wave = wave
        self.frequency = frequency
        self.duration = duration
        self.amplitude = amplitude
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
        self.harmonics = harmonics
        self.detune = detune
        self.saturation = saturation
        self.stereoWidth = stereoWidth
        self.pan = pan
    }
}

public struct SavedSynthPreset: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var params: SynthParameters

    public init(id: String = UUID().uuidString, name: String, params: SynthParameters) {
        self.id = id
        self.name = name
        self.params = params
    }
}

public struct AudioSynthesizer {

    // MARK: - Legacy-compatible API

    public static func generate(
        wave: SynthWaveType,
        freq: Float,
        duration: Double,
        amp: Float,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let params = SynthParameters(
            wave: wave,
            frequency: freq,
            duration: duration,
            amplitude: amp
        )
        return generate(params: params, format: format)
    }

    // MARK: - Sound Lab / Advanced API

    public static func generate(
        params: SynthParameters,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)

        let safeDuration = max(0.008, params.duration)
        let safeAmp = max(0, min(params.amplitude, 1))
        let safeFreq = max(20, params.frequency)
        let safeAttack = max(0.001, params.attack)
        let safeDecay = max(0.001, params.decay)
        let safeSustain = max(0, min(params.sustain, 1))
        let safeRelease = max(0.001, params.release)
        let safeHarmonics = max(0, min(params.harmonics, 2.5))
        let safeDetune = max(0, min(params.detune, 0.03))
        let safeSaturation = max(0.5, min(params.saturation, 3.0))
        let safeStereoWidth = max(0, min(params.stereoWidth, 1.0))
        let safePan = max(-1, min(params.pan, 1))

        let frameCount = AVAudioFrameCount(sampleRate * safeDuration)

        guard frameCount > 0 else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return nil }

        let totalFrames = Int(frameCount)
        let attackFrames = max(1, Int(sampleRate * safeAttack))
        let decayFrames = max(1, Int(sampleRate * safeDecay))
        let releaseFrames = max(1, Int(sampleRate * safeRelease))
        let releaseStart = max(attackFrames + decayFrames, totalFrames - releaseFrames)

        let detuneA = Double(safeFreq) * Double(1.0 - safeDetune)
        let detuneB = Double(safeFreq) * Double(1.0 + safeDetune)
        let detuneC = Double(safeFreq)

        let deltaA = (2.0 * Double.pi * detuneA) / sampleRate
        let deltaB = (2.0 * Double.pi * detuneB) / sampleRate
        let deltaC = (2.0 * Double.pi * detuneC) / sampleRate

        var phaseA: Double = 0
        var phaseB: Double = 0
        var phaseC: Double = 0

        var noiseState: UInt64 = 0x12345678ABCDEF

        for i in 0..<totalFrames {
            let t = Double(i) / sampleRate

            let baseA = oscillatorSample(
                wave: params.wave,
                phase: phaseA,
                time: t,
                frequency: detuneA,
                noiseState: &noiseState
            )

            let baseB = oscillatorSample(
                wave: params.wave,
                phase: phaseB,
                time: t,
                frequency: detuneB,
                noiseState: &noiseState
            )

            let overtone = oscillatorSample(
                wave: params.wave,
                phase: phaseC * 1.5,
                time: t,
                frequency: detuneC * 1.5,
                noiseState: &noiseState
            )

            let fundamental = Float((baseA * 0.58) + (baseB * 0.28))
            let harmonicLayer = Float(overtone) * safeHarmonics * 0.35
            let airLayer = Float(sin(phaseC * 2.0)) * 0.08

            let rawSample = fundamental + harmonicLayer + airLayer
            let env = envelope(
                frame: i,
                totalFrames: totalFrames,
                attackFrames: attackFrames,
                decayFrames: decayFrames,
                sustainLevel: safeSustain,
                releaseStart: releaseStart
            )

            let transientBoost: Float = i < max(1, attackFrames / 2) ? 1.05 : 1.0
            let saturated = tanhClipped(rawSample * safeAmp * env * transientBoost * safeSaturation)

            let spread = stereoSpreadValue(
                for: i,
                total: totalFrames,
                width: safeStereoWidth
            )

            for c in 0..<channelCount {
                let gain: Float
                if channelCount == 1 {
                    gain = 1.0
                } else {
                    let basePan = c % 2 == 0 ? (-safePan) : safePan
                    let combinedPan = max(-1, min(1, basePan + (c % 2 == 0 ? -spread : spread)))
                    gain = panGain(for: combinedPan, isLeftChannel: c % 2 == 0)
                }

                channelData[c][i] = saturated * gain
            }

            phaseA += deltaA
            phaseB += deltaB
            phaseC += deltaC

            if phaseA > (2.0 * Double.pi) { phaseA.formTruncatingRemainder(dividingBy: 2.0 * Double.pi) }
            if phaseB > (2.0 * Double.pi) { phaseB.formTruncatingRemainder(dividingBy: 2.0 * Double.pi) }
            if phaseC > (2.0 * Double.pi) { phaseC.formTruncatingRemainder(dividingBy: 2.0 * Double.pi) }
        }

        return buffer
    }

    // MARK: - Export Helpers

    public static func exportJSONString(for params: SynthParameters) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(params) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func exportSwiftSnippet(named name: String, params: SynthParameters) -> String {
        """
        let \(name) = SynthParameters(
            wave: .\(params.wave.rawValue),
            frequency: \(String(format: "%.2f", params.frequency)),
            duration: \(String(format: "%.3f", params.duration)),
            amplitude: \(String(format: "%.3f", params.amplitude)),
            attack: \(String(format: "%.3f", params.attack)),
            decay: \(String(format: "%.3f", params.decay)),
            sustain: \(String(format: "%.3f", params.sustain)),
            release: \(String(format: "%.3f", params.release)),
            harmonics: \(String(format: "%.3f", params.harmonics)),
            detune: \(String(format: "%.4f", params.detune)),
            saturation: \(String(format: "%.3f", params.saturation)),
            stereoWidth: \(String(format: "%.3f", params.stereoWidth)),
            pan: \(String(format: "%.3f", params.pan))
        )
        """
    }

    // MARK: - Private DSP

    private static func oscillatorSample(
        wave: SynthWaveType,
        phase: Double,
        time: Double,
        frequency: Double,
        noiseState: inout UInt64
    ) -> Double {
        switch wave {
        case .sine:
            return sin(phase)

        case .square:
            return sin(phase) >= 0 ? 1.0 : -1.0

        case .triangle:
            return (2.0 / Double.pi) * asin(sin(phase))

        case .saw:
            let cycle = (time * frequency).truncatingRemainder(dividingBy: 1.0)
            return (2.0 * cycle) - 1.0

        case .whiteNoise:
            return Double(nextNoiseSample(state: &noiseState))
        }
    }

    private static func envelope(
        frame: Int,
        totalFrames: Int,
        attackFrames: Int,
        decayFrames: Int,
        sustainLevel: Float,
        releaseStart: Int
    ) -> Float {
        if frame < attackFrames {
            return Float(Double(frame) / Double(attackFrames))
        }

        if frame < attackFrames + decayFrames {
            let decayProgress = Double(frame - attackFrames) / Double(max(1, decayFrames))
            return Float(1.0 - ((1.0 - Double(sustainLevel)) * decayProgress))
        }

        if frame >= releaseStart {
            let releaseProgress = Double(frame - releaseStart) / Double(max(1, totalFrames - releaseStart))
            return Float(max(0.0, Double(sustainLevel) * (1.0 - releaseProgress)))
        }

        return sustainLevel
    }

    private static func nextNoiseSample(state: inout UInt64) -> Float {
        state = state &* 6364136223846793005 &+ 1
        let upper = UInt32((state >> 32) & 0xFFFFFFFF)
        let normalized = (Double(upper) / Double(UInt32.max)) * 2.0 - 1.0
        return Float(normalized)
    }

    private static func tanhClipped(_ x: Float) -> Float {
        Float(tanh(Double(x)))
    }

    private static func stereoSpreadValue(
        for index: Int,
        total: Int,
        width: Float
    ) -> Float {
        guard total > 1 else { return 0 }
        let progress = Float(index) / Float(total - 1)
        let centered = (progress - 0.5) * 2.0
        return centered * width * 0.08
    }

    private static func panGain(for pan: Float, isLeftChannel: Bool) -> Float {
        let normalizedPan = max(-1, min(1, pan))
        let angle = (normalizedPan + 1) * (.pi / 4)
        return isLeftChannel ? cos(angle) : sin(angle)
    }
}
