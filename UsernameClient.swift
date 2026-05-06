//
//  UsernameClient.swift
//  TriviaGoatNextGen
//
//  Production-ready Firebase Functions client for codename claims.
//  - aligned with claimUsername callable
//  - strong structured error mapping
//  - safe client-side preflight
//  - backend remains source of truth
//

import Foundation
import FirebaseFunctions

struct UsernameClaimResponse: Decodable, Equatable {
    let username: String
}

enum UsernameClientError: LocalizedError, Equatable {
    case emptyUsername
    case invalidFormat
    case reserved
    case offensive
    case alreadyTaken
    case rateLimited
    case moderationBlocked
    case renameBlocked
    case badResponse
    case missingUsername
    case networkIssue
    case unauthenticated
    case server(String)

    var errorDescription: String? {
        switch self {
        case .emptyUsername:
            return "Enter a codename to continue."
        case .invalidFormat:
            return "That codename format isn’t allowed. Try a different one."
        case .reserved:
            return "That codename is reserved. Try another."
        case .offensive:
            return "That codename can’t be used. Try another."
        case .alreadyTaken:
            return "That codename is already taken."
        case .rateLimited:
            return "Too many attempts. Please wait a moment and try again."
        case .moderationBlocked:
            return "That codename can’t be deployed. Try a different codename."
        case .renameBlocked:
            return "Codename changes are not allowed."
        case .badResponse:
            return "Invalid server response."
        case .missingUsername:
            return "Username was not returned by the server."
        case .networkIssue:
            return "Network issue. Check your connection and try again."
        case .unauthenticated:
            return "Authentication failed. Please try again."
        case .server(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Unable to deploy codename right now."
                : message
        }
    }
}

final class UsernameClient {

    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "us-central1")) {
        self.functions = functions
    }

    // MARK: - Public API

    /// Calls Cloud Function: `claimUsername`
    ///
    /// Request:
    /// { username: string }
    ///
    /// Expected success response:
    /// { username: string }
    /// or
    /// { data: { username: string } }
    func claim(username: String) async throws -> UsernameClaimResponse {
        let cleaned = normalize(username)

        guard !cleaned.isEmpty else {
            throw UsernameClientError.emptyUsername
        }

        try preflightValidate(cleaned)

        let callable = functions.httpsCallable("claimUsername")

        do {
            let rawData = try await callData(callable, payload: [
                "username": cleaned
            ])

            if let response = decodeClaimResponse(from: rawData) {
                let normalizedReturnedUsername = normalize(response.username)

                guard !normalizedReturnedUsername.isEmpty else {
                    throw UsernameClientError.missingUsername
                }

                return UsernameClaimResponse(username: normalizedReturnedUsername)
            }

            if let structuredError = decodeStructuredError(from: rawData) {
                throw structuredError
            }

            throw UsernameClientError.missingUsername
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Preflight Validation

    /// Client-side preflight only.
    /// Backend remains source of truth.
    private func preflightValidate(_ username: String) throws {
        guard username.count >= 3, username.count <= 16 else {
            throw UsernameClientError.invalidFormat
        }

        guard !username.allSatisfy(\.isNumber) else {
            throw UsernameClientError.invalidFormat
        }

        guard username.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else {
            throw UsernameClientError.invalidFormat
        }

        guard !username.hasPrefix("_"),
              !username.hasSuffix("_"),
              !username.contains("__") else {
            throw UsernameClientError.invalidFormat
        }

        let lowered = username
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let compact = lowered.replacingOccurrences(of: "_", with: "")

        let reserved: Set<String> = [
            "admin",
            "administrator",
            "support",
            "system",
            "moderator",
            "mod",
            "owner",
            "staff",
            "official",
            "developer",
            "dev",
            "founder",
            "goat",
            "triviagoat",
            "trivia_goat",
            "gt",
            "firebase",
            "google",
            "openai"
        ]

        if reserved.contains(lowered) || reserved.contains(compact) {
            throw UsernameClientError.reserved
        }
    }

    // MARK: - Success Decoding

    private func decodeClaimResponse(from rawData: Any) -> UsernameClaimResponse? {
        if let dict = rawData as? [String: Any] {
            if let username = extractUsername(from: dict) {
                return UsernameClaimResponse(username: username)
            }

            if let nested = dict["data"] as? [String: Any],
               let username = extractUsername(from: nested) {
                return UsernameClaimResponse(username: username)
            }
        }

        if let jsonString = rawData as? String,
           let parsed = try? JSONDecoder().decode(UsernameClaimResponse.self, from: Data(jsonString.utf8)) {
            let normalized = normalize(parsed.username)
            guard !normalized.isEmpty else { return nil }
            return UsernameClaimResponse(username: normalized)
        }

        return nil
    }

    private func extractUsername(from dict: [String: Any]) -> String? {
        guard let username = dict["username"] as? String else { return nil }
        let cleaned = normalize(username)
        return cleaned.isEmpty ? nil : cleaned
    }

    // MARK: - Structured Error Decoding

    private func decodeStructuredError(from rawData: Any) -> UsernameClientError? {
        guard let dict = rawData as? [String: Any] else { return nil }

        if let reason = extractReason(from: dict) {
            return mapStructuredServerCode(reason)
        }

        if let nested = dict["data"] as? [String: Any],
           let reason = extractReason(from: nested) {
            return mapStructuredServerCode(reason)
        }

        if let nested = dict["details"] as? [String: Any],
           let reason = extractReason(from: nested) {
            return mapStructuredServerCode(reason)
        }

        return nil
    }

    private func extractReason(from dict: [String: Any]) -> String? {
        if let reason = dict["reason"] as? String {
            return reason
        }

        if let errorCode = dict["errorCode"] as? String {
            return errorCode
        }

        if let details = dict["details"] as? [String: Any],
           let reason = details["reason"] as? String {
            return reason
        }

        return nil
    }

    // MARK: - Error Mapping

    private func mapError(_ error: Error) -> UsernameClientError {
        if let typed = error as? UsernameClientError {
            return typed
        }

        let nsError = error as NSError
        let lower = nsError.localizedDescription.lowercased()

        if nsError.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: nsError.code) {
            if let reason = extractReason(fromUserInfo: nsError.userInfo) {
                return mapStructuredServerCode(reason)
            }

            switch code {
            case .invalidArgument:
                if lower.contains("rename") || lower.contains("changes are not allowed") {
                    return .renameBlocked
                }
                if lower.contains("reserved") {
                    return .reserved
                }
                if lower.contains("offensive")
                    || lower.contains("profan")
                    || lower.contains("abusive")
                    || lower.contains("restricted") {
                    return .offensive
                }
                if lower.contains("blocked") || lower.contains("not allowed") {
                    return .moderationBlocked
                }
                return .invalidFormat

            case .alreadyExists:
                return .alreadyTaken

            case .resourceExhausted:
                return .rateLimited

            case .permissionDenied:
                return .moderationBlocked

            case .unauthenticated:
                return .unauthenticated

            case .unavailable, .deadlineExceeded:
                return .networkIssue

            case .failedPrecondition:
                if lower.contains("rename") {
                    return .renameBlocked
                }
                if lower.contains("blocked") || lower.contains("moderat") {
                    return .moderationBlocked
                }
                return .server("That codename can’t be deployed right now.")

            case .internal, .unknown, .dataLoss:
                return .server("Unable to deploy codename right now.")

            default:
                return .server(nsError.localizedDescription)
            }
        }

        if lower.contains("already taken") || lower.contains("already exists") {
            return .alreadyTaken
        }

        if lower.contains("rate")
            || lower.contains("too many")
            || lower.contains("quota")
            || lower.contains("resource exhausted") {
            return .rateLimited
        }

        if lower.contains("reserved") {
            return .reserved
        }

        if lower.contains("offensive")
            || lower.contains("profan")
            || lower.contains("abusive")
            || lower.contains("hate")
            || lower.contains("slur")
            || lower.contains("restricted") {
            return .offensive
        }

        if lower.contains("rename") || lower.contains("changes are not allowed") {
            return .renameBlocked
        }

        if lower.contains("invalid") || lower.contains("format") {
            return .invalidFormat
        }

        if lower.contains("moderat")
            || lower.contains("blocked")
            || lower.contains("not allowed") {
            return .moderationBlocked
        }

        if lower.contains("network")
            || lower.contains("internet")
            || lower.contains("offline")
            || lower.contains("timed out") {
            return .networkIssue
        }

        return .server(nsError.localizedDescription)
    }

    private func extractReason(fromUserInfo userInfo: [String: Any]) -> String? {
        if let details = userInfo["details"] as? [String: Any],
           let reason = details["reason"] as? String {
            return reason
        }

        if let details = userInfo[FunctionsErrorDetailsKey] as? [String: Any],
           let reason = details["reason"] as? String {
            return reason
        }

        return nil
    }

    private func mapStructuredServerCode(_ code: String) -> UsernameClientError {
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "taken", "already_taken", "alreadyexists", "already_exists":
            return .alreadyTaken

        case "reserved":
            return .reserved

        case "restricted_word":
            return .offensive

        case "length",
             "charset",
             "edge_underscore",
             "double_underscore",
             "invalid_format",
             "invalid":
            return .invalidFormat

        case "cooldown",
             "hourly_limit",
             "rate_limited",
             "ratelimited":
            return .rateLimited

        case "rename_blocked":
            return .renameBlocked

        case "blocked",
             "moderation_blocked",
             "too_numeric",
             "pattern",
             "repeated_chars",
             "repetitive_pattern":
            return .moderationBlocked

        default:
            return .server("That codename couldn’t be deployed. Try a different codename.")
        }
    }

    // MARK: - Helpers

    private func normalize(_ username: String) -> String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    // MARK: - Typed Async Bridge

    private func callData(_ callable: HTTPSCallable, payload: [String: Any]) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            callable.call(payload) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = result?.data else {
                    continuation.resume(throwing: UsernameClientError.badResponse)
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }
}
