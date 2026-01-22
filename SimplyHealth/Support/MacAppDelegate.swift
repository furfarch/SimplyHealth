#if os(macOS)
import Cocoa

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            PendingShareStore.shared.pendingURL = url
            NotificationCenter.default.post(name: NotificationNames.pendingShareReceived, object: nil, userInfo: ["url": url])
        }
    }

    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        return false
    }
}
#endif
