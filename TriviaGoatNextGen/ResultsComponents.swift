//
//  XPParticle.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-02-07.
//


import SwiftUI

// MARK: - XPParticle

struct XPParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var scale: CGFloat
    var opacity: Double
    var rotation: Angle
}

// MARK: - ResultStatBox

struct ResultStatBox: View {
    let title: String
    let value: String
    var accent: Color = Color.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(accent.opacity(0.85))

            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                )
        )
    }
}
