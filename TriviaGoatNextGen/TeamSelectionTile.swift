//
//  TeamSelectionTile.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-02-09.
//


import SwiftUI

/// Single-source Team picker tile used by Onboarding + Settings.
/// NOTE: If you already have a TeamSelectionTile declared elsewhere,
/// delete the other one to avoid "Invalid redeclaration of 'TeamSelectionTile'".
struct TeamSelectionTile: View {
    let team: TacticalTeam
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Circle()
                    .fill(team.color)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )

                Text(team.label)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(isSelected ? 1.0 : 0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 98, height: 72)
        }
        .buttonStyle(TeamTile3DStyle(color: team.color, isSelected: isSelected))
    }
}

private struct TeamTile3DStyle: ButtonStyle {
    let color: Color
    let isSelected: Bool

    private let depth: CGFloat = 4
    private let cornerRadius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .offset(y: depth)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.78))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(
                                    isSelected ? color.opacity(0.9) : Color.white.opacity(0.12),
                                    lineWidth: isSelected ? 2 : 1.2
                                )
                        )
                        .offset(y: pressed ? depth : 0)
                }
            )
            .animation(.spring(response: 0.18, dampingFraction: 0.75), value: pressed)
    }
}
