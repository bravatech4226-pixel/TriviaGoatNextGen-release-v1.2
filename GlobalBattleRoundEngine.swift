//
//  GlobalBattleRoundEngine.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-03-16.
//


//
//  GlobalBattleRoundEngine.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Global Battle round controller
//  - host authoritative timing
//  - answer collection
//  - scoring
//  - lightweight Firestore usage
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

@MainActor
final class GlobalBattleRoundEngine: ObservableObject {

    struct RoundState: Equatable {
        var questionIndex: Int = 0
        var timeRemaining: Int = 10
        var isLocked: Bool = false
        var correctIndex: Int? = nil
    }

    struct PlayerAnswer {
        let uid: String
        let answerIndex: Int
        let timeRemaining: Int
    }

    @Published private(set) var round = RoundState()
    @Published private(set) var answers: [String: PlayerAnswer] = [:]

    private var timer: Timer?
    private var lobbyID: String?

    func startRound(lobbyID: String) {
        self.lobbyID = lobbyID

        round = RoundState(
            questionIndex: round.questionIndex + 1,
            timeRemaining: 10,
            isLocked: false,
            correctIndex: nil
        )

        answers.removeAll()

        startTimer()
    }

    func submitAnswer(uid: String, index: Int) {

        guard answers[uid] == nil else { return }

        answers[uid] = PlayerAnswer(
            uid: uid,
            answerIndex: index,
            timeRemaining: round.timeRemaining
        )
    }

    func revealAnswer(correctIndex: Int) {

        timer?.invalidate()

        round.isLocked = true
        round.correctIndex = correctIndex
    }

    func advanceRound() {
        timer?.invalidate()
        round.questionIndex += 1
        answers.removeAll()
    }

    private func startTimer() {

        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in

            Task { @MainActor in
                self.tick()
            }
        }
    }

    private func tick() {

        guard round.timeRemaining > 0 else {
            timer?.invalidate()
            round.isLocked = true
            return
        }

        round.timeRemaining -= 1
    }

    func scorePlayers(correctIndex: Int) -> [String: Int] {

        var scores: [String: Int] = [:]

        for (uid, answer) in answers {

            guard answer.answerIndex == correctIndex else {
                scores[uid] = 0
                continue
            }

            let speedBonus = answer.timeRemaining
            let baseScore = 100

            scores[uid] = baseScore + (speedBonus * 5)
        }

        return scores
    }
}
