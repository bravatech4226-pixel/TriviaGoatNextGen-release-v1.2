//
//  PushNotificationManager.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-02-12.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
@preconcurrency import UserNotifications
import UIKit

// MARK: - App push route event
extension Notification.Name {
    static let tgPushRoute = Notification.Name("tg.push.route")
}

final class PushNotificationManager: NSObject {

    static let shared = PushNotificationManager()
    private override init() {}

    private enum DebugLog {
        static let verbose = false
        static let tokenEvents = true
    }

    private var hasRequestedPermission = false
    private var hasStartedRemoteRegistration = false
    private var hasAPNSToken = false
    private var lastSyncedFCMToken: String?
    private var pendingFCMToken: String?

    // MARK: - Public

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        #if targetEnvironment(simulator)
        if DebugLog.tokenEvents {
            print("📭 [Push] Simulator detected — skipping push registration.")
        }
        #else
        requestPermissionIfNeeded()
        #endif
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        hasAPNSToken = true
        Messaging.messaging().apnsToken = deviceToken

        if DebugLog.tokenEvents {
            print("✅ [Push] APNS token registered.")
        }

        flushPendingFCMTokenIfPossible()
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        if DebugLog.tokenEvents {
            print("⚠️ [Push] Failed to register for remote notifications: \(error.localizedDescription)")
        }
    }

    func didReceiveFCMToken(_ token: String?) {
        #if targetEnvironment(simulator)
        return
        #else
        guard let token else { return }

        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        guard hasAPNSToken else {
            pendingFCMToken = cleaned

            if DebugLog.verbose {
                print("🟨 [Push] Holding FCM token until APNS token is available.")
            }
            return
        }

        syncFCMTokenIfNeeded(cleaned)
        #endif
    }
    // MARK: - Private

    private func requestPermissionIfNeeded() {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true

        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error, DebugLog.tokenEvents {
                print("⚠️ [Push] Notification permission request failed: \(error.localizedDescription)")
            }

            guard granted else {
                if DebugLog.tokenEvents {
                    print("🟨 [Push] Notification permission not granted.")
                }
                return
            }

            DispatchQueue.main.async {
                self.registerForRemoteNotificationsIfNeeded()
            }
        }
    }

    private func registerForRemoteNotificationsIfNeeded() {
        guard !hasStartedRemoteRegistration else { return }
        hasStartedRemoteRegistration = true

        UIApplication.shared.registerForRemoteNotifications()

        if DebugLog.tokenEvents {
            print("📡 [Push] Requested remote notification registration.")
        }
    }


    private func flushPendingFCMTokenIfPossible() {
        guard hasAPNSToken, let pendingFCMToken else { return }
        self.pendingFCMToken = nil
        syncFCMTokenIfNeeded(pendingFCMToken)
    }

    private func syncFCMTokenIfNeeded(_ token: String) {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        guard cleaned != lastSyncedFCMToken else { return }

        guard let uid = Auth.auth().currentUser?.uid else {
            pendingFCMToken = cleaned

            if DebugLog.verbose {
                print("🟨 [Push] Holding FCM token until authenticated user is available.")
            }
            return
        }

        lastSyncedFCMToken = cleaned
        pendingFCMToken = nil

        Firestore.firestore()
            .collection("users")
            .document(uid)
            .setData(
                [
                    "fcmToken": cleaned,
                    "updatedAt": FieldValue.serverTimestamp(),
                ],
                merge: true
            )

        if DebugLog.tokenEvents {
            print("✅ [Push] FCM token synced for uid: \(uid)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let type = (userInfo["type"] as? String) ?? ""

        NotificationCenter.default.post(
            name: .tgPushRoute,
            object: nil,
            userInfo: ["type": type, "payload": userInfo]
        )

        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension PushNotificationManager: MessagingDelegate {

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        didReceiveFCMToken(fcmToken)
    }
}
