import SwiftUI
import UIKit
import FirebaseCore
import FirebaseMessaging
import FirebaseAppCheck

// MARK: - App Check Provider Factory

final class TriviaGoatAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        } else {
            return DeviceCheckProvider(app: app)
        }
        #endif
    }
}

// MARK: - AppDelegate bridge

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // MARK: App Check
        // Must be installed BEFORE FirebaseApp.configure()
        AppCheck.setAppCheckProviderFactory(TriviaGoatAppCheckProviderFactory())

        #if DEBUG
        #if targetEnvironment(simulator)
        if let debugToken = ProcessInfo.processInfo.environment["FIRA_APP_CHECK_DEBUG_TOKEN"],
           !debugToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(
                debugToken.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: "FIRAAppCheckDebugToken"
            )
            print("🟠 [AppCheck] Using simulator debug token from Xcode scheme.")
        } else {
            print("🔴 [AppCheck] Missing FIRA_APP_CHECK_DEBUG_TOKEN env var for simulator.")
            print("🔴 [AppCheck] Add it in Xcode Scheme > Run > Arguments > Environment Variables.")
        }
        #endif
        #endif

        FirebaseApp.configure()
        print("✅ Firebase configured in AppDelegate.")

        PushNotificationManager.shared.configure()

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
    }
}

// MARK: - App Entry

@main
struct TriviaGoatNextGenApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @StateObject private var appState = AppState()
    @StateObject private var motion = MotionManager()

    @State private var didBootPro: Bool = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ContentView()
            }
            .environmentObject(appState)
            .environmentObject(motion)
            .environmentObject(ProManager.shared)
            .onAppear {
                appState.bootIfNeeded()

                guard !didBootPro else { return }
                didBootPro = true

                Task {
                    await ProManager.shared.boot()
                }
            }
            .onOpenURL { url in
                appState.handleIncomingEventURL(url)
            }
        }
    }
}
