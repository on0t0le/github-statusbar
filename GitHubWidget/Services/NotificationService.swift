import Foundation
import UserNotifications
import AppKit

protocol NotificationServiceProtocol: AnyObject {
    func requestPermission() async -> Bool
    func diff(old: PRFetchResult?, new: PRFetchResult, username: String) -> Set<Int>
}

final class NotificationService: NSObject, NotificationServiceProtocol {
    static let shared = NotificationService()
    private override init() {}

    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func diff(old: PRFetchResult?, new: PRFetchResult, username: String) -> Set<Int> {
        guard let old = old else { return [] }
        var unseenIds = Set<Int>()

        let oldChangesIds = Set(old.changesRequested.map(\.id))
        for pr in new.changesRequested where !oldChangesIds.contains(pr.id) {
            post(title: "Changes requested", body: pr.title, prId: pr.id, url: pr.htmlUrl)
            unseenIds.insert(pr.id)
        }

        let oldReviewIds = Set(old.reviewRequested.map(\.id))
        for pr in new.reviewRequested where !oldReviewIds.contains(pr.id) && !unseenIds.contains(pr.id) {
            post(title: "New review request", body: pr.title, prId: pr.id, url: pr.htmlUrl)
            unseenIds.insert(pr.id)
        }

        let oldReadyIds = Set(old.readyToMerge.map(\.id))
        for pr in new.readyToMerge
            where !oldReadyIds.contains(pr.id) && pr.user.login == username && !unseenIds.contains(pr.id) {
            post(title: "PR approved", body: pr.title, prId: pr.id, url: pr.htmlUrl)
            unseenIds.insert(pr.id)
        }

        return unseenIds
    }

    private func post(title: String, body: String, prId: Int, url: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["url": url]
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
