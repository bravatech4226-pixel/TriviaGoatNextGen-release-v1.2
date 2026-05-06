//
//  TriviaPackClient.swift
//  TriviaGoatNextGen
//
//  Firebase Functions client for trivia packs
//  ✅ Daily Mission is SERVER-authoritative (send dayKey only)
//  ✅ Swift 6 safe
//  ✅ Ad-hoc topic packs reject undersized responses for lobby preheat
//  ✅ In-flight request deduplication (no duplicate token burn)
//  ✅ Smart retry logic + telemetry hooks
//

import Foundation
import FirebaseFunctions

struct TriviaPackClient {

    // MARK: - Types

    struct DailyMissionPayload {
        let questions: [TriviaQuestion]
        let topic: String
        let dayKey: String
        let generatedAt: String
        let cached: Bool
        let model: String?
    }

    // MARK: - Firebase Functions

    private let functions = Functions.functions(region: "us-central1")

    // MARK: - Token Burn Protection

    private actor PackCache {

        struct Entry {
            let createdAt: Date
            let questions: [TriviaQuestion]
        }

        private var store: [String: Entry] = [:]
        private var inFlight: [String: Task<[TriviaQuestion], Error>] = [:]

        func get(key: String, maxAgeSeconds: TimeInterval) -> [TriviaQuestion]? {
            guard let entry = store[key] else { return nil }

            if Date().timeIntervalSince(entry.createdAt) <= maxAgeSeconds {
                return entry.questions
            } else {
                store.removeValue(forKey: key)
                return nil
            }
        }

        func set(key: String, questions: [TriviaQuestion]) {
            store[key] = Entry(createdAt: Date(), questions: questions)
        }

        func clear(key: String) {
            store.removeValue(forKey: key)
        }

        func getOrCreateTask(
            key: String,
            create: @escaping () async throws -> [TriviaQuestion]
        ) async throws -> [TriviaQuestion] {

            if let existing = inFlight[key] {
                return try await existing.value
            }

            let task = Task {
                try await create()
            }

            inFlight[key] = task

            defer {
                inFlight.removeValue(forKey: key)
            }

            return try await task.value
        }
    }

    private static let packCache = PackCache()

    // MARK: - Training / Ad-hoc Pack

    func generatePack(for topic: String, count: Int = 50) async throws -> [TriviaQuestion] {
        let cleanedTopic = normalizedTopic(topic)
        let requestedCount = max(20, min(count, 50))
        let minimumAcceptableCount = requestedCount

        let key = "adhoc|\(cleanedTopic.lowercased())|\(requestedCount)"

        // ✅ Fast cache hit
        if let cached = await Self.packCache.get(key: key, maxAgeSeconds: 180),
           cached.count >= requestedCount {
            return Array(cached.prefix(requestedCount))
        }

        // ✅ In-flight deduplication
        let fetchedQuestions: [TriviaQuestion] = try await Self.packCache.getOrCreateTask(key: key) {

            let callable = functions.httpsCallable("generateTriviaPack")
            let res = try await callable.call([
                "topic": cleanedTopic,
                "count": requestedCount
            ])

            guard let dict = res.data as? [String: Any] else {
                throw NSError(
                    domain: "TriviaPackClient",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Bad response"]
                )
            }

            return try Self.parseQuestions(dict["questions"])
        }

        let deduped = dedupeQuestions(fetchedQuestions)

        // ❗ Soft retry before failure
        if deduped.count < minimumAcceptableCount {

            await Self.packCache.clear(key: key)

            do {
                let retry = try await generatePack(for: cleanedTopic, count: requestedCount)
                if retry.count >= minimumAcceptableCount {
                    return retry
                }
            } catch {
                // fall through
            }

            // 📊 Telemetry: failure
            Task {
                await FirestoreService.shared.logEvent(
                    name: "pack_generation_failed",
                    uid: nil,
                    props: [
                        "topic": cleanedTopic,
                        "requestedCount": requestedCount,
                        "returnedCount": deduped.count
                    ]
                )
            }

            throw NSError(
                domain: "TriviaPackClient",
                code: 9,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Trivia pack returned only \(deduped.count) usable questions for \(cleanedTopic) after retry."
                ]
            )
        }

        let finalQuestions = Array(deduped.prefix(requestedCount))

        await Self.packCache.set(key: key, questions: finalQuestions)

        // 📊 Telemetry: success
        Task {
            await FirestoreService.shared.logEvent(
                name: "pack_generation_success",
                uid: nil,
                props: [
                    "topic": cleanedTopic,
                    "count": finalQuestions.count
                ]
            )
        }

        return finalQuestions
    }

    // MARK: - Daily Mission (SERVER SSoT)

    func generateGlobalDailyMissionPayload(dayKey: String) async throws -> DailyMissionPayload {
        let cleanedDayKey = dayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedDayKey.isEmpty else {
            throw NSError(
                domain: "TriviaPackClient",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing dayKey"]
            )
        }

        let callable = functions.httpsCallable("generateDailyMissionPack")
        let res = try await callable.call([
            "dayKey": cleanedDayKey
        ])

        guard let dict = res.data as? [String: Any] else {
            throw NSError(
                domain: "TriviaPackClient",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Bad daily mission response"]
            )
        }

        let questions = dedupeQuestions(try Self.parseQuestions(dict["questions"]))

        let topicRaw = (dict["topic"] as? String) ?? "Daily Mission"
        let topic = topicRaw.trimmingCharacters(in: .whitespacesAndNewlines)

        let returnedDayKey = (dict["dayKey"] as? String) ?? cleanedDayKey
        let generatedAt = (dict["generatedAt"] as? String) ?? ISO8601DateFormatter().string(from: Date())
        let cached = (dict["cached"] as? Bool) ?? true
        let model = dict["model"] as? String

        return DailyMissionPayload(
            questions: questions,
            topic: topic.isEmpty ? "Daily Mission" : topic,
            dayKey: returnedDayKey,
            generatedAt: generatedAt,
            cached: cached,
            model: model
        )
    }

    func generateGlobalDailyMissionPack(dayKey: String) async throws -> [TriviaQuestion] {
        try await generateGlobalDailyMissionPayload(dayKey: dayKey).questions
    }

    // MARK: - Parsing

    private static func parseQuestions(_ any: Any?) throws -> [TriviaQuestion] {
        guard let arr = any as? [[String: Any]] else {
            throw NSError(
                domain: "TriviaPackClient",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Missing questions array"]
            )
        }

        return try arr.enumerated().map { (i, q) in
            let prompt = String(q["prompt"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !prompt.isEmpty else {
                throw NSError(
                    domain: "TriviaPackClient",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Bad prompt at \(i)"]
                )
            }

            guard let choicesAny = q["choices"] as? [Any], choicesAny.count == 4 else {
                throw NSError(
                    domain: "TriviaPackClient",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "Bad choices at \(i)"]
                )
            }

            let choices = choicesAny.map {
                String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard choices.allSatisfy({ !$0.isEmpty }) else {
                throw NSError(
                    domain: "TriviaPackClient",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "Empty choice at \(i)"]
                )
            }

            let correctAny = q["correctIndex"]
            let correct: Int

            if let n = correctAny as? Int {
                correct = n
            } else if let n = correctAny as? NSNumber {
                correct = n.intValue
            } else if let s = correctAny as? String, let n = Int(s) {
                correct = n
            } else {
                throw NSError(
                    domain: "TriviaPackClient",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "Bad correctIndex at \(i)"]
                )
            }

            guard (0...3).contains(correct) else {
                throw NSError(
                    domain: "TriviaPackClient",
                    code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "correctIndex out of range at \(i)"]
                )
            }

            return TriviaQuestion(
                prompt: prompt,
                choices: choices,
                correctIndex: correct
            )
        }
    }

    // MARK: - Helpers

    private func normalizedTopic(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "General Knowledge" : cleaned
    }

    private func dedupeQuestions(_ input: [TriviaQuestion]) -> [TriviaQuestion] {
        var seen = Set<String>()
        var output: [TriviaQuestion] = []

        for question in input {
            let key = DailyPackStore.qid(question)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(question)
        }

        return output
    }
}
