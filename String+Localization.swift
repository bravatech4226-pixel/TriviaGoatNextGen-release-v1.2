//
//  String+Localization.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-05.
//


//
//  String+Localization.swift
//  TriviaGoatNextGen
//
//  PURPOSE:
//  Centralized string localization helper.
//  - Provides clean `.localized` access for all string keys
//  - Supports formatted localization (e.g. %d, %@)
//  - Keeps UI code clean and consistent across the app
//
//  USAGE:
//  "onboarding.header.title".localized
//  "paywall.savings".localized(25)
//
//  NOTES:
//  - Requires Localizable.strings files in en.lproj / fr.lproj / es.lproj
//  - Falls back to key if translation is missing
//

import Foundation

extension String {

    /// Basic localization lookup
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// Localization with formatting support (e.g. %d, %@)
    func localized(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
}