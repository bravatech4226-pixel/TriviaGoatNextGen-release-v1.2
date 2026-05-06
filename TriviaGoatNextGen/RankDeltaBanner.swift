//
//  RankDeltaBanner.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-02-12.
//


import SwiftUI

struct RankDeltaBanner: View {
    let delta: LeaderboardLiveService.RankDelta

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundColor(color)

            Text(text)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.70))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var icon: String {
        switch delta.direction {
        case .up: return "arrow.up.circle.fill"
        case .down: return "arrow.down.circle.fill"
        case .same: return "minus.circle.fill"
        }
    }

    private var color: Color {
        switch delta.direction {
        case .up: return .green
        case .down: return .red
        case .same: return .white.opacity(0.6)
        }
    }

    private var text: String {
        switch delta.direction {
        case .up: return "RANK UP  #\(delta.oldRank) → #\(delta.newRank)"
        case .down: return "RANK DOWN  #\(delta.oldRank) → #\(delta.newRank)"
        case .same: return "RANK  #\(delta.newRank)"
        }
    }
}
