import AppKit
import UserNotifications

protocol NotificationServiceProtocol: Sendable {
    func sendCompletionNotification(for agent: Agent)
    func getAuthorizationStatus() async -> UNAuthorizationStatus
}

final class SystemNotificationService: NSObject, NotificationServiceProtocol,
    UNUserNotificationCenterDelegate
{
    static let shared = SystemNotificationService()

    private override init() {
        super.init()
    }

    func setUp() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
            _, _ in
        }
    }

    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func sendCompletionNotification(for agent: Agent) {
        let content = UNMutableNotificationContent()
        content.title = "\(agent.project) completed"
        content.subtitle = agent.cwd
        content.body = agent.title
        content.sound = .default
        content.userInfo = ["tabID": agent.tabID]

        let request = UNNotificationRequest(
            identifier: "agent-\(agent.paneID)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let tabID = userInfo["tabID"] as? Int else {
            completionHandler()
            return
        }

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
        Task {
            await AgentScanner.activateTab(for: agent)
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

final class MockNotificationService: NotificationServiceProtocol, @unchecked Sendable {
    private(set) var notifiedAgents: [Agent] = []

    func sendCompletionNotification(for agent: Agent) {
        notifiedAgents.append(agent)
    }

    func getAuthorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }
}
