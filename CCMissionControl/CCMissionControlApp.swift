import SwiftUI

@main
struct CCMissionControlApp: App {
    @State private var viewModel = AgentListViewModel()

    init() {
        SystemNotificationService.shared.setUp()
        SystemNotificationService.shared.requestAuthorization()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: viewModel)
                .frame(width: 480, height: 350)
                .onAppear { viewModel.startScanning() }
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
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
