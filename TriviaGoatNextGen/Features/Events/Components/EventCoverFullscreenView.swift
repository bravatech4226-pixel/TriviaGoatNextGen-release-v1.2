//
//  EventCoverFullscreenView.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-14.
//


import SwiftUI

struct EventCoverFullscreenView: View {
    let event: AppState.TGEvent
    let namespace: Namespace.ID
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let urlString = event.coverImageURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.orange)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .matchedGeometryEffect(id: "event-cover-\(event.id)", in: namespace)
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
                .padding(.horizontal, 10)
            } else {
                fallback
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    )
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .orange.opacity(0.45),
                    .black,
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.orange)

                Text(event.title.uppercased())
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .ignoresSafeArea()
    }
}