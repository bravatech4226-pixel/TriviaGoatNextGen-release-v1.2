//
//  EventDraft.swift
//  TriviaGoatNextGen
//

import Foundation
import FirebaseFirestore

struct EventDraft: Equatable {

    var title: String = ""
    var heroLine: String = ""
    var summary: String = ""

    var category: String = "launch"
    var visibility: String = "private"
    var locationType: String = "hybrid"

    var startsAt: Date? = nil
    var endsAt: Date? = nil

    var rsvpOpensAt: Date? = nil
    var rsvpClosesAt: Date? = nil
    var waitlistOpensAt: Date? = nil
    var waitlistClosesAt: Date? = nil

    var venueName: String = ""

    var capacity: Int = 100
    var waitlistEnabled: Bool = true

    var featured: Bool = false
    var published: Bool = false
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

        let resolvedRSVPOpensAt = rsvpOpensAt ?? startsAt
        let resolvedRSVPClosesAt = rsvpClosesAt ?? endsAt ?? startsAt
        let resolvedWaitlistOpensAt = waitlistOpensAt ?? resolvedRSVPOpensAt
        let resolvedWaitlistClosesAt = waitlistClosesAt ?? resolvedRSVPClosesAt

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
            "published": false,

            "approvalStatus": "draft",
            "status": "draft",

            "organizerUID": organizerUID,
            "organizerName": organizerName,
            "submittedByUID": organizerUID,

            "rsvpCount": 0,
            "waitlistCount": 0,

            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let startsAt {
            let timestamp = Timestamp(date: startsAt)
            payload["startsAt"] = timestamp
            payload["startAt"] = timestamp
            payload["eventDate"] = timestamp
        } else {
            payload["startsAt"] = NSNull()
            payload["startAt"] = NSNull()
            payload["eventDate"] = NSNull()
        }

        if let endsAt {
            let timestamp = Timestamp(date: endsAt)
            payload["endsAt"] = timestamp
            payload["endAt"] = timestamp
        } else {
            payload["endsAt"] = NSNull()
            payload["endAt"] = NSNull()
        }

        if let resolvedRSVPOpensAt {
            payload["rsvpOpensAt"] = Timestamp(date: resolvedRSVPOpensAt)
        } else {
            payload["rsvpOpensAt"] = NSNull()
        }

        if let resolvedRSVPClosesAt {
            payload["rsvpClosesAt"] = Timestamp(date: resolvedRSVPClosesAt)
        } else {
            payload["rsvpClosesAt"] = NSNull()
        }

        if let resolvedWaitlistOpensAt {
            payload["waitlistOpensAt"] = Timestamp(date: resolvedWaitlistOpensAt)
        } else {
            payload["waitlistOpensAt"] = NSNull()
        }

        if let resolvedWaitlistClosesAt {
            payload["waitlistClosesAt"] = Timestamp(date: resolvedWaitlistClosesAt)
        } else {
            payload["waitlistClosesAt"] = NSNull()
        }

        return payload
    }
}
