//
//  CommunityPulseClient.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-04-01.
//


//
//  CommunityPulseClient.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Handles Cloud Functions for Community system
//

import Foundation
import FirebaseFunctions

struct CommunityPulseClient {

    private let functions = Functions.functions(region: "us-central1")

    // MARK: - Seed Launch Content

    func seedLaunchContent() async throws {
        _ = try await functions
            .httpsCallable("seedCommunityLaunchContent")
            .call([:])
    }
}