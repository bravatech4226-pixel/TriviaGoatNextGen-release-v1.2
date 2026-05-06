//
//  SpatialAudioManager.swift
//  TriviaGoatNextGen
//
//  PREMIUM STATE-AWARE AUDIO SYSTEM
//  Cinematic • Context-aware • Low-fatigue • 4D arena environment
//

import Foundation
import AVFoundation
import UIKit
import QuartzCore

enum AudioState: Equatable {
    case idle
    case hq
    case lobby
    case matchCalm
    case matchPressure
    case reveal
    case victory
    case defeat
}

@MainActor
final class SpatialAudioManager {

    static let shared = SpatialAudioManager()

    private let engine = AVAudioEngine()

    private let cueNode = AVAudioPlayerNode()
    private let rewardNode = AVAudioPlayerNode()
    private let xpLoopNode = AVAudioPlayerNode()

    private let ambientNode = AVAudioPlayerNode()
    private let ambientTextureNode = AVAudioPlayerNode()
    private let ambientAirNode = AVAudioPlayerNode()

    private let cueMixer = AVAudioMixerNode()
    private let ambientMixer = AVAudioMixerNode()

    private let cueEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let cueDelay = AVAudioUnitDelay()
    private let cueReverb = AVAudioUnitReverb()

    private let ambientEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let ambientReverb = AVAudioUnitReverb()

    private let mixer: AVAudioMixerNode

    private var isRunning = false
    private var xpLoopActive = false
    private var ambientActive = false

    private var currentState: AudioState = .idle
    private var lastCueTimestamps: [AudioCue: TimeInterval] = [:]
    private var lastAmbientIntensity: Float = 0

    private let cueCooldowns: [AudioCue: TimeInterval] = [
        .uiTap: 0.04,
        .countdownTick: 0.08,
        .dangerPulse: 0.45,
        .lockIn: 0.10,
        .victory: 0.65
    ]

    private init() {
        mixer = engine.mainMixerNode

        engine.attach(cueNode)
        engine.attach(rewardNode)
        engine.attach(xpLoopNode)

        engine.attach(ambientNode)
        engine.attach(ambientTextureNode)
        engine.attach(ambientAirNode)

        engine.attach(cueMixer)
        engine.attach(ambientMixer)

        engine.attach(cueEQ)
        engine.attach(cueDelay)
        engine.attach(cueReverb)

        engine.attach(ambientEQ)
        engine.attach(ambientReverb)

        engine.connect(cueNode, to: cueMixer, format: nil)
        engine.connect(rewardNode, to: cueMixer, format: nil)
        engine.connect(cueMixer, to: cueEQ, format: nil)
        engine.connect(cueEQ, to: cueDelay, format: nil)
        engine.connect(cueDelay, to: cueReverb, format: nil)
        engine.connect(cueReverb, to: mixer, format: nil)

        engine.connect(xpLoopNode, to: mixer, format: nil)

        engine.connect(ambientNode, to: ambientMixer, format: nil)
        engine.connect(ambientTextureNode, to: ambientMixer, format: nil)
        engine.connect(ambientAirNode, to: ambientMixer, format: nil)
        engine.connect(ambientMixer, to: ambientEQ, format: nil)
        engine.connect(ambientEQ, to: ambientReverb, format: nil)
        engine.connect(ambientReverb, to: mixer, format: nil)

        cueNode.volume = 0.90
        rewardNode.volume = 0.88
        xpLoopNode.volume = 0.0

        ambientNode.volume = 0.065
        ambientTextureNode.volume = 0.038
        ambientAirNode.volume = 0.026

        cueMixer.outputVolume = 1.0
        ambientMixer.outputVolume = 1.0
        mixer.outputVolume = 1.0

        configureFX()
        configureSession()
        start()
    }

    // MARK: - State-Aware Audio

    func transition(to newState: AudioState, force: Bool = false) {
        guard force || newState != currentState else { return }

        currentState = newState
        ensureRunning()

        switch newState {
        case .idle:
            stopAll()

        case .hq:
            stopArenaAmbient()
            stopXPCountLoop()
            cueNode.volume = 0.70

        case .lobby:
            startArenaAmbient(intensity: 0.70, force: force)
            ambientNode.volume = 0.048
            ambientTextureNode.volume = 0.026
            ambientAirNode.volume = 0.016
            stopXPCountLoop()

        case .matchCalm:
            startArenaAmbient(intensity: 0.86, force: force)
            ambientNode.volume = 0.060
            ambientTextureNode.volume = 0.030
            ambientAirNode.volume = 0.020
            stopXPCountLoop()

        case .matchPressure:
            rampAmbient(to: 1.18)
            ambientNode.volume = 0.084
            ambientTextureNode.volume = 0.040
            ambientAirNode.volume = 0.025
            stopXPCountLoop()
            play(.dangerPulse)

        case .reveal:
            ambientNode.volume = 0.044
            ambientTextureNode.volume = 0.020
            ambientAirNode.volume = 0.012
            stopXPCountLoop()
            playWarpTrigger()

        case .victory:
            stopAmbient()
            stopXPCountLoop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                self.playFinalVictory()
            }

        case .defeat:
            stopAmbient()
            stopXPCountLoop()
            play(.wrong)
        }
    }

    // MARK: - Public Cue API

    func play(_ cue: AudioCue) {
        ensureRunning()
        guard engine.isRunning else { return }

        guard shouldPlay(cue) else { return }
        lastCueTimestamps[cue] = CACurrentMediaTime()

        guard let buffer = makeBuffer(for: cue) else { return }

        setCueVolume(for: cue)
        tuneCueFX(for: cue)

        cueNode.stop()
        cueNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        cueNode.play()

        triggerHaptics(for: cue)
    }

    func playXPClaim() {
        ensureRunning()
        guard engine.isRunning else { return }

        let format = mixer.outputFormat(forBus: 0)
        let params = SynthParameters(
            wave: .sine,
            frequency: 540,
            duration: 0.12,
            amplitude: 0.052,
            attack: 0.006,
            decay: 0.025,
            sustain: 0.48,
            release: 0.12,
            harmonics: 0.07,
            detune: 0.0008,
            saturation: 0.94,
            stereoWidth: 0.34,
            pan: softPan()
        )

        guard let buffer = AudioSynthesizer.generate(params: params, format: format) else { return }

        rewardNode.volume = 0.54
        cueDelay.wetDryMix = 5
        cueDelay.feedback = 6
        cueReverb.wetDryMix = 6

        rewardNode.stop()
        rewardNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        rewardNode.play()

        HapticManager.instance.impact(.light)
    }

    func playStreakMilestone() {
        ensureRunning()
        guard engine.isRunning else { return }

        let format = mixer.outputFormat(forBus: 0)

        let main = SynthParameters(
            wave: .sine,
            frequency: 594,
            duration: 0.28,
            amplitude: 0.074,
            attack: 0.010,
            decay: 0.045,
            sustain: 0.62,
            release: 0.24,
            harmonics: 0.24,
            detune: 0.0012,
            saturation: 0.96,
            stereoWidth: 0.72,
            pan: softPan()
        )

        let shimmer = SynthParameters(
            wave: .sine,
            frequency: 792,
            duration: 0.22,
            amplitude: 0.035,
            attack: 0.016,
            decay: 0.050,
            sustain: 0.48,
            release: 0.22,
            harmonics: 0.18,
            detune: 0.0018,
            saturation: 0.94,
            stereoWidth: 0.88,
            pan: -softPan()
        )

        guard let mainBuffer = AudioSynthesizer.generate(params: main, format: format) else { return }

        rewardNode.volume = 0.70
        cueDelay.wetDryMix = 9
        cueDelay.feedback = 10
        cueReverb.wetDryMix = 14

        rewardNode.stop()
        rewardNode.scheduleBuffer(mainBuffer, at: nil, options: .interrupts)

        if let shimmerBuffer = AudioSynthesizer.generate(params: shimmer, format: format) {
            let delay = AVAudioTime(
                sampleTime: AVAudioFramePosition(0.11 * format.sampleRate),
                atRate: format.sampleRate
            )
            rewardNode.scheduleBuffer(shimmerBuffer, at: delay, options: [])
        }

        rewardNode.play()
        HapticManager.instance.successPulse()
    }

    func playFinalVictory() {
        ensureRunning()
        guard engine.isRunning else { return }

        let format = mixer.outputFormat(forBus: 0)

        let body = SynthParameters(
            wave: .sine,
            frequency: 523.25,
            duration: 0.64,
            amplitude: 0.105,
            attack: 0.018,
            decay: 0.070,
            sustain: 0.72,
            release: 0.44,
            harmonics: 0.62,
            detune: 0.002,
            saturation: 1.00,
            stereoWidth: 0.95,
            pan: 0
        )

        let lift = SynthParameters(
            wave: .triangle,
            frequency: 784,
            duration: 0.42,
            amplitude: 0.044,
            attack: 0.020,
            decay: 0.060,
            sustain: 0.54,
            release: 0.34,
            harmonics: 0.38,
            detune: 0.0022,
            saturation: 0.98,
            stereoWidth: 1.0,
            pan: 0.12
        )

        guard let bodyBuffer = AudioSynthesizer.generate(params: body, format: format) else {
            play(.victory)
            return
        }

        rewardNode.volume = 0.88
        cueDelay.wetDryMix = 13
        cueDelay.feedback = 13
        cueReverb.wetDryMix = 22

        rewardNode.stop()
        rewardNode.scheduleBuffer(bodyBuffer, at: nil, options: .interrupts)

        if let liftBuffer = AudioSynthesizer.generate(params: lift, format: format) {
            let delay = AVAudioTime(
                sampleTime: AVAudioFramePosition(0.14 * format.sampleRate),
                atRate: format.sampleRate
            )
            rewardNode.scheduleBuffer(liftBuffer, at: delay, options: [])
        }

        rewardNode.play()
        HapticManager.instance.successPulse()
    }

    func playCustom(params: SynthParameters) {
        ensureRunning()
        guard engine.isRunning else { return }

        let format = mixer.outputFormat(forBus: 0)
        guard let buffer = AudioSynthesizer.generate(params: params, format: format) else { return }

        cueNode.volume = 0.72
        tuneCustomCueFX(using: params)

        cueNode.stop()
        cueNode.scheduleBuffer(buffer, at: nil, options: .interrupts)
        cueNode.play()
    }

    func playWarpTrigger() {
        guard let params = manifestParams(for: "trigger_warp_001") else {
            play(.tieBreak)
            return
        }

        playCustom(params: params)
    }

    private func shouldPlay(_ cue: AudioCue) -> Bool {
        guard let cooldown = cueCooldowns[cue] else { return true }

        let now = CACurrentMediaTime()
        let last = lastCueTimestamps[cue] ?? 0

        return now - last > cooldown
    }

    private func setCueVolume(for cue: AudioCue) {
        switch cue {
        case .uiTap:
            cueNode.volume = 0.54
        case .lockIn:
            cueNode.volume = 0.88
        case .correct:
            cueNode.volume = 0.86
        case .wrong:
            cueNode.volume = 0.64
        case .countdownTick:
            cueNode.volume = 0.60
        case .dangerPulse:
            cueNode.volume = 0.62
        case .tieBreak:
            cueNode.volume = 0.78
        case .victory:
            cueNode.volume = 0.82
        }
    }
    
    private func rampAmbient(to target: Float) {
        startArenaAmbient(intensity: target, force: true)
    }
    
    // MARK: - Arena Ambient

    func startArenaAmbient(intensity: Float = 1.0, force: Bool = false) {
        ensureRunning()
        guard engine.isRunning else { return }

        if ambientActive && !force && abs(lastAmbientIntensity - intensity) < 0.02 {
            return
        }

        lastAmbientIntensity = intensity

        let format = mixer.outputFormat(forBus: 0)
        let pressure = intensity >= 1.0

        let baseParams = manifestParams(for: "idle_ambient_001") ?? SynthParameters(
            wave: .whiteNoise,
            frequency: 42,
            duration: 7.5,
            amplitude: Float(0.018 * Double(intensity)),
            attack: 1.8,
            decay: 0.6,
            sustain: 1.0,
            release: 1.8,
            harmonics: 0.44,
            detune: 0.0,
            saturation: 0.88,
            stereoWidth: 1.0,
            pan: 0
        )

        let lowBedParams = SynthParameters(
            wave: .sine,
            frequency: pressure ? 43 : 38,
            duration: 7.5,
            amplitude: Float(0.016 * Double(intensity)),
            attack: 1.2,
            decay: 0.4,
            sustain: 0.90,
            release: 1.7,
            harmonics: 0.032,
            detune: 0.001,
            saturation: 0.92,
            stereoWidth: 0.18,
            pan: 0
        )

        let airParams = SynthParameters(
            wave: .whiteNoise,
            frequency: pressure ? 94 : 70,
            duration: 9.0,
            amplitude: Float(0.0075 * Double(intensity)),
            attack: 2.2,
            decay: 0.7,
            sustain: 0.84,
            release: 2.0,
            harmonics: pressure ? 0.34 : 0.22,
            detune: 0.0,
            saturation: 0.86,
            stereoWidth: 1.0,
            pan: pressure ? -0.14 : 0.10
        )

        guard
            let lowBed = AudioSynthesizer.generate(params: lowBedParams, format: format),
            let texture = AudioSynthesizer.generate(params: baseParams, format: format),
            let air = AudioSynthesizer.generate(params: airParams, format: format)
        else { return }

        ambientNode.stop()
        ambientTextureNode.stop()
        ambientAirNode.stop()

        ambientNode.scheduleBuffer(lowBed, at: nil, options: [.loops])
        ambientTextureNode.scheduleBuffer(texture, at: nil, options: [.loops])
        ambientAirNode.scheduleBuffer(air, at: nil, options: [.loops])

        ambientNode.play()
        ambientTextureNode.play()
        ambientAirNode.play()

        ambientActive = true
    }

    func stopArenaAmbient() {
        ambientNode.stop()
        ambientTextureNode.stop()
        ambientAirNode.stop()

        ambientActive = false
        lastAmbientIntensity = 0
    }

    func stopAmbient() {
        stopArenaAmbient()
    }

    // MARK: - XP Loop

    func startXPCountLoop() {
        // Disabled for live pressure moments.
        // A short looping buffer can become a non-stop tone during long Solo runs.
        stopXPCountLoop()
    }

    func stopXPCountLoop() {
        xpLoopNode.stop()
        xpLoopActive = false
    }

    // MARK: - Settings / Compatibility

    func refreshAudioState() {
        configureSession()
        ensureRunning()
        transition(to: currentState, force: true)
    }

    func resumeAfterInterruption() {
        configureSession()
        ensureRunning()
        transition(to: currentState, force: true)
    }

    func stopAll() {
        cueNode.stop()
        rewardNode.stop()
        xpLoopNode.stop()

        ambientNode.stop()
        ambientTextureNode.stop()
        ambientAirNode.stop()

        xpLoopActive = false
        ambientActive = false
        lastAmbientIntensity = 0
    }

    func stopBGM() {
        stopAll()
    }

    // MARK: - Cue Sound Design

    private func makeBuffer(for cue: AudioCue) -> AVAudioPCMBuffer? {
        let format = mixer.outputFormat(forBus: 0)

        if let mapped = manifestParams(for: manifestID(for: cue)) {
            return AudioSynthesizer.generate(params: mapped, format: format)
        }

        switch cue {
        case .uiTap:
            return AudioSynthesizer.generate(
                params: SynthParameters(
                    wave: .triangle,
                    frequency: 720,
                    duration: 0.014,
                    amplitude: 0.056,
                    attack: 0.002,
                    decay: 0.010,
                    sustain: 0.20,
                    release: 0.026,
                    harmonics: 0.022,
                    detune: 0.0005,
                    saturation: 0.92,
                    stereoWidth: 0.04,
                    pan: softPan()
                ),
                format: format
            )

        case .lockIn:
            return AudioSynthesizer.generate(
                params: SynthParameters(
                    wave: .triangle,
                    frequency: 472,
                    duration: 0.060,
                    amplitude: 0.088,
                    attack: 0.004,
                    decay: 0.022,
                    sustain: 0.43,
                    release: 0.065,
                    harmonics: 0.08,
                    detune: 0.0012,
                    saturation: 0.98,
                    stereoWidth: 0.10,
                    pan: 0
                ),
                format: format
            )

        case .correct:
            return AudioSynthesizer.generate(
                params: SynthParameters(
                    wave: .sine,
                    frequency: 740,
                    duration: 0.16,
                    amplitude: 0.102,
                    attack: 0.006,
                    decay: 0.030,
                    sustain: 0.56,
                    release: 0.095,
                    harmonics: 0.32,
                    detune: 0.0012,
                    saturation: 0.96,
                    stereoWidth: 0.38,
                    pan: softPan()
                ),
                format: format
            )

        case .wrong:
            return AudioSynthesizer.generate(
                params: SynthParameters(
                    wave: .triangle,
                    frequency: 196,
                    duration: 0.145,
                    amplitude: 0.070,
                    attack: 0.004,
                    decay: 0.020,
                    sustain: 0.22,
                    release: 0.080,
                    harmonics: 0.07,
                    detune: 0.001,
                    saturation: 0.92,
                    stereoWidth: 0.08,
                    pan: 0
                ),
                format: format
            )

        case .countdownTick:
            return AudioSynthesizer.generate(
                params: SynthParameters(
                    wave: .triangle,
                    frequency: 390,
                    duration: 0.022,
                    amplitude: 0.060,
                    attack: 0.002,
                    decay: 0.010,
                    sustain: 0.20,
                    release: 0.026,
                    harmonics: 0.018,
                    detune: 0.0,
                    saturation: 0.94,
                    stereoWidth: 0.0,
                    pan: 0
                ),
                format: format
            )

        case .dangerPulse:
            return AudioSynthesizer.generate(
                params: SynthParameters(
                    wave: .sine,
                    frequency: 62,
                    duration: 0.28,
                    amplitude: 0.078,
                    attack: 0.024,
                    decay: 0.060,
                    sustain: 0.50,
                    release: 0.190,
                    harmonics: 0.010,
                    detune: 0.0006,
                    saturation: 0.90,
                    stereoWidth: 0.10,
                    pan: 0
                ),
                format: format
            )

        case .tieBreak:
            return AudioSynthesizer.generate(
                params: SynthParameters(
                    wave: .triangle,
                    frequency: 612,
                    duration: 0.050,
                    amplitude: 0.090,
                    attack: 0.003,
                    decay: 0.014,
                    sustain: 0.36,
                    release: 0.050,
                    harmonics: 0.050,
                    detune: 0.001,
                    saturation: 0.98,
                    stereoWidth: 0.12,
                    pan: 0
                ),
                format: format
            )

        case .victory:
            return AudioSynthesizer.generate(
                params: SynthParameters(
                    wave: .sine,
                    frequency: 520,
                    duration: 0.32,
                    amplitude: 0.080,
                    attack: 0.012,
                    decay: 0.040,
                    sustain: 0.60,
                    release: 0.28,
                    harmonics: 0.20,
                    detune: 0.001,
                    saturation: 0.94,
                    stereoWidth: 0.60,
                    pan: 0
                ),
                format: format
            )
        }
    }

    private func manifestID(for cue: AudioCue) -> String? {
        switch cue {
        case .correct:
            return "success_hit_001"
        case .wrong:
            return "hurt_001"
        default:
            return nil
        }
    }

    // MARK: - FX Configuration

    private func configureFX() {
        let lowCut = cueEQ.bands[0]
        lowCut.filterType = .highPass
        lowCut.frequency = 92
        lowCut.bandwidth = 0.5
        lowCut.gain = 0
        lowCut.bypass = false

        let presence = cueEQ.bands[1]
        presence.filterType = .parametric
        presence.frequency = 2380
        presence.bandwidth = 0.92
        presence.gain = 0.62
        presence.bypass = false

        cueDelay.delayTime = 0.052
        cueDelay.feedback = 8
        cueDelay.lowPassCutoff = 5000
        cueDelay.wetDryMix = 6

        cueReverb.loadFactoryPreset(.mediumRoom)
        cueReverb.wetDryMix = 12

        let ambientLowCut = ambientEQ.bands[0]
        ambientLowCut.filterType = .highPass
        ambientLowCut.frequency = 30
        ambientLowCut.bandwidth = 0.5
        ambientLowCut.gain = 0
        ambientLowCut.bypass = false

        let ambientAir = ambientEQ.bands[1]
        ambientAir.filterType = .parametric
        ambientAir.frequency = 2050
        ambientAir.bandwidth = 1.25
        ambientAir.gain = 0.48
        ambientAir.bypass = false

        ambientReverb.loadFactoryPreset(.largeRoom)
        ambientReverb.wetDryMix = 22
    }

    private func tuneCueFX(for cue: AudioCue) {
        switch cue {
        case .uiTap:
            cueDelay.wetDryMix = 3
            cueDelay.feedback = 5
            cueReverb.wetDryMix = 3

        case .lockIn:
            cueDelay.wetDryMix = 7
            cueDelay.feedback = 8
            cueReverb.wetDryMix = 7

        case .correct:
            cueDelay.wetDryMix = 9
            cueDelay.feedback = 10
            cueReverb.wetDryMix = 11

        case .wrong:
            cueDelay.wetDryMix = 5
            cueDelay.feedback = 7
            cueReverb.wetDryMix = 7

        case .countdownTick:
            cueDelay.wetDryMix = 3
            cueDelay.feedback = 4
            cueReverb.wetDryMix = 3

        case .dangerPulse:
            cueDelay.wetDryMix = 6
            cueDelay.feedback = 8
            cueReverb.wetDryMix = 12

        case .tieBreak:
            cueDelay.wetDryMix = 8
            cueDelay.feedback = 9
            cueReverb.wetDryMix = 9

        case .victory:
            cueDelay.wetDryMix = 8
            cueDelay.feedback = 10
            cueReverb.wetDryMix = 14
        }
    }

    private func tuneCustomCueFX(using params: SynthParameters) {
        let brightness = max(0.0, min(1.0, (params.frequency - 120.0) / 1200.0))
        let wet = 6 + (brightness * 8)
        let delayWet = 4 + (Double(params.stereoWidth) * 11)

        cueDelay.feedback = Float(7 + (Double(params.harmonics) * 3))
        cueDelay.wetDryMix = Float(delayWet)
        cueReverb.wetDryMix = Float(wet)
    }

    // MARK: - Manifest

    private func manifestParams(for id: String?) -> SynthParameters? {
        guard let id else { return nil }
        guard let data = BuiltInManifest.json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(BuiltInManifestRoot.self, from: data) else {
            return nil
        }

        return decoded.master_manifest.first(where: { $0.id == id })?.params
    }

    // MARK: - Haptics

    private func triggerHaptics(for cue: AudioCue) {
        switch cue {
        case .uiTap:
            HapticManager.instance.impact(.light)
        case .lockIn:
            HapticManager.instance.impact(.medium)
        case .correct:
            HapticManager.instance.successPulse()
        case .wrong:
            HapticManager.instance.impact(.light)
        case .countdownTick:
            HapticManager.instance.impact(.light)
        case .dangerPulse:
            HapticManager.instance.impact(.light)
        case .tieBreak:
            HapticManager.instance.impact(.rigid)
        case .victory:
            HapticManager.instance.successPulse()
        }
    }

    // MARK: - Engine

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            print("🔴 Audio Session Error: \(error)")
        }
    }

    private func ensureRunning() {
        if !engine.isRunning {
            start()
        }
    }

    private func start() {
        configureSession()

        do {
            if !engine.isRunning {
                try engine.start()
            }

            isRunning = true
            mixer.outputVolume = 1.0
        } catch {
            print("🔴 Audio Engine Error: \(error)")
            isRunning = false
        }
    }

    private func softPan() -> Float {
        Float.random(in: -0.12...0.12)
    }
}

// MARK: - Built-in Manifest Models

private struct BuiltInManifestRoot: Codable {
    let master_manifest: [BuiltInManifestEntry]
}

private struct BuiltInManifestEntry: Codable {
    let name: String
    let id: String
    let analysis: String
    let params: SynthParameters
}

private enum BuiltInManifest {
    static let json = """
    {
      "master_manifest": [
        {
          "name": "Warp-In Trigger",
          "id": "trigger_warp_001",
          "analysis": "Cinematic reveal shift with a wide arena sweep and mechanical tension release.",
          "params": {
            "wave": "saw",
            "frequency": 710.0,
            "duration": 0.72,
            "amplitude": 0.095,
            "attack": 0.008,
            "decay": 0.08,
            "sustain": 0.46,
            "release": 0.36,
            "harmonics": 0.78,
            "detune": 0.003,
            "saturation": 1.0,
            "stereoWidth": 0.84,
            "pan": 0.0
          }
        },
        {
          "name": "Tactile Success",
          "id": "success_hit_001",
          "analysis": "Clean confirmation tone with restrained reward energy and low fatigue.",
          "params": {
            "wave": "sine",
            "frequency": 740.0,
            "duration": 0.16,
            "amplitude": 0.102,
            "attack": 0.006,
            "decay": 0.03,
            "sustain": 0.56,
            "release": 0.095,
            "harmonics": 0.32,
            "detune": 0.0012,
            "saturation": 0.96,
            "stereoWidth": 0.38,
            "pan": 0.0
          }
        },
        {
          "name": "Damage/Error Jolt",
          "id": "hurt_001",
          "analysis": "Soft negative cue with reduced harshness and short corrective tail.",
          "params": {
            "wave": "triangle",
            "frequency": 196.0,
            "duration": 0.145,
            "amplitude": 0.07,
            "attack": 0.004,
            "decay": 0.02,
            "sustain": 0.22,
            "release": 0.08,
            "harmonics": 0.07,
            "detune": 0.001,
            "saturation": 0.92,
            "stereoWidth": 0.08,
            "pan": 0.0
          }
        },
        {
          "name": "Ambient Arena Texture",
          "id": "idle_ambient_001",
          "analysis": "Subtle low-frequency arena air bed with soft wide motion.",
          "params": {
            "wave": "whiteNoise",
            "frequency": 42.0,
            "duration": 7.5,
            "amplitude": 0.018,
            "attack": 1.8,
            "decay": 0.6,
            "sustain": 1.0,
            "release": 1.8,
            "harmonics": 0.44,
            "detune": 0.0,
            "saturation": 0.88,
            "stereoWidth": 1.0,
            "pan": 0.0
          }
        }
      ]
    }
    """
}
