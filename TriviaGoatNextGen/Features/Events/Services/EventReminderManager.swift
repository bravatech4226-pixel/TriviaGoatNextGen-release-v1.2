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

        addCalendarAlarmIfFuture(to: calendarEvent, startsAt: startsAt, offset: -24 * 60 * 60)
        addCalendarAlarmIfFuture(to: calendarEvent, startsAt: startsAt, offset: -60 * 60)
        addCalendarAlarmIfFuture(to: calendarEvent, startsAt: startsAt, offset: -5 * 60)

        try eventStore.save(calendarEvent, span: .thisEvent, commit: true)

        guard let eventIdentifier = calendarEvent.eventIdentifier else {
            throw EventReminderError.calendarSaveFailed
        }

        #if DEBUG
        print("📅 [EventReminderManager] Calendar saved:", event.id, eventIdentifier)
        #endif

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

        let reminders: [(id: String, fireDate: Date, minutesBefore: Int)] = [
            ("24h", startsAt.addingTimeInterval(-24 * 60 * 60), 24 * 60),
            ("1h", startsAt.addingTimeInterval(-60 * 60), 60),
            ("5m", startsAt.addingTimeInterval(-5 * 60), 5),
            ("live", startsAt, 0)
        ]

        let identifiers = reminderIdentifiers(for: event)

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)

        var scheduledCount = 0

        for reminder in reminders {
            guard reminder.fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = reminderBody(for: event, minutesBefore: reminder.minutesBefore)
            content.sound = .default
            content.userInfo = [
                "type": "event",
                "eventID": event.id,
                "eventURL": eventHubURLString(for: event)
            ]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.fireDate
            )

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: reminderIdentifier(for: event, suffix: reminder.id),
                content: content,
                trigger: trigger
            )

            try await UNUserNotificationCenter.current().add(request)
            scheduledCount += 1
        }

        #if DEBUG
        print("🔔 [EventReminderManager] Local reminders scheduled:", event.id, scheduledCount)
        #endif
    }

    func cancelLocalReminders(for event: AppState.TGEvent) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: reminderIdentifiers(for: event)
            )

        #if DEBUG
        print("🔕 [EventReminderManager] Local reminders cancelled:", event.id)
        #endif
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

    private func addCalendarAlarmIfFuture(
        to calendarEvent: EKEvent,
        startsAt: Date,
        offset: TimeInterval
    ) {
        let fireDate = startsAt.addingTimeInterval(offset)
        guard fireDate > Date() else { return }
        calendarEvent.addAlarm(EKAlarm(relativeOffset: offset))
    }

    private func calendarNotes(
        for event: AppState.TGEvent,
        marker: String
    ) -> String {
        var lines: [String] = []

        let heroLine = event.heroLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = event.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = event.category.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let locationType = event.locationType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        lines.append("Trivia GOAT Event")
        lines.append("")

        if !heroLine.isEmpty {
            lines.append(heroLine)
            lines.append("")
        }

        if !summary.isEmpty && summary != heroLine {
            lines.append(summary)
            lines.append("")
        }

        if heroLine.isEmpty && summary.isEmpty {
            lines.append("Event details are available in the Trivia GOAT event hub.")
            lines.append("")
        }

        if !category.isEmpty {
            lines.append("Category: \(category)")
        }

        if !locationType.isEmpty {
            lines.append("Format: \(locationType)")
        }

        if let organizerName = event.organizerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !organizerName.isEmpty {
            lines.append("Hosted by: \(organizerName)")
        }

        lines.append("")
        lines.append("Open event hub:")
        lines.append(eventHubURLString(for: event))
        lines.append("")
        lines.append(marker)

        return lines.joined(separator: "\n")
    }
    private func reminderBody(for event: AppState.TGEvent, minutesBefore: Int) -> String {
        if minutesBefore == 0 {
            return "Your Trivia GOAT event is live now."
        }

        if minutesBefore >= 24 * 60 {
            return "Your Trivia GOAT event starts tomorrow."
        }

        if minutesBefore >= 60 {
            return "Your Trivia GOAT event starts in 1 hour."
        }

        let heroLine = event.heroLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if !heroLine.isEmpty {
            return heroLine
        }

        return "Your Trivia GOAT event starts in \(minutesBefore) minutes."
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

    private func reminderIdentifier(for event: AppState.TGEvent, suffix: String) -> String {
        "tg.event.reminder.\(event.id).\(suffix)"
    }

    private func reminderIdentifiers(for event: AppState.TGEvent) -> [String] {
        [
            reminderIdentifier(for: event, suffix: "24h"),
            reminderIdentifier(for: event, suffix: "1h"),
            reminderIdentifier(for: event, suffix: "5m"),
            reminderIdentifier(for: event, suffix: "live")
        ]
    }
}

enum EventReminderError: Error {
    case missingStartDate
    case calendarPermissionDenied
    case notificationPermissionDenied
    case calendarSaveFailed
}
