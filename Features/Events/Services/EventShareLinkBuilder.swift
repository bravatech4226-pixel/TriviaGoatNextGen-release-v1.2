//
//  EventShareLinkBuilder.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-14.
//

import Foundation

enum EventShareLinkBuilder {

    private static let appStoreURL = "https://apps.apple.com/ca/app/id6757435282"

    static func url(for event: AppState.TGEvent) -> URL {
        URL(string: appStoreURL)!
    }

    static func message(for event: AppState.TGEvent) -> String {
        """
        \(event.title)

        \(event.heroLine.isEmpty ? "Join this Trivia GOAT event on Trivia GOAT." : event.heroLine)

        Download Trivia GOAT:
        \(appStoreURL)
        """
    }
}
