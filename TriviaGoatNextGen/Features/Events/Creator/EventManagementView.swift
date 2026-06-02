//
//  EventManagementView.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Creator/Admin event command center.
//  Draft → Submitted → Approved → Published → RSVP/Ops.
//

import SwiftUI

struct EventManagementView: View {

    @EnvironmentObject private var app: AppState

    let event: AppState.TGEvent

    private var isApproved: Bool { event.approvalStatus == "approved" }
    private var isSubmitted: Bool { event.approvalStatus == "submitted" }
    private var isDraft: Bool { event.approvalStatus == "draft" }
    private var isRejected: Bool { event.approvalStatus == "rejected" }
    private var isLivePublished: Bool { event.published && isApproved }

    private var capacityText: String {
        event.capacity > 0 ? "\(event.attendeeCount)/\(event.capacity) attending" : "\(event.attendeeCount) attending"
    }

    private var remainingText: String {
        event.capacity > 0 ? "\(max(0, event.capacity - event.attendeeCount)) seats left" : "Open capacity"
    }

    private var statusText: String {
        if isLivePublished { return "PUBLISHED" }
        if isApproved { return "APPROVED" }
        return event.approvalStatus.uppercased()
    }

    private var lifecycleText: String {
        if isLivePublished { return "Public access active" }
        if isApproved { return "Approved, ready to publish" }
        if isSubmitted { return "Awaiting admin review" }
        if isRejected { return "Needs revision" }
        if isDraft { return "Draft in progress" }
        return "Event operations"
    }

    private var statusColor: Color {
        if isLivePublished || isApproved { return .green }

        switch event.approvalStatus {
        case "submitted": return .orange
        case "rejected": return .red
        case "draft": return .white
        default: return .orange
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpaceBackground()

                VStack(spacing: 0) {
                    header(safeTop: geo.safeAreaInsets.top)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            heroPanel
                            lifecyclePanel
                            statusPanel
                            adminReviewPanel
                            attendeeSnapshot
                            operationsPanel
                            wdcPanel
                            messagingPanel
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 40)
                    }
                }

                toastOverlay
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarHidden(true)
        }
    }

    private func header(safeTop: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.setRoute(.creatorConsole)
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
                Text("MANAGE EVENT")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .tracking(1.6)

                Text(event.category.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.refreshEvents()
                app.showEventToast("SYNCING EVENT")
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

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(statusText)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(isLivePublished || isApproved ? .black.opacity(0.88) : .white.opacity(0.90))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill((isLivePublished || isApproved) ? Color.green.opacity(0.92) : statusColor.opacity(0.18)))
                    .overlay(Capsule().stroke(statusColor.opacity(0.26), lineWidth: 1))

                Text(event.visibility.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .tracking(1)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.white.opacity(0.055)))

                Spacer()

                Text(event.locationType.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.82))
                    .tracking(1)
            }

            Text(event.title)
                .font(.system(size: event.title.count > 46 ? 26 : 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(event.heroLine.isEmpty ? event.summary : event.heroLine)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.66))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Color.white.opacity(0.08))

            HStack {
                statBlock(title: "CAPACITY", value: capacityText)
                statBlock(title: "REMAINING", value: remainingText)
                statBlock(title: "WAITLIST", value: event.waitlistEnabled ? "ENABLED" : "OFF")
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.orange.opacity(0.22), lineWidth: 1.2))
    }

    private var lifecyclePanel: some View {
        sectionPanel(title: "EVENT LIFECYCLE", subtitle: lifecycleText) {
            VStack(spacing: 10) {
                lifecycleRow(title: "Creator Draft", isComplete: true)
                lifecycleRow(title: "Submitted for Review", isComplete: isSubmitted || isApproved || isLivePublished)
                lifecycleRow(title: "Admin Approved", isComplete: isApproved || isLivePublished)
                lifecycleRow(title: "Public Access Live", isComplete: isLivePublished)
            }
        }
    }

    private func lifecycleRow(title: String, isComplete: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(isComplete ? .green.opacity(0.92) : .white.opacity(0.28))

            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(isComplete ? .white.opacity(0.84) : .white.opacity(0.42))
                .tracking(0.8)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.30)))
    }

    private var statusPanel: some View {
        sectionPanel(title: "STATUS CONTROLS", subtitle: "Creator workflow and publishing") {
            HStack(spacing: 10) {
                controlButton(title: primaryActionTitle, icon: primaryActionIcon, tint: primaryActionTint) {
                    handlePrimaryAction()
                }

                controlButton(
                    title: event.featured ? "FEATURED" : "FEATURE",
                    icon: "star.fill",
                    tint: .orange
                ) {
                    app.setEventFeatured(event, featured: !event.featured)
                }
            }

            HStack(spacing: 10) {
                controlButton(title: "EDIT", icon: "square.and.pencil", tint: .white) {
                    guard app.canEdit(event) else {
                        app.showEventToast("EDIT LOCKED")
                        return
                    }

                    app.selectedEvent = event
                    app.setRoute(.eventEditor)
                }

                controlButton(title: "PUBLIC VIEW", icon: "arrow.up.right.square.fill", tint: .white) {
                    guard isLivePublished else {
                        app.showEventToast("NOT PUBLIC YET")
                        return
                    }

                    app.selectedEvent = event
                    app.setRoute(.eventDetail)
                }
            }
        }
    }

    @ViewBuilder
    private var adminReviewPanel: some View {
        if app.canModerate(event) && isSubmitted {
            sectionPanel(title: "ADMIN REVIEW", subtitle: "Approve or return event to creator") {
                HStack(spacing: 10) {
                    controlButton(title: "APPROVE", icon: "checkmark.seal.fill", tint: .green) {
                        app.approveEvent(event)
                    }

                    controlButton(title: "REJECT", icon: "xmark.seal.fill", tint: .red) {
                        app.rejectEvent(event)
                    }
                }
            }
        }
    }

    private var primaryActionTitle: String {
        if isLivePublished { return "LIVE" }
        if isApproved { return "PUBLISH" }
        if isSubmitted { return app.canModerate(event) ? "REVIEW" : "IN REVIEW" }
        if isRejected { return "REVISE" }
        return "SUBMIT"
    }

    private var primaryActionIcon: String {
        if isLivePublished { return "checkmark.seal.fill" }
        if isApproved { return "paperplane.fill" }
        if isSubmitted { return app.canModerate(event) ? "checkmark.seal.fill" : "hourglass" }
        if isRejected { return "exclamationmark.triangle.fill" }
        return "paperplane.fill"
    }

    private var primaryActionTint: Color {
        if isLivePublished { return .green }
        if isRejected { return .red }
        return .orange
    }

    private func handlePrimaryAction() {
        if isLivePublished {
            app.showEventToast("EVENT IS LIVE")
            return
        }

        if isApproved {
            app.publishApprovedEvent(event)
            return
        }

        if isSubmitted {
            if app.canModerate(event) {
                app.approveEvent(event)
            } else {
                app.showEventToast("AWAITING REVIEW")
            }
            return
        }

        if isRejected {
            app.selectedEvent = event
            app.setRoute(.eventEditor)
            return
        }

        app.submitEventForReview(event)
    }

    private var attendeeSnapshot: some View {
        sectionPanel(title: "ATTENDEE SNAPSHOT", subtitle: "Capacity, waitlist, and demand") {
            EventAttendeePreview(
                attendeeCount: event.attendeeCount,
                capacity: max(1, event.capacity),
                accent: .orange
            )
        }
    }

    private var operationsPanel: some View {
        sectionPanel(title: "OPERATIONS", subtitle: "Event-day command tools") {
            HStack(spacing: 10) {
                opsTile(title: "CHECK-IN", subtitle: "Door flow", icon: "qrcode.viewfinder")
                opsTile(title: "BADGES", subtitle: "Guest IDs", icon: "lanyardcard.fill")
            }

            HStack(spacing: 10) {
                opsTile(title: "RUN OF SHOW", subtitle: "Timeline", icon: "list.bullet.rectangle.fill")
                opsTile(title: "STAFF ROLES", subtitle: "Delegated ops", icon: "person.3.fill")
            }
        }
    }

    private var wdcPanel: some View {
        sectionPanel(title: "WDC EVENT SYSTEM", subtitle: "Sessions, delegates, speakers, and guest panels") {
            operationRow(title: "SESSION BUILDER", subtitle: "Create tracks, rooms, and time blocks", icon: "rectangle.3.group.fill")
            operationRow(title: "DELEGATE DIRECTORY", subtitle: "Assign roles and access levels", icon: "person.crop.rectangle.stack.fill")
            operationRow(title: "GUEST PANEL", subtitle: "Speakers, moderators, sponsors, VIPs", icon: "person.2.badge.gearshape.fill")
        }
    }

    private var messagingPanel: some View {
        sectionPanel(title: "MESSAGING", subtitle: "Attendee communication center") {
            operationRow(title: "MESSAGE ATTENDEES", subtitle: "Send event updates", icon: "envelope.fill")
            operationRow(title: "SEND REMINDER", subtitle: "Push/email reminder workflow", icon: "bell.badge.fill")
            operationRow(title: "MESSAGE WAITLIST", subtitle: "Notify overflow demand", icon: "text.bubble.fill")
        }
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.42))
                .tracking(1)

            Text(value.uppercased())
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.86))
                .lineLimit(2)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionPanel<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.48))
                }
            }

            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func controlButton(
        title: String,
        icon: String,
        tint: Color,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            HapticManager.instance.impact(.light)
            SpatialAudioManager.shared.play(.uiTap)

            if let action {
                action()
            } else {
                app.showEventToast("COMING NEXT")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .black))

                Text(title)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            .foregroundColor(tint == .green ? .black.opacity(0.90) : tint.opacity(0.92))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(tint == .green ? Color.green.opacity(0.94) : tint.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func opsTile(title: String, subtitle: String, icon: String) -> some View {
        Button {
            HapticManager.instance.impact(.light)
            SpatialAudioManager.shared.play(.uiTap)
            app.showEventToast("COMING NEXT")
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .black))
                    .foregroundColor(.orange.opacity(0.92))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.orange.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.92))
                        .tracking(0.8)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.48))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 118)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func operationRow(title: String, subtitle: String, icon: String) -> some View {
        Button {
            HapticManager.instance.impact(.light)
            SpatialAudioManager.shared.play(.uiTap)
            app.showEventToast("COMING NEXT")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(.orange.opacity(0.92))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.orange.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.86))
                        .tracking(0.8)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.46))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white.opacity(0.28))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.34)))
        }
        .buttonStyle(.plain)
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
