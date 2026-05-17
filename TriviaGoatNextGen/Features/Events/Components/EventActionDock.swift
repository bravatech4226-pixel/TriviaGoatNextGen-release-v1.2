//
//  EventActionDock.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-14.
//

import SwiftUI

struct EventActionDock: View {

    @EnvironmentObject private var app: AppState

    let event: AppState.TGEvent
    let onShare: () -> Void

    @State private var isProcessingCalendar = false

    private var isOrganizer: Bool {
        app.isOrganizer(of: event)
    }

    private var hasRSVPed: Bool {
        app.hasRSVPedToEvent(event.id)
    }

    private var hasWaitlisted: Bool {
        app.hasJoinedWaitlist(event.id)
    }

    private var isFull: Bool {
        event.capacity > 0 && event.attendeeCount >= event.capacity
    }

    var body: some View {
        VStack(spacing: 10) {

            primaryAction

            HStack(spacing: 10) {

                secondaryButton(
                    title: isProcessingCalendar
                    ? "SAVING"
                    : "CALENDAR",

                    systemImage: "calendar.badge.plus"
                ) {
                    saveCalendarAndReminders()
                }
                .disabled(
                    isProcessingCalendar
                    || event.startsAt == nil
                )
                .opacity(event.startsAt == nil ? 0.45 : 1)

                secondaryButton(
                    title: "SHARE",
                    systemImage: "square.and.arrow.up"
                ) {
                    onShare()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(
                            Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: Color.orange.opacity(0.20),
                    radius: 22,
                    x: 0,
                    y: 12
                )
        )
    }

    // MARK: - Primary Action

    private var primaryAction: some View {

        Button {
            handlePrimaryAction()
        } label: {

            HStack(spacing: 10) {

                Image(systemName: primaryIcon)

                Text(primaryTitle)
                    .font(
                        .system(
                            size: 14,
                            weight: .black,
                            design: .monospaced
                        )
                    )
            }
            .foregroundColor(primaryForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 19)
                    .fill(primaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 19)
                            .stroke(primaryStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(
            isOrganizer
            || hasRSVPed
            || hasWaitlisted
            || (isFull && !event.waitlistEnabled)
        )
    }

    // MARK: - CTA State

    private var primaryTitle: String {

        if isOrganizer {
            return "HOSTING"
        }

        if hasRSVPed {
            return "YOU'RE IN"
        }

        if hasWaitlisted {
            return "WAITLISTED"
        }

        if isFull && event.waitlistEnabled {
            return "JOIN WAITLIST"
        }

        if isFull {
            return "FULL"
        }

        return "RSVP NOW"
    }

    private var primaryIcon: String {

        if isOrganizer {
            return "crown.fill"
        }

        if hasRSVPed {
            return "checkmark.seal.fill"
        }

        if hasWaitlisted {
            return "clock.badge.checkmark"
        }

        if isFull && event.waitlistEnabled {
            return "person.crop.circle.badge.plus"
        }

        if isFull {
            return "lock.fill"
        }

        return "bolt.fill"
    }

    private var primaryForeground: Color {

        if isFull && !event.waitlistEnabled {
            return Color.white.opacity(0.45)
        }

        return Color.black
    }

    private var primaryBackground: Color {

        if isFull && !event.waitlistEnabled {
            return Color.white.opacity(0.08)
        }

        if hasRSVPed || isOrganizer {
            return Color.green
        }

        if hasWaitlisted {
            return Color.orange.opacity(0.85)
        }

        return Color.orange
    }

    private var primaryStroke: Color {

        if isFull && !event.waitlistEnabled {
            return Color.white.opacity(0.12)
        }

        return Color.white.opacity(0.20)
    }

    // MARK: - Secondary Buttons

    private func secondaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {

            HStack(spacing: 8) {

                Image(systemName: systemImage)

                Text(title)
                    .font(
                        .system(
                            size: 11,
                            weight: .black,
                            design: .monospaced
                        )
                    )
            }
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 17)
                    .fill(Color.orange.opacity(0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 17)
                            .stroke(
                                Color.orange.opacity(0.30),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - RSVP Flow

    private func handlePrimaryAction() {

        if isOrganizer {
            app.showEventToast("YOU ARE HOSTING")
            return
        }

        if hasRSVPed {
            app.showEventToast("ALREADY REQUESTED")
            return
        }

        if hasWaitlisted {
            app.showEventToast("ALREADY WAITLISTED")
            return
        }

        if isFull {

            if event.waitlistEnabled {
                app.joinEventWaitlist(event)
            } else {
                app.showEventToast("EVENT FULL")
            }

            return
        }

        app.RSVPToEvent(event)
    }

    // MARK: - Calendar + Reminder Flow

    private func saveCalendarAndReminders() {

        Task {

            isProcessingCalendar = true

            defer {
                isProcessingCalendar = false
            }

            do {

                try await EventReminderManager.shared
                    .saveEventToCalendar(event)

                try await EventReminderManager.shared
                    .scheduleLocalReminders(for: event)

                app.showEventToast("REMINDERS SET")

            } catch {

                app.showEventToast("REMINDER FAILED")

                print(
                    "⚠️ Event reminder failed: \(error.localizedDescription)"
                )
            }
        }
    }
}
