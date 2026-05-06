//
//  MissionHostView.swift
//  TriviaGoatNextGen
//

import SwiftUI

struct MissionHostView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        content
            .navigationBarHidden(true)
            .onAppear {
                if app.route == .mission {
                    app.ensureTriviaRunLoaded()
                }
            }
            .onChange(of: app.route) { _, newRoute in
                guard newRoute != .mission else { return }

                if newRoute != .results,
                   newRoute != .battleDecision,
                   newRoute != .hq,
                   newRoute != .proPaywall {
                    app.setRoute(.hq)
                }
            }
    }

    // MARK: - Body content (split to keep type-checking fast)

    @ViewBuilder
    private var content: some View {
        if isTrainingRun {
            TrainingMissionView()
                .id(contentIdentityKey)
        } else {
            TriviaGameView()
                .id(contentIdentityKey)
        }
    }
    
    private var contentIdentityKey: String {
        isTrainingRun ? "training-mission-host" : "daily-mission-host"
    }

    // MARK: - Topic classification

    private var isTrainingRun: Bool {
        let raw = (app.trivia.topic ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.uppercased().hasPrefix("TRAINING")
    }
}
