//
//  AppState+ProfilePersistence.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Persist the current profile (if signed in) then refresh leaderboard.
//  SINGLE SOURCE OF TRUTH: Do not duplicate this function anywhere else.
//

import Foundation

extension AppState {

    /// Saves current profile to Firestore (if signed in) then refreshes leaderboard.
    /// Safe to call multiple times.
    @MainActor
    func persistProfileAndRefreshLeaderboard() async {
        guard let uid = await AuthManager.shared.currentUID() else {
            refreshLeaderboard()
            return
        }

        do {
            try await FirestoreService.shared.saveProfile(uid: uid, profile: profile)
        } catch {
            // Don’t block UX on persistence failures during early dev.
            print("⚠️ Persist profile failed: \(error)")
        }

        refreshLeaderboard()
    }
}
