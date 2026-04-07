import SwiftUI

@Observable
final class AgentListViewModel {
    private(set) var agents: [Agent] = []
    private(set) var error: (any Error)?
    private(set) var isScanning = false
    private(set) var unreadPaneIDs: Set<Int> = []
    let notificationService: any NotificationServiceProtocol
    private var previousStatusByPaneID: [Int: Agent.Status] = [:]
    private var timer: Timer?

    init(notificationService: some NotificationServiceProtocol = SystemNotificationService.shared) {
        self.notificationService = notificationService
    }

    func startScanning() {
        guard timer == nil else { return }
        scanNow()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.scanNow()
        }
    }

    func markAsRead(_ agent: Agent) {
        unreadPaneIDs.remove(agent.paneID)
    }

    func scanNow() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            do {
                let result = try await AgentScanner.scan()
                applyResult(result)
            } catch {
                self.error = error
            }
            self.isScanning = false
        }
    }

    var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }

    func applyResult(_ result: [Agent]) {
        for agent in result {
            let previousStatus = previousStatusByPaneID[agent.paneID]
            if previousStatus == .running && agent.status == .idle && !agent.isActive {
                unreadPaneIDs.insert(agent.paneID)
                if notificationsEnabled {
                    notificationService.sendCompletionNotification(for: agent)
                }
            }
            if agent.isActive {
                unreadPaneIDs.remove(agent.paneID)
            }
            previousStatusByPaneID[agent.paneID] = agent.status
        }
        self.agents = result
        self.error = nil
    }
}

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    let viewModel: AgentListViewModel

    var body: some View {
        Group {
            if let error = viewModel.error {
                ContentUnavailableView {
                    Label("Scan Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            } else if viewModel.agents.isEmpty {
                ContentUnavailableView(
                    "No Claude Code Sessions",
                    systemImage: "terminal",
                    description: Text("No active Claude Code sessions found in WezTerm.")
                )
            } else {
                List(viewModel.agents) { agent in
                    AgentRowView(
                        agent: agent,
                        isUnread: viewModel.unreadPaneIDs.contains(agent.paneID),
                        isActive: agent.isActive
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.markAsRead(agent)
                        Task {
                            await AgentScanner.activateTab(for: agent)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FooterView(
                onSettings: { openSettings() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.scanNow()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isScanning)
            }
        }
        .onAppear { viewModel.startScanning() }
    }
}

struct FooterButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .glassEffect()
    }
}

struct FooterView: View {
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            FooterButton(icon: "gearshape", title: "Settings", action: onSettings)
                .fixedSize()
            Spacer()
            FooterButton(icon: "power", title: "Quit", action: onQuit)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview("Footer") {
    FooterView()
        .frame(width: 480)
}
