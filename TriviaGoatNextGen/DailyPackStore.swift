//
//  DailyPackStore.swift
//  TriviaGoatNextGen
//
//  Production-ready daily topic cache for iOS gameplay + Global Battle.
//  - exact-topic warm checks
//  - disk + memory caching
//  - shared in-flight fetch reuse
//  - safe fallback behavior
//  - aligned with TriviaPackClient + GlobalBattleSession
//

import Foundation
import Combine

@MainActor
final class DailyPackStore: ObservableObject {

    static let shared = DailyPackStore()

    // MARK: - Public API

    /// Keep aligned with topic surfaces exposed in iOS.
    let topics: [String] = [
        "General Knowledge",
        "Science",
        "Technology",
        "Sports",
        "History",
        "Geography",
        "Movies",
        "Music",
        "Pop Culture",
        "Animals",
        "Food",
        "Space"
    ]

    /// Maximum warm inventory kept per topic per day.
    let perTopicCount: Int = 50

    /// Bump this when cache schema or warm logic changes.
    let packVersion: Int = 3

    /// Fast in-memory store.
    private(set) var packsByTopic: [String: [TriviaQuestion]] = [:]

    @Published private(set) var isReady: Bool = false
    @Published private(set) var lastLoadError: String? = nil

    // MARK: - Internals

    private let client = TriviaPackClient()

    private var currentDayKey: String?
    private var ensureAllTask: Task<Void, Never>?
    private var inFlightTopicTasks: [String: Task<[TriviaQuestion], Never>] = [:]

    private init() {}

    // MARK: - Ensure Daily Cache

    /// Full daily preload.
    /// Loads disk cache first, then fills only weak/missing topics.
    func ensureTodayLoaded(dayKey: String, forceRefresh: Bool = false) async {
        let normalizedDayKey = normalizedDayKey(dayKey)
        guard !normalizedDayKey.isEmpty else { return }

        if currentDayKey != normalizedDayKey {
            resetForNewDay(dayKey: normalizedDayKey)
        }

        if loadFromDisk(dayKey: normalizedDayKey) {
            isReady = hasAtLeastOneUsableTopic

            if !forceRefresh && !needsRefresh {
                return
            }
        }

        if let existingTask = ensureAllTask {
            await existingTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            self.lastLoadError = nil

            var sawFailure = false
            var failureMessages: [String] = []

            for topic in self.topics {
                let cleanedTopic = self.normalizedTopic(topic)
                let exactCount = self.exactQuestionsForTopic(cleanedTopic).count

                if !forceRefresh && exactCount >= self.minimumUsableTopicCount {
                    continue
                }

                let fetched = await self.fetchTopicPackShared(
                    topic: cleanedTopic,
                    count: self.perTopicCount
                )

                if fetched.count >= self.minimumUsableTopicCount {
                    self.packsByTopic[cleanedTopic] = self.dedupeQuestions(fetched)
                } else {
                    sawFailure = true
                    failureMessages.append("\(cleanedTopic): insufficient inventory")
                }
            }

            self.isReady = self.hasAtLeastOneUsableTopic
            self.saveToDisk(dayKey: normalizedDayKey, packsByTopic: self.packsByTopic)

            if sawFailure {
                self.lastLoadError = failureMessages.joined(separator: " | ")
            }

            Task.detached {
                await FirestoreService.shared.logEvent(
                    name: "daily_pack_store_ensure_complete",
                    uid: nil,
                    props: [
                        "dayKey": normalizedDayKey,
                        "ready": self.isReady,
                        "topicCount": self.packsByTopic.count
                    ]
                )
            }
        }

        ensureAllTask = task
        await task.value
        ensureAllTask = nil
    }

    /// Preheats exactly one topic for match-grade use.
    /// Global Battle should use this.
    func preheatTopicIfNeeded(
        dayKey: String,
        topic: String,
        minimumCount: Int,
        forceFetchIfInsufficient: Bool
    ) async -> [TriviaQuestion] {
        let normalizedDayKey = normalizedDayKey(dayKey)
        let cleanedTopic = normalizedTopic(topic)
        let targetCount = max(1, min(max(minimumCount, 10), perTopicCount))

        guard !normalizedDayKey.isEmpty else {
            return fallbackSelection(for: cleanedTopic, count: targetCount)
        }

        if currentDayKey != normalizedDayKey {
            resetForNewDay(dayKey: normalizedDayKey)
        }

        _ = loadFromDisk(dayKey: normalizedDayKey)

        let exactCached = exactQuestionsForTopic(cleanedTopic)
        if exactCached.count >= targetCount {
            isReady = hasAtLeastOneUsableTopic
            return Array(exactCached.shuffled().prefix(targetCount))
        }

        guard forceFetchIfInsufficient else {
            isReady = hasAtLeastOneUsableTopic
            return fallbackSelection(for: cleanedTopic, count: targetCount)
        }

        let fetched = await fetchTopicPackShared(topic: cleanedTopic, count: targetCount)

        if !fetched.isEmpty {
            packsByTopic[cleanedTopic] = dedupeQuestions(fetched)
            saveToDisk(dayKey: normalizedDayKey, packsByTopic: packsByTopic)
        }

        isReady = hasAtLeastOneUsableTopic

        let finalExact = exactQuestionsForTopic(cleanedTopic)
        if finalExact.count >= targetCount {
            return Array(finalExact.shuffled().prefix(targetCount))
        }

        return fallbackSelection(for: cleanedTopic, count: targetCount)
    }

    /// Exact-topic count only. No general fallback.
    func warmedQuestionCount(for topic: String) -> Int {
        exactQuestionsForTopic(normalizedTopic(topic)).count
    }

    /// True only when the exact topic is truly warm.
    func hasWarmQuestions(for topic: String, minimumCount: Int) -> Bool {
        warmedQuestionCount(for: topic) >= max(1, minimumCount)
    }

    // MARK: - Match Retrieval

    /// Match-safe retrieval with avoid set.
    /// Exact topic first, then General Knowledge fallback, then hard fallback.
    func questionsForMatch(topic: String, count: Int, avoidIds: Set<String>) -> [TriviaQuestion] {
        let cleanedTopic = normalizedTopic(topic)
        let safeCount = max(1, min(count, 60))

        let source = questionsForTopicWithFallback(cleanedTopic)
        if !source.isEmpty {
            let filtered = source.filter { !avoidIds.contains(Self.qid($0)) }

            if filtered.count >= safeCount {
                return Array(filtered.shuffled().prefix(safeCount))
            }

            let mixed = dedupeQuestions(filtered + source)
            if !mixed.isEmpty {
                return Array(mixed.shuffled().prefix(min(safeCount, mixed.count)))
            }
        }

        let fallback = Self.fallbackQuestions().filter { !avoidIds.contains(Self.qid($0)) }
        if fallback.count >= safeCount {
            return Array(fallback.shuffled().prefix(safeCount))
        }

        let mixedFallback = dedupeQuestions(fallback + Self.fallbackQuestions())
        return Array(mixedFallback.shuffled().prefix(min(safeCount, mixedFallback.count)))
    }

    static func qid(_ question: TriviaQuestion) -> String {
        let joined = question.prompt + "|" + question.choices.joined(separator: "|")
        return String(joined.hashValue)
    }

    // MARK: - Shared Topic Fetch

    private func fetchTopicPackShared(topic: String, count: Int) async -> [TriviaQuestion] {
        let safeCount = max(1, min(count, perTopicCount))
        let key = "\(topic.lowercased())|\(safeCount)"

        if let existingTask = inFlightTopicTasks[key] {
            return await existingTask.value
        }

        let task = Task<[TriviaQuestion], Never> { [weak self] in
            guard let self else { return [] }

            do {
                let fetched = try await self.fetchTopicPack(topic: topic, count: safeCount)

                Task.detached {
                    await FirestoreService.shared.logEvent(
                        name: "daily_pack_topic_fetch_success",
                        uid: nil,
                        props: [
                            "topic": topic,
                            "count": fetched.count
                        ]
                    )
                }

                return fetched
            } catch {
                Task.detached {
                    await FirestoreService.shared.logEvent(
                        name: "daily_pack_topic_fetch_failed",
                        uid: nil,
                        props: [
                            "topic": topic,
                            "requestedCount": safeCount,
                            "error": error.localizedDescription
                        ]
                    )
                }

                return []
            }
        }

        inFlightTopicTasks[key] = task
        let result = await task.value
        inFlightTopicTasks.removeValue(forKey: key)
        return result
    }

    // MARK: - Disk Persistence

    private struct DailyCacheFile: Codable {
        let dayKey: String
        let version: Int
        let packs: [String: [CodableQuestion]]
    }

    private struct CodableQuestion: Codable {
        let prompt: String
        let choices: [String]
        let correctIndex: Int

        init(_ question: TriviaQuestion) {
            self.prompt = question.prompt
            self.choices = question.choices
            self.correctIndex = question.correctIndex
        }

        func toModel() -> TriviaQuestion {
            TriviaQuestion(
                prompt: prompt,
                choices: choices,
                correctIndex: correctIndex
            )
        }
    }

    private func cacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("daily_topic_packs_v\(packVersion).json")
    }

    @discardableResult
    private func loadFromDisk(dayKey: String) -> Bool {
        guard let url = cacheURL() else { return false }
        guard let data = try? Data(contentsOf: url) else { return false }
        guard let file = try? JSONDecoder().decode(DailyCacheFile.self, from: data) else { return false }

        guard file.dayKey == dayKey else { return false }
        guard file.version == packVersion else { return false }

        var rebuilt: [String: [TriviaQuestion]] = [:]
        for (topic, questions) in file.packs {
            rebuilt[normalizedTopic(topic)] = dedupeQuestions(questions.map { $0.toModel() })
        }

        packsByTopic = rebuilt
        return true
    }

    private func saveToDisk(dayKey: String, packsByTopic: [String: [TriviaQuestion]]) {
        guard let url = cacheURL() else { return }

        var packs: [String: [CodableQuestion]] = [:]
        for (topic, questions) in packsByTopic {
            packs[topic] = dedupeQuestions(questions).map(CodableQuestion.init)
        }

        let file = DailyCacheFile(
            dayKey: dayKey,
            version: packVersion,
            packs: packs
        )

        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    // MARK: - Helpers

    private var minimumUsableTopicCount: Int { 10 }

    private var hasAtLeastOneUsableTopic: Bool {
        packsByTopic.values.contains { dedupeQuestions($0).count >= minimumUsableTopicCount }
    }

    private var needsRefresh: Bool {
        for topic in topics {
            let cleaned = normalizedTopic(topic)
            if exactQuestionsForTopic(cleaned).count < minimumUsableTopicCount {
                return true
            }
        }
        return false
    }

    private func normalizedDayKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTopic(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "General Knowledge" : cleaned
    }

    private func resetForNewDay(dayKey: String) {
        currentDayKey = dayKey
        packsByTopic = [:]
        isReady = false
        lastLoadError = nil
        ensureAllTask?.cancel()
        ensureAllTask = nil
        inFlightTopicTasks.removeAll()
    }

    /// Exact-topic only.
    private func exactQuestionsForTopic(_ topic: String) -> [TriviaQuestion] {
        dedupeQuestions(packsByTopic[topic] ?? [])
    }

    /// Retrieval helper only.
    /// Allows General Knowledge fallback for serving, but not for warm validation.
    private func questionsForTopicWithFallback(_ topic: String) -> [TriviaQuestion] {
        let exact = exactQuestionsForTopic(topic)
        if !exact.isEmpty {
            return exact
        }

        if topic != "General Knowledge" {
            let general = exactQuestionsForTopic("General Knowledge")
            if !general.isEmpty {
                return general
            }
        }

        return []
    }

    private func fallbackSelection(for topic: String, count: Int) -> [TriviaQuestion] {
        let source = questionsForTopicWithFallback(topic)
        if !source.isEmpty {
            return Array(source.shuffled().prefix(min(count, source.count)))
        }

        let fallback = Self.fallbackQuestions()
        return Array(fallback.shuffled().prefix(min(count, fallback.count)))
    }

    private func dedupeQuestions(_ input: [TriviaQuestion]) -> [TriviaQuestion] {
        var seen = Set<String>()
        var output: [TriviaQuestion] = []

        for question in input {
            let key = Self.qid(question)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(question)
        }

        return output
    }

    private func fetchTopicPack(topic: String, count: Int) async throws -> [TriviaQuestion] {
        let safeCount = max(1, min(count, perTopicCount))
        let result = try await client.generatePack(for: topic, count: safeCount)
        return dedupeQuestions(result)
    }

    // MARK: - Fallback

    private static func fallbackQuestions() -> [TriviaQuestion] {
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
            ),
            TriviaQuestion(
                prompt: "What is the capital of Japan?",
                choices: ["Seoul", "Tokyo", "Kyoto", "Osaka"],
                correctIndex: 1
            ),
            TriviaQuestion(
                prompt: "Which gas do plants absorb from the atmosphere?",
                choices: ["Oxygen", "Hydrogen", "Carbon Dioxide", "Nitrogen"],
                correctIndex: 2
            ),
            TriviaQuestion(
                prompt: "How many continents are there?",
                choices: ["5", "6", "7", "8"],
                correctIndex: 2
            ),
            TriviaQuestion(
                prompt: "What is the largest ocean on Earth?",
                choices: ["Atlantic Ocean", "Indian Ocean", "Pacific Ocean", "Arctic Ocean"],
                correctIndex: 2
            )
        ]
    }
}
