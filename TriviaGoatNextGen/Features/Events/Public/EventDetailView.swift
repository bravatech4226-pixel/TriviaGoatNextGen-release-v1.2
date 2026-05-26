//
//  EventDetailView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-16.
//
//  PURPOSE:
//  Public event detail surface.
//  - Premium event destination
//  - RSVP action dock
//  - Calendar/reminder action
//  - Deep-link share payload
//

import SwiftUI
import Combine
import UIKit

struct EventDetailView: View {

    @EnvironmentObject private var app: AppState

    let event: AppState.TGEvent

    @State private var showShareSheet = false
    @State private var now = Date()
    @State private var pulse = false

    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private var currentEvent: AppState.TGEvent {
        app.events.first(where: { $0.id == event.id }) ?? event
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()

                EventDetailAmbientGlow(pulse: pulse, statusColor: statusColor)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    header(safeTop: geo.safeAreaInsets.top)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            heroCard
                            telemetryGrid
                            statusCard
                            detailSection
                            organizerSection
                            actionDock
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 42)
                    }
                }

                toastOverlay
                confirmationMomentOverlay
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .onAppear {
                app.listenToRSVPState(for: event.id)

                withAnimation(.easeInOut(duration: 1.55).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .onReceive(timer) { value in
                now = value
            }
            .sheet(isPresented: $showShareSheet) {
                EventShareSheet(items: eventShareItems)
            }
        }
    }

    private func header(safeTop: CGFloat) -> some View {
        HStack {
            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.setRoute(.events)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text("EVENT DETAILS")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.6)

                Text(headerSubtitle)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.orange.opacity(0.95))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, safeTop + 8)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.72).ignoresSafeArea(edges: .top))
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isLiveNow ? Color.orange : Color.white.opacity(0.22))
                            .frame(width: 8, height: 8)
                            .scaleEffect(isLiveNow && pulse ? 1.18 : 1.0)

                        Text(heroEyebrow)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.95))
                            .tracking(2.4)
                    }

                    Text(currentEvent.category.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                        .tracking(1.8)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(statusColor.opacity(pulse ? 0.18 : 0.08))
                        .frame(width: 62, height: 62)
                        .blur(radius: pulse ? 4 : 0)

                    Circle()
                        .stroke(statusColor.opacity(0.18), lineWidth: 1)
                        .frame(width: 54, height: 54)

                    Image(systemName: statusIcon)
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(statusColor.opacity(0.96))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(currentEvent.title)
                    .font(.system(size: currentEvent.title.count > 48 ? 30 : 34, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)

                if !heroCopy.isEmpty {
                    Text(heroCopy)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            statusColor.opacity(0.24),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            HStack(spacing: 10) {
                statusPill

                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .black))

                    Text(timelineText)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundColor(.black)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Capsule().fill(statusColor.opacity(0.96)))

                Spacer()
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.black.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(statusColor.opacity(pulse ? 0.34 : 0.20), lineWidth: 1.2)
        )
        .shadow(color: statusColor.opacity(0.16), radius: 28, x: 0, y: 16)
    }

    private var telemetryGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                telemetryPill(icon: "calendar", title: "DATE", value: formattedDate)
                telemetryPill(icon: "timer", title: isLiveNow ? "STATUS" : "COUNTDOWN", value: timelineText)
            }

            HStack(spacing: 10) {
                telemetryPill(icon: "person.2.fill", title: "ATTENDING", value: attendeeText)
                telemetryPill(icon: "dot.radiowaves.left.and.right", title: "ACCESS", value: accessText)
            }
        }
    }

    private func telemetryPill(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.orange.opacity(0.92))

                Text(title)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.40))
                    .tracking(1.2)
            }

            Text(value)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.18))
                    .frame(width: 42, height: 42)

                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                Text(statusSubtitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(statusColor.opacity(0.22), lineWidth: 1))
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EVENT BRIEFING")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            Text(currentEvent.summary.isEmpty ? "More event details coming soon." : currentEvent.summary)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var organizerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ORGANIZER")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: isOrganizer ? "star.circle.fill" : "person.crop.circle.fill")
                        .font(.system(size: 25, weight: .black))
                        .foregroundColor(.orange.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(organizerDisplayName)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white)

                    Text(isOrganizer ? "YOU ARE HOSTING THIS EVENT" : hostedBySubtitle)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.48))
                        .tracking(0.8)
                }

                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.orange.opacity(0.72))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var actionDock: some View {
        EventActionDock(
            event: currentEvent,
            onShare: {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                showShareSheet = true
            }
        )
    }

    private var statusPill: some View {
        Text(statusTitle)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundColor(statusPillForeground)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Capsule().fill(statusPillBackground))
    }

    private var eventShareURL: URL {
        URL(string: "https://triviagoat.ca/events/\(currentEvent.id)")!
    }

    private var eventShareText: String {
        var lines: [String] = []

        lines.append(currentEvent.title)

        if !currentEvent.heroLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(currentEvent.heroLine)
        }

        lines.append(formattedDate)
        lines.append(eventShareURL.absoluteString)

        return lines.joined(separator: "\n")
    }

    private var eventShareItems: [Any] {
        [eventShareText, eventShareURL]
    }

    private var isOrganizer: Bool {
        app.isOrganizer(of: currentEvent)
    }

    private var isRegistered: Bool {
        app.hasRSVPedToEvent(currentEvent.id)
    }

    private var heroCopy: String {
        let hero = currentEvent.heroLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hero.isEmpty { return hero }

        return currentEvent.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var headerSubtitle: String {
        if isLiveNow { return "LIVE NOW" }
        if hasEnded { return "EVENT COMPLETE" }
        return currentEvent.category.uppercased()
    }

    private var heroEyebrow: String {
        if isLiveNow { return "LIVE EVENT" }
        if currentEvent.featured { return "FEATURED EVENT" }
        return "EVENT"
    }

    private var organizerDisplayName: String {
        let cleaned = (currentEvent.organizerName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "Trivia GOAT" : cleaned
    }

    private var hostedBySubtitle: String {
        organizerDisplayName.caseInsensitiveCompare("Trivia GOAT") == .orderedSame
            ? "OFFICIAL PLATFORM EVENT"
            : "EVENT HOST"
    }

    private var formattedDate: String {
        guard let startsAt = currentEvent.startsAt else {
            return "DATE COMING"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, MMM d • h:mm a"

        return formatter.string(from: startsAt).uppercased()
    }

    private var attendeeText: String {
        guard currentEvent.capacity > 0 else {
            return "\(currentEvent.attendeeCount) RSVP"
        }

        if currentEvent.attendeeCount >= currentEvent.capacity {
            return "FULL"
        }

        return "\(currentEvent.attendeeCount)/\(currentEvent.capacity) RSVP"
    }

    private var accessText: String {
        if hasEnded { return "CLOSED" }
        if isLiveNow { return "LIVE" }
        if isFull { return currentEvent.waitlistEnabled ? "WAITLIST" : "FULL" }
        return currentEvent.locationType.uppercased()
    }

    private var statusTitle: String {
        if isOrganizer { return "HOSTING" }
        if isRegistered { return "REGISTERED" }
        if hasEnded { return "ENDED" }
        if isLiveNow { return "LIVE" }
        if isFull { return currentEvent.waitlistEnabled ? "WAITLIST" : "FULL" }
        if currentEvent.published { return "OPEN RSVP" }
        return currentEvent.approvalStatus.uppercased()
    }

    private var statusSubtitle: String {
        if isOrganizer { return "Organizer access is enabled for this event." }
        if isRegistered { return "You're registered. Add it to calendar or share the event." }
        if hasEnded { return "This event has ended." }
        if isLiveNow { return "This event is active right now. Stay close to the action." }
        if currentEvent.startsAt == nil { return "Schedule will be announced soon." }
        if isFull && currentEvent.waitlistEnabled { return "Capacity is full, but the waitlist is open." }
        if isFull { return "This event is currently full." }
        return "Limited access is available. RSVP to lock in your spot."
    }

    private var statusIcon: String {
        if isOrganizer { return "crown.fill" }
        if isRegistered { return "checkmark.seal.fill" }
        if hasEnded { return "checkmark.circle.fill" }
        if isLiveNow { return "dot.radiowaves.left.and.right" }
        if isFull { return "lock.fill" }
        if currentEvent.startsAt == nil { return "calendar.badge.clock" }
        return "bolt.fill"
    }

    private var statusColor: Color {
        if isOrganizer { return .white }
        if isRegistered { return .green }
        if hasEnded { return .white.opacity(0.55) }
        if isLiveNow { return .orange }
        if isFull { return .red }
        return .orange
    }

    private var statusPillForeground: Color {
        if isRegistered || isLiveNow { return .black }
        return .white.opacity(0.88)
    }

    private var statusPillBackground: Color {
        if isRegistered { return .green.opacity(0.95) }
        if isLiveNow { return .orange.opacity(0.96) }
        if hasEnded { return .white.opacity(0.12) }
        if isFull { return .red.opacity(0.30) }
        return .white.opacity(0.12)
    }

    private var isLiveNow: Bool {
        guard let startsAt = currentEvent.startsAt else { return false }
        let endsAt = currentEvent.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        return now >= startsAt && now <= endsAt
    }

    private var hasEnded: Bool {
        guard let startsAt = currentEvent.startsAt else { return false }
        let endsAt = currentEvent.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        return now > endsAt
    }

    private var isFull: Bool {
        currentEvent.capacity > 0 && currentEvent.attendeeCount >= currentEvent.capacity
    }

    private var timelineText: String {
        if hasEnded { return "COMPLETE" }
        if isLiveNow { return "LIVE NOW" }

        guard let startsAt = currentEvent.startsAt else {
            return "SOON"
        }

        let seconds = Int(startsAt.timeIntervalSince(now))

        if seconds <= 0 { return "NOW" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)D \(hours)H"
        }

        if hours > 0 {
            return "\(hours)H \(minutes)M"
        }

        return "\(max(1, minutes))M"
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = app.eventRSVPToastMessage {
            VStack {
                Spacer()

                Text(toast)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.orange.opacity(0.96)))
                    .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
                    .padding(.bottom, 34)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .allowsHitTesting(false)
            .zIndex(99)
        }
    }

    @ViewBuilder
    private var confirmationMomentOverlay: some View {
        if let confirmedEvent = app.eventConfirmationMoment,
           confirmedEvent.id == currentEvent.id {
            ZStack {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Color.green.opacity(0.24),
                        Color.orange.opacity(0.10),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 320
                )
                .ignoresSafeArea()

                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.18))
                            .frame(width: 112, height: 112)
                            .blur(radius: 12)

                        Circle()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            .frame(width: 92, height: 92)

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 38, weight: .black))
                            .foregroundColor(.green.opacity(0.96))
                    }

                    Text("ACCESS CONFIRMED")
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(confirmedEvent.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 28)
                }
                .padding(.horizontal, 24)
            }
            .transition(.opacity.combined(with: .scale(scale: 1.02)))
            .zIndex(120)
            .allowsHitTesting(false)
        }
    }
}

private struct EventDetailAmbientGlow: View {
    let pulse: Bool
    let statusColor: Color

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    statusColor.opacity(pulse ? 0.12 : 0.06),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 320
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.clear,
                    Color.white.opacity(0.018),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}
