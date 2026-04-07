import AppKit
import Combine
import SwiftUI

@main
struct CCMissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: FloatingPanelController!
    private let viewModel = AgentListViewModel()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SystemNotificationService.shared.setUp()
        SystemNotificationService.shared.requestAuthorization()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }

        panelController = FloatingPanelController {
            ContentView(viewModel: self.viewModel)
                .frame(width: 480, height: 400)
        }

        viewModel.startScanning()
        updateStatusItemLabel()

        cancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.updateStatusItemLabel() }

        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updateStatusItemLabel()
        }
    }

    @objc private func statusItemClicked() {
        panelController.toggle(relativeTo: statusItem.button)
    }

    private func updateStatusItemLabel() {
        guard let button = statusItem.button else { return }

        let runningCount = viewModel.agents.filter { $0.status == .running }.count
        let totalCount = viewModel.agents.count
        let hasUnread = !viewModel.unreadPaneIDs.isEmpty

        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

        let attachment = NSMutableAttributedString()

        if hasUnread {
            if let bellImage = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let bellAttachment = NSTextAttachment()
                bellAttachment.image = bellImage
                attachment.append(NSAttributedString(attachment: bellAttachment))
                attachment.append(NSAttributedString(string: " "))
            }
        }

        let iconName = runningCount > 0 ? "bolt.fill" : "powersleep"
        if let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let iconAttachment = NSTextAttachment()
            iconAttachment.image = iconImage
            attachment.append(NSAttributedString(attachment: iconAttachment))
        }

        let count = runningCount > 0 ? runningCount : totalCount
        let countString = NSAttributedString(
            string: " \(count)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)]
        )
        attachment.append(countString)

        button.attributedTitle = attachment
    }
}
