//
//  SpatialAudioHooks.swift
//  TriviaGoatNextGen
//
//  Centralized audio trigger layer for synth-based system
//

import Foundation

enum SpatialAudioHooks {

    static func tap() {
        SpatialAudioManager.shared.play(.uiTap)
    }

    static func lockIn() {
        SpatialAudioManager.shared.play(.lockIn)
    }

    static func correct() {
        SpatialAudioManager.shared.play(.correct)
    }

    static func wrong() {
        SpatialAudioManager.shared.play(.wrong)
    }

    static func countdownTick() {
        SpatialAudioManager.shared.play(.countdownTick)
    }

    static func dangerPulse() {
        SpatialAudioManager.shared.play(.dangerPulse)
    }

    static func tieBreak() {
        SpatialAudioManager.shared.play(.tieBreak)
    }

    static func victory() {
        SpatialAudioManager.shared.play(.victory)
    }

    // legacy bridge
    static func rewardPresent() {
        SpatialAudioManager.shared.play(.victory)
    }

    static func rewardVacuum() {
        SpatialAudioManager.shared.play(.wrong)
    }
}
