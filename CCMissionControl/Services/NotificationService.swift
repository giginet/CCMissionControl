import AppKit
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func sendCompletionNotification(for agent: Agent) {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code completed"
        content.body = "\(agent.project) (\(agent.workspace))"
        content.sound = .default
        content.userInfo = ["tabID": agent.tabID]

        let request = UNNotificationRequest(
            identifier: "agent-\(agent.paneID)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let tabID = userInfo["tabID"] as? Int else { return }

        let agent = Agent(
            paneID: -1,
            tabID: tabID,
            workspace: "",
            project: "",
            cwd: "",
            title: "",
            status: .idle,
            isActive: false
        )
        await AgentScanner.activateTab(for: agent)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
