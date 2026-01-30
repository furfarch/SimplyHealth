#if canImport(UIKit)
import Foundation
import UIKit
import CloudKit

// Scene delegate to handle modern URL / userActivity delivery (iOS 13+ scenes)
@objc
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // Called when app is COLD LAUNCHED (not running) - share data comes through options
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        ShareDebugStore.shared.appendLog("SceneDelegate: willConnectTo called, urlContexts=\(connectionOptions.urlContexts.count), userActivities=\(connectionOptions.userActivities.count)")

        // Check for share URL in URL contexts (cold launch via URL scheme)
        for context in connectionOptions.urlContexts {
            handleShareURL(context.url)
        }

        // Check for share in user activities (cold launch via universal link or CloudKit share)
        for userActivity in connectionOptions.userActivities {
            handleUserActivity(userActivity)
        }
    }

    // Called when app is ALREADY RUNNING and receives a URL
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            handleShareURL(context.url)
        }
    }

    // Called when app is ALREADY RUNNING and receives a user activity (universal link, CloudKit share)
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleUserActivity(userActivity)
    }

    private func handleShareURL(_ url: URL) {
        ShareDebugStore.shared.appendLog("SceneDelegate: received URL: \(url.absoluteString)")
        PendingShareStore.shared.pendingURL = url
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NotificationNames.pendingShareReceived,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }

    private func handleUserActivity(_ userActivity: NSUserActivity) {
        ShareDebugStore.shared.appendLog("SceneDelegate: received userActivity type: \(userActivity.activityType)")

        // Check for CloudKit share metadata (available iOS 10+)
        if let metadata = extractCloudKitMetadata(from: userActivity) {
            ShareDebugStore.shared.appendLog("SceneDelegate: found cloudKitShareMetadata, container: \(metadata.containerIdentifier)")
            PendingShareStore.shared.pendingMetadata = metadata
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NotificationNames.pendingShareReceived,
                    object: nil,
                    userInfo: ["metadata": metadata]
                )
            }
            return
        }

        // Fall back to webpage URL (universal links)
        if let url = userActivity.webpageURL {
            ShareDebugStore.shared.appendLog("SceneDelegate: found webpageURL: \(url.absoluteString)")
            handleShareURL(url)
        }
    }

    private func extractCloudKitMetadata(from userActivity: NSUserActivity) -> CKShare.Metadata? {
        // Use Key-Value coding to access cloudKitShareMetadata safely
        // This avoids compilation issues with the property not being found
        return userActivity.value(forKey: "cloudKitShareMetadata") as? CKShare.Metadata
    }
}

@objc
class AppDelegate: UIResponder, UIApplicationDelegate {
    // Provide a scene configuration that uses `SceneDelegate` as the scene's delegate class.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // Fallback acceptance for older code paths (pre-scene apps). Keep minimal.
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        ShareDebugStore.shared.appendLog("AppDelegate: received userActivity type: \(userActivity.activityType)")

        // Use Key-Value coding to access cloudKitShareMetadata safely
        if let metadata = userActivity.value(forKey: "cloudKitShareMetadata") as? CKShare.Metadata {
            ShareDebugStore.shared.appendLog("AppDelegate: found cloudKitShareMetadata")
            PendingShareStore.shared.pendingMetadata = metadata
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NotificationNames.pendingShareReceived,
                    object: nil,
                    userInfo: ["metadata": metadata]
                )
            }
            return true
        }

        if let url = userActivity.webpageURL {
            ShareDebugStore.shared.appendLog("AppDelegate: found webpageURL: \(url.absoluteString)")
            PendingShareStore.shared.pendingURL = url
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NotificationNames.pendingShareReceived,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
            return true
        }

        return false
    }
}
#endif
