//
//  DashboardView.swift
//  TriviaGoatNextGen
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var app: AppState
    @State private var battleTopic: String = ""

    var body: some View {
        let appRef: AppState = app

        let profile = appRef.profile
        let levelProgress = appRef.levelProgress
        let currentLevel = appRef.currentLevel
        let canAccessGlobalBattle = appRef.canAccessGlobalBattle
        let isGlobalBattleEnabled = appRef.isGlobalBattleEnabled

        let teamFill = AnyShapeStyle(profile.team.color.gradient)

        ZStack {
            SpaceBackground(showsGrid: true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    HeaderSection(
                        teamFill: teamFill,
                        levelProgress: levelProgress,
                        currentLevel: currentLevel,
                        onLeaderboard: {
                            withAnimation { appRef.setRoute(.leaderboard) }
                        }
                    )

                    GlobalBattleSection(
                        isEnabled: isGlobalBattleEnabled,
                        canEnter: canAccessGlobalBattle,
                        onEnter: {
                            withAnimation {
                                _ = appRef.openGlobalBattleIfEnabled()
                            }
                        }
                    )

                    TacticalFeedSection(
                        items: [
                            .init(icon: "globe.americas.fill", iconTint: .orange, text: "Global Battle is now the primary multiplayer arena."),
                            .init(icon: "bolt.fill", iconTint: .cyan, text: "AI Forge updated")
                        ]
                    )

                    ForgeSection(
                        battleTopic: $battleTopic,
                        onForge: { cleanedTopic in
                            appRef.startAIGame(topic: cleanedTopic)
                        }
                    )

                    StatsQuickLook(
                        globalRankText: "#\(profile.globalRank ?? 999)",
                        teamXPText: "\(profile.xp)"
                    )
                }
                .padding()
                .padding(.bottom, 12)
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Header

private struct HeaderSection: View {
    let teamFill: AnyShapeStyle
    let levelProgress: Double
    let currentLevel: Int
    let onLeaderboard: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Circle()
                .fill(teamFill)
                .frame(width: 50, height: 50)
                .overlay(Text("🐐"))

            VStack(alignment: .leading) {
                XPVolumetricBar(progress: levelProgress)
                Text("LVL \(currentLevel)")
                    .font(.caption.monospaced().bold())
                    .foregroundColor(.orange)
            }

            Spacer()

            Button(action: onLeaderboard) {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Global Battle

private struct GlobalBattleSection: View {
    let isEnabled: Bool
    let canEnter: Bool
    let onEnter: () -> Void

    private var statusText: String {
        if !isEnabled { return "GLOBAL MULTIPLAYER IS CURRENTLY OFFLINE" }
        if canEnter { return "ENTER THE LIVE GLOBAL ARENA" }
        return "GLOBAL ACCESS IS CURRENTLY UNAVAILABLE"
    }

    private var buttonTitle: String {
        canEnter ? "ENTER GLOBAL BATTLE" : "GLOBAL BATTLE UNAVAILABLE"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "globe.americas.fill")
                    .foregroundColor(.orange)

                Text("GLOBAL BATTLE")
                    .font(.caption.monospaced().bold())
                    .foregroundColor(.orange)

                Spacer()

                Circle()
                    .fill(isEnabled ? Color.green : Color.red.opacity(0.8))
                    .frame(width: 8, height: 8)
            }

            Text(statusText)
                .font(.footnote.monospaced())
                .foregroundColor(.white.opacity(0.9))

            Text("Fast live multiplayer is now centered on the global arena. Solo and Training remain your core progression lanes.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: onEnter) {
                HStack {
                    Image(systemName: "bolt.horizontal.circle.fill")
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(ChunkyButtonStyle(color: .orange))
            .disabled(!canEnter)
            .opacity(canEnter ? 1.0 : 0.65)
        }
        .tacticalPanel()
    }
}

// MARK: - Tactical Feed

private struct TacticalFeedItem: Identifiable {
    let id = UUID()
    let icon: String
    let iconTint: Color
    let text: String
}

private struct TacticalFeedSection: View {
    let items: [TacticalFeedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TACTICAL FEED")
                .font(.caption.monospaced().bold())
                .foregroundColor(.secondary)

            ForEach(items) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .foregroundColor(item.iconTint)

                    Text(item.text)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.92))

                    Spacer(minLength: 0)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(15)
    }
}

// MARK: - Forge

private struct ForgeSection: View {
    @Binding var battleTopic: String
    let onForge: (String) -> Void

    var body: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: "bolt.shield.fill")
                Text("BATTLE FORGE").bold()
                Spacer()
            }
            .foregroundColor(.orange)

            TextField("Enter Battle Topic...", text: $battleTopic)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                )

            Button {
                let cleaned = battleTopic.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return }
                onForge(cleaned)
            } label: {
                Text("FORGE BATTLE")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChunkyButtonStyle(color: .orange))
            .disabled(battleTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .tacticalPanel()
    }
}

// MARK: - Stats

private struct StatsQuickLook: View {
    let globalRankText: String
    let teamXPText: String

    var body: some View {
        HStack {
            VStack {
                Text("GLOBAL RANK").font(.system(size: 8))
                Text(globalRankText).bold()
            }

            Spacer()

            VStack {
                Text("TEAM XP").font(.system(size: 8))
                Text(teamXPText).bold()
            }
        }
        .foregroundColor(.secondary)
        .padding()
    }
}
