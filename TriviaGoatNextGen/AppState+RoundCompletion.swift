//
//  AppState+RoundCompletion.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Safe “advance or finish” helper without touching your existing advanceTrivia().
//

import Foundation

extension AppState {

    /// If last question → route to results. Otherwise → advance normally.
    @MainActor
    func advanceTriviaOrFinish() {
        let total = trivia.pack.count
        let idx = trivia.currentIndex

        guard total > 0 else {
            advanceTrivia()
            return
        }

        if idx >= (total - 1) {
            setRoute(.results)
        } else {
            advanceTrivia()
        }
    }
}

