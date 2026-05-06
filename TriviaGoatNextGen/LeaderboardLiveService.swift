//
//  LeaderboardLiveService.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-02-12.
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class LeaderboardLiveService: ObservableObject {

    static let shared = LeaderboardLiveService()

    @Published private(set) var topPlayers: [UserProfile] = []
    @Published private(set) var lastDelta: RankDelta? = nil

    private var listener: ListenerRegistration?
    private var lastUIDToRank: [String: Int] = [:]

    struct RankDelta: Equatable {
        let uid: String
        let oldRank: Int
        let newRank: Int
        let direction: Direction

        enum Direction: String {
            case up
            case down
            case same
        }
    }

    private init() {}

    func start(limit: Int = 25) {
        stop()

        listener = Firestore.firestore()
            .collection("leaderboard")
            .document("global")
            .collection("top")
            .order(by: "xp", descending: true)
            .limit(to: limit)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }

                if let err {
                    print("⚠️ leaderboard live err:", err)
                    return
                }

                guard let snap else { return }

                var profiles: [UserProfile] = []
                var uids: [String] = []

                for doc in snap.documents {
                    if let p = try? doc.data(as: UserProfile.self) {
                        profiles.append(p)
                        uids.append(doc.documentID)
                    }
                }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.computeDeltaAndPublish(profiles: profiles, uids: uids)
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    private func computeDeltaAndPublish(profiles: [UserProfile], uids: [String]) async {
        topPlayers = profiles

        var newMap: [String: Int] = [:]
        for (idx, uid) in uids.enumerated() {
            newMap[uid] = idx + 1
        }

        if let myUID = await AuthManager.shared.currentUID(),
           let newRank = newMap[myUID] {

            let oldRank = lastUIDToRank[myUID] ?? newRank
            let dir: RankDelta.Direction =
                newRank < oldRank ? .up :
                (newRank > oldRank ? .down : .same)

            if oldRank != newRank {
                lastDelta = RankDelta(
                    uid: myUID,
                    oldRank: oldRank,
                    newRank: newRank,
                    direction: dir
                )
            }
        }

        lastUIDToRank = newMap
    }
}
