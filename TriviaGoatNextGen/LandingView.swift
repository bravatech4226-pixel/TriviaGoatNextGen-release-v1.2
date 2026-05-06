//
//  LeaderboardView.swift
//  TriviaGoatNextGen
//

import SwiftUI

struct LeaderboardViewLegacy: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if app.topPlayers.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(app.topPlayers.enumerated()), id: \.offset) { idx, p in
                            row(rank: idx + 1, player: p)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            app.refreshLeaderboard()
        }
    }

    private var header: some View {
        HStack {
            Text("LEADERBOARD")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.orange)
                .tracking(2)

            Spacer()

            Button {
                HapticManager.instance.impact(.light)
                withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                    app.setRoute(.hq) // ✅ “then B”
                }
            } label: {
                Text("BACK TO HQ")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.orange)
            Text("SYNCING GLOBAL RANKS…")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.85))
        }
        .tacticalPanel()
    }

    private func row(rank: Int, player: UserProfile) -> some View {
        let isMe = player.displayName == app.profile.displayName

        return HStack(spacing: 12) {
            Text("#\(rank)")
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 46, alignment: .leading)

            Circle()
                .fill(player.team.color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(player.displayName.uppercased())
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(player.team.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            Text("\(player.xp) XP")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.9))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isMe ? Color.white.opacity(0.10) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isMe ? Color.orange.opacity(0.55) : Color.white.opacity(0.10), lineWidth: isMe ? 2 : 1)
        )
    }
}
