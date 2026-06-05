//
//  EventsView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-16.
//
//  PURPOSE:
//  Premium events destination.
//  - Featured event hero
//  - Live / upcoming event rail
//  - Event unread handling
//  - Premium cinematic presentation
//

import SwiftUI
import Combine

struct EventsView: View {

    @EnvironmentObject private var app: AppState

    @State private var pulse = false
    @State private var now = Date()

    private let timer = Timer
        .publish(every: 20, on: .main, in: .common)
        .autoconnect()

    private var visibleEvents: [AppState.TGEvent] {
        app.events
            .filter { event in
                event.published &&
                event.approvalStatus == "approved" &&
                event.visibility.lowercased() == "public"
            }
            .sorted { lhs, rhs in
                let lhsEnded = isEnded(lhs)
                let rhsEnded = isEnded(rhs)

                if lhsEnded != rhsEnded {
                    return !lhsEnded
                }

                let lhsLive = isLive(lhs)
                let rhsLive = isLive(rhs)

                if lhsLive != rhsLive {
                    return lhsLive
                }

                switch (lhs.startsAt, rhs.startsAt) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.title < rhs.title
                }
            }
    }

    private var activeEvents: [AppState.TGEvent] {
        visibleEvents.filter { !isEnded($0) }
    }

    private var completedEvents: [AppState.TGEvent] {
        visibleEvents.filter { isEnded($0) }
    }

    private var heroEvent: AppState.TGEvent? {
        if let featured = activeEvents.first(where: { $0.featured }) {
            return featured
        }

        if let live = activeEvents.first(where: { isLive($0) }) {
            return live
        }

        return activeEvents.first ?? completedEvents.first
    }

    private var railEvents: [AppState.TGEvent] {
        guard let heroEvent else { return visibleEvents }
        return visibleEvents.filter { $0.id != heroEvent.id }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()
                ambientBackground

                VStack(spacing: 0) {
                    header(safeTop: geo.safeAreaInsets.top)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            if let heroEvent {
                                featuredHero(heroEvent)
                            }

                            if visibleEvents.isEmpty {
                                emptyState
                            } else if !railEvents.isEmpty {
                                eventRail
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 42)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarHidden(true)
        .onAppear {
            app.markEventsRead()

            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onReceive(timer) { value in
            now = value
        }
    }

    private func header(safeTop: CGFloat) -> some View {
        HStack {
            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.setRoute(.hq)
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
                Text("EVENTS")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.6)

                Text(eventsSubtitle)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer()

            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.refreshEvents()
            } label: {
                Image(systemName: app.isRefreshingEvents ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.orange.opacity(0.95))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.orange.opacity(0.18), lineWidth: 1))
                    .rotationEffect(.degrees(app.isRefreshingEvents ? 180 : 0))
                    .animation(.easeInOut(duration: 0.35), value: app.isRefreshingEvents)
            }
            .buttonStyle(.plain)
            .disabled(app.isRefreshingEvents)
            .opacity(app.isRefreshingEvents ? 0.62 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, max(safeTop, 44) + 12)
        .padding(.bottom, 14)
        .background(Color.black.opacity(0.74).ignoresSafeArea(edges: .top))
    }

    private func featuredHero(_ event: AppState.TGEvent) -> some View {
        Button {
            open(event)
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(heroStatusColor(for: event))
                                .frame(width: 8, height: 8)
                                .scaleEffect(isLive(event) && pulse ? 1.22 : 1.0)

                            Text(heroEyebrow(for: event))
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(heroStatusColor(for: event).opacity(0.98))
                                .tracking(2.4)
                        }

                        Text(event.category.uppercased())
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.42))
                            .tracking(1.8)
                    }

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(heroStatusColor(for: event).opacity(pulse ? 0.18 : 0.08))
                            .frame(width: 62, height: 62)
                            .blur(radius: pulse ? 4 : 0)

                        Circle()
                            .stroke(heroStatusColor(for: event).opacity(0.20), lineWidth: 1)
                            .frame(width: 54, height: 54)

                        Image(systemName: heroIcon(for: event))
                            .font(.system(size: 24, weight: .black))
                            .foregroundColor(heroStatusColor(for: event).opacity(0.96))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(event.title)
                        .font(.system(size: event.title.count > 48 ? 30 : 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineSpacing(-2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !event.heroLine.isEmpty {
                        Text(event.heroLine)
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
                                heroStatusColor(for: event).opacity(0.24),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)

                HStack(spacing: 10) {
                    heroStatusPill(for: event)
                    heroTimePill(for: event)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white.opacity(0.46))
                }
            }
            .padding(22)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color.black.opacity(0.84))

                    LinearGradient(
                        colors: [
                            heroStatusColor(for: event).opacity(0.12),
                            Color.blue.opacity(0.055),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(heroStatusColor(for: event).opacity(pulse ? 0.34 : 0.20), lineWidth: 1.2)
            )
            .shadow(color: heroStatusColor(for: event).opacity(0.16), radius: 28, x: 0, y: 16)
        }
        .buttonStyle(.plain)
    }

    private func heroTimePill(for event: AppState.TGEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: timeIcon(for: event))
                .font(.system(size: 11, weight: .black))

            Text(timeString(for: event))
                .font(.system(size: 10, weight: .black, design: .monospaced))
        }
        .foregroundColor(isEnded(event) ? .white.opacity(0.72) : .black)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(isEnded(event) ? Color.white.opacity(0.12) : heroStatusColor(for: event).opacity(0.96))
        )
    }

    private var eventRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(eventRailTitle)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                Spacer()

                Text("\(railEvents.count)")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.42))
            }

            VStack(spacing: 12) {
                ForEach(railEvents) { event in
                    eventCard(event)
                }
            }
        }
    }

    private func eventCard(_ event: AppState.TGEvent) -> some View {
        Button {
            open(event)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(heroStatusColor(for: event).opacity(isEnded(event) ? 0.08 : 0.14))
                        .frame(width: 58, height: 58)

                    Image(systemName: heroIcon(for: event))
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(heroStatusColor(for: event))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(isEnded(event) ? .white.opacity(0.66) : .white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(statusText(for: event))
                        Text("•")
                        Text(timeString(for: event))
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))

                    Text(event.category.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.orange.opacity(isEnded(event) ? 0.52 : 0.82))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(attendeeText(for: event))
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.62))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.white.opacity(0.30))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isEnded(event) ? Color.white.opacity(0.035) : Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isEnded(event) ? Color.white.opacity(0.055) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .opacity(isEnded(event) ? 0.82 : 1)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 96, height: 96)

                Image(systemName: "calendar")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(.orange.opacity(0.92))
            }

            VStack(spacing: 8) {
                Text("NO PUBLIC EVENTS")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                Text("Approved launch moments, tournaments, and live community experiences will appear here.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var ambientBackground: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.orange.opacity(pulse ? 0.14 : 0.08),
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

    private func open(_ event: AppState.TGEvent) {
        HapticManager.instance.impact(.light)
        SpatialAudioManager.shared.play(.uiTap)

        app.selectedEvent = event
        app.setRoute(.eventDetail)
    }

    private var eventsSubtitle: String {
        if app.isRefreshingEvents && visibleEvents.isEmpty {
            return "SYNCING EVENTS"
        }

        if visibleEvents.isEmpty {
            return "NO PUBLIC EVENTS"
        }

        let activeCount = activeEvents.count

        if activeCount == 1 {
            return "1 ACTIVE EVENT"
        }

        return "\(activeCount) ACTIVE EVENTS"
    }

    private var eventRailTitle: String {
        let hasLive = railEvents.contains { isLive($0) }
        let hasUpcoming = railEvents.contains { !isLive($0) && !isEnded($0) }

        if hasLive {
            return "LIVE & UPCOMING"
        }

        if hasUpcoming {
            return "UPCOMING EVENTS"
        }

        return "EVENT ARCHIVE"
    }

    private func attendeeText(for event: AppState.TGEvent) -> String {
        if isEnded(event) {
            return finalAttendanceText(for: event)
        }

        if isFull(event), event.waitlistEnabled {
            return "\(event.waitlistCount) WAITING"
        }

        if event.capacity <= 0 {
            return "\(event.attendeeCount) RSVP"
        }

        return "\(event.attendeeCount)/\(event.capacity)"
    }

    private func finalAttendanceText(for event: AppState.TGEvent) -> String {
        if event.capacity <= 0 {
            return "\(event.attendeeCount) ATTENDED"
        }

        return "\(event.attendeeCount)/\(event.capacity)"
    }

    private func heroEyebrow(for event: AppState.TGEvent) -> String {
        if isLive(event) {
            return "LIVE EVENT"
        }

        if isEnded(event) {
            return "EVENT ARCHIVE"
        }

        if event.featured {
            return "FEATURED EVENT"
        }

        return "UPCOMING EVENT"
    }

    private func heroIcon(for event: AppState.TGEvent) -> String {
        if isLive(event) {
            return "dot.radiowaves.left.and.right"
        }

        if isEnded(event) {
            return "checkmark.seal.fill"
        }

        if isFull(event) {
            return "lock.fill"
        }

        return "bolt.fill"
    }

    private func heroStatusColor(for event: AppState.TGEvent) -> Color {
        if isLive(event) {
            return .orange
        }

        if isEnded(event) {
            return .white.opacity(0.62)
        }

        if isFull(event) {
            return .red
        }

        return .orange
    }

    private func heroStatusPill(for event: AppState.TGEvent) -> some View {
        Text(statusText(for: event))
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundColor(isLive(event) ? .black : .white.opacity(0.88))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(isLive(event) ? Color.orange.opacity(0.96) : Color.white.opacity(0.12))
            )
    }

    private func statusText(for event: AppState.TGEvent) -> String {
        if isLive(event) {
            return "LIVE"
        }

        if isEnded(event) {
            return "ARCHIVED"
        }

        if isFull(event) {
            return event.waitlistEnabled ? "WAITLIST" : "FULL"
        }

        return "OPEN"
    }

    private func timeIcon(for event: AppState.TGEvent) -> String {
        if isEnded(event) {
            return "archivebox.fill"
        }

        if isLive(event) {
            return "dot.radiowaves.left.and.right"
        }

        return "timer"
    }

    private func isLive(_ event: AppState.TGEvent) -> Bool {
        let status = event.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if status == "live" {
            return true
        }

        guard let startsAt = event.startsAt else {
            return false
        }

        let endsAt = event.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)

        return now >= startsAt && now <= endsAt
    }

    private func isEnded(_ event: AppState.TGEvent) -> Bool {
        let status = event.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if status == "ended" || status == "cancelled" {
            return true
        }

        guard let startsAt = event.startsAt else {
            return false
        }

        let endsAt = event.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)

        return now > endsAt
    }

    private func isFull(_ event: AppState.TGEvent) -> Bool {
        event.capacity > 0 && event.attendeeCount >= event.capacity
    }

    private func timeString(for event: AppState.TGEvent) -> String {
        if isEnded(event) {
            return "PAST EVENT"
        }

        if isLive(event) {
            return "LIVE NOW"
        }

        guard let startsAt = event.startsAt else {
            return "DATE COMING"
        }

        let seconds = Int(startsAt.timeIntervalSince(now))

        if seconds <= 0 {
            return "STARTING"
        }

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
}
