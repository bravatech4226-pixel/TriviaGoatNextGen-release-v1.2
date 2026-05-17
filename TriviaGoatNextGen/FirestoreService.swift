//
//  FirestoreService.swift
//  TriviaGoatNextGen
//
//  Production-ready shared Firestore service for iOS + Web-aligned platform wiring.
//  - Global Battle runtime + lobby support
//  - adminConfig/platformSettings feature flag sync
//  - legacy globalBattle config fallback
//  - public site config / blog / stats / leaderboard support
//  - Swift 6-safe closure capture semantics
//

import Foundation
import FirebaseFirestore

struct GlobalBattleLobby: Codable, Identifiable {
    var id: String?

    var code: String
    var hostUID: String
    var topic: String
    var dayKey: String

    var status: String
    var maxPlayers: Int
    var questionCount: Int
    var roundIndex: Int

    var createdAt: Date?
    var updatedAt: Date?
}

struct GlobalBattleParticipant: Codable, Identifiable {
    var id: String?

    var uid: String
    var displayName: String
    var score: Int
    var isHost: Bool
    var joinedAt: Date?
}

struct GlobalBattleAdminConfig: Codable, Equatable {
    var enabled: Bool
    var updatedAt: Date?
}

struct PlatformConfigSnapshot: Equatable {
    var featureFlags: [String: Bool]
    var version: Int
    var updatedBy: String?
    var updatedAt: Date?

    var globalBattleEnabled: Bool {
        featureFlags["global_battle_live"] ?? false
    }

    var communityLaunchSurfaceEnabled: Bool {
        featureFlags["community_launch_surface"] ?? false
    }

    var eventsPublicAccessEnabled: Bool {
        featureFlags["events_public_access"] ?? false
    }

    var proPaywallEntryEnabled: Bool {
        featureFlags["pro_paywall_entry"] ?? false
    }

    var sponsorRotationSurfaceEnabled: Bool {
        featureFlags["sponsor_rotation_surface"] ?? false
    }

    var publicStatsSyncEnabled: Bool {
        featureFlags["public_stats_sync"] ?? false
    }
}

// MARK: - Global Battle Runtime Models

struct GlobalBattleLiveQuestion: Codable, Equatable {
    var key: String
    var prompt: String
    var choices: [String]
    var correctIndex: Int
}

struct GlobalBattleRuntimeFinishState: Codable, Equatable {
    var type: String
    var winnerUID: String?
    var disqualifiedUID: String?
    var disqualifiedUIDs: [String]
    var duringTieBreak: Bool
}

struct GlobalBattleRuntimeState: Codable, Identifiable, Equatable {
    var id: String?

    var lobbyId: String
    var phase: String
    var roundIndex: Int
    var question: GlobalBattleLiveQuestion?

    var roundDurationSeconds: Int
    var extraTieBreakRounds: Int

    var deadlineAt: Date?
    var revealedAt: Date?

    var finish: GlobalBattleRuntimeFinishState?

    var hostAdvancedAt: Date?
    var updatedAt: Date?
}

struct GlobalBattleAnswerSubmission: Codable, Identifiable, Equatable {
    var id: String?

    var uid: String
    var displayName: String
    var roundIndex: Int
    var choiceIndex: Int
    var isCorrect: Bool?
    var submittedAt: Date?
}

// MARK: - Web Admin / Public WWW Models

struct AdminUserRole: Codable, Equatable {
    var uid: String
    var email: String?
    var displayName: String?
    var isSuperAdmin: Bool
    var canManageBlog: Bool
    var canManageStats: Bool
    var canManageUsers: Bool
    var updatedAt: Date?
}

struct WebBlogPost: Codable, Identifiable, Equatable {
    var id: String?

    var slug: String
    var title: String
    var excerpt: String
    var contentHTML: String

    var coverImageURL: String?
    var authorName: String?

    var isPublished: Bool
    var isFeatured: Bool
    var tags: [String]

    var publishedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
}

struct PublicSiteStat: Codable, Identifiable, Equatable {
    var id: String?

    var key: String
    var label: String
    var valueText: String
    var sortOrder: Int
    var isVisible: Bool
    var updatedAt: Date?
}

struct PublicLeaderboardEntry: Codable, Identifiable, Equatable {
    var id: String?

    var uid: String
    var displayName: String
    var xp: Int
    var rank: Int
    var badge: String?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case uid
        case displayName
        case xp
        case score
        case rank
        case badge
        case updatedAt
    }

    init(
        id: String? = nil,
        uid: String,
        displayName: String,
        xp: Int,
        rank: Int,
        badge: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.uid = uid
        self.displayName = displayName
        self.xp = xp
        self.rank = rank
        self.badge = badge
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        uid = try container.decodeIfPresent(String.self, forKey: .uid) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "PILOT"

        let decodedXP = try container.decodeIfPresent(Int.self, forKey: .xp)
        let decodedScore = try container.decodeIfPresent(Int.self, forKey: .score)
        xp = decodedXP ?? decodedScore ?? 0

        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 999
        badge = try container.decodeIfPresent(String.self, forKey: .badge)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(uid, forKey: .uid)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(xp, forKey: .xp)
        try container.encode(xp, forKey: .score)
        try container.encode(rank, forKey: .rank)
        try container.encodeIfPresent(badge, forKey: .badge)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct AdminDashboardSnapshot: Equatable {
    var totalUsers: Int
    var publishedBlogPosts: Int
    var visiblePublicStats: Int
    var liveGlobalBattles: Int
}

struct PublicSiteConfig: Codable, Equatable {
    var homepageHeadline: String?
    var homepageSubheadline: String?
    var appStoreURL: String?
    var blogEnabled: Bool
    var statsEnabled: Bool
    var leaderboardEnabled: Bool
    var updatedAt: Date?
}

struct SponsorPlacementPayload: Equatable {
    let placementID: String
    let campaignID: String?
    let sponsorID: String?

    let sponsorName: String
    let headline: String
    let subheadline: String?
    let ctaLabel: String?
    let destinationURL: String?
    let logoURL: String?
    let placementType: String?
    let slotKey: String?
}

final class FirestoreService {
    
    static let shared = FirestoreService()

    static var db: Firestore {
        Firestore.firestore()
    }
    
    private enum DebugLog {
        static let sponsorVerbose = false
        static let telemetryErrors = true
    }
    
    private let db = Firestore.firestore()
    
    
    private enum Collections {
        static let users = "users"
        
        // Telemetry
        static let telemetry = "telemetry"
        static let events = "events"
        static let dailyMission = "dailyMission"
        static let payloads = "payloads"
        
        // Global Battle
        static let globalBattles = "globalBattles"
        static let participants = "participants"
        static let usedQuestionKeys = "usedQuestionKeys"
        static let runtime = "runtime"
        static let liveState = "liveState"
        static let answers = "answers"
        static let rounds = "rounds"
        
        // Admin / Config
        static let admin = "admin"
        static let config = "config"
        static let adminConfig = "adminConfig"
        static let globalBattle = "globalBattle"
        static let platformSettings = "platformSettings"
        
        // Web / Public WWW
        static let roles = "roles"
        static let website = "website"
        static let publicConfig = "publicConfig"
        static let blog = "blog"
        static let posts = "posts"
        static let publicStats = "publicStats"
        static let leaderboard = "leaderboard"
        static let snapshots = "snapshots"
        static let monetization = "monetization"
        static let globalBattleSponsorPlacement = "globalBattleSponsorPlacement"
        
        // Monetization
        static let sponsors = "sponsors"
        static let campaigns = "campaigns"
        static let placements = "placements"
    }
    
    private init() {}
    
    // MARK: - Shared Refs
    
    private func userRef(_ uid: String) -> DocumentReference {
        db.collection(Collections.users).document(uid)
    }
    
    private func lobbyRef(_ lobbyId: String) -> DocumentReference {
        db.collection(Collections.globalBattles).document(lobbyId)
    }
    
    private func runtimeRef(_ lobbyId: String) -> DocumentReference {
        lobbyRef(lobbyId)
            .collection(Collections.runtime)
            .document(Collections.liveState)
    }
    
    private func roundRef(_ lobbyId: String, roundIndex: Int) -> DocumentReference {
        lobbyRef(lobbyId)
            .collection(Collections.rounds)
            .document("round_\(max(1, roundIndex))")
    }
    
    private func answersRef(_ lobbyId: String, roundIndex: Int) -> CollectionReference {
        roundRef(lobbyId, roundIndex: roundIndex)
            .collection(Collections.answers)
    }
    
    private func usedKeysRef(_ lobbyId: String) -> CollectionReference {
        lobbyRef(lobbyId)
            .collection(Collections.usedQuestionKeys)
    }
    
    private func adminRoleRef(_ uid: String) -> DocumentReference {
        db.collection(Collections.admin)
            .document(Collections.roles)
            .collection(Collections.roles)
            .document(uid)
    }
    
    private func legacyGlobalBattleAdminConfigRef() -> DocumentReference {
        db.collection(Collections.admin)
            .document(Collections.config)
            .collection(Collections.config)
            .document(Collections.globalBattle)
    }
    
    private func platformSettingsRef() -> DocumentReference {
        db.collection(Collections.adminConfig)
            .document(Collections.platformSettings)
    }
    
    private func legacyPlatformSettingsRef() -> DocumentReference {
        db.collection(Collections.admin)
            .document(Collections.config)
            .collection(Collections.config)
            .document(Collections.platformSettings)
    }
    
    private func websiteRootRef() -> DocumentReference {
        db.collection(Collections.website).document(Collections.website)
    }
    
    private func publicConfigRef() -> DocumentReference {
        websiteRootRef()
            .collection(Collections.publicConfig)
            .document(Collections.publicConfig)
    }
    
    private func publicGlobalBattleSponsorPlacementRef() -> DocumentReference {
        websiteRootRef()
            .collection(Collections.publicConfig)
            .document(Collections.monetization)
            .collection(Collections.publicConfig)
            .document(Collections.globalBattleSponsorPlacement)
    }
    
    private func blogPostsRef() -> CollectionReference {
        websiteRootRef()
            .collection(Collections.blog)
            .document(Collections.posts)
            .collection(Collections.posts)
    }
    
    private func blogPostRef(_ postId: String) -> DocumentReference {
        blogPostsRef().document(postId)
    }
    
    private func publicStatsRef() -> CollectionReference {
        websiteRootRef()
            .collection(Collections.publicStats)
            .document(Collections.publicStats)
            .collection(Collections.publicStats)
    }
    
    private func publicStatRef(_ statId: String) -> DocumentReference {
        publicStatsRef().document(statId)
    }
    
    private func publicLeaderboardRef() -> CollectionReference {
        websiteRootRef()
            .collection(Collections.leaderboard)
            .document(Collections.snapshots)
            .collection(Collections.snapshots)
    }
    
    // MARK: - Helpers
    
    private func cleanedNonEmpty(_ value: String, code: Int, message: String) throws -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw NSError(
                domain: "FirestoreService",
                code: code,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return cleaned
    }
    
    private func cleanOptionalString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
    
    private func trimmedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
    
    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String, let parsed = Int(value) { return parsed }
        return nil
    }
    
    private func dateValue(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp {
            return ts.dateValue()
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
    
    private func decodeDocument<T: Decodable>(
        _ snapshot: DocumentSnapshot,
        as type: T.Type
    ) throws -> T {
        guard let raw = snapshot.data() else {
            throw NSError(
                domain: "FirestoreService",
                code: 9990,
                userInfo: [NSLocalizedDescriptionKey: "Document data is missing."]
            )
        }
        
        let normalizedObject = normalizeFirestoreJSONValue(raw)
        
        guard JSONSerialization.isValidJSONObject(normalizedObject) else {
            throw NSError(
                domain: "FirestoreService",
                code: 9991,
                userInfo: [NSLocalizedDescriptionKey: "Invalid JSON after normalization."]
            )
        }
        
        let data = try JSONSerialization.data(withJSONObject: normalizedObject, options: [])
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        
        return try decoder.decode(T.self, from: data)
    }
    
    private func normalizeFirestoreJSONValue(_ value: Any) -> Any {
        switch value {
            
        case let timestamp as Timestamp:
            return timestamp.dateValue().timeIntervalSince1970
            
        case let date as Date:
            return date.timeIntervalSince1970
            
        case let dict as [String: Any]:
            var newDict: [String: Any] = [:]
            for (key, val) in dict {
                newDict[key] = normalizeFirestoreJSONValue(val)
            }
            return newDict
            
        case let array as [Any]:
            return array.map { normalizeFirestoreJSONValue($0) }
            
        case let number as NSNumber:
            return number
            
        case let string as String:
            return string
            
        case let bool as Bool:
            return bool
            
        case _ as NSNull:
            return NSNull()
            
        default:
            return String(describing: value)
        }
    }
    
    // MARK: - Profile Fetch
    
    func fetchProfile(uid: String) async throws -> UserProfile? {
        let cleanedUID = try cleanedNonEmpty(
            uid,
            code: 9001,
            message: "User UID is empty."
        )
        
        let snapshot = try await userRef(cleanedUID).getDocument()
        guard snapshot.exists else { return nil }
        
        return try decodeDocument(snapshot, as: UserProfile.self)
    }
    
    // MARK: - Real-Time Profile Listener
    
    func listenToProfile(
        uid: String,
        completion: @escaping (Result<UserProfile, Error>) -> Void
    ) -> ListenerRegistration {
        let cleanedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let docRef = userRef(cleanedUID)
        
        return docRef.addSnapshotListener { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }
            
            guard let snapshot, snapshot.exists else { return }
            
            do {
                let profile = try self.decodeDocument(snapshot, as: UserProfile.self)
                completion(.success(profile))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Profile Save
    
    func saveProfile(uid: String, profile: UserProfile) async throws {
        let cleanedUID = try cleanedNonEmpty(
            uid,
            code: 9002,
            message: "User UID is empty."
        )
        
        let data: [String: Any] = [
            "displayName": profile.displayName,
            "displayNameKey": profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "team": profile.team.rawValue,
            "xp": profile.xp,
            "globalRank": profile.globalRank as Any,
            "matchesWon": profile.matchesWon,
            "avatarStyle": profile.avatarStyle,
            "avatarSeed": profile.avatarSeed,
            "isPro": profile.isPro,
            "proTier": profile.proTier as Any,
            "proStartedAt": profile.proStartedAt.map { Timestamp(date: $0) } as Any,
            "proExpiresAt": profile.proExpiresAt.map { Timestamp(date: $0) } as Any,
            "trialUsed": profile.trialUsed,
            "trialEndsAt": profile.trialEndsAt.map { Timestamp(date: $0) } as Any,
            "isPublic": true,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        try await userRef(cleanedUID).setData(data, merge: true)
    }
    
    // MARK: - Shared Entitlement Sync
    
    func updateEntitlement(
        uid: String,
        isPro: Bool,
        proTier: String?,
        proStartedAt: Date?,
        proExpiresAt: Date?,
        trialUsed: Bool,
        trialEndsAt: Date?
    ) async throws {
        let cleanedUID = try cleanedNonEmpty(
            uid,
            code: 9003,
            message: "User UID is empty."
        )
        
        let cleanedTier: String? = {
            guard let proTier else { return nil }
            let trimmed = proTier.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        
        var data: [String: Any] = [
            "isPro": isPro,
            "trialUsed": trialUsed,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        data["proTier"] = cleanedTier as Any
        data["proStartedAt"] = proStartedAt.map { Timestamp(date: $0) } as Any
        data["proExpiresAt"] = proExpiresAt.map { Timestamp(date: $0) } as Any
        data["trialEndsAt"] = trialEndsAt.map { Timestamp(date: $0) } as Any
        
        try await userRef(cleanedUID).setData(data, merge: true)
    }
    
    // MARK: - Leaderboard
    
    func fetchLeaderboard(limit: Int = 25) async throws -> [UserProfile] {
        let query = db.collection(Collections.users)
            .order(by: "xp", descending: true)
            .limit(to: limit)
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents.compactMap { doc in
            try? self.decodeDocument(doc, as: UserProfile.self)
        }
    }
    
    // MARK: - Platform Settings Mapping

    private func defaultPlatformFeatureFlags() -> [String: Bool] {
        [
            "global_battle_live": false,
            "events_public_access": true,
            "community_launch_surface": false,
            "pro_paywall_entry": false,
            "sponsor_rotation_surface": false,
            "public_stats_sync": true
        ]
    }

    private func platformConfigSnapshot(from data: [String: Any]) -> PlatformConfigSnapshot {
        let rawFeatureFlags = data["featureFlags"] as? [String: Bool] ?? [:]
        let mergedFeatureFlags = defaultPlatformFeatureFlags().merging(rawFeatureFlags) { _, new in new }

        let version = max(1, intValue(data["version"]) ?? 1)
        let updatedBy = cleanOptionalString(data["updatedBy"])
        let updatedAt = dateValue(data["updatedAt"])

        return PlatformConfigSnapshot(
            featureFlags: mergedFeatureFlags,
            version: version,
            updatedBy: updatedBy,
            updatedAt: updatedAt
        )
    }

    private func legacyGlobalBattleConfig(from data: [String: Any]) -> GlobalBattleAdminConfig {
        GlobalBattleAdminConfig(
            enabled: data["enabled"] as? Bool ?? false,
            updatedAt: dateValue(data["updatedAt"])
        )
    }

    private func globalBattleFinishData(
        type: String,
        winnerUID: String? = nil,
        disqualifiedUID: String? = nil,
        disqualifiedUIDs: [String] = [],
        duringTieBreak: Bool
    ) -> [String: Any] {
        let cleanedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedWinnerUID = winnerUID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDisqualifiedUID = disqualifiedUID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedDisqualifiedUIDs = disqualifiedUIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return [
            "type": cleanedType,
            "winnerUID": (cleanedWinnerUID?.isEmpty == false ? cleanedWinnerUID! : NSNull()),
            "disqualifiedUID": (cleanedDisqualifiedUID?.isEmpty == false ? cleanedDisqualifiedUID! : NSNull()),
            "disqualifiedUIDs": cleanedDisqualifiedUIDs,
            "duringTieBreak": duringTieBreak
        ]
    }

    // MARK: - Platform Settings / Global Battle Sync

    func fetchPlatformConfigSnapshot() async throws -> PlatformConfigSnapshot? {
        let liveSnapshot = try await platformSettingsRef().getDocument()

        if liveSnapshot.exists, let data = liveSnapshot.data() {
            return platformConfigSnapshot(from: data)
        }

        let legacySnapshot = try await legacyPlatformSettingsRef().getDocument()

        guard legacySnapshot.exists, let data = legacySnapshot.data() else {
            return nil
        }

        return platformConfigSnapshot(from: data)
    }

    func listenToPlatformConfigSnapshot(
        completion: @escaping (Result<PlatformConfigSnapshot?, Error>) -> Void
    ) -> ListenerRegistration {
        platformSettingsRef().addSnapshotListener { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            if let snapshot, snapshot.exists, let data = snapshot.data() {
                completion(.success(self.platformConfigSnapshot(from: data)))
                return
            }

            Task {
                do {
                    let legacySnapshot = try await self.legacyPlatformSettingsRef().getDocument()

                    guard legacySnapshot.exists, let legacyData = legacySnapshot.data() else {
                        completion(.success(nil))
                        return
                    }

                    completion(.success(self.platformConfigSnapshot(from: legacyData)))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Global Battle Admin Config

    func fetchGlobalBattleAdminConfig() async throws -> GlobalBattleAdminConfig? {
        if let platformConfig = try await fetchPlatformConfigSnapshot() {
            return GlobalBattleAdminConfig(
                enabled: platformConfig.globalBattleEnabled,
                updatedAt: platformConfig.updatedAt
            )
        }

        let snapshot = try await legacyGlobalBattleAdminConfigRef().getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }

        return legacyGlobalBattleConfig(from: data)
    }

    func listenToGlobalBattleAdminConfig(
        completion: @escaping (Result<GlobalBattleAdminConfig?, Error>) -> Void
    ) -> ListenerRegistration {
        platformSettingsRef().addSnapshotListener { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            if let snapshot, snapshot.exists, let data = snapshot.data() {
                let platformConfig = self.platformConfigSnapshot(from: data)
                completion(
                    .success(
                        GlobalBattleAdminConfig(
                            enabled: platformConfig.globalBattleEnabled,
                            updatedAt: platformConfig.updatedAt
                        )
                    )
                )
                return
            }

            Task {
                do {
                    if let platformConfig = try await self.fetchPlatformConfigSnapshot() {
                        completion(
                            .success(
                                GlobalBattleAdminConfig(
                                    enabled: platformConfig.globalBattleEnabled,
                                    updatedAt: platformConfig.updatedAt
                                )
                            )
                        )
                        return
                    }

                    let legacySnapshot = try await self.legacyGlobalBattleAdminConfigRef().getDocument()
                    guard legacySnapshot.exists, let legacyData = legacySnapshot.data() else {
                        completion(.success(nil))
                        return
                    }

                    completion(.success(self.legacyGlobalBattleConfig(from: legacyData)))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func fetchActiveGlobalBattleSponsorPlacement() async throws -> SponsorPlacementPayload? {
        let ref = publicGlobalBattleSponsorPlacementRef()

        if DebugLog.sponsorVerbose {
            print("🟧 [Sponsor] reading mirror doc: \(ref.path)")
        }

        let snapshot = try await ref.getDocument()

        guard snapshot.exists, let data = snapshot.data() else {
            if DebugLog.sponsorVerbose {
                print("🟥 [Sponsor] mirror doc missing at path: \(ref.path)")
            }
            return nil
        }

        let isEnabled = data["isEnabled"] as? Bool ?? false
        guard isEnabled else {
            if DebugLog.sponsorVerbose {
                print("🟥 [Sponsor] mirror exists but isEnabled == false")
            }
            return nil
        }

        let placementID =
            trimmedString(data["placementID"]) ??
            trimmedString(data["placementId"]) ??
            Collections.globalBattleSponsorPlacement

        let campaignID =
            trimmedString(data["campaignID"]) ??
            trimmedString(data["campaignId"])

        let sponsorID =
            trimmedString(data["sponsorID"]) ??
            trimmedString(data["sponsorId"])

        let sponsorName =
            trimmedString(data["sponsorName"]) ??
            "Sponsor"

        let headline =
            trimmedString(data["headline"]) ??
            sponsorName

        let subheadline = trimmedString(data["subheadline"])

        let ctaLabel =
            trimmedString(data["ctaLabel"]) ??
            "Learn More"

        let destinationURL =
            trimmedString(data["destinationURL"]) ??
            trimmedString(data["destinationUrl"]) ??
            trimmedString(data["websiteURL"]) ??
            trimmedString(data["websiteUrl"])

        let logoURL =
            trimmedString(data["logoURL"]) ??
            trimmedString(data["logoUrl"])

        let placementType = trimmedString(data["placementType"])
        let slotKey = trimmedString(data["slotKey"])

        let payload = SponsorPlacementPayload(
            placementID: placementID,
            campaignID: campaignID,
            sponsorID: sponsorID,
            sponsorName: sponsorName,
            headline: headline,
            subheadline: subheadline,
            ctaLabel: ctaLabel,
            destinationURL: destinationURL,
            logoURL: logoURL,
            placementType: placementType,
            slotKey: slotKey
        )

        if DebugLog.sponsorVerbose {
            print("🟩 [Sponsor] resolved placement id=\(placementID) sponsor=\(sponsorName)")
        }

        return payload
    }

    // MARK: - Global Battle Lobby

    func createGlobalBattleLobby(
        code: String,
        hostUID: String,
        topic: String,
        dayKey: String,
        maxPlayers: Int,
        questionCount: Int
    ) async throws -> String {
        let cleanedCode = try cleanedNonEmpty(
            code.uppercased(),
            code: 1001,
            message: "Global battle code is empty."
        )
        let cleanedHostUID = try cleanedNonEmpty(
            hostUID,
            code: 1002,
            message: "Host UID is empty."
        )
        let cleanedTopic = try cleanedNonEmpty(
            topic,
            code: 1003,
            message: "Topic is empty."
        )
        let cleanedDayKey = try cleanedNonEmpty(
            dayKey,
            code: 1004,
            message: "Day key is empty."
        )

        let ref = db.collection(Collections.globalBattles).document()
        let clampedMaxPlayers = max(2, min(maxPlayers, 50))
        let clampedQuestionCount = max(1, min(questionCount, 50))

        let batch = db.batch()

        batch.setData([
            "code": cleanedCode,
            "hostUID": cleanedHostUID,
            "topic": cleanedTopic,
            "dayKey": cleanedDayKey,
            "status": "lobby",
            "maxPlayers": clampedMaxPlayers,
            "questionCount": clampedQuestionCount,
            "roundIndex": 1,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: ref)

        batch.setData([
            "lobbyId": ref.documentID,
            "phase": "waiting",
            "roundIndex": 1,
            "question": NSNull(),
            "roundDurationSeconds": 10,
            "extraTieBreakRounds": 0,
            "deadlineAt": NSNull(),
            "revealedAt": NSNull(),
            "finish": NSNull(),
            "hostAdvancedAt": NSNull(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: runtimeRef(ref.documentID), merge: true)

        try await batch.commit()
        return ref.documentID
    }

    func fetchGlobalBattleLobby(code: String) async throws -> GlobalBattleLobby? {
        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        let snapshot = try await db.collection(Collections.globalBattles)
            .whereField("code", isEqualTo: cleanedCode)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first else { return nil }

        var lobby = try decodeDocument(doc, as: GlobalBattleLobby.self)
        lobby.id = doc.documentID
        return lobby
    }

    func joinGlobalBattleLobby(
        lobbyId: String,
        participant: GlobalBattleParticipant
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1005,
            message: "Lobby ID is empty."
        )
        let cleanedUID = try cleanedNonEmpty(
            participant.uid,
            code: 1006,
            message: "Participant UID is empty."
        )

        let cleanedDisplayName = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let participantRef = lobbyRef(cleanedLobbyId)
            .collection(Collections.participants)
            .document(cleanedUID)

        let batch = db.batch()

        batch.setData([
            "uid": cleanedUID,
            "displayName": cleanedDisplayName.isEmpty ? "PILOT" : cleanedDisplayName,
            "score": max(0, participant.score),
            "isHost": participant.isHost,
            "joinedAt": FieldValue.serverTimestamp()
        ], forDocument: participantRef, merge: true)

        batch.updateData([
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: lobbyRef(cleanedLobbyId))

        try await batch.commit()
    }

    func removeGlobalBattleParticipant(
        lobbyId: String,
        uid: String
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1103,
            message: "Lobby ID is empty."
        )
        let cleanedUID = try cleanedNonEmpty(
            uid,
            code: 1104,
            message: "Participant UID is empty."
        )

        let batch = db.batch()

        batch.deleteDocument(
            lobbyRef(cleanedLobbyId)
                .collection(Collections.participants)
                .document(cleanedUID)
        )

        batch.updateData([
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: lobbyRef(cleanedLobbyId))

        try await batch.commit()
    }

    func listenToGlobalBattleLobby(
        lobbyId: String,
        completion: @escaping (Result<GlobalBattleLobby, Error>) -> Void
    ) -> ListenerRegistration {
        lobbyRef(lobbyId)
            .addSnapshotListener { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot, snapshot.exists else { return }

                do {
                    var lobby = try self.decodeDocument(snapshot, as: GlobalBattleLobby.self)
                    lobby.id = snapshot.documentID
                    completion(.success(lobby))
                } catch {
                    completion(.failure(error))
                }
            }
    }

    func listenToGlobalBattleParticipants(
        lobbyId: String,
        completion: @escaping (Result<[GlobalBattleParticipant], Error>) -> Void
    ) -> ListenerRegistration {
        lobbyRef(lobbyId)
            .collection(Collections.participants)
            .order(by: "joinedAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot else { return }

                let participants: [GlobalBattleParticipant] = snapshot.documents.compactMap { doc in
                    let data = doc.data()

                    let uid = self.cleanOptionalString(data["uid"]) ?? doc.documentID
                    let displayName = self.cleanOptionalString(data["displayName"]) ?? "PILOT"
                    let score = self.intValue(data["score"]) ?? 0
                    let isHost = data["isHost"] as? Bool ?? false
                    let joinedAt = self.dateValue(data["joinedAt"])

                    return GlobalBattleParticipant(
                        id: doc.documentID,
                        uid: uid,
                        displayName: displayName,
                        score: max(0, score),
                        isHost: isHost,
                        joinedAt: joinedAt
                    )
                }

                completion(.success(participants))
            }
    }

    func updateGlobalBattleStatus(
        lobbyId: String,
        status: String,
        roundIndex: Int
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1105,
            message: "Lobby ID is empty."
        )

        try await lobbyRef(cleanedLobbyId).updateData([
            "status": status,
            "roundIndex": max(1, roundIndex),
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Global Battle Runtime

    func listenToGlobalBattleRuntime(
        lobbyId: String,
        completion: @escaping (Result<GlobalBattleRuntimeState, Error>) -> Void
    ) -> ListenerRegistration {
        runtimeRef(lobbyId)
            .addSnapshotListener { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot, snapshot.exists else { return }

                let data = snapshot.data() ?? [:]

                let question: GlobalBattleLiveQuestion? = {
                    guard let q = data["question"] as? [String: Any] else { return nil }

                    let key = self.cleanOptionalString(q["key"]) ?? ""
                    let prompt = self.cleanOptionalString(q["prompt"]) ?? ""
                    let choices = q["choices"] as? [String] ?? []
                    let correctIndex = self.intValue(q["correctIndex"]) ?? 0

                    guard !key.isEmpty, !prompt.isEmpty, !choices.isEmpty else {
                        return nil
                    }

                    return GlobalBattleLiveQuestion(
                        key: key,
                        prompt: prompt,
                        choices: choices,
                        correctIndex: correctIndex
                    )
                }()

                let finish: GlobalBattleRuntimeFinishState? = {
                    guard let raw = data["finish"] as? [String: Any] else { return nil }

                    let type = self.cleanOptionalString(raw["type"]) ?? ""
                    guard !type.isEmpty else { return nil }

                    let winnerUID = self.cleanOptionalString(raw["winnerUID"])
                    let disqualifiedUID = self.cleanOptionalString(raw["disqualifiedUID"])
                    let disqualifiedUIDs = (raw["disqualifiedUIDs"] as? [String] ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let duringTieBreak = raw["duringTieBreak"] as? Bool ?? false

                    return GlobalBattleRuntimeFinishState(
                        type: type,
                        winnerUID: winnerUID,
                        disqualifiedUID: disqualifiedUID,
                        disqualifiedUIDs: disqualifiedUIDs,
                        duringTieBreak: duringTieBreak
                    )
                }()

                let runtime = GlobalBattleRuntimeState(
                    id: snapshot.documentID,
                    lobbyId: self.cleanOptionalString(data["lobbyId"]) ?? lobbyId,
                    phase: self.cleanOptionalString(data["phase"]) ?? "waiting",
                    roundIndex: max(1, self.intValue(data["roundIndex"]) ?? 1),
                    question: question,
                    roundDurationSeconds: max(3, self.intValue(data["roundDurationSeconds"]) ?? 10),
                    extraTieBreakRounds: max(0, self.intValue(data["extraTieBreakRounds"]) ?? 0),
                    deadlineAt: self.dateValue(data["deadlineAt"]),
                    revealedAt: self.dateValue(data["revealedAt"]),
                    finish: finish,
                    hostAdvancedAt: self.dateValue(data["hostAdvancedAt"]),
                    updatedAt: self.dateValue(data["updatedAt"])
                )

                completion(.success(runtime))
            }
    }
    
    func stageGlobalBattleRoundWaiting(
        lobbyId: String,
        roundIndex: Int,
        extraTieBreakRounds: Int = 0
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1204,
            message: "Lobby ID is empty."
        )

        let clampedRoundIndex = max(1, roundIndex)

        let batch = db.batch()

        batch.setData([
            "lobbyId": cleanedLobbyId,
            "phase": "waiting",
            "roundIndex": clampedRoundIndex,
            "question": NSNull(),
            "roundDurationSeconds": 10,
            "extraTieBreakRounds": max(0, extraTieBreakRounds),
            "deadlineAt": NSNull(),
            "revealedAt": NSNull(),
            "finish": NSNull(),
            "hostAdvancedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: runtimeRef(cleanedLobbyId), merge: true)

        batch.updateData([
            "status": "live",
            "roundIndex": clampedRoundIndex,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: lobbyRef(cleanedLobbyId))

        try await batch.commit()
    }

    func updateGlobalBattleTieBreakRounds(
        lobbyId: String,
        extraTieBreakRounds: Int
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1211,
            message: "Lobby ID is empty."
        )

        try await runtimeRef(cleanedLobbyId).updateData([
            "extraTieBreakRounds": max(0, extraTieBreakRounds),
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func publishGlobalBattleRound(
        lobbyId: String,
        roundIndex: Int,
        question: GlobalBattleLiveQuestion,
        roundDurationSeconds: Int,
        extraTieBreakRounds: Int = 0
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1201,
            message: "Lobby ID is empty."
        )

        let clampedRoundIndex = max(1, roundIndex)
        let clampedDuration = max(3, roundDurationSeconds)
        let deadline = Date().addingTimeInterval(TimeInterval(clampedDuration))

        let batch = db.batch()

        batch.setData([
            "lobbyId": cleanedLobbyId,
            "phase": "answering",
            "roundIndex": clampedRoundIndex,
            "question": [
                "key": question.key,
                "prompt": question.prompt,
                "choices": question.choices,
                "correctIndex": question.correctIndex
            ],
            "roundDurationSeconds": clampedDuration,
            "extraTieBreakRounds": max(0, extraTieBreakRounds),
            "deadlineAt": Timestamp(date: deadline),
            "revealedAt": NSNull(),
            "finish": NSNull(),
            "hostAdvancedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: runtimeRef(cleanedLobbyId), merge: true)

        batch.updateData([
            "status": "live",
            "roundIndex": clampedRoundIndex,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: lobbyRef(cleanedLobbyId))

        try await batch.commit()
    }

    func revealGlobalBattleRound(
        lobbyId: String,
        roundIndex: Int
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1206,
            message: "Lobby ID is empty."
        )

        let runtimeDocument = runtimeRef(cleanedLobbyId)
        let lobbyDocument = lobbyRef(cleanedLobbyId)
        let clampedRoundIndex = max(1, roundIndex)

        _ = try await db.runTransaction { transaction, errorPointer in
            let runtimeSnap: DocumentSnapshot

            do {
                runtimeSnap = try transaction.getDocument(runtimeDocument)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            let data = runtimeSnap.data() ?? [:]

            let currentPhase = ((data["phase"] as? String) ?? "waiting")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let currentRoundIndex = max(1, self.intValue(data["roundIndex"]) ?? 1)

            guard currentPhase == "answering" else { return nil }
            guard currentRoundIndex == clampedRoundIndex else { return nil }

            transaction.updateData([
                "phase": "revealed",
                "roundIndex": clampedRoundIndex,
                "revealedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: runtimeDocument)

            transaction.updateData([
                "status": "live",
                "roundIndex": clampedRoundIndex,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: lobbyDocument)

            return nil
        }
    }

    func finishGlobalBattleRuntime(
        lobbyId: String,
        finish: GlobalBattleRuntimeFinishState
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1207,
            message: "Lobby ID is empty."
        )

        let batch = db.batch()

        batch.updateData([
            "phase": "finished",
            "revealedAt": FieldValue.serverTimestamp(),
            "deadlineAt": NSNull(),
            "finish": globalBattleFinishData(
                type: finish.type,
                winnerUID: finish.winnerUID,
                disqualifiedUID: finish.disqualifiedUID,
                disqualifiedUIDs: finish.disqualifiedUIDs,
                duringTieBreak: finish.duringTieBreak
            ),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: runtimeRef(cleanedLobbyId))

        batch.updateData([
            "status": "finished",
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: lobbyRef(cleanedLobbyId))

        try await batch.commit()
    }

    func submitGlobalBattleAnswer(
        lobbyId: String,
        submission: GlobalBattleAnswerSubmission
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1202,
            message: "Lobby ID is empty."
        )
        let cleanedUID = try cleanedNonEmpty(
            submission.uid,
            code: 1203,
            message: "Submission UID is empty."
        )

        let cleanedName = submission.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedRoundIndex = max(1, submission.roundIndex)

        let ref = answersRef(cleanedLobbyId, roundIndex: clampedRoundIndex)
            .document(cleanedUID)

        try await ref.setData([
            "uid": cleanedUID,
            "displayName": cleanedName.isEmpty ? "PILOT" : cleanedName,
            "roundIndex": clampedRoundIndex,
            "choiceIndex": submission.choiceIndex,
            "isCorrect": submission.isCorrect as Any,
            "submittedAt": FieldValue.serverTimestamp(),
            "clientSubmittedAt": Timestamp(date: Date())
        ], merge: true)
    }

    func fetchGlobalBattleAnswers(
        lobbyId: String,
        roundIndex: Int
    ) async throws -> [GlobalBattleAnswerSubmission] {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1205,
            message: "Lobby ID is empty."
        )

        let snapshot = try await answersRef(cleanedLobbyId, roundIndex: roundIndex)
            .order(by: "submittedAt", descending: false)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let data = doc.data()

            let uid = self.cleanOptionalString(data["uid"]) ?? doc.documentID
            let displayName = self.cleanOptionalString(data["displayName"]) ?? "PILOT"

            guard let choiceIndex = self.intValue(data["choiceIndex"]), choiceIndex >= 0 else {
                return nil
            }

            return GlobalBattleAnswerSubmission(
                id: doc.documentID,
                uid: uid,
                displayName: displayName,
                roundIndex: max(1, self.intValue(data["roundIndex"]) ?? roundIndex),
                choiceIndex: choiceIndex,
                isCorrect: data["isCorrect"] as? Bool,
                submittedAt: self.dateValue(data["submittedAt"])
            )
        }
    }

    func listenToGlobalBattleAnswers(
        lobbyId: String,
        roundIndex: Int,
        completion: @escaping (Result<[GlobalBattleAnswerSubmission], Error>) -> Void
    ) -> ListenerRegistration {
        answersRef(lobbyId, roundIndex: roundIndex)
            .order(by: "submittedAt", descending: false)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                guard let snapshot else { return }

                let answers: [GlobalBattleAnswerSubmission] = snapshot.documents.compactMap { doc in
                    let data = doc.data()

                    let uid = self.cleanOptionalString(data["uid"]) ?? doc.documentID
                    let displayName = self.cleanOptionalString(data["displayName"]) ?? "PILOT"

                    guard let choiceIndex = self.intValue(data["choiceIndex"]), choiceIndex >= 0 else {
                        return nil
                    }

                    return GlobalBattleAnswerSubmission(
                        id: doc.documentID,
                        uid: uid,
                        displayName: displayName,
                        roundIndex: max(1, self.intValue(data["roundIndex"]) ?? roundIndex),
                        choiceIndex: choiceIndex,
                        isCorrect: data["isCorrect"] as? Bool,
                        submittedAt: self.dateValue(data["submittedAt"])
                    )
                }

                completion(.success(answers))
            }
    }

    func clearGlobalBattleAnswers(
        lobbyId: String,
        roundIndex: Int
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1208,
            message: "Lobby ID is empty."
        )

        let snapshot = try await answersRef(cleanedLobbyId, roundIndex: roundIndex)
            .getDocuments()

        let batch = db.batch()

        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }

        try await batch.commit()
    }
    
    func markUsedQuestionKeys(
        lobbyId: String,
        keys: [String]
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1209,
            message: "Lobby ID is empty."
        )

        let batch = db.batch()
        let root = usedKeysRef(cleanedLobbyId)

        for key in keys {
            let cleanedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedKey.isEmpty else { continue }

            batch.setData([
                "key": cleanedKey,
                "usedAt": FieldValue.serverTimestamp()
            ], forDocument: root.document(cleanedKey))
        }

        try await batch.commit()
    }

    func incrementGlobalBattleParticipantScore(
        lobbyId: String,
        uid: String,
        by delta: Int
    ) async throws {
        let cleanedLobbyId = try cleanedNonEmpty(
            lobbyId,
            code: 1212,
            message: "Lobby ID is empty."
        )
        let cleanedUID = try cleanedNonEmpty(
            uid,
            code: 1213,
            message: "Participant UID is empty."
        )

        let safeDelta = max(0, delta)
        guard safeDelta > 0 else { return }

        let participantRef = lobbyRef(cleanedLobbyId)
            .collection(Collections.participants)
            .document(cleanedUID)

        let batch = db.batch()

        batch.updateData([
            "score": FieldValue.increment(Int64(safeDelta))
        ], forDocument: participantRef)

        batch.updateData([
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: lobbyRef(cleanedLobbyId))

        try await batch.commit()
    }

    // MARK: - Telemetry

    func logEvent(
        name: String,
        uid: String?,
        props: [String: Any] = [:]
    ) async {
        let eventName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventName.isEmpty else { return }

        var data: [String: Any] = [
            "name": eventName,
            "ts": FieldValue.serverTimestamp()
        ]

        let cleanedUID = (uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedUID.isEmpty {
            data["uid"] = cleanedUID
        }

        for (k, v) in props {
            let key = k.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            data[key] = v
        }

        do {
            _ = try await db.collection(Collections.telemetry)
                .document(Collections.events)
                .collection(Collections.events)
                .addDocument(data: data)
        } catch {
            if DebugLog.telemetryErrors {
                print("⚠️ Telemetry logEvent failed: \(error)")
            }
        }
    }
}
