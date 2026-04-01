import SwiftUI

@Observable
final class AgentListViewModel {
    private(set) var agents: [Agent] = []
    private(set) var error: (any Error)?
    private(set) var isScanning = false
    private(set) var unreadPaneIDs: Set<Int> = []
    private var previousStatusByPaneID: [Int: Agent.Status] = [:]
    private var timer: Timer?

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

    func applyResult(_ result: [Agent]) {
        for agent in result {
            let previousStatus = previousStatusByPaneID[agent.paneID]
            if previousStatus == .running && agent.status == .idle && !agent.isActive {
                unreadPaneIDs.insert(agent.paneID)
                NotificationService.shared.sendCompletionNotification(for: agent)
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
                        isUnread: viewModel.unreadPaneIDs.contains(agent.paneID)
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

#Preview {
    ContentView(viewModel: AgentListViewModel())
}
