//
//  TopicQuestionPool.swift
//  TriviaGoatNextGen
//

import Foundation

@MainActor
final class TopicQuestionPool {

    static let shared = TopicQuestionPool()

    private init() {}

    // MARK: - Storage

    /// Real topic pools only.
    /// IMPORTANT:
    /// Do not store fallback questions in here, or the session can mistakenly
    /// believe a topic is ready when it is still only holding generic content.
    private var topicPools: [String: [TriviaQuestion]] = [:]

    /// Topic keys that have completed a successful Firebase load.
    private var firebaseReady: Set<String> = []

    /// Topic keys currently being fetched.
    private var inFlightFetch: Set<String> = []

    /// Tracks which questions have already been served for a topic
    /// so we do not repeat until we exhaust the pool.
    private var usedQuestionKeysByTopic: [String: Set<String>] = [:]

    /// Dedicated fallback pool usage tracking.
    /// This is kept separate so fallback does not pollute real topic pools.
    private var fallbackUsedKeys: Set<String> = []

    /// Last fetch failure time by topic.
    /// Helpful for light cooldown behavior if a topic repeatedly fails.
    private var lastFetchFailureAtByTopic: [String: Date] = [:]

    // MARK: - Tuning

    /// Minimum acceptable real pack size before we consider a topic "ready".
    /// Keeps tiny/weak payloads from being treated like a healthy live topic.
    private let minimumUsableLivePackCount: Int = 10

    /// Failure cooldown to avoid hammering backend when a topic just failed.
    private let refetchCooldownAfterFailure: TimeInterval = 2.0

    // MARK: - Normalization

    private func key(_ topic: String) -> String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func questionKey(_ question: TriviaQuestion) -> String {
        let prompt = question.prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let choices = question.choices
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "||")

        return "\(prompt)|\(choices)|\(question.correctIndex)"
    }

    // MARK: - Public State

    func isFirebaseReady(_ topic: String) -> Bool {
        firebaseReady.contains(key(topic))
    }

    func hasUsableLivePool(for topic: String) -> Bool {
        let k = key(topic)
        guard let pool = topicPools[k] else { return false }
        return firebaseReady.contains(k) && pool.count >= minimumUsableLivePackCount
    }

    /// Returns cached live questions immediately if present.
    /// If not present, begins Firebase fetch but does NOT seed fallback into topic cache.
    @discardableResult
    func loadTopic(_ topic: String) async -> [TriviaQuestion] {
        let k = key(topic)

        if let cached = topicPools[k], !cached.isEmpty {
            return cached
        }

        startFetchIfNeeded(for: topic)
        return []
    }

    /// Waits for a topic to become genuinely live-ready.
    /// Returns true if Firebase topic data became available in time.
    @discardableResult
    func waitUntilReady(topic: String, timeoutSeconds: Double) async -> Bool {
        let k = key(topic)
        let start = Date()

        while !hasUsableLivePool(for: topic) {
            if Date().timeIntervalSince(start) >= timeoutSeconds {
                return false
            }

            startFetchIfNeeded(for: topic)
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        return firebaseReady.contains(k)
    }

    // MARK: - Reset helpers

    func resetUsageTracking() {
        usedQuestionKeysByTopic.removeAll()
        fallbackUsedKeys.removeAll()
    }

    func resetUsageTracking(for topic: String) {
        usedQuestionKeysByTopic.removeValue(forKey: key(topic))
    }

    // MARK: - Fetch control

    private func startFetchIfNeeded(for topic: String) {
        let k = key(topic)

        if hasUsableLivePool(for: topic) { return }
        if inFlightFetch.contains(k) { return }

        if let lastFailureAt = lastFetchFailureAtByTopic[k],
           Date().timeIntervalSince(lastFailureAt) < refetchCooldownAfterFailure {
            return
        }

        inFlightFetch.insert(k)

        Task { [weak self] in
            guard let self else { return }
            await self.fetchFromFirebase(topic)
        }
    }
    enum NearbyFallbackQuestions {
        static func all() -> [TriviaQuestion] {
            [
                TriviaQuestion(
                    prompt: "In computing, what does 'CPU' stand for?",
                    choices: [
                        "Central Processing Unit",
                        "Computer Personal Unit",
                        "Core Process Utility",
                        "Central Program Upload"
                    ],
                    correctIndex: 0
                ),
                TriviaQuestion(
                    prompt: "Which planet is known as the Red Planet?",
                    choices: ["Venus", "Mars", "Jupiter", "Mercury"],
                    correctIndex: 1
                )
                // 🔥 keep only a SMALL clean set — don’t copy all 10
            ]
        }
    }

    // MARK: - Firebase fetch

    private func fetchFromFirebase(_ topic: String) async {
        let k = key(topic)

        defer { inFlightFetch.remove(k) }

        do {
            let questions = try await TriviaPackClient()
                .generatePack(for: topic, count: 50)

            let sanitized = sanitizeLiveQuestions(questions)

            guard sanitized.count >= minimumUsableLivePackCount else {
                lastFetchFailureAtByTopic[k] = Date()
                print("⚠️ Firebase topic pack too small / weak for \(topic) count=\(sanitized.count)")
                return
            }

            topicPools[k] = sanitized.shuffled()
            firebaseReady.insert(k)
            lastFetchFailureAtByTopic.removeValue(forKey: k)

            // Keep usage only for questions that still exist in the new pool.
            let validKeys = Set(sanitized.map(questionKey(_:)))
            let existingUsed = usedQuestionKeysByTopic[k] ?? []
            usedQuestionKeysByTopic[k] = existingUsed.intersection(validKeys)

            print("📦 Loaded Firebase topic pack \(topic) questions=\(sanitized.count)")
        } catch {
            lastFetchFailureAtByTopic[k] = Date()
            print("⚠️ Topic pack fetch failed for \(topic): \(error)")
        }
    }

    // MARK: - Draw logic

    /// Draw behavior:
    /// - prefers a real Firebase-backed topic pool
    /// - waits briefly for live data when requested
    /// - only falls back if live topic data still is not available
    /// - keeps fallback isolated from real topic caches
    func drawQuestions(
        topic: String,
        count: Int,
        preferFirebaseWaitSeconds: Double = 0.0
    ) async -> [TriviaQuestion] {
        guard count > 0 else { return [] }

        let k = key(topic)

        _ = await loadTopic(topic)

        let becameReady: Bool
        if preferFirebaseWaitSeconds > 0 {
            becameReady = await waitUntilReady(topic: topic, timeoutSeconds: preferFirebaseWaitSeconds)
        } else {
            becameReady = hasUsableLivePool(for: topic)
        }

        if becameReady, let livePool = topicPools[k], !livePool.isEmpty {
            return drawFromPool(
                livePool,
                count: count,
                usedKeys: &usedQuestionKeysByTopic[k, default: []]
            )
        }

        // Hard fallback path only when live topic data is still unavailable.
        let fallbackPool = sanitizeFallbackQuestions(NearbyFallbackQuestions.all().shuffled())
        guard !fallbackPool.isEmpty else { return [] }

        print("⚠️ Using fallback questions for topic \(topic) count=\(count)")

        return drawFromPool(
            fallbackPool,
            count: count,
            usedKeys: &fallbackUsedKeys
        )
    }

    // MARK: - Pool draw helpers

    private func drawFromPool(
        _ pool: [TriviaQuestion],
        count: Int,
        usedKeys: inout Set<String>
    ) -> [TriviaQuestion] {
        guard !pool.isEmpty else { return [] }

        let allKeys = Set(pool.map(questionKey(_:)))

        // If exhausted, reset usage and begin a fresh cycle.
        if usedKeys.isSuperset(of: allKeys) || usedKeys.count >= allKeys.count {
            usedKeys.removeAll()
        }

        let freshQuestions = pool
            .filter { !usedKeys.contains(questionKey($0)) }
            .shuffled()

        var selected = Array(freshQuestions.prefix(count))

        // If exhausted mid-draw, reset cycle and top up without duplicates in the same draw.
        if selected.count < count {
            usedKeys.removeAll()

            let selectedKeys = Set(selected.map(questionKey(_:)))
            let refill = pool
                .filter { !selectedKeys.contains(questionKey($0)) }
                .shuffled()

            let needed = count - selected.count
            selected.append(contentsOf: refill.prefix(needed))
        }

        for question in selected {
            usedKeys.insert(questionKey(question))
        }

        return selected
    }

    // MARK: - Sanitizers

    private func sanitizeLiveQuestions(_ questions: [TriviaQuestion]) -> [TriviaQuestion] {
        dedupeQuestions(questions).filter { isValidQuestion($0) }
    }

    private func sanitizeFallbackQuestions(_ questions: [TriviaQuestion]) -> [TriviaQuestion] {
        dedupeQuestions(questions).filter { isValidQuestion($0) }
    }

    private func dedupeQuestions(_ questions: [TriviaQuestion]) -> [TriviaQuestion] {
        var seen = Set<String>()
        var result: [TriviaQuestion] = []

        for question in questions {
            let qKey = questionKey(question)
            guard !seen.contains(qKey) else { continue }
            seen.insert(qKey)
            result.append(question)
        }

        return result
    }

    private func isValidQuestion(_ question: TriviaQuestion) -> Bool {
        let prompt = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return false }

        guard question.choices.count == 4 else { return false }
        guard (0..<4).contains(question.correctIndex) else { return false }

        let cleanedChoices = question.choices.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard cleanedChoices.allSatisfy({ !$0.isEmpty }) else { return false }

        let uniqueChoices = Set(cleanedChoices.map { $0.lowercased() })
        guard uniqueChoices.count == 4 else { return false }

        return true
    }
}
