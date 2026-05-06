//
//  AppState.swift
//  TriviaGoatNextGen
//
//  SINGLE SOURCE OF TRUTH
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

    @Published var route: Route = .landing

    // MARK: - Core State

    @Published private(set) var user: User? = nil
    @Published var isBusy: Bool = false
    @Published var profile: UserProfile = .placeholder
    @Published var trivia: TriviaSession = .idle
    @Published private(set) var hasResolvedInitialRoute: Bool = false

    @Published private(set) var topPlayers: [UserProfile] = []
    @Published var rankDelta: LeaderboardLiveService.RankDelta? = nil
    @Published var onboardingErrorMessage: String? = nil
    @Published var globalBattleSession: GlobalBattleSession? = nil

    @Published private(set) var isProfileSecuredWithApple: Bool = false
    @Published var showSecureProfilePrompt: Bool = false
    @Published var secureProfilePromptMessage: String? = nil

    /// In-run streak (combo) used by TriviaGameView
    @Published var streakCount: Int = 0

    /// Daily streak system snapshot (days + multiplier)
    @Published private(set) var dailyStreakCount: Int = 0
    @Published private(set) var dailyStreakMultiplier: Double = 1.0

#if DEBUG
    @AppStorage("tg.debug.globalBattleEnabled") private var debugGlobalBattleEnabled: Bool = true
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

    private var pendingCommunityRefreshCompletion: (() -> Void)? = nil
    @Published private(set) var communityPulseLastRefreshedAt: Date? = nil

    private var communityPulseListener: ListenerRegistration?
    private var communityCommentListeners: [String: ListenerRegistration] = [:]
    private var pendingCommunityCommentStatusListeners: [String: ListenerRegistration] = [:]
    private var globalBattleAdminListener: ListenerRegistration?

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

    // MARK: - Task Handles

    private var syncTask: Task<Void, Never>?
    private var runLoadTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var leaderboardTask: Task<Void, Never>?
    private var leaderboardAutoRouteTask: Task<Void, Never>?
    private var entitlementSyncTask: Task<Void, Never>?

    // MARK: - Entitlement Sync State

    private var lastEntitlementSyncFingerprint: String?
    private var isEntitlementSyncInFlight: Bool = false
    private var onboardingCompletionInFlight: Bool = false

    // MARK: - Run Snapshot

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

    // MARK: - Local Rewards Ledger

    struct RewardsLedger: Equatable, Codable {
        var totalClaims: Int = 0
        var totalXPDeposited: Int = 0

        var lastClaimedAt: Date? = nil
        var lastClaimedXP: Int = 0
        var lastRankCheckpoint: String = ""
        var lastStreakSaved: Bool = false

        var lastClaimKey: String = ""
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

    // MARK: - Daily Trivia Pack Warmup

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
            updated.lastReceiptKey = claimKey
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
        return ProManager.shared.isPro
#else
        return ProManager.shared.isPro
#endif
    }

    var isGlobalBattleEnabled: Bool {
        true
    }

    var canAccessGlobalBattle: Bool {
        isGlobalBattleEnabled
    }

    // MARK: - Lifecycle

    init() {
        var loadedRewards = RewardsLedgerStore.load()
        loadedRewards.lastClaimKey = ""

        rewards = loadedRewards
        RewardsLedgerStore.save(loadedRewards)
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

    private func refreshAuthSecuritySnapshot() {
        Task { @MainActor in
            let isAnonymous = await AuthManager.shared.isAnonymousUser()
            isProfileSecuredWithApple = !isAnonymous
        }
    }

    func dismissSecureProfilePrompt() {
        showSecureProfilePrompt = false
        secureProfilePromptMessage = nil
    }

    func promptToSecureProfile(message: String? = nil) {
        secureProfilePromptMessage = message ?? "Sign in with Apple to protect your XP, leaderboard rank, and Global Battle access."
        showSecureProfilePrompt = true
    }

    func secureCurrentProfileWithApple() {
        guard !isBusy else { return }

        onboardingErrorMessage = nil
        isBusy = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }

            do {
                let uid = try await AuthManager.shared.secureCurrentProfileWithApple()

                self.user = Auth.auth().currentUser
                self.isProfileSecuredWithApple = true
                self.showSecureProfilePrompt = false
                self.secureProfilePromptMessage = nil

#if DEBUG
                print("🍎 [SecureProfile] linked/restored uid=\(uid)")
                print("🍎 [SecureProfile] firebaseUID=\(Auth.auth().currentUser?.uid ?? "nil")")
                print("🍎 [SecureProfile] isAnonymous=\(Auth.auth().currentUser?.isAnonymous.description ?? "nil")")
#endif

                if let remote = try await FirestoreService.shared.fetchProfile(uid: uid) {
#if DEBUG
                    print("🍎 [SecureProfile] Firestore profile FOUND for uid=\(uid)")
#endif
                    self.profile = remote
                    self.attachProfileListenerIfNeeded(uid: uid)
                } else {
#if DEBUG
                    print("🍎 [SecureProfile] Firestore profile MISSING — saving current local profile for uid=\(uid)")
#endif
                    try await self.persistProfileNow(uid: uid)
                    self.attachProfileListenerIfNeeded(uid: uid)
                }

                self.refreshDailyStreakSnapshot()
                self.refreshLeaderboard()
                await self.syncEntitlementFromStoreKit(force: true)

                if self.proEnabled {
                    _ = self.ensureGlobalBattleSession()
                    self.cancelLeaderboardAutoRoute()
                    self.setRoute(.globalBattle)
                } else {
                    self.setRoute(.proPaywall)
                }

            } catch {
#if DEBUG
                print("🚨 [SecureProfile] failed: \(error)")
#endif
                self.onboardingErrorMessage = "Could not secure your profile with Apple. Please try again."
                self.promptToSecureProfile(
                    message: "Apple sign-in did not complete. Your current progress is still playable, but not protected yet."
                )
            }
        }
    }

#if DEBUG
    private func gbDebug(_ message: String) {
        print("🌍 [GlobalBattleGate] \(message)")
    }
#else
    private func gbDebug(_ message: String) { }
#endif

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

    func restoreExistingProfileWithApple() {
        guard !isBusy else { return }

        onboardingErrorMessage = nil
        isBusy = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isBusy = false }

            do {
                let uid = try await AuthManager.shared.secureCurrentProfileWithApple()

                guard !uid.isEmpty else {
                    self.onboardingErrorMessage = "Sign in failed. Please try again."
                    self.setRoute(.onboarding)
                    return
                }

                guard let remote = try await FirestoreService.shared.fetchProfile(uid: uid) else {
                    self.onboardingErrorMessage = "No existing profile was found for this Apple ID."
                    self.setRoute(.onboarding)
                    return
                }

                self.user = Auth.auth().currentUser
                self.isProfileSecuredWithApple = true
                self.profile = remote
                self.attachProfileListenerIfNeeded(uid: uid)
                self.clearWelcomeState()
                self.clearBattleDecision()
                self.refreshDailyStreakSnapshot()

                if self.isOnboardingComplete(remote) {
                    self.refreshLeaderboard()
                    await self.syncEntitlementFromStoreKit(force: true)
                    self.setRoute(.hq)
                } else {
                    self.onboardingErrorMessage = nil
                    self.setRoute(.onboarding)
                }

            } catch {
                self.onboardingErrorMessage = "Could not restore your profile. Please try again."
                self.setRoute(.onboarding)
            }
        }
    }

    private var isOnGlobalBattleSurface: Bool {
        switch route {
        case .globalBattle, .globalBattleMatch:
            return true
        default:
            return false
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
        let placeholderName = UserProfile.placeholder.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return false }

        let upper = name.uppercased()

        let blockedPlaceholders: Set<String> = [
            "",
            "NEW PILOT",
            "PILOT",
            "PLAYER",
            "UNCLAIMED PILOT"
        ]

        if blockedPlaceholders.contains(upper) {
            return false
        }

        if !placeholderName.isEmpty,
           name.caseInsensitiveCompare(placeholderName) == .orderedSame {
            return false
        }

        return true
    }

    private func isReservedPlaceholderCodename(_ value: String) -> Bool {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let blocked: Set<String> = [
            "",
            "NEW PILOT",
            "PILOT",
            "PLAYER",
            "UNCLAIMED PILOT"
        ]

        return blocked.contains(name)
    }

    func cancelLeaderboardAutoRoute() {
        leaderboardAutoRouteTask?.cancel()
        leaderboardAutoRouteTask = nil
    }

    // MARK: - Boot

    func bootIfNeeded() {
        guard !didBoot else { return }
        didBoot = true

        route = .landing
        startAuthListenerIfNeeded()
        startLiveLeaderboardIfNeeded()
        startCommunityPulseListenerIfNeeded()
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

    // MARK: - Results Routing

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

    // MARK: - Paywall Routing

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

    func openGlobalBattlePaywall() {
        setRoute(.proPaywall)
    }

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
        self.refreshAuthSecuritySnapshot()

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
                profile = remote
                attachProfileListenerIfNeeded(uid: uid)

                if isOnboardingComplete(remote) {
                    if route != .welcome {
                        clearWelcomeState()
                    }

                    if !isOnGlobalBattleSurface && route != .welcome {
                        route = .hq
                    }

                    await syncEntitlementFromStoreKit(force: false)
                } else {
                    if onboardingCompletionInFlight || route == .welcome {
                        return
                    }

                    clearWelcomeState()

                    if !isOnGlobalBattleSurface {
                        route = .onboarding
                    }
                }
            } else {
                detachProfileListener()

                if onboardingCompletionInFlight || route == .welcome {
                    return
                }

                clearWelcomeState()

                if !isOnGlobalBattleSurface {
                    route = .onboarding
                }
            }
        } catch {
            detachProfileListener()

            if onboardingCompletionInFlight || route == .welcome {
                return
            }

            clearWelcomeState()

            if !isOnGlobalBattleSurface {
                route = .onboarding
            }
        }
    }

    private func startAuthListenerIfNeeded() {
        guard authListener == nil else { return }

        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }

            Task { @MainActor in
                self.user = user
                self.refreshAuthSecuritySnapshot()

                if user == nil {
                    self.handleSignedOutState()
                } else {
                    self.scheduleEntitlementSync(force: false)
                }
            }
        }
    }

    // MARK: - Profile Listener

    private func attachProfileListenerIfNeeded(uid: String) {
        if listeningUID == uid, profileListener != nil { return }

        detachProfileListener()
        listeningUID = uid

        profileListener = FirestoreService.shared.listenToProfile(uid: uid) { [weak self] (result: Result<UserProfile, Error>) in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let updated):
                    self.profile = updated

                    if self.isOnboardingComplete(updated),
                       self.route == .onboarding,
                       !self.onboardingCompletionInFlight {
                        self.clearWelcomeState()
                        self.route = .hq
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

    // MARK: - Routing Helper

    func setRoute(_ next: Route) {
        if next != .leaderboard {
            cancelLeaderboardAutoRoute()
        }

        clearGlobalBattleSessionIfNeededForNonGlobalRoute(next)
        route = next

        if route == .hq || route == .welcome || route == .globalBattle || route == .community {
            warmDailyPacksIfNeeded()
        }
    }

    func openGlobalBattleIfEnabled() -> Bool {
        gbDebug("""
        TAP
        route=\(route)
        isGlobalBattleEnabled=\(isGlobalBattleEnabled)
        canAccessGlobalBattle=\(canAccessGlobalBattle)
        proEnabled=\(proEnabled)
        proManagerIsPro=\(ProManager.shared.isPro)
        isProfileSecuredWithApple=\(isProfileSecuredWithApple)
        userUID=\(user?.uid ?? "nil")
        firebaseUID=\(Auth.auth().currentUser?.uid ?? "nil")
        isAnonymous=\(Auth.auth().currentUser?.isAnonymous.description ?? "nil")
        remoteGlobalBattleEnabled=\(remoteGlobalBattleEnabled)
        """)

        guard isGlobalBattleEnabled else {
            gbDebug("BLOCKED: feature disabled")
            setRoute(.hq)
            return true
        }

        guard isProfileSecuredWithApple else {
            gbDebug("BLOCKED: profile not secured with Apple -> showing secure prompt")
            promptToSecureProfile(
                message: "Secure your profile with Apple before entering Global Battle so your rank, XP, and battle history stay protected."
            )
            return true
        }

        guard proEnabled else {
            gbDebug("BLOCKED: secured but not Pro -> routing proPaywall")
            setRoute(.proPaywall)
            return true
        }

        gbDebug("PASS: opening Global Battle lobby")

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

    // MARK: - Daily Streak Snapshot

    private func refreshDailyStreakSnapshot() {
        let pro = proEnabled
        StreakManager.shared.reconcile(isPro: pro)

        dailyStreakCount = StreakManager.shared.streakCount
        dailyStreakMultiplier = StreakManager.shared.xpMultiplier()
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

    // MARK: - Profile Updates

    func saveProfile(name: String, avatarStyle: String? = nil, avatarSeed: String? = nil) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return }

        let onboardingIsStillOpen = !isOnboardingComplete(profile)
        guard onboardingIsStillOpen || cleaned.caseInsensitiveCompare(current) == .orderedSame else {
            onboardingErrorMessage = "Codename changes are not allowed."
            return
        }

        profile.displayName = cleaned

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
        guard !cleaned.isEmpty else { return }
        guard !onboardingCompletionInFlight else { return }

        onboardingErrorMessage = nil
        onboardingCompletionInFlight = true
        isBusy = true

        Task { [weak self] in
            guard let self else { return }

            defer {
                self.isBusy = false
                self.onboardingCompletionInFlight = false
            }

            do {
                let uid = try await AuthManager.shared.ensureAuthenticated()
                guard !uid.isEmpty else {
                    self.onboardingErrorMessage = "Authentication failed. Please try again."
                    self.clearWelcomeState()
                    self.setRoute(.onboarding)
                    return
                }

                self.user = Auth.auth().currentUser

                let claimed = try await UsernameClient().claim(username: cleaned)

                self.profile.displayName = claimed.username
                self.profile.team = team
                self.onboardingErrorMessage = nil

                self.welcomeState = WelcomeState(
                    playerName: claimed.username,
                    selectedTeam: team,
                    createdAt: Date()
                )

                try await self.persistProfileNow(uid: uid)

                self.attachProfileListenerIfNeeded(uid: uid)
                self.refreshDailyStreakSnapshot()
                self.refreshLeaderboard()

                self.route = .welcome
                self.warmDailyPacksIfNeeded()

            } catch {
                let nsError = error as NSError
                let rawMessage = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

    #if DEBUG
                if nsError.domain == FunctionsErrorDomain {
                    print("🚨 Functions code=\(FunctionsErrorCode(rawValue: nsError.code)?.rawValue ?? nsError.code)")
                    print("🚨 Functions details=\(nsError.userInfo[FunctionsErrorDetailsKey] ?? "nil")")
                }

                print("🚨 [Onboarding] Username claim failed")
                print("🚨 domain=\(nsError.domain)")
                print("🚨 code=\(nsError.code)")
                print("🚨 message=\(rawMessage)")
                print("🚨 userInfo=\(nsError.userInfo)")
    #endif

                self.onboardingErrorMessage = self.userFacingUsernameErrorMessage(from: error)
                self.clearWelcomeState()
                self.setRoute(.onboarding)
            }
        }
    }
    private func message(for error: UsernameClientError) -> String {
        let text = error.errorDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let normalized = text.lowercased()

        if normalized.contains("too many attempts") ||
            normalized.contains("rate") ||
            normalized.contains("limit") ||
            normalized.contains("wait") {
            return "Too many codename attempts. Please wait a moment and try again."
        }

        if normalized.contains("taken") ||
            normalized.contains("already") ||
            normalized.contains("exists") ||
            normalized.contains("unavailable") {
            return "That codename is already taken. Choose another."
        }

        if normalized.contains("reserved") ||
            normalized.contains("not allowed") ||
            normalized.contains("blocked") {
            return "That codename is not allowed. Choose another."
        }

        if normalized.contains("inappropriate") ||
            normalized.contains("moderation") ||
            normalized.contains("policy") {
            return "That codename did not pass review. Choose another."
        }

        return text.isEmpty
            ? "That codename couldn’t be deployed. Try a different codename."
            : text
    }

    private func userFacingUsernameErrorMessage(from error: Error) -> String {
        let nsError = error as NSError

        let candidates: [String] = [
            nsError.localizedDescription,
            nsError.userInfo["message"] as? String,
            nsError.userInfo["details"] as? String,
            nsError.userInfo["reason"] as? String,
            nsError.userInfo["error"] as? String
        ].compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let combined = candidates.joined(separator: " ").lowercased()

        if combined.contains("already") ||
            combined.contains("taken") ||
            combined.contains("exists") ||
            combined.contains("unavailable") ||
            combined.contains("duplicate") {
            return "That codename is already taken. Choose another."
        }

        if combined.contains("reserved") ||
            combined.contains("blocked") ||
            combined.contains("not allowed") {
            return "That codename is not allowed. Choose another."
        }

        if combined.contains("moderation") ||
            combined.contains("policy") ||
            combined.contains("inappropriate") ||
            combined.contains("unsafe") {
            return "That codename did not pass review. Choose another."
        }

#if DEBUG
        if let first = candidates.first, !first.isEmpty {
            return "DEBUG: \(first)"
        }
#endif

        return "Unable to deploy codename right now."
    }

    // MARK: - Training

    func beginTrainingArenaRun(topic: String) {
        let cleaned = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        battleDecision = nil
        clearWelcomeState()

        if !proEnabled {
            let gate = TrainingGate.snapshot(isPro: false)

            if gate.remainingToday <= 0 {
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

    // MARK: - AI Forge

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

    // MARK: - Daily Mission

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

    // MARK: - Local Training Fallback Vault

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

    // MARK: - Finalize

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

    // MARK: - Community Pulse Listener

    private func startCommunityPulseListenerIfNeeded() {
        guard communityPulseListener == nil else { return }

        communityPulseListener = Firestore.firestore()
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

        let listener = Firestore.firestore()
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

        let listener = Firestore.firestore()
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

                let ref = try await Firestore.firestore()
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

    // MARK: - Persistence

    private func persistProfileFast() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            guard let self else { return }
            guard let uid = await self.currentUID() else { return }

            do {
                try await FirestoreService.shared.saveProfile(uid: uid, profile: self.profile)
            } catch {
                // intentionally silent; gameplay must not block on persistence
            }
        }
    }

    private func persistProfileNow(uid: String? = nil) async throws {
        let resolvedUID: String?

        if let uid, !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedUID = uid
        } else {
            resolvedUID = await currentUID()
        }

        guard let resolvedUID, !resolvedUID.isEmpty else { return }

        try await FirestoreService.shared.saveProfile(uid: resolvedUID, profile: profile)
    }
}
