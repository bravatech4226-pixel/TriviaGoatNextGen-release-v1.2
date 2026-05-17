//
//  ContentView.swift
//  TriviaGoatNextGen
//
//  CLEAN SSoT ROUTER
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            SpaceBackground()

            routedContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)

            if app.isBusy && shouldShowGlobalBusyOverlay {
                busyOverlay
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: app.route)
    }

    private var shouldShowGlobalBusyOverlay: Bool {
        switch app.route {
        case .onboarding:
            return false
        default:
            return true
        }
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            ProgressView()
                .tint(.orange)
                .padding(20)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func routedContent() -> some View {
        switch app.route {

        case .landing:
            ProgressView()
                .tint(.orange)
                .onAppear {
                    app.bootIfNeeded()
                }

        case .onboarding:
            OnboardingView()

        case .welcome:
            if let welcome = app.welcomeState {
                WelcomeToTriviaGoatView(
                    playerName: welcome.playerName,
                    onStartDailyMission: {
                        app.startDailyMissionFromWelcome()
                    },
                    onEnterTrainingArena: {
                        app.startTrainingFromWelcome(topic: "General Knowledge")
                    },
                    onGoToHQ: {
                        app.goToHQFromWelcome()
                    }
                )
            } else {
                Color.clear
                    .onAppear {
                        app.setRoute(.hq)
                    }
            }

        case .hq:
            ArenaView()

        case .community:
            CommunityView()

        case .events:
            EventsView()
                .environmentObject(app)

        case .eventDetail:
            if let event = app.selectedEvent {
                EventDetailView(event: event)
                    .environmentObject(app)
            } else {
                EventsView()
                    .environmentObject(app)
            }

        case .creatorConsole:
            CreatorConsoleView()
                .environmentObject(app)

        case .manageEvent:
            if let event = app.selectedEvent {
                EventManagementView(event: event)
                    .environmentObject(app)
            } else {
                CreatorConsoleView()
                    .environmentObject(app)
            }

        case .eventEditor:
            EventEditorView()
                .environmentObject(app)

        case .globalBattle:
            GlobalMatchView()
                .environmentObject(app)

        case .globalBattleMatch:
            if let session = app.globalBattleSession {
                GlobalBattleMatchView(session: session)
                    .environmentObject(app)
            } else {
                Color.clear
                    .onAppear {
                        app.setRoute(.hq)
                    }
            }

        case .mission:
            MissionHostView()

        case .results:
            ResultsView()

        case .battleDecision:
            if let decision = app.battleDecision {
                BattleDecisionView(
                    context: .solo,
                    outcome: decision.outcome,
                    opponentName: resolvedOpponentName(decision.opponentName),
                    scoreLine: resolvedScoreLine(decision.scoreLine),
                    onRematch: {
                        app.setRoute(.hq)
                    },
                    onDailyMission: {
                        app.startDailyMissionRun()
                    },
                    onTraining: {
                        app.beginTrainingArenaRun(topic: "General Knowledge")
                    },
                    onBackToHQ: {
                        app.setRoute(.hq)
                    }
                )
            } else {
                Color.clear
                    .onAppear {
                        app.setRoute(.hq)
                    }
            }

        case .leaderboard:
            LeaderboardHostView()

        case .settings:
            SettingsView()

        case .proPaywall, .paywall:
            PaywallView()

        case .streakPaywall:
            SaveStreakPaywallView(
                missedDays: StreakManager.shared.missedDaysCount(),
                currentStreak: StreakManager.shared.streakCount
            )
        }
    }

    private func resolvedOpponentName(_ name: String?) -> String {
        let cleaned = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "RIVAL PILOT" : cleaned
    }

    private func resolvedScoreLine(_ scoreLine: String?) -> String {
        let cleaned = (scoreLine ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "MATCH COMPLETE" : cleaned
    }
}
