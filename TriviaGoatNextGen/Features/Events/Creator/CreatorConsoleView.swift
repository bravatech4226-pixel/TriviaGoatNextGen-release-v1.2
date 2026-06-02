//  CreatorConsoleView.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Creator/admin-facing event operations dashboard.
//  Creator → Admin Review → Approval → Public Access → RSVP → Event Ops.
//

import SwiftUI

struct CreatorConsoleView: View {

    @EnvironmentObject private var app: AppState

    @State private var selectedScope: ConsoleScope = .overview

    private enum ConsoleScope: String, CaseIterable, Identifiable {
        case overview = "OVERVIEW"
        case pending = "PENDING"
        case live = "LIVE"
        case drafts = "DRAFTS"

        var id: String { rawValue }
    }

    private var managedEvents: [AppState.TGEvent] {
        app.events
            .filter { app.canManage($0) || app.canModerate($0) }
            .sorted { lhs, rhs in
                switch (lhs.startsAt, rhs.startsAt) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.title < rhs.title
                }
            }
    }

    private var pendingEvents: [AppState.TGEvent] {
        managedEvents.filter { $0.approvalStatus == "submitted" }
    }

    private var liveEvents: [AppState.TGEvent] {
        managedEvents.filter { $0.published && $0.approvalStatus == "approved" }
    }

    private var draftEvents: [AppState.TGEvent] {
        managedEvents.filter {
            $0.approvalStatus == "draft" || $0.approvalStatus == "rejected"
        }
    }

    private var visibleEvents: [AppState.TGEvent] {
        switch selectedScope {
        case .overview: return managedEvents
        case .pending: return pendingEvents
        case .live: return liveEvents
        case .drafts: return draftEvents
        }
    }

    private var consoleSubtitle: String {
        managedEvents.isEmpty
        ? "Event operations"
        : "\(managedEvents.count) managed event\(managedEvents.count == 1 ? "" : "s")"
    }

    private var reviewReadyCount: Int {
        managedEvents.filter { eventReadinessScore($0) == 4 }.count
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()

                VStack(spacing: 0) {
                    header(safeTop: geo.safeAreaInsets.top)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            commandPanel
                            createEventButton
                            readinessPanel
                            metricsGrid
                            scopePicker
                            eventQueuePanel
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 36)
                    }
                }

                toastOverlay
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
            .onAppear {
                app.refreshEvents()
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
                Text("CREATOR CONSOLE")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.6)

                Text(consoleSubtitle)
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
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.orange.opacity(0.95))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                    .overlay(Circle().stroke(Color.orange.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, safeTop + 8)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.72).ignoresSafeArea(edges: .top))
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("EVENT OPS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                Spacer()

                Text("CREATOR / ADMIN")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.black.opacity(0.86))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.orange.opacity(0.94)))
            }

            Text("Create drafts, monitor approval status, manage published events, and prepare attendee operations.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                microPill("CREATE", "plus.circle.fill")
                microPill("REVIEW", "checkmark.seal.fill")
                microPill("RSVP OPS", "person.3.fill")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.orange.opacity(0.20), lineWidth: 1))
    }

    private var createEventButton: some View {
        Button {
            HapticManager.instance.impact(.medium)
            SpatialAudioManager.shared.play(.uiTap)
            app.selectedEvent = nil
            app.setRoute(.eventEditor)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .black))

                VStack(alignment: .leading, spacing: 2) {
                    Text("CREATE EVENT")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(1.1)

                    Text("Build a complete draft for review")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.black.opacity(0.52))
                        .tracking(0.6)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 21, weight: .black))
            }
            .foregroundColor(.black.opacity(0.90))
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.orange.opacity(0.96)))
            .shadow(color: .orange.opacity(0.20), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var readinessPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("READINESS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

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
                readinessStep("PUBLIC", liveEvents.count > 0)
                readinessStep("OPS", managedEvents.contains { $0.attendeeCount > 0 || $0.waitlistCount > 0 })
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

    private var metricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                metricCard(title: "PENDING", value: pendingEvents.count, icon: "hourglass", color: .orange)
                metricCard(title: "LIVE", value: liveEvents.count, icon: "dot.radiowaves.left.and.right", color: .green)
            }

            HStack(spacing: 10) {
                metricCard(title: "DRAFTS", value: draftEvents.count, icon: "doc.text.fill", color: .white)
                metricCard(title: "TOTAL", value: managedEvents.count, icon: "square.stack.3d.up.fill", color: .orange)
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
        .frame(height: 54)
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
                Text(selectedScope.rawValue)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

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
            Image(systemName: "tray.fill")
                .font(.system(size: 24, weight: .black))
                .foregroundColor(.orange.opacity(0.74))

            Text("NO EVENTS IN THIS QUEUE")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.72))
                .tracking(1)

            Text("Create a draft or adjust the selected filter.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private func eventOpsRow(_ event: AppState.TGEvent) -> some View {
        let score = eventReadinessScore(event)
        let ready = score == 4

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
                            .fill(statusColor(for: event).opacity(0.14))
                            .frame(width: 42, height: 42)

                        Image(systemName: statusIcon(for: event))
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(statusColor(for: event))
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
                            Text(capacityLabel(for: event))
                        }
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.48))
                        .tracking(0.8)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(ready ? .green.opacity(0.95) : .orange.opacity(0.90))

                        Text("\(score)/4")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(ready ? .green.opacity(0.88) : .white.opacity(0.42))
                    }
                }

                readinessStrip(for: event)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ready ? Color.green.opacity(0.07) : Color.black.opacity(0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ready ? Color.green.opacity(0.24) : statusColor(for: event).opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func readinessStrip(for event: AppState.TGEvent) -> some View {
        HStack(spacing: 6) {
            miniCheck("INFO", hasCoreInfo(event))
            miniCheck("TIME", hasSchedule(event))
            miniCheck("RSVP", hasRSVPWindow(event))
            miniCheck("WAIT", hasWaitlistWindow(event))
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

    private func eventReadinessScore(_ event: AppState.TGEvent) -> Int {
        [
            hasCoreInfo(event),
            hasSchedule(event),
            hasRSVPWindow(event),
            hasWaitlistWindow(event)
        ].filter { $0 }.count
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

    private func capacityLabel(for event: AppState.TGEvent) -> String {
        if event.capacity <= 0 {
            return "\(event.attendeeCount) RSVP"
        }

        return "\(event.attendeeCount)/\(event.capacity) RSVP"
    }

    private func statusLabel(for event: AppState.TGEvent) -> String {
        if event.published && event.approvalStatus == "approved" {
            return "PUBLISHED"
        }

        return event.approvalStatus.uppercased()
    }

    private func statusIcon(for event: AppState.TGEvent) -> String {
        if event.published && event.approvalStatus == "approved" {
            return "dot.radiowaves.left.and.right"
        }

        switch event.approvalStatus {
        case "submitted": return "hourglass"
        case "rejected": return "xmark.seal.fill"
        case "draft": return "doc.text.fill"
        case "approved": return "checkmark.seal.fill"
        default: return "circle.grid.cross.fill"
        }
    }

    private func statusColor(for event: AppState.TGEvent) -> Color {
        if event.published && event.approvalStatus == "approved" {
            return .green
        }

        switch event.approvalStatus {
        case "submitted": return .orange
        case "rejected": return .red
        case "draft": return .white
        case "approved": return .green
        default: return .orange
        }
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
