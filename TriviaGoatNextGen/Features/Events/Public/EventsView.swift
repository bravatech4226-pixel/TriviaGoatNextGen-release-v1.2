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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()

                VStack(spacing: 0) {
                    topBar(safeTop: geo.safeAreaInsets.top)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            commandSummary

                            if let featured = app.featuredEvent {
                                featuredCard(featured)
                            }

                            if app.events.isEmpty {
                                emptyState
                            } else {
                                eventListSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 36)
                    }
                    .refreshable {
                        app.refreshEvents()
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .onAppear {
                app.markEventsRead()

                if let featured = app.featuredEvent {
                    app.listenToRSVPState(for: featured.id)
                }

                for event in app.events {
                    app.listenToRSVPState(for: event.id)
                }
            }
            .onChange(of: app.events) { _, events in
                for event in events {
                    app.listenToRSVPState(for: event.id)
                }
            }
        }
    }

    private var nonFeaturedEvents: [AppState.TGEvent] {
        guard let featuredID = app.featuredEvent?.id else {
            return app.events
        }

        return app.events.filter { $0.id != featuredID }
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

                Text("Launches, tournaments, and live drops")
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
            summaryChip(title: "LIVE", value: "\(publishedEventCount)", icon: "calendar", color: .orange)
            summaryChip(title: "EVENTS", value: "\(publishedEventCount)", icon: "square.stack.3d.up.fill", color: .orange)
            summaryChip(title: "NEXT", value: app.featuredEvent == nil ? "SOON" : "ACTIVE", icon: "timer", color: .orange)
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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private func featuredCard(_ event: AppState.TGEvent) -> some View {
        Button {
            openDetail(event)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                Text("FEATURED EVENT")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(2.4)

                Text(event.title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(4)
                    .minimumScaleFactor(0.84)

                if !event.heroLine.isEmpty {
                    Text(event.heroLine)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                eventMetaGrid(event)

                rsvpButton(event)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.black.opacity(0.84)))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.orange.opacity(0.22), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .onAppear {
            app.listenToRSVPState(for: event.id)
        }
    }

    private var eventListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !nonFeaturedEvents.isEmpty {
                Text("UPCOMING")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.50))
                    .tracking(2)

                ForEach(nonFeaturedEvents) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: AppState.TGEvent) -> some View {
        Button {
            openDetail(event)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(event.category.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.82))
                    .tracking(1.4)

                Text(event.title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
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
        }
        .buttonStyle(.plain)
        .onAppear {
            app.listenToRSVPState(for: event.id)
        }
    }

    @ViewBuilder
    private func eventMetaGrid(_ event: AppState.TGEvent) -> some View {
        HStack(spacing: 8) {
            metaChip(icon: "calendar", text: dateText(event.startsAt))

            if shouldShowAttendeeCount(for: event) {
                metaChip(icon: "person.2.fill", text: attendeeDisplayText(for: event))
            }
        }
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .black))

            Text(text)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundColor(.white.opacity(0.72))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    private func rsvpButton(_ event: AppState.TGEvent) -> some View {
        Button {
            HapticManager.instance.impact(.medium)
            SpatialAudioManager.shared.play(.uiTap)

            if app.hasRSVPedToEvent(event.id) {
                app.showEventToast("ALREADY REGISTERED")
                return
            }

            app.RSVPToEvent(event)
        } label: {
            Text(app.hasRSVPedToEvent(event.id) ? "RSVP'D" : "RSVP")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.black)
                .tracking(1.1)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.95)))
        }
        .buttonStyle(.plain)
    }

    private func openDetail(_ event: AppState.TGEvent) {
        HapticManager.instance.impact(.light)
        SpatialAudioManager.shared.play(.uiTap)
        app.listenToRSVPState(for: event.id)
        app.selectedEvent = event
        app.setRoute(.eventDetail)
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

        return formatter.string(from: date).uppercased()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: app.isRefreshingEvents ? "arrow.triangle.2.circlepath" : "calendar.badge.clock")
                .font(.system(size: 32, weight: .black))
                .foregroundColor(.orange.opacity(0.92))

            Text(app.isRefreshingEvents ? "SYNCING EVENTS" : "NO LIVE EVENTS YET")
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .tracking(1.2)

            Text(app.eventsErrorMessage ?? "Launch events, tournaments, and special drops will appear here.")
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
}
