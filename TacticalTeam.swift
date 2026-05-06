//
//  TacticalTeam.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-02-07.
//


import SwiftUI

/// Core squad/team model for TriviaGOAT Tactical OS.
/// Used by:
/// - UserProfile
/// - UI color styling
enum TacticalTeam: String, CaseIterable, Codable, Hashable {

    case striker
    case titan
    case phantom

    /// High-contrast tactical colors used throughout the UI
    var color: Color {
        switch self {
        case .striker: return .orange
        case .titan:   return .blue
        case .phantom: return .green
        }
    }

    /// Optional display label (future UI polish)
    var label: String {
        rawValue.uppercased()
    }
}
