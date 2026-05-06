//
//  AudioCue.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-04-19.
//


//
//  AudioCue.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-04-19.
//

import Foundation

enum AudioCue: String, CaseIterable, Hashable, Sendable {
    case uiTap
    case lockIn
    case correct
    case wrong
    case countdownTick
    case dangerPulse
    case tieBreak
    case victory

    var title: String {
        switch self {
        case .uiTap: return "UI TAP"
        case .lockIn: return "LOCK IN"
        case .correct: return "CORRECT"
        case .wrong: return "WRONG"
        case .countdownTick: return "COUNTDOWN TICK"
        case .dangerPulse: return "DANGER PULSE"
        case .tieBreak: return "TIE BREAK"
        case .victory: return "VICTORY"
        }
    }

    var waveLabel: String {
        switch self {
        case .uiTap: return "TRIANGLE"
        case .lockIn: return "SQUARE"
        case .correct: return "SINE"
        case .wrong: return "SAW"
        case .countdownTick: return "SQUARE"
        case .dangerPulse: return "SINE"
        case .tieBreak: return "TRIANGLE"
        case .victory: return "SINE"
        }
    }

    var roleLabel: String {
        switch self {
        case .uiTap: return "UI FEEDBACK"
        case .lockIn: return "ANSWER LOCK"
        case .correct: return "POSITIVE RESULT"
        case .wrong: return "NEGATIVE RESULT"
        case .countdownTick: return "TIME PRESSURE"
        case .dangerPulse: return "HIGH STAKES"
        case .tieBreak: return "SUDDEN DEATH"
        case .victory: return "MATCH RESOLUTION"
        }
    }
}