//
//  HowItWorksSheet.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-02-13.
//

import SwiftUI

struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            SpaceBackground()

            VStack(spacing: 18) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    bullet("how.bullet.mission".localized)
                    bullet("how.bullet.streak".localized)
                    bullet("how.bullet.leaderboard".localized)
                    bullet("how.bullet.challenge".localized)
                }
                .tacticalPanel()
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("how.notifications.title".localized)
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.95))
                        .tracking(1)

                    Text("how.notifications.body".localized)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))

                    VStack(alignment: .leading, spacing: 8) {
                        bulletSmall("how.notifications.leaderboard".localized)
                        bulletSmall("how.notifications.streak".localized)
                        bulletSmall("how.notifications.challenge".localized)
                    }
                }
                .tacticalPanel()
                .padding(.horizontal, 16)

                Button {
                    HapticManager.instance.rigidClick()
                    dismiss()
                } label: {
                    Text("common.got_it".localized)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(ChunkyButtonStyle(color: .orange))
                .padding(.bottom, 18)
            }
            .padding(.top, 18)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("how.title".localized)
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(.orange.opacity(0.95))
                .tracking(4)

            Text("how.brand".localized)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Text("how.subtitle".localized)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
        }
        .padding(.horizontal, 16)
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chevron.right.circle.fill")
                .foregroundColor(.orange.opacity(0.9))
                .font(.system(size: 14, weight: .black))

            Text(s)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func bulletSmall(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.fill")
                .foregroundColor(.orange.opacity(0.9))
                .font(.system(size: 12, weight: .black))

            Text(s)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
} 
