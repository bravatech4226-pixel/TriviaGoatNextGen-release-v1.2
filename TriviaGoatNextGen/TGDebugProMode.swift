//
//  TGDebugProOverride.swift
//  TriviaGoatNextGen
//
//  Debug-only entitlement override for testing.
//  NOTE: This is the ONLY place TGDebugProMode should be defined.
//

import Foundation

#if DEBUG

/// Debug-only entitlement mode used to bypass gates during testing.
enum TGDebugProMode: Int, CaseIterable, Identifiable {
    case standard = 0
    case pro = 1

    var id: Int { rawValue }
}

enum TGDebugProOverride {

    static let didChangeNotification = Notification.Name("tg.debug.proOverride.changed")
    private static let key = "tg.debug.proOverride.mode"

    static var mode: TGDebugProMode {
        get {
            let raw = UserDefaults.standard.integer(forKey: key)
            return TGDebugProMode(rawValue: raw) ?? .standard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static var isPro: Bool {
        mode == .pro
    }
}

#endif

