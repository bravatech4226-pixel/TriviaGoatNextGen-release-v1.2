//
//  SecureWithAppleCard.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-04-27.
//


import SwiftUI

struct SecureWithAppleCard: View {

    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("Secure Your Rank")
                .font(.headline)

            Text("Sign in with Apple to protect your progress and leaderboard position.")
                .font(.subheadline)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    isLoading = true
                    do {
                        _ = try await AuthManager.shared.secureCurrentProfileWithApple()
                    } catch {
                        self.error = error.localizedDescription
                    }
                    isLoading = false
                }
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Sign in with Apple")
                        .bold()
                }
            }
            .buttonStyle(.borderedProminent)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}