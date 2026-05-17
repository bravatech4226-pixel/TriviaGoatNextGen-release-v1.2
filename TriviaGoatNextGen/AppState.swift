//
//  AppState.swift
//  TriviaGoatNextGen
//
//  SINGLE SOURCE OF TRUTH (REPAIRED & ALIGNED)
//  Routing + profile + trivia session + leaderboard + global battle
//

import SwiftUI
import Combine
import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class AppState: ObservableObject {
    
    
    // MARK: - Routing
    enum Route: Equatable {
        case landing
        case onboarding
        case welcome
        case hq
        case community
        case mission
        case events
        case eventDetail
        case creatorConsole
        case manageEvent
        case eventEditor
        case results
        case leaderboard
        case settings
        case battleDecision
        case proPaywall
        case streakPaywall
        case paywall
        case globalBattle
        case globalBattleMatch
    }
    
    struct TGEvent: Equatable, Identifiable {
        let id: String
        let title: String
        let heroLine: String
        let summary: String
        let coverImageURL: String?
        let status: String
        let approvalStatus: String
        let visibility: String
        let category: String
        let locationType: String
        let startsAt: Date?
        let endsAt: Date?
        let capacity: Int
        let attendeeCount: Int
        let waitlistEnabled: Bool
        let featured: Bool
        let featuredPriority: Int
        let published: Bool
        let organizerUID: String?
        let organizerName: String?
        let submittedByUID: String?
        let approvedByUID: String?
        let approvedAt: Date?
        let rejectedReason: String?
        let createdAt: Date?
    }
    
    @Published var route: Route = .landing
    
    // --- FIX: PERSISTENCE LATCHES ---
    // These ensure that once a user has a name, the app stays in HQ
    // even if the Firebase sync is momentarily slow on boot.
    @AppStorage("tg.onboarding.isComplete") private var localOnboardingComplete: Bool = false
    @AppStorage("tg.user.codename") private var localCodename: String = ""
    
    // MARK: - Core State
    
    @Published private(set) var user: User? = nil
    @Published var isBusy: Bool = false
    @Published var profile: UserProfile = .placeholder
    @Published var trivia: TriviaSession = .idle
    
    @Published private(set) var topPlayers: [UserProfile] = []
    @Published var rankDelta: LeaderboardLiveService.RankDelta? = nil
    @Published var onboardingErrorMessage: String? = nil
    @Published private(set) var pendingPostPaywallRoute: Route? = nil
    @Published var globalBattleSession: GlobalBattleSession? = nil
    
    /// In-run streak (combo) used by TriviaGameView
    @Published var streakCount: Int = 0
    
    /// Daily streak system snapshot (days + multiplier)
    @Published private(set) var dailyStreakCount: Int = 0
    @Published private(set) var dailyStreakMultiplier: Double = 1.0
    
#if DEBUG
    @AppStorage("tg.debug.globalBattleEnabled") private var debugGlobalBattleEnabled: Bool = false
#endif
    
    @Published private(set) var remoteGlobalBattleEnabled: Bool = false
    @Published private(set) var communityPulse: [CommunityPulseItem] = []
    @Published private(set) var latestAIPulse: CommunityPulseItem? = nil
    @Published private(set) var latestCommunityPulse: CommunityPulseItem? = nil
    @Published var hasUnreadCommunityPulse: Bool = false
    @Published private(set) var isRefreshingCommunityPulse: Bool = false
    
    @Published private(set) var communityCommentsByPostID: [String: [CommunityComment]] = [:]
    @Published private(set) var isRefreshingCommunityCommentsByPostID: [String: Bool] = [:]
    @Published private(set) var isSubmittingCommunityComment: Bool = false
    @Published private(set) var pendingCommunityCommentStatesByPostID: [String: PendingCommunityCommentState] = [:]
    @Published private(set) var isRefreshingEvents: Bool = false
    @Published var hasUnreadEvents: Bool = false
    @Published var eventsErrorMessage: String? = nil
    @Published private(set) var RSVPedEventIDs: Set<String> = []
    @Published var eventRSVPToastMessage: String? = nil
    @Published private(set) var joinedEventWaitlists: Set<String> = []
    
    private var pendingCommunityRefreshCompletion: (() -> Void)? = nil
    @Published private(set) var communityPulseLastRefreshedAt: Date? = nil
    @Published private(set) var events: [TGEvent] = []
    @Published private(set) var featuredEvent: TGEvent? = nil
    @Published var selectedEvent: TGEvent?
    
    private var communityPulseListener: ListenerRegistration?
    private var eventsListener: ListenerRegistration?
    private var communityCommentListeners: [String: ListenerRegistration] = [:]
    private var pendingCommunityCommentStatusListeners: [String: ListenerRegistration] = [:]
    private var globalBattleAdminListener: ListenerRegistration?
    private var eventRSVPListeners: [String: ListenerRegistration] = [:]
    
    
    
    // MARK: - Post-Battle Decision
    
    struct BattleDecisionState: Equatable {
        let outcome: BattleDecisionView.Outcome
        let opponentName: String?
        let scoreLine: String?
    }
    
    @Published private(set) var battleDecision: BattleDecisionState? = nil
    
    
    // MARK: - Post-Onboarding Welcome
    
    struct WelcomeState: Equatable {
        let playerName: String
        let selectedTeam: TacticalTeam
        let createdAt: Date
    }
    
    // MARK: - Events Ecosystem

    private func startEventsListenerIfNeeded() {
        guard eventsListener == nil else { return }

        isRefreshingEvents = true
        eventsErrorMessage = nil

        eventsListener = FirestoreService.db
            .collection("events")
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    self.isRefreshingEvents = false
                    self.eventsErrorMessage = "Events could not be loaded right now."
                    print("⚠️ Events listener error: \(error)")
                    return
                }

                guard let documents = snapshot?.documents else {
                    self.events = []
                    self.featuredEvent = nil
                    self.isRefreshingEvents = false
                    return
                }

                let nextEvents: [TGEvent] = documents.compactMap { doc in
                    self.makeTGEvent(from: doc)
                }

                let publicEvents = nextEvents
                    .filter {
                        $0.published &&
                        $0.approvalStatus == "approved" &&
                        $0.visibility.lowercased() == "public"
                    }
                    .sorted { lhs, rhs in
                        switch (lhs.startsAt, rhs.startsAt) {
                        case let (l?, r?):
                            return l < r
                        case (_?, nil):
                            return true
                        case (nil, _?):
                            return false
                        case (nil, nil):
                            return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
                        }
                    }

                self.events = publicEvents

                self.featuredEvent =
                    publicEvents
                        .sorted { $0.featuredPriority > $1.featuredPriority }
                        .first(where: { $0.featured })
                    ?? publicEvents.first

                self.isRefreshingEvents = false
            }
    }

    private func makeTGEvent(from doc: QueryDocumentSnapshot) -> TGEvent? {
        let data = doc.data()

        let title =
            cleanString(data["title"])
            ?? cleanString(data["name"])
            ?? "Untitled Event"

        guard !title.isEmpty else { return nil }

        let heroLine =
            cleanString(data["heroLine"])
            ?? cleanString(data["description"])
            ?? ""

        let summary =
            cleanString(data["summary"])
            ?? cleanString(data["description"])
            ?? heroLine

        let startsAt =
            eventDateValue(data["startsAt"])
            ?? eventDateValue(data["startAt"])
            ?? eventDateValue(data["startDate"])
            ?? eventDateValue(data["date"])
            ?? eventDateValue(data["eventDate"])

        let endsAt =
            eventDateValue(data["endsAt"])
            ?? eventDateValue(data["endAt"])
            ?? eventDateValue(data["endDate"])

        let attendeeCount =
            intEventValue(data["attendeeCount"])
            ?? intEventValue(data["rsvpCount"])
            ?? 0

        return TGEvent(
            id: doc.documentID,
            title: title,
            heroLine: heroLine,
            summary: summary,
            coverImageURL: cleanString(data["coverImageURL"]),
            status: cleanString(data["status"]) ?? "scheduled",
            approvalStatus: cleanString(data["approvalStatus"]) ?? legacyApprovalStatus(from: data),
            visibility: cleanString(data["visibility"]) ?? legacyVisibility(from: data),
            category: cleanString(data["category"]) ?? cleanString(data["type"]) ?? "community",
            locationType: cleanString(data["locationType"]) ?? "virtual",
            startsAt: startsAt,
            endsAt: endsAt,
            capacity: intEventValue(data["capacity"]) ?? 0,
            attendeeCount: max(0, attendeeCount),
            waitlistEnabled: data["waitlistEnabled"] as? Bool ?? false,
            featured: data["featured"] as? Bool ?? false,
            featuredPriority: intEventValue(data["featuredPriority"]) ?? 0,
            published: data["published"] as? Bool ?? data["isPublic"] as? Bool ?? false,
            organizerUID: cleanString(data["organizerUID"]),
            organizerName: cleanString(data["organizerName"]),
            submittedByUID: cleanString(data["submittedByUID"]),
            approvedByUID: cleanString(data["approvedByUID"]),
            approvedAt: eventDateValue(data["approvedAt"]),
            rejectedReason: cleanString(data["rejectedReason"]),
            createdAt: eventDateValue(data["createdAt"])
        )
    }

    private func cleanString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func intEventValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func eventDateValue(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp {
            return ts.dateValue()
        }

        if let date = value as? Date {
            return date
        }

        if let seconds = value as? TimeInterval {
            return Date(timeIntervalSince1970: seconds)
        }

        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }

        if let string = value as? String {
            let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }

            let isoWithFractionalSeconds = ISO8601DateFormatter()
            isoWithFractionalSeconds.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]

            if let parsed = isoWithFractionalSeconds.date(from: cleaned) {
                return parsed
            }

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]

            if let parsed = iso.date(from: cleaned) {
                return parsed
            }

            let fallback = DateFormatter()
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"

            return fallback.date(from: cleaned)
        }

        return nil
    }

    func refreshEvents() {
        isRefreshingEvents = true
        eventsErrorMessage = nil

        eventsListener?.remove()
        eventsListener = nil

        startEventsListenerIfNeeded()
    }

    func markEventsRead() {
        hasUnreadEvents = false
    }

    func openEvents() {
        setRoute(.events)
    }

    func showEventToast(_ message: String) {
        eventRSVPToastMessage = message

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)

            guard let self else { return }

            if self.eventRSVPToastMessage == message {
                self.eventRSVPToastMessage = nil
            }
        }
    }

    func hasRSVPed(to event: TGEvent) -> Bool {
        RSVPedEventIDs.contains(event.id)
    }

    func hasRSVPedToEvent(_ eventID: String) -> Bool {
        RSVPedEventIDs.contains(eventID)
    }

    func hasJoinedWaitlist(_ eventID: String) -> Bool {
        joinedEventWaitlists.contains(eventID)
    }

    func isOrganizer(of event: TGEvent) -> Bool {
        guard let uid = user?.uid else { return false }
        return event.organizerUID == uid
    }

    func canManage(_ event: TGEvent) -> Bool {
        guard let currentUID = user?.uid else { return false }
        return event.organizerUID == currentUID
    }

    func canEdit(_ event: TGEvent) -> Bool {
        guard canManage(event) else { return false }

        switch event.approvalStatus {
        case "draft", "submitted", "rejected":
            return true
        default:
            return false
        }
    }

    func canMessageAttendees(_ event: TGEvent) -> Bool {
        canManage(event)
    }

    func canPublish(_ event: TGEvent) -> Bool {
        canModerate(event)
    }

    func canModerate(_ event: TGEvent) -> Bool {
        let email = user?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return email == "bravatech4226@gmail.com"
    }

    private func legacyApprovalStatus(from data: [String: Any]) -> String {
        if let status = cleanString(data["status"])?.lowercased() {
            if status == "cancelled" || status == "canceled" {
                return "archived"
            }

            if status == "live" || status == "scheduled" || status == "active" {
                return "approved"
            }
        }

        if data["isPublic"] as? Bool == true {
            return "approved"
        }

        return "draft"
    }

    private func legacyVisibility(from data: [String: Any]) -> String {
        if data["isPublic"] as? Bool == true {
            return "public"
        }

        return cleanString(data["visibility"]) ?? "private"
    }

    // MARK: - Event Drafts

    func saveEventDraft(_ draft: EventDraft) {
        guard let uid = user?.uid else {
            showEventToast("SIGN IN REQUIRED")
            return
        }

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else {
            showEventToast("TITLE REQUIRED")
            return
        }

        let organizerName = profile.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var payload = draft.firestorePayload(
            organizerUID: uid,
            organizerName: organizerName.isEmpty ? "Trivia GOAT" : organizerName
        )

        payload["updatedAt"] = FieldValue.serverTimestamp()

        FirestoreService.db
            .collection("events")
            .document()
            .setData(payload, merge: true) { [weak self] error in
                guard let self else { return }

                Task { @MainActor in
                    if let error {
                        print("⚠️ Save event draft failed: \(error)")
                        self.showEventToast("DRAFT SAVE FAILED")
                        return
                    }

                    self.showEventToast("DRAFT SAVED")
                    self.refreshEvents()
                    self.setRoute(.creatorConsole)
                }
            }
    }

    func RSVPToEvent(_ event: TGEvent) {
        guard let uid = user?.uid else {
            showEventToast("SIGN IN REQUIRED")
            return
        }

        guard !RSVPedEventIDs.contains(event.id) else {
            showEventToast("ALREADY RSVP'D")
            return
        }

        guard !isOrganizer(of: event) else {
            showEventToast("YOU ARE HOSTING")
            return
        }

        let isFull = event.capacity > 0 && event.attendeeCount >= event.capacity

        if isFull {
            if event.waitlistEnabled {
                joinEventWaitlist(event)
            } else {
                showEventToast("EVENT FULL")
            }

            return
        }

        let cleanedName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanedName.isEmpty ? "Pilot" : cleanedName

        RSVPToEventLocally(event.id)

        let db = FirestoreService.db
        let eventRef = db.collection("events").document(event.id)
        let rsvpRef = eventRef.collection("rsvps").document(uid)

        db.runTransaction({ transaction, errorPointer -> Any? in
            do {
                let rsvpSnapshot = try transaction.getDocument(rsvpRef)

                if rsvpSnapshot.exists {
                    return nil
                }

                transaction.setData([
                    "uid": uid,
                    "displayName": displayName,
                    "status": "confirmed",
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: rsvpRef, merge: true)

                transaction.updateData([
                    "attendeeCount": FieldValue.increment(Int64(1)),
                    "rsvpCount": FieldValue.increment(Int64(1)),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: eventRef)

                return nil
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }) { [weak self] _, error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.RSVPedEventIDs.remove(event.id)
                    print("⚠️ RSVP failed: \(error)")
                    self.showEventToast("RSVP FAILED")
                    return
                }

                self.showEventToast("RSVP CONFIRMED")
                self.refreshEvents()
            }
        }
    }

    private func RSVPToEventLocally(_ eventID: String) {
        RSVPedEventIDs.insert(eventID)
    }

    func joinEventWaitlist(_ event: TGEvent) {
        guard let uid = user?.uid else {
            showEventToast("SIGN IN REQUIRED")
            return
        }

        guard !joinedEventWaitlists.contains(event.id) else {
            showEventToast("ALREADY WAITLISTED")
            return
        }

        let cleanedName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cleanedName.isEmpty ? "Pilot" : cleanedName

        joinedEventWaitlists.insert(event.id)

        let db = FirestoreService.db
        let eventRef = db.collection("events").document(event.id)
        let waitlistRef = eventRef.collection("waitlist").document(uid)

        db.runTransaction({ transaction, errorPointer -> Any? in
            do {
                let waitlistSnapshot = try transaction.getDocument(waitlistRef)

                if waitlistSnapshot.exists {
                    return nil
                }

                transaction.setData([
                    "uid": uid,
                    "displayName": displayName,
                    "status": "waitlisted",
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: waitlistRef, merge: true)

                transaction.updateData([
                    "waitlistCount": FieldValue.increment(Int64(1)),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: eventRef)

                return nil
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
        }) { [weak self] _, error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.joinedEventWaitlists.remove(event.id)
                    print("⚠️ Join waitlist failed: \(error)")
                    self.showEventToast("WAITLIST FAILED")
                    return
                }

                self.showEventToast("WAITLIST JOINED")
                self.refreshEvents()
            }
        }
    }
    
    
    // MARK: - Community Pulse
    
    struct CommunityPulseItem: Equatable, Identifiable {
        let id: String
        let title: String
        let content: String
        let authorName: String
        let isAI: Bool
        let contentType: String?
        let topic: String?
        let createdAt: Date
    }
    
    struct CommunityComment: Equatable, Identifiable {
        let id: String
        let postID: String
        let parentCommentID: String?
        let content: String
        let authorName: String
        let authorUID: String?
        let isAI: Bool
        let status: String
        let createdAt: Date
        
        var isReply: Bool {
            guard let parentCommentID else { return false }
            return !parentCommentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    struct PendingCommunityCommentState: Equatable {
        enum Status: Equatable {
            case pending
            case rejected
        }
        
        let status: Status
        let userFacingReason: String?
        
        var isPending: Bool {
            status == .pending
        }
    }
    
    @Published private(set) var welcomeState: WelcomeState? = nil
    
    // MARK: - Internal Latches
    
    @Published private(set) var didBoot: Bool = false
    @Published private(set) var isSyncing: Bool = false
    
    private var authListener: AuthStateDidChangeListenerHandle?
    private var profileListener: ListenerRegistration?
    private var listeningUID: String?
    
    private var cancellables: Set<AnyCancellable> = []
    private var didStartLiveLeaderboard: Bool = false
    
    // MARK: - Task Handles (cancel stale work)
    
    private var syncTask: Task<Void, Never>?
    private var runLoadTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var leaderboardTask: Task<Void, Never>?
    private var leaderboardAutoRouteTask: Task<Void, Never>?
    private var entitlementSyncTask: Task<Void, Never>?
    
    
    // MARK: - Entitlement Sync State
    
    private var lastEntitlementSyncFingerprint: String?
    private var isEntitlementSyncInFlight: Bool = false
    
    // MARK: - Run Snapshot (Results UI reads ONLY this)
    
    struct LastRun: Equatable {
        
        enum RunKind: Equatable {
            case dailyMission
            case training
            case aiForge
            case unknown
        }
        
        let kind: RunKind
        let topic: String
        let scoreCorrect: Int
        let questionCount: Int
        
        let baseXP: Int
        let missionBonusXP: Int
        
        let runStreakCount: Int
        let dailyStreakCount: Int
        let streakMultiplier: Double
        
        let finalXP: Int
        
        let didCompleteMissionToday: Bool
        let dayKey: String?
        
        let createdAt: Date
    }
    
    @Published private(set) var lastRun: LastRun? = nil
    
    var lastRunScoreLine: String {
        guard let run = lastRun else { return "RUN COMPLETE" }
        return "\(run.scoreCorrect)/\(max(1, run.questionCount)) CORRECT • +\(run.finalXP) XP"
    }
    
    // MARK: - Local Rewards Ledger (no backend required)
    
    struct RewardsLedger: Equatable, Codable {
        var totalClaims: Int = 0
        var totalXPDeposited: Int = 0
        
        // historical ledger info
        var lastClaimedAt: Date? = nil
        var lastClaimedXP: Int = 0
        var lastRankCheckpoint: String = ""
        var lastStreakSaved: Bool = false
        
        // UI presentation trigger — now intentionally unused / kept blank
        var lastClaimKey: String = ""
        
        // internal dedupe key so repeat claim taps do not double-count
        var lastReceiptKey: String = ""
    }
    
    @Published private(set) var rewards: RewardsLedger = .init()
    
    private enum RewardsLedgerStore {
        static let ud = UserDefaults.standard
        static let key = "tg.rewards.ledger.v1"
        
        static func load() -> RewardsLedger {
            guard let data = ud.data(forKey: key) else { return RewardsLedger() }
            do { return try JSONDecoder().decode(RewardsLedger.self, from: data) }
            catch { return RewardsLedger() }
        }
        
        static func save(_ ledger: RewardsLedger) {
            do {
                let data = try JSONEncoder().encode(ledger)
                ud.set(data, forKey: key)
            } catch { }
        }
    }
    
    // MARK: - Daily Trivia Pack Warmup (1% Performance Guard)
    
    private var didWarmDailyPacks: Bool = false
    
    func warmDailyPacksIfNeeded() {
        guard !didWarmDailyPacks else { return }
        didWarmDailyPacks = true
        
        let dayKey = TrainingGate.snapshot().dayKey
        
        Task { @MainActor in
            await DailyPackStore.shared.ensureTodayLoaded(dayKey: dayKey)
        }
    }
    
    // MARK: - Claim Glory
    
    /// SSoT “claim” action: records a local receipt (no XP double-add),
    /// then refreshes + routes to Leaderboard.
    func claimGlory() {
        guard let run = lastRun else {
            setRoute(.hq)
            return
        }
        
        cancelLeaderboardAutoRoute()
        
        let claimKey = makeClaimKey(for: run)
        
        if rewards.lastReceiptKey != claimKey {
            var updated = rewards
            updated.totalClaims += 1
            updated.totalXPDeposited += max(0, run.finalXP)
            updated.lastClaimedAt = Date()
            updated.lastClaimedXP = max(0, run.finalXP)
            updated.lastStreakSaved = (run.dailyStreakCount > 0)
            
            let rankName = RankEngine.currentTier(for: profile.xp).name
            updated.lastRankCheckpoint = rankName
            
            // keep internal receipt tracking for dedupe
            updated.lastReceiptKey = claimKey
            
            // explicitly suppress HQ/Arena reward overlay trigger
            updated.lastClaimKey = ""
            
            rewards = updated
            RewardsLedgerStore.save(updated)
        }
        
        refreshLeaderboard()
        setRoute(.leaderboard)
        
        leaderboardAutoRouteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            
            guard !Task.isCancelled else { return }
            guard self.route == .leaderboard else { return }
            guard self.battleDecision != nil else { return }
            
            self.setRoute(.battleDecision)
        }
    }
    
    private func makeClaimKey(for run: LastRun) -> String {
        let k = String(describing: run.kind)
        let day = run.dayKey ?? "-"
        let t = String(Int(run.createdAt.timeIntervalSince1970))
        return "\(k)|\(day)|\(t)"
    }
    
    // MARK: - Computed
    
    var currentQuestion: TriviaQuestion? {
        let idx = trivia.currentIndex
        guard idx >= 0, idx < trivia.pack.count else { return nil }
        return trivia.pack[idx]
    }
    
    var currentLevel: Int {
        max(1, (profile.xp / 500) + 1)
    }
    
    var levelProgress: Double {
        let mod = profile.xp % 500
        return Double(mod) / 500.0
    }
    
    private var proEnabled: Bool {
    #if DEBUG
        if TGDebugProOverride.isPro { return true }
    #endif
        return profile.isPro || ProManager.shared.isPro
    }
    
    
    var isGlobalBattleEnabled: Bool {
#if DEBUG
        debugGlobalBattleEnabled || remoteGlobalBattleEnabled
#else
        remoteGlobalBattleEnabled
#endif
    }
    
    var canAccessGlobalBattle: Bool {
        isGlobalBattleEnabled && proEnabled
    }
    // MARK: - Lifecycle
    
    init() {
        var loadedRewards = RewardsLedgerStore.load()
        
        // hard-disable legacy HQ/Arena XP re-entry presentation
        loadedRewards.lastClaimKey = ""
        
        rewards = loadedRewards
        RewardsLedgerStore.save(loadedRewards)
        
        // --- FIX: Initial Routing Latch ---
        // If the phone remembers we are done, start in HQ immediately
        // This stops the "First Run" view from appearing on App Kill/Restart
        if localOnboardingComplete && !localCodename.isEmpty {
            self.route = .hq
        }
    }
    
    deinit {
        syncTask?.cancel()
        runLoadTask?.cancel()
        persistTask?.cancel()
        leaderboardTask?.cancel()
        leaderboardAutoRouteTask?.cancel()
        entitlementSyncTask?.cancel()

        if let h = authListener {
            Auth.auth().removeStateDidChangeListener(h)
        }

        profileListener?.remove()
        profileListener = nil
        listeningUID = nil

        // ADD THESE
        eventsListener?.remove()
        eventsListener = nil

        globalBattleAdminListener?.remove()
        globalBattleAdminListener = nil

        communityPulseListener?.remove()
        communityPulseListener = nil

        communityCommentListeners.values.forEach { $0.remove() }
        communityCommentListeners.removeAll()

        pendingCommunityCommentStatusListeners.values.forEach { $0.remove() }
        pendingCommunityCommentStatusListeners.removeAll()

        cancellables.removeAll()
    }
    // MARK: - Helpers
    
    private func currentUID() async -> String? {
        await AuthManager.shared.currentUID()
    }
    
    private func clearGlobalBattleSessionIfNeededForNonGlobalRoute(_ next: Route) {
        switch next {
        case .globalBattle, .globalBattleMatch:
            return
        default:
            break
        }
        
        guard globalBattleSession != nil else { return }
        clearGlobalBattleSession()
    }
    
    private var isOnGlobalBattleSurface: Bool {
        switch route {
        case .globalBattle, .globalBattleMatch:
            return true
        default:
            return false
        }
    }
    
    func completeProUpgradeFlow() {
        // Force entitlement refresh
        scheduleEntitlementSync(force: true)
        
        let destination = pendingPostPaywallRoute
        pendingPostPaywallRoute = nil
        
        if destination == .globalBattle {
            _ = ensureGlobalBattleSession()
            setRoute(.globalBattle)
        } else {
            setRoute(.hq)
        }
    }
    
    private func handleSignedOutState() {
        user = nil
        detachProfileListener()
        clearWelcomeState()
        clearBattleDecision()
        clearGlobalBattleSession()
        lastEntitlementSyncFingerprint = nil
        isEntitlementSyncInFlight = false
        entitlementSyncTask?.cancel()
        entitlementSyncTask = nil
        events = []
        featuredEvent = nil
        selectedEvent = nil
        isRefreshingEvents = false
        hasUnreadEvents = false
        eventsErrorMessage = nil
        RSVPedEventIDs = []
        joinedEventWaitlists = []
        eventRSVPToastMessage = nil

        eventsListener?.remove()
        eventsListener = nil
        
        // Reset local latches on sign out
        localOnboardingComplete = false
        localCodename = ""
        
        route = .onboarding
        communityPulse = []
        latestAIPulse = nil
        latestCommunityPulse = nil
        hasUnreadCommunityPulse = false
        isRefreshingCommunityPulse = false
        pendingCommunityRefreshCompletion = nil
        
        communityCommentListeners.values.forEach { $0.remove() }
        communityCommentListeners.removeAll()
        
        pendingCommunityCommentStatusListeners.values.forEach { $0.remove() }
        pendingCommunityCommentStatusListeners.removeAll()
        
        communityCommentsByPostID = [:]
        isRefreshingCommunityCommentsByPostID = [:]
        isSubmittingCommunityComment = false
        pendingCommunityCommentStatesByPostID = [:]
    }
    
    private func routeToHQIfAppropriate() {
        guard route != .welcome else { return }
        
        guard isOnboardingComplete(profile) else {
            if !isOnGlobalBattleSurface {
                route = .onboarding
            }
            return
        }
        
        switch route {
        case .globalBattle, .globalBattleMatch:
            return
        default:
            route = .hq
        }
    }
    
    private func isOnboardingComplete(_ profile: UserProfile) -> Bool {
        let name = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 🔥 CRITICAL FIX:
        // If we already have a LOCAL latch, trust it over remote/profile timing
        if localOnboardingComplete && !localCodename.isEmpty {
            return true
        }
        
        // Standard validation
        guard !name.isEmpty else { return false }
        
        // Only block if it's explicitly NEW PILOT
        if name.uppercased() == "NEW PILOT" {
            return false
        }
        
        return true
    }
    
    func cancelLeaderboardAutoRoute() {
        leaderboardAutoRouteTask?.cancel()
        leaderboardAutoRouteTask = nil
    }
    
    // MARK: - Boot
    
    func bootIfNeeded() {
        guard !didBoot else { return }
        didBoot = true
        
        // --- FIX: Logic to prevent landing -> onboarding flicker ---
        // If we are latched, we jump straight to HQ.
        if localOnboardingComplete && !localCodename.isEmpty {
            route = .hq
        } else {
            route = .landing
        }
        
        startAuthListenerIfNeeded()
        startLiveLeaderboardIfNeeded()
        startCommunityPulseListenerIfNeeded()
        startEventsListenerIfNeeded()
        installPlaceholderCommunityPulseIfNeeded()
        
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncAuthAndProfile()
            await MainActor.run {
                self.refreshDailyStreakSnapshot()
            }
        }
    }
    
    // MARK: - Admin / Feature Gates
    
    var canAccessGlobalBattleAdmin: Bool {
        isGlobalBattleEnabled
    }
    
    func openGlobalBattleAdmin() {
        guard canAccessGlobalBattleAdmin else { return }
        _ = ensureGlobalBattleSession()
        setRoute(.globalBattle)
    }
    
    // MARK: - Scene Phase
    
    func handleScenePhase(_ phase: ScenePhase) {
        guard phase == .active else { return }
        
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncAuthAndProfile()
            await MainActor.run {
                self.refreshDailyStreakSnapshot()
            }
        }
    }
    
    // MARK: - Results Routing (SSoT Gate)
    
    @discardableResult
    func openResults() -> Bool {
        guard lastRun != nil else { return false }
        setRoute(.results)
        return true
    }
    
    // MARK: - Battle Decision Routing
    
    func openBattleDecisionIfAvailable() -> Bool {
        guard battleDecision != nil else { return false }
        setRoute(.battleDecision)
        return true
    }
    
    func dismissBattleDecisionToResults() {
        guard lastRun != nil else {
            setRoute(.hq)
            return
        }
        setRoute(.results)
    }
    
    func clearBattleDecision() {
        battleDecision = nil
    }
    
    func rematchFromDecision() {
        clearBattleDecision()
        
        if openGlobalBattleIfEnabled() {
            return
        }
        
        setRoute(.hq)
    }
    
    func startDailyMissionFromDecision() {
        clearBattleDecision()
        startDailyMissionRun()
    }
    
    func startTrainingFromDecision(topic: String = "General Knowledge") {
        clearBattleDecision()
        beginTrainingArenaRun(topic: topic)
    }
    
    func backToHQFromDecision() {
        clearBattleDecision()
        setRoute(.hq)
    }
    
    
    // MARK: - Welcome Routing
    
    func openWelcomeIfAvailable() -> Bool {
        guard welcomeState != nil else { return false }
        setRoute(.welcome)
        return true
    }
    
    func clearWelcomeState() {
        welcomeState = nil
    }
    
    func goToHQFromWelcome() {
        clearWelcomeState()
        setRoute(.hq)
    }
    
    func startDailyMissionFromWelcome() {
        clearWelcomeState()
        startDailyMissionRun()
    }
    
    func startTrainingFromWelcome(topic: String = "General Knowledge") {
        clearWelcomeState()
        beginTrainingArenaRun(topic: topic)
    }
    
    // MARK: - Apple Profile Restore
    
    func secureOnboardingWithApple() {
        guard !isBusy else { return }

        onboardingErrorMessage = nil
        isBusy = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }

            do {
                let uid = try await AuthManager.shared.secureCurrentProfileWithApple()

                await syncAuthAndProfile()

                self.user = Auth.auth().currentUser
                self.attachProfileListenerIfNeeded(uid: uid)

                if let remote = try await FirestoreService.shared.fetchProfile(uid: uid),
                   self.isOnboardingComplete(remote) {
                    self.profile = remote
                    self.localOnboardingComplete = true
                    self.localCodename = remote.displayName
                    self.clearWelcomeState()
                    self.setRoute(.hq)
                    return
                }

                // No existing complete profile found.
                // Stay on onboarding so user can choose codename/team.
                self.setRoute(.onboarding)

            } catch {
                self.onboardingErrorMessage = "Sign in with Apple could not be completed. You can try again or continue without signing in."
            }
        }
    }
    
    func restoreExistingProfileWithApple() {
        guard !isBusy else { return }
        
        onboardingErrorMessage = nil
        isBusy = true
        
        Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            
            do {
                let uid = try await AuthManager.shared.secureCurrentProfileWithApple()
                
                // 🔥 FORCE FULL RE-SYNC
                await syncAuthAndProfile()
                
                guard let remote = try await FirestoreService.shared.fetchProfile(uid: uid) else {
                    self.onboardingErrorMessage = "No existing profile was found for this Apple ID."
                    return // 🚫 DO NOT force onboarding
                }
                
                self.user = Auth.auth().currentUser
                self.profile = remote
                self.attachProfileListenerIfNeeded(uid: uid)
                
                self.clearWelcomeState()
                self.clearBattleDecision()
                self.refreshDailyStreakSnapshot()
                self.refreshLeaderboard()
                await self.syncEntitlementFromStoreKit(force: true)
                
                if self.isOnboardingComplete(remote) {
                    // ✅ CRITICAL: restore latch
                    self.localOnboardingComplete = true
                    self.localCodename = remote.displayName
                    
                    self.setRoute(.hq)
                }
                
            } catch {
                self.onboardingErrorMessage = "Could not restore your profile. Please try again."
                // 🚫 DO NOT force onboarding
            }
        }
    }
    
    // MARK: - Paywall Routing (SSoT)
    
    func ensureGlobalBattleSession() -> GlobalBattleSession {
        if let globalBattleSession {
            return globalBattleSession
        }
        
        let session = GlobalBattleSession()
        globalBattleSession = session
        return session
    }
    
    func clearGlobalBattleSession() {
        globalBattleSession?.reset()
        globalBattleSession = nil
    }
    
    func showProPaywall() {
        setRoute(.proPaywall)
    }
    
    func showStreakPaywall() {
        setRoute(.streakPaywall)
    }
    
    // MARK: - Auth + Profile
    
    private func syncAuthAndProfile() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            _ = try await AuthManager.shared.ensureAuthenticated()
        } catch {
            print("⚠️ Auth ensure failed: \(error)")
        }
        
        let resolvedUser = Auth.auth().currentUser
        self.user = resolvedUser
        
        PushNotificationManager.shared.syncTokenForCurrentUserIfPossible()
        
        let uid: String?
        if let directUID = resolvedUser?.uid, !directUID.isEmpty {
            uid = directUID
        } else {
            uid = await currentUID()
        }
        
        guard let uid, !uid.isEmpty else {
            handleSignedOutState()
            return
        }
        
        startGlobalBattleAdminListenerIfNeeded()
        
        do {
            if let remote = try await FirestoreService.shared.fetchProfile(uid: uid) {
                let remoteName = remote.displayName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()

                let remoteLooksPlaceholder = remoteName.isEmpty || remoteName == "NEW PILOT"

                if localOnboardingComplete && !localCodename.isEmpty && remoteLooksPlaceholder {
                    #if DEBUG
                    print("🛑 [SyncAuth] Ignored placeholder remote profile because local onboarding latch is complete")
                    #endif

                    if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "NEW PILOT" {
                        profile.displayName = localCodename
                    }
                } else {
                    profile = remote
                }

                attachProfileListenerIfNeeded(uid: uid)
                
                // --- THE REFINED GUARD ---
                // 1. Check the local latch first. If we are already complete locally,
                //    DO NOT change the route to onboarding, regardless of what the server says.
                if localOnboardingComplete && !localCodename.isEmpty {
                    if !isOnGlobalBattleSurface && welcomeState == nil {
                        self.route = .hq
                    }
                    await syncEntitlementFromStoreKit(force: false)
                    return // Exit early, routing is already handled by the latch
                }
                
                // 2. If no local latch, check the remote profile
                let complete = isOnboardingComplete(remote)
                
                if complete {
                    localOnboardingComplete = true
                    localCodename = remote.displayName
                    
                    if welcomeState == nil && !isOnGlobalBattleSurface {
                        route = .hq
                    }
                    await syncEntitlementFromStoreKit(force: false)
                } else {
                    clearWelcomeState()
                    if !isOnGlobalBattleSurface {
                        route = .onboarding
                    }
                }
                
            } else {
                // Cloud returned no profile
                detachProfileListener()
                if welcomeState == nil { clearWelcomeState() }
                
                if !isOnGlobalBattleSurface {
                    // Fallback to local latch memory
                    route = localOnboardingComplete ? .hq : .onboarding
                }
            }
        } catch {
            // Network error
            detachProfileListener()
            if welcomeState == nil { clearWelcomeState() }
            
            if !isOnGlobalBattleSurface {
                route = localOnboardingComplete ? .hq : .onboarding
            }
        }
    }
    
    private func startAuthListenerIfNeeded() {
        guard authListener == nil else { return }
        
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            
            Task { @MainActor in
                self.user = user
                
                if user == nil {
                    self.handleSignedOutState()
                } else {
                    self.scheduleEntitlementSync(force: false)
                }
            }
        }
    }
    
    // MARK: - Profile Listener (live updates)
    
    private func attachProfileListenerIfNeeded(uid: String) {
        if listeningUID == uid, profileListener != nil { return }
        
        detachProfileListener()
        listeningUID = uid
        
        profileListener = FirestoreService.shared.listenToProfile(uid: uid) { [weak self] (result: Result<UserProfile, Error>) in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let updated):

                    let name = updated.displayName
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .uppercased()

                    // 🚨 BLOCK server from re-injecting placeholder
                    if name.isEmpty || name == "NEW PILOT" {
                        #if DEBUG
                        print("🛑 [ProfileListener] Ignored placeholder profile from Firestore")
                        #endif
                        return
                    }

                    self.profile = updated
                    // Sync local latch if cloud has data
                    if self.isOnboardingComplete(updated) {
                        self.localOnboardingComplete = true
                        self.localCodename = updated.displayName
                    }
                    
                case .failure(let err):
                    print("⚠️ Profile listener error: \(err)")
                }
            }
        }
    }
    
    private func detachProfileListener() {
        profileListener?.remove()
        profileListener = nil
        listeningUID = nil
    }
    
    private func startGlobalBattleAdminListenerIfNeeded() {
        guard globalBattleAdminListener == nil else { return }
        
        globalBattleAdminListener = FirestoreService.shared.listenToGlobalBattleAdminConfig { [weak self] result in
            guard let self else { return }
            
            Task { @MainActor in
                switch result {
                case .success(let config):
                    self.remoteGlobalBattleEnabled = config?.enabled ?? false
                    
                case .failure(let error):
                    print("⚠️ Global Battle admin listener error: \(error)")
                    self.remoteGlobalBattleEnabled = false
                }
            }
        }
    }
    
    // MARK: - Entitlement Sync
    
    private func scheduleEntitlementSync(force: Bool) {
        entitlementSyncTask?.cancel()
        entitlementSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncEntitlementFromStoreKit(force: force)
        }
    }
    
    private func entitlementFingerprint(
        isPro: Bool,
        proTier: String?,
        proStartedAt: Date?,
        proExpiresAt: Date?,
        trialUsed: Bool,
        trialEndsAt: Date?
    ) -> String {
        let tier = proTier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "-"
        let started = proStartedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        let expires = proExpiresAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        let trialEnd = trialEndsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        
        return [
            isPro ? "1" : "0",
            tier,
            started,
            expires,
            trialUsed ? "1" : "0",
            trialEnd
        ].joined(separator: "|")
    }
    
    func syncEntitlementFromStoreKit(force: Bool = false) async {
        guard let uid = user?.uid.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else {
            return
        }
        
        guard !isEntitlementSyncInFlight else { return }
        isEntitlementSyncInFlight = true
        defer { isEntitlementSyncInFlight = false }
        
        let snapshot = await ProManager.shared.currentEntitlementSnapshot()
        
        let nextFingerprint = entitlementFingerprint(
            isPro: snapshot.isPro,
            proTier: snapshot.proTier,
            proStartedAt: snapshot.proStartedAt,
            proExpiresAt: snapshot.proExpiresAt,
            trialUsed: profile.trialUsed,
            trialEndsAt: profile.trialEndsAt
        )
        
        if !force, lastEntitlementSyncFingerprint == nextFingerprint {
            return
        }
        
        var didChangeLocalProfile = false
        
        if profile.isPro != snapshot.isPro {
            profile.isPro = snapshot.isPro
            didChangeLocalProfile = true
        }
        
        if profile.proTier != snapshot.proTier {
            profile.proTier = snapshot.proTier
            didChangeLocalProfile = true
        }
        
        if profile.proStartedAt != snapshot.proStartedAt {
            profile.proStartedAt = snapshot.proStartedAt
            didChangeLocalProfile = true
        }
        
        if profile.proExpiresAt != snapshot.proExpiresAt {
            profile.proExpiresAt = snapshot.proExpiresAt
            didChangeLocalProfile = true
        }
        
        if didChangeLocalProfile {
            persistProfileFast()
        }
        
        do {
            try await FirestoreService.shared.updateEntitlement(
                uid: uid,
                isPro: snapshot.isPro,
                proTier: snapshot.proTier,
                proStartedAt: snapshot.proStartedAt,
                proExpiresAt: snapshot.proExpiresAt,
                trialUsed: profile.trialUsed,
                trialEndsAt: profile.trialEndsAt
            )
            
            lastEntitlementSyncFingerprint = nextFingerprint
        } catch {
            print("⚠️ Entitlement sync failed: \(error)")
        }
    }
    
    func triggerEntitlementRefreshAfterPurchase() {
        scheduleEntitlementSync(force: true)
    }
    
    func triggerEntitlementRefreshAfterRestore() {
        scheduleEntitlementSync(force: true)
    }
    
    func triggerEntitlementRefreshAfterTransactionUpdate() {
        scheduleEntitlementSync(force: true)
    }
    
    // MARK: - Community Pulse Listener
    
    private func startCommunityPulseListenerIfNeeded() {
        guard communityPulseListener == nil else { return }
        
        communityPulseListener = FirestoreService.db
            .collection("posts")
            .whereField("status", isEqualTo: "approved")
            .order(by: "createdAt", descending: true)
            .limit(to: 8)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                
                if let error {
                    print("⚠️ Community pulse listener error: \(error)")
                    self.isRefreshingCommunityPulse = false
                    self.pendingCommunityRefreshCompletion?()
                    self.pendingCommunityRefreshCompletion = nil
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let nextItems: [CommunityPulseItem] = documents.compactMap { doc in
                    let data = doc.data()
                    
                    let status = (data["status"] as? String ?? "").lowercased()
                    guard status == "approved" else { return nil }
                    
                    let content = (data["content"] as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { return nil }
                    
                    let authorName = (data["authorName"] as? String ?? "Unknown")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let isAI = data["isAI"] as? Bool ?? false
                    let contentType = data["contentType"] as? String
                    let topic = data["topic"] as? String
                    
                    let createdAt: Date = {
                        if let ts = data["createdAt"] as? Timestamp {
                            return ts.dateValue()
                        }
                        if let ts = data["approvedAt"] as? Timestamp {
                            return ts.dateValue()
                        }
                        return Date()
                    }()
                    
                    let title = Self.makePulseTitle(from: content)
                    
                    return CommunityPulseItem(
                        id: doc.documentID,
                        title: title,
                        content: content,
                        authorName: authorName.isEmpty ? "Unknown" : authorName,
                        isAI: isAI,
                        contentType: contentType,
                        topic: topic,
                        createdAt: createdAt
                    )
                }
                
                let previousTopID = self.communityPulse.first?.id
                let nextTopID = nextItems.first?.id
                
                if nextItems.isEmpty {
                    self.installPlaceholderCommunityPulseIfNeeded()
                } else {
                    self.communityPulse = nextItems
                    self.latestAIPulse = nextItems.first(where: { $0.isAI })
                    self.latestCommunityPulse = nextItems.first(where: { !$0.isAI })
                }
                
                if let previousTopID, let nextTopID, previousTopID != nextTopID {
                    self.hasUnreadCommunityPulse = true
                }
                
                self.isRefreshingCommunityPulse = false
                self.communityPulseLastRefreshedAt = Date()
                self.pendingCommunityRefreshCompletion?()
                self.pendingCommunityRefreshCompletion = nil
            }
    }
    
    func markCommunityPulseRead() {
        hasUnreadCommunityPulse = false
    }
    
    func refreshCommunityPulse(completion: (() -> Void)? = nil) {
        isRefreshingCommunityPulse = true
        pendingCommunityRefreshCompletion = completion
        
        communityPulseListener?.remove()
        communityPulseListener = nil
        startCommunityPulseListenerIfNeeded()
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            if self.isRefreshingCommunityPulse {
                self.isRefreshingCommunityPulse = false
                self.pendingCommunityRefreshCompletion?()
                self.pendingCommunityRefreshCompletion = nil
            }
        }
    }
    
    func seedCommunityLaunchContent() {
        guard !isBusy else { return }
        
        isBusy = true
        
        Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            
            do {
                _ = try await AuthManager.shared.ensureAuthenticated()
                
                _ = try await Functions.functions(region: "us-central1")
                    .httpsCallable("seedCommunityLaunchContent")
                    .call([:])
                
                await MainActor.run {
                    self.hasUnreadCommunityPulse = true
                    self.refreshCommunityPulse()
                }
            } catch {
                print("⚠️ seedCommunityLaunchContent failed: \(error)")
            }
        }
    }
    
    var communityPulseRefreshLabel: String {
        guard let communityPulseLastRefreshedAt else { return "LIVE" }
        
        let seconds = Int(Date().timeIntervalSince(communityPulseLastRefreshedAt))
        
        if seconds < 15 { return "JUST NOW" }
        if seconds < 60 { return "\(seconds)S AGO" }
        
        let minutes = max(1, seconds / 60)
        return "\(minutes)M AGO"
    }
    
    private func installPlaceholderCommunityPulseIfNeeded() {
        guard communityPulse.isEmpty else { return }
        
        let now = Date()
        
        let ai = CommunityPulseItem(
            id: "placeholder-ai-pulse",
            title: "AI insights, featured posts, and live community signals will appear here.",
            content: "AI insights, featured posts, and live community signals will appear here.",
            authorName: "Trivia GOAT AI",
            isAI: true,
            contentType: "placeholder",
            topic: "community",
            createdAt: now
        )
        
        let community = CommunityPulseItem(
            id: "placeholder-community-pulse",
            title: "Player activity, discussions, and fresh platform momentum will surface here.",
            content: "Player activity, discussions, and fresh platform momentum will surface here.",
            authorName: "Community",
            isAI: false,
            contentType: "placeholder",
            topic: "community",
            createdAt: now.addingTimeInterval(-1)
        )
        
        communityPulse = [ai, community]
        latestAIPulse = ai
        latestCommunityPulse = community
        hasUnreadCommunityPulse = true
    }
    
    private static func makePulseTitle(from content: String) -> String {
        let normalized = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalized.count <= 88 { return normalized }
        
        let idx = normalized.index(normalized.startIndex, offsetBy: 88)
        return String(normalized[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
    
    // MARK: - Community Comments
    
    func commentsForCommunityPost(_ postID: String) -> [CommunityComment] {
        communityCommentsByPostID[postID] ?? []
    }
    
    func pendingCommunityCommentState(for postID: String) -> PendingCommunityCommentState? {
        pendingCommunityCommentStatesByPostID[postID]
    }
    
    func hasPendingCommunityComment(for postID: String) -> Bool {
        pendingCommunityCommentStatesByPostID[postID]?.isPending == true
    }
    
    func clearPendingCommunityCommentFlag(for postID: String) {
        pendingCommunityCommentStatusListeners[postID]?.remove()
        pendingCommunityCommentStatusListeners[postID] = nil
        pendingCommunityCommentStatesByPostID.removeValue(forKey: postID)
    }
    
    private func startPendingCommunityCommentStatusListener(
        for postID: String,
        commentID: String
    ) {
        pendingCommunityCommentStatusListeners[postID]?.remove()
        pendingCommunityCommentStatusListeners[postID] = nil
        
        let listener = FirestoreService.db
            .collection("posts")
            .document(postID)
            .collection("comments")
            .document(commentID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                
                if let error {
                    print("⚠️ Pending comment status listener error for post \(postID): \(error)")
                    return
                }
                
                guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                    return
                }
                
                let status = (data["status"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                
                switch status {
                case "pending":
                    self.pendingCommunityCommentStatesByPostID[postID] = PendingCommunityCommentState(
                        status: .pending,
                        userFacingReason: nil
                    )
                    
                case "approved":
                    self.pendingCommunityCommentStatesByPostID.removeValue(forKey: postID)
                    self.pendingCommunityCommentStatusListeners[postID]?.remove()
                    self.pendingCommunityCommentStatusListeners[postID] = nil
                    
                case "rejected":
                    let moderationReason = (data["moderationReason"] as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    self.pendingCommunityCommentStatesByPostID[postID] = PendingCommunityCommentState(
                        status: .rejected,
                        userFacingReason: self.userFacingCommunityModerationReason(moderationReason)
                    )
                    
                    self.pendingCommunityCommentStatusListeners[postID]?.remove()
                    self.pendingCommunityCommentStatusListeners[postID] = nil
                    
                default:
                    break
                }
            }
        
        pendingCommunityCommentStatusListeners[postID] = listener
    }
    
    private func userFacingCommunityModerationReason(_ reason: String) -> String {
        let normalized = reason.lowercased()
        
        switch normalized {
        case "policy", "policy_fallback", "restricted_word", "toxicity", "harassment":
            return "That comment did not pass review. Keep it respectful and try again."
            
        case "sexual_content", "adult_content":
            return "That comment did not pass review. Keep discussion appropriate for all players."
            
        case "hate", "hate_speech", "slur":
            return "That comment did not pass review. Hate or abusive language is not allowed."
            
        case "violence", "threat", "self_harm":
            return "That comment did not pass review. Threats or harmful language are not allowed."
            
        case "spam", "scam":
            return "That comment did not pass review. Spam or scam-like content is not allowed."
            
        case "empty":
            return "That comment was empty. Try again with something meaningful."
            
        default:
            return "That comment did not pass review. Edit the wording and try again."
        }
    }
    
    func startCommunityCommentsListener(for postID: String) {
        let cleanedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPostID.isEmpty else { return }
        guard !cleanedPostID.hasPrefix("placeholder-") else {
            communityCommentsByPostID[cleanedPostID] = []
            isRefreshingCommunityCommentsByPostID[cleanedPostID] = false
            return
        }
        
        if communityCommentListeners[cleanedPostID] != nil {
            return
        }
        
        isRefreshingCommunityCommentsByPostID[cleanedPostID] = true
        
        let listener = FirestoreService.db
            .collection("posts")
            .document(cleanedPostID)
            .collection("comments")
            .whereField("status", isEqualTo: "approved")
            .order(by: "createdAt", descending: false)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                
                if let error {
                    print("⚠️ Community comments listener error for post \(cleanedPostID): \(error)")
                    self.isRefreshingCommunityCommentsByPostID[cleanedPostID] = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.communityCommentsByPostID[cleanedPostID] = []
                    self.isRefreshingCommunityCommentsByPostID[cleanedPostID] = false
                    return
                }
                
                let comments: [CommunityComment] = documents.compactMap { doc in
                    let data = doc.data()
                    
                    let status = (data["status"] as? String ?? "approved")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let content = (data["content"] as? String ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { return nil }
                    
                    let authorName = (data["authorName"] as? String ?? "Unknown")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let authorUID = (data["authorUID"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let parentCommentID = (data["parentCommentID"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let isAI = data["isAI"] as? Bool ?? false
                    
                    let createdAt: Date = {
                        if let ts = data["createdAt"] as? Timestamp {
                            return ts.dateValue()
                        }
                        if let ts = data["approvedAt"] as? Timestamp {
                            return ts.dateValue()
                        }
                        return Date()
                    }()
                    
                    return CommunityComment(
                        id: doc.documentID,
                        postID: cleanedPostID,
                        parentCommentID: parentCommentID?.isEmpty == true ? nil : parentCommentID,
                        content: content,
                        authorName: authorName.isEmpty ? "Unknown" : authorName,
                        authorUID: authorUID?.isEmpty == true ? nil : authorUID,
                        isAI: isAI,
                        status: status.isEmpty ? "approved" : status,
                        createdAt: createdAt
                    )
                }
                
                self.communityCommentsByPostID[cleanedPostID] = comments
                self.isRefreshingCommunityCommentsByPostID[cleanedPostID] = false
            }
        
        communityCommentListeners[cleanedPostID] = listener
    }
    
    func stopCommunityCommentsListener(for postID: String) {
        let cleanedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPostID.isEmpty else { return }
        
        communityCommentListeners[cleanedPostID]?.remove()
        communityCommentListeners[cleanedPostID] = nil
        
        pendingCommunityCommentStatusListeners[cleanedPostID]?.remove()
        pendingCommunityCommentStatusListeners[cleanedPostID] = nil
        
        isRefreshingCommunityCommentsByPostID[cleanedPostID] = false
    }
    
    func refreshCommunityComments(for postID: String) {
        let cleanedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedPostID.isEmpty else { return }
        
        stopCommunityCommentsListener(for: cleanedPostID)
        startCommunityCommentsListener(for: cleanedPostID)
    }
    
    func submitCommunityComment(
        postID: String,
        content: String,
        parentCommentID: String? = nil
    ) {
        let cleanedPostID = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedParentID = parentCommentID?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanedPostID.isEmpty else { return }
        guard !cleanedPostID.hasPrefix("placeholder-") else { return }
        guard !cleanedContent.isEmpty else { return }
        guard !isSubmittingCommunityComment else { return }
        
        isSubmittingCommunityComment = true
        pendingCommunityCommentStatesByPostID[cleanedPostID] = PendingCommunityCommentState(
            status: .pending,
            userFacingReason: nil
        )
        
        Task { [weak self] in
            guard let self else { return }
            defer { self.isSubmittingCommunityComment = false }
            
            do {
                _ = try await AuthManager.shared.ensureAuthenticated()
                
                let uid = Auth.auth().currentUser?.uid
                let trimmedDisplayName = self.profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedAuthorName = trimmedDisplayName.isEmpty ? "Pilot" : trimmedDisplayName
                
                var payload: [String: Any] = [
                    "postID": cleanedPostID,
                    "content": cleanedContent,
                    "authorName": resolvedAuthorName,
                    "isAI": false,
                    "status": "pending",
                    "createdAt": FieldValue.serverTimestamp()
                ]
                
                if let uid, !uid.isEmpty {
                    payload["authorUID"] = uid
                }
                
                if let cleanedParentID, !cleanedParentID.isEmpty {
                    payload["parentCommentID"] = cleanedParentID
                }
                
                let ref = try await FirestoreService.db
                    .collection("posts")
                    .document(cleanedPostID)
                    .collection("comments")
                    .addDocument(data: payload)
                
                self.startPendingCommunityCommentStatusListener(
                    for: cleanedPostID,
                    commentID: ref.documentID
                )
                
            } catch {
                self.pendingCommunityCommentStatesByPostID.removeValue(forKey: cleanedPostID)
                print("⚠️ submitCommunityComment failed: \(error)")
            }
        }
    }
    
    // MARK: - Leaderboard Live
    
    private func startLiveLeaderboardIfNeeded() {
        guard !didStartLiveLeaderboard else { return }
        didStartLiveLeaderboard = true
        
        LeaderboardLiveService.shared.start(limit: 25)
        
        LeaderboardLiveService.shared.$topPlayers
            .receive(on: RunLoop.main)
            .assign(to: &$topPlayers)
        
        LeaderboardLiveService.shared.$lastDelta
            .receive(on: RunLoop.main)
            .sink { [weak self] delta in
                self?.rankDelta = delta
            }
            .store(in: &cancellables)
    }
    
    func refreshLeaderboard() {
        leaderboardTask?.cancel()
        leaderboardTask = Task { [weak self] in
            guard let self else { return }
            do {
                let players = try await FirestoreService.shared.fetchLeaderboard(limit: 25)
                await MainActor.run {
                    self.topPlayers = players
                }
            } catch {
                await MainActor.run {
                    self.topPlayers = []
                }
            }
        }
    }
    
    // MARK: - Profile Updates (SSoT)
    
    /// Codename claim is onboarding-authoritative.
    /// This method should not rename a pilot after claim.
    func saveProfile(name: String, avatarStyle: String? = nil, avatarSeed: String? = nil) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleaned.isEmpty else { return }
        
        guard cleaned.caseInsensitiveCompare(current) == .orderedSame else {
            onboardingErrorMessage = "Codename changes are not allowed."
            return
        }
        
        if let avatarStyle {
            profile.avatarStyle = avatarStyle
        }
        
        if let avatarSeed {
            profile.avatarSeed = avatarSeed
        }
        
        persistProfileFast()
    }
    
    func completeOnboarding(name: String, team: TacticalTeam) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            onboardingErrorMessage = "Please enter a codename to continue."
            return
        }

        guard !isBusy else {
            onboardingErrorMessage = "Deployment is already in progress. Please wait."
            return
        }
        
        onboardingErrorMessage = nil
        isBusy = true
        
        Task { [weak self] in
            guard let self else { return }
            
            do {
                let uid = try await AuthManager.shared.ensureAuthenticated()
                guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NSError(
                        domain: "AppState",
                        code: 4101,
                        userInfo: [NSLocalizedDescriptionKey: "Authentication failed. Please try again."]
                    )
                }
                
                self.user = Auth.auth().currentUser
                
                let claimed = try await UsernameClient().claim(username: cleaned)

                guard !claimed.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NSError(
                        domain: "AppState",
                        code: 4102,
                        userInfo: [NSLocalizedDescriptionKey: "That codename couldn’t be deployed. Try a different codename."]
                    )
                }
                
                self.profile.displayName = claimed.username
                self.profile.team = team
                self.onboardingErrorMessage = nil
                
                self.localOnboardingComplete = true
                self.localCodename = claimed.username
                
                self.welcomeState = WelcomeState(
                    playerName: claimed.username,
                    selectedTeam: team,
                    createdAt: Date()
                )
                
                try await self.persistProfileNow(uid: uid)
                
                self.attachProfileListenerIfNeeded(uid: uid)
                self.refreshDailyStreakSnapshot()
                self.refreshLeaderboard()
                
                self.isBusy = false
                self.setRoute(.welcome)
                
            } catch let usernameError as UsernameClientError {
                self.isBusy = false
                self.onboardingErrorMessage = self.message(for: usernameError)
                self.clearWelcomeState()
                self.setRoute(.onboarding)
                
            } catch {
                self.isBusy = false
                
                let nsError = error as NSError
                let rawMessage = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                
                self.onboardingErrorMessage = rawMessage.isEmpty || rawMessage == "The operation couldn’t be completed."
                ? "That codename couldn’t be deployed. Try a different codename."
                : rawMessage
                
                self.clearWelcomeState()
                self.setRoute(.onboarding)
            }
        }
    }
    
    private func message(for error: UsernameClientError) -> String {
        let text = error.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty
        ? "That codename couldn’t be deployed. Try a different codename."
        : text
    }
    
    // MARK: - Routing Helper
    
    func setRoute(_ next: Route) {
        if next != .leaderboard {
            cancelLeaderboardAutoRoute()
        }
        
        clearGlobalBattleSessionIfNeededForNonGlobalRoute(next)
        route = next
        
        if route == .hq || route == .welcome || route == .globalBattle || route == .community || route == .events || route == .eventDetail {
            warmDailyPacksIfNeeded()
        }
    }
    
    func openGlobalBattleIfEnabled() -> Bool {
        guard isGlobalBattleEnabled else { return false }

        guard canAccessGlobalBattle else {
            pendingPostPaywallRoute = .globalBattle
            setRoute(.proPaywall)
            return false
        }

        _ = ensureGlobalBattleSession()
        cancelLeaderboardAutoRoute()
        setRoute(.globalBattle)
        return true
    }
    
    func enterGlobalBattleMatch() {
        guard globalBattleSession != nil else {
            setRoute(.hq)
            return
        }
        
        cancelLeaderboardAutoRoute()
        setRoute(.globalBattleMatch)
    }
    
    func exitGlobalBattleMatchToLobby() {
        guard globalBattleSession != nil else {
            setRoute(.hq)
            return
        }
        
        cancelLeaderboardAutoRoute()
        setRoute(.globalBattle)
    }
    
    func exitGlobalBattleToHQ() {
        cancelLeaderboardAutoRoute()
        clearGlobalBattleSession()
        setRoute(.hq)
    }
    
    // MARK: - Daily Streak Snapshot (read-only for UI)
    
    private func refreshDailyStreakSnapshot() {
        let pro = proEnabled
        StreakManager.shared.reconcile(isPro: pro)
        
        dailyStreakCount = StreakManager.shared.streakCount
        dailyStreakMultiplier = StreakManager.shared.xpMultiplier()
    }
    
    // MARK: - Training (NO TOKEN BURN, 1% PRINCIPLE)
    
    func beginTrainingArenaRun(topic: String) {
        let cleaned = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        
        battleDecision = nil
        clearWelcomeState()
        
        if !proEnabled {
            if TrainingGate.isBlocked(isPro: false) {
                setRoute(.proPaywall)
                return
            }
            
            TrainingGate.consumeOneUseIfNeeded(isPro: false)
            
            let localPack = Array(localFallbackVault.shuffled().prefix(10))
            startSession(questions: localPack, topic: "TRAINING: \(cleaned)")
            return
        }
        
        trivia = TriviaSession.makeNew(from: [], topic: "TRAINING: \(cleaned)")
        streakCount = 0
        setRoute(.mission)
    }
    
    // MARK: - AI Forge (compatibility API for DashboardView)
    
    func startAIGame(topic: String) {
        let cleaned = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        
        battleDecision = nil
        clearWelcomeState()
        isBusy = true
        
        runLoadTask?.cancel()
        runLoadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            
            do {
                _ = try await AuthManager.shared.ensureAuthenticated()
                let qs = try await TriviaPackClient().generatePack(for: cleaned, count: 10)
                self.startSession(questions: qs, topic: cleaned)
            } catch {
                self.startSession(questions: [], topic: cleaned)
            }
        }
    }
    
    // MARK: - Daily Mission (SERVER SSoT)
    
    func startDailyMissionRun() {
        battleDecision = nil
        clearWelcomeState()
        isBusy = true
        
        runLoadTask?.cancel()
        runLoadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }
            
            let uid = await self.currentUID()
            let snap = DailyMission.snapshot(uid: uid, team: self.profile.team)
            
            do {
                _ = try await AuthManager.shared.ensureAuthenticated()
                
                DailyMission.beginMissionRun(uid: uid, team: self.profile.team)
                
                let payload = try await TriviaPackClient()
                    .generateGlobalDailyMissionPayload(dayKey: snap.dayKey)
                
                DailyMission.setServerLockedTopic(dayKey: payload.dayKey, topic: payload.topic)
                
                self.startSession(questions: payload.questions, topic: payload.topic)
            } catch {
                self.startSession(questions: [], topic: snap.topic)
            }
        }
    }
    
    func ensureTriviaRunLoaded() {
        if !trivia.pack.isEmpty || isBusy { return }
        
        let raw = (trivia.topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = raw.uppercased()
        let isTraining = upper.hasPrefix("TRAINING")
        
        isBusy = true
        
        runLoadTask?.cancel()
        runLoadTask = Task { [weak self] in
            guard let self else { return }
            
            defer {
                Task { @MainActor in
                    self.isBusy = false
                    self.runLoadTask = nil
                }
            }
            
            do {
                _ = try await AuthManager.shared.ensureAuthenticated()
                
                if isTraining {
                    let topic = raw
                        .replacingOccurrences(of: "TRAINING:", with: "", options: [.caseInsensitive])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    let resolved = topic.isEmpty ? "General Knowledge" : topic
                    
                    if !self.proEnabled {
                        if TrainingGate.isBlocked(isPro: false) {
                            await MainActor.run {
                                self.setRoute(.proPaywall)
                            }
                            return
                        }
                        
                        let localPack = Array(self.localFallbackVault.shuffled().prefix(10))
                        await MainActor.run {
                            self.startSession(questions: localPack, topic: "TRAINING: \(resolved)")
                        }
                        return
                    }
                    
                    let qs = try await TriviaPackClient().generatePack(for: resolved, count: 10)
                    await MainActor.run {
                        self.startSession(questions: qs, topic: "TRAINING: \(resolved)")
                    }
                    return
                }
                
                let uid = await self.currentUID()
                let snap = DailyMission.snapshot(uid: uid, team: self.profile.team)
                DailyMission.beginMissionRun(uid: uid, team: self.profile.team)
                
                let payload = try await TriviaPackClient()
                    .generateGlobalDailyMissionPayload(dayKey: snap.dayKey)
                
                DailyMission.setServerLockedTopic(dayKey: payload.dayKey, topic: payload.topic)
                await MainActor.run {
                    self.startSession(questions: payload.questions, topic: payload.topic)
                }
                
            } catch {
                if isTraining, !self.proEnabled {
                    if TrainingGate.isBlocked(isPro: false) {
                        await MainActor.run {
                            self.setRoute(.proPaywall)
                        }
                        return
                    }
                    
                    let localPack = Array(self.localFallbackVault.shuffled().prefix(10))
                    let fallbackTopic = raw.isEmpty ? "TRAINING: General Knowledge" : raw
                    await MainActor.run {
                        self.startSession(questions: localPack, topic: fallbackTopic)
                    }
                    return
                }
                
                await MainActor.run {
                    self.startSession(questions: [], topic: raw.isEmpty ? "General Knowledge" : raw)
                }
            }
        }
    }
    
    // MARK: - Session
    
    func startSession(questions: [TriviaQuestion], topic: String) {
        lastRun = nil
        battleDecision = nil
        clearWelcomeState()
        cancelLeaderboardAutoRoute()
        
        trivia = TriviaSession.makeNew(from: questions, topic: topic)
        streakCount = 0
        setRoute(.mission)
    }
    
    func advanceTrivia() {
        if trivia.currentIndex >= trivia.pack.count - 1 {
            finalizeRoundAndRouteToResults()
        } else {
            trivia.next()
        }
    }
    
    // MARK: - Local Training Fallback Vault (SOLO only)
    
    private let localFallbackVault: [TriviaQuestion] = [
        TriviaQuestion(
            prompt: "In computing, what does CPU stand for?",
            choices: [
                "Central Processing Unit",
                "Computer Personal Unit",
                "Core Process Utility",
                "Central Program Upload"
            ],
            correctIndex: 0
        ),
        TriviaQuestion(
            prompt: "Which planet is known as the Red Planet?",
            choices: ["Venus", "Mars", "Jupiter", "Mercury"],
            correctIndex: 1
        ),
        TriviaQuestion(
            prompt: "What is the largest ocean on Earth?",
            choices: ["Atlantic", "Indian", "Pacific", "Arctic"],
            correctIndex: 2
        ),
        TriviaQuestion(
            prompt: "Which language is primarily used for iOS development?",
            choices: ["Swift", "Kotlin", "Ruby", "Go"],
            correctIndex: 0
        ),
        TriviaQuestion(
            prompt: "How many continents are there?",
            choices: ["5", "6", "7", "8"],
            correctIndex: 2
        ),
        TriviaQuestion(
            prompt: "Which gas do plants absorb from the atmosphere?",
            choices: ["Oxygen", "Nitrogen", "Carbon Dioxide", "Hydrogen"],
            correctIndex: 2
        ),
        TriviaQuestion(
            prompt: "What is the capital of Japan?",
            choices: ["Seoul", "Tokyo", "Kyoto", "Osaka"],
            correctIndex: 1
        ),
        TriviaQuestion(
            prompt: "Which element has the symbol 'O'?",
            choices: ["Gold", "Oxygen", "Osmium", "Silver"],
            correctIndex: 1
        ),
        TriviaQuestion(
            prompt: "How many sides does a hexagon have?",
            choices: ["5", "6", "7", "8"],
            correctIndex: 1
        ),
        TriviaQuestion(
            prompt: "What does HTTP stand for?",
            choices: [
                "HyperText Transfer Protocol",
                "High Transfer Text Process",
                "Host Transport Transfer Package",
                "Hyperlink Trace Transfer Program"
            ],
            correctIndex: 0
        )
    ]
    
    // MARK: - FINALIZE (XP + Mission + Streak) — SSoT LOCKED HERE
    
    private func finalizeRoundAndRouteToResults() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            let baseXP = (max(0, self.trivia.score) * 100) + (max(0, self.streakCount) * 10)
            
            let rawTopic = (self.trivia.topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = rawTopic.uppercased()
            let looksTraining = upper.hasPrefix("TRAINING")
            let looksMissionByTopic = upper.hasPrefix("DAILY MISSION")
            
            let isMissionLatched = DailyMission.isActiveMissionRun()
            let isMissionRun = isMissionLatched || looksMissionByTopic
            
            let pro = self.proEnabled
            let uid = await self.currentUID()
            
            StreakManager.shared.reconcile(isPro: pro)
            
            // Keep shared entitlement truth warm after foregrounded/active gameplay sessions.
            self.scheduleEntitlementSync(force: false)
            
            StreakManager.shared.markRunCompleted(uid: uid, isPro: pro)
            
            let dailyCount = StreakManager.shared.streakCount
            let streakMulti = StreakManager.shared.xpMultiplier()
            
            self.dailyStreakCount = dailyCount
            self.dailyStreakMultiplier = streakMulti
            
            var bonusXP = 0
            var didCompleteMission = false
            
            let runKind: LastRun.RunKind = looksTraining ? .training : (isMissionRun ? .dailyMission : .aiForge)
            
            if isMissionRun {
                let team = self.profile.team
                DailyMission.applyDailyResetIfNeeded(uid: uid, team: team)
                
                let snap = DailyMission.snapshot(uid: uid, team: team)
                didCompleteMission = DailyMission.markCompleteIfNeeded(uid: uid, team: team)
                bonusXP = didCompleteMission ? DailyMission.bonusXP : 0
                
                let candidateXP = baseXP + bonusXP
                let finalCandidate = Int(Double(candidateXP) * streakMulti)
                
                let best = MissionBestScoreStore.bestXP(for: snap.dayKey)
                let improvement = max(0, finalCandidate - best)
                
                if finalCandidate > best {
                    MissionBestScoreStore.setBestXP(finalCandidate, for: snap.dayKey)
                }
                
                if improvement > 0 {
                    self.profile.xp += improvement
                }
                
                self.lastRun = LastRun(
                    kind: .dailyMission,
                    topic: rawTopic.isEmpty ? "DAILY MISSION" : rawTopic,
                    scoreCorrect: max(0, self.trivia.score),
                    questionCount: max(0, self.trivia.pack.count),
                    baseXP: baseXP,
                    missionBonusXP: bonusXP,
                    runStreakCount: max(0, self.streakCount),
                    dailyStreakCount: dailyCount,
                    streakMultiplier: streakMulti,
                    finalXP: finalCandidate,
                    didCompleteMissionToday: didCompleteMission,
                    dayKey: snap.dayKey,
                    createdAt: Date()
                )
                
                _ = DailyMission.consumeActiveMissionRunFlag()
                
            } else {
                let finalXP = Int(Double(baseXP) * streakMulti)
                self.profile.xp += finalXP
                
                self.lastRun = LastRun(
                    kind: runKind,
                    topic: rawTopic.isEmpty ? "MISSION" : rawTopic,
                    scoreCorrect: max(0, self.trivia.score),
                    questionCount: max(0, self.trivia.pack.count),
                    baseXP: baseXP,
                    missionBonusXP: 0,
                    runStreakCount: max(0, self.streakCount),
                    dailyStreakCount: dailyCount,
                    streakMultiplier: streakMulti,
                    finalXP: finalXP,
                    didCompleteMissionToday: false,
                    dayKey: nil,
                    createdAt: Date()
                )
            }
            
            self.battleDecision = self.makeBattleDecisionState(from: self.lastRun)
            self.persistProfileFast()
            self.refreshLeaderboard()
            self.setRoute(.results)
        }
    }
    
    private func makeBattleDecisionState(from run: LastRun?) -> BattleDecisionState? {
        guard let run else { return nil }
        
        let outcome: BattleDecisionView.Outcome
        let accuracy = run.questionCount > 0
        ? Double(run.scoreCorrect) / Double(run.questionCount)
        : 0
        
        if accuracy >= 0.80 {
            outcome = .victory
        } else if accuracy >= 0.50 {
            outcome = .draw
        } else {
            outcome = .defeat
        }
        
        let xpText = "+\(max(0, run.finalXP)) XP"
        let scoreText = "\(run.scoreCorrect) / \(max(1, run.questionCount))"
        let scoreLine = "\(scoreText) • \(xpText)"
        
        return BattleDecisionState(
            outcome: outcome,
            opponentName: nil,
            scoreLine: scoreLine
        )
    }
    
    private enum MissionBestScoreStore {
        private static let ud = UserDefaults.standard
        private static let prefix = "tg.dailyMission.bestXP."
        
        static func bestXP(for dayKey: String) -> Int {
            ud.integer(forKey: prefix + dayKey)
        }
        
        static func setBestXP(_ value: Int, for dayKey: String) {
            ud.set(value, forKey: prefix + dayKey)
        }
    }
    
    // MARK: - Persistence
    
    
    
    func listenToRSVPState(for eventID: String) {

        guard let uid = user?.uid else { return }

        if eventRSVPListeners[eventID] != nil {
            return
        }

        let listener = FirestoreService.db
            .collection("events")
            .document(eventID)
            .collection("rsvps")
            .document(uid)
            .addSnapshotListener { [weak self] snapshot, error in

                guard let self else { return }

                if let error {
                    print("⚠️ RSVP listener failed: \(error)")
                    return
                }

                Task { @MainActor in

                    if snapshot?.exists == true {
                        self.RSVPedEventIDs.insert(eventID)
                    } else {
                        self.RSVPedEventIDs.remove(eventID)
                    }
                }
            }

        eventRSVPListeners[eventID] = listener
    }
    
    private func persistProfileNow(uid: String? = nil) async throws {

        // 🚨 CRITICAL: BLOCK placeholder from ever reaching Firestore
        let name = profile.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if name.isEmpty || name == "NEW PILOT" {
            #if DEBUG
            print("🛑 [ProfilePersistNow] BLOCKED placeholder write")
            #endif
            return
        }

        let resolvedUID: String?
        
        if let uid, !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedUID = uid
        } else {
            resolvedUID = await currentUID()
        }
        
        guard let resolvedUID, !resolvedUID.isEmpty else { return }
        
        try await FirestoreService.shared.saveProfile(uid: resolvedUID, profile: profile)
    }
    
    private func persistProfileFast() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            guard let self else { return }
            guard let uid = await self.currentUID() else { return }
            
            // 🚨 HARD BLOCK: NEVER persist placeholder profile
            let name = self.profile.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            
            if name.isEmpty || name == "NEW PILOT" {
#if DEBUG
                print("🛑 [ProfilePersist] BLOCKED placeholder write to Firestore")
#endif
                return
            }
            
            do {
                try await FirestoreService.shared.saveProfile(uid: uid, profile: self.profile)
            } catch {
                print("⚠️ persistProfileFast failed: \(error)")
            }
        }
    }
}
