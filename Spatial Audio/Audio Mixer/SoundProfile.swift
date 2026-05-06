//
//  SoundProfile.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-03-25.
//


import Foundation

struct SoundProfile: Codable, Equatable {
    var id: String
    var volume: Float      // Gain (0.0 - 1.0)
    var pitch: Float       // cents (-2400 to 2400)
    var delay: Double      // Sync Offset (0.0 to 1.0s)
    var velocity: Float    // Playback Rate (0.5 to 2.0)

    /// The Factory Presets
    static var manifest: [String: SoundProfile] {
        return [
            "tg_ui_tap": SoundProfile(id: "tg_ui_tap", volume: 0.35, pitch: 0, delay: 0.0, velocity: 1.0),
            "tg_correct": SoundProfile(id: "tg_correct", volume: 0.7, pitch: 0, delay: 0.05, velocity: 1.0),
            "tg_wrong": SoundProfile(id: "tg_wrong", volume: 0.7, pitch: -200, delay: 0.08, velocity: 1.0),
            "tg_mission_start": SoundProfile(id: "tg_mission_start", volume: 0.75, pitch: 0, delay: 0.15, velocity: 1.0),
            "tg_mission_complete": SoundProfile(id: "tg_mission_complete", volume: 0.90, pitch: 0, delay: 0.10, velocity: 1.0)
        ]
    }
}