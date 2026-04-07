import Testing
import Foundation
@testable import CCMissionControl

// isActive is determined by matching focused_pane_id from list-clients.
// Only the pane the user is actually viewing is true.

@MainActor
struct AgentListViewModelTests {
    private func makeViewModel() -> (AgentListViewModel, MockNotificationService) {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        return (vm, mock)
    }

    private func makeAgent(
        paneID: Int = 0,
        status: Agent.Status,
        isActive: Bool
    ) -> Agent {
        Agent(
            paneID: paneID,
            tabID: 0,
            workspace: "default",
            project: "TestProject",
            cwd: "~/test",
            title: "",
            status: status,
            isActive: isActive
        )
    }

    // MARK: - No badge for focused pane

    @Test func noUnreadWhenFocusedPane_RunningToIdle() {
        let (vm, _) = makeViewModel()

        // User keeps focus on this pane during running→idle
        vm.applyResult([makeAgent(status: .running, isActive: true)])
        vm.applyResult([makeAgent(status: .idle, isActive: true)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - Badge for unfocused pane

    @Test func unreadWhenUnfocusedPane_RunningToIdle() {
        let (vm, _) = makeViewModel()

        // Claude Code running in another tab (unfocused) transitions to idle
        vm.applyResult([makeAgent(status: .running, isActive: false)])
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))
    }

    // MARK: - Mark as read on click

    @Test func markAsReadClearsBadge() {
        let (vm, _) = makeViewModel()

        vm.applyResult([makeAgent(status: .running, isActive: false)])
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))

        vm.markAsRead(makeAgent(status: .idle, isActive: false))
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - No badge for idle→idle

    @Test func noUnreadWhenIdleToIdle() {
        let (vm, _) = makeViewModel()

        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - No badge on first scan

    @Test func noUnreadOnFirstScan() {
        let (vm, _) = makeViewModel()

        // previousStatus is nil → not a running→idle transition, so no unread
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - Multiple sessions are independent

    @Test func multipleSessionsIndependent() {
        let (vm, _) = makeViewModel()

        // pane 0: focused, pane 1: another tab (unfocused)
        vm.applyResult([
            makeAgent(paneID: 0, status: .running, isActive: true),
            makeAgent(paneID: 1, status: .running, isActive: false),
        ])

        // Both go idle → pane 0 is focused so no unread, pane 1 is unread
        vm.applyResult([
            makeAgent(paneID: 0, status: .idle, isActive: true),
            makeAgent(paneID: 1, status: .idle, isActive: false),
        ])
        #expect(!vm.unreadPaneIDs.contains(0))
        #expect(vm.unreadPaneIDs.contains(1))
    }

    // MARK: - Focus change timing

    @Test func focusedWhileRunning_UnfocusedWhenIdle_ShowsBadge() {
        let (vm, _) = makeViewModel()

        // Focused while running
        vm.applyResult([makeAgent(status: .running, isActive: true)])

        // Focus moved to another pane when transitioning to idle → show badge
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))
    }

    @Test func unfocusedWhileRunning_FocusedWhenIdle_NoBadge() {
        let (vm, _) = makeViewModel()

        // Unfocused while running
        vm.applyResult([makeAgent(status: .running, isActive: false)])

        // User returned focus just as it went idle → no badge
        vm.applyResult([makeAgent(status: .idle, isActive: true)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - Unread cleared when focus returns

    @Test func unreadClearedByFocusReturn() {
        let (vm, _) = makeViewModel()

        // Create unread state
        vm.applyResult([makeAgent(status: .running, isActive: false)])
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))

        // User returns to the tab (focused) → unread is cleared
        vm.applyResult([makeAgent(status: .idle, isActive: true)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - No badge for running→running

    @Test func noUnreadWhenRunningToRunning() {
        let (vm, _) = makeViewModel()

        vm.applyResult([makeAgent(status: .running, isActive: false)])
        vm.applyResult([makeAgent(status: .running, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - Notification delivery

    @Test func notificationSentWhenUnfocusedSessionCompletes() {
        let (vm, mock) = makeViewModel()

        vm.applyResult([makeAgent(status: .running, isActive: false)])
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(mock.notifiedAgents.count == 1)
        #expect(mock.notifiedAgents[0].paneID == 0)
    }

    @Test func noNotificationWhenFocusedSessionCompletes() {
        let (vm, mock) = makeViewModel()

        vm.applyResult([makeAgent(status: .running, isActive: true)])
        vm.applyResult([makeAgent(status: .idle, isActive: true)])
        #expect(mock.notifiedAgents.isEmpty)
    }
}
