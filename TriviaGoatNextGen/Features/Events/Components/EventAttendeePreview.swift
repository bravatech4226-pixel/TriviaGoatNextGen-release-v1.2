//
//  EventAttendeePreview.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-17.
//


//
//  EventAttendeePreview.swift
//  TriviaGoatNextGen
//

import SwiftUI

struct EventAttendeePreview: View {

    let attendeeCount: Int
    let capacity: Int
    let accent: Color

    private var progress: Double {
        guard capacity > 0 else { return 0 }
        return min(1.0, Double(attendeeCount) / Double(capacity))
    }

    private var remainingSeats: Int {
        max(0, capacity - attendeeCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack {
                Text("ATTENDEES")
                    .font(
                        DS.Typography.font(
                            10,
                            weight: .black,
                            design: .monospaced,
                            cappedAt: 12
                        )
                    )
                    .foregroundColor(.white.opacity(0.52))
                    .tracking(1.6)

                Spacer()

                Text("\(attendeeCount)/\(capacity)")
                    .font(
                        DS.Typography.font(
                            12,
                            weight: .black,
                            design: .rounded,
                            cappedAt: 15
                        )
                    )
                    .foregroundColor(.white.opacity(0.92))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {

                    Capsule()
                        .fill(Color.white.opacity(0.06))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.92),
                                    accent.opacity(0.62)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 10)

            HStack(spacing: 10) {

                statPill(
                    icon: "person.2.fill",
                    text: "\(attendeeCount) RSVP"
                )

                statPill(
                    icon: "person.2.fill",
                    text: "\(remainingSeats) LEFT"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 8) {

            Image(systemName: icon)
                .font(
                    DS.Typography.font(
                        10,
                        weight: .black,
                        design: .default,
                        cappedAt: 12
                    )
                )
                .foregroundColor(accent)

            Text(text)
                .font(
                    DS.Typography.font(
                        10,
                        weight: .black,
                        design: .monospaced,
                        cappedAt: 12
                    )
                )
                .foregroundColor(.white.opacity(0.84))
                .tracking(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
