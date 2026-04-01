import SwiftUI

@main
struct CCMissionControlApp: App {
    @State private var viewModel: AgentListViewModel = {
        let vm = AgentListViewModel()
        vm.onSessionCompleted = { agent in
            NotificationService.shared.sendCompletionNotification(for: agent)
        }
        vm.startScanning()
        return vm
    }()

    init() {
        NotificationService.shared.setUp()
        NotificationService.shared.requestAuthorization()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: viewModel)
                .frame(width: 480, height: 350)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let viewModel: AgentListViewModel

    var body: some View {
        let runningCount = viewModel.agents.filter { $0.status == .running }.count
        let totalCount = viewModel.agents.count
        let hasUnread = !viewModel.unreadPaneIDs.isEmpty

        HStack(alignment: .center, spacing: 4) {
            if hasUnread {
                Image(systemName: "bell.badge.fill")
            }
            Image(systemName: runningCount > 0 ? "bolt.fill" : "powersleep")
                .imageScale(.small)
            Text("\(runningCount > 0 ? runningCount : totalCount)")
                .monospacedDigit()
        }
    }
}
