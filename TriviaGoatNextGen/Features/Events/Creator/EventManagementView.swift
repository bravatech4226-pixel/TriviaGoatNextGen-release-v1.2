//
//  EventManagementView.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Creator/Admin event command center.
//  Draft → Submitted → Approved → Published → RSVP/Ops.
//  SSoT-safe: renders from latest AppState event snapshot.
//  Forward-ready: includes contacts import + staged invite/delegate workflow.
//  Backend persistence hook points are isolated in sendStagedInvitations().
//

import SwiftUI
import UIKit
import Contacts
import ContactsUI
import FirebaseFunctions
import FirebaseFirestore

struct EventManagementView: View {
    
    @EnvironmentObject private var app: AppState
    
    let event: AppState.TGEvent
    
    @State private var activeCommand: EventCommandSheet?
    @State private var commandNotes: String = ""
    @State private var communicationAudience: CommunicationAudience = .accepted
    @State private var communicationTemplate: CommunicationTemplate = .reminder
    @State private var communicationSubject: String = ""
    @State private var communicationIndividualGuest: GuestRecord? = nil
    @State private var isSendingCommunication: Bool = false
    
    @State private var guestName: String = ""
    @State private var guestEmail: String = ""
    @State private var guestOrganization: String = ""
    @State private var guestNotes: String = ""
    @State private var guestRole: GuestRole = .delegate
    @State private var guestStatus: GuestStatus = .manual
    @State private var guestIsVIP: Bool = false
    @State private var guestRecords: [GuestRecord] = []
    @State private var guestFilter: GuestFilter = .all
    
    @State private var sessionRecords: [EventSession] = []
    @State private var liveEventSessionsListener: ListenerRegistration? = nil
    @State private var liveEventSessionsEventID: String = ""
    
    @State private var sessionTitle: String = ""
    @State private var sessionDescription: String = ""
    @State private var sessionRoom: String = "Main Stage"
    @State private var sessionTrack: String = "General"
    @State private var sessionStartsAt: Date = Date()
    @State private var sessionEndsAt: Date = Date().addingTimeInterval(3600)
    @State private var sessionCapacityText: String = ""
    @State private var sessionFeatured: Bool = false
    @State private var sessionStatus: String = "draft"
    @State private var selectedSessionSpeakerIDs: Set<String> = []
    @State private var isSavingSession: Bool = false
    @State private var editingSession: EventSession? = nil
    @State private var editSessionTitle: String = ""
    @State private var editSessionDescription: String = ""
    @State private var editSessionRoom: String = "Main Stage"
    @State private var editSessionTrack: String = "General"
    @State private var editSessionStartsAt: Date = Date()
    @State private var editSessionEndsAt: Date = Date().addingTimeInterval(3600)
    @State private var editSessionCapacityText: String = ""
    @State private var editSessionFeatured: Bool = false
    @State private var editSessionStatus: String = "draft"
    @State private var editSessionSpeakerIDs: Set<String> = []
    
    
    @State private var contactImportRole: GuestRole = .delegate
    @State private var contactImportVIP: Bool = false
    @State private var contactsPermissionStatus: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @State private var isLoadingContacts: Bool = false
    @State private var contactSearchText: String = ""
    @State private var importedContacts: [ContactCandidate] = []
    @State private var selectedContactIDs: Set<String> = []
    @State private var showNativeContactPicker: Bool = false
    @State private var isSendingStagedInvitations: Bool = false
    @State private var liveEventGuests: [AppState.EventGuest] = []
    @State private var liveEventGuestsListener: ListenerRegistration? = nil
    @State private var liveEventGuestsEventID: String = ""
    
    @State private var editingGuest: GuestRecord? = nil
    @State private var editGuestName: String = ""
    @State private var editGuestEmail: String = ""
    @State private var editGuestOrganization: String = ""
    @State private var editGuestNotes: String = ""
    @State private var editGuestRole: GuestRole = .delegate
    @State private var editGuestStatus: GuestStatus = .manual
    @State private var editGuestIsVIP: Bool = false
    @State private var editGuestBio: String = ""
    @State private var editGuestHeadshotURL: String = ""
    @State private var editGuestFeaturedSpeaker: Bool = false
    
    private let contactStore = CNContactStore()
    
    private enum EventCommandSheet: String, Identifiable {
        case checkIn
        case badges
        case runOfShow
        case staffRoles
        case invitationCenter
        case sessionBuilder
        case delegateDirectory
        case guestPanel
        case messageAttendees
        case sendReminder
        case messageWaitlist
        
        var id: String { rawValue }
    }
    
    private enum GuestRole: String, CaseIterable, Identifiable {
        case delegate = "Delegate"
        case speaker = "Speaker"
        case moderator = "Moderator"
        case sponsor = "Sponsor"
        case vip = "VIP"
        case staff = "Staff"
        case attendee = "Attendee"
        
        var id: String { rawValue }
        
        var backendValue: String {
            rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
        }
    }
    
    private enum GuestStatus: String, CaseIterable, Identifiable {
        case manual = "Manual"
        case staged = "Staged"
        case invited = "Invited"
        case accepted = "Accepted"
        case declined = "Declined"
        case checkedIn = "Checked In"
        
        var id: String { rawValue }
        
        var backendValue: String {
            rawValue.lowercased().replacingOccurrences(of: " ", with: "_")
        }
    }
    
    private enum GuestFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case staged = "Staged"
        case invited = "Invited"
        case accepted = "Accepted"
        case vip = "VIP"
        case staff = "Staff"
        
        var id: String { rawValue }
    }

    private enum CommunicationAudience: String, CaseIterable, Identifiable {
        case all = "All Guests"
        case accepted = "Accepted"
        case invited = "Invited"
        case waitlist = "Waitlist"
        case checkedIn = "Checked In"
        case vip = "VIP"
        case speakers = "Speakers"

        var id: String { rawValue }

        var shortLabel: String {
            switch self {
            case .all: return "ALL"
            case .accepted: return "ACCEPTED"
            case .invited: return "INVITED"
            case .waitlist: return "WAITLIST"
            case .checkedIn: return "CHECKED IN"
            case .vip: return "VIP"
            case .speakers: return "SPEAKERS"
            }
        }

        var backendValue: String {
            switch self {
            case .all: return "all"
            case .accepted: return "accepted"
            case .invited: return "invited"
            case .waitlist: return "waitlist"
            case .checkedIn: return "checked_in"
            case .vip: return "vip"
            case .speakers: return "speakers"
            }
        }

        var icon: String {
            switch self {
            case .all: return "person.3.fill"
            case .accepted: return "checkmark.seal.fill"
            case .invited: return "paperplane.fill"
            case .waitlist: return "person.crop.circle.badge.clock"
            case .checkedIn: return "qrcode.viewfinder"
            case .vip: return "star.circle.fill"
            case .speakers: return "mic.fill"
            }
        }
    }

    private enum CommunicationTemplate: String, CaseIterable, Identifiable {
        case reminder = "Reminder"
        case finalCall = "Final Call"
        case venueChange = "Venue Change"
        case scheduleUpdate = "Schedule Update"
        case checkInInstructions = "Check-In"
        case thankYou = "Thank You"
        case custom = "Custom"

        var id: String { rawValue }

        var shortLabel: String {
            switch self {
            case .reminder: return "REMINDER"
            case .finalCall: return "FINAL CALL"
            case .venueChange: return "VENUE"
            case .scheduleUpdate: return "SCHEDULE"
            case .checkInInstructions: return "CHECK-IN"
            case .thankYou: return "THANK YOU"
            case .custom: return "CUSTOM"
            }
        }

        var backendValue: String {
            switch self {
            case .reminder: return "reminder"
            case .finalCall: return "final_call"
            case .venueChange: return "venue_change"
            case .scheduleUpdate: return "schedule_update"
            case .checkInInstructions: return "check_in_instructions"
            case .thankYou: return "thank_you"
            case .custom: return "custom"
            }
        }

        var icon: String {
            switch self {
            case .reminder: return "bell.badge.fill"
            case .finalCall: return "megaphone.fill"
            case .venueChange: return "mappin.and.ellipse"
            case .scheduleUpdate: return "calendar.badge.clock"
            case .checkInInstructions: return "qrcode.viewfinder"
            case .thankYou: return "sparkles"
            case .custom: return "square.and.pencil"
            }
        }
    }
    
    private struct GuestRecord: Identifiable, Equatable {
        let id: UUID
        
        var name: String
        var email: String
        
        var organization: String
        
        var role: GuestRole
        var status: GuestStatus
        
        var isVIP: Bool
        
        var notes: String
        
        // CRM speaker profile fields
        var bio: String = ""
        var headshotURL: String? = nil
        var featuredSpeaker: Bool = false
        
        var source: String
        var createdAt: Date
        
        
        init(
            id: UUID = UUID(),
            name: String,
            email: String,
            organization: String,
            role: GuestRole,
            status: GuestStatus,
            isVIP: Bool,
            notes: String,
            source: String,
            createdAt: Date = Date()
        ){
            self.id = id
            self.name = name
            self.email = email
            self.organization = organization
            self.role = role
            self.status = status
            self.isVIP = isVIP
            self.notes = notes
            self.source = source
            self.createdAt = createdAt
        }
    }
    
    private struct ContactCandidate: Identifiable, Equatable {
        let id: String
        let name: String
        let email: String
        let organization: String
        
        var displayEmail: String {
            email.isEmpty ? "No email on contact" : email
        }
    }
    
    private var currentEvent: AppState.TGEvent {
        app.events.first(where: { $0.id == event.id }) ?? app.selectedEvent ?? event
    }

    private var currentCRMGuests: [AppState.EventGuest] {
        if !liveEventGuests.isEmpty {
            return liveEventGuests
        }

        return app.guests(for: currentEvent.id)
    }
    
    private var isApproved: Bool { currentEvent.approvalStatus == "approved" }
    private var isSubmitted: Bool { currentEvent.approvalStatus == "submitted" }
    private var isDraft: Bool { currentEvent.approvalStatus == "draft" }
    private var isRejected: Bool { currentEvent.approvalStatus == "rejected" }
    private var isLivePublished: Bool { currentEvent.published && isApproved }
    
    private var filteredContacts: [ContactCandidate] {
        let query = contactSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return importedContacts }
        
        return importedContacts.filter {
            $0.name.lowercased().contains(query)
            || $0.email.lowercased().contains(query)
            || $0.organization.lowercased().contains(query)
        }
    }
    
    private var liveGuestRecords: [GuestRecord] {
        currentCRMGuests.map { crmGuestRecord(from: $0) }
    }
    
    private var directoryGuestRecords: [GuestRecord] {
        let persistedEmails = Set(
            liveGuestRecords
                .map { normalizedEmail($0.email) }
                .filter { !$0.isEmpty }
        )
        
        let localOnlyRecords = guestRecords.filter { record in
            let email = normalizedEmail(record.email)
            guard !email.isEmpty else { return true }
            return !persistedEmails.contains(email)
        }
        
        return (liveGuestRecords + localOnlyRecords).sorted { lhs, rhs in
            let lhsStatus = statusSortRank(lhs.status)
            let rhsStatus = statusSortRank(rhs.status)
            
            if lhsStatus != rhsStatus {
                return lhsStatus < rhsStatus
            }
            
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    private var filteredGuests: [GuestRecord] {
        let records = directoryGuestRecords
        
        switch guestFilter {
        case .all:
            return records
        case .staged:
            return records.filter { $0.status == .staged }
        case .invited:
            return records.filter { $0.status == .invited }
        case .accepted:
            return records.filter { $0.status == .accepted || $0.status == .checkedIn }
        case .vip:
            return records.filter { $0.isVIP || $0.role == .vip }
        case .staff:
            return records.filter { $0.role == .staff || $0.role == .moderator }
        }
    }
    
    private var stagedInviteCount: Int {
        guestRecords.filter { $0.status == .staged }.count
    }
    
    private var displayedContacts: [ContactCandidate] {
        Array(filteredContacts.prefix(250))
    }
    
    private var selectableDisplayedContacts: [ContactCandidate] {
        displayedContacts.filter { !$0.email.isEmpty && !isContactAlreadyInDirectory($0) }
    }
    
    private var capacityText: String {
        currentEvent.capacity > 0
        ? "\(currentEvent.attendeeCount)/\(currentEvent.capacity) attending"
        : "\(currentEvent.attendeeCount) attending"
    }
    
    private var remainingText: String {
        currentEvent.capacity > 0
        ? "\(max(0, currentEvent.capacity - liveCRMCapacityCount)) seats left"
        : "Open capacity"
    }
    
    private var invitedCRMCount: Int {
        currentCRMGuests.filter { normalizedInvitationStatus($0.invitationStatus) == "invited" }.count
    }
    
    private var acceptedCRMCount: Int {
        currentCRMGuests.filter { normalizedInvitationStatus($0.invitationStatus) == "accepted" }.count
    }
    
    private var declinedCRMCount: Int {
        currentCRMGuests.filter { normalizedInvitationStatus($0.invitationStatus) == "declined" }.count
    }
    
    private var checkedInCRMCount: Int {
        currentCRMGuests.filter { normalizedInvitationStatus($0.invitationStatus) == "checked_in" }.count
    }
    
    private var liveCRMCapacityCount: Int {
        max(currentEvent.attendeeCount, acceptedCRMCount + checkedInCRMCount)
    }
    
    private var liveCapacityPercent: Int {
        guard currentEvent.capacity > 0 else {
            return liveCRMCapacityCount > 0 ? 100 : 0
        }
        
        return min(100, Int((Double(liveCRMCapacityCount) / Double(currentEvent.capacity)) * 100.0))
    }
    
    private var operationsHealthText: String {
        if isLivePublished && checkedInCRMCount > 0 { return "Live check-in active" }
        if isLivePublished { return "Published and operational" }
        if isApproved { return "Approved, ready to publish" }
        if isSubmitted { return "Awaiting admin review" }
        if isRejected { return "Needs creator revision" }
        return "Draft operations setup"
    }
    
    private var statusText: String {
        if isLivePublished { return "PUBLISHED" }
        if isApproved { return "APPROVED" }
        return currentEvent.approvalStatus.uppercased()
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
        
        switch currentEvent.approvalStatus {
        case "submitted": return .orange
        case "rejected": return .red
        case "draft": return .white
        default: return .orange
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            eventManagementRoot(safeTop: geo.safeAreaInsets.top)
        }
    }
    
    private func eventManagementRoot(safeTop: CGFloat) -> some View {
        ZStack {
            SpaceBackground()
            eventManagementContent(safeTop: safeTop)
            toastOverlay
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarHidden(true)
        .sheet(item: $activeCommand) { command in
            commandSheetHost(command)
        }
        .onAppear {
            app.selectedEvent = currentEvent
            app.refreshEvents()
            contactsPermissionStatus = CNContactStore.authorizationStatus(for: .contacts)
            
            startLiveEventGuestsListener(for: currentEvent.id)
            startLiveEventSessionsListener(for: currentEvent.id)
        }
        .onDisappear {
            stopLiveEventGuestsListener()
            stopLiveEventSessionsListener()
        }
    }
    
    private func eventManagementContent(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            header(safeTop: safeTop)
            
            ScrollView(showsIndicators: false) {
                eventManagementSections
            }
        }
    }
    
    private var eventManagementSections: some View {
        VStack(spacing: 16) {
            heroPanel
            eventOpsCommandCenter
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
    
    private func commandSheetHost(_ command: EventCommandSheet) -> AnyView {
        AnyView(
            commandSheet(command)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .sheet(isPresented: $showNativeContactPicker) {
                    ContactPickerSheet { contacts in
                        mergePickedContactsIntoImportCandidates(contacts)
                    }
                }
                .sheet(item: $editingGuest) { guest in
                    guestEditSheetHost(guest)
                }
                .sheet(item: $editingSession) { session in
                    sessionEditSheetHost(session)
                }
        )
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
                
                Text(currentEvent.category.uppercased())
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
                
                Text(currentEvent.visibility.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48))
                    .tracking(1)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.white.opacity(0.085)))
                
                Spacer()
                
                Text(currentEvent.locationType.uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.82))
                    .tracking(1)
            }
            
            Text(currentEvent.title)
                .font(.system(size: currentEvent.title.count > 46 ? 26 : 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(currentEvent.heroLine.isEmpty ? currentEvent.summary : currentEvent.heroLine)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.66))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider().overlay(Color.white.opacity(0.08))
            
            HStack {
                statBlock(title: "CAPACITY", value: capacityText)
                statBlock(title: "REMAINING", value: remainingText)
                statBlock(title: "WAITLIST", value: currentEvent.waitlistEnabled ? "ENABLED" : "OFF")
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.orange.opacity(0.22), lineWidth: 1.2))
    }
    
    
    private var eventOpsCommandCenter: some View {
        sectionPanel(title: "EVENT OPERATIONS CENTER", subtitle: operationsHealthText) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    crmMetric("ACCEPTED", acceptedCRMCount, tint: .green)
                    crmMetric("CHECKED IN", checkedInCRMCount, tint: .green)
                }
                
                HStack(spacing: 10) {
                    crmMetric("INVITED", invitedCRMCount, tint: .orange)
                    crmMetric("WAITLIST", currentEvent.waitlistCount, tint: .orange)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CAPACITY SIGNAL")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.42))
                            .tracking(1)
                        
                        Spacer()
                        
                        Text(currentEvent.capacity > 0 ? "\(liveCRMCapacityCount)/\(currentEvent.capacity)" : "\(liveCRMCapacityCount) RSVP")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.62))
                            .tracking(0.8)
                    }
                    
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            
                            Capsule()
                                .fill(liveCapacityPercent >= 90 ? Color.orange.opacity(0.92) : Color.green.opacity(0.82))
                                .frame(width: max(8, proxy.size.width * CGFloat(liveCapacityPercent) / 100.0))
                        }
                    }
                    .frame(height: 10)
                    .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.28)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
            }
        }
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
                
                controlButton(title: currentEvent.featured ? "FEATURED" : "FEATURE", icon: "star.fill", tint: .orange) {
                    app.setEventFeatured(currentEvent, featured: !currentEvent.featured)
                }
            }
            
            HStack(spacing: 10) {
                controlButton(title: "EDIT", icon: "square.and.pencil", tint: .white) {
                    guard app.canEdit(currentEvent) else {
                        app.showEventToast("EDIT LOCKED")
                        return
                    }
                    app.selectedEvent = currentEvent
                    app.setRoute(.eventEditor)
                }
                
                controlButton(title: "PUBLIC VIEW", icon: "arrow.up.right.square.fill", tint: .white) {
                    guard isLivePublished else {
                        app.showEventToast("NOT PUBLIC YET")
                        return
                    }
                    app.selectedEvent = currentEvent
                    app.setRoute(.eventDetail)
                }
            }
        }
    }
    
    @ViewBuilder
    private var adminReviewPanel: some View {
        if app.canModerate(currentEvent) && isSubmitted {
            sectionPanel(title: "ADMIN REVIEW", subtitle: "Approve or return event to creator") {
                HStack(spacing: 10) {
                    controlButton(title: "APPROVE", icon: "checkmark.seal.fill", tint: .green) { app.approveEvent(currentEvent) }
                    controlButton(title: "REJECT", icon: "xmark.seal.fill", tint: .red) { app.rejectEvent(currentEvent) }
                }
            }
        }
    }
    
    private var primaryActionTitle: String {
        if isLivePublished { return "LIVE" }
        if isApproved { return "PUBLISH" }
        if isSubmitted { return app.canModerate(currentEvent) ? "REVIEW" : "IN REVIEW" }
        if isRejected { return "REVISE" }
        return "SUBMIT"
    }
    
    private var primaryActionIcon: String {
        if isLivePublished { return "checkmark.seal.fill" }
        if isApproved { return "paperplane.fill" }
        if isSubmitted { return app.canModerate(currentEvent) ? "checkmark.seal.fill" : "hourglass" }
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
            app.publishApprovedEvent(currentEvent)
            return
        }
        if isSubmitted {
            app.canModerate(currentEvent) ? app.approveEvent(currentEvent) : app.showEventToast("AWAITING REVIEW")
            return
        }
        if isRejected {
            app.selectedEvent = currentEvent
            app.setRoute(.eventEditor)
            return
        }
        app.submitEventForReview(currentEvent)
    }
    
    
    
    private var attendeeSnapshot: some View {
        sectionPanel(title: "ATTENDEE SNAPSHOT", subtitle: "Capacity, invites, and confirmed demand") {
            VStack(spacing: 12) {
                EventAttendeePreview(
                    attendeeCount: liveCRMCapacityCount,
                    capacity: max(1, currentEvent.capacity),
                    accent: .orange
                )

                HStack(spacing: 10) {
                    crmMetric("INVITED", invitedCRMCount, tint: .orange)
                    crmMetric("ACCEPTED", acceptedCRMCount, tint: .green)
                }

                HStack(spacing: 10) {
                    crmMetric("DECLINED", declinedCRMCount, tint: .red)
                    crmMetric("CHECKED IN", checkedInCRMCount, tint: .green)
                }
            }
        }
    }

    private func guestRow(_ guest: GuestRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                speakerOrGuestAvatar(guest)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(guest.name)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.94))
                        .lineLimit(1)
                    
                    Text("\(guest.role.rawValue.uppercased()) • \(guest.status.rawValue.uppercased()) • \(guest.source.uppercased())")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.48))
                        .tracking(0.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    
                    if !guest.email.isEmpty {
                        Text(guest.email)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 7) {
                    if guest.isVIP || guest.role == .vip {
                        Text("VIP")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.black.opacity(0.88))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(Color.orange.opacity(0.96)))
                    }
                    
                    if guest.status == .checkedIn {
                        Text("ARRIVED")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(.black.opacity(0.88))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(Color.green.opacity(0.92)))
                    }
                }
            }
            
            HStack(spacing: 8) {
                Button {
                    beginEditingGuest(guest)
                } label: {
                    guestRowActionLabel("EDIT", "square.and.pencil", tint: .orange)
                }
                .buttonStyle(.plain)
                
                Button {
                    openIndividualCommunication(for: guest)
                } label: {
                    guestRowActionLabel("MESSAGE", "envelope.fill", tint: .orange)
                }
                .buttonStyle(.plain)
                .disabled(normalizedEmail(guest.email).isEmpty)
                .opacity(normalizedEmail(guest.email).isEmpty ? 0.55 : 1)
                
                Button {
                    markGuestCheckedIn(guest)
                } label: {
                    guestRowActionLabel(guest.status == .checkedIn ? "CHECKED IN" : "CHECK IN", "checkmark.seal.fill", tint: .green)
                }
                .buttonStyle(.plain)
                .disabled(guest.status == .checkedIn || guest.status == .declined)
                .opacity((guest.status == .checkedIn || guest.status == .declined) ? 0.55 : 1)
                
                Button {
                    removeGuestRecord(guest)
                } label: {
                    guestRowActionLabel("REMOVE", "minus.circle.fill", tint: .red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(guest.name)")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.34)))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(guest.status == .checkedIn ? Color.green.opacity(0.20) : Color.white.opacity(0.065), lineWidth: 1)
        )
    }
    
    private func guestRowActionLabel(_ title: String, _ icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .black))
            
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .foregroundColor(tint.opacity(0.92))
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(tint.opacity(0.18), lineWidth: 1))
    }
    
    private func speakerOrGuestAvatar(_ guest: GuestRecord) -> some View {
        ZStack {
            Circle()
                .fill(guestTint(guest).opacity(0.13))
                .frame(width: 42, height: 42)
            
            if let urlString = guest.headshotURL,
               let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
               !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: guestIcon(guest))
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(guestTint(guest))
                    case .empty:
                        ProgressView()
                            .tint(.orange)
                            .scaleEffect(0.70)
                    @unknown default:
                        Image(systemName: guestIcon(guest))
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(guestTint(guest))
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
            } else {
                Image(systemName: guestIcon(guest))
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(guestTint(guest))
            }
        }
        .overlay(Circle().stroke(guestTint(guest).opacity(0.22), lineWidth: 1))
    }

    private func normalizedInvitationStatus(_ rawValue: String) -> String {
        let cleaned = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch cleaned {
        case "checkedin", "checked_in":
            return "checked_in"
        case "accepted", "confirmed", "rsvp", "rsvped":
            return "accepted"
        case "declined", "rejected":
            return "declined"
        case "invited", "sent":
            return "invited"
        default:
            return cleaned.isEmpty ? "staged" : cleaned
        }
    }


    private func crmGuestRecord(from guest: AppState.EventGuest) -> GuestRecord {
        var record = GuestRecord(
            id: stableCRMGuestUUID(id: guest.id, email: guest.email),
            name: guest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Guest" : guest.name,
            email: guest.email,
            organization: guest.organization,
            role: guestRole(from: guest.role),
            status: guestStatus(from: guest.invitationStatus),
            isVIP: guest.isVIP || guestRole(from: guest.role) == .vip,
            notes: guest.bio,
            source: "crm",
            createdAt: guest.createdAt ?? guest.invitedAt ?? Date()
        )

        record.bio = guest.bio
        record.headshotURL = guest.headshotURL
        record.featuredSpeaker = false

        return record
    }

    private func guestRole(from rawValue: String) -> GuestRole {
        let cleaned = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch cleaned {
        case "speaker", "keynote_speaker", "panelist":
            return .speaker
        case "moderator", "host":
            return .moderator
        case "sponsor", "partner":
            return .sponsor
        case "vip":
            return .vip
        case "staff", "volunteer":
            return .staff
        case "attendee", "guest":
            return .attendee
        default:
            return .delegate
        }
    }

    private func guestStatus(from rawValue: String) -> GuestStatus {
        switch normalizedInvitationStatus(rawValue) {
        case "invited":
            return .invited
        case "accepted":
            return .accepted
        case "declined":
            return .declined
        case "checked_in":
            return .checkedIn
        case "staged":
            return .staged
        default:
            return .manual
        }
    }

    private func statusSortRank(_ status: GuestStatus) -> Int {
        switch status {
        case .checkedIn:
            return 0
        case .accepted:
            return 1
        case .invited:
            return 2
        case .staged:
            return 3
        case .manual:
            return 4
        case .declined:
            return 5
        }
    }

    private func normalizedEmail(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func stableCRMGuestUUID(id: String, email: String) -> UUID {
        let seed = "\(id)|\(email)"
        var hex = seed.unicodeScalars
            .map { String(format: "%02x", Int($0.value) & 0xff) }
            .joined()

        if hex.count < 12 {
            hex += String(repeating: "0", count: 12 - hex.count)
        }

        let suffix = String(hex.prefix(12))
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") ?? UUID()
    }

    private func startLiveEventGuestsListener(for eventID: String) {
        let cleanedID = eventID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedID.isEmpty else { return }

        if liveEventGuestsListener != nil, liveEventGuestsEventID == cleanedID {
            return
        }

        stopLiveEventGuestsListener()
        liveEventGuestsEventID = cleanedID
        print("🧭 [EventManagementView] currentEvent.id:", currentEvent.id)
        print("🧭 [EventManagementView] listening path: events/\(cleanedID)/guests")

        liveEventGuestsListener = FirestoreService.db
            .collection("events")
            .document(cleanedID)
            .collection("guests")
            .addSnapshotListener { snapshot, error in
                if let error {

                        print("⚠️ [EventManagementView] Guest listener failed: \(error)")

                        return

                    }

                    print("🧭 [EventManagementView] guest snapshot docs:", snapshot?.documents.count ?? -1)

                    if let snapshot {

                        for doc in snapshot.documents {

                            print("🧭 [EventManagementView] guest doc:", doc.documentID, doc.data())

                        }

                    }

                let guests: [AppState.EventGuest] = snapshot?.documents.compactMap { doc in
                    let data = doc.data()

                    return AppState.EventGuest(
                        id: doc.documentID,
                        eventID: data["eventId"] as? String ?? cleanedID,
                        name: data["name"] as? String ?? "",
                        email: data["email"] as? String ?? "",
                        organization: data["organization"] as? String ?? "",
                        bio: data["bio"] as? String ?? "",
                        role: data["role"] as? String ?? "guest",
                        isVIP: data["isVIP"] as? Bool ?? false,
                        headshotURL: data["headshotURL"] as? String,
                        invitationStatus: data["invitationStatus"] as? String ?? "staged",
                        invitedAt: eventGuestDateValue(data["invitedAt"]),
                        acceptedAt: eventGuestDateValue(data["acceptedAt"]),
                        createdAt: eventGuestDateValue(data["createdAt"])
                    )
                } ?? []

                Task { @MainActor in
                    let sortedGuests = guests.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }

                    self.liveEventGuests = sortedGuests

                    print("🟢 [EventManagementView] Loaded CRM guests:", sortedGuests.count)

                    for guest in sortedGuests {
                        print(
                            "🟢 CRM Guest:",
                            guest.name,
                            "| status:",
                            guest.invitationStatus,
                            "| role:",
                            guest.role,
                            "| email:",
                            guest.email
                        )
                    }
                }
            }
    }
    private func stopLiveEventGuestsListener() {
        liveEventGuestsListener?.remove()
        liveEventGuestsListener = nil
        liveEventGuestsEventID = ""
        liveEventGuests = []
    }

    private func eventGuestDateValue(_ value: Any?) -> Date? {
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

    private func crmMetric(_ title: String, _ value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(tint.opacity(0.88))
                .tracking(1)

            Text("\(value)")
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.94))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private var operationsPanel: some View {
        sectionPanel(title: "OPERATIONS", subtitle: "Event-day command tools and live control paths") {
            HStack(spacing: 10) {
                opsTile(title: "CHECK-IN", subtitle: "\(checkedInCRMCount) arrived", icon: "qrcode.viewfinder", command: .checkIn)
                opsTile(title: "BADGES", subtitle: "Guest IDs", icon: "lanyardcard.fill", command: .badges)
            }

            HStack(spacing: 10) {
                opsTile(title: "RUN OF SHOW", subtitle: "\(sessionRecords.count) sessions", icon: "list.bullet.rectangle.fill", command: .runOfShow)
                opsTile(title: "STAFF ROLES", subtitle: "Delegated ops", icon: "person.3.fill", command: .staffRoles)
            }

            operationRow(
                title: "SESSION BUILDER",
                subtitle: "Create tracks, rooms, speakers, and featured agenda blocks",
                icon: "rectangle.3.group.fill",
                command: .sessionBuilder
            )
        }
    }

    private var wdcPanel: some View {
        sectionPanel(
            title: "PEOPLE CRM",
            subtitle: "Guest management, speakers, delegates, sponsors, and invitations"
        ) {
            operationRow(
                title: "INVITATION CENTER",
                subtitle: "\(stagedInviteCount) staged • \(invitedCRMCount) invited • \(acceptedCRMCount) accepted",
                icon: "person.crop.circle.badge.plus",
                command: .invitationCenter
            )

            operationRow(
                title: "SPEAKER MANAGEMENT",
                subtitle: "\(sessionSpeakerOptions.count) speakers/moderators available for sessions",
                icon: "person.crop.square.fill",
                command: .guestPanel
            )

            operationRow(
                title: "DELEGATE DIRECTORY",
                subtitle: "Delegates, VIPs, sponsors, moderators, and check-in status",
                icon: "person.crop.rectangle.stack.fill",
                command: .delegateDirectory
            )
        }
    }

    private var messagingPanel: some View {
        sectionPanel(title: "COMMUNICATIONS CENTER", subtitle: "Segmented event messaging, reminders, and operational notices") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    communicationMetric("ALL", communicationAudienceCount(.all), tint: .white)
                    communicationMetric("ACCEPTED", communicationAudienceCount(.accepted), tint: .green)
                }

                HStack(spacing: 10) {
                    communicationMetric("WAITLIST", communicationAudienceCount(.waitlist), tint: .orange)
                    communicationMetric("CHECKED IN", communicationAudienceCount(.checkedIn), tint: .green)
                }

                operationRow(
                    title: "SEND EVENT UPDATE",
                    subtitle: "Audience segments, templates, preview and copy workflow",
                    icon: "envelope.badge.fill",
                    command: .messageAttendees
                )

                operationRow(
                    title: "SEND REMINDER",
                    subtitle: "Timing, access, and event readiness message",
                    icon: "bell.badge.fill",
                    command: .sendReminder
                )

                operationRow(
                    title: "MESSAGE WAITLIST",
                    subtitle: "\(communicationAudienceCount(.waitlist)) waitlisted • capacity movement ready",
                    icon: "text.bubble.fill",
                    command: .messageWaitlist
                )
            }
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
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
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
            action?() ?? app.showEventToast("COMING NEXT")
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

    private func opsTile(title: String, subtitle: String, icon: String, command: EventCommandSheet) -> some View {
        Button { openCommand(command) } label: {
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
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func operationRow(title: String, subtitle: String, icon: String, command: EventCommandSheet) -> some View {
        Button { openCommand(command) } label: {
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

    private func openCommand(_ command: EventCommandSheet) {
        HapticManager.instance.impact(.light)
        SpatialAudioManager.shared.play(.uiTap)

        if isCommunicationCommand(command) {
            communicationIndividualGuest = nil
            communicationTemplate = defaultCommunicationTemplate(for: command)
            communicationAudience = defaultCommunicationAudience(for: command)
            communicationSubject = defaultCommunicationSubject(template: communicationTemplate)
            commandNotes = communicationMessageBody(template: communicationTemplate, audience: communicationAudience)
        } else {
            communicationIndividualGuest = nil
            commandNotes = defaultCommandText(for: command)
        }

        activeCommand = command

        if command == .guestPanel || command == .delegateDirectory || command == .staffRoles {
            refreshContactPermissionStatus()
        }
    }

    private func openIndividualCommunication(for guest: GuestRecord) {
        let email = normalizedEmail(guest.email)
        guard !email.isEmpty else {
            app.showEventToast("EMAIL REQUIRED")
            return
        }

        HapticManager.instance.impact(.light)
        SpatialAudioManager.shared.play(.uiTap)

        communicationIndividualGuest = guest
        communicationTemplate = .custom
        communicationAudience = .all
        communicationSubject = "Update: \(currentEvent.title)"
        commandNotes = communicationMessageBody(
            template: .custom,
            audience: .all,
            recipient: guest
        )
        activeCommand = .messageAttendees
    }

    private func commandSheet(_ command: EventCommandSheet) -> AnyView {
        let bodyContent: AnyView

        switch command {
        case .invitationCenter, .guestPanel, .delegateDirectory, .staffRoles:
            bodyContent = AnyView(guestDirectoryPanel(command))

        case .sessionBuilder:
            bodyContent = AnyView(sessionBuilderPanel)

        case .messageAttendees, .sendReminder, .messageWaitlist:
            bodyContent = AnyView(communicationsCenterPanel(command))

        default:
            bodyContent = AnyView(
                VStack(alignment: .leading, spacing: 18) {
                    commandNotesEditor(command)
                    commandPrimaryActions(command)
                }
            )
        }

        return AnyView(
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        commandSheetHeader(command)
                        commandSummaryCard(command)
                        bodyContent
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
        )
    }

    private func commandSheetHeader(_ command: EventCommandSheet) -> some View {
        HStack(spacing: 12) {
            Image(systemName: commandIcon(command))
                .font(.system(size: 18, weight: .black))
                .foregroundColor(.orange.opacity(0.96))
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.orange.opacity(0.13)))

            VStack(alignment: .leading, spacing: 4) {
                Text(commandTitle(command))
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(1)

                Text(currentEvent.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.50))
                    .lineLimit(2)
            }

            Spacer()

            Button { activeCommand = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.white.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.09)))
            }
            .buttonStyle(.plain)
        }
    }

    private func commandSummaryCard(_ command: EventCommandSheet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(commandSubtitle(command))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                commandMetric("RSVP", "\(currentEvent.attendeeCount)")
                commandMetric("LEFT", currentEvent.capacity > 0 ? "\(max(0, currentEvent.capacity - currentEvent.attendeeCount))" : "OPEN")
                commandMetric("WAIT", "\(currentEvent.waitlistCount)")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.085)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.orange.opacity(0.14), lineWidth: 1))
    }

    private func commandMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.82))
                .tracking(1)

            Text(value)
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.38)))
    }

    private func guestDirectoryPanel(_ command: EventCommandSheet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            guestQuickStats
            invitePipelinePanel
            contactsImportPanel
            guestInputPanel(command)
            guestFilterRow
            guestListPanel
            guestExportActions
        }
    }

    private var guestQuickStats: some View {
        let records = directoryGuestRecords

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                commandMetric("PEOPLE", "\(records.count)")
                commandMetric("ACCEPTED", "\(records.filter { $0.status == .accepted || $0.status == .checkedIn }.count)")
                commandMetric("CHECK-IN", "\(records.filter { $0.status == .checkedIn }.count)")
            }

            HStack(spacing: 10) {
                commandMetric("STAGED", "\(stagedInviteCount)")
                commandMetric("SPEAKERS", "\(records.filter { $0.role == .speaker || $0.role == .moderator }.count)")
                commandMetric("VIP", "\(records.filter { $0.isVIP || $0.role == .vip }.count)")
            }
        }
    }

    private var invitePipelinePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("INVITE PIPELINE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                Spacer()

                Text("\(stagedInviteCount) STAGED")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(stagedInviteCount > 0 ? .black.opacity(0.88) : .white.opacity(0.50))
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(stagedInviteCount > 0 ? Color.orange.opacity(0.96) : Color.white.opacity(0.08)))
            }

            Text("Import contacts in multiple passes, add/remove people as needed, assign roles, stage invitations, then send through the backend invite flow.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                pipelineStep("IMPORT", importedContacts.isEmpty == false)
                pipelineStep("ROLE", true)
                pipelineStep("STAGE", stagedInviteCount > 0)
                pipelineStep("SEND", false)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.orange.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.orange.opacity(0.14), lineWidth: 1))
    }

    private func pipelineStep(_ title: String, _ complete: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9, weight: .black))

            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(0.6)
        }
        .foregroundColor(complete ? .green.opacity(0.92) : .white.opacity(0.42))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(complete ? Color.green.opacity(0.10) : Color.white.opacity(0.045)))
    }

    private var contactsImportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("IMPORT FROM CONTACTS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                Spacer()

                Text(contactPermissionLabel)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(contactPermissionColor)
                    .tracking(0.8)
            }

            HStack(spacing: 10) {
                pickerShell(title: "ASSIGN ROLE") {
                    Picker("", selection: $contactImportRole) {
                        ForEach(GuestRole.allCases) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.orange)
                }

                Toggle(isOn: $contactImportVIP) {
                    Text("VIP")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.72))
                }
                .tint(.orange)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.085)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
            }

            HStack(spacing: 10) {
                Button { presentNativeContactPicker() } label: {
                    commandActionLabel("IMPORT", "person.crop.circle.badge.plus", filled: false)
                }
                .buttonStyle(.plain)

                Button { stageSelectedContactsAsInvites() } label: {
                    commandActionLabel(selectedContactIDs.isEmpty ? "SELECT" : "STAGE", "paperplane.fill", filled: true)
                }
                .buttonStyle(.plain)
                .disabled(selectedContactIDs.isEmpty)
                .opacity(selectedContactIDs.isEmpty ? 0.55 : 1)
            }

            if contactsPermissionStatus == .denied || contactsPermissionStatus == .restricted {
                Text("Contacts permission is blocked. Enable Contacts access in iOS Settings to import invitees.")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.red.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !importedContacts.isEmpty {
                premiumTextField("Search contacts", text: $contactSearchText)

                HStack {
                    Text("\(selectedContactIDs.count) SELECTED")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.86))
                        .tracking(1)

                    Spacer()

                    Button {
                        let selectableIDs = Set(selectableDisplayedContacts.map(\.id))

                        if !selectableIDs.isEmpty && selectableIDs.isSubset(of: selectedContactIDs) {
                            selectedContactIDs.subtract(selectableIDs)
                        } else {
                            selectedContactIDs.formUnion(selectableIDs)
                        }
                    } label: {
                        let selectableIDs = Set(selectableDisplayedContacts.map(\.id))
                        let allDisplayedSelected = !selectableIDs.isEmpty && selectableIDs.isSubset(of: selectedContactIDs)

                        Text(allDisplayedSelected ? "CLEAR SHOWN" : "SELECT SHOWN")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.white.opacity(0.72))
                            .tracking(0.8)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    ForEach(displayedContacts) { contact in
                        contactImportRow(contact)
                    }
                }

                if filteredContacts.count > displayedContacts.count {
                    Text("Showing first \(displayedContacts.count) matches. Search to narrow the list, stage selected people, or tap Import More Contacts again to add another batch from iOS Contacts.")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func contactImportRow(_ contact: ContactCandidate) -> some View {
        Button {
            handleContactImportTap(contact)
        } label: {
            contactImportRowContent(contact)
        }
        .buttonStyle(.plain)
    }

    private func handleContactImportTap(_ contact: ContactCandidate) {
        let alreadyAdded = isContactAlreadyInDirectory(contact)
        let selected = selectedContactIDs.contains(contact.id)
        let canSelect = !contact.email.isEmpty && !alreadyAdded

        if alreadyAdded {
            app.showEventToast("ALREADY IN QUEUE")
            return
        }

        if selected {
            selectedContactIDs.remove(contact.id)
            return
        }

        if canSelect {
            selectedContactIDs.insert(contact.id)
        } else {
            app.showEventToast("EMAIL REQUIRED")
        }
    }

    private func contactImportRowContent(_ contact: ContactCandidate) -> some View {
        let selected = selectedContactIDs.contains(contact.id)
        let alreadyAdded = isContactAlreadyInDirectory(contact)
        let canSelect = !contact.email.isEmpty && !alreadyAdded
        let iconName = contactImportIconName(selected: selected, alreadyAdded: alreadyAdded)
        let iconColor = contactImportIconColor(selected: selected, alreadyAdded: alreadyAdded)
        let nameOpacity = canSelect || alreadyAdded ? 0.90 : 0.45
        let rowFill = contactImportRowFill(selected: selected, alreadyAdded: alreadyAdded)
        let rowStroke = contactImportRowStroke(selected: selected, alreadyAdded: alreadyAdded)

        return HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .black))
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(nameOpacity))
                    .lineLimit(1)

                Text(contact.displayEmail)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(contact.email.isEmpty ? Color.red.opacity(0.62) : Color.white.opacity(0.44))
                    .lineLimit(1)
            }

            Spacer()

            contactImportTrailingBadge(contact, alreadyAdded: alreadyAdded)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(rowStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func contactImportTrailingBadge(
        _ contact: ContactCandidate,
        alreadyAdded: Bool
    ) -> some View {
        if alreadyAdded {
            Text("ADDED")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.black.opacity(0.86))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.orange.opacity(0.92)))
        } else if !contact.organization.isEmpty {
            Text(contact.organization.uppercased())
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.36))
                .lineLimit(1)
        }
    }

    private func contactImportIconName(
        selected: Bool,
        alreadyAdded: Bool
    ) -> String {
        if alreadyAdded { return "checkmark.seal.fill" }
        if selected { return "checkmark.circle.fill" }
        return "circle"
    }

    private func contactImportIconColor(
        selected: Bool,
        alreadyAdded: Bool
    ) -> Color {
        if alreadyAdded { return Color.orange.opacity(0.88) }
        if selected { return Color.green.opacity(0.94) }
        return Color.white.opacity(0.30)
    }

    private func contactImportRowFill(
        selected: Bool,
        alreadyAdded: Bool
    ) -> Color {
        if alreadyAdded { return Color.orange.opacity(0.07) }
        if selected { return Color.green.opacity(0.09) }
        return Color.black.opacity(0.30)
    }

    private func contactImportRowStroke(
        selected: Bool,
        alreadyAdded: Bool
    ) -> Color {
        if alreadyAdded { return Color.orange.opacity(0.18) }
        if selected { return Color.green.opacity(0.20) }
        return Color.white.opacity(0.06)
    }

    private func guestInputPanel(_ command: EventCommandSheet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADD PERSON MANUALLY")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            premiumTextField("Name", text: $guestName)
            premiumTextField("Email", text: $guestEmail)
            premiumTextField("Organization / Company", text: $guestOrganization)

            HStack(spacing: 10) {
                pickerShell(title: "ROLE") {
                    Picker("", selection: $guestRole) {
                        ForEach(GuestRole.allCases) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.orange)
                }

                pickerShell(title: "STATUS") {
                    Picker("", selection: $guestStatus) {
                        ForEach(GuestStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.orange)
                }
            }

            Toggle(isOn: $guestIsVIP) {
                Text("VIP / PRIORITY GUEST")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.76))
                    .tracking(1)
            }
            .tint(.orange)

            TextEditor(text: $guestNotes)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.98))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 88)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.085)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))

            HStack(spacing: 10) {
                Button { addGuestRecord(asInvite: false) } label: {
                    commandActionLabel("ADD MANUAL", "person.badge.plus", filled: false)
                }
                .buttonStyle(.plain)

                Button { addGuestRecord(asInvite: true) } label: {
                    commandActionLabel("STAGE INVITE", "paperplane.fill", filled: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func premiumTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(.white.opacity(0.62)))
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(.white.opacity(0.98))
            .tint(.orange)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1.15)
            )
            .shadow(color: .black.opacity(0.20), radius: 10, x: 0, y: 5)
    }

    private func pickerShell<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.82))
                .tracking(1)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.085)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private var guestFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GuestFilter.allCases) { filter in
                    Button { guestFilter = filter } label: {
                        Text(filter.rawValue.uppercased())
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(guestFilter == filter ? .black.opacity(0.9) : .white.opacity(0.62))
                            .tracking(0.8)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Capsule().fill(guestFilter == filter ? Color.orange.opacity(0.96) : Color.white.opacity(0.075)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var guestListPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DIRECTORY")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            if filteredGuests.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(.orange.opacity(0.72))

                    Text("NO PEOPLE IN THIS VIEW")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.70))
                        .tracking(1)

                    Text("Import contacts, stage invitees, or add a manual guest.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.44))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredGuests) { guest in
                        guestRow(guest)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func beginEditingGuest(_ guest: GuestRecord) {
        editGuestName = guest.name
        editGuestEmail = guest.email
        editGuestOrganization = guest.organization
        editGuestNotes = guest.notes
        editGuestRole = guest.role
        editGuestStatus = guest.status
        editGuestIsVIP = guest.isVIP || guest.role == .vip
        editingGuest = guest
        editGuestBio = guest.bio
        editGuestHeadshotURL = guest.headshotURL ?? ""
        editGuestFeaturedSpeaker = guest.featuredSpeaker
    }

    private func guestEditSheetHost(_ guest: GuestRecord) -> AnyView {
        AnyView(
            guestEditSheet(guest)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        )
    }

    private func guestEditSheet(_ guest: GuestRecord) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    guestEditHeader(guest)
                    guestEditSummary(guest)
                    guestEditForm
                    speakerProfileEditor
                    guestEditActions(guest)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
        }
    }

    private func guestEditHeader(_ guest: GuestRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: guestIcon(guest))
                .font(.system(size: 18, weight: .black))
                .foregroundColor(.orange.opacity(0.96))
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.orange.opacity(0.13)))

            VStack(alignment: .leading, spacing: 4) {
                Text("EDIT PERSON")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(1)

                Text(currentEvent.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.50))
                    .lineLimit(2)
            }

            Spacer()

            Button { editingGuest = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(.white.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.09)))
            }
            .buttonStyle(.plain)
        }
    }

    private var speakerProfileEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPEAKER PROFILE")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            premiumTextField("Headshot URL", text: $editGuestHeadshotURL)

            Toggle(isOn: $editGuestFeaturedSpeaker) {
                Text("FEATURED SPEAKER")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.76))
                    .tracking(1)
            }
            .tint(.orange)

            TextEditor(text: $editGuestBio)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.98))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.085)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.orange.opacity(0.12), lineWidth: 1))
    }
    
    private func guestEditSummary(_ guest: GuestRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep roles, status, VIP priority, and notes editable after invitation so event admins can correct speaker/delegate assignments without removing the person.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                commandMetric("ROLE", editGuestRole.rawValue.uppercased())
                commandMetric("STATUS", editGuestStatus.rawValue.uppercased())
                commandMetric("VIP", editGuestIsVIP ? "YES" : "NO")
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.085)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.orange.opacity(0.14), lineWidth: 1))
    }

    private var guestEditForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROFILE & ROLE")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            premiumTextField("Name", text: $editGuestName)
            premiumTextField("Email", text: $editGuestEmail)
            premiumTextField("Organization / Company", text: $editGuestOrganization)

            HStack(spacing: 10) {
                pickerShell(title: "ROLE") {
                    Picker("", selection: $editGuestRole) {
                        ForEach(GuestRole.allCases) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.orange)
                }

                pickerShell(title: "STATUS") {
                    Picker("", selection: $editGuestStatus) {
                        ForEach(GuestStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.orange)
                }
            }

            Toggle(isOn: $editGuestIsVIP) {
                Text("VIP / PRIORITY GUEST")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.76))
                    .tracking(1)
            }
            .tint(.orange)

            TextEditor(text: $editGuestNotes)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.98))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.085)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func guestEditActions(_ guest: GuestRecord) -> some View {
        VStack(spacing: 10) {
            Button { saveGuestEdits(guest) } label: {
                commandActionLabel("SAVE PERSON", "checkmark.seal.fill", filled: true)
            }
            .buttonStyle(.plain)

            Button {
                removeGuestRecord(guest)
                editingGuest = nil
            } label: {
                commandActionLabel("REMOVE FROM EVENT", "trash.fill", filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func saveGuestEdits(_ guest: GuestRecord) {
        let name = editGuestName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = editGuestEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let organization = editGuestOrganization.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = editGuestNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let bio = editGuestBio.trimmingCharacters(in: .whitespacesAndNewlines)
        let headshotURL = editGuestHeadshotURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            app.showEventToast("NAME REQUIRED")
            return
        }

        if (editGuestStatus == .staged || editGuestStatus == .invited) && email.isEmpty {
            app.showEventToast("EMAIL REQUIRED")
            return
        }

        var updated = guest
        updated.name = name
        updated.email = email
        updated.organization = organization
        updated.notes = notes
        updated.role = editGuestRole
        updated.status = editGuestStatus
        updated.isVIP = editGuestIsVIP || editGuestRole == .vip
        updated.bio = bio
        updated.headshotURL = headshotURL.isEmpty ? nil : headshotURL
        updated.featuredSpeaker = editGuestFeaturedSpeaker

        if let index = guestRecords.firstIndex(where: { $0.id == guest.id }) {
            guestRecords[index] = updated
        }

        let eventID = currentEvent.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventID.isEmpty else {
            app.showEventToast("EVENT NOT FOUND")
            return
        }

        let matchingCRMGuest = liveEventGuests.first {
            normalizedEmail($0.email) == normalizedEmail(guest.email)
        }

        guard let crmGuest = matchingCRMGuest else {
            app.showEventToast("CRM GUEST NOT FOUND")
            return
        }

        var payload: [String: Any] = [
            "name": name,
            "email": email,
            "organization": organization,
            "notes": notes,
            "bio": bio,
            "role": editGuestRole.backendValue,
            "isVIP": updated.isVIP,
            "featuredSpeaker": editGuestFeaturedSpeaker,
            "invitationStatus": editGuestStatus.backendValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if headshotURL.isEmpty {
            payload["headshotURL"] = FieldValue.delete()
        } else {
            payload["headshotURL"] = headshotURL
        }

        FirestoreService.db
            .collection("events")
            .document(eventID)
            .collection("guests")
            .document(crmGuest.id)
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    if let error {
                        print("⚠️ [EventManagementView] Save CRM guest failed:", error)
                        self.app.showEventToast("SAVE FAILED")
                        return
                    }

                    self.editingGuest = nil
                    self.app.showEventToast("PERSON SAVED")
                }
            }
    }

    private func markGuestCheckedIn(_ guest: GuestRecord) {
        guard guest.status != .checkedIn else {
            app.showEventToast("ALREADY CHECKED IN")
            return
        }

        let eventID = currentEvent.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventID.isEmpty else {
            app.showEventToast("EVENT NOT FOUND")
            return
        }

        let matchingCRMGuest = currentCRMGuests.first {
            normalizedEmail($0.email) == normalizedEmail(guest.email)
        }

        if let index = guestRecords.firstIndex(where: { $0.id == guest.id }) {
            var updated = guestRecords[index]
            updated.status = .checkedIn
            guestRecords[index] = updated
        }

        guard let crmGuest = matchingCRMGuest else {
            app.showEventToast("LOCAL CHECK-IN")
            return
        }

        FirestoreService.db
            .collection("events")
            .document(eventID)
            .collection("guests")
            .document(crmGuest.id)
            .setData([
                "invitationStatus": GuestStatus.checkedIn.backendValue,
                "checkedInAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true) { error in
                DispatchQueue.main.async {
                    if let error {
                        print("⚠️ [EventManagementView] Check-in failed:", error)
                        self.app.showEventToast("CHECK-IN FAILED")
                        return
                    }

                    self.app.showEventToast("GUEST CHECKED IN")
                }
            }
    }


    private var guestExportActions: some View {
        VStack(spacing: 10) {
            Button { sendStagedInvitations() } label: {
                commandActionLabel(
                    isSendingStagedInvitations ? "SENDING INVITES" : "SEND STAGED INVITES",
                    "paperplane.fill",
                    filled: true
                )
            }
            .buttonStyle(.plain)
            .disabled(stagedInviteCount == 0 || isSendingStagedInvitations)
            .opacity((stagedInviteCount == 0 || isSendingStagedInvitations) ? 0.55 : 1)

            Button {
                UIPasteboard.general.string = guestDirectoryExport()
                app.showEventToast("DIRECTORY COPIED")
                activeCommand = nil
            } label: {
                commandActionLabel("COPY DIRECTORY", "doc.on.doc.fill", filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func addGuestRecord(asInvite: Bool) {
        let name = guestName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = guestEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let organization = guestOrganization.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = guestNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            app.showEventToast("NAME REQUIRED")
            return
        }

        if asInvite && email.isEmpty {
            app.showEventToast("EMAIL REQUIRED")
            return
        }

        upsertGuestRecord(
            GuestRecord(
                name: name,
                email: email,
                organization: organization,
                role: guestRole,
                status: asInvite ? .staged : guestStatus,
                isVIP: guestIsVIP || guestRole == .vip,
                notes: notes,
                source: asInvite ? "manual invite" : "manual"
            )
        )

        guestName = ""
        guestEmail = ""
        guestOrganization = ""
        guestNotes = ""
        guestRole = .delegate
        guestStatus = .manual
        guestIsVIP = false

        app.showEventToast(asInvite ? "INVITE STAGED" : "GUEST ADDED")
    }

    private func upsertGuestRecord(_ record: GuestRecord) {
        let normalizedEmail = record.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !normalizedEmail.isEmpty,
           let existingIndex = guestRecords.firstIndex(where: { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedEmail }) {
            var updated = record
            let existing = guestRecords[existingIndex]

            if existing.status == .invited || existing.status == .accepted || existing.status == .checkedIn {
                updated.status = existing.status
            }

            if !existing.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               existing.notes != updated.notes {
                updated.notes = [existing.notes, updated.notes]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")
            }

            guestRecords[existingIndex] = updated
            return
        }

        guestRecords.insert(record, at: 0)
    }

    private func removeGuestRecord(_ guest: GuestRecord) {
        guestRecords.removeAll { $0.id == guest.id }

        if !guest.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let removedEmail = guest.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            selectedContactIDs = Set(
                selectedContactIDs.filter { selectedID in
                    !selectedID.lowercased().contains(removedEmail)
                }
            )
        }

        app.showEventToast("REMOVED")
    }

    private func isContactAlreadyInDirectory(_ contact: ContactCandidate) -> Bool {
        let email = normalizedEmail(contact.email)
        guard !email.isEmpty else { return false }

        return directoryGuestRecords.contains {
            normalizedEmail($0.email) == email
        }
    }

    private func stageSelectedContactsAsInvites() {
        let selected = importedContacts.filter {
            selectedContactIDs.contains($0.id) && !isContactAlreadyInDirectory($0)
        }

        guard !selected.isEmpty else {
            app.showEventToast("SELECT CONTACTS")
            return
        }

        var stagedCount = 0

        for contact in selected where !contact.email.isEmpty {
            upsertGuestRecord(
                GuestRecord(
                    name: contact.name,
                    email: contact.email,
                    organization: contact.organization,
                    role: contactImportRole,
                    status: .staged,
                    isVIP: contactImportVIP || contactImportRole == .vip,
                    notes: "Imported from Contacts. Role assigned by event admin.",
                    source: "contacts"
                )
            )
            stagedCount += 1
        }

        selectedContactIDs.removeAll()

        app.showEventToast(stagedCount == 1 ? "1 INVITE STAGED" : "\(stagedCount) INVITES STAGED")
    }

    private func sendStagedInvitations() {
        let staged = guestRecords.filter { $0.status == .staged && !$0.email.isEmpty }

        guard !staged.isEmpty else {
            app.showEventToast("NO STAGED INVITES")
            return
        }

        let eventID = currentEvent.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventID.isEmpty else {
            app.showEventToast("EVENT NOT FOUND")
            return
        }

        guard !isSendingStagedInvitations else { return }

        isSendingStagedInvitations = true

        let stagedIDs = Set(staged.map(\.id))
        let invitees: [[String: Any]] = staged.map { record in
            [
                "name": record.name.trimmingCharacters(in: .whitespacesAndNewlines),
                "email": record.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                "role": record.role.rawValue,
                "organization": record.organization.trimmingCharacters(in: .whitespacesAndNewlines),
                "notes": record.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                "isVIP": record.isVIP || record.role == .vip,
                "source": record.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "manual" : record.source
            ]
        }

        let payload: [String: Any] = [
            "eventId": eventID,
            "invitees": invitees
        ]

        let callable = Functions.functions(region: "us-central1")
            .httpsCallable("sendEventInvitations")

        callable.call(payload) { result, error in
            DispatchQueue.main.async {
                self.isSendingStagedInvitations = false

                if let error {
                    print("⚠️ sendEventInvitations failed: \(error)")
                    self.app.showEventToast("INVITE SEND FAILED")
                    return
                }

                let data = result?.data as? [String: Any]
                let sentCount = data?["sentCount"] as? Int ?? staged.count

                self.guestRecords = self.guestRecords.map { record in
                    guard stagedIDs.contains(record.id) else { return record }

                    var updated = record
                    updated.status = .invited

                    let sentNote = "Invitation sent via Event CRM."
                    if updated.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        updated.notes = sentNote
                    } else if !updated.notes.contains(sentNote) {
                        updated.notes = "\(updated.notes)\n\(sentNote)"
                    }

                    return updated
                }

                self.app.refreshEvents()
                self.app.showEventToast(sentCount == 1 ? "1 INVITE SENT" : "\(sentCount) INVITES SENT")
            }
        }
    }
    private func presentNativeContactPicker() {
        refreshContactPermissionStatus()
        showNativeContactPicker = true
    }

    private func mergePickedContactsIntoImportCandidates(_ contacts: [CNContact]) {
        guard !contacts.isEmpty else { return }

        var nextCandidates = importedContacts
        var nextSelectedIDs = selectedContactIDs
        var addedCount = 0

        for contact in contacts {
            let candidates = makeContactCandidates(from: contact)

            for candidate in candidates {
                guard !candidate.email.isEmpty else { continue }

                if !nextCandidates.contains(where: { $0.id == candidate.id }) {
                    nextCandidates.append(candidate)
                    addedCount += 1
                }

                if !isContactAlreadyInDirectory(candidate) {
                    nextSelectedIDs.insert(candidate.id)
                }
            }
        }

        importedContacts = nextCandidates.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        selectedContactIDs = nextSelectedIDs
        contactSearchText = ""
        refreshContactPermissionStatus()

        if addedCount == 0 {
            app.showEventToast("CONTACTS ALREADY LOADED")
        } else if addedCount == 1 {
            app.showEventToast("1 CONTACT ADDED")
        } else {
            app.showEventToast("\(addedCount) CONTACTS ADDED")
        }
    }

    private func makeContactCandidates(from contact: CNContact) -> [ContactCandidate] {
        let name = [contact.givenName, contact.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.isEmpty ? organization : name

        if contact.emailAddresses.isEmpty {
            let fallbackName = resolvedName.isEmpty ? "Unnamed Contact" : resolvedName
            return [
                ContactCandidate(
                    id: contact.identifier,
                    name: fallbackName,
                    email: "",
                    organization: organization
                )
            ]
        }

        return contact.emailAddresses.compactMap { emailValue in
            let email = String(emailValue.value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !email.isEmpty else { return nil }

            return ContactCandidate(
                id: "\(contact.identifier)|\(email.lowercased())",
                name: resolvedName.isEmpty ? email : resolvedName,
                email: email,
                organization: organization
            )
        }
    }

    private func requestContactsAndLoad() {
        refreshContactPermissionStatus()

        switch contactsPermissionStatus {
        case .authorized, .limited:
            loadContacts()
        case .notDetermined:
            isLoadingContacts = true
            contactStore.requestAccess(for: .contacts) { granted, _ in
                DispatchQueue.main.async {
                    self.contactsPermissionStatus = CNContactStore.authorizationStatus(for: .contacts)
                    self.isLoadingContacts = false

                    if granted {
                        self.loadContacts()
                    } else {
                        self.app.showEventToast("CONTACTS DENIED")
                    }
                }
            }
        case .denied, .restricted:
            app.showEventToast("CONTACTS BLOCKED")
        @unknown default:
            app.showEventToast("CONTACTS UNAVAILABLE")
        }
    }

    private func loadContacts() {
        isLoadingContacts = true

        DispatchQueue.global(qos: .userInitiated).async {
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor
            ]

            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault

            var candidates: [ContactCandidate] = []

            do {
                try contactStore.enumerateContacts(with: request) { contact, _ in
                    let name = [contact.givenName, contact.familyName]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")

                    let resolvedName = name.isEmpty
                    ? contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
                    : name

                    let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)

                    if contact.emailAddresses.isEmpty {
                        if !resolvedName.isEmpty {
                            candidates.append(ContactCandidate(id: contact.identifier, name: resolvedName, email: "", organization: organization))
                        }
                    } else {
                        for emailValue in contact.emailAddresses {
                            let email = String(emailValue.value).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !email.isEmpty else { continue }
                            candidates.append(ContactCandidate(id: "\(contact.identifier)|\(email.lowercased())", name: resolvedName.isEmpty ? email : resolvedName, email: email, organization: organization))
                        }
                    }
                }

                let sorted = candidates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                DispatchQueue.main.async {
                    self.importedContacts = sorted
                    self.selectedContactIDs = self.selectedContactIDs.filter { selectedID in
                        sorted.contains { $0.id == selectedID && !self.isContactAlreadyInDirectory($0) }
                    }
                    self.isLoadingContacts = false
                    self.app.showEventToast(sorted.isEmpty ? "NO CONTACTS FOUND" : "\(sorted.count) CONTACTS LOADED")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoadingContacts = false
                    self.app.showEventToast("CONTACT LOAD FAILED")
                    print("⚠️ Contacts import failed:", error.localizedDescription)
                }
            }
        }
    }

    private func refreshContactPermissionStatus() {
        contactsPermissionStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    private var contactPermissionLabel: String {
        switch contactsPermissionStatus {
        case .authorized: return "READY"
        case .limited: return "LIMITED"
        case .notDetermined: return "ASK"
        case .denied, .restricted: return "BLOCKED"
        @unknown default: return "UNKNOWN"
        }
    }

    private var contactPermissionColor: Color {
        switch contactsPermissionStatus {
        case .authorized, .limited: return .green.opacity(0.92)
        case .notDetermined: return .orange.opacity(0.92)
        case .denied, .restricted: return .red.opacity(0.92)
        @unknown default: return .white.opacity(0.54)
        }
    }

    private func guestIcon(_ guest: GuestRecord) -> String {
        if guest.status == .checkedIn { return "checkmark.seal.fill" }
        if guest.status == .staged { return "tray.and.arrow.up.fill" }
        if guest.status == .invited { return "paperplane.fill" }
        if guest.role == .speaker { return "mic.fill" }
        if guest.role == .sponsor { return "star.circle.fill" }
        if guest.role == .staff { return "person.3.fill" }
        return "person.fill"
    }

    private func guestTint(_ guest: GuestRecord) -> Color {
        if guest.status == .checkedIn || guest.status == .accepted { return .green }
        if guest.status == .declined { return .red }
        return .orange
    }


    // MARK: - Session Builder

    private var sessionSpeakerOptions: [AppState.EventGuest] {
        currentCRMGuests.filter { guest in
            let role = guest.role
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")

            return role == "speaker" || role == "moderator" || role == "panelist" || role == "host"
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var sortedSessionRecords: [EventSession] {
        sessionRecords.sorted { lhs, rhs in
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            if lhs.featured != rhs.featured { return lhs.featured && !rhs.featured }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var sessionBuilderPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            sessionQuickStats
            sessionCreatePanel
            sessionListPanel
        }
    }

    private var sessionQuickStats: some View {
        let featuredCount = sessionRecords.filter { $0.featured }.count
        let roomsCount = Set(sessionRecords.map { $0.room.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }).count
        let tracksCount = Set(sessionRecords.map { $0.track.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }).count

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                commandMetric("SESSIONS", "\(sessionRecords.count)")
                commandMetric("FEATURED", "\(featuredCount)")
                commandMetric("SPEAKERS", "\(sessionSpeakerOptions.count)")
            }

            HStack(spacing: 10) {
                commandMetric("ROOMS", "\(roomsCount)")
                commandMetric("TRACKS", "\(tracksCount)")
                commandMetric("STATUS", sessionRecords.isEmpty ? "DRAFT" : "LIVE")
            }
        }
    }

    private var sessionCreatePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CREATE SESSION")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            premiumTextField("Session title", text: $sessionTitle)

            TextEditor(text: $sessionDescription)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.98))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1.1))

            premiumTextField("Room", text: $sessionRoom)
            premiumTextField("Track", text: $sessionTrack)

            VStack(alignment: .leading, spacing: 10) {
                sessionDatePickerCard(title: "START", selection: $sessionStartsAt)
                sessionDatePickerCard(title: "END", selection: $sessionEndsAt)
            }

            premiumTextField("Capacity", text: $sessionCapacityText)
                .keyboardType(.numberPad)

            sessionFeaturedToggle(isOn: $sessionFeatured)

            sessionSpeakerPicker(selectedIDs: $selectedSessionSpeakerIDs)

            Button { saveNewSession() } label: {
                commandActionLabel(isSavingSession ? "SAVING SESSION" : "CREATE SESSION", "plus.circle.fill", filled: true)
            }
            .buttonStyle(.plain)
            .disabled(isSavingSession)
            .opacity(isSavingSession ? 0.55 : 1)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.orange.opacity(0.12), lineWidth: 1))
    }

    private var sessionListPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SESSION AGENDA")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                Spacer()

                Text("\(sessionRecords.count) TOTAL")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.46))
            }

            if sortedSessionRecords.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.3.group.fill")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(.orange.opacity(0.72))

                    Text("NO SESSIONS YET")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.72))
                        .tracking(1)

                    Text("Create a keynote, panel, workshop, networking block, or event segment.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.44))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(sortedSessionRecords) { session in
                        sessionRow(session)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private func sessionRow(_ session: EventSession) -> some View {
        Button { beginEditingSession(session) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text(sessionTime(session.startsAt))
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.92))
                    Text(sessionTime(session.endsAt))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.40))
                }
                .frame(width: 54, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(session.title.isEmpty ? "Untitled Session" : session.title)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(2)

                        if session.featured {
                            Text("FEATURED")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundColor(.black.opacity(0.88))
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                                .background(Capsule().fill(Color.orange.opacity(0.96)))
                        }
                    }

                    Text("\(session.track.uppercased()) • \(session.room.uppercased())")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.46))
                        .tracking(0.6)
                        .lineLimit(1)

                    if !sessionSpeakerNames(for: session).isEmpty {
                        Text(sessionSpeakerNames(for: session))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange.opacity(0.70))
                            .lineLimit(2)
                    }

                    if !session.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(session.description)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.48))
                            .lineLimit(3)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white.opacity(0.26))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.black.opacity(0.34)))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white.opacity(0.055), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    
    private func sessionDatePickerCard(
        title: String,
        selection: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(1.1)

            DatePicker("", selection: selection, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(.orange)
                .colorScheme(.dark)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.13), lineWidth: 1))
    }

    private func sessionFeaturedToggle(isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text("FEATURED SESSION")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.76))
                .tracking(1)
        }
        .tint(.orange)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.085)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

private func sessionSpeakerPicker(selectedIDs: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ASSIGN SPEAKERS")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.82))
                .tracking(1)

            sessionSpeakerPickerContent(selectedIDs: selectedIDs)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func sessionSpeakerPickerContent(selectedIDs: Binding<Set<String>>) -> some View {
        if sessionSpeakerOptions.isEmpty {
            sessionSpeakerEmptyState
        } else {
            VStack(spacing: 8) {
                ForEach(sessionSpeakerOptions) { speaker in
                    sessionSpeakerPickerRow(speaker: speaker, selectedIDs: selectedIDs)
                }
            }
        }
    }

    private var sessionSpeakerEmptyState: some View {
        Text("No accepted speakers or moderators yet. Add speakers in Speaker Management first.")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.42))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sessionSpeakerPickerRow(
        speaker: AppState.EventGuest,
        selectedIDs: Binding<Set<String>>
    ) -> some View {
        let isSelected = selectedIDs.wrappedValue.contains(speaker.id)

        return Button {
            toggleSessionSpeaker(speaker.id, selectedIDs: selectedIDs)
        } label: {
            sessionSpeakerPickerRowContent(speaker: speaker, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func sessionSpeakerPickerRowContent(
        speaker: AppState.EventGuest,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .black))
                .foregroundColor(isSelected ? .green.opacity(0.94) : .white.opacity(0.32))

            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.name.isEmpty ? "Speaker" : speaker.name)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.98))

                Text(speaker.role.uppercased())
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.40))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(sessionSpeakerRowBackground(isSelected: isSelected))
        .overlay(sessionSpeakerRowStroke(isSelected: isSelected))
    }

    private func sessionSpeakerRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isSelected ? Color.green.opacity(0.09) : Color.black.opacity(0.28))
    }

    private func sessionSpeakerRowStroke(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(isSelected ? Color.green.opacity(0.18) : Color.white.opacity(0.06), lineWidth: 1)
    }

    private func toggleSessionSpeaker(
        _ speakerID: String,
        selectedIDs: Binding<Set<String>>
    ) {
        if selectedIDs.wrappedValue.contains(speakerID) {
            selectedIDs.wrappedValue.remove(speakerID)
        } else {
            selectedIDs.wrappedValue.insert(speakerID)
        }
    }

    private func beginEditingSession(_ session: EventSession) {
        editSessionTitle = session.title
        editSessionDescription = session.description
        editSessionRoom = session.room
        editSessionTrack = session.track
        editSessionStartsAt = session.startsAt
        editSessionEndsAt = session.endsAt
        editSessionCapacityText = session.capacity > 0 ? "\(session.capacity)" : ""
        editSessionFeatured = session.featured
        editSessionStatus = session.status
        editSessionSpeakerIDs = Set(session.speakerIDs)
        editingSession = session
    }

    private func sessionEditSheetHost(_ session: EventSession) -> AnyView {
        AnyView(
            sessionEditSheet(session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        )
    }

    private func sessionEditSheet(_ session: EventSession) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.3.group.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(.orange.opacity(0.96))
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Color.orange.opacity(0.13)))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("EDIT SESSION")
                                .font(.system(size: 15, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                                .tracking(1)

                            Text(currentEvent.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.50))
                                .lineLimit(2)
                        }

                        Spacer()

                        Button { editingSession = nil } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(.white.opacity(0.78))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Color.white.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("SESSION DETAILS")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.92))
                            .tracking(2)

                        premiumTextField("Session title", text: $editSessionTitle)

                        TextEditor(text: $editSessionDescription)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.98))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.12)))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1.1))

                        premiumTextField("Room", text: $editSessionRoom)
                        premiumTextField("Track", text: $editSessionTrack)

                        VStack(alignment: .leading, spacing: 10) {
                            sessionDatePickerCard(title: "START", selection: $editSessionStartsAt)
                            sessionDatePickerCard(title: "END", selection: $editSessionEndsAt)
                        }

                        premiumTextField("Capacity", text: $editSessionCapacityText)
                            .keyboardType(.numberPad)

                        sessionFeaturedToggle(isOn: $editSessionFeatured)

                        sessionSpeakerPicker(selectedIDs: $editSessionSpeakerIDs)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.orange.opacity(0.12), lineWidth: 1))

                    Button { saveExistingSession(session) } label: {
                        commandActionLabel(isSavingSession ? "SAVING SESSION" : "SAVE SESSION", "checkmark.seal.fill", filled: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingSession)
                    .opacity(isSavingSession ? 0.55 : 1)

                    Button { deleteSession(session) } label: {
                        commandActionLabel("DELETE SESSION", "trash.fill", filled: false)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .padding(.bottom, 24)
            }
        }
    }

    private func saveNewSession() {
        let title = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = sessionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let room = sessionRoom.trimmingCharacters(in: .whitespacesAndNewlines)
        let track = sessionTrack.trimmingCharacters(in: .whitespacesAndNewlines)
        let capacity = Int(sessionCapacityText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let eventID = currentEvent.id.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !eventID.isEmpty else {
            app.showEventToast("EVENT NOT FOUND")
            return
        }

        guard !title.isEmpty else {
            app.showEventToast("SESSION TITLE REQUIRED")
            return
        }

        guard sessionEndsAt > sessionStartsAt else {
            app.showEventToast("END AFTER START")
            return
        }

        isSavingSession = true

        let ref = FirestoreService.db
            .collection("events")
            .document(eventID)
            .collection("sessions")
            .document()

        let payload: [String: Any] = [
            "id": ref.documentID,
            "eventId": eventID,
            "title": title,
            "description": description,
            "speakerIDs": Array(selectedSessionSpeakerIDs),
            "room": room.isEmpty ? "Main Stage" : room,
            "track": track.isEmpty ? "General" : track,
            "startsAt": Timestamp(date: sessionStartsAt),
            "endsAt": Timestamp(date: sessionEndsAt),
            "capacity": max(0, capacity),
            "featured": sessionFeatured,
            "status": sessionStatus,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        ref.setData(payload, merge: true) { error in
            DispatchQueue.main.async {
                self.isSavingSession = false

                if let error {
                    print("⚠️ [EventManagementView] Save session failed:", error)
                    self.app.showEventToast("SESSION SAVE FAILED")
                    return
                }

                self.sessionTitle = ""
                self.sessionDescription = ""
                self.sessionRoom = "Main Stage"
                self.sessionTrack = "General"
                self.sessionStartsAt = Date()
                self.sessionEndsAt = Date().addingTimeInterval(3600)
                self.sessionCapacityText = ""
                self.sessionFeatured = false
                self.sessionStatus = "draft"
                self.selectedSessionSpeakerIDs = []
                self.app.showEventToast("SESSION CREATED")
            }
        }
    }

    private func saveExistingSession(_ session: EventSession) {
        let title = editSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = editSessionDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let room = editSessionRoom.trimmingCharacters(in: .whitespacesAndNewlines)
        let track = editSessionTrack.trimmingCharacters(in: .whitespacesAndNewlines)
        let capacity = Int(editSessionCapacityText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let eventID = currentEvent.id.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !eventID.isEmpty else {
            app.showEventToast("EVENT NOT FOUND")
            return
        }

        guard !title.isEmpty else {
            app.showEventToast("SESSION TITLE REQUIRED")
            return
        }

        guard editSessionEndsAt > editSessionStartsAt else {
            app.showEventToast("END AFTER START")
            return
        }

        let payload: [String: Any] = [
            "id": session.id,
            "eventId": eventID,
            "title": title,
            "description": description,
            "speakerIDs": Array(editSessionSpeakerIDs),
            "room": room.isEmpty ? "Main Stage" : room,
            "track": track.isEmpty ? "General" : track,
            "startsAt": Timestamp(date: editSessionStartsAt),
            "endsAt": Timestamp(date: editSessionEndsAt),
            "capacity": max(0, capacity),
            "featured": editSessionFeatured,
            "status": editSessionStatus,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        FirestoreService.db
            .collection("events")
            .document(eventID)
            .collection("sessions")
            .document(session.id)
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    if let error {
                        print("⚠️ [EventManagementView] Update session failed:", error)
                        self.app.showEventToast("SESSION SAVE FAILED")
                        return
                    }

                    self.editingSession = nil
                    self.app.showEventToast("SESSION SAVED")
                }
            }
    }

    private func deleteSession(_ session: EventSession) {
        let eventID = currentEvent.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventID.isEmpty else {
            app.showEventToast("EVENT NOT FOUND")
            return
        }

        FirestoreService.db
            .collection("events")
            .document(eventID)
            .collection("sessions")
            .document(session.id)
            .delete { error in
                DispatchQueue.main.async {
                    if let error {
                        print("⚠️ [EventManagementView] Delete session failed:", error)
                        self.app.showEventToast("DELETE FAILED")
                        return
                    }

                    self.editingSession = nil
                    self.app.showEventToast("SESSION DELETED")
                }
            }
    }

    private func startLiveEventSessionsListener(for eventID: String) {
        let cleanedID = eventID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedID.isEmpty else { return }

        if liveEventSessionsListener != nil, liveEventSessionsEventID == cleanedID {
            return
        }

        stopLiveEventSessionsListener()
        liveEventSessionsEventID = cleanedID

        liveEventSessionsListener = FirestoreService.db
            .collection("events")
            .document(cleanedID)
            .collection("sessions")
            .order(by: "startsAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("⚠️ [EventManagementView] Session listener failed: \(error)")
                    return
                }

                let sessions: [EventSession] = snapshot?.documents.compactMap { doc in
                    let data = doc.data()
                    let startsAt = self.eventGuestDateValue(data["startsAt"]) ?? Date()
                    let endsAt = self.eventGuestDateValue(data["endsAt"]) ?? startsAt.addingTimeInterval(3600)

                    return EventSession(
                        id: data["id"] as? String ?? doc.documentID,
                        title: data["title"] as? String ?? "Untitled Session",
                        description: data["description"] as? String ?? "",
                        speakerIDs: data["speakerIDs"] as? [String] ?? [],
                        room: data["room"] as? String ?? "Main Stage",
                        track: data["track"] as? String ?? "General",
                        startsAt: startsAt,
                        endsAt: endsAt,
                        capacity: data["capacity"] as? Int ?? 0,
                        featured: data["featured"] as? Bool ?? false,
                        status: data["status"] as? String ?? "draft"
                    )
                } ?? []

                Task { @MainActor in
                    self.sessionRecords = sessions
                }
            }
    }

    private func stopLiveEventSessionsListener() {
        liveEventSessionsListener?.remove()
        liveEventSessionsListener = nil
        liveEventSessionsEventID = ""
        sessionRecords = []
    }

    private func sessionSpeakerNames(for session: EventSession) -> String {
        let names = session.speakerIDs.compactMap { speakerID in
            currentCRMGuests.first(where: { $0.id == speakerID })?.name
        }

        return names.joined(separator: ", ")
    }

    private func sessionTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func guestDirectoryExport() -> String {
        var lines: [String] = []
        lines.append("Guest / Delegate Directory — \(currentEvent.title)")
        lines.append(eventDateLine(currentEvent))
        lines.append("")

        let records = directoryGuestRecords

        if records.isEmpty {
            lines.append("No guests added yet.")
            return lines.joined(separator: "\n")
        }

        for guest in records {
            lines.append("• \(guest.name)")
            lines.append("  Role: \(guest.role.rawValue)")
            lines.append("  Status: \(guest.status.rawValue)")
            lines.append("  Source: \(guest.source)")
            if !guest.email.isEmpty { lines.append("  Email: \(guest.email)") }
            if !guest.organization.isEmpty { lines.append("  Organization: \(guest.organization)") }
            if guest.isVIP { lines.append("  VIP: Yes") }
            if !guest.notes.isEmpty { lines.append("  Notes: \(guest.notes)") }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func communicationsCenterPanel(_ command: EventCommandSheet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            communicationOpsSnapshot
            communicationTemplatePicker
            communicationAudiencePicker
            communicationMessageComposer
            communicationPreviewActions(command)
        }
    }

    private var communicationOpsSnapshot: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MESSAGE OPS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(2)

                Spacer()

                Text(communicationIndividualGuest == nil ? "AUDIENCE MODE" : "INDIVIDUAL MODE")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.black.opacity(0.86))
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(Capsule().fill(Color.orange.opacity(0.96)))
            }

            Text(communicationIndividualGuest == nil ? "Choose an audience, apply a template, review the message, then send through the verified event communication pipeline." : "Send a personalized one-to-one event message to this attendee using the same event communication pipeline.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                communicationMetric("AUDIENCE", communicationAudienceCount(communicationAudience), tint: .orange)
                communicationMetric("ACCEPTED", communicationAudienceCount(.accepted), tint: .green)
                communicationMetric("WAITLIST", communicationAudienceCount(.waitlist), tint: .orange)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.orange.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.orange.opacity(0.14), lineWidth: 1))
    }

    private var communicationTemplatePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MESSAGE TEMPLATE")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CommunicationTemplate.allCases) { template in
                    communicationChoiceTile(
                        title: template.shortLabel,
                        subtitle: template.rawValue,
                        icon: template.icon,
                        selected: communicationTemplate == template
                    ) {
                        communicationTemplate = template
                        communicationSubject = defaultCommunicationSubject(template: template)
                        commandNotes = communicationMessageBody(
                            template: template,
                            audience: communicationAudience,
                            recipient: communicationIndividualGuest
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var communicationAudiencePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(communicationIndividualGuest == nil ? "AUDIENCE SEGMENT" : "INDIVIDUAL RECIPIENT")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            if let guest = communicationIndividualGuest {
                individualRecipientCard(guest)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(CommunicationAudience.allCases) { audience in
                        communicationChoiceTile(
                            title: audience.shortLabel,
                            subtitle: "\(communicationAudienceCount(audience)) people",
                            icon: audience.icon,
                            selected: communicationAudience == audience
                        ) {
                            communicationAudience = audience
                            commandNotes = communicationMessageBody(
                                template: communicationTemplate,
                                audience: audience,
                                recipient: nil
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func individualRecipientCard(_ guest: GuestRecord) -> some View {
        HStack(spacing: 12) {
            speakerOrGuestAvatar(guest)

            VStack(alignment: .leading, spacing: 4) {
                Text(guest.name.isEmpty ? "Guest" : guest.name)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.94))
                    .lineLimit(1)

                Text(guest.email)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.52))
                    .lineLimit(1)

                Text("\(guest.role.rawValue.uppercased()) • \(guest.status.rawValue.uppercased())")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.66))
                    .tracking(0.6)
            }

            Spacer()

            Text("1:1")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(.black.opacity(0.86))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.orange.opacity(0.96)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.black.opacity(0.34)))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.orange.opacity(0.16), lineWidth: 1))
    }

    private func communicationChoiceTile(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.instance.impact(.light)
            SpatialAudioManager.shared.play(.uiTap)
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(selected ? .black.opacity(0.86) : .orange.opacity(0.92))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(selected ? Color.orange.opacity(0.96) : Color.orange.opacity(0.10)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(selected ? .white.opacity(0.95) : .white.opacity(0.78))
                        .tracking(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(subtitle.uppercased())
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                }

                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? Color.orange.opacity(0.10) : Color.black.opacity(0.30)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? Color.orange.opacity(0.24) : Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var communicationMessageComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MESSAGE PREVIEW")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            premiumTextField("Subject", text: $communicationSubject)

            TextEditor(text: $commandNotes)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.98))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 210)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.085)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func communicationPreviewActions(_ command: EventCommandSheet) -> some View {
        VStack(spacing: 10) {
            Button {
                sendEventCommunication(testMode: false)
            } label: {
                commandActionLabel(
                    isSendingCommunication
                    ? "SENDING"
                    : (communicationIndividualGuest == nil ? "SEND TO AUDIENCE" : "SEND TO ATTENDEE"),
                    "paperplane.fill",
                    filled: true
                )
            }
            .buttonStyle(.plain)
            .disabled(isSendingCommunication || !canSendCurrentCommunication)
            .opacity((isSendingCommunication || !canSendCurrentCommunication) ? 0.55 : 1)
        }
    }

    private var canSendCurrentCommunication: Bool {
        if let guest = communicationIndividualGuest {
            return !normalizedEmail(guest.email).isEmpty
        }

        return communicationAudienceCount(communicationAudience) > 0
    }

    private func sendEventCommunication(testMode: Bool) {
        guard !isSendingCommunication else { return }

        let eventID = currentEvent.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = communicationSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = commandNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let individualGuest = communicationIndividualGuest

        guard !eventID.isEmpty else {
            app.showEventToast("EVENT NOT FOUND")
            return
        }

        guard !subject.isEmpty else {
            app.showEventToast("SUBJECT REQUIRED")
            return
        }

        guard !body.isEmpty else {
            app.showEventToast("MESSAGE REQUIRED")
            return
        }

        if !testMode {
            if let individualGuest {
                guard !normalizedEmail(individualGuest.email).isEmpty else {
                    app.showEventToast("EMAIL REQUIRED")
                    return
                }
            } else if communicationAudienceCount(communicationAudience) == 0 {
                app.showEventToast("NO RECIPIENTS")
                return
            }
        }

        isSendingCommunication = true

        var payload: [String: Any] = [
            "eventId": eventID,
            "audience": communicationAudience.backendValue,
            "template": communicationTemplate.backendValue,
            "subject": subject,
            "body": body,
            "testMode": testMode,
            "personalize": true,
            "mode": individualGuest == nil ? "audience" : "individual"
        ]

        if let individualGuest {
            payload["recipientGuestId"] = individualGuest.source == "crm" ? stableCRMGuestDocumentID(for: individualGuest) : ""
            payload["recipientEmail"] = normalizedEmail(individualGuest.email)
            payload["recipientName"] = individualGuest.name.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["recipientRole"] = individualGuest.role.backendValue
            payload["recipientOrganization"] = individualGuest.organization.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        Functions.functions(region: "us-central1")
            .httpsCallable("sendEventCommunication")
            .call(payload) { result, error in
                DispatchQueue.main.async {
                    self.isSendingCommunication = false

                    if let error {
                        print("⚠️ [EventManagementView] sendEventCommunication failed:", error)
                        self.app.showEventToast(testMode ? "TEST SEND FAILED" : "SEND FAILED")
                        return
                    }

                    let data = result?.data as? [String: Any]
                    let sentCount = data?["sentCount"] as? Int ?? 0
                    let failedCount = data?["failedCount"] as? Int ?? 0
                    let status = (data?["status"] as? String ?? "").lowercased()

                    if testMode {
                        self.app.showEventToast(sentCount > 0 ? "TEST SENT" : "TEST FAILED")
                    } else if failedCount > 0 {
                        self.app.showEventToast("\(sentCount) SENT • \(failedCount) FAILED")
                    } else if status == "sent" {
                        if individualGuest != nil {
                            self.app.showEventToast("MESSAGE SENT")
                        } else {
                            self.app.showEventToast(
                                sentCount == 1
                                ? "1 MESSAGE SENT"
                                : "\(sentCount) MESSAGES SENT"
                            )
                        }
                    } else {
                        self.app.showEventToast("SEND FAILED")
                    }

                    self.communicationIndividualGuest = nil
                    self.activeCommand = nil
                }
            }
    }

    private func stableCRMGuestDocumentID(for guest: GuestRecord) -> String {
        currentCRMGuests.first {
            normalizedEmail($0.email) == normalizedEmail(guest.email)
        }?.id ?? ""
    }

    private func communicationMetric(_ title: String, _ value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(tint.opacity(0.88))
                .tracking(1)

            Text("\(value)")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.94))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(tint.opacity(0.16), lineWidth: 1))
    }

    private func isCommunicationCommand(_ command: EventCommandSheet) -> Bool {
        switch command {
        case .messageAttendees, .sendReminder, .messageWaitlist:
            return true
        default:
            return false
        }
    }

    private func defaultCommunicationTemplate(for command: EventCommandSheet) -> CommunicationTemplate {
        switch command {
        case .sendReminder:
            return .reminder
        case .messageWaitlist:
            return .finalCall
        case .messageAttendees:
            return .scheduleUpdate
        default:
            return .custom
        }
    }

    private func defaultCommunicationAudience(for command: EventCommandSheet) -> CommunicationAudience {
        switch command {
        case .messageWaitlist:
            return .waitlist
        case .sendReminder, .messageAttendees:
            return .accepted
        default:
            return .all
        }
    }

    private func communicationAudienceCount(_ audience: CommunicationAudience) -> Int {
        switch audience {
        case .all:
            return directoryGuestRecords.count
        case .accepted:
            return acceptedCRMCount + checkedInCRMCount
        case .invited:
            return invitedCRMCount
        case .waitlist:
            return currentEvent.waitlistCount
        case .checkedIn:
            return checkedInCRMCount
        case .vip:
            return directoryGuestRecords.filter { $0.isVIP || $0.role == .vip }.count
        case .speakers:
            return sessionSpeakerOptions.count
        }
    }

    private func defaultCommunicationSubject(template: CommunicationTemplate) -> String {
        switch template {
        case .reminder:
            return "Reminder: \(currentEvent.title)"
        case .finalCall:
            return "Final call: \(currentEvent.title)"
        case .venueChange:
            return "Venue update: \(currentEvent.title)"
        case .scheduleUpdate:
            return "Schedule update: \(currentEvent.title)"
        case .checkInInstructions:
            return "Check-in details: \(currentEvent.title)"
        case .thankYou:
            return "Thank you for joining \(currentEvent.title)"
        case .custom:
            return currentEvent.title
        }
    }

    private func communicationMessageBody(
        template: CommunicationTemplate,
        audience: CommunicationAudience,
        recipient: GuestRecord? = nil
    ) -> String {
        let title = currentEvent.title
        let dateLine = eventDateLine(currentEvent)
        let greetingName = recipientFirstName(recipient)
        let greeting = greetingName.isEmpty ? "Hi {{firstName}}," : "Hi \(greetingName),"

        switch template {
        case .reminder:
            return """
            \(greeting)

            This is a reminder that you’re confirmed for \(title).

            Event timing:
            \(dateLine)

            Please check your event details before arrival. We’ll share any final access instructions if anything changes.

            — Trivia GOAT
            """

        case .finalCall:
            return """
            \(greeting)

            Final call for \(title).

            Timing:
            \(dateLine)

            If you plan to attend, please confirm your event details now. Capacity and waitlist movement will be handled through the event system.

            — Trivia GOAT
            """

        case .venueChange:
            return """
            \(greeting)

            Venue details for \(title) have been updated.

            Current event timing:
            \(dateLine)

            Please review the latest event page before arrival and use the newest location/access instructions.

            — Trivia GOAT
            """

        case .scheduleUpdate:
            return """
            \(greeting)

            There is a schedule update for \(title).

            Current timing:
            \(dateLine)

            Please review the latest agenda and event details before the event begins.

            — Trivia GOAT
            """

        case .checkInInstructions:
            return """
            \(greeting)

            Check-in instructions for \(title):

            1. Arrive with your RSVP confirmation ready.
            2. Check in with event staff on arrival.
            3. Follow speaker/session timing from the event agenda.

            Event timing:
            \(dateLine)

            — Trivia GOAT
            """

        case .thankYou:
            return """
            \(greeting)

            Thank you for joining \(title).

            We appreciate you being part of the Trivia GOAT event experience. Watch for follow-up details, recaps, or future event announcements.

            — Trivia GOAT
            """

        case .custom:
            return """
            \(greeting)

            Update for \(title):

            [Write your message here.]

            Event timing:
            \(dateLine)

            — Trivia GOAT
            """
        }
    }

    private func communicationExportText() -> String {
        """
        To: \(communicationAudience.rawValue) (\(communicationAudienceCount(communicationAudience)))
        Subject: \(communicationSubject)

        \(commandNotes)
        """
    }

    private func recipientFirstName(_ recipient: GuestRecord?) -> String {
        guard let recipient else { return "" }

        let cleaned = recipient.name
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "" }

        return cleaned
            .split(separator: " ")
            .first
            .map(String.init) ?? cleaned
    }

    private func commandNotesEditor(_ command: EventCommandSheet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMAND NOTES")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.92))
                .tracking(2)

            TextEditor(text: $commandNotes)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.98))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
    }

    private func commandPrimaryActions(_ command: EventCommandSheet) -> some View {
        VStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = commandNotes
                app.showEventToast("COPIED")
                activeCommand = nil
            } label: {
                commandActionLabel("COPY COMMAND PLAN", "doc.on.doc.fill", filled: true)
            }
            .buttonStyle(.plain)

            Button {
                app.showEventToast(commandToast(command))
                activeCommand = nil
            } label: {
                commandActionLabel("MARK READY", "checkmark.seal.fill", filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func commandActionLabel(_ title: String, _ icon: String, filled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .black))

            Text(title)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .tracking(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .black))
        }
        .foregroundColor(filled ? .black.opacity(0.90) : .orange.opacity(0.95))
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(filled ? Color.orange.opacity(0.96) : Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private func commandTitle(_ command: EventCommandSheet) -> String {
        switch command {
        case .checkIn: return "CHECK-IN OPS"
        case .badges: return "BADGE CONTROL"
        case .runOfShow: return "RUN OF SHOW"
        case .staffRoles: return "STAFF ROLES"
        case .invitationCenter: return "INVITATION CENTER"
        case .sessionBuilder: return "SESSION BUILDER"
        case .delegateDirectory: return "DELEGATE DIRECTORY"
        case .guestPanel: return "GUEST PANEL"
        case .messageAttendees: return "MESSAGE ATTENDEES"
        case .sendReminder: return "SEND REMINDER"
        case .messageWaitlist: return "MESSAGE WAITLIST"
        }
    }

    private func commandSubtitle(_ command: EventCommandSheet) -> String {
        switch command {
        case .checkIn:
            return "Prepare event-day check-in flow, door notes, and guest verification steps."
        case .badges:
            return "Draft badge requirements, guest ID rules, and access-marker instructions."
        case .runOfShow:
            return "Build the event timeline with arrival, opening, sessions, breaks, and closeout."
        case .staffRoles:
            return "Assign staff, moderators, VIP handlers, and event-day ownership."
        case .invitationCenter:
            return "Import contacts, stage invitees, assign roles, send invitations, and track responses."
        case .sessionBuilder:
            return "Outline tracks, rooms, time blocks, and session ownership."
        case .delegateDirectory:
            return "Import contacts, stage invitations, assign roles, and manage delegates."
        case .guestPanel:
            return "Add guests manually or import from Contacts, then stage invitations with locked admin-assigned roles."
        case .messageAttendees:
            return "Segment an audience, choose a template, preview, and prepare an event update."
        case .sendReminder:
            return "Prepare a reminder with timing, access, check-in, and agenda details."
        case .messageWaitlist:
            return "Prepare a waitlist notice for capacity pressure and access movement."
        }
    }

    private func commandIcon(_ command: EventCommandSheet) -> String {
        switch command {
        case .checkIn: return "qrcode.viewfinder"
        case .badges: return "lanyardcard.fill"
        case .runOfShow: return "list.bullet.rectangle.fill"
        case .staffRoles: return "person.3.fill"
        case .invitationCenter: return "person.crop.circle.badge.plus"
        case .sessionBuilder: return "rectangle.3.group.fill"
        case .delegateDirectory: return "person.crop.rectangle.stack.fill"
        case .guestPanel: return "person.2.badge.gearshape.fill"
        case .messageAttendees: return "envelope.fill"
        case .sendReminder: return "bell.badge.fill"
        case .messageWaitlist: return "text.bubble.fill"
        }
    }

    private func commandToast(_ command: EventCommandSheet) -> String {
        switch command {
        case .checkIn: return "CHECK-IN READY"
        case .badges: return "BADGES READY"
        case .runOfShow: return "RUN OF SHOW READY"
        case .staffRoles: return "STAFF READY"
        case .invitationCenter: return "INVITATIONS READY"
        case .sessionBuilder: return "SESSIONS READY"
        case .delegateDirectory: return "DELEGATES READY"
        case .guestPanel: return "GUEST PANEL READY"
        case .messageAttendees: return "MESSAGE READY"
        case .sendReminder: return "REMINDER READY"
        case .messageWaitlist: return "WAITLIST MESSAGE READY"
        }
    }

    private func defaultCommandText(for command: EventCommandSheet) -> String {
        let title = currentEvent.title
        let dateLine = eventDateLine(currentEvent)

        switch command {
        case .checkIn:
            return """
            Check-In Plan — \(title)
            Date: \(dateLine)

            1. Confirm attendee list before doors open.
            2. Verify RSVP status at entry.
            3. Escalate unmatched guests to event lead.
            4. Track no-shows and late arrivals.
            """

        case .badges:
            return """
            Badge Plan — \(title)

            Badge groups:
            • Attendees
            • Staff
            • Speakers / VIP
            • Sponsors

            Notes:
            • Confirm names before printing.
            • Keep backup blank badges ready.
            """

        case .runOfShow:
            return """
            Run of Show — \(title)
            Date: \(dateLine)

            Arrival:
            Opening:
            Main Segment:
            Break:
            Closing:
            Post-event follow-up:
            """

        case .staffRoles, .delegateDirectory, .guestPanel, .invitationCenter:
            return ""

        case .sessionBuilder:
            return """
            Session Builder — \(title)

            Track 1:
            Room / Space:
            Start:
            End:
            Owner:
            Notes:
            """

        case .messageAttendees:
            return """
            Hi,

            You’re confirmed for \(title).

            Event timing:
            \(dateLine)

            We’ll share any final access details before the event begins.

            — Trivia GOAT
            """

        case .sendReminder:
            return """
            Reminder: \(title) is coming up.

            Timing:
            \(dateLine)

            Please check your event details and arrive ready.

            — Trivia GOAT
            """

        case .messageWaitlist:
            return """
            Hi,

            You’re currently on the waitlist for \(title).

            We’ll notify you if capacity opens or your access status changes.

            — Trivia GOAT
            """
        }
    }

    private func eventDateLine(_ event: AppState.TGEvent) -> String {
        guard let startsAt = event.startsAt else { return "Date coming soon" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d • h:mm a"

        if let endsAt = event.endsAt {
            return "\(formatter.string(from: startsAt)) → \(formatter.string(from: endsAt))"
        }

        return formatter.string(from: startsAt)
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




private struct ContactPickerSheet: UIViewControllerRepresentable {
    let onPick: ([CNContact]) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactEmailAddressesKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([CNContact]) -> Void

        init(onPick: @escaping ([CNContact]) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onPick(contacts)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick([contact])
        }
    }
}








// MARK: - Session Builder Foundation

extension EventManagementView {

    struct EventSession: Identifiable, Hashable {
        var id: String
        var title: String
        var description: String
        var speakerIDs: [String]
        var room: String
        var track: String
        var startsAt: Date
        var endsAt: Date
        var capacity: Int
        var featured: Bool
        var status: String
    }
}








