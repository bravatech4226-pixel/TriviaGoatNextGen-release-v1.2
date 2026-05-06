//
//  DailyMission.swift
//  TriviaGoatNextGen
//


import Foundation

enum DailyMission {

    // MARK: - Config

    static let bonusXP: Int = 250
    static let fallbackTopic: String = "Daily Mission: General Knowledge"
    static let questionCount: Int = 15

    /// Curated “mission pool” (fallback only; server topic wins)
    private static let curatedTopics: [String] = [
        "Daily Mission: General Knowledge Blitz",
        "Daily Mission: World Capitals",
        "Daily Mission: Science & Space",
        "Daily Mission: Ancient Civilizations",
        "Daily Mission: Famous Inventions",
        "Daily Mission: Pop Culture Classics",
        "Daily Mission: Geography Essentials",
        "Daily Mission: Sports Legends",
        "Daily Mission: Movies & TV",
        "Daily Mission: Technology Milestones",
        "Daily Mission: Music Through the Decades",
        "Daily Mission: History Turning Points",
        "Daily Mission: Mythology & Folklore",
        "Daily Mission: Animals & Nature",
        "Daily Mission: Business & Brands",
        "Daily Mission: World Cuisines"
    ]

    // MARK: - Snapshot

    struct Snapshot: Equatable {
        let dayKey: String
        let title: String
        let topic: String
        let isComplete: Bool
        let bonusXP: Int
        let questionCount: Int

        // Non-breaking additions
        let packId: String
        let answeredCount: Int
        let correctCount: Int
    }

    static func snapshot(uid: String?, team: TacticalTeam?, now: Date = Date()) -> Snapshot {
        applyDailyResetIfNeeded(uid: uid, team: team, now: now)

        let key = dayKey(for: now)
        let topic = currentTopic()
        let packId = currentPackId() ?? buildPackId(dayKey: key, topic: topic)

        return Snapshot(
            dayKey: key,
            title: "TODAY'S MISSION",
            topic: topic,
            isComplete: isCompleteToday(uid: uid, team: team, now: now),
            bonusXP: bonusXP,
            questionCount: questionCount,
            packId: packId,
            answeredCount: ud.integer(forKey: kAnsweredCount),
            correctCount: ud.integer(forKey: kCorrectCount)
        )
    }

    // Backward-compatible overload
    static func snapshot(uid: String?, now: Date = Date()) -> Snapshot {
        snapshot(uid: uid, team: nil, now: now)
    }

    // MARK: - Run Latch

    static func beginMissionRun(uid: String?, team: TacticalTeam?) {
        applyDailyResetIfNeeded(uid: uid, team: team)
        ud.set(true, forKey: kActiveRunIsMission)
    }

    static func beginMissionRun(uid: String?) {
        beginMissionRun(uid: uid, team: nil)
    }

    /// ✅ NEW: non-consuming read (prevents finalize drift)
    static func isActiveMissionRun() -> Bool {
        ud.bool(forKey: kActiveRunIsMission)
    }

    static func consumeActiveMissionRunFlag() -> Bool {
        let was = ud.bool(forKey: kActiveRunIsMission)
        if was { ud.set(false, forKey: kActiveRunIsMission) }
        return was
    }

    // MARK: - ✅ Server Alignment Hook (FOREVER FIX)

    /// Call this AFTER receiving the server payload for the daily mission.
    /// Ensures local topic + packId match the server-cached pack.
    ///
    /// If dayKey changes vs stored, we reset completion/progress for safety.
    static func setServerLockedTopic(dayKey: String, topic: String) {
        let dk = dayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let tp = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dk.isEmpty, !tp.isEmpty else { return }

        let storedDay = ud.string(forKey: kDayKey)

        // If the server says "different day", we should not carry progress over.
        if storedDay != dk {
            ud.set(false, forKey: kCompleteToday)
            ud.set(false, forKey: kActiveRunIsMission)
            ud.set(0, forKey: kAnsweredCount)
            ud.set(0, forKey: kCorrectCount)
        }

        ud.set(dk, forKey: kDayKey)
        ud.set(tp, forKey: kTopic)
        ud.set(buildPackId(dayKey: dk, topic: tp), forKey: kPackId)
    }

    // MARK: - Pack Identity (GLOBAL)

    static func packIdToday(uid: String?, team: TacticalTeam?, now: Date = Date()) -> String {
        applyDailyResetIfNeeded(uid: uid, team: team, now: now)
        return currentPackId() ?? buildPackId(dayKey: dayKey(for: now), topic: currentTopic())
    }

    static func packIdToday(uid: String?, now: Date = Date()) -> String {
        packIdToday(uid: uid, team: nil, now: now)
    }

    /// GLOBAL seed (dayKey + topic only)
    static func seedToday(uid: String?, team: TacticalTeam?, now: Date = Date()) -> Int {
        let key = dayKey(for: now)
        let topic = snapshot(uid: uid, team: team, now: now).topic
        return abs(stableHash(key + "|" + topic))
    }

    static func seedToday(uid: String?, now: Date = Date()) -> Int {
        seedToday(uid: uid, team: nil, now: now)
    }

    // MARK: - Progress + Completion

    static func recordAnswer(correct: Bool, uid: String?, team: TacticalTeam?, now: Date = Date()) {
        applyDailyResetIfNeeded(uid: uid, team: team, now: now)

        ud.set(ud.integer(forKey: kAnsweredCount) + 1, forKey: kAnsweredCount)
        if correct {
            ud.set(ud.integer(forKey: kCorrectCount) + 1, forKey: kCorrectCount)
        }

        if ud.integer(forKey: kAnsweredCount) >= questionCount {
            _ = markCompleteIfNeeded(uid: uid, team: team, now: now)
        }
    }

    static func recordAnswer(correct: Bool, uid: String?, now: Date = Date()) {
        recordAnswer(correct: correct, uid: uid, team: nil, now: now)
    }

    static func markCompleteIfNeeded(uid: String?, team: TacticalTeam?, now: Date = Date()) -> Bool {
        applyDailyResetIfNeeded(uid: uid, team: team, now: now)
        if ud.bool(forKey: kCompleteToday) { return false }
        ud.set(true, forKey: kCompleteToday)
        return true
    }

    static func markCompleteIfNeeded(uid: String?, now: Date = Date()) -> Bool {
        markCompleteIfNeeded(uid: uid, team: nil, now: now)
    }

    static func isCompleteToday(uid: String?, team: TacticalTeam?, now: Date = Date()) -> Bool {
        applyDailyResetIfNeeded(uid: uid, team: team, now: now)
        return ud.bool(forKey: kCompleteToday)
    }

    static func isCompleteToday(uid: String?, now: Date = Date()) -> Bool {
        isCompleteToday(uid: uid, team: nil, now: now)
    }

    // MARK: - Storage

    private static let ud = UserDefaults.standard

    private static let kDayKey = "tg.dailyMission.dayKey"
    private static let kCompleteToday = "tg.dailyMission.completeToday"
    private static let kActiveRunIsMission = "tg.dailyMission.activeRunIsMission"
    private static let kTopic = "tg.dailyMission.topic"
    private static let kPackId = "tg.dailyMission.packId"

    private static let kAnsweredCount = "tg.dailyMission.answeredCount"
    private static let kCorrectCount = "tg.dailyMission.correctCount"

    // MARK: - Daily Reset + Curated Pick (GLOBAL fallback)

    static func applyDailyResetIfNeeded(uid: String?, team: TacticalTeam?, now: Date = Date()) {
        let today = dayKey(for: now)

        let storedDay = ud.string(forKey: kDayKey)
        let needsResetForNewDay = (storedDay != today)
        let missingTopic = (ud.string(forKey: kTopic) == nil)

        if needsResetForNewDay || missingTopic {
            ud.set(today, forKey: kDayKey)
            ud.set(false, forKey: kCompleteToday)
            ud.set(false, forKey: kActiveRunIsMission)

            ud.set(0, forKey: kAnsweredCount)
            ud.set(0, forKey: kCorrectCount)

            // fallback deterministic pick (server still wins once payload arrives)
            let topic = pickCuratedTopic(dayKey: today)
            ud.set(topic, forKey: kTopic)
            ud.set(buildPackId(dayKey: today, topic: topic), forKey: kPackId)
        }
    }

    static func applyDailyResetIfNeeded(uid: String?, now: Date = Date()) {
        applyDailyResetIfNeeded(uid: uid, team: nil, now: now)
    }

    private static func currentTopic() -> String {
        ud.string(forKey: kTopic) ?? fallbackTopic
    }

    private static func currentPackId() -> String? {
        ud.string(forKey: kPackId)
    }

    // MARK: - Curated Selection (GLOBAL by dayKey only)

    private static func pickCuratedTopic(dayKey: String) -> String {
        let base = abs(stableHash(dayKey))
        let idx = curatedTopics.isEmpty ? 0 : (base % curatedTopics.count)
        return curatedTopics.isEmpty ? fallbackTopic : curatedTopics[idx]
    }

    // MARK: - Pack Id (stable)

    private static func buildPackId(dayKey: String, topic: String) -> String {
        let dk = dayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let tp = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let topicHash = abs(stableHash(tp.isEmpty ? fallbackTopic : tp)).description
        return "dm|\(dk)|t\(topicHash)"
    }

    // MARK: - Stable Hash (FNV-1a 64)

    private static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 1469598103934665603
        let prime: UInt64 = 1099511628211
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* prime
        }
        return Int(truncatingIfNeeded: h)
    }

    // MARK: - Day Key

    private static func dayKey(for date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return "\(y)-\(m)-\(d)"
    }
}
