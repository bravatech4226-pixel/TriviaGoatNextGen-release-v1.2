//
//  SaveStreakPaywallView.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-03-04.
//

import SwiftUI

struct SaveStreakPaywallView: View {

    @EnvironmentObject private var app: AppState

    let missedDays: Int
    let currentStreak: Int

    var body: some View {
        ZStack {
            SpaceBackground()

            VStack(spacing: 14) {
                topBar

                headerCard

                perksCard

                Button {
                    HapticManager.instance.rigidClick()

                    // ✅ Keep flow simple & stable:
                    // Pro purchase wiring can be refined later.
                    // For now, just open Settings (where Pro toggle / restore exists).
                    withAnimation(.spring()) {
                        app.setRoute(.settings)
                    }
                } label: {
                    Text("UNLOCK PRO")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(ChunkyButtonStyle(color: .orange))

                Button {
                    HapticManager.instance.impact(.medium)
                    withAnimation(.spring()) {
                        app.setRoute(.hq)   // ✅ single source of truth route
                    }
                } label: {
                    Text("NOT NOW")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(ChunkyButtonStyle(color: .white.opacity(0.18)))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - UI

private extension SaveStreakPaywallView {

    var topBar: some View {
        HStack {
            Button {
                HapticManager.instance.impact(.light)
                withAnimation(.spring()) { app.setRoute(.hq) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("SAVE STREAK")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.9))
                .tracking(1)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
    }

    var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR STREAK IS AT RISK")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .tracking(2)

            Text("\(currentStreak) day streak")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Text(missedDays > 0
                 ? "You missed \(missedDays) day(s). Pro can protect streaks with freezes."
                 : "Pro can protect streaks with freezes if you miss a day.")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
        }
        .tacticalPanel()
    }

    var perksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRO PERKS")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .tracking(2)

            perkRow("Streak freeze protection")
            perkRow("Unlimited Training Arena runs")
            perkRow("Full Pro experience (no gates)")
        }
        .tacticalPanel()
    }

    func perkRow(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green.opacity(0.9))
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
    }
}

