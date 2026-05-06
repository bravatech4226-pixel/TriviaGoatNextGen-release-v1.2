//
//  TriviaGoatSoundLab.swift
//  TriviaGoatNextGen
//
//  CLEAN • FAST COMPILE • COPY-READY EXPORT
//

import SwiftUI
import UIKit

struct TriviaGoatSoundLab: View {
    @AppStorage("tg.soundlab.savedPresetsJSON") private var savedPresetsJSON: String = ""
    @AppStorage("tg.soundlab.stagedPresetJSON") private var stagedPresetJSON: String = ""

    @State private var params = SynthParameters()
    @State private var exportString = ""
    @State private var presetName = "New Preset"
    @State private var savedPresets: [SavedSynthPreset] = []
    @State private var selectedQuickCue: QuickCue = .uiTap
    @State private var didCopyExport = false

    var body: some View {
        Form {
            quickStartSection()
            oscillatorSection()
            envelopeSection()
            toneSection()
            stereoSection()
            testSection()
            exportSection()
            savedPresetsSection()
        }
        .navigationTitle("GOAT Sound Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSavedPresets()
            loadStagedPresetIfNeeded()
        }
        .onChange(of: savedPresets) { _, _ in
            persistSavedPresets()
        }
    }
}

private extension TriviaGoatSoundLab {
    func quickStartSection() -> some View {
        Section {
            Picker("Reference Cue", selection: $selectedQuickCue) {
                ForEach(QuickCue.allCases) { cue in
                    Text(cue.title).tag(cue)
                }
            }

            Button("Load Reference") {
                params = selectedQuickCue.defaultParameters
                presetName = selectedQuickCue.title
                exportString = ""
                didCopyExport = false
            }
            .foregroundColor(.orange)
        } header: {
            Text("Quick Start")
        }
    }

    func oscillatorSection() -> some View {
        Section {
            Picker("Waveform", selection: $params.wave) {
                ForEach(SynthWaveType.allCases, id: \.self) { wave in
                    Text(displayName(for: wave)).tag(wave)
                }
            }
            .pickerStyle(.segmented)

            sliderRow(
                title: "Frequency",
                value: Binding(
                    get: { Double(params.frequency) },
                    set: { params.frequency = Float($0) }
                ),
                range: 40...2000,
                display: "\(Int(params.frequency)) Hz"
            )

            sliderRow(
                title: "Duration",
                value: $params.duration,
                range: 0.01...1.5,
                display: "\(Int(params.duration * 1000)) ms"
            )

            sliderRow(
                title: "Amplitude",
                value: Binding(
                    get: { Double(params.amplitude) },
                    set: { params.amplitude = Float($0) }
                ),
                range: 0.01...1.0,
                display: String(format: "%.2f", params.amplitude)
            )
        } header: {
            Text("Oscillator")
        }
    }

    func envelopeSection() -> some View {
        Section {
            sliderRow(
                title: "Attack",
                value: $params.attack,
                range: 0.001...0.15,
                display: "\(Int(params.attack * 1000)) ms"
            )

            sliderRow(
                title: "Decay",
                value: $params.decay,
                range: 0.001...0.30,
                display: "\(Int(params.decay * 1000)) ms"
            )

            sliderRow(
                title: "Sustain",
                value: Binding(
                    get: { Double(params.sustain) },
                    set: { params.sustain = Float($0) }
                ),
                range: 0.0...1.0,
                display: String(format: "%.2f", params.sustain)
            )

            sliderRow(
                title: "Release",
                value: $params.release,
                range: 0.001...1.0,
                display: "\(Int(params.release * 1000)) ms"
            )
        } header: {
            Text("Envelope")
        }
    }

    func toneSection() -> some View {
        Section {
            sliderRow(
                title: "Harmonics",
                value: Binding(
                    get: { Double(params.harmonics) },
                    set: { params.harmonics = Float($0) }
                ),
                range: 0.0...2.5,
                display: String(format: "%.2f", params.harmonics)
            )

            sliderRow(
                title: "Detune",
                value: Binding(
                    get: { Double(params.detune) },
                    set: { params.detune = Float($0) }
                ),
                range: 0.0...0.03,
                display: String(format: "%.4f", params.detune)
            )

            sliderRow(
                title: "Saturation",
                value: Binding(
                    get: { Double(params.saturation) },
                    set: { params.saturation = Float($0) }
                ),
                range: 0.5...3.0,
                display: String(format: "%.2f", params.saturation)
            )
        } header: {
            Text("Tone Shaping")
        }
    }

    func stereoSection() -> some View {
        Section {
            sliderRow(
                title: "Width",
                value: Binding(
                    get: { Double(params.stereoWidth) },
                    set: { params.stereoWidth = Float($0) }
                ),
                range: 0.0...1.0,
                display: String(format: "%.2f", params.stereoWidth)
            )

            sliderRow(
                title: "Pan",
                value: Binding(
                    get: { Double(params.pan) },
                    set: { params.pan = Float($0) }
                ),
                range: -1.0...1.0,
                display: String(format: "%.2f", params.pan)
            )
        } header: {
            Text("Stereo")
        }
    }

    func testSection() -> some View {
        Section {
            Button("Test Tone") {
                SpatialAudioManager.shared.playCustom(params: params)
            }
            .foregroundColor(.orange)

            Button("Save Preset") {
                saveCurrentPreset()
            }
        } header: {
            Text("Test")
        } footer: {
            Text("Use Test Tone while tuning. Save Preset stores it locally for recall.")
        }
    }

    func exportSection() -> some View {
        Section {
            TextField("Preset Name", text: $presetName)

            Button("Generate JSON") {
                exportString = AudioSynthesizer.exportJSONString(for: params) ?? ""
                didCopyExport = false
            }

            Button("Generate Swift Snippet") {
                exportString = AudioSynthesizer.exportSwiftSnippet(
                    named: sanitizedVariableName(from: presetName),
                    params: params
                )
                didCopyExport = false
            }

            if !exportString.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Export Output")
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(exportString)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                    }

                    HStack(spacing: 10) {
                        Button(didCopyExport ? "Copied" : "Copy Export") {
                            UIPasteboard.general.string = exportString
                            didCopyExport = true
                        }
                        .foregroundColor(.orange)

                        Button("Test Current") {
                            SpatialAudioManager.shared.playCustom(params: params)
                        }
                    }
                }
            }
        } header: {
            Text("Export")
        }
    }

    func savedPresetsSection() -> some View {
        Section {
            if savedPresets.isEmpty {
                Text("No presets yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(savedPresets) { preset in
                    savedPresetRow(preset)
                }
            }
        } header: {
            Text("Saved Presets")
        }
    }

    func savedPresetRow(_ preset: SavedSynthPreset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preset.name)
                .font(.headline)

            Text(summary(for: preset.params))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Load") {
                    params = preset.params
                    presetName = preset.name
                    exportString = ""
                    didCopyExport = false
                }
                .foregroundColor(.orange)

                Button("Test") {
                    SpatialAudioManager.shared.playCustom(params: preset.params)
                }

                Spacer()

                Button("Delete", role: .destructive) {
                    deletePreset(id: preset.id)
                }
            }
        }
        .padding(.vertical, 4)
    }

    func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value, in: range)
        }
    }

    func displayName(for wave: SynthWaveType) -> String {
        switch wave {
        case .sine: return "Sine"
        case .square: return "Square"
        case .triangle: return "Triangle"
        case .saw: return "Saw"
        case .whiteNoise: return "Noise"
        }
    }

    func sanitizedVariableName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "customPreset" : trimmed

        let pieces = fallback
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let result = pieces.enumerated().map { index, piece in
            if index == 0 {
                return piece.prefix(1).lowercased() + piece.dropFirst()
            } else {
                return piece.prefix(1).uppercased() + piece.dropFirst()
            }
        }.joined()

        return result.isEmpty ? "customPreset" : result
    }

    func summary(for params: SynthParameters) -> String {
        "\(displayName(for: params.wave)) • \(Int(params.frequency)) Hz • \(Int(params.duration * 1000)) ms • A:\(Int(params.attack * 1000)) D:\(Int(params.decay * 1000)) R:\(Int(params.release * 1000))"
    }

    func saveCurrentPreset() {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? "Untitled Preset" : trimmed
        let preset = SavedSynthPreset(name: resolvedName, params: params)

        if let index = savedPresets.firstIndex(where: { $0.name.caseInsensitiveCompare(resolvedName) == .orderedSame }) {
            savedPresets[index] = preset
        } else {
            savedPresets.insert(preset, at: 0)
        }
    }

    func deletePreset(id: String) {
        savedPresets.removeAll { $0.id == id }
    }

    func loadSavedPresets() {
        guard let data = savedPresetsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([SavedSynthPreset].self, from: data) else {
            savedPresets = []
            return
        }

        savedPresets = decoded
    }

    func persistSavedPresets() {
        guard let data = try? JSONEncoder().encode(savedPresets),
              let json = String(data: data, encoding: .utf8) else { return }
        savedPresetsJSON = json
    }

    func loadStagedPresetIfNeeded() {
        guard !stagedPresetJSON.isEmpty,
              let data = stagedPresetJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SynthParameters.self, from: data) else {
            return
        }

        params = decoded
        stagedPresetJSON = ""
    }
}

private enum QuickCue: String, CaseIterable, Identifiable {
    case uiTap
    case lockIn
    case correct
    case wrong
    case countdownTick
    case dangerPulse
    case tieBreak
    case victory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uiTap: return "UI Tap"
        case .lockIn: return "Lock In"
        case .correct: return "Correct"
        case .wrong: return "Wrong"
        case .countdownTick: return "Countdown"
        case .dangerPulse: return "Danger"
        case .tieBreak: return "Tie-Break"
        case .victory: return "Victory"
        }
    }

    var defaultParameters: SynthParameters {
        switch self {
        case .uiTap:
            return SynthParameters(
                wave: .triangle,
                frequency: 900,
                duration: 0.018,
                amplitude: 0.12,
                attack: 0.003,
                decay: 0.015,
                sustain: 0.35,
                release: 0.035,
                harmonics: 0.08,
                detune: 0.001,
                saturation: 1.10,
                stereoWidth: 0.02,
                pan: 0
            )

        case .lockIn:
            return SynthParameters(
                wave: .triangle,
                frequency: 520,
                duration: 0.045,
                amplitude: 0.14,
                attack: 0.004,
                decay: 0.020,
                sustain: 0.55,
                release: 0.050,
                harmonics: 0.18,
                detune: 0.002,
                saturation: 1.20,
                stereoWidth: 0.03,
                pan: 0
            )

        case .correct:
            return SynthParameters(
                wave: .sine,
                frequency: 640,
                duration: 0.110,
                amplitude: 0.16,
                attack: 0.005,
                decay: 0.035,
                sustain: 0.70,
                release: 0.090,
                harmonics: 0.10,
                detune: 0.002,
                saturation: 1.05,
                stereoWidth: 0.05,
                pan: 0
            )

        case .wrong:
            return SynthParameters(
                wave: .triangle,
                frequency: 420,
                duration: 0.090,
                amplitude: 0.13,
                attack: 0.004,
                decay: 0.020,
                sustain: 0.50,
                release: 0.070,
                harmonics: 0.05,
                detune: 0.001,
                saturation: 1.00,
                stereoWidth: 0.02,
                pan: 0
            )

        case .countdownTick:
            return SynthParameters(
                wave: .triangle,
                frequency: 420,
                duration: 0.020,
                amplitude: 0.10,
                attack: 0.002,
                decay: 0.012,
                sustain: 0.25,
                release: 0.030,
                harmonics: 0.04,
                detune: 0.000,
                saturation: 1.00,
                stereoWidth: 0.00,
                pan: 0
            )

        case .dangerPulse:
            return SynthParameters(
                wave: .sine,
                frequency: 90,
                duration: 0.140,
                amplitude: 0.10,
                attack: 0.006,
                decay: 0.030,
                sustain: 0.60,
                release: 0.100,
                harmonics: 0.02,
                detune: 0.001,
                saturation: 1.00,
                stereoWidth: 0.01,
                pan: 0
            )

        case .tieBreak:
            return SynthParameters(
                wave: .triangle,
                frequency: 720,
                duration: 0.035,
                amplitude: 0.14,
                attack: 0.003,
                decay: 0.015,
                sustain: 0.45,
                release: 0.040,
                harmonics: 0.08,
                detune: 0.001,
                saturation: 1.10,
                stereoWidth: 0.03,
                pan: 0
            )

        case .victory:
            return SynthParameters(
                wave: .triangle,
                frequency: 640,
                duration: 0.140,
                amplitude: 0.16,
                attack: 0.006,
                decay: 0.030,
                sustain: 0.68,
                release: 0.120,
                harmonics: 0.12,
                detune: 0.002,
                saturation: 1.08,
                stereoWidth: 0.05,
                pan: 0
            )
        }
    }
}
