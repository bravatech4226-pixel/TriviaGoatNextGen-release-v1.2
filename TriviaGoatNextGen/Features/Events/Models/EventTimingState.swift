//
//  EventTimingState.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-14.
//

import SwiftUI

enum EventTimingState: Equatable {
    case dateTBA
    case upcoming(days: Int, hours: Int, minutes: Int)
    case today(hours: Int, minutes: Int)
    case startingSoon(minutes: Int)
    case live
    case ended

    var label: String {
        switch self {
        case .dateTBA:
            return "DATE TBA"
        case .upcoming(let days, let hours, let minutes):
            return "\(days)D \(hours)H \(minutes)M"
        case .today(let hours, let minutes):
            return "\(hours)H \(minutes)M"
        case .startingSoon(let minutes):
            return "STARTS IN \(minutes)M"
        case .live:
            return "LIVE NOW"
        case .ended:
            return "ENDED"
        }
    }

    var subtitle: String {
        switch self {
        case .dateTBA:
            return "Schedule pending"
        case .upcoming:
            return "Countdown active"
        case .today:
            return "Coming up today"
        case .startingSoon:
            return "Final call"
        case .live:
            return "Event is currently active"
        case .ended:
            return "Event has concluded"
        }
    }

    var systemImage: String {
        switch self {
        case .dateTBA:
            return "calendar.badge.clock"
        case .upcoming:
            return "timer"
        case .today:
            return "clock"
        case .startingSoon:
            return "timer"
        case .live:
            return "dot.radiowaves.left.and.right"
        case .ended:
            return "checkmark.seal"
        }
    }

    static func resolve(
        startsAt: Date?,
        endsAt: Date?,
        now: Date = Date()
    ) -> EventTimingState {
        guard let startsAt else {
            return .dateTBA
        }

        let resolvedEnd = endsAt ?? startsAt.addingTimeInterval(60 * 60)

        if now >= resolvedEnd {
            return .ended
        }

        if now >= startsAt && now < resolvedEnd {
            return .live
        }

        let totalSeconds = max(0, Int(startsAt.timeIntervalSince(now)))

        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = max(1, (totalSeconds % 3_600) / 60)

        if totalSeconds <= 3_600 {
            return .startingSoon(minutes: max(1, Int(ceil(Double(totalSeconds) / 60.0))))
        }

        if totalSeconds <= 86_400 {
            return .today(hours: max(1, hours), minutes: minutes)
        }

        return .upcoming(days: max(1, days), hours: hours, minutes: minutes)
    }
}
