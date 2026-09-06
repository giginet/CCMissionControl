import SwiftUI

@Observable
final class AgentListViewModel {
    private(set) var agents: [Agent] = []
    private(set) var error: (any Error)?
    private(set) var isScanning = false
    private(set) var unreadPaneIDs: Set<Int> = []
    let notificationService: any NotificationServiceProtocol
    private var previousAgentsByPaneID: [Int: Agent] = [:]
    private var overriddenActivePaneID: Int?
    private var overrideSetAt: Date?
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

    func setActive(paneID: Int) {
        overriddenActivePaneID = paneID
        overrideSetAt = Date()
        agents = agents.map { agent in
            var updated = agent
            updated.isActive = agent.paneID == paneID
            return updated
        }
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

    var notifyForeground: Bool {
        UserDefaults.standard.bool(forKey: "notifyForeground")
    }

    func applyResult(_ result: [Agent]) {
        // Clear override when WezTerm is foreground so scan's focused_pane_id takes effect.
        // Skip clearing for 5 seconds after click since activateTab briefly makes WezTerm active.
        if overriddenActivePaneID != nil {
            let cooldownElapsed = overrideSetAt.map { Date().timeIntervalSince($0) > 5 } ?? true
            if cooldownElapsed {
                let wezTermIsActive =
                    NSRunningApplication.runningApplications(
                        withBundleIdentifier: "com.github.wez.wezterm"
                    ).first?.isActive ?? false
                if wezTermIsActive {
                    overriddenActivePaneID = nil
                    overrideSetAt = nil
                }
            }
        }

        var updatedAgents: [Agent] = []
        for agent in result {
            var effectiveAgent = agent
            if let overrideID = overriddenActivePaneID {
                effectiveAgent.isActive = agent.paneID == overrideID
            }
            let previous = previousAgentsByPaneID[effectiveAgent.paneID]
            let sameSession = previous?.sessionIdentity == effectiveAgent.sessionIdentity
            if !sameSession { unreadPaneIDs.remove(effectiveAgent.paneID) }
            let becameIdle =
                sameSession && previous?.status == .running && effectiveAgent.status == .idle
            if becameIdle && !effectiveAgent.isActive {
                unreadPaneIDs.insert(effectiveAgent.paneID)
            }
            if becameIdle && notificationsEnabled
                && (!effectiveAgent.isActive || notifyForeground)
            {
                notificationService.sendCompletionNotification(for: effectiveAgent)
            }
            if effectiveAgent.isActive {
                unreadPaneIDs.remove(effectiveAgent.paneID)
            }
            updatedAgents.append(effectiveAgent)
        }
        previousAgentsByPaneID = Dictionary(
            uniqueKeysWithValues: updatedAgents.map { ($0.paneID, $0) })
        unreadPaneIDs.formIntersection(previousAgentsByPaneID.keys)
        self.agents = updatedAgents
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
                    "No Agent Sessions",
                    systemImage: "terminal",
                    description: Text("No Claude Code or Codex sessions found in WezTerm.")
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
                        viewModel.setActive(paneID: agent.paneID)
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
