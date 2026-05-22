//
//  EventsView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-11.
//
//  PURPOSE:
//  Premium Events ecosystem landing surface.
//

import SwiftUI
import Combine

struct EventsView: View {

    @EnvironmentObject private var app: AppState

    @State private var now = Date()
    @State private var pulse = false
    @State private var attendeeFlashEventIDs: Set<String> = []
    @State private var lastAttendeeCountsByEventID: [String: Int] = [:]

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()

                AmbientEventGlow(pulse: pulse)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar(safeTop: geo.safeAreaInsets.top)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            commandSummary

                            if let featured = app.featuredEvent {
                                featuredGatewayCard(featured)
                            }

                            if app.isRefreshingEvents && app.events.isEmpty {
                                loadingState
                            } else if app.events.isEmpty {
                                emptyState
                            } else {
                                eventListSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 42)
                    }
                    .refreshable {
                        app.refreshEvents()
                    }
                }

                toastOverlay
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .onAppear {
                app.openEvents()
                app.markEventsRead()
                startRSVPListeners(for: app.events)
                captureAttendeeCounts(app.events)

                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .onReceive(timer) { value in
                now = value
            }
            .onChange(of: app.events) { _, events in
                startRSVPListeners(for: events)
                detectAttendeeMomentum(events)
            }
        }
    }

    private var nonFeaturedEvents: [AppState.TGEvent] {
        guard let featuredID = app.featuredEvent?.id else {
            return app.events
        }

        return app.events.filter { $0.id != featuredID }
    }

    private var upcomingEvents: [AppState.TGEvent] {
        app.events.filter { !hasEnded($0) }
    }

    private var liveEvents: [AppState.TGEvent] {
        app.events.filter { isLiveNow($0) }
    }

    private var nextEvent: AppState.TGEvent? {
        upcomingEvents
            .filter { $0.startsAt != nil }
            .sorted {
                ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture)
            }
            .first
    }

    private var publishedEventCount: Int {
        app.events.filter { $0.published }.count
    }

    private func topBar(safeTop: CGFloat) -> some View {
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

                Text(liveEvents.isEmpty ? "Launches, tournaments, and live drops" : "Live event activity is active")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .lineLimit(1)
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
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .rotationEffect(.degrees(app.isRefreshingEvents ? 180 : 0))
                    .animation(.easeInOut(duration: 0.35), value: app.isRefreshingEvents)
            }
            .buttonStyle(.plain)
            .disabled(app.isRefreshingEvents)
            .opacity(app.isRefreshingEvents ? 0.55 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, safeTop + 8)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.72).ignoresSafeArea(edges: .top))
    }

    private var commandSummary: some View {
        HStack(spacing: 10) {
            summaryChip(title: "LIVE", value: "\(liveEvents.count)", icon: "dot.radiowaves.left.and.right", color: .orange)
            summaryChip(title: "EVENTS", value: "\(publishedEventCount)", icon: "square.stack.3d.up.fill", color: .orange)
            summaryChip(title: "NEXT", value: nextEvent == nil ? "SOON" : timeUntilText(for: nextEvent!), icon: "timer", color: .orange)
        }
    }

    private func summaryChip(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(color.opacity(0.95))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.42))
                    .tracking(1.1)

                Text(value)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
    }

    private func featuredGatewayCard(_ event: AppState.TGEvent) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isLiveNow(event) ? Color.orange : Color.white.opacity(0.22))
                            .frame(width: 8, height: 8)
                            .scaleEffect(isLiveNow(event) && pulse ? 1.18 : 1.0)

                        Text(isLiveNow(event) ? "LIVE FEATURED EVENT" : "FEATURED EVENT")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.95))
                            .tracking(2.6)
                    }

                    Text(event.category.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                        .tracking(1.8)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(pulse ? 0.16 : 0.08))
                        .frame(width: 62, height: 62)
                        .blur(radius: pulse ? 4 : 0)

                    Circle()
                        .stroke(Color.orange.opacity(0.16), lineWidth: 1)
                        .frame(width: 54, height: 54)

                    Image(systemName: isLiveNow(event) ? "dot.radiowaves.left.and.right" : "calendar.badge.clock")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(.orange.opacity(0.96))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(event.title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(event.heroLine.isEmpty ? event.summary : event.heroLine)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    telemetryPill(icon: "calendar", title: "DATE", value: dateText(event.startsAt))
                    telemetryPill(icon: "timer", title: isLiveNow(event) ? "STATUS" : "COUNTDOWN", value: timelineText(for: event))
                }

                HStack(spacing: 10) {
                    telemetryPill(
                        icon: isAttendeeMomentumActive(for: event) ? "person.2.badge.plus" : "person.2.fill",
                        title: isAttendeeMomentumActive(for: event) ? "MOMENTUM" : "ATTENDING",
                        value: attendeeDisplayText(for: event)
                    )
                    telemetryPill(icon: "dot.radiowaves.left.and.right", title: "ACCESS", value: statusText(for: event))
                }
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.orange.opacity(0.22),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            HStack(spacing: 12) {
                Button {
                    openDetail(event)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                        Text("ENTER EVENT")
                    }
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    HapticManager.instance.impact(.medium)
                    SpatialAudioManager.shared.play(.uiTap)

                    if app.hasRSVPedToEvent(event.id) {
                        app.showEventToast("ALREADY REGISTERED")
                        return
                    }

                    if app.isOrganizer(of: event) {
                        app.showEventToast("YOU ARE HOSTING")
                        return
                    }

                    app.RSVPToEvent(event)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: rsvpIcon(for: event))
                            .font(.system(size: 12, weight: .black))

                        Text(rsvpTitle(for: event))
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .tracking(1.2)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 14).fill(rsvpBackground(for: event)))
                }
                .buttonStyle(.plain)
                .disabled(app.hasRSVPedToEvent(event.id) || app.isOrganizer(of: event) || hasEnded(event))
                .opacity(hasEnded(event) ? 0.55 : 1)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.black.opacity(0.84)))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color.orange.opacity(pulse ? 0.34 : 0.18), lineWidth: 1.2))
        .shadow(color: Color.orange.opacity(0.16), radius: 28, x: 0, y: 16)
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .onAppear {
            app.listenToRSVPState(for: event.id)
        }
    }

    private var eventListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !nonFeaturedEvents.isEmpty {
                HStack {
                    Text("UPCOMING")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.50))
                        .tracking(2)

                    Spacer()

                    Text("\(nonFeaturedEvents.count)")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 9)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                }

                ForEach(nonFeaturedEvents) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: AppState.TGEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(event.category.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.82))
                    .tracking(1.4)

                Spacer()

                statusPill(for: event)
            }

            Text(event.title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(3)

            if !event.summary.isEmpty {
                Text(event.summary)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.66))
                    .lineLimit(3)
            }

            eventMetaGrid(event)
            rsvpButton(event)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.orange.opacity(0.18), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            openDetail(event)
        }
        .onAppear {
            app.listenToRSVPState(for: event.id)
        }
    }

    @ViewBuilder
    private func eventMetaGrid(_ event: AppState.TGEvent) -> some View {
        HStack(spacing: 8) {
            metaChip(icon: "calendar", text: dateText(event.startsAt))
            metaChip(icon: "timer", text: timelineText(for: event))

            if shouldShowAttendeeCount(for: event) {
                metaChip(
                    icon: isAttendeeMomentumActive(for: event) ? "person.2.badge.plus" : "person.2.fill",
                    text: attendeeDisplayText(for: event),
                    isHot: isAttendeeMomentumActive(for: event)
                )
            }
        }
    }

    private func metaChip(icon: String, text: String, isHot: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .black))

            Text(text)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .foregroundColor(isHot ? .black : .white.opacity(0.72))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(
            Capsule()
                .fill(isHot ? Color.orange.opacity(0.96) : Color.white.opacity(0.07))
        )
        .scaleEffect(isHot && pulse ? 1.025 : 1.0)
        .animation(.easeInOut(duration: 0.22), value: isHot)
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
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func statusPill(for event: AppState.TGEvent) -> some View {
        Text(statusText(for: event))
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundColor(statusForeground(for: event))
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(Capsule().fill(statusBackground(for: event)))
    }

    private func rsvpButton(_ event: AppState.TGEvent) -> some View {
        Button {
            HapticManager.instance.impact(.medium)
            SpatialAudioManager.shared.play(.uiTap)

            if app.hasRSVPedToEvent(event.id) {
                app.showEventToast("ALREADY REGISTERED")
                return
            }

            if app.isOrganizer(of: event) {
                app.showEventToast("YOU ARE HOSTING")
                return
            }

            app.RSVPToEvent(event)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: rsvpIcon(for: event))
                    .font(.system(size: 11, weight: .black))

                Text(rsvpTitle(for: event))
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.1)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(rsvpBackground(for: event)))
        }
        .buttonStyle(.plain)
        .disabled(app.hasRSVPedToEvent(event.id) || app.isOrganizer(of: event) || hasEnded(event))
        .opacity(hasEnded(event) ? 0.55 : 1)
    }

    private func openDetail(_ event: AppState.TGEvent) {
        HapticManager.instance.impact(.light)
        SpatialAudioManager.shared.play(.uiTap)
        app.listenToRSVPState(for: event.id)
        app.selectedEvent = event
        app.setRoute(.eventDetail)
    }

    private func startRSVPListeners(for events: [AppState.TGEvent]) {
        if let featured = app.featuredEvent {
            app.listenToRSVPState(for: featured.id)
        }

        for event in events {
            app.listenToRSVPState(for: event.id)
        }
    }
    private func captureAttendeeCounts(_ events: [AppState.TGEvent]) {
        lastAttendeeCountsByEventID = Dictionary(
            uniqueKeysWithValues: events.map { ($0.id, $0.attendeeCount) }
        )
    }

    private func detectAttendeeMomentum(_ events: [AppState.TGEvent]) {
        for event in events {
            let previous = lastAttendeeCountsByEventID[event.id] ?? event.attendeeCount

            if event.attendeeCount > previous {
                attendeeFlashEventIDs.insert(event.id)

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    attendeeFlashEventIDs.remove(event.id)
                }
            }

            lastAttendeeCountsByEventID[event.id] = event.attendeeCount
        }
    }

    private func isAttendeeMomentumActive(for event: AppState.TGEvent) -> Bool {
        attendeeFlashEventIDs.contains(event.id)
    }

    private func shouldShowAttendeeCount(for event: AppState.TGEvent) -> Bool {
        event.attendeeCount > 0 || event.capacity > 0 && event.attendeeCount >= event.capacity
    }

    private func attendeeDisplayText(for event: AppState.TGEvent) -> String {
        guard event.capacity > 0 else {
            return "\(event.attendeeCount) RSVP"
        }

        if event.attendeeCount >= event.capacity {
            return "FULL"
        }

        return "\(event.attendeeCount)/\(event.capacity) RSVP"
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "DATE COMING" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d • h:mm a"
        formatter.timeZone = .current

        return formatter.string(from: date).uppercased()
    }

    private func statusText(for event: AppState.TGEvent) -> String {
        if app.isOrganizer(of: event) { return "HOSTING" }
        if app.hasRSVPedToEvent(event.id) { return "REGISTERED" }
        if hasEnded(event) { return "ENDED" }
        if isLiveNow(event) { return "LIVE" }
        if isFull(event) { return event.waitlistEnabled ? "WAITLIST" : "FULL" }
        return "OPEN"
    }

    private func statusForeground(for event: AppState.TGEvent) -> Color {
        if isLiveNow(event) || app.hasRSVPedToEvent(event.id) {
            return .black
        }

        return .white.opacity(0.86)
    }

    private func statusBackground(for event: AppState.TGEvent) -> Color {
        if app.hasRSVPedToEvent(event.id) { return .green.opacity(0.95) }
        if isLiveNow(event) { return .orange.opacity(0.96) }
        if hasEnded(event) { return .white.opacity(0.12) }
        if isFull(event) { return .red.opacity(0.30) }
        return .white.opacity(0.12)
    }

    private func rsvpTitle(for event: AppState.TGEvent) -> String {
        if app.isOrganizer(of: event) { return "HOSTING" }
        if app.hasRSVPedToEvent(event.id) { return "RSVP'D" }
        if hasEnded(event) { return "ENDED" }
        if isFull(event) && event.waitlistEnabled { return "JOIN WAITLIST" }
        if isFull(event) { return "FULL" }
        return "RSVP"
    }

    private func rsvpIcon(for event: AppState.TGEvent) -> String {
        if app.isOrganizer(of: event) { return "crown.fill" }
        if app.hasRSVPedToEvent(event.id) { return "checkmark.seal.fill" }
        if hasEnded(event) { return "checkmark.circle.fill" }
        if isFull(event) && event.waitlistEnabled { return "person.crop.circle.badge.plus" }
        if isFull(event) { return "lock.fill" }
        return "bolt.fill"
    }

    private func rsvpBackground(for event: AppState.TGEvent) -> Color {
        if app.hasRSVPedToEvent(event.id) { return .green.opacity(0.95) }
        if app.isOrganizer(of: event) { return .white.opacity(0.92) }
        if isFull(event) && event.waitlistEnabled { return .orange.opacity(0.82) }
        if isFull(event) || hasEnded(event) { return .white.opacity(0.35) }
        return .orange.opacity(0.95)
    }

    private func timelineText(for event: AppState.TGEvent) -> String {
        if hasEnded(event) { return "COMPLETE" }
        if isLiveNow(event) { return "LIVE NOW" }
        return timeUntilText(for: event)
    }

    private func timeUntilText(for event: AppState.TGEvent) -> String {
        guard let startsAt = event.startsAt else { return "SOON" }

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

    private func isLiveNow(_ event: AppState.TGEvent) -> Bool {
        guard let startsAt = event.startsAt else { return false }
        let endsAt = event.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        return now >= startsAt && now <= endsAt
    }

    private func hasEnded(_ event: AppState.TGEvent) -> Bool {
        guard let startsAt = event.startsAt else { return false }
        let endsAt = event.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        return now > endsAt
    }

    private func isFull(_ event: AppState.TGEvent) -> Bool {
        event.capacity > 0 && event.attendeeCount >= event.capacity
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 32, weight: .black))
                .foregroundColor(.orange.opacity(0.92))
                .rotationEffect(.degrees(pulse ? 360 : 0))
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: pulse)

            Text("SYNCING EVENTS")
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .tracking(1.2)

            Text("Pulling the latest launch moments, tournaments, and community drops.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black.opacity(0.68)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.orange.opacity(0.18), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32, weight: .black))
                .foregroundColor(.orange.opacity(0.92))

            Text("NO LIVE EVENTS YET")
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .tracking(1.2)

            Text(app.eventsErrorMessage ?? "Launch events, tournaments, and special drops will appear here.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 22)

            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.refreshEvents()
            } label: {
                Text("REFRESH EVENTS")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.95)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black.opacity(0.68)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.orange.opacity(0.18), lineWidth: 1))
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

private struct AmbientEventGlow: View {
    let pulse: Bool

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.orange.opacity(pulse ? 0.12 : 0.06),
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
