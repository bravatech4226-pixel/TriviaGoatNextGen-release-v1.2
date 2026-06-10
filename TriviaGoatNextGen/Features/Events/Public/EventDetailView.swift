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
import FirebaseFirestore

struct EventDetailView: View {

    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL

    let event: AppState.TGEvent

    @State private var showShareSheet = false
    @State private var now = Date()
    @State private var pulse = false
    @State private var eventSessions: [EventPublicSession] = []
    @State private var eventSessionsListener: ListenerRegistration? = nil

    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private var currentEvent: AppState.TGEvent {
        app.events.first(where: { $0.id == event.id }) ?? app.selectedEvent ?? event
    }

    private var crmGuests: [AppState.EventGuest] {
        app.guests(for: currentEvent.id)
    }

    private func normalizedGuestStatus(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private var confirmedGuestCount: Int {
        crmGuests.filter { guest in
            let status = normalizedGuestStatus(guest.invitationStatus)
            return status == "accepted" || status == "checked_in" || status == "checkedin"
        }.count
    }

    private var liveRegisteredCount: Int {
        max(currentEvent.attendeeCount, confirmedGuestCount)
    }

    private var liveWaitlistCount: Int {
        let crmWaitlistCount = crmGuests.filter { guest in
            let status = normalizedGuestStatus(guest.invitationStatus)
            return status == "waitlisted" || status == "waitlist" || status == "waiting"
        }.count

        return max(currentEvent.waitlistCount, crmWaitlistCount)
    }


    private struct EventPublicSession: Identifiable, Equatable {
        let id: String
        let title: String
        let description: String
        let speakerIDs: [String]
        let room: String
        let track: String
        let startsAt: Date?
        let endsAt: Date?
        let capacity: Int
        let featured: Bool
        let status: String
    }

    private var visibleEventSessions: [EventPublicSession] {
        eventSessions
            .filter { session in
                let status = session.status
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return status != "hidden" && status != "deleted" && status != "archived"
            }
            .sorted { lhs, rhs in
                switch (lhs.startsAt, rhs.startsAt) {
                case let (.some(left), .some(right)):
                    return left < right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
    }

    private func startEventSessionsListener(for eventID: String) {
        let cleanedID = eventID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedID.isEmpty else { return }

        stopEventSessionsListener()

        eventSessionsListener = FirestoreService.db
            .collection("events")
            .document(cleanedID)
            .collection("sessions")
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("⚠️ [EventDetailView] Sessions listener failed:", error)
                    return
                }

                let sessions: [EventPublicSession] = snapshot?.documents.compactMap { doc in
                    let data = doc.data()

                    return EventPublicSession(
                        id: doc.documentID,
                        title: data["title"] as? String ?? "",
                        description: data["description"] as? String ?? "",
                        speakerIDs: data["speakerIDs"] as? [String] ?? [],
                        room: data["room"] as? String ?? "",
                        track: data["track"] as? String ?? "",
                        startsAt: eventDetailDateValue(data["startsAt"]),
                        endsAt: eventDetailDateValue(data["endsAt"]),
                        capacity: data["capacity"] as? Int ?? 0,
                        featured: data["featured"] as? Bool ?? false,
                        status: data["status"] as? String ?? "published"
                    )
                } ?? []

                Task { @MainActor in
                    self.eventSessions = sessions
                    print("🟢 [EventDetailView] Loaded event sessions:", sessions.count)
                }
            }
    }

    private func stopEventSessionsListener() {
        eventSessionsListener?.remove()
        eventSessionsListener = nil
        eventSessions = []
    }

    private func eventDetailDateValue(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }

        if let date = value as? Date {
            return date
        }

        if let seconds = value as? TimeInterval {
            return Date(timeIntervalSince1970: seconds)
        }

        if let iso = value as? String {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: iso)
        }

        return nil
    }

    @ViewBuilder
    private var publicAgendaSection: some View {
        if !visibleEventSessions.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader(
                        title: "EVENT AGENDA",
                        subtitle: "Sessions, speakers, rooms, and timing"
                    )

                    Spacer()

                    Text("\(visibleEventSessions.count) SESSION\(visibleEventSessions.count == 1 ? "" : "S")")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.46))
                        .tracking(1)
                }

                VStack(spacing: 12) {
                    ForEach(visibleEventSessions) { session in
                        publicAgendaSessionCard(session)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        }
    }

    private func publicAgendaSessionCard(_ session: EventPublicSession) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sessionTimeText(session.startsAt))
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.94))
                    .lineLimit(1)

                Text(sessionTimeText(session.endsAt))
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.44))
                    .lineLimit(1)
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(session.title.isEmpty ? "Untitled Session" : session.title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.94))
                        .lineLimit(2)

                    if session.featured {
                        Text("FEATURED")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(.black.opacity(0.88))
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Capsule().fill(Color.orange.opacity(0.96)))
                    }
                }

                let meta = publicAgendaMetaText(session)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.42))
                        .tracking(0.8)
                        .lineLimit(2)
                }

                let names = sessionSpeakerNames(for: session)
                if !names.isEmpty {
                    Text(names)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.orange.opacity(0.88))
                        .lineLimit(2)
                }

                if !session.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(session.description)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.32)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(session.featured ? Color.orange.opacity(0.22) : Color.white.opacity(0.07), lineWidth: 1))
    }

    private func sessionTimeText(_ date: Date?) -> String {
        guard let date else { return "TBA" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date).uppercased()
    }

    private func publicAgendaMetaText(_ session: EventPublicSession) -> String {
        [session.track, session.room]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.uppercased() }
            .joined(separator: " • ")
    }

    private func sessionSpeakerNames(for session: EventPublicSession) -> String {
        let normalizedIDs = Set(session.speakerIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })

        let matched = crmGuests.filter { guest in
            normalizedIDs.contains(guest.id)
        }

        return matched
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
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
                            publicAgendaSection
                            meetTheSpeakersSection
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
                app.startEventGuestsListener(for: event.id)
                startEventSessionsListener(for: currentEvent.id)

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
            .onDisappear {
                stopEventSessionsListener()
            }
            .sheet(isPresented: $showShareSheet) {
                EventShareSheet(items: eventShareItems)
            }
        }
    }

    @ViewBuilder
    private var meetTheSpeakersSection: some View {
        let speakers = crmGuests
            .filter { guest in
                let role = guest.role
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: "-", with: "_")
                    .replacingOccurrences(of: " ", with: "_")

                return role == "speaker" || role == "moderator" || role == "panelist"
            }
            .sorted { lhs, rhs in
                let lhsRole = lhs.role.localizedCaseInsensitiveCompare(rhs.role)
                if lhsRole != .orderedSame {
                    return speakerSortRank(lhs.role) < speakerSortRank(rhs.role)
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        if !speakers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("MEET THE SPEAKERS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                VStack(spacing: 12) {
                    ForEach(speakers) { speaker in
                        speakerProfileCard(speaker)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        }
    }

    private func speakerProfileCard(_ speaker: AppState.EventGuest) -> some View {
        HStack(alignment: .top, spacing: 14) {
            speakerPortrait(speaker)

            VStack(alignment: .leading, spacing: 7) {
                Text(speaker.name.isEmpty ? "Featured Speaker" : speaker.name)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.94))
                    .lineLimit(2)

                Text(publicSpeakerRoleLabel(speaker.role))
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.black.opacity(0.88))
                    .tracking(0.8)
                    .padding(.horizontal, 8)
                    .frame(height: 21)
                    .background(Capsule().fill(Color.orange.opacity(0.96)))

                if !speaker.organization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(speaker.organization)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.58))
                        .lineLimit(2)
                }

                if !speaker.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(speaker.bio)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.66))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.32)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.orange.opacity(0.16), lineWidth: 1))
    }

    private func speakerSortRank(_ role: String) -> Int {
        switch normalizedSpeakerRole(role) {
        case "keynote", "keynote_speaker": return 0
        case "speaker": return 1
        case "panelist": return 2
        case "moderator": return 3
        default: return 9
        }
    }

    private func normalizedSpeakerRole(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func publicSpeakerRoleLabel(_ role: String) -> String {
        switch normalizedSpeakerRole(role) {
        case "keynote", "keynote_speaker": return "KEYNOTE SPEAKER"
        case "panelist": return "PANELIST"
        case "moderator": return "MODERATOR"
        case "speaker": return "SPEAKER"
        default:
            let cleaned = role.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "SPEAKER" : cleaned.uppercased()
        }
    }

    @ViewBuilder
    private func speakerPortrait(_ speaker: AppState.EventGuest) -> some View {
        if let urlString = speaker.headshotURL,
           let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
           !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    speakerPortraitPlaceholder(speaker)

                case .empty:
                    ProgressView()
                        .tint(.orange)

                @unknown default:
                    speakerPortraitPlaceholder(speaker)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.orange.opacity(0.30), lineWidth: 1.2))
            .shadow(color: Color.orange.opacity(0.12), radius: 10, x: 0, y: 4)
        } else {
            speakerPortraitPlaceholder(speaker)
                .frame(width: 64, height: 64)
        }
    }

    private func speakerPortraitPlaceholder(_ speaker: AppState.EventGuest) -> some View {
        let initials = speaker.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()

        return ZStack {
            Circle()
                .fill(Color.orange.opacity(0.12))

            Text(initials.isEmpty ? "TG" : initials)
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.95))
        }
        .overlay(Circle().stroke(Color.orange.opacity(0.30), lineWidth: 1.2))
    .shadow(color: Color.orange.opacity(0.12), radius: 10, x: 0, y: 4)
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
                        .frame(width: 64, height: 64)

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
                    value: "\(liveRegisteredCount)",
                    icon: "person.2.fill"
                )

                momentumMetric(
                    title: "WAITLIST",
                    value: "\(liveWaitlistCount)",
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
            return "\(liveWaitlistCount) WAITLISTED"
        }

        guard currentEvent.capacity > 0 else {
            return "\(liveRegisteredCount) RSVP"
        }

        if liveRegisteredCount >= currentEvent.capacity {
            return "FULL"
        }

        return "\(liveRegisteredCount)/\(currentEvent.capacity) RSVP"
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
        currentEvent.capacity > 0 && liveRegisteredCount >= currentEvent.capacity
    }

    private var capacityProgress: CGFloat {
        guard currentEvent.capacity > 0 else {
            return liveRegisteredCount > 0 ? 1 : 0
        }

        return min(1, CGFloat(liveRegisteredCount) / CGFloat(currentEvent.capacity))
    }

    private var capacityPercentText: String {
        guard currentEvent.capacity > 0 else {
            return liveRegisteredCount > 0 ? "OPEN" : "0%"
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
