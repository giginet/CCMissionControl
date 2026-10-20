@testable import CCMissionControl
import Foundation
import Testing

@MainActor
struct TabCloserTests {
    private func agent(paneID: Int = 1, tabID: Int = 10, processID: Int = 100) -> Agent {
        Agent(
            paneID: paneID, tabID: tabID, workspace: "default", project: "Test",
            cwd: "/tmp", title: "", status: .idle, isActive: false, processID: processID)
    }

    private func pane(_ id: Int, tabID: Int = 10) -> WezTermPane {
        WezTermPane(
            paneId: id, tabId: tabID, workspace: "default", title: "zsh",
            cwd: "/tmp", ttyName: "/dev/ttys\(id)", isActive: false)
    }

    @Test func singlePaneClosesWithoutConfirmation() async throws {
        let session = agent()
        let terminal = Terminal(panes: [pane(1), pane(9, tabID: 90)])
        let closer = TabCloser(
            fetchPanes: { await terminal.panes }, fetchAgents: { [session] },
            killPane: { await terminal.kill($0) })
        let plan = try await closer.prepare(for: session)
        #expect(!plan.requiresConfirmation)
        try await closer.close(plan)
        #expect(await terminal.killed == [1])
        #expect(await terminal.panes.map(\.paneId) == [9])
    }

    @Test func splitWithShellRequiresConfirmationAndClosesWholeTab() async throws {
        let session = agent()
        let terminal = Terminal(panes: [pane(1), pane(2)])
        let closer = TabCloser(
            fetchPanes: { await terminal.panes }, fetchAgents: { [session] },
            killPane: { await terminal.kill($0) })
        let plan = try await closer.prepare(for: session)
        #expect(plan.requiresConfirmation)
        #expect(await terminal.killed.isEmpty)
        try await closer.close(plan)
        #expect(await terminal.killed == [2, 1])
    }

    @Test func newSplitAfterConfirmationPreventsClosing() async throws {
        let session = agent()
        let terminal = Terminal(panes: [pane(1)])
        let closer = TabCloser(
            fetchPanes: { await terminal.panes }, fetchAgents: { [session] },
            killPane: { await terminal.kill($0) })
        let plan = try await closer.prepare(for: session)
        await terminal.add(pane(2))
        await #expect(throws: TabCloseError.self) { try await closer.close(plan) }
        #expect(await terminal.killed.isEmpty)
    }

    @Test func multipleAgentSessionsRequireConfirmation() async throws {
        let first = agent()
        let second = agent(paneID: 2, processID: 200)
        let terminal = Terminal(panes: [pane(1), pane(2)])
        let closer = TabCloser(
            fetchPanes: { await terminal.panes }, fetchAgents: { [first, second] },
            killPane: { await terminal.kill($0) })
        let plan = try await closer.prepare(for: first)
        #expect(plan.requiresConfirmation)
        #expect(plan.sessions.count == 2)
        #expect(await terminal.killed.isEmpty)
    }

    @Test func commandFailureStopsBeforeClosingOtherPanes() async throws {
        let session = agent()
        let terminal = Terminal(panes: [pane(1), pane(2)])
        let closer = TabCloser(
            fetchPanes: { await terminal.panes }, fetchAgents: { [session] },
            killPane: { _ in throw ShellExecutor.ShellError.nonZeroExit(1) })
        let plan = try await closer.prepare(for: session)
        await #expect(throws: ShellExecutor.ShellError.self) { try await closer.close(plan) }
        #expect(await terminal.panes.count == 2)
    }

    @Test func movedSessionPreventsClosing() async throws {
        let session = agent()
        let terminal = Terminal(panes: [pane(1, tabID: 90)])
        let closer = TabCloser(
            fetchPanes: { await terminal.panes }, fetchAgents: { [session] },
            killPane: { await terminal.kill($0) })
        await #expect(throws: TabCloseError.self) { try await closer.prepare(for: session) }
        #expect(await terminal.killed.isEmpty)
    }

    @Test func replacedSessionPreventsClosing() async throws {
        let session = agent()
        let replacement = agent(processID: 200)
        let terminal = Terminal(panes: [pane(1)])
        let closer = TabCloser(
            fetchPanes: { await terminal.panes }, fetchAgents: { [replacement] },
            killPane: { await terminal.kill($0) })
        await #expect(throws: TabCloseError.self) { try await closer.prepare(for: session) }
        #expect(await terminal.killed.isEmpty)
    }
}

private actor Terminal {
    var panes: [WezTermPane]
    var killed: [Int] = []

    init(panes: [WezTermPane]) { self.panes = panes }
    func add(_ pane: WezTermPane) { panes.append(pane) }
    func kill(_ id: Int) {
        killed.append(id)
        panes.removeAll { $0.paneId == id }
    }
}
