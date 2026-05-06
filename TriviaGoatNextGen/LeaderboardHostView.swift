//
//  LeaderboardHostView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-02-10.
//


//
//  LeaderboardHostView.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  A single, conflict-free entry point for the leaderboard route.
//  If you already have a LeaderboardView somewhere else, we won't fight it.
//

import SwiftUI

struct LeaderboardHostView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        LeaderboardView()
            .onAppear { app.refreshLeaderboard() }
    }
}
