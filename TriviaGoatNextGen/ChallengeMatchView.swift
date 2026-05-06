//
//  ChallengeMatchView.swift
//  TriviaGoatNextGen
//

import SwiftUI

struct ChallengeMatchView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        emptyState
            .navigationBarHidden(true)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ZStack {
            SpaceBackground()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.02),
                    Color.clear,
                    Color.orange.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                Text("NO ACTIVE MATCH")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.92))
                    .tracking(1.6)

                Text("The nearby session is no longer active.")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.94))
                    .multilineTextAlignment(.center)

                Button {
                    HapticManager.instance.impact(.light)
                    SpatialAudioManager.shared.play(.uiTap)
                    app.setRoute(.hq)
                } label: {
                    Text("BACK TO HQ")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(ChunkyButtonStyle(color: .orange))
            }
            .padding(18)
            .frame(maxWidth: 420)
            .tacticalPanel()
            .premiumStroke(isOn: true)
            .padding(.horizontal, 16)
        }
    }
}
