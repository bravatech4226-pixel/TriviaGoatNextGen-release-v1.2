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

    private var featuredEvent: AppState.TGEvent? {

        app.featuredEvent

    }

    private var events: [AppState.TGEvent] {

        app.events

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

                            if let featuredEvent {

                                featuredHero(featuredEvent)

                            }

                            if events.isEmpty {

                                emptyState

                            } else {

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

            withAnimation(

                .easeInOut(duration: 1.8)

                .repeatForever(autoreverses: true)

            ) {

                pulse = true

            }

        }

        .onReceive(timer) { value in

            now = value

        }

    }

    // MARK: - Header

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

                    .background(

                        Circle()

                            .fill(Color.white.opacity(0.08))

                    )

                    .overlay(

                        Circle()

                            .stroke(

                                Color.white.opacity(0.12),

                                lineWidth: 1

                            )

                    )

            }

            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {

                Text("EVENTS")

                    .font(

                        .system(

                            size: 12,

                            weight: .black,

                            design: .monospaced

                        )

                    )

                    .foregroundColor(.orange.opacity(0.95))

                    .tracking(1.6)

                Text(eventsSubtitle)

                    .font(

                        .system(

                            size: 10,

                            weight: .bold,

                            design: .monospaced

                        )

                    )

                    .foregroundColor(.white.opacity(0.48))

            }

            Spacer()

            if app.isRefreshingEvents {

                ProgressView()

                    .progressViewStyle(.circular)

                    .tint(.orange)

            } else {

                Button {

                    HapticManager.instance.impact(.light)

                    SpatialAudioManager.shared.play(.uiTap)

                    app.refreshEvents()

                } label: {

                    Image(systemName: "arrow.clockwise")

                        .font(.system(size: 14, weight: .black))

                        .foregroundColor(.orange.opacity(0.95))

                        .frame(width: 42, height: 42)

                        .background(

                            Circle()

                                .fill(Color.white.opacity(0.08))

                        )

                        .overlay(

                            Circle()

                                .stroke(

                                    Color.white.opacity(0.12),

                                    lineWidth: 1

                                )

                        )

                }

                .buttonStyle(.plain)

            }

        }

        .padding(.horizontal, 16)

        .padding(.top, safeTop + 8)

        .padding(.bottom, 12)

        .background(

            Color.black

                .opacity(0.72)

                .ignoresSafeArea(edges: .top)

        )

    }

    // MARK: - Featured Hero

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

                                .scaleEffect(pulse ? 1.18 : 1.0)

                            Text(heroEyebrow(for: event))

                                .font(

                                    .system(

                                        size: 10,

                                        weight: .black,

                                        design: .monospaced

                                    )

                                )

                                .foregroundColor(.orange.opacity(0.95))

                                .tracking(2.4)

                        }

                        Text(event.category.uppercased())

                            .font(

                                .system(

                                    size: 9,

                                    weight: .black,

                                    design: .monospaced

                                )

                            )

                            .foregroundColor(.white.opacity(0.38))

                            .tracking(1.8)

                    }

                    Spacer()

                    ZStack {

                        Circle()

                            .fill(

                                heroStatusColor(for: event)

                                    .opacity(pulse ? 0.18 : 0.08)

                            )

                            .frame(width: 62, height: 62)

                            .blur(radius: pulse ? 4 : 0)

                        Circle()

                            .stroke(

                                heroStatusColor(for: event)

                                    .opacity(0.18),

                                lineWidth: 1

                            )

                            .frame(width: 54, height: 54)

                        Image(systemName: heroIcon(for: event))

                            .font(.system(size: 24, weight: .black))

                            .foregroundColor(

                                heroStatusColor(for: event)

                                    .opacity(0.96)

                            )

                    }

                }

                VStack(alignment: .leading, spacing: 10) {

                    Text(event.title)

                        .font(

                            .system(

                                size: event.title.count > 48 ? 30 : 34,

                                weight: .black,

                                design: .rounded

                            )

                        )

                        .foregroundColor(.white)

                        .lineSpacing(-2)

                        .fixedSize(horizontal: false, vertical: true)

                    if !event.heroLine.isEmpty {

                        Text(event.heroLine)

                            .font(

                                .system(

                                    size: 15,

                                    weight: .bold,

                                    design: .rounded

                                )

                            )

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

                    HStack(spacing: 8) {

                        Image(systemName: "timer")

                            .font(.system(size: 11, weight: .black))

                        Text(timeString(for: event))

                            .font(

                                .system(

                                    size: 10,

                                    weight: .black,

                                    design: .monospaced

                                )

                            )

                    }

                    .foregroundColor(.black)

                    .padding(.vertical, 8)

                    .padding(.horizontal, 10)

                    .background(

                        Capsule()

                            .fill(

                                heroStatusColor(for: event)

                                    .opacity(0.96)

                            )

                    )

                    Spacer()

                    Image(systemName: "arrow.up.right")

                        .font(.system(size: 13, weight: .black))

                        .foregroundColor(.white.opacity(0.46))

                }

            }

            .padding(22)

            .background(

                RoundedRectangle(

                    cornerRadius: 32,

                    style: .continuous

                )

                .fill(Color.black.opacity(0.84))

            )

            .overlay(

                RoundedRectangle(

                    cornerRadius: 32,

                    style: .continuous

                )

                .stroke(

                    heroStatusColor(for: event)

                        .opacity(pulse ? 0.34 : 0.20),

                    lineWidth: 1.2

                )

            )

            .shadow(

                color: heroStatusColor(for: event)

                    .opacity(0.16),

                radius: 28,

                x: 0,

                y: 16

            )

        }

        .buttonStyle(.plain)

    }

    // MARK: - Event Rail

    private var eventRail: some View {

        VStack(alignment: .leading, spacing: 14) {

            HStack {

                Text("UPCOMING EVENTS")

                    .font(

                        .system(

                            size: 10,

                            weight: .black,

                            design: .monospaced

                        )

                    )

                    .foregroundColor(.orange.opacity(0.92))

                    .tracking(2)

                Spacer()

                Text("\(events.count)")

                    .font(

                        .system(

                            size: 10,

                            weight: .black,

                            design: .monospaced

                        )

                    )

                    .foregroundColor(.white.opacity(0.42))

            }

            VStack(spacing: 12) {

                ForEach(events) { event in

                    eventCard(event)

                }

            }

        }

    }

    // MARK: - Event Card

    private func eventCard(_ event: AppState.TGEvent) -> some View {

        Button {

            open(event)

        } label: {

            HStack(spacing: 14) {

                ZStack {

                    RoundedRectangle(

                        cornerRadius: 18,

                        style: .continuous

                    )

                    .fill(

                        heroStatusColor(for: event)

                            .opacity(0.14)

                    )

                    .frame(width: 58, height: 58)

                    Image(systemName: heroIcon(for: event))

                        .font(.system(size: 22, weight: .black))

                        .foregroundColor(heroStatusColor(for: event))

                }

                VStack(alignment: .leading, spacing: 6) {

                    Text(event.title)

                        .font(

                            .system(

                                size: 15,

                                weight: .black,

                                design: .rounded

                            )

                        )

                        .foregroundColor(.white)

                        .lineLimit(2)

                    Text(timeString(for: event))

                        .font(

                            .system(

                                size: 10,

                                weight: .black,

                                design: .monospaced

                            )

                        )

                        .foregroundColor(.white.opacity(0.48))

                    Text(event.category.uppercased())

                        .font(

                            .system(

                                size: 9,

                                weight: .black,

                                design: .monospaced

                            )

                        )

                        .foregroundColor(.orange.opacity(0.82))

                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {

                    Text(attendeeText(for: event))

                        .font(

                            .system(

                                size: 10,

                                weight: .black,

                                design: .monospaced

                            )

                        )

                        .foregroundColor(.white.opacity(0.62))

                    Image(systemName: "chevron.right")

                        .font(.system(size: 12, weight: .black))

                        .foregroundColor(.white.opacity(0.30))

                }

            }

            .padding(16)

            .background(

                RoundedRectangle(

                    cornerRadius: 24,

                    style: .continuous

                )

                .fill(Color.white.opacity(0.055))

            )

            .overlay(

                RoundedRectangle(

                    cornerRadius: 24,

                    style: .continuous

                )

                .stroke(

                    Color.white.opacity(0.08),

                    lineWidth: 1

                )

            )

        }

        .buttonStyle(.plain)

    }

    // MARK: - Empty State

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

                Text("NO EVENTS LIVE")

                    .font(

                        .system(

                            size: 22,

                            weight: .black,

                            design: .monospaced

                        )

                    )

                    .foregroundColor(.white)

                Text("New platform events, battles, and community experiences will appear here.")

                    .font(

                        .system(

                            size: 14,

                            weight: .semibold,

                            design: .rounded

                        )

                    )

                    .foregroundColor(.white.opacity(0.58))

                    .multilineTextAlignment(.center)

            }

        }

        .frame(maxWidth: .infinity)

        .padding(.vertical, 48)

        .padding(.horizontal, 22)

        .background(

            RoundedRectangle(

                cornerRadius: 28,

                style: .continuous

            )

            .fill(Color.black.opacity(0.78))

        )

        .overlay(

            RoundedRectangle(

                cornerRadius: 28,

                style: .continuous

            )

            .stroke(

                Color.white.opacity(0.08),

                lineWidth: 1

            )

        )

    }

    // MARK: - Ambient

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

    // MARK: - Helpers

    private func open(_ event: AppState.TGEvent) {

        HapticManager.instance.impact(.light)

        SpatialAudioManager.shared.play(.uiTap)

        app.selectedEvent = event

        app.setRoute(.eventDetail)

    }

    private var eventsSubtitle: String {

        if app.isRefreshingEvents {

            return "SYNCING EVENTS"

        }

        if events.isEmpty {

            return "NO EVENTS AVAILABLE"

        }

        return "\(events.count) ACTIVE EVENTS"

    }

    private func attendeeText(for event: AppState.TGEvent) -> String {

        if event.capacity <= 0 {

            return "\(event.attendeeCount) RSVP"

        }

        return "\(event.attendeeCount)/\(event.capacity)"

    }

    private func heroEyebrow(for event: AppState.TGEvent) -> String {

        if isLive(event) {

            return "LIVE EVENT"

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

            return .white.opacity(0.6)

        }

        if isFull(event) {

            return .red

        }

        return .orange

    }

    private func heroStatusPill(for event: AppState.TGEvent) -> some View {

        Text(statusText(for: event))

            .font(

                .system(

                    size: 9,

                    weight: .black,

                    design: .monospaced

                )

            )

            .foregroundColor(

                isLive(event)

                ? .black

                : .white.opacity(0.88)

            )

            .padding(.vertical, 6)

            .padding(.horizontal, 10)

            .background(

                Capsule()

                    .fill(

                        isLive(event)

                        ? Color.orange.opacity(0.96)

                        : Color.white.opacity(0.12)

                    )

            )

    }

    private func statusText(for event: AppState.TGEvent) -> String {

        if isLive(event) {

            return "LIVE"

        }

        if isEnded(event) {

            return "ENDED"

        }

        if isFull(event) {

            return event.waitlistEnabled

            ? "WAITLIST"

            : "FULL"

        }

        return "OPEN"

    }

    private func isLive(_ event: AppState.TGEvent) -> Bool {

        guard let startsAt = event.startsAt else {

            return false

        }

        let endsAt = event.endsAt

        ?? startsAt.addingTimeInterval(2 * 60 * 60)

        return now >= startsAt && now <= endsAt

    }

    private func isEnded(_ event: AppState.TGEvent) -> Bool {

        guard let startsAt = event.startsAt else {

            return false

        }

        let endsAt = event.endsAt

        ?? startsAt.addingTimeInterval(2 * 60 * 60)

        return now > endsAt

    }

    private func isFull(_ event: AppState.TGEvent) -> Bool {

        event.capacity > 0 &&

        event.attendeeCount >= event.capacity

    }

    private func timeString(for event: AppState.TGEvent) -> String {

        if isEnded(event) {

            return "COMPLETE"

        }

        if isLive(event) {

            return "LIVE NOW"

        }

        guard let startsAt = event.startsAt else {

            return "DATE COMING"

        }

        let seconds = Int(startsAt.timeIntervalSince(now))

        if seconds <= 0 {

            return "NOW"

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
