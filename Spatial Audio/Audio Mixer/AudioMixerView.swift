//
//  AudioMixerView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-03-25.
//

import SwiftUI

struct AudioMixerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("globalAudioVelocity") private var globalVelocity: Double = 1.0

    private let cues = AudioCue.allCases

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [Color.indigo.opacity(0.15), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AUDIO CALIBRATION")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundColor(.indigo)

                        Text("STUDIO MONITOR V1.0 // PROJECT: TRIVIAGOAT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.2))
                    }
                }
                .padding(25)
                .background(.ultraThinMaterial)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 30) {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                Label("GLOBAL ENGINE VELOCITY", systemImage: "gauge.with.dots.needle.bottom.100percent")
                                Spacer()
                                Text(String(format: "%.2fx", globalVelocity))
                                    .foregroundColor(.indigo)
                            }
                            .font(.system(size: 10, weight: .black, design: .monospaced))

                            Slider(value: $globalVelocity, in: 0.5...2.0, step: 0.05)
                                .tint(.indigo)

                            Text("UI-ONLY PLACEHOLDER FOR FUTURE GLOBAL AUDIO SCALING.")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding()
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                        )

                        ForEach(cues, id: \.self) { cue in
                            channelStrip(for: cue)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func channelStrip(for cue: AudioCue) -> some View {
        VStack(spacing: 18) {
            HStack {
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundColor(.indigo)

                Text(cue.title)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    SpatialAudioManager.shared.play(cue)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .padding(10)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
            }

            VStack(spacing: 12) {
                mixerReadout(label: "WAVE CLASS", value: cue.waveLabel, color: .cyan)
                mixerReadout(label: "ROLE", value: cue.roleLabel, color: .indigo)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func mixerReadout(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                Text(value)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }

            RoundedRectangle(cornerRadius: 999)
                .fill(Color.white.opacity(0.06))
                .frame(height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }
}
