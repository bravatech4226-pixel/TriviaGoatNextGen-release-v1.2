//
//  EventReminderManager.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Event calendar + local reminder helper.
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

        let granted = try await requestCalendarPermissionIfNeeded()
        guard granted else {
            throw EventReminderError.calendarPermissionDenied
        }

        let calendarEvent = EKEvent(eventStore: eventStore)
        calendarEvent.title = event.title
        calendarEvent.startDate = startsAt
        calendarEvent.endDate = event.endsAt ?? startsAt.addingTimeInterval(60 * 60)

        let notes: String = {
            var lines: [String] = []

            if !event.heroLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(event.heroLine)
            }

            if !event.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(event.summary)
            }

            lines.append("Added from Trivia GOAT.")

            return lines.joined(separator: "\n\n")
        }()

        calendarEvent.notes = notes
        calendarEvent.location = event.locationType.uppercased()
        calendarEvent.calendar = eventStore.defaultCalendarForNewEvents

        let alarm = EKAlarm(relativeOffset: -30 * 60)
        calendarEvent.addAlarm(alarm)

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
        content.body = event.heroLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderIdentifier(for: event)])

        try await UNUserNotificationCenter.current().add(request)
    }

    func cancelLocalReminders(for event: AppState.TGEvent) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: [reminderIdentifier(for: event)]
            )
    }

    private func requestCalendarPermissionIfNeeded() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess, .authorized:
            return true

        case .notDetermined:
            if #available(iOS 17.0, *) {
                return try await eventStore.requestFullAccessToEvents()
            } else {
                return try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }

        case .writeOnly:
            return true

        case .denied, .restricted:
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
