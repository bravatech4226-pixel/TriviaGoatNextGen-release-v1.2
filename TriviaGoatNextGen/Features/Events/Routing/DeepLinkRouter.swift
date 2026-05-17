//
//  DeepLinkRouter.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-14.
//

import Foundation

@MainActor
enum DeepLinkRouter {

    static func handle(
        url: URL,
        app: AppState
    ) {
        guard let eventID = eventID(from: url) else {
            return
        }

        routeToEvent(
            eventID: eventID,
            app: app
        )
    }

    private static func eventID(from url: URL) -> String? {
        let components = url.pathComponents

        guard components.count >= 3 else {
            return nil
        }

        guard components[1].lowercased() == "events" else {
            return nil
        }

        return components[2]
    }

    private static func routeToEvent(
        eventID: String,
        app: AppState
    ) {
        if let event = app.events.first(where: { $0.id == eventID }) {
            app.selectedEvent = event
            app.setRoute(.eventDetail)
            return
        }

        app.showEventToast("EVENT LOADING")
        app.setRoute(.events)

        Task {
            await retryEventRoute(
                eventID: eventID,
                app: app
            )
        }
    }

    private static func retryEventRoute(
        eventID: String,
        app: AppState
    ) async {
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 500_000_000)

            if let event = app.events.first(where: { $0.id == eventID }) {
                app.selectedEvent = event
                app.setRoute(.eventDetail)
                return
            }
        }

        app.showEventToast("EVENT UNAVAILABLE")
    }
}
