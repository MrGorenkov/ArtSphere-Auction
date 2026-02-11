import Foundation
import UIKit
import UserNotifications

/// Manages push notification registration and handling via APNs.
///
/// Setup:
/// 1. Enable "Push Notifications" capability in Xcode
/// 2. Add `aps-environment` entitlement
/// 3. Configure APNs key in Apple Developer Portal
/// 4. Backend sends push via Vapor's APNS library
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    @Published var isRegistered = false
    @Published var deviceToken: String?

    private let network = NetworkService.shared

    private override init() {
        super.init()
    }

    // MARK: - Registration

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { [weak self] granted, error in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                self?.isRegistered = granted
            }
            if let error {
                print("[Push] Permission error: \(error)")
            }
        }
    }

    func handleDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        print("[Push] Device token: \(tokenString)")

        // Send token to backend
        registerTokenOnServer(tokenString)
    }

    func handleRegistrationError(_ error: Error) {
        print("[Push] Registration failed: \(error)")
    }

    // MARK: - Server Registration

    private func registerTokenOnServer(_ token: String) {
        guard network.authToken != nil else { return }

        Task {
            do {
                try await network.requestVoid(
                    endpoint: "users/me/device-token",
                    method: .post,
                    body: DeviceTokenRequest(token: token, platform: "ios")
                )
                print("[Push] Token registered on server")
            } catch {
                print("[Push] Failed to register token: \(error)")
            }
        }
    }

    // MARK: - Handle Incoming Notifications

    func handleNotification(
        _ userInfo: [AnyHashable: Any],
        completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Always show notification as banner when app is in foreground
        completionHandler([.banner, .badge, .sound])

        AnalyticsService.shared.track(.screenView, parameters: [
            "screen_name": "push_notification",
            "type": userInfo["type"] as? String ?? "unknown"
        ])
    }

    func handleNotificationTap(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo

        if let type = userInfo["type"] as? String {
            switch type {
            case "outbid", "bid":
                if let auctionId = userInfo["auctionId"] as? String {
                    NotificationCenter.default.post(
                        name: .pushNavigateToAuction,
                        object: nil,
                        userInfo: ["auctionId": auctionId]
                    )
                }
            case "auction_won":
                NotificationCenter.default.post(
                    name: .pushNavigateToCollection,
                    object: nil
                )
            default:
                break
            }
        }
    }

    // MARK: - Local Notification (fallback when push not available)

    func scheduleLocalNotification(title: String, body: String, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handleNotification(
            notification.request.content.userInfo,
            completionHandler: completionHandler
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationTap(response)
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let pushNavigateToAuction = Notification.Name("pushNavigateToAuction")
    static let pushNavigateToCollection = Notification.Name("pushNavigateToCollection")
}

// MARK: - Request DTO

private struct DeviceTokenRequest: Codable {
    let token: String
    let platform: String
}
