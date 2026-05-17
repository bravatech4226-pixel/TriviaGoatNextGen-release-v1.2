//
//  EventShareSheet.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-05-14.
//


import SwiftUI
import UIKit

struct EventShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}