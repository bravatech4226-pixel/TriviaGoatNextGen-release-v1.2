//
//  TrainingGateStatus.swift
//  TRIVIA GOAT
//
//  Simple computed UI strings for Training Gate
//

import Foundation

extension TrainingGate {
    var badgeText: String {
        canUseFreeToday ? "\(remainingToday) Free Left" : "Free Used"
    }

    var detailText: String {
        "Daily Free: \(usedToday)/\(dailyLimit) used"
    }
}

