//
//  PushTokenManager.swift
//  TriviaGoatNextGen
//  Created by Michael Houlder on 2026-02-12.
//


import Foundation
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import UIKit

final class PushTokenManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushTokenManager()

    private override init() {}

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        saveTokenToUser(token)
    }

    private func saveTokenToUser(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).setData(
            ["fcmToken": token],
            merge: true
        )
    }
}
