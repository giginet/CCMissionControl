import Testing

@testable import CCMissionControl

struct CodexStatusTests {
    @Test(arguments: ["Ready", "Ready | project", "  Ready | project\n"])
    func recognizesIdle(_ title: String) {
        #expect(CodexDetector.status(fromTitle: title) == .idle)
    }

    @Test(arguments: ["Working", "Thinking", "Working | project", "Thinking | project"])
    func recognizesRunning(_ title: String) {
        #expect(CodexDetector.status(fromTitle: title) == .running)
    }

    @Test(arguments: Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"))
    func recognizesSpinner(_ frame: Character) {
        #expect(CodexDetector.status(fromTitle: "\(frame) project") == .running)
        #expect(CodexDetector.status(fromTitle: String(frame)) == .running)
    }

    @Test(arguments: [
        "[ ! ] Action Required", "[ . ] Action Required",
        "[ ! ] Action Required | project", "[ . ] Action Required | Ready",
    ])
    func recognizesWaiting(_ title: String) {
        #expect(CodexDetector.status(fromTitle: title) == .waiting)
    }

    @Test(arguments: [
        "", "project", "zsh", "project | Ready", "Already Working", "ReadyPlayerOne",
        "Working notes", "[ ! ] Action Required documentation", "⠋project", "✳ Claude",
    ])
    func unrecognizedTitlesStayUnknown(_ title: String) {
        #expect(CodexDetector.status(fromTitle: title) == .unknown)
    }

    @Test func scannerUsesRawPaneTitleAndPreservesClaudeDetection() {
        let tree = ProcessTree(
            parsing: "PID PPID TTY COMM\n100 1 ttys001 codex\n200 1 ttys002 claude",
            argumentsByPID: [100: ["codex"]])
        for (title, expected) in [
            ("⠸ project", Agent.Status.running), ("Ready | project", .idle),
            ("[ ! ] Action Required | project", .waiting), ("project", .idle),
        ] {
            let agents = AgentScanner.agents(
                panes: [pane(1, title), pane(2, "⠸ Claude")], tree: tree, focusedPaneID: 1)
            #expect(agents.first(where: { $0.kind == .codex })?.status == expected)
            #expect(agents.first(where: { $0.kind == .claudeCode })?.status == .idle)
        }
    }

    @Test func defaultIdleTitleMustMatchPaneDirectory() {
        let detector = CodexDetector()
        let detection = AgentDetection(pid: 100, kind: .codex, status: .unknown)
        for (cwd, title, expected) in [
            ("file:///Users/test/work/voxkhronos", "voxkhronos", Agent.Status.idle),
            ("/Users/test/work/voxkhronos", "voxkhronos", .idle),
            ("file:///tmp/my%20project", "my project", .idle),
            ("file:///tmp/project", "zsh", .unknown),
            ("file:///tmp/project", "different project", .unknown),
            ("", "", .unknown),
            ("file:///tmp/project", "⠸ project", .running),
            ("file:///tmp/project", "[ ! ] Action Required | project", .waiting),
        ] {
            let pane = WezTermPane(
                paneId: 1, tabId: 1, workspace: "default", title: title,
                cwd: cwd, ttyName: "/dev/ttys001", isActive: false)
            #expect(detector.status(for: detection, pane: pane) == expected)
        }
    }

    private func pane(_ id: Int, _ title: String) -> WezTermPane {
        WezTermPane(
            paneId: id, tabId: id, workspace: "default", title: title,
            cwd: "file:///tmp/project", ttyName: "/dev/ttys00\(id)", isActive: false)
    }
}

@MainActor
struct CodexStatusNotificationTests {
    @Test func waitingIsNotCompletion() {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        for status in [Agent.Status.running, .waiting, .waiting, .idle] {
            vm.applyResult([agent(status)])
        }
        #expect(mock.notifiedAgents.isEmpty)
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    @Test func completionAfterResumingFromWaitingNotifiesOnce() {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        for status in [Agent.Status.running, .waiting, .running, .idle, .idle] {
            vm.applyResult([agent(status)])
        }
        #expect(mock.notifiedAgents.count == 1)
        #expect(vm.unreadPaneIDs == [1])
    }

    private func agent(_ status: Agent.Status) -> Agent {
        Agent(
            paneID: 1, tabID: 1, workspace: "default", project: "test", cwd: "/tmp", title: "",
            status: status, isActive: false, kind: .codex, processID: 100)
    }
}

@MainActor
struct CodexNotificationPipelineTests {
    @Test func defaultTitlesProduceOneCompletionNotification() {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        for title in ["⠸ project", "⠦ project", "project", "project"] {
            vm.applyResult(scan(title: title, focusedPaneID: 2))
        }
        #expect(mock.notifiedAgents.count == 1)
        #expect(mock.notifiedAgents.first?.kind == .codex)
        #expect(mock.notifiedAgents.first?.paneID == 1)
        #expect(mock.notifiedAgents.first?.tabID == 10)
        #expect(vm.unreadPaneIDs == [1])
    }

    @Test func focusedCodexDoesNotNotify() {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        for title in ["⠸ project", "project"] {
            vm.applyResult(scan(title: title, focusedPaneID: 1))
        }
        #expect(mock.notifiedAgents.isEmpty)
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    @Test func waitingAndUnknownTitlesDoNotProduceCompletion() {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        for title in [
            "⠸ project", "[ ! ] Action Required | project", "project",
            "⠸ project", "custom title", "project",
        ] {
            vm.applyResult(scan(title: title, focusedPaneID: 2))
        }
        #expect(mock.notifiedAgents.isEmpty)
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    private func scan(title: String, focusedPaneID: Int?) -> [Agent] {
        let tree = ProcessTree(
            parsing: "PID PPID TTY COMM\n100 1 ttys001 codex",
            argumentsByPID: [100: ["codex"]])
        let pane = WezTermPane(
            paneId: 1, tabId: 10, workspace: "default", title: title,
            cwd: "file:///tmp/project", ttyName: "/dev/ttys001", isActive: true)
        return AgentScanner.agents(panes: [pane], tree: tree, focusedPaneID: focusedPaneID)
    }
}
