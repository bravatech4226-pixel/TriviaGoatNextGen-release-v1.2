//
//  EventDetailView.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Public event detail surface.
//  - Premium event destination
//  - RSVP action dock
//  - Calendar/reminder action
//  - Live event hub access
//  - Deep-link share payload
//

import SwiftUI
import Combine
import UIKit

struct EventDetailView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL

    let event: AppState.TGEvent

    @State private var showShareSheet = false
    @State private var now = Date()
    @State private var pulse = false

    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private var currentEvent: AppState.TGEvent {
        app.events.first(where: { $0.id == event.id }) ?? app.selectedEvent ?? event
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
                            actionDock
                            eventSnapshotCard
                            timelineCard
                            momentumCard
                            detailSection
                            organizerSection
                            hostManagementCard
                            liveEventHubCard
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
                app.selectedEvent = currentEvent

                if !isLiveNow && !hasEnded {
                    app.listenToRSVPState(for: currentEvent.id)
                }

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
        HStack(spacing: 12) {
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
                    .overlay(Circle().stroke(Color.orange.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, max(safeTop, 44) + 12)
        .padding(.bottom, 14)
        .background(Color.black.opacity(0.74).ignoresSafeArea(edges: .top))
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isLiveNow && pulse ? 1.24 : 1.0)

                        Text(heroEyebrow)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(statusColor.opacity(0.98))
                            .tracking(2.4)
                    }

                    Text(currentEvent.category.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.42))
                        .tracking(1.8)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(statusColor.opacity(pulse ? 0.18 : 0.08))
                        .frame(width: 68, height: 68)
                        .blur(radius: pulse ? 5 : 0)

                    Circle()
                        .stroke(statusColor.opacity(0.22), lineWidth: 1)
                        .frame(width: 58, height: 58)

                    Image(systemName: statusIcon)
                        .font(.system(size: 25, weight: .black))
                        .foregroundColor(statusColor.opacity(0.96))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(currentEvent.title)
                    .font(.system(size: currentEvent.title.count > 48 ? 31 : 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)

                if !heroCopy.isEmpty {
                    Text(heroCopy)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            countdownBlock

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, statusColor.opacity(0.26), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            HStack(spacing: 10) {
                statusPill
                eventDatePill

                Spacer()
            }
        }
        .padding(22)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.black.opacity(0.86))

                LinearGradient(
                    colors: [
                        statusColor.opacity(0.14),
                        Color.blue.opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(statusColor.opacity(pulse ? 0.36 : 0.22), lineWidth: 1.2)
        )
        .shadow(color: statusColor.opacity(0.18), radius: 30, x: 0, y: 16)
    }

    private var countdownBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(countdownLabel)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.46))
                .tracking(1.4)

            Text(timelineText)
                .font(.system(size: 32, weight: .black, design: .monospaced))
                .foregroundColor(statusColor.opacity(0.96))
                .tracking(1)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(statusColor.opacity(0.18), lineWidth: 1)
        )
    }
    private var eventDatePill: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .black))

            Text(formattedDate)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundColor(hasEnded ? .white.opacity(0.72) : .black)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(hasEnded ? Color.white.opacity(0.12) : statusColor.opacity(0.96))
        )
    }

    private var eventSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "EVENT SNAPSHOT",
                subtitle: "Everything players need before they join"
            )

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    snapshotTile(icon: "calendar", title: "DATE", value: formattedDate)
                    snapshotTile(icon: "person.2.fill", title: "ATTENDING", value: attendeeText)
                }

                HStack(spacing: 10) {
                    snapshotTile(icon: "dot.radiowaves.left.and.right", title: "ACCESS", value: accessText)
                    snapshotTile(icon: "ticket.fill", title: "STATUS", value: statusTitle)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.052))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func snapshotTile(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(statusColor.opacity(0.92))

                Text(title)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.40))
                    .tracking(1.2)
            }

            Text(value)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        )
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "EVENT TIMELINE",
                subtitle: "Registration, waitlist, and live event windows"
            )

            VStack(spacing: 10) {
                timelineRow(
                    title: "RSVP WINDOW",
                    value: rsvpWindowText,
                    icon: "person.crop.circle.badge.plus",
                    isActive: !hasEnded && !isFull
                )

                timelineRow(
                    title: "WAITLIST",
                    value: waitlistWindowText,
                    icon: "person.3.sequence.fill",
                    isActive: isWaitlistOpen
                )

                timelineRow(
                    title: "EVENT START",
                    value: formattedStartDate,
                    icon: "flag.checkered",
                    isActive: !hasEnded
                )

                timelineRow(
                    title: "EVENT END",
                    value: formattedEndDate,
                    icon: "flag.fill",
                    isActive: isLiveNow
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private func timelineRow(
        title: String,
        value: String,
        icon: String,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundColor(isActive ? statusColor.opacity(0.94) : .white.opacity(0.34))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isActive ? statusColor.opacity(0.12) : Color.white.opacity(0.055))
                )
                .overlay(
                    Circle()
                        .stroke(isActive ? statusColor.opacity(0.18) : Color.white.opacity(0.06), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(isActive ? .white.opacity(0.88) : .white.opacity(0.44))
                    .tracking(1)

                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(isActive ? 0.70 : 0.42))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
            }

            Spacer()

            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(isActive ? statusColor.opacity(0.90) : .white.opacity(0.24))
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isActive ? statusColor.opacity(0.06) : Color.black.opacity(0.24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isActive ? statusColor.opacity(0.16) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var momentumCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "EVENT MOMENTUM",
                subtitle: "Live registration energy and capacity signal"
            )

            HStack(spacing: 10) {
                momentumMetric(
                    title: "REGISTERED",
                    value: "\(currentEvent.attendeeCount)",
                    icon: "person.2.fill"
                )

                momentumMetric(
                    title: "WAITLIST",
                    value: "\(currentEvent.waitlistCount)",
                    icon: "person.crop.circle.badge.clock"
                )

                momentumMetric(
                    title: "CAPACITY",
                    value: capacityPercentText,
                    icon: "gauge.with.dots.needle.67percent"
                )
            }

            capacityBar
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.052))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(statusColor.opacity(0.12), lineWidth: 1)
        )
    }

    private func momentumMetric(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundColor(statusColor.opacity(0.92))

            Text(value)
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            Text(title)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.42))
                .tracking(0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var capacityBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(statusColor.opacity(0.88))
                    .frame(width: max(8, proxy.size.width * capacityProgress))
            }
        }
        .frame(height: 10)
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "EVENT BRIEFING",
                subtitle: "Overview, experience, and player expectations"
            )

            Text(currentEvent.summary.isEmpty ? "More event details coming soon." : currentEvent.summary)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            Text(subtitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.48))
        }
    }
    private var organizerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "HOSTED BY",
                subtitle: "Verified organizer and event ownership"
            )

            organizerRow
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.052))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var organizerRow: some View {
        HStack(spacing: 14) {
            organizerIcon

            organizerText

            Spacer()

            organizerVerifiedMark
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.12), lineWidth: 1)
        )
    }

    private var organizerIcon: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.14))
                .frame(width: 50, height: 50)

            Circle()
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
                .frame(width: 50, height: 50)

            Image(systemName: isOrganizer ? "crown.fill" : "checkmark.seal.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundColor(.orange.opacity(0.92))
        }
    }

    private var organizerText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(organizerDisplayName.uppercased())
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.76)

            Text(isOrganizer ? "YOU ARE HOSTING THIS EVENT" : hostedBySubtitle)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.48))
                .tracking(0.8)
        }
    }

    private var organizerVerifiedMark: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.green.opacity(0.82))

            Text("VERIFIED")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(.green.opacity(0.78))
                .tracking(0.8)
        }
    }

    @ViewBuilder
    private var hostManagementCard: some View {
        if app.canManage(currentEvent) || app.canModerate(currentEvent) {
            Button {
                HapticManager.instance.impact(.light)
                SpatialAudioManager.shared.play(.uiTap)
                app.selectedEvent = currentEvent
                app.setRoute(.manageEvent)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.black.opacity(0.86))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.orange.opacity(0.96)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("MANAGE EVENT")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.94))
                            .tracking(0.9)

                        Text("Open creator/admin controls, review workflow, publishing, and guest operations.")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.56))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.white.opacity(0.34))
                }
                .padding(16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black.opacity(0.52))

                        LinearGradient(
                            colors: [
                                Color.orange.opacity(0.12),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.orange.opacity(0.20), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var liveEventHubCard: some View {
        if isLiveNow || hasEnded {
            Button {
                HapticManager.instance.impact(.medium)
                SpatialAudioManager.shared.play(.uiTap)
                openURL(eventShareURL)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.18))
                            .frame(width: 48, height: 48)

                        Image(systemName: hasEnded ? "play.rectangle.fill" : "safari.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(hasEnded ? "VIEW EVENT HUB" : "OPEN EVENT HUB")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(0.9)

                        Text(hasEnded ? "Catch the event page, recap, and follow-up details." : "Jump to the live event page for launch updates and access.")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.64))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white.opacity(0.42))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.78)))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(statusColor.opacity(pulse ? 0.34 : 0.18), lineWidth: 1))
                .shadow(color: statusColor.opacity(0.14), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var actionDock: some View {
        if hasEnded {
            eventStateDock(
                title: "EVENT ENDED",
                subtitle: "Registration is closed. View the event hub for recap and follow-up details.",
                icon: "archivebox.fill",
                tint: .white.opacity(0.72),
                actionTitle: "VIEW EVENT HUB",
                actionIcon: "arrow.up.right"
            ) {
                openURL(eventShareURL)
            }
        } else if isLiveNow {
            eventStateDock(
                title: "LIVE NOW",
                subtitle: "RSVP is closed. Open the live event hub for current updates and access.",
                icon: "dot.radiowaves.left.and.right",
                tint: .orange,
                actionTitle: "OPEN EVENT HUB",
                actionIcon: "safari.fill"
            ) {
                openURL(eventShareURL)
            }
        } else {
            EventActionDock(
                event: currentEvent,
                onShare: {
                    HapticManager.instance.impact(.light)
                    SpatialAudioManager.shared.play(.uiTap)
                    showShareSheet = true
                }
            )
        }
    }
    
    private func eventStateDock(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        actionTitle: String,
        actionIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 46, height: 46)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(1)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Button {
                HapticManager.instance.impact(.medium)
                SpatialAudioManager.shared.play(.uiTap)
                action()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 12, weight: .black))

                    Text(actionTitle)
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(0.8)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .black))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.96))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
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
        URL(string: "https://triviagoat.ca/events/public/\(currentEvent.id)")!
    }

    private var eventShareText: String {
        var lines: [String] = []
        lines.append("Join me for this Trivia GOAT event:")
        lines.append(currentEvent.title)

        let heroLine = currentEvent.heroLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !heroLine.isEmpty {
            lines.append(heroLine)
        }

        lines.append("When: \(formattedDate)")
        lines.append("Open event: \(eventShareURL.absoluteString)")
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

    private var isWaitlisted: Bool {
        app.hasJoinedWaitlist(currentEvent.id)
    }
    
    private var isWaitlistOpen: Bool {
        app.isWaitlistWindowOpen(for: currentEvent)
    }

    private var heroCopy: String {
        let hero = currentEvent.heroLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hero.isEmpty { return hero }
        return currentEvent.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var normalizedStatus: String {
        currentEvent.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    
    private var headerSubtitle: String {
        if isLiveNow { return "LIVE NOW" }
        if hasEnded { return "EVENT ARCHIVE" }
        return currentEvent.category.uppercased()
    }

    private var heroEyebrow: String {
        if isLiveNow { return "LIVE EVENT" }
        if hasEnded { return "EVENT ARCHIVE" }
        if currentEvent.featured { return "FEATURED EVENT" }
        return "PREMIUM EVENT"
    }

    private var countdownLabel: String {
        if hasEnded { return "EVENT STATUS" }
        if isLiveNow { return "HAPPENING NOW" }
        if currentEvent.startsAt == nil { return "SCHEDULE STATUS" }
        return "STARTS IN"
    }

    private var organizerDisplayName: String {
        let cleaned = (currentEvent.organizerName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "Trivia GOAT Live" : cleaned
    }

    private var hostedBySubtitle: String {
        organizerDisplayName.caseInsensitiveCompare("Trivia GOAT Live") == .orderedSame ||
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

    private var formattedStartDate: String {
        guard let startsAt = currentEvent.startsAt else {
            return "DATE COMING"
        }

        return formattedTimelineDate(startsAt)
    }

    private var formattedEndDate: String {
        guard let startsAt = currentEvent.startsAt else {
            return "DATE COMING"
        }

        let endsAt = currentEvent.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        return formattedTimelineDate(endsAt)
    }

    private func formattedTimelineDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d • h:mm a"
        return formatter.string(from: date).uppercased()
    }
    private var rsvpWindowText: String {
        if hasEnded {
            return "REGISTRATION CLOSED"
        }

        guard let opensAt = currentEvent.rsvpOpensAt,
              let closesAt = currentEvent.rsvpClosesAt else {
            return "RSVP WINDOW COMING"
        }

        if now < opensAt {
            return "OPENS \(formattedTimelineDate(opensAt))"
        }

        if now > closesAt {
            return "CLOSED \(formattedTimelineDate(closesAt))"
        }

        return "OPEN UNTIL \(formattedTimelineDate(closesAt))"
    }

    private var waitlistWindowText: String {
        if hasEnded {
            return "WAITLIST CLOSED"
        }

        guard currentEvent.waitlistEnabled else {
            return "WAITLIST OFF"
        }

        guard let opensAt = currentEvent.waitlistOpensAt,
              let closesAt = currentEvent.waitlistClosesAt else {
            return "WINDOW COMING"
        }

        if now < opensAt {
            return "OPENS \(formattedTimelineDate(opensAt))"
        }

        if now > closesAt {
            return "CLOSED \(formattedTimelineDate(closesAt))"
        }

        return "OPEN UNTIL \(formattedTimelineDate(closesAt))"
    }

    private var attendeeText: String {
        if isFull && currentEvent.waitlistEnabled {
            return "\(currentEvent.waitlistCount) WAITLISTED"
        }

        guard currentEvent.capacity > 0 else {
            return "\(currentEvent.attendeeCount) RSVP"
        }

        if currentEvent.attendeeCount >= currentEvent.capacity {
            return "FULL"
        }

        return "\(currentEvent.attendeeCount)/\(currentEvent.capacity) RSVP"
    }

    private var accessText: String {
        if hasEnded { return "ARCHIVE" }
        if isLiveNow { return "LIVE" }
        if isFull { return isWaitlistOpen ? "WAITLIST" : "FULL" }
        return currentEvent.locationType.uppercased()
    }

    private var statusTitle: String {
        if isOrganizer { return "HOSTING" }
        if isRegistered { return "REGISTERED" }
        if isWaitlisted { return "WAITLISTED" }
        if hasEnded { return "ARCHIVED" }
        if isLiveNow { return "LIVE" }
        if isFull { return isWaitlistOpen ? "WAITLIST" : "FULL" }
        if currentEvent.published { return "OPEN RSVP" }
        return currentEvent.approvalStatus.uppercased()
    }

    private var statusIcon: String {
        if isOrganizer { return "crown.fill" }
        if isRegistered { return "checkmark.seal.fill" }
        if isWaitlisted { return "clock.badge.checkmark" }
        if hasEnded { return "archivebox.fill" }
        if isLiveNow { return "dot.radiowaves.left.and.right" }
        if isFull { return "lock.fill" }
        if currentEvent.startsAt == nil { return "calendar.badge.clock" }
        return "bolt.fill"
    }

    private var statusColor: Color {
        if isOrganizer { return .white }
        if isRegistered { return .green }
        if isWaitlisted { return .orange }
        if hasEnded { return .white.opacity(0.58) }
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
        if normalizedStatus == "live" {
            return true
        }

        guard let startsAt = currentEvent.startsAt else { return false }
        let endsAt = currentEvent.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        return now >= startsAt && now <= endsAt
    }

    private var hasEnded: Bool {
        if normalizedStatus == "ended" || normalizedStatus == "cancelled" {
            return true
        }

        guard let startsAt = currentEvent.startsAt else { return false }
        let endsAt = currentEvent.endsAt ?? startsAt.addingTimeInterval(2 * 60 * 60)
        return now > endsAt
    }

    private var isFull: Bool {
        currentEvent.capacity > 0 && currentEvent.attendeeCount >= currentEvent.capacity
    }

    private var capacityProgress: CGFloat {
        guard currentEvent.capacity > 0 else {
            return currentEvent.attendeeCount > 0 ? 1 : 0
        }

        return min(1, CGFloat(currentEvent.attendeeCount) / CGFloat(currentEvent.capacity))
    }

    private var capacityPercentText: String {
        guard currentEvent.capacity > 0 else {
            return currentEvent.attendeeCount > 0 ? "OPEN" : "0%"
        }

        return "\(Int(capacityProgress * 100))%"
    }

    private var timelineText: String {
        if hasEnded { return "PAST EVENT" }
        if isLiveNow { return "LIVE NOW" }

        guard let startsAt = currentEvent.startsAt else {
            return "SOON"
        }

        let seconds = Int(startsAt.timeIntervalSince(now))
        if seconds <= 0 { return "STARTING" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
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
                Color.black.opacity(0.74)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Color.green.opacity(0.26),
                        Color.orange.opacity(0.12),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 340
                )
                .ignoresSafeArea()

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.18))
                            .frame(width: 118, height: 118)
                            .blur(radius: 12)

                        Circle()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            .frame(width: 96, height: 96)

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 40, weight: .black))
                            .foregroundColor(.green.opacity(0.96))
                    }

                    Text("YOU'RE IN")
                        .font(.system(size: 30, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(confirmedEvent.title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 28)

                    Text(formattedDate)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.92))
                        .tracking(1)
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
                    statusColor.opacity(pulse ? 0.13 : 0.07),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 330
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
