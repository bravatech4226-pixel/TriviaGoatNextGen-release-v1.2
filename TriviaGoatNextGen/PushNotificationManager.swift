//
//  PushNotificationManager.swift
//  TriviaGoatNextGen
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
@preconcurrency import UserNotifications
import UIKit

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
            return
        }

        syncFCMTokenIfNeeded(cleaned)
        #endif
    }

    func syncTokenForCurrentUserIfPossible() {
        #if targetEnvironment(simulator)
        return
        #else
        if let pendingFCMToken {
            syncFCMTokenIfNeeded(pendingFCMToken)
            return
        }

        Messaging.messaging().token { [weak self] token, error in
            if let error, DebugLog.tokenEvents {
                print("⚠️ [Push] Failed to fetch FCM token: \(error.localizedDescription)")
            }

            self?.didReceiveFCMToken(token)
        }
        #endif
    }

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
        guard hasAPNSToken else { return }

        if let pendingFCMToken {
            syncFCMTokenIfNeeded(pendingFCMToken)
            return
        }

        syncTokenForCurrentUserIfPossible()
    }

    private func syncFCMTokenIfNeeded(_ token: String) {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        guard cleaned != lastSyncedFCMToken else { return }

        guard let uid = Auth.auth().currentUser?.uid else {
            pendingFCMToken = cleaned
            return
        }

        lastSyncedFCMToken = cleaned
        pendingFCMToken = nil

        FirestoreService.db
            .collection("users")
            .document(uid)
            .setData(
                [
                    "fcmToken": cleaned,
                    "updatedAt": FieldValue.serverTimestamp()
                ],
                merge: true
            )

        if DebugLog.tokenEvents {
            print("✅ [Push] FCM token synced for uid: \(uid)")
        }
    }

    private func routeNotificationTap(userInfo: [AnyHashable: Any]) {
        let type = (userInfo["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        let eventID = (userInfo["eventID"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let eventURL = (userInfo["eventURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var routePayload: [String: Any] = [
            "type": type,
            "payload": userInfo
        ]

        if let eventID, !eventID.isEmpty {
            routePayload["eventID"] = eventID
        }

        if let eventURL, !eventURL.isEmpty {
            routePayload["eventURL"] = eventURL
        }

        NotificationCenter.default.post(
            name: .tgPushRoute,
            object: nil,
            userInfo: routePayload
        )
    }
}

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
        routeNotificationTap(
            userInfo: response.notification.request.content.userInfo
        )

        completionHandler()
    }
}

extension PushNotificationManager: MessagingDelegate {

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        didReceiveFCMToken(fcmToken)
    }
}
