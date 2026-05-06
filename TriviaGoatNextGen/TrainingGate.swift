//
//  TrainingGate.swift
//  TriviaGoatNextGen
//
//  Daily Free gate storage + snapshot
//

import Foundation

struct TrainingGate: Equatable {

    // MARK: - Config

    /// ✅ Daily free uses for non-Pro users
    static let dailyFreeLimit: Int = 1

    /// What the UI can show for "unlimited" (keeps UI simple without special casing).
    private static let proUnlimitedCount: Int = 999

    // MARK: - Snapshot (UI-friendly)

    let dailyLimit: Int
    let usedToday: Int
    let remainingToday: Int
    let canUseFreeToday: Bool
    let dayKey: String

    /// Backwards-compatible snapshot (assumes non-pro).
    static func snapshot(now: Date = Date()) -> TrainingGate {
        snapshot(isPro: false, now: now)
    }

    /// ✅ Preferred snapshot: pass your effective pro value.
    static func snapshot(isPro: Bool, now: Date = Date()) -> TrainingGate {
        applyDailyResetIfNeeded(now: now)

        let key = dayKey(for: now)
        let used = usedToday()

        if isPro {
            return TrainingGate(
                dailyLimit: proUnlimitedCount,
                usedToday: used,
                remainingToday: proUnlimitedCount,
                canUseFreeToday: true,
                dayKey: key
            )
        }

        let remaining = max(0, dailyFreeLimit - used)

        return TrainingGate(
            dailyLimit: dailyFreeLimit,
            usedToday: used,
            remainingToday: remaining,
            canUseFreeToday: remaining > 0,
            dayKey: key
        )
    }

    // MARK: - Convenience

    /// True when a non-pro user has no free uses left today.
    static func isBlocked(isPro: Bool, now: Date = Date()) -> Bool {
        !snapshot(isPro: isPro, now: now).canUseFreeToday
    }

    /// Consume one free use ONLY if non-pro.
    static func consumeOneUseIfNeeded(isPro: Bool, now: Date = Date()) {
        guard !isPro else { return }
        consumeOneFreeUse(now: now)
    }

    // MARK: - Storage

    private static let ud = UserDefaults.standard
    private static let kDayKey = "tg.training.dayKey"
    private static let kUsedToday = "tg.training.usedToday"

    static func applyDailyResetIfNeeded(now: Date = Date()) {
        let today = dayKey(for: now)
        let stored = ud.string(forKey: kDayKey)

        if stored != today {
            ud.set(today, forKey: kDayKey)
            ud.set(0, forKey: kUsedToday)
        }
    }

    /// Low-level consume (non-pro callers should prefer `consumeOneUseIfNeeded(isPro:)`)
    static func consumeOneFreeUse(now: Date = Date()) {
        applyDailyResetIfNeeded(now: now)

        let used = usedToday()
        guard used < dailyFreeLimit else { return }

        ud.set(used + 1, forKey: kUsedToday)
    }

    static func usedToday() -> Int {
        max(0, ud.integer(forKey: kUsedToday))
    }

    // MARK: - Helpers

    private static func dayKey(for date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

