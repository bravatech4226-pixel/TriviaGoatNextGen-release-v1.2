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

    private init() {}

    func saveEventToCalendar(_ event: AppState.TGEvent) async throws {
        guard let startsAt = event.startsAt else {
            throw EventReminderError.missingStartDate
        }

        let granted = try await requestCalendarAccessIfNeeded()
        guard granted else {
            throw EventReminderError.calendarPermissionDenied
        }

        let endsAt = event.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        let marker = "TriviaGOATEventID:\(event.id)"

        let calendarEvent = EKEvent(eventStore: eventStore)
        calendarEvent.title = event.title
        calendarEvent.startDate = startsAt
        calendarEvent.endDate = max(endsAt, startsAt.addingTimeInterval(30 * 60))
        calendarEvent.notes = "\(event.summary)\n\n\(marker)"
        calendarEvent.calendar = eventStore.defaultCalendarForNewEvents
        calendarEvent.addAlarm(EKAlarm(relativeOffset: -30 * 60))

        try eventStore.save(calendarEvent, span: .thisEvent, commit: true)
    }

    func scheduleLocalReminders(for event: AppState.TGEvent) async throws {
        guard let startsAt = event.startsAt else {
            throw EventReminderError.missingStartDate
        }

        let granted = try await requestNotificationPermissionIfNeeded()

        guard granted else {
            throw EventReminderError.notificationPermissionDenied
        }

        let reminderDate = startsAt.addingTimeInterval(-30 * 60)

        guard reminderDate > Date() else {
            throw EventReminderError.reminderDateInPast
        }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.heroLine.isEmpty
            ? "Your Trivia GOAT event starts soon."
            : event.heroLine
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: reminderIdentifier(for: event),
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
    }

    func cancelLocalReminders(for event: AppState.TGEvent) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [reminderIdentifier(for: event)]
            )
    }

    private func requestCalendarAccessIfNeeded() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess:
            return true

        case .authorized:
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
        event: AppState.TGEvent,
        startsAt: Date,
        endsAt: Date,
        marker: String
    ) -> EKEvent? {
        let searchStart = startsAt.addingTimeInterval(-24 * 60 * 60)
        let searchEnd = endsAt.addingTimeInterval(24 * 60 * 60)

        let predicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: nil
        )

        return eventStore.events(matching: predicate).first { ekEvent in
            ekEvent.notes?.contains(marker) == true
        }
    }

    private func calendarNotes(
        for event: AppState.TGEvent,
        marker: String
    ) -> String {
        var lines: [String] = []

        if !event.heroLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(event.heroLine)
        }

        if !event.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(event.summary)
        }

        lines.append("")
        lines.append(marker)

        return lines.joined(separator: "\n")
    }

    private func calendarMarker(for event: AppState.TGEvent) -> String {
        "TriviaGOATEventID:\(event.id)"
    }

    private func reminderIdentifier(for event: AppState.TGEvent) -> String {
        "tg.event.reminder.\(event.id)"
    }
}

enum EventReminderError: Error {
    case missingStartDate
    case calendarPermissionDenied
    case notificationPermissionDenied
    case reminderDateInPast
}
