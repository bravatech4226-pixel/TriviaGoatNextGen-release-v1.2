//
//  HapticManager.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-02-07.
//


import UIKit

final class HapticManager {
    static let instance = HapticManager()
    private init() {}

    func successPulse() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func errorJolt() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    func rigidClick() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}
