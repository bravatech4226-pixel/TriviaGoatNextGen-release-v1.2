//
//  CreatorConsoleView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-16.
//
//  PURPOSE:
//  Creator/admin-facing event operations dashboard.
//  WDC-style event command center foundation.
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
                case let (l?, r?):
                    return l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.title < rhs.title
                }
            }
    }

    private var pendingEvents: [AppState.TGEvent] {
        managedEvents.filter { $0.approvalStatus == "submitted" }
    }

    private var liveEvents: [AppState.TGEvent] {
        managedEvents.filter {
            $0.published && $0.approvalStatus == "approved"
        }
    }

    private var draftEvents: [AppState.TGEvent] {
        managedEvents.filter {
            $0.approvalStatus == "draft" || $0.approvalStatus == "rejected"
        }
    }

    private var visibleEvents: [AppState.TGEvent] {
        switch selectedScope {
        case .overview:
            return managedEvents
        case .pending:
            return pendingEvents
        case .live:
            return liveEvents
        case .drafts:
            return draftEvents
        }
    }

    private var consoleSubtitle: String {
        managedEvents.isEmpty
            ? "Event operations"
            : "\(managedEvents.count) managed event\(managedEvents.count == 1 ? "" : "s")"
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
        HStack {
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

                Text("CREATOR")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.black.opacity(0.86))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.orange.opacity(0.94)))
            }

            Text("Create drafts, track submissions, manage approved events, and prepare attendee operations.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                microPill("SESSIONS", "rectangle.3.group.fill")
                microPill("DELEGATES", "person.3.fill")
                microPill("GUEST OPS", "lanyardcard.fill")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.orange.opacity(0.20), lineWidth: 1))
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

    private var createEventButton: some View {
        Button {
            HapticManager.instance.impact(.medium)
            SpatialAudioManager.shared.play(.uiTap)
            app.setRoute(.eventEditor)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .black))

                Text("CREATE EVENT")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(1.1)

                Spacer()

                Text("DRAFT")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.black.opacity(0.14)))
            }
            .foregroundColor(.black.opacity(0.90))
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.orange.opacity(0.96))
            )
        }
        .buttonStyle(.plain)
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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 1)
        )
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
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
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
        Button {
            HapticManager.instance.impact(.light)
            SpatialAudioManager.shared.play(.uiTap)
            app.selectedEvent = event
            app.setRoute(.manageEvent)
        } label: {
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

                        Text("\(event.attendeeCount)/\(max(0, event.capacity)) RSVP")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .tracking(0.8)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white.opacity(0.30))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
        case "submitted":
            return "hourglass"
        case "rejected":
            return "xmark.seal.fill"
        case "draft":
            return "doc.text.fill"
        default:
            return "circle.grid.cross.fill"
        }
    }

    private func statusColor(for event: AppState.TGEvent) -> Color {
        if event.published && event.approvalStatus == "approved" {
            return .green
        }

        switch event.approvalStatus {
        case "submitted":
            return .orange
        case "rejected":
            return .red
        case "draft":
            return .white
        default:
            return .orange
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
