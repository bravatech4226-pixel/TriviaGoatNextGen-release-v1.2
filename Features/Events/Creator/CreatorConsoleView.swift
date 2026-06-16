//  CreatorConsoleView.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Creator/admin-facing event operations dashboard.
//  Creator → Admin Review → Approval → Public Access → RSVP → Event Ops.
//
//  MILESTONE:
//  Premium Creator HQ dashboard.
//  - CRM-grade operational metrics
//  - Lifecycle queues
//  - Readiness / risk scoring
//  - RSVP + waitlist signal
//  - Admin review visibility
//  - Fast route into Event Management
//

import SwiftUI
import Combine

struct CreatorConsoleView: View {

    @EnvironmentObject private var app: AppState

    @State private var selectedScope: ConsoleScope = .overview
    @State private var now = Date()

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private enum ConsoleScope: String, CaseIterable, Identifiable {
        case overview = "OVERVIEW"
        case action = "ACTION"
        case pending = "PENDING"
        case published = "PUBLIC"
        case live = "LIVE"
        case drafts = "DRAFTS"

        var id: String { rawValue }
    }

    private enum EventHealth: Equatable {
        case ready
        case needsSchedule
        case needsRSVP
        case needsWaitlist
        case review
        case rejected
        case live
        case archived

        var label: String {
            switch self {
            case .ready: return "READY"
            case .needsSchedule: return "SCHEDULE"
            case .needsRSVP: return "RSVP"
            case .needsWaitlist: return "WAITLIST"
            case .review: return "IN REVIEW"
            case .rejected: return "REVISE"
            case .live: return "LIVE"
            case .archived: return "ARCHIVE"
            }
        }

        var icon: String {
            switch self {
            case .ready: return "checkmark.seal.fill"
            case .needsSchedule: return "calendar.badge.exclamationmark"
            case .needsRSVP: return "person.crop.circle.badge.exclamationmark"
            case .needsWaitlist: return "person.3.sequence.fill"
            case .review: return "hourglass"
            case .rejected: return "xmark.seal.fill"
            case .live: return "dot.radiowaves.left.and.right"
            case .archived: return "archivebox.fill"
            }
        }

        var tint: Color {
            switch self {
            case .ready: return .green
            case .needsSchedule: return .orange
            case .needsRSVP: return .orange
            case .needsWaitlist: return .orange
            case .review: return .orange
            case .rejected: return .red
            case .live: return .green
            case .archived: return .white.opacity(0.62)
            }
        }
    }

    private var managedEvents: [AppState.TGEvent] {
        app.events
            .filter { app.canManage($0) || app.canModerate($0) }
            .sorted { lhs, rhs in
                let lhsRank = eventSortRank(lhs)
                let rhsRank = eventSortRank(rhs)

                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }

                switch (lhs.startsAt, rhs.startsAt) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
    }

    private var publicEvents: [AppState.TGEvent] {
        managedEvents.filter { $0.published && $0.approvalStatus == "approved" }
    }

    private var pendingEvents: [AppState.TGEvent] {
        managedEvents.filter { $0.approvalStatus == "submitted" }
    }

    private var liveEvents: [AppState.TGEvent] {
        managedEvents.filter { isLive($0) }
    }

    private var draftEvents: [AppState.TGEvent] {
        managedEvents.filter {
            $0.approvalStatus == "draft" || $0.approvalStatus == "rejected"
        }
    }

    private var actionEvents: [AppState.TGEvent] {
        managedEvents.filter { event in
            let health = eventHealth(event)
            return health != .ready && health != .live && health != .archived
        }
    }

    private var upcomingEvents: [AppState.TGEvent] {
        managedEvents.filter { event in
            guard let startsAt = event.startsAt else { return false }
            return startsAt > now
        }
    }

    private var visibleEvents: [AppState.TGEvent] {
        switch selectedScope {
        case .overview: return managedEvents
        case .action: return actionEvents
        case .pending: return pendingEvents
        case .published: return publicEvents
        case .live: return liveEvents
        case .drafts: return draftEvents
        }
    }

    private var totalRSVPCount: Int {
        managedEvents.reduce(0) { $0 + max(0, $1.attendeeCount) }
    }

    private var totalWaitlistCount: Int {
        managedEvents.reduce(0) { $0 + max(0, $1.waitlistCount) }
    }

    private var totalCapacity: Int {
        managedEvents.reduce(0) { $0 + max(0, $1.capacity) }
    }

    private var reviewReadyCount: Int {
        managedEvents.filter { eventReadinessScore($0) >= 4 }.count
    }

    private var totalCapacityPercent: Int {
        guard totalCapacity > 0 else { return totalRSVPCount > 0 ? 100 : 0 }
        return min(100, Int((Double(totalRSVPCount) / Double(totalCapacity)) * 100.0))
    }

    private var consoleSubtitle: String {
        managedEvents.isEmpty
        ? "Event operations"
        : "\(managedEvents.count) managed • \(totalRSVPCount) RSVP • \(totalWaitlistCount) waitlist"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()

                creatorConsoleContent(safeTop: geo.safeAreaInsets.top)

                toastOverlay
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .onAppear {
                now = Date()
                app.refreshEvents()
            }
            .onReceive(timer) { value in
                now = value
            }
        }
    }

    private func creatorConsoleContent(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            header(safeTop: safeTop)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    commandPanel
                    createEventButton
                    executiveSummaryPanel
                    metricsGrid
                    readinessPanel
                    scopePicker
                    eventQueuePanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 38)
            }
        }
    }

    private func header(safeTop: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.setRoute(.settings)
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
                Text("CREATOR HQ")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.8)

                Text(consoleSubtitle)
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
                app.showEventToast("SYNCING EVENTS")
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 42, height: 42)

                    if app.isRefreshingEvents {
                        ProgressView()
                            .tint(.orange)
                            .scaleEffect(0.72)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(.orange.opacity(0.95))
                    }
                }
                .overlay(Circle().stroke(Color.orange.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, max(safeTop, 44) + 10)
        .padding(.bottom, 13)
        .background(Color.black.opacity(0.74).ignoresSafeArea(edges: .top))
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EVENT COMMAND CENTER")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.92))
                        .tracking(2)

                    Text("Creator workflow, admin review, attendee demand, and live event operations in one control surface.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    Text(app.isRefreshingEvents ? "SYNCING" : "LIVE")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(.black.opacity(0.86))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(app.isRefreshingEvents ? Color.orange.opacity(0.94) : Color.green.opacity(0.92)))

                    Text("CLONE DB")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.34))
                        .tracking(1)
                }
            }

            HStack(spacing: 8) {
                microPill("CREATE", "plus.circle.fill")
                microPill("REVIEW", "checkmark.seal.fill")
                microPill("CRM", "person.crop.rectangle.stack.fill")
                microPill("AGENDA", "rectangle.3.group.fill")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.black.opacity(0.80))

                LinearGradient(
                    colors: [
                        Color.orange.opacity(0.13),
                        Color.blue.opacity(0.055),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.orange.opacity(0.20), lineWidth: 1.1))
        .shadow(color: Color.orange.opacity(0.10), radius: 24, x: 0, y: 12)
    }

    private var createEventButton: some View {
        Button {
            HapticManager.instance.impact(.medium)
            SpatialAudioManager.shared.play(.uiTap)
            app.selectedEvent = nil
            app.setRoute(.eventEditor)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 21, weight: .black))

                VStack(alignment: .leading, spacing: 3) {
                    Text("CREATE EVENT")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(1.1)

                    Text("Draft, submit, approve, publish, then manage CRM + sessions")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.black.opacity(0.54))
                        .tracking(0.45)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 21, weight: .black))
            }
            .foregroundColor(.black.opacity(0.90))
            .padding(.horizontal, 16)
            .frame(height: 62)
            .background(RoundedRectangle(cornerRadius: 21, style: .continuous).fill(Color.orange.opacity(0.96)))
            .shadow(color: .orange.opacity(0.22), radius: 15, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var executiveSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle("EXECUTIVE SNAPSHOT")

                Spacer()

                Text("\(totalCapacityPercent)% CAPACITY")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(totalCapacityPercent >= 90 ? .black.opacity(0.88) : .white.opacity(0.55))
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(
                        Capsule()
                            .fill(totalCapacityPercent >= 90 ? Color.orange.opacity(0.96) : Color.white.opacity(0.08))
                    )
            }

            HStack(spacing: 10) {
                heroMetric(title: "UPCOMING", value: "\(upcomingEvents.count)", icon: "calendar.badge.clock", tint: .orange)
                heroMetric(title: "PUBLIC", value: "\(publicEvents.count)", icon: "globe.americas.fill", tint: .green)
                heroMetric(title: "ACTION", value: "\(actionEvents.count)", icon: "exclamationmark.triangle.fill", tint: actionEvents.isEmpty ? .green : .orange)
            }

            capacityProgressBar
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.050)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func heroMetric(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(tint.opacity(0.94))

            Text(value)
                .font(.system(size: 19, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.94))
                .lineLimit(1)

            Text(title)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.42))
                .tracking(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background(RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Color.black.opacity(0.30)))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(tint.opacity(0.13), lineWidth: 1))
    }

    private var capacityProgressBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("TOTAL DEMAND")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.42))
                    .tracking(1)

                Spacer()

                Text(totalCapacity > 0 ? "\(totalRSVPCount)/\(totalCapacity) RSVP" : "\(totalRSVPCount) RSVP")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.58))
                    .tracking(0.7)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))

                    Capsule()
                        .fill(totalCapacityPercent >= 90 ? Color.orange.opacity(0.92) : Color.green.opacity(0.82))
                        .frame(width: max(8, proxy.size.width * CGFloat(totalCapacityPercent) / 100.0))
                }
            }
            .frame(height: 10)
            .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("READINESS PIPELINE")

                Spacer()

                Text("\(reviewReadyCount) READY")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(reviewReadyCount > 0 ? .black.opacity(0.86) : .white.opacity(0.56))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        Capsule()
                            .fill(reviewReadyCount > 0 ? Color.green.opacity(0.92) : Color.white.opacity(0.08))
                    )
            }

            HStack(spacing: 10) {
                readinessStep("DRAFT", draftEvents.count > 0)
                readinessStep("REVIEW", pendingEvents.count > 0)
                readinessStep("PUBLIC", publicEvents.count > 0)
                readinessStep("LIVE", liveEvents.count > 0)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func readinessStep(_ title: String, _ isComplete: Bool) -> some View {
        VStack(spacing: 7) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(isComplete ? .green.opacity(0.95) : .white.opacity(0.28))

            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(isComplete ? .white.opacity(0.82) : .white.opacity(0.38))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isComplete ? Color.green.opacity(0.09) : Color.black.opacity(0.24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isComplete ? Color.green.opacity(0.28) : Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var metricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                metricCard(title: "PENDING", value: pendingEvents.count, icon: "hourglass", color: .orange)
                metricCard(title: "PUBLIC", value: publicEvents.count, icon: "globe.americas.fill", color: .green)
            }

            HStack(spacing: 10) {
                metricCard(title: "RSVP", value: totalRSVPCount, icon: "person.2.fill", color: .white)
                metricCard(title: "WAITLIST", value: totalWaitlistCount, icon: "person.crop.circle.badge.clock", color: .orange)
            }
        }
    }

    private func metricCard(title: String, value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundColor(color.opacity(0.94))
                .frame(width: 32, height: 32)
                .background(Circle().fill(color.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.44))
                    .tracking(1)

                Text("\(value)")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.92))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.16), lineWidth: 1))
    }

    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ConsoleScope.allCases) { scope in
                    Button {
                        HapticManager.instance.impact(.light)
                        SpatialAudioManager.shared.play(.uiTap)

                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedScope = scope
                        }
                    } label: {
                        Text(scope.rawValue)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(selectedScope == scope ? .black.opacity(0.9) : .white.opacity(0.70))
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(
                                Capsule()
                                    .fill(selectedScope == scope ? Color.orange.opacity(0.96) : Color.white.opacity(0.09))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(selectedScope == scope ? 0 : 0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var eventQueuePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(selectedScope.rawValue)

                Spacer()

                Text("\(visibleEvents.count) EVENTS")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.46))
                    .tracking(1)
            }

            if visibleEvents.isEmpty {
                emptyQueue
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleEvents) { event in
                        eventOpsRow(event)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var emptyQueue: some View {
        VStack(spacing: 10) {
            Image(systemName: selectedScope == .action ? "checkmark.seal.fill" : "tray.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundColor(selectedScope == .action ? .green.opacity(0.78) : .orange.opacity(0.74))

            Text(selectedScope == .action ? "NO ACTION ITEMS" : "NO EVENTS IN THIS QUEUE")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.72))
                .tracking(1)

            Text(selectedScope == .action ? "Everything currently visible is in a healthy state." : "Create a draft or adjust the selected filter.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func eventOpsRow(_ event: AppState.TGEvent) -> some View {
        let score = eventReadinessScore(event)
        let health = eventHealth(event)
        let capacityPercent = eventCapacityPercent(event)

        return Button {
            HapticManager.instance.impact(.light)
            SpatialAudioManager.shared.play(.uiTap)
            app.selectedEvent = event
            app.setRoute(.manageEvent)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(health.tint.opacity(0.14))
                            .frame(width: 44, height: 44)

                        Image(systemName: health.icon)
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(health.tint)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.94))
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        HStack(spacing: 8) {
                            Text(statusLabel(for: event))
                            Text("•")
                            Text(eventDateLine(event))
                        }
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.48))
                        .tracking(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(health.label)
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(health == .ready || health == .live ? .black.opacity(0.86) : health.tint.opacity(0.95))
                            .tracking(0.8)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(
                                Capsule()
                                    .fill((health == .ready || health == .live) ? health.tint.opacity(0.92) : health.tint.opacity(0.11))
                            )

                        Text("\(score)/4 READY")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(score >= 4 ? .green.opacity(0.88) : .white.opacity(0.42))
                    }
                }

                HStack(spacing: 10) {
                    queueMetric("RSVP", event.attendeeCount)
                    queueMetric("WAIT", event.waitlistCount)
                    queueMetric("CAP", event.capacity <= 0 ? "OPEN" : "\(capacityPercent)%")
                }

                readinessStrip(for: event)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill((health == .ready || health == .live) ? Color.green.opacity(0.065) : Color.black.opacity(0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke((health == .ready || health == .live) ? Color.green.opacity(0.22) : health.tint.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func queueMetric(_ title: String, _ value: Int) -> some View {
        queueMetric(title, "\(value)")
    }

    private func queueMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.38))
                .tracking(0.8)

            Text(value)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.90))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func readinessStrip(for event: AppState.TGEvent) -> some View {
        HStack(spacing: 6) {
            miniCheck("INFO", hasCoreInfo(event))
            miniCheck("TIME", hasSchedule(event))
            miniCheck("RSVP", hasRSVPWindow(event))
            miniCheck("WAIT", hasWaitlistWindow(event) || !event.waitlistEnabled)
        }
    }

    private func miniCheck(_ title: String, _ complete: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9, weight: .black))

            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.5)
        }
        .foregroundColor(complete ? .green.opacity(0.92) : .white.opacity(0.32))
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Capsule().fill(complete ? Color.green.opacity(0.10) : Color.white.opacity(0.045)))
        .overlay(Capsule().stroke(complete ? Color.green.opacity(0.18) : Color.white.opacity(0.06), lineWidth: 1))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundColor(.orange.opacity(0.92))
            .tracking(2)
    }

    private func microPill(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .black))

            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.8)
        }
        .foregroundColor(.white.opacity(0.66))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.055)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func eventSortRank(_ event: AppState.TGEvent) -> Int {
        if isLive(event) { return 0 }
        if event.approvalStatus == "submitted" { return 1 }
        if eventHealth(event) != .ready { return 2 }
        if event.published && event.approvalStatus == "approved" { return 3 }
        if event.approvalStatus == "draft" || event.approvalStatus == "rejected" { return 4 }
        return 5
    }

    private func eventReadinessScore(_ event: AppState.TGEvent) -> Int {
        [
            hasCoreInfo(event),
            hasSchedule(event),
            hasRSVPWindow(event),
            hasWaitlistWindow(event) || !event.waitlistEnabled
        ].filter { $0 }.count
    }

    private func eventHealth(_ event: AppState.TGEvent) -> EventHealth {
        if hasEnded(event) { return .archived }
        if isLive(event) { return .live }

        if event.approvalStatus == "rejected" { return .rejected }
        if event.approvalStatus == "submitted" { return .review }

        if !hasSchedule(event) { return .needsSchedule }
        if !hasRSVPWindow(event) { return .needsRSVP }
        if event.waitlistEnabled && !hasWaitlistWindow(event) { return .needsWaitlist }

        return .ready
    }

    private func hasCoreInfo(_ event: AppState.TGEvent) -> Bool {
        !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !event.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hasSchedule(_ event: AppState.TGEvent) -> Bool {
        event.startsAt != nil && event.endsAt != nil
    }

    private func hasRSVPWindow(_ event: AppState.TGEvent) -> Bool {
        event.rsvpOpensAt != nil && event.rsvpClosesAt != nil
    }

    private func hasWaitlistWindow(_ event: AppState.TGEvent) -> Bool {
        event.waitlistOpensAt != nil && event.waitlistClosesAt != nil
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

        return event.published
        && event.approvalStatus == "approved"
        && now >= startsAt
        && now <= endsAt
    }

    private func hasEnded(_ event: AppState.TGEvent) -> Bool {
        let status = event.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if status == "ended" || status == "cancelled" || status == "canceled" {
            return true
        }

        guard let startsAt = event.startsAt else {
            return false
        }

        let endsAt = event.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        return now > endsAt
    }

    private func eventCapacityPercent(_ event: AppState.TGEvent) -> Int {
        guard event.capacity > 0 else { return event.attendeeCount > 0 ? 100 : 0 }
        return min(100, Int((Double(max(0, event.attendeeCount)) / Double(event.capacity)) * 100.0))
    }

    private func eventDateLine(_ event: AppState.TGEvent) -> String {
        guard let startsAt = event.startsAt else { return "DATE TBA" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d • h:mm a"

        return formatter.string(from: startsAt).uppercased()
    }

    private func statusLabel(for event: AppState.TGEvent) -> String {
        let status = event.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if status == "LIVE" {
            return "LIVE"
        }

        if event.published && event.approvalStatus == "approved" {
            return "PUBLISHED"
        }

        return event.approvalStatus.uppercased()
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

