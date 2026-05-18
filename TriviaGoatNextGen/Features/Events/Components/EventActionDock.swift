//

//  EventActionDock.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-14.
//
//  PURPOSE:
//  Public event CTA dock.
//  Handles RSVP / waitlist / calendar / share presentation.
//

import SwiftUI
import Combine

struct EventActionDock: View {

    @EnvironmentObject private var app: AppState

    let event: AppState.TGEvent

    let onShare: () -> Void

    @State private var isProcessingCalendar = false

    @State private var now = Date()

    @AppStorage("tg.events.calendarSavedIDs") private var savedCalendarIDsRaw: String = ""

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

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

    private var hasDate: Bool {

        event.startsAt != nil

    }

    private var hasCalendarSaved: Bool {

        savedCalendarIDs.contains(event.id)

    }

    var body: some View {

        VStack(spacing: 10) {

            liveStatusStrip

            primaryAction

            HStack(spacing: 10) {

                secondaryButton(

                    title: calendarTitle,

                    systemImage: calendarIcon

                ) {

                    saveCalendarAndReminders()

                }

                .disabled(isProcessingCalendar || !hasDate || hasCalendarSaved)

                .opacity(hasDate ? 1 : 0.45)

                secondaryButton(

                    title: "SHARE",

                    systemImage: "square.and.arrow.up"

                ) {

                    HapticManager.instance.impact(.light)

                    SpatialAudioManager.shared.play(.uiTap)

                    onShare()

                }

            }

        }

        .padding(14)

        .background(

            RoundedRectangle(cornerRadius: 26, style: .continuous)

                .fill(Color.black.opacity(0.72))

                .overlay(

                    RoundedRectangle(cornerRadius: 26, style: .continuous)

                        .stroke(Color.white.opacity(0.10), lineWidth: 1)

                )

                .shadow(color: Color.orange.opacity(0.20), radius: 22, x: 0, y: 12)

        )

        .onReceive(timer) { value in

            now = value

        }

    }

    // MARK: - Live Status

    private var liveStatusStrip: some View {

        HStack(spacing: 10) {

            Image(systemName: liveStatusIcon)

                .font(.system(size: 12, weight: .black))

                .foregroundColor(.orange.opacity(0.94))

            VStack(alignment: .leading, spacing: 2) {

                Text(liveStatusTitle)

                    .font(.system(size: 10, weight: .black, design: .monospaced))

                    .foregroundColor(.white.opacity(0.84))

                    .tracking(0.8)

                Text(liveStatusSubtitle)

                    .font(.system(size: 11, weight: .bold, design: .rounded))

                    .foregroundColor(.white.opacity(0.54))

                    .lineLimit(1)

                    .minimumScaleFactor(0.74)

            }

            Spacer()

        }

        .padding(.horizontal, 12)

        .frame(height: 48)

        .background(

            RoundedRectangle(cornerRadius: 17, style: .continuous)

                .fill(Color.white.opacity(0.055))

        )

        .overlay(

            RoundedRectangle(cornerRadius: 17, style: .continuous)

                .stroke(Color.white.opacity(0.08), lineWidth: 1)

        )

    }

    private var liveStatusIcon: String {

        if event.startsAt == nil { return "calendar.badge.clock" }

        if isLiveNow { return "dot.radiowaves.left.and.right" }

        if hasEnded { return "checkmark.seal.fill" }

        return "timer"

    }

    private var liveStatusTitle: String {

        if isOrganizer { return "HOST CONTROLS READY" }

        if isLiveNow { return "LIVE NOW" }

        if hasEnded { return "EVENT COMPLETE" }

        if event.startsAt == nil { return "DATE COMING" }

        return "STARTS \(timeUntilStartText)"

    }

    private var liveStatusSubtitle: String {

        if isOrganizer { return "You are hosting this event." }

        if hasRSVPed { return "You are already RSVP’d." }

        if hasWaitlisted { return "You are already on the waitlist." }

        if isFull && event.waitlistEnabled { return "Event is full — waitlist is available." }

        if isFull { return "Event is currently full." }

        if event.startsAt == nil { return "Schedule will be announced soon." }

        return "Limited access available."

    }

    private var isLiveNow: Bool {

        guard let startsAt = event.startsAt else { return false }

        let endsAt = event.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)

        return now >= startsAt && now <= endsAt

    }

    private var hasEnded: Bool {

        guard let startsAt = event.startsAt else { return false }

        let endsAt = event.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)

        return now > endsAt

    }

    private var timeUntilStartText: String {

        guard let startsAt = event.startsAt else { return "SOON" }

        let seconds = Int(startsAt.timeIntervalSince(now))

        if seconds <= 0 { return "NOW" }

        let days = seconds / 86_400

        let hours = (seconds % 86_400) / 3_600

        let minutes = (seconds % 3_600) / 60

        if days > 0 {

            return "IN \(days)D \(hours)H"

        }

        if hours > 0 {

            return "IN \(hours)H \(minutes)M"

        }

        return "IN \(max(1, minutes))M"

    }

    // MARK: - Primary Action

    private var primaryAction: some View {

        Button {

            handlePrimaryAction()

        } label: {

            HStack(spacing: 10) {

                Image(systemName: primaryIcon)

                Text(primaryTitle)

                    .font(.system(size: 14, weight: .black, design: .monospaced))

                    .tracking(0.9)

            }

            .foregroundColor(primaryForeground)

            .frame(maxWidth: .infinity)

            .padding(.vertical, 15)

            .background(

                RoundedRectangle(cornerRadius: 19, style: .continuous)

                    .fill(primaryBackground)

                    .overlay(

                        RoundedRectangle(cornerRadius: 19, style: .continuous)

                            .stroke(primaryStroke, lineWidth: 1)

                    )

            )

        }

        .buttonStyle(.plain)

        .disabled(primaryDisabled)

    }

    private var primaryDisabled: Bool {

        isOrganizer

        || hasRSVPed

        || hasWaitlisted

        || hasEnded

        || (isFull && !event.waitlistEnabled)

    }

    private var primaryTitle: String {

        if isOrganizer { return "HOSTING" }

        if hasEnded { return "EVENT ENDED" }

        if hasRSVPed { return "ALREADY RSVP'D" }

        if hasWaitlisted { return "WAITLISTED" }

        if isFull && event.waitlistEnabled { return "JOIN WAITLIST" }

        if isFull { return "FULL" }

        return "RSVP NOW"

    }

    private var primaryIcon: String {

        if isOrganizer { return "crown.fill" }

        if hasEnded { return "checkmark.seal.fill" }

        if hasRSVPed { return "checkmark.seal.fill" }

        if hasWaitlisted { return "clock.badge.checkmark" }

        if isFull && event.waitlistEnabled { return "person.crop.circle.badge.plus" }

        if isFull { return "lock.fill" }

        return "bolt.fill"

    }

    private var primaryForeground: Color {

        if primaryDisabled && !hasRSVPed && !hasWaitlisted && !isOrganizer {

            return Color.white.opacity(0.45)

        }

        return Color.black

    }

    private var primaryBackground: Color {

        if primaryDisabled && !hasRSVPed && !hasWaitlisted && !isOrganizer {

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

        if primaryDisabled && !hasRSVPed && !hasWaitlisted && !isOrganizer {

            return Color.white.opacity(0.12)

        }

        return Color.white.opacity(0.20)

    }

    // MARK: - Secondary Buttons

    private var calendarTitle: String {

        if isProcessingCalendar { return "ADDING..." }

        if hasCalendarSaved { return "IN CALENDAR" }

        if !hasDate { return "DATE COMING" }

        return "ADD TO CAL"

    }

    private var calendarIcon: String {

        if hasCalendarSaved { return "calendar.badge.checkmark" }

        if !hasDate { return "calendar.badge.clock" }

        return "calendar.badge.plus"

    }

    private func secondaryButton(

        title: String,

        systemImage: String,

        action: @escaping () -> Void

    ) -> some View {

        Button(action: action) {

            HStack(spacing: 8) {

                Image(systemName: systemImage)

                Text(title)

                    .font(.system(size: 11, weight: .black, design: .monospaced))

                    .lineLimit(1)

                    .minimumScaleFactor(0.68)

            }

            .foregroundColor(.orange)

            .frame(maxWidth: .infinity)

            .padding(.vertical, 13)

            .background(

                RoundedRectangle(cornerRadius: 17, style: .continuous)

                    .fill(Color.orange.opacity(0.11))

                    .overlay(

                        RoundedRectangle(cornerRadius: 17, style: .continuous)

                            .stroke(Color.orange.opacity(0.30), lineWidth: 1)

                    )

            )

        }

        .buttonStyle(.plain)

    }

    // MARK: - RSVP Flow

    private func handlePrimaryAction() {

        HapticManager.instance.impact(.medium)

        SpatialAudioManager.shared.play(.uiTap)

        if isOrganizer {

            app.showEventToast("YOU ARE HOSTING")

            return

        }

        if hasEnded {

            app.showEventToast("EVENT ENDED")

            return

        }

        if hasRSVPed {

            app.showEventToast("ALREADY RSVP'D")

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

        guard event.startsAt != nil else {

            app.showEventToast("DATE COMING")

            return

        }

        guard !hasCalendarSaved else {

            app.showEventToast("REMINDERS SET")

            return

        }

        Task {

            isProcessingCalendar = true

            defer {

                isProcessingCalendar = false

            }

            do {

                try await EventReminderManager.shared.saveEventToCalendar(event)

                try await EventReminderManager.shared.scheduleLocalReminders(for: event)

                savedCalendarIDs.insert(event.id)

                app.showEventToast("REMINDERS SET")

            } catch {

                app.showEventToast("REMINDER FAILED")

                print("⚠️ Event reminder failed: \(error.localizedDescription)")

            }

        }

    }

    // MARK: - Local Calendar Saved Store

    private var savedCalendarIDs: Set<String> {

        get {

            Set(

                savedCalendarIDsRaw

                    .split(separator: ",")

                    .map { String($0) }

                    .filter { !$0.isEmpty }

            )

        }

        nonmutating set {

            savedCalendarIDsRaw = newValue.sorted().joined(separator: ",")

        }

    }

}
