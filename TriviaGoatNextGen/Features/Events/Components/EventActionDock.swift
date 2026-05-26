//
//  EventActionDock.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-16.
//
//  PURPOSE:
//  Public event CTA dock.
//  Handles RSVP / waitlist / calendar / share presentation.
//  Synced to latest AppState event ecosystem.
//

import SwiftUI
import Combine

struct EventActionDock: View {

    @EnvironmentObject private var app: AppState

    let event: AppState.TGEvent
    let onShare: () -> Void

    @State private var isProcessingCalendar = false
    @State private var now = Date()
    @State private var pulse = false

    @AppStorage("tg.events.calendarSavedIDs")
    private var savedCalendarIDsRaw: String = ""

    private let timer = Timer
        .publish(every: 30, on: .main, in: .common)
        .autoconnect()

    private var syncedEvent: AppState.TGEvent {
        app.events.first(where: { $0.id == event.id }) ?? event
    }

    var body: some View {
        VStack(spacing: 12) {
            commandHeader
            liveStatusStrip
            primaryAction
            secondaryActionRow
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(dockStrokeColor, lineWidth: 1.15)
                )
                .shadow(color: dockGlowColor, radius: 24, x: 0, y: 14)
        )
        .onAppear {
            app.listenToRSVPState(for: syncedEvent.id)

            withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onReceive(timer) { value in
            now = value
        }
    }

    // MARK: - Header

    private var commandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(pulse ? 0.18 : 0.08))
                    .frame(width: 38, height: 38)

                Image(systemName: primaryIcon)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(statusColor.opacity(0.96))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(commandTitle)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.4)

                Text(commandSubtitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.64))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            statusPill
        }
    }

    // MARK: - Status Strip

    private var liveStatusStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: liveStatusIcon)
                .font(.system(size: 12, weight: .black))
                .foregroundColor(statusColor.opacity(0.94))

            VStack(alignment: .leading, spacing: 2) {
                Text(liveStatusTitle)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.84))
                    .tracking(0.8)

                Text(liveStatusSubtitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.54))
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Primary CTA

    private var primaryAction: some View {
        Button {
            handlePrimaryAction()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 13, weight: .black))

                Text(primaryTitle)
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(0.9)
            }
            .foregroundColor(primaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(primaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(primaryStroke, lineWidth: 1)
                    )
            )
            .shadow(
                color: primaryShadow,
                radius: primaryDisabled ? 0 : 16,
                x: 0,
                y: 10
            )
        }
        .buttonStyle(.plain)
        .disabled(primaryDisabled)
    }

    // MARK: - Secondary CTA Row

    private var secondaryActionRow: some View {
        HStack(spacing: 10) {

            secondaryButton(
                title: calendarTitle,
                systemImage: calendarIcon,
                isProcessing: isProcessingCalendar
            ) {
                saveCalendarAndReminders()
            }
            .disabled(isProcessingCalendar || !hasDate || hasCalendarSaved)
            .opacity(hasDate ? 1 : 0.45)

            secondaryButton(
                title: "SHARE",
                systemImage: "square.and.arrow.up",
                isProcessing: false
            ) {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                onShare()
            }
        }
    }

    private func secondaryButton(
        title: String,
        systemImage: String,
        isProcessing: Bool,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isProcessing ? "arrow.triangle.2.circlepath" : systemImage)
                    .font(.system(size: 12, weight: .black))
                    .rotationEffect(.degrees(isProcessing && pulse ? 360 : 0))
                    .animation(
                        isProcessing
                        ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                        : .default,
                        value: pulse
                    )

                Text(title)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.orange.opacity(0.105))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.28), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Pill

    private var statusPill: some View {
        Text(statusPillText)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundColor(statusPillForeground)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(
                Capsule()
                    .fill(statusPillBackground)
            )
    }

    // MARK: - State

    private var isOrganizer: Bool {
        app.isOrganizer(of: syncedEvent)
    }

    private var hasRSVPed: Bool {
        app.hasRSVPedToEvent(syncedEvent.id)
    }

    private var hasWaitlisted: Bool {
        app.hasJoinedWaitlist(syncedEvent.id)
    }

    private var isFull: Bool {
        syncedEvent.capacity > 0 &&
        syncedEvent.attendeeCount >= syncedEvent.capacity
    }

    private var hasDate: Bool {
        syncedEvent.startsAt != nil
    }

    private var hasCalendarSaved: Bool {
        savedCalendarIDs.contains(syncedEvent.id)
    }

    private var isLiveNow: Bool {
        guard let startsAt = syncedEvent.startsAt else { return false }

        let endsAt = syncedEvent.endsAt
        ?? startsAt.addingTimeInterval(2 * 60 * 60)

        return now >= startsAt && now <= endsAt
    }

    private var hasEnded: Bool {
        guard let startsAt = syncedEvent.startsAt else { return false }

        let endsAt = syncedEvent.endsAt
        ?? startsAt.addingTimeInterval(2 * 60 * 60)

        return now > endsAt
    }

    // MARK: - Copy

    private var commandTitle: String {
        if isOrganizer { return "HOST COMMAND" }
        if hasRSVPed { return "ACCESS CONFIRMED" }
        if hasWaitlisted { return "WAITLIST ACTIVE" }
        if hasEnded { return "EVENT CLOSED" }
        if isLiveNow { return "LIVE EVENT ACCESS" }
        return "EVENT COMMAND"
    }

    private var commandSubtitle: String {
        if isOrganizer {
            return "You are hosting this event."
        }

        if hasRSVPed {
            return "You’re locked in. Add it to calendar or share the event."
        }

        if hasWaitlisted {
            return "You’re on the waitlist. Watch for updates."
        }

        if hasEnded {
            return "This event has completed."
        }

        if isFull && syncedEvent.waitlistEnabled {
            return "Capacity is full, but waitlist access is open."
        }

        if isFull {
            return "This event is currently full."
        }

        if isLiveNow { return "Live event access is currently active." }

        return "RSVP, save the date, or share the event."
    }

    // MARK: - Status Strip Copy

    private var liveStatusIcon: String {
        if syncedEvent.startsAt == nil {
            return "calendar.badge.clock"
        }

        if isLiveNow {
            return "dot.radiowaves.left.and.right"
        }

        if hasEnded {
            return "checkmark.seal.fill"
        }

        return "timer"
    }

    private var liveStatusTitle: String {
        if isOrganizer { return "HOST CONTROLS READY" }
        if isLiveNow { return "LIVE NOW" }
        if hasEnded { return "EVENT COMPLETE" }
        if syncedEvent.startsAt == nil { return "DATE COMING" }

        return "STARTS \(timeUntilStartText)"
    }

    private var liveStatusSubtitle: String {
        if isOrganizer {
            return "Organizer state is active."
        }

        if hasRSVPed {
            return "You're confirmed and ready for launch."
        }

        if hasWaitlisted {
            return "Waitlisted — watch for capacity changes."
        }

        if isLiveNow {
            return "This event is happening right now."
        }

        if isFull && event.waitlistEnabled {
            return "Event is full — waitlist access is available."
        }

        if isFull {
            return "This event is currently full."
        }

        if event.startsAt == nil {
            return "Schedule will be announced soon."
        }

        return "Secure your spot before launch."
    }

    private var timeUntilStartText: String {
        guard let startsAt = syncedEvent.startsAt else {
            return "SOON"
        }

        let seconds = Int(startsAt.timeIntervalSince(now))

        if seconds <= 0 {
            return "NOW"
        }

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

    // MARK: - Primary Action State

    private var primaryDisabled: Bool {
        isOrganizer ||
        hasRSVPed ||
        hasWaitlisted ||
        hasEnded ||
        isLiveNow ||
        (isFull && !event.waitlistEnabled)
    }

    private var primaryTitle: String {
        if isOrganizer { return "HOSTING" }
        if hasEnded { return "EVENT ENDED" }
        if hasRSVPed { return "REGISTERED" }
        if hasWaitlisted { return "WAITLISTED" }
        if isLiveNow { return "EVENT LIVE" }
        if isFull && event.waitlistEnabled { return "JOIN WAITLIST" }
        if isFull { return "FULL" }
        return "RSVP NOW"
    }

    private var primaryIcon: String {
        if isOrganizer { return "crown.fill" }
        if hasEnded { return "checkmark.seal.fill" }
        if hasRSVPed { return "checkmark.seal.fill" }
        if hasWaitlisted { return "clock.badge.checkmark" }
        if isLiveNow { return "dot.radiowaves.left.and.right" }
        if isFull && event.waitlistEnabled { return "person.crop.circle.badge.plus" }
        if isFull { return "lock.fill" }
        return "bolt.fill"
    }

    private var primaryForeground: Color {
        if primaryDisabled &&
            !hasRSVPed &&
            !hasWaitlisted &&
            !isOrganizer {
            return Color.white.opacity(0.45)
        }

        return .black
    }

    private var primaryBackground: Color {
        if primaryDisabled &&
            !hasRSVPed &&
            !hasWaitlisted &&
            !isOrganizer {
            return Color.white.opacity(0.08)
        }

        if hasRSVPed {
            return Color.green.opacity(0.96)
        }

        if isOrganizer {
            return Color.white.opacity(0.92)
        }

        if hasWaitlisted {
            return Color.orange.opacity(0.85)
        }

        return Color.orange.opacity(0.96)
    }

    private var primaryStroke: Color {
        if primaryDisabled &&
            !hasRSVPed &&
            !hasWaitlisted &&
            !isOrganizer {
            return Color.white.opacity(0.12)
        }

        return Color.white.opacity(0.20)
    }

    private var primaryShadow: Color {
        if hasRSVPed {
            return Color.green.opacity(0.16)
        }

        return Color.orange.opacity(0.20)
    }

    // MARK: - Secondary Buttons

    private var calendarTitle: String {
        if isProcessingCalendar {
            return "ADDING..."
        }

        if hasCalendarSaved {
            return "IN CALENDAR"
        }

        if !hasDate {
            return "DATE COMING"
        }

        return "ADD TO CAL"
    }

    private var calendarIcon: String {
        if hasCalendarSaved {
            return "calendar.badge.checkmark"
        }

        if !hasDate {
            return "calendar.badge.clock"
        }

        return "calendar.badge.plus"
    }

    // MARK: - Styling

    private var statusPillText: String {
        if isOrganizer { return "HOST" }
        if hasRSVPed { return "IN" }
        if hasWaitlisted { return "WAITLIST" }
        if hasEnded { return "CLOSED" }
        if isLiveNow { return "LIVE" }

        if isFull {
            return syncedEvent.waitlistEnabled
            ? "WAITLIST"
            : "FULL"
        }

        return "OPEN"
    }

    private var statusColor: Color {
        if isOrganizer { return .white }
        if hasRSVPed { return .green }
        if hasEnded { return .white.opacity(0.58) }
        if isLiveNow { return .orange }
        if isFull { return .red }

        return .orange
    }

    private var statusPillForeground: Color {
        if hasRSVPed || isLiveNow {
            return .black
        }

        return .white.opacity(0.88)
    }

    private var statusPillBackground: Color {
        if hasRSVPed {
            return .green.opacity(0.95)
        }

        if isLiveNow {
            return .orange.opacity(0.96)
        }

        if hasEnded {
            return .white.opacity(0.12)
        }

        if isFull {
            return .red.opacity(0.30)
        }

        return .white.opacity(0.12)
    }

    private var dockStrokeColor: Color {
        statusColor.opacity(pulse ? 0.30 : 0.14)
    }

    private var dockGlowColor: Color {
        statusColor.opacity(0.16)
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
        if isLiveNow {
            app.showEventToast("EVENT ALREADY LIVE")
            return
        }

        if hasRSVPed {
            app.showEventToast("ALREADY REGISTERED")
            return
        }

        if hasWaitlisted {
            app.showEventToast("ALREADY WAITLISTED")
            return
        }

        if isFull {

            if syncedEvent.waitlistEnabled {
                app.joinEventWaitlist(syncedEvent)
            } else {
                app.showEventToast("EVENT FULL")
            }

            return
        }

        app.RSVPToEvent(syncedEvent)
    }

    // MARK: - Calendar Flow

    private func saveCalendarAndReminders() {

        guard syncedEvent.startsAt != nil else {
            app.showEventToast("DATE COMING")
            return
        }

        guard !hasCalendarSaved else {
            app.showEventToast("ALREADY IN CALENDAR")
            return
        }

        Task {
            isProcessingCalendar = true

            defer {
                isProcessingCalendar = false
            }

            do {
                let calendarEventID = try await EventReminderManager.shared
                    .saveEventToCalendar(syncedEvent)

                print("📅 Saved Apple Calendar EKEvent ID:", calendarEventID)

                try? await EventReminderManager.shared
                    .scheduleLocalReminders(for: syncedEvent)

                savedCalendarIDs.insert(syncedEvent.id)

                app.showEventToast("ADDED TO CALENDAR")

            } catch {

                app.showEventToast("CALENDAR FAILED")

                print(
                    "⚠️ Event calendar save failed:",
                    error.localizedDescription
                )
            }
        }
    }

    // MARK: - Calendar Saved Store

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
            savedCalendarIDsRaw = newValue
                .sorted()
                .joined(separator: ",")
        }
    }
}
