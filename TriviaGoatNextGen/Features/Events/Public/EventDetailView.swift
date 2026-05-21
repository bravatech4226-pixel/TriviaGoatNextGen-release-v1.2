//
//  EventDetailView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-16.
//
//  PURPOSE:
//  Public event detail surface.
//  - Event detail presentation
//  - RSVP action dock
//  - Deep-link share payload
//

import SwiftUI
import Combine
import UIKit

struct EventDetailView: View {

    @EnvironmentObject private var app: AppState

    let event: AppState.TGEvent

    @State private var showShareSheet = false

    private var currentEvent: AppState.TGEvent {
        app.events.first(where: { $0.id == event.id }) ?? event
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()

                VStack(spacing: 0) {
                    header(safeTop: geo.safeAreaInsets.top)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            heroCard
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
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .onAppear {
                app.listenToRSVPState(for: event.id)
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

                Text(currentEvent.category.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, safeTop + 8)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.72).ignoresSafeArea(edges: .top))
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(currentEvent.featured ? "FEATURED EVENT" : "EVENT")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(2.4)

                Spacer()

                if currentEvent.published {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(.green.opacity(0.95))
                }
            }

            Text(currentEvent.title)
                .font(.system(size: currentEvent.title.count > 48 ? 30 : 34, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(4)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            if !currentEvent.heroLine.isEmpty {
                Text(currentEvent.heroLine)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            organizerLine

            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 10) {
                detailMetaRow(icon: "calendar", text: formattedDate)
                detailMetaRow(icon: "dot.radiowaves.left.and.right", text: currentEvent.locationType.uppercased())

                if shouldShowAttendeeCount {
                    detailMetaRow(icon: "person.2.fill", text: attendeeText)
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 14)
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.18))
                    .frame(width: 38, height: 38)

                Image(systemName: statusIcon)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                Text(statusSubtitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.66))
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(statusColor.opacity(0.22), lineWidth: 1)
        )
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DETAILS")
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
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var organizerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ORGANIZER")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            HStack(spacing: 12) {
                Image(systemName: isOrganizer ? "star.circle.fill" : "person.crop.circle.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.orange.opacity(0.9))

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
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
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

    @ViewBuilder
    private var organizerLine: some View {
        if !organizerDisplayName.isEmpty {
            Text(hostedByText(for: organizerDisplayName))
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.46))
                .tracking(1.2)
        }
    }

    private func detailMetaRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
                .foregroundColor(.orange.opacity(0.92))

            Text(text)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.78))

            Spacer()
        }
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

    private func hostedByText(for organizerName: String) -> String {
        let cleaned = organizerName.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.caseInsensitiveCompare("Trivia GOAT") == .orderedSame {
            return "OFFICIAL TRIVIA GOAT EVENT"
        }

        return "HOSTED BY \(cleaned.uppercased())"
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

    private var shouldShowAttendeeCount: Bool {
        currentEvent.attendeeCount > 0 ||
        (currentEvent.capacity > 0 && currentEvent.attendeeCount >= currentEvent.capacity)
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

    private var statusTitle: String {
        if isOrganizer { return "HOSTING" }
        if app.hasRSVPedToEvent(currentEvent.id) { return "REGISTERED" }
        if currentEvent.published { return "OPEN RSVP" }
        return currentEvent.approvalStatus.uppercased()
    }

    private var statusSubtitle: String {
        if isOrganizer { return "Organizer access enabled" }
        if app.hasRSVPedToEvent(currentEvent.id) { return "You're registered for this event" }
        if currentEvent.startsAt == nil { return "Schedule will be announced soon" }
        if currentEvent.published { return "Limited access available" }
        return "Event access is not currently public"
    }

    private var statusIcon: String {
        if isOrganizer { return "crown.fill" }
        if app.hasRSVPedToEvent(currentEvent.id) { return "checkmark.seal.fill" }
        if currentEvent.startsAt == nil { return "calendar.badge.clock" }
        if currentEvent.published { return "bolt.fill" }
        return "lock.fill"
    }

    private var statusColor: Color {
        if isOrganizer { return .white }
        if app.hasRSVPedToEvent(currentEvent.id) { return .green }
        if currentEvent.startsAt == nil { return .orange }
        if currentEvent.published { return .orange }
        return .red
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
}


