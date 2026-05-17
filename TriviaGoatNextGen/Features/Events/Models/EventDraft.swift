//
//  EventDraft.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-16.
//
//  PURPOSE:
//  Canonical event creation/editing draft model.
//  Single source of truth for EventEditorView + AppState.
//

import Foundation
import FirebaseFirestore

struct EventDraft: Equatable {

    var title: String = ""
    var heroLine: String = ""
    var summary: String = ""

    var category: String = "launch"
    var visibility: String = "public"
    var locationType: String = "hybrid"

    var startsAt: Date? = nil
    var endsAt: Date? = nil

    var venueName: String = ""

    var capacity: Int = 100
    var waitlistEnabled: Bool = true

    var featured: Bool = false
    var published: Bool = true
}

extension EventDraft {

    func firestorePayload(
        organizerUID: String,
        organizerName: String
    ) -> [String: Any] {

        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedHeroLine = heroLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedVenueName = venueName.trimmingCharacters(in: .whitespacesAndNewlines)

        var payload: [String: Any] = [
            "title": cleanedTitle,
            "heroLine": cleanedHeroLine,
            "summary": cleanedSummary,

            "category": category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "visibility": visibility.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "locationType": locationType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),

            "venueName": cleanedVenueName,

            "capacity": max(0, capacity),
            "attendeeCount": 0,
            "waitlistEnabled": waitlistEnabled,

            "featured": featured,
            "featuredPriority": featured ? 100 : 0,
            "published": published,

            "approvalStatus": published ? "approved" : "draft",
            "status": published ? "scheduled" : "draft",

            "organizerUID": organizerUID,
            "organizerName": organizerName,
            "submittedByUID": organizerUID,

            "rsvpCount": 0,
            "waitlistCount": 0,

            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let startsAt {
            payload["startsAt"] = Timestamp(date: startsAt)
            payload["startAt"] = Timestamp(date: startsAt)
            payload["eventDate"] = Timestamp(date: startsAt)
        } else {
            payload["startsAt"] = NSNull()
            payload["startAt"] = NSNull()
            payload["eventDate"] = NSNull()
        }

        if let endsAt {
            payload["endsAt"] = Timestamp(date: endsAt)
            payload["endAt"] = Timestamp(date: endsAt)
        } else {
            payload["endsAt"] = NSNull()
            payload["endAt"] = NSNull()
        }

        return payload
    }
}
