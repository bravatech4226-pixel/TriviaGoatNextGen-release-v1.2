//
//  QuestionClockMode.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-02-15.
//


//
//  QuestionClockConfig.swift
//  TriviaGoatNextGen
//
//  Single source of truth for per-question time limit (7s / 10s).
//

import Foundation

enum QuestionClockMode: Int, CaseIterable {
    case competitive7 = 7
    case casual10 = 10

    var seconds: Int { rawValue }

    var label: String {
        switch self {
        case .competitive7: return "7s"
        case .casual10:     return "10s"
        }
    }

    var title: String {
        switch self {
        case .competitive7: return "Competitive"
        case .casual10:     return "Casual"
        }
    }
}

enum QuestionClockConfig {
    private static let key = "tg_question_seconds"

    static var mode: QuestionClockMode {
        get {
            let v = UserDefaults.standard.integer(forKey: key)
            return QuestionClockMode(rawValue: v) ?? .competitive7
        }
        set {
            UserDefaults.standard.set(newValue.seconds, forKey: key)
        }
    }

    static func toggle() {
        mode = (mode == .competitive7) ? .casual10 : .competitive7
    }
}
