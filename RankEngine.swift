//
//  RankTier 2.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-02-26.
//


import Foundation

struct RankTier: Identifiable {
    let id = UUID()
    let name: String
    let minXP: Int
}

enum RankEngine {

    static let tiers: [RankTier] = [
        RankTier(name: "RECRUIT", minXP: 0),
        RankTier(name: "STRIKER I", minXP: 500),
        RankTier(name: "STRIKER II", minXP: 1500),
        RankTier(name: "PHANTOM I", minXP: 3000),
        RankTier(name: "PHANTOM II", minXP: 6000),
        RankTier(name: "TITAN I", minXP: 10000),
        RankTier(name: "TITAN II", minXP: 18000),
        RankTier(name: "WARLORD", minXP: 30000)
    ]

    static func currentTier(for xp: Int) -> RankTier {
        tiers.last(where: { xp >= $0.minXP }) ?? tiers[0]
    }

    static func nextTier(for xp: Int) -> RankTier? {
        guard let next = tiers.first(where: { xp < $0.minXP }) else { return nil }
        return next
    }

    static func progress(for xp: Int) -> Double {
        let current = currentTier(for: xp)
        guard let next = nextTier(for: xp) else { return 1.0 }

        let span = max(1, next.minXP - current.minXP)
        let progressed = max(0, xp - current.minXP)
        return min(1.0, Double(progressed) / Double(span))
    }

    static func xpToNext(for xp: Int) -> Int {
        guard let next = nextTier(for: xp) else { return 0 }
        return max(0, next.minXP - xp)
    }
}
