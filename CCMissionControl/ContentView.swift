import SwiftUI

@Observable
final class AgentListViewModel {
    private(set) var agents: [Agent] = []
    private(set) var error: (any Error)?
    private(set) var isScanning = false
    private var timer: Timer?

    func startScanning() {
        scanNow()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.scanNow()
        }
    }

    func stopScanning() {
        timer?.invalidate()
        timer = nil
    }

    func scanNow() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            do {
                let result = try await AgentScanner.scan()
                self.agents = result
                self.error = nil
            } catch {
                self.error = error
            }
            self.isScanning = false
        }
    }
}

struct ContentView: View {
    @State private var viewModel = AgentListViewModel()

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
                    AgentRowView(agent: agent)
                        .contentShape(Rectangle())
                        .onTapGesture {
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
        .frame(minWidth: 400, minHeight: 300)
        .onAppear { viewModel.startScanning() }
        .onDisappear { viewModel.stopScanning() }
    }
}

#Preview {
    ContentView()
}
