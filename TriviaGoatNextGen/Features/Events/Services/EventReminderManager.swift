//
//  EventReminderManager.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  EventKit calendar save/update + local notification reminder helper.
//

import Foundation
import EventKit
import UserNotifications

final class EventReminderManager {

    static let shared = EventReminderManager()

    private let eventStore = EKEventStore()
    private let eventHubBaseURL = "https://triviagoat.ca/events/public"

    private init() {}

    @discardableResult
    func saveEventToCalendar(_ event: AppState.TGEvent) async throws -> String {
        guard let startsAt = event.startsAt else {
            throw EventReminderError.missingStartDate
        }

        let granted = try await requestCalendarAccessIfNeeded()
        guard granted else {
            throw EventReminderError.calendarPermissionDenied
        }

        let safeEnd = event.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        let endsAt = max(safeEnd, startsAt.addingTimeInterval(30 * 60))
        let marker = calendarMarker(for: event)

        let calendarEvent = findExistingCalendarEvent(
            startsAt: startsAt,
            endsAt: endsAt,
            marker: marker
        ) ?? EKEvent(eventStore: eventStore)

        calendarEvent.title = event.title
        calendarEvent.startDate = startsAt
        calendarEvent.endDate = endsAt
        calendarEvent.notes = calendarNotes(for: event, marker: marker)
        calendarEvent.url = eventHubURL(for: event)

        if calendarEvent.calendar == nil {
            calendarEvent.calendar = eventStore.defaultCalendarForNewEvents
        }

        guard calendarEvent.calendar != nil else {
            throw EventReminderError.calendarSaveFailed
        }

        calendarEvent.alarms = nil
        calendarEvent.addAlarm(EKAlarm(relativeOffset: -30 * 60))
        calendarEvent.addAlarm(EKAlarm(relativeOffset: -5 * 60))

        try eventStore.save(calendarEvent, span: .thisEvent, commit: true)

        guard let eventIdentifier = calendarEvent.eventIdentifier else {
            throw EventReminderError.calendarSaveFailed
        }

        return eventIdentifier
    }

    func scheduleLocalReminders(for event: AppState.TGEvent) async throws {
        guard let startsAt = event.startsAt else {
            throw EventReminderError.missingStartDate
        }

        let granted = try await requestNotificationPermissionIfNeeded()
        guard granted else {
            throw EventReminderError.notificationPermissionDenied
        }

        let reminderDates = [
            startsAt.addingTimeInterval(-30 * 60),
            startsAt.addingTimeInterval(-5 * 60)
        ]

        let identifiers = reminderIdentifiers(for: event)

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)

        for (index, reminderDate) in reminderDates.enumerated() {
            guard reminderDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = reminderBody(for: event, minutesBefore: index == 0 ? 30 : 5)
            content.sound = .default
            content.userInfo = [
                "type": "event",
                "eventID": event.id,
                "eventURL": eventHubURLString(for: event)
            ]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminderDate
            )

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: identifiers[index],
                content: content,
                trigger: trigger
            )

            try await UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelLocalReminders(for event: AppState.TGEvent) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: reminderIdentifiers(for: event)
            )
    }

    private func requestCalendarAccessIfNeeded() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess, .authorized:
            return true

        case .notDetermined:
            if #available(iOS 17.0, *) {
                return try await eventStore.requestFullAccessToEvents()
            } else {
                return try await eventStore.requestAccess(to: .event)
            }

        case .denied, .restricted, .writeOnly:
            return false

        @unknown default:
            return false
        }
    }

    private func requestNotificationPermissionIfNeeded() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true

        case .notDetermined:
            return try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )

        case .denied:
            return false

        @unknown default:
            return false
        }
    }

    private func findExistingCalendarEvent(
        startsAt: Date,
        endsAt: Date,
        marker: String
    ) -> EKEvent? {
        let predicate = eventStore.predicateForEvents(
            withStart: startsAt.addingTimeInterval(-24 * 60 * 60),
            end: endsAt.addingTimeInterval(24 * 60 * 60),
            calendars: nil
        )

        return eventStore.events(matching: predicate).first {
            $0.notes?.contains(marker) == true
        }
    }

    private func calendarNotes(
        for event: AppState.TGEvent,
        marker: String
    ) -> String {
        var lines: [String] = []

        let heroLine = event.heroLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = event.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        if !heroLine.isEmpty {
            lines.append(heroLine)
        }

        if !summary.isEmpty && summary != heroLine {
            lines.append("")
            lines.append(summary)
        }

        lines.append("")
        lines.append("Open event hub:")
        lines.append(eventHubURLString(for: event))
        lines.append("")
        lines.append(marker)

        return lines.joined(separator: "\n")
    }

    private func reminderBody(for event: AppState.TGEvent, minutesBefore: Int) -> String {
        let heroLine = event.heroLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if !heroLine.isEmpty {
            return heroLine
        }

        return minutesBefore <= 5
            ? "Your Trivia GOAT event is about to start."
            : "Your Trivia GOAT event starts in \(minutesBefore) minutes."
    }

    private func eventHubURLString(for event: AppState.TGEvent) -> String {
        let encodedID = event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.id
        return "\(eventHubBaseURL)/\(encodedID)"
    }

    private func eventHubURL(for event: AppState.TGEvent) -> URL? {
        URL(string: eventHubURLString(for: event))
    }

    private func calendarMarker(for event: AppState.TGEvent) -> String {
        "TriviaGOATEventID:\(event.id)"
    }

    private func reminderIdentifiers(for event: AppState.TGEvent) -> [String] {
        [
            "tg.event.reminder.\(event.id).30m",
            "tg.event.reminder.\(event.id).5m"
        ]
    }
}

enum EventReminderError: Error {
    case missingStartDate
    case calendarPermissionDenied
    case notificationPermissionDenied
    case calendarSaveFailed
}
