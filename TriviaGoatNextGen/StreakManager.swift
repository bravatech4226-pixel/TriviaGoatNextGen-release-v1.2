// StreakManager.swift
//  Created by Michael Houlder on 2026-03-04.
//

import Foundation
import Combine
@preconcurrency import UserNotifications
import FirebaseFirestore

@MainActor
final class StreakManager: ObservableObject {

    static let shared = StreakManager()

    // MARK: - Public state

    @Published private(set) var streakCount: Int = 0
    @Published private(set) var lastDayKey: String? = nil
    @Published private(set) var freezeUsedCount: Int = 0

    /// Free users get 1 lifetime streak save. Pro gets unlimited saves.
    private let freeUserLifetimeSaves: Int = 1

    // MARK: - Storage keys

    private let ud = UserDefaults.standard
    private let kStreakCount = "tg.streak.count"
    private let kLastDayKey = "tg.streak.lastDayKey"
    private let kFreezeUsed = "tg.streak.freezeUsed"
    private let kLastReconcileKey = "tg.streak.lastReconcileKey"
    private let kLastCompletionKey = "tg.streak.lastCompletionKey"
    private let kReminderScheduledForDayKey = "tg.streak.reminderScheduledForDayKey"

    private init() {
        load()
    }

    // MARK: - Snapshot

    struct Snapshot: Equatable {
        let streakCount: Int
        let lastDayKey: String?
        let freezeUsedCount: Int
        let canUseFreeze: Bool
        let isAtRiskToday: Bool
    }

    func snapshot(isPro: Bool, now: Date = Date()) -> Snapshot {
        reconcile(isPro: isPro, now: now)

        let today = dayKey(for: now)
        let atRisk = (lastDayKey != today)

        return Snapshot(
            streakCount: streakCount,
            lastDayKey: lastDayKey,
            freezeUsedCount: freezeUsedCount,
            canUseFreeze: canUseFreeze(isPro: isPro),
            isAtRiskToday: atRisk
        )
    }

    // MARK: - Core

    /// Call on app foreground + before key screens.
    func reconcile(isPro: Bool, now: Date = Date()) {
        let today = dayKey(for: now)

        // run once per day
        if ud.string(forKey: kLastReconcileKey) == today { return }
        ud.set(today, forKey: kLastReconcileKey)

        guard let last = lastDayKey else {
            persist()
            return
        }

        let gap = dayGap(from: last, to: today)
        if gap <= 1 {
            persist()
            return
        }

        // gap >= 2: missed at least one full day
        // If exactly 2, allow one freeze to cover the missed day.
        if gap == 2, canUseFreeze(isPro: isPro) {
            consumeFreeze()
            lastDayKey = dayKey(for: Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now) // yesterday
            persist()
            scheduleStreakReminderIfNeeded(now: now)
            return
        }

        // break
        streakCount = 0
        lastDayKey = nil
        persist()
    }

    /// Call once when a run completes (Results screen).
    func markRunCompleted(uid: String?, isPro: Bool, now: Date = Date()) {
        reconcile(isPro: isPro, now: now)

        let today = dayKey(for: now)

        // de-dupe
        if ud.string(forKey: kLastCompletionKey) == today { return }
        ud.set(today, forKey: kLastCompletionKey)

        if let last = lastDayKey {
            let gap = dayGap(from: last, to: today)
            if gap == 1 {
                streakCount = max(0, streakCount) + 1
            } else if gap == 0 {
                // already today (should be deduped)
            } else if gap == 2, canUseFreeze(isPro: isPro) {
                consumeFreeze()
                streakCount = max(0, streakCount) + 1
            } else {
                streakCount = 1
            }
        } else {
            streakCount = 1
        }

        lastDayKey = today
        persist()

        if let uid, !uid.isEmpty {
            Task { await mirrorToFirestore(uid: uid, today: today) }
        }
    }
    
    func missedDaysCount(now: Date = Date()) -> Int {
        let today = dayKey(for: now)
        guard let last = lastDayKey else { return 0 }
        let gap = dayGap(from: last, to: today)
        return max(0, gap - 1)
    }

    // MARK: - Multiplier

    /// +5% per day up to +50% (cap at 10 streak)
    func xpMultiplier() -> Double {
        let capped = min(10, max(0, streakCount))
        return 1.0 + (Double(capped) * 0.05)
    }

    // MARK: - Freeze

    private func canUseFreeze(isPro: Bool) -> Bool {
        if isPro { return true }
        return freezeUsedCount < freeUserLifetimeSaves
    }

    private func consumeFreeze() {
        freezeUsedCount = max(0, freezeUsedCount) + 1
    }

    // MARK: - Local reminder (8pm warning)

    /// Schedules a local notification at 8:00pm local time *today* if user hasn't completed today.
    func scheduleStreakReminderIfNeeded(now: Date = Date()) {
        let today = dayKey(for: now)
        if lastDayKey == today { return }

        if ud.string(forKey: kReminderScheduledForDayKey) == today { return }
        ud.set(today, forKey: kReminderScheduledForDayKey)

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

            let cal = Calendar.current
            let compsNow = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)

            var triggerComps = DateComponents()
            triggerComps.year = compsNow.year
            triggerComps.month = compsNow.month
            triggerComps.day = compsNow.day
            triggerComps.hour = 20
            triggerComps.minute = 0

            // If it's already past 8pm, schedule a "last call" in 60 seconds.
            let eightPM = cal.date(from: triggerComps) ?? now
            let trigger: UNNotificationTrigger
            if now >= eightPM {
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
            } else {
                trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
            }

            let content = UNMutableNotificationContent()
            content.title = "Streak at risk 🔥"
            content.body = "Run Training today to keep your streak alive."
            content.sound = .default

            let req = UNNotificationRequest(
                identifier: "tg.streak.reminder.\(today)",
                content: content,
                trigger: trigger
            )

            center.add(req, withCompletionHandler: nil)
        }
    }

    // MARK: - Persistence

    private func load() {
        streakCount = ud.integer(forKey: kStreakCount)
        lastDayKey = ud.string(forKey: kLastDayKey)
        freezeUsedCount = ud.integer(forKey: kFreezeUsed)
    }

    private func persist() {
        ud.set(streakCount, forKey: kStreakCount)
        ud.set(lastDayKey, forKey: kLastDayKey)
        ud.set(freezeUsedCount, forKey: kFreezeUsed)
    }

    // MARK: - Firestore mirror (best-effort)

    private func mirrorToFirestore(uid: String, today: String) async {
        do {
            try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData(
                    [
                        "streakCount": streakCount,
                        "streakDayKey": today,
                        "streakFreezeUsed": freezeUsedCount
                    ],
                    merge: true
                )
        } catch {
            // best-effort only
            print("⚠️ streak mirror failed: \(error)")
        }
    }

    // MARK: - Date helpers

    private func dayKey(for date: Date) -> String {
        // stable: YYYY-MM-DD
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)

        let mm = String(format: "%02d", m)
        let dd = String(format: "%02d", d)
        return "\(y)-\(mm)-\(dd)"
    }

    private func parseDayKey(_ key: String) -> Date? {
        // key: "YYYY-MM-DD"
        let parts = key.split(separator: "-").map { Int($0) ?? 0 }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 12 // noon to avoid DST edges
        return Calendar.current.date(from: comps)
    }

    private func dayGap(from fromKey: String, to toKey: String) -> Int {
        guard
            let a0 = parseDayKey(fromKey),
            let b0 = parseDayKey(toKey)
        else { return 999 }

        let cal = Calendar.current
        let a = cal.startOfDay(for: a0)
        let b = cal.startOfDay(for: b0)
        return cal.dateComponents([.day], from: a, to: b).day ?? 999
    }
}

