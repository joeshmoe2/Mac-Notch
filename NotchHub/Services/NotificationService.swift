import AppKit
import UserNotifications

/// Wraps UserNotifications: permission handling, posting and sounds.
@Observable
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshStatus()
    }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NotificationService.shared.authorization = status }
            }
        }
    }

    func requestAuthorizationIfNeeded() {
        guard authorization == .notDetermined else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NotificationService.shared.refreshStatus() }
            }
        }
    }

    /// Posts a notification immediately. If notifications are denied, the
    /// module UI still shows the completed state and the optional sound plays.
    func post(title: String, body: String, identifier: String = UUID().uuidString) {
        requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static let soundNames = ["Glass", "Hero", "Ping", "Purr", "Submarine", "Funk", "Blow", "Bottle", "Frog", "Pop", "Sosumi", "Tink"]

    func playSound(named name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // Show banners even though we're an agent app that's "frontmost" from UN's point of view.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
