import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit
import Security
import UIKit

// MARK: - Debug

nonisolated private func authDebug(_ message: String) {
    #if DEBUG
    print("🍎 [AppleAuth] \(message)")
    #endif
}

// MARK: - Auth Manager

actor AuthManager {
    static let shared = AuthManager()
    private init() {}

    func currentUID() -> String? {
        Auth.auth().currentUser?.uid
    }

    func isAnonymousUser() -> Bool {
        Auth.auth().currentUser?.isAnonymous ?? true
    }

    func ensureAuthenticated() async throws -> String {
        if let uid = currentUID(), !uid.isEmpty {
            return uid
        }

        return try await signInAnonymously()
    }

    private func signInAnonymously() async throws -> String {
        if let uid = currentUID(), !uid.isEmpty {
            return uid
        }

        authDebug("Signing in anonymously")
        let result = try await Auth.auth().signInAnonymously()

        guard !result.user.uid.isEmpty else {
            throw NSError(
                domain: "AuthManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Anonymous sign-in returned empty UID."]
            )
        }

        authDebug("Anonymous sign-in complete uid=\(result.user.uid)")
        return result.user.uid
    }

    @MainActor
    func secureCurrentProfileWithApple() async throws -> String {
        authDebug("START secureCurrentProfileWithApple()")

        if let user = Auth.auth().currentUser {
            authDebug("Current Firebase user uid=\(user.uid), isAnonymous=\(user.isAnonymous)")
        } else {
            authDebug("No Firebase user. Creating anonymous user first.")
            let anon = try await Auth.auth().signInAnonymously()

            guard !anon.user.uid.isEmpty else {
                throw NSError(
                    domain: "AuthManager",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Anonymous bootstrap returned empty UID."]
                )
            }

            authDebug("Anonymous user created uid=\(anon.user.uid)")
        }

        authDebug("Launching Apple Sign-In sheet")
        let apple = try await AppleSignInCoordinator.signIn()
        authDebug("Apple returned token length=\(apple.idToken.count)")

        let credential = OAuthProvider.appleCredential(
            withIDToken: apple.idToken,
            rawNonce: apple.rawNonce,
            fullName: nil
        )

        if let user = Auth.auth().currentUser, user.isAnonymous {
            authDebug("Attempting LINK to anonymous uid=\(user.uid)")

            do {
                let result = try await user.link(with: credential)

                guard !result.user.uid.isEmpty else {
                    throw NSError(
                        domain: "AuthManager",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "Apple link returned empty UID."]
                    )
                }

                authDebug("LINK SUCCESS uid=\(result.user.uid), isAnonymous=\(result.user.isAnonymous)")
                await forceAuthRefresh()
                return result.user.uid

            } catch {
                let nsError = error as NSError
                authDebug("LINK FAILED code=\(nsError.code), domain=\(nsError.domain)")

                if nsError.code == AuthErrorCode.credentialAlreadyInUse.rawValue ||
                    nsError.code == AuthErrorCode.providerAlreadyLinked.rawValue ||
                    nsError.code == AuthErrorCode.emailAlreadyInUse.rawValue {

                    authDebug("Credential already linked. Recovering existing account.")

                    if let updatedCredential = nsError.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential {
                        authDebug("Using updated credential from error payload")

                        let result = try await Auth.auth().signIn(with: updatedCredential)

                        guard !result.user.uid.isEmpty else {
                            throw NSError(
                                domain: "AuthManager",
                                code: -4,
                                userInfo: [NSLocalizedDescriptionKey: "Recovered Apple sign-in returned empty UID."]
                            )
                        }

                        authDebug("RECOVERED USER uid=\(result.user.uid), isAnonymous=\(result.user.isAnonymous)")
                        await forceAuthRefresh()
                        return result.user.uid
                    }

                    authDebug("No updated credential. Falling back to direct Apple sign-in.")

                    let result = try await Auth.auth().signIn(with: credential)

                    guard !result.user.uid.isEmpty else {
                        throw NSError(
                            domain: "AuthManager",
                            code: -5,
                            userInfo: [NSLocalizedDescriptionKey: "Apple fallback sign-in returned empty UID."]
                        )
                    }

                    authDebug("APPLE SIGN-IN SUCCESS uid=\(result.user.uid), isAnonymous=\(result.user.isAnonymous)")
                    await forceAuthRefresh()
                    return result.user.uid
                }

                throw error
            }
        }

        authDebug("Signing in with Apple credential directly")

        let result = try await Auth.auth().signIn(with: credential)

        guard !result.user.uid.isEmpty else {
            throw NSError(
                domain: "AuthManager",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Apple direct sign-in returned empty UID."]
            )
        }

        authDebug("APPLE SIGN-IN SUCCESS uid=\(result.user.uid), isAnonymous=\(result.user.isAnonymous)")
        await forceAuthRefresh()
        return result.user.uid
    }

    private func forceAuthRefresh() async {
        authDebug("Forcing auth refresh")

        guard let user = Auth.auth().currentUser else { return }

        do {
            try await user.reload()
            _ = try await user.getIDTokenResult(forcingRefresh: true)
            authDebug("Auth refresh complete uid=\(user.uid)")
        } catch {
            authDebug("Auth refresh failed: \(error.localizedDescription)")
        }
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}

// MARK: - Apple Sign-In Coordinator

@MainActor
private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    struct AppleResult {
        let idToken: String
        let rawNonce: String
    }

    private var continuation: CheckedContinuation<AppleResult, Error>?
    private let rawNonce: String
    private let anchor: ASPresentationAnchor

    private init(rawNonce: String, anchor: ASPresentationAnchor) {
        self.rawNonce = rawNonce
        self.anchor = anchor
        super.init()
    }

    static func signIn() async throws -> AppleResult {
        let rawNonce = randomNonceString()
        authDebug("Nonce generated length=\(rawNonce.count)")

        guard let anchor = Self.activePresentationAnchor() else {
            authDebug("No active presentation anchor available")
            throw AuthManagerAppleError.missingPresentationAnchor
        }

        let coordinator = AppleSignInCoordinator(rawNonce: rawNonce, anchor: anchor)

        return try await withCheckedThrowingContinuation { continuation in
            coordinator.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = []
            request.nonce = sha256(rawNonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator

            AppleSignInRetainer.shared.retain(coordinator)

            authDebug("Performing Apple authorization request")
            controller.performRequests()
        }
    }

    private static func activePresentationAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        if let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        return scenes
            .flatMap(\.windows)
            .first(where: { !$0.isHidden && $0.windowLevel == .normal })
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { AppleSignInRetainer.shared.release(self) }

        authDebug("Apple authorization completed")

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AuthManagerAppleError.invalidCredential)
            continuation = nil
            return
        }

        guard let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            continuation?.resume(throwing: AuthManagerAppleError.missingIdentityToken)
            continuation = nil
            return
        }

        authDebug("Apple identity token received")

        continuation?.resume(returning: AppleResult(idToken: token, rawNonce: rawNonce))
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { AppleSignInRetainer.shared.release(self) }

        authDebug("Apple authorization failed: \(error.localizedDescription)")
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }
}

// MARK: - Retainer

@MainActor
private final class AppleSignInRetainer {
    static let shared = AppleSignInRetainer()

    private var coordinators: [ObjectIdentifier: AppleSignInCoordinator] = [:]

    func retain(_ coordinator: AppleSignInCoordinator) {
        coordinators[ObjectIdentifier(coordinator)] = coordinator
    }

    func release(_ coordinator: AppleSignInCoordinator) {
        coordinators.removeValue(forKey: ObjectIdentifier(coordinator))
    }
}

// MARK: - Errors

private enum AuthManagerAppleError: LocalizedError {
    case invalidCredential
    case missingIdentityToken
    case missingPresentationAnchor

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Apple sign-in returned an invalid credential."
        case .missingIdentityToken:
            return "Apple sign-in did not return an identity token."
        case .missingPresentationAnchor:
            return "Apple sign-in could not find an active app window."
        }
    }
}

// MARK: - Nonce Helpers

private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)

    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        var random: UInt8 = 0
        let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)

        if status != errSecSuccess { continue }

        if random < charset.count {
            result.append(charset[Int(random)])
            remainingLength -= 1
        }
    }

    return result
}

private func sha256(_ input: String) -> String {
    let data = Data(input.utf8)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
