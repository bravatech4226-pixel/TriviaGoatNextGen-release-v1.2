//
//  AppState+TriviaAnswering.swift
//  TriviaGoatNextGen
//
//  Single source of truth for answering + scoring
//

import Foundation

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

@MainActor
extension AppState {

    /// Central answer submission (single source of truth)
    /// Handles:
    /// - scoring
    /// - streak updates
    /// - daily mission progress
    /// - optional backend telemetry
    func submitAnswer(index: Int) {
        guard let q = currentQuestion else { return }
        guard (0..<q.choices.count).contains(index) else { return }

        let isCorrect = (index == q.correctIndex)

        // MARK: - Local scoring (authoritative)

        if isCorrect {
            trivia.score += 1
            streakCount += 1
        } else {
            streakCount = 0
        }

        // MARK: - Daily Mission progress

        let rawTopic = (trivia.topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = rawTopic.uppercased()

        let isTrainingRun = upper.hasPrefix("TRAINING")
        let isDailyMissionRun = upper.hasPrefix("DAILY MISSION")

        if isDailyMissionRun && !isTrainingRun {

            Task { @MainActor [weak self] in
                guard let self else { return }

                let uid = await AuthManager.shared.currentUID()
                let team = self.profile.team

                // Ensure today's structure exists
                DailyMission.applyDailyResetIfNeeded(uid: uid, team: team)

                // Record the answer
                DailyMission.recordAnswer(
                    correct: isCorrect,
                    uid: uid,
                    team: team
                )
            }
        }

        // MARK: - Backend hook (fire-and-forget)

        #if canImport(FirebaseFunctions)
        Task {
            do {
                _ = try await AuthManager.shared.ensureAuthenticated()

                let functions = Functions.functions(region: "us-central1")

                _ = try await functions
                    .httpsCallable("submitAnswer")
                    .call([
                        "isCorrect": isCorrect
                    ])

            } catch {
                // Backend failures must NEVER interrupt gameplay
            }
        }
        #endif
    }
}
