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
            ("⠸ Fix build | project", .running), ("Fix build | project", .idle),
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
            ("file:///tmp/Scipio/", "CIを26以上に更新し27での実行を追加 | Scipio", .idle),
            ("file:///tmp/project", "Fix build | project", .idle),
            ("file:///tmp/project", "Fix build | add tests | project", .idle),
            ("file:///tmp/project", "  Fix build | project\n", .idle),
            ("file:///tmp/project", "Fix build | another-project", .idle),
            ("file:///tmp/project", "Fix build | project | extra", .unknown),
            ("file:///tmp/project", "Fix build | proj...", .unknown),
            ("file:///tmp/project", " | project", .unknown),
            ("file:///tmp/project", "project | Ready", .unknown),
            ("file:///tmp/project", "zsh", .unknown),
            ("file:///tmp/project", "different project", .unknown),
            ("", "", .unknown),
            ("file:///tmp/project", "⠸ project", .running),
            ("file:///tmp/project", "[ ! ] Action Required | project", .waiting),
            ("file:///tmp/project", "⠸ Fix build | project", .running),
            ("file:///tmp/project", "[ ! ] Action Required | Fix build | project", .waiting),
        ] {
            let pane = WezTermPane(
                paneId: 1, tabId: 1, workspace: "default", title: title,
                cwd: cwd, ttyName: "/dev/ttys001", isActive: false)
            #expect(detector.status(for: detection, pane: pane) == expected)
        }
    }

    @Test func abbreviatedProjectTitlesMustMatchPaneDirectory() {
        let detector = CodexDetector()
        let detection = AgentDetection(pid: 100, kind: .codex, status: .unknown)
        for (title, expected) in [
            ("long-project-name-for...", Agent.Status.idle),
            ("Fix build | long-project-name-for...", .idle),
            ("Fix build | long-project-name-for-title-tests", .idle),
            ("⠸ Fix build | long-project-name-for...", .running),
            ("[ . ] Action Required | Fix build | long-project-name-for...", .waiting),
            ("Fix build | long-project-name-...", .unknown),
            ("Fix build | another-project-nam...", .unknown),
        ] {
            let pane = WezTermPane(
                paneId: 1, tabId: 1, workspace: "default", title: title,
                cwd: "file:///tmp/long-project-name-for-title-tests/",
                ttyName: "/dev/ttys001", isActive: false)
            #expect(detector.status(for: detection, pane: pane) == expected)
        }
    }

    @Test func resumedThreadTitleDoesNotRequireMatchingPaneDirectory() {
        let tree = ProcessTree(
            parsing: "PID PPID TTY COMM\n100 1 ttys001 codex",
            argumentsByPID: [100: ["codex", "resume"]])
        for cwd in ["file:///tmp/current-project/", "/tmp/current-project", ""] {
            for (title, expected) in [
                ("Update guidelines | original-project", Agent.Status.idle),
                ("Update guidelines | long-project-name-for...", .idle),
                ("⠸ Update guidelines | long-project-name-for...", .running),
                ("Working | Update guidelines | original-project", .running),
                ("[ ! ] Action Required | Update guidelines | original-project", .waiting),
                ("original-project", .unknown),
                ("custom title", .unknown),
                ("", .unknown),
                (" | original-project", .unknown),
                ("Update guidelines | ", .unknown),
                ("Update guidelines | original-project | extra", .unknown),
                ("Update guidelines | Ready", .unknown),
                ("Update guidelines | Working", .unknown),
                ("Update guidelines | [ ! ] Action Required", .unknown),
                ("Update guidelines | proj...", .unknown),
            ] {
                let pane = WezTermPane(
                    paneId: 1, tabId: 1, workspace: "default", title: title,
                    cwd: cwd, ttyName: "/dev/ttys001", isActive: false)
                let agents = AgentScanner.agents(panes: [pane], tree: tree, focusedPaneID: nil)
                #expect(agents.count == 1)
                #expect(agents.first?.status == expected)
            }
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

    @Test func threadTitlesProduceOneCompletionNotification() {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        for title in [
            "⠸ Fix build | project", "⠦ Fix build | project", "Fix build | project",
            "Fix build | project",
        ] {
            vm.applyResult(scan(title: title, focusedPaneID: 2))
        }
        #expect(mock.notifiedAgents.count == 1)
        #expect(vm.unreadPaneIDs == [1])
    }

    @Test func threadTitlesDoNotNotifyAfterWaitingOrUnknown() {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        for title in [
            "⠸ Fix build | project", "[ ! ] Action Required | Fix build | project",
            "Fix build | project",
            "⠸ Fix build | project", "custom title", "Fix build | project",
        ] {
            vm.applyResult(scan(title: title, focusedPaneID: 2))
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

    @Test func resumedThreadInAnotherDirectoryNotifiesOnceOnCompletion() {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        for title in [
            "Update guidelines | long-project-name-for...",
            "⠸ Update guidelines | long-project-name-for...",
            "Update guidelines | long-project-name-for...",
            "Update guidelines | long-project-name-for...",
        ] {
            vm.applyResult(scan(title: title, focusedPaneID: 2, arguments: ["codex", "resume"]))
        }
        #expect(mock.notifiedAgents.count == 1)
        #expect(vm.unreadPaneIDs == [1])
    }

    @Test func resumedThreadDoesNotNotifyAfterWaitingOrUnknown() {
        let mock = MockNotificationService()
        let vm = AgentListViewModel(notificationService: mock)
        for title in [
            "⠸ Update guidelines | another-project",
            "[ ! ] Action Required | Update guidelines | another-project",
            "Update guidelines | another-project",
            "⠸ Update guidelines | another-project",
            "Update guidelines | Ready",
            "Update guidelines | another-project",
        ] {
            vm.applyResult(scan(title: title, focusedPaneID: 2, arguments: ["codex", "resume"]))
        }
        #expect(mock.notifiedAgents.isEmpty)
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    private func scan(title: String, focusedPaneID: Int?, arguments: [String] = ["codex"])
        -> [Agent]
    {
        let tree = ProcessTree(
            parsing: "PID PPID TTY COMM\n100 1 ttys001 codex",
            argumentsByPID: [100: arguments])
        let pane = WezTermPane(
            paneId: 1, tabId: 10, workspace: "default", title: title,
            cwd: "file:///tmp/project", ttyName: "/dev/ttys001", isActive: true)
        return AgentScanner.agents(panes: [pane], tree: tree, focusedPaneID: focusedPaneID)
    }
}
