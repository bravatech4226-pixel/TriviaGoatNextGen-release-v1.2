// PushDebugView.swift
//  Created by Michael Houlder on 2026-03-04.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

struct PushDebugView: View {
    @State private var status: String = "—"
    @State private var token: String = "—"
    @State private var isSending: Bool = false
    @State private var isRefreshing: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 14) {

                header

                VStack(alignment: .leading, spacing: 10) {
                    Text("UID: \(Auth.auth().currentUser?.uid ?? "nil")")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("Token (from Firestore):")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.95))

                    Text(token)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(8)
                        .textSelection(.enabled)

                    Text("Status: \(status)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .padding(.horizontal, 16)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await refreshToken() }
                } label: {
                    ZStack {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Text("REFRESH TOKEN")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.tertiaryLabel))
                .padding(.horizontal, 16)
                .disabled(isRefreshing)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await sendTestPush() }
                } label: {
                    ZStack {
                        if isSending {
                            ProgressView().tint(.black)
                        } else {
                            Text("SEND TEST PUSH")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.horizontal, 16)
                .disabled(isSending)

                Spacer(minLength: 20)
            }
            .padding(.top, 12)
            .navigationBarHidden(true)
        }
        .onAppear {
            Task { await refreshToken() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("PUSH DEBUG")
                    .font(.system(size: 18, weight: .black, design: .rounded))

                Text("Token + test send")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Firestore token read

    private func refreshToken() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            status = "No user signed in."
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snap = try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .getDocument()

            let data = snap.data() ?? [:]
            let t = data["fcmToken"] as? String ?? ""
            token = t.isEmpty ? "— (missing: users/\(uid).fcmToken)" : t
            status = t.isEmpty ? "Token missing in Firestore." : "Token loaded."
        } catch {
            status = "Failed to load token: \(error.localizedDescription)"
        }
    }

    // MARK: - Callable test push

    private func sendTestPush() async {
        isSending = true
        defer { isSending = false }

        status = "Sending…"
        do {
            let functions = Functions.functions()
            _ = try await functions.httpsCallable("sendTestPush").call([:])
            status = "Sent ✅ (check device notifications)"
        } catch {
            status = "Send failed: \(error.localizedDescription)"
        }
    }
}

