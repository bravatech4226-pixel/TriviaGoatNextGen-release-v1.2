//
//  PressScaleModifier 2.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-02-26.
//


//
//  View+Interactions.swift
//  TriviaGoatNextGen
//
//  Shared interaction + stroke helpers (global, reusable)
//  ✅ Fixes: 'pressScale' inaccessible due to 'fileprivate'
//  ✅ Keeps ArenaView + TriviaGameView consistent
//

import SwiftUI



extension View {
        
    /// Simple premium stroke (TriviaGameView style)
    func premiumStroke(isOn: Bool) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(isOn ? 0.10 : 0.06), lineWidth: 1)
        )
    }

    /// Premium stroke with animated phase (ArenaView style)
    func premiumStroke(phase: Double, isOn: Bool) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(isOn ? 0.18 : 0.08),
                            Color.white.opacity(0.06)
                        ],
                        center: .center,
                        angle: .degrees(phase * 360.0)
                    ),
                    lineWidth: 1.2
                )
                .blendMode(.screen)
                .opacity(0.65)
        )
    }
}
