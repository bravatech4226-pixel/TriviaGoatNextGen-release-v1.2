//
//  PressScaleModifier.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-02-26.
//


import SwiftUI

/// Global press-scale helper (accessible from any file)
struct PressScaleModifier: ViewModifier {
    @State private var pressed: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: pressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in pressed = true }
                    .onEnded { _ in pressed = false }
            )
    }
}

extension View {
    /// Use on Buttons and tappable cards.
    func pressScale() -> some View {
        modifier(PressScaleModifier())
    }
}