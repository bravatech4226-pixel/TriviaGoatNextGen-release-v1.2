//
//  UserProfile.swift
//  TriviaGoatNextGen
//
//  Production-ready shared user profile model.
//  FIXED:
//  - prevents "NEW PILOT" from being re-injected during decoding
//  - keeps placeholder ONLY as an explicit fallback state
//  - protects real user data from being overwritten
//

import Foundation
import SwiftUI

struct UserProfile: Codable, Identifiable, Equatable {
    var id: String?

    // MARK: - Core Identity
    var displayName: String
    var team: TacticalTeam
    var xp: Int
    var globalRank: Int?
    var matchesWon: Int

    // MARK: - Avatar
    var avatarStyle: String
    var avatarSeed: String

    // MARK: - Entitlement (Shared with Web)
    var isPro: Bool
    var proTier: String?
    var proStartedAt: Date?
    var proExpiresAt: Date?
    var trialUsed: Bool
    var trialEndsAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case team
        case xp
        case globalRank
        case matchesWon
        case avatarStyle
        case avatarSeed
        case isPro
        case proTier
        case proStartedAt
        case proExpiresAt
        case trialUsed
        case trialEndsAt
    }

    // MARK: - Init

    init(
        id: String? = nil,
        displayName: String,
        team: TacticalTeam,
        xp: Int,
        globalRank: Int? = nil,
        matchesWon: Int = 0,
        avatarStyle: String = "adventurer",
        avatarSeed: String = "TriviaGoatAlpha",
        isPro: Bool = false,
        proTier: String? = nil,
        proStartedAt: Date? = nil,
        proExpiresAt: Date? = nil,
        trialUsed: Bool = false,
        trialEndsAt: Date? = nil
    ) {
        self.id = Self.cleanedOptionalString(id)
        self.displayName = Self.cleanedDisplayName(displayName)
        self.team = team
        self.xp = max(0, xp)
        self.globalRank = Self.cleanedOptionalRank(globalRank)
        self.matchesWon = max(0, matchesWon)
        self.avatarStyle = Self.cleanedAvatarStyle(avatarStyle)
        self.avatarSeed = Self.cleanedAvatarSeed(avatarSeed)
        self.isPro = isPro
        self.proTier = Self.cleanedOptionalString(proTier)
        self.proStartedAt = proStartedAt
        self.proExpiresAt = proExpiresAt
        self.trialUsed = trialUsed
        self.trialEndsAt = trialEndsAt
    }

    // MARK: - Decoding (🔥 FIXED)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawID = try container.decodeIfPresent(String.self, forKey: .id)
        let rawDisplayName = try container.decodeIfPresent(String.self, forKey: .displayName)

        let decodedTeam = try container.decodeIfPresent(TacticalTeam.self, forKey: .team)
        let decodedXP = try container.decodeIfPresent(Int.self, forKey: .xp)
        let decodedGlobalRank = try container.decodeIfPresent(Int.self, forKey: .globalRank)
        let decodedMatchesWon = try container.decodeIfPresent(Int.self, forKey: .matchesWon)

        let rawAvatarStyle = try container.decodeIfPresent(String.self, forKey: .avatarStyle)
        let rawAvatarSeed = try container.decodeIfPresent(String.self, forKey: .avatarSeed)

        let decodedIsPro = try container.decodeIfPresent(Bool.self, forKey: .isPro)
        let rawProTier = try container.decodeIfPresent(String.self, forKey: .proTier)
        let decodedProStartedAt = try container.decodeIfPresent(Date.self, forKey: .proStartedAt)
        let decodedProExpiresAt = try container.decodeIfPresent(Date.self, forKey: .proExpiresAt)
        let decodedTrialUsed = try container.decodeIfPresent(Bool.self, forKey: .trialUsed)
        let decodedTrialEndsAt = try container.decodeIfPresent(Date.self, forKey: .trialEndsAt)

        id = Self.cleanedOptionalString(rawID)

        // 🚨 CRITICAL FIX:
        // DO NOT fallback to "NEW PILOT" here
        let cleanedName = Self.cleanedDisplayName(rawDisplayName)
        displayName = cleanedName.isEmpty ? "" : cleanedName

        team = decodedTeam ?? .striker
        xp = max(0, decodedXP ?? 0)
        globalRank = Self.cleanedOptionalRank(decodedGlobalRank)
        matchesWon = max(0, decodedMatchesWon ?? 0)

        avatarStyle = Self.cleanedAvatarStyle(rawAvatarStyle)
        avatarSeed = Self.cleanedAvatarSeed(rawAvatarSeed)

        isPro = decodedIsPro ?? false
        proTier = Self.cleanedOptionalString(rawProTier)
        proStartedAt = decodedProStartedAt
        proExpiresAt = decodedProExpiresAt
        trialUsed = decodedTrialUsed ?? false
        trialEndsAt = decodedTrialEndsAt
    }

    // MARK: - Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(Self.cleanedOptionalString(id), forKey: .id)
        try container.encode(Self.cleanedDisplayName(displayName), forKey: .displayName)
        try container.encode(team, forKey: .team)
        try container.encode(max(0, xp), forKey: .xp)
        try container.encodeIfPresent(Self.cleanedOptionalRank(globalRank), forKey: .globalRank)
        try container.encode(max(0, matchesWon), forKey: .matchesWon)
        try container.encode(Self.cleanedAvatarStyle(avatarStyle), forKey: .avatarStyle)
        try container.encode(Self.cleanedAvatarSeed(avatarSeed), forKey: .avatarSeed)

        try container.encode(isPro, forKey: .isPro)
        try container.encodeIfPresent(Self.cleanedOptionalString(proTier), forKey: .proTier)
        try container.encodeIfPresent(proStartedAt, forKey: .proStartedAt)
        try container.encodeIfPresent(proExpiresAt, forKey: .proExpiresAt)
        try container.encode(trialUsed, forKey: .trialUsed)
        try container.encodeIfPresent(trialEndsAt, forKey: .trialEndsAt)
    }

    // MARK: - Placeholder (UNCHANGED)

    static var placeholder: UserProfile {
        UserProfile(
            id: nil,
            displayName: "NEW PILOT",
            team: .striker,
            xp: 0,
            globalRank: nil,
            matchesWon: 0,
            avatarStyle: "adventurer",
            avatarSeed: "TriviaGoatAlpha",
            isPro: false,
            proTier: nil,
            proStartedAt: nil,
            proExpiresAt: nil,
            trialUsed: false,
            trialEndsAt: nil
        )
    }

    // MARK: - Helpers

    var isPlaceholder: Bool {
        displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "NEW PILOT"
    }

    var hasValidName: Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.uppercased() != "NEW PILOT"
    }

    // MARK: - Normalizers (🔥 FIXED)

    private static func cleanedDisplayName(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func cleanedOptionalRank(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return value > 0 ? value : nil
    }

    private static func cleanedAvatarStyle(_ value: String?) -> String {
        let cleaned = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "adventurer" : cleaned
    }

    private static func cleanedAvatarSeed(_ value: String?) -> String {
        let cleaned = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "TriviaGoatAlpha" : cleaned
    }
}
