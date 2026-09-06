import Foundation
import Testing

@testable import CCMissionControl

struct AgentDetectorTests {
    @Test func mixedPanesAndHelpers() {
        let tree = ProcessTree(
            parsing: """
                PID PPID TTY COMM
                100 1 ttys001 /bin/zsh
                110 100 ttys001 claude
                111 110 ttys001 caffeinate
                200 1 ttys002 /bin/zsh
                210 200 ttys002 /opt/homebrew/bin/node
                220 210 ttys002 /opt/homebrew/bin/codex
                221 220 ttys002 /opt/homebrew/bin/codex-code-mode-host
                300 1 ?? /Applications/ChatGPT.app/Contents/Resources/codex
                400 1 ttys003 /opt/homebrew/bin/codex
                """,
            argumentsByPID: [
                220: ["codex"], 300: ["codex", "app-server"], 400: ["codex", "mcp-server"],
            ]
        )
        let agents = AgentScanner.agents(
            panes: [pane(1), pane(2), pane(3)], tree: tree, focusedPaneID: 2)
        #expect(agents.count == 2)
        #expect(agents[0].kind == .claudeCode)
        #expect(agents[0].status == .running)
        #expect(agents[1].kind == .codex)
        #expect(agents[1].processID == 220)
        #expect(agents[1].status == .unknown)
        #expect(agents[1].isActive)
    }

    @Test(arguments: [
        ["codex"], ["codex", "resume", "--last"], ["codex", "fork", "abc"],
        ["codex", "-C", "/path with spaces", "fix app-server"],
        ["codex", "--model=gpt-test", "hello"], ["codex", "-mtest"],
        ["codex", "--", "app-server"], ["codex", "-c", "key=exec", "hello"],
        ["codex", "--remote", "unix://"],
    ])
    func interactiveArguments(_ arguments: [String]) {
        #expect(CodexDetector.isInteractive(arguments))
    }

    @Test(arguments: [
        ["codex", "app-server"], ["codex", "mcp-server"], ["codex", "exec", "hello"],
        ["codex", "-C", "/tmp", "review"], ["codex", "--model=test", "exec"],
        ["codex", "--help"], ["codex", "resume", "--help"], ["codex", "--version"],
        ["codex", "--unknown-option", "app-server"], ["codex", "-C"], [],
    ])
    func excludesNonInteractiveArguments(_ arguments: [String]) {
        #expect(!CodexDetector.isInteractive(arguments))
    }

    @Test func unknownArgumentsAndLookalikesAreExcluded() {
        let tree = ProcessTree(parsing: "PID PPID TTY COMM\n")
        for name in ["codex-code-mode-host", "Codex (Service)", "my-codex", "node"] {
            let process = ProcessEntry(
                pid: 1, ppid: 0, tty: "ttys001", command: name, arguments: [name])
            #expect(CodexDetector().detect(process, in: tree) == nil)
        }
        let process = ProcessEntry(pid: 1, ppid: 0, tty: "ttys001", command: "codex")
        #expect(CodexDetector().detect(process, in: tree) == nil)
    }

    @Test func nestedAgentsPreferOuterSessionRegardlessOfProcessOrder() {
        let lines = ["220 110 ttys001 codex", "110 100 ttys001 claude", "100 1 ttys001 zsh"]
        for ordered in [lines, lines.reversed().map { $0 }] {
            let tree = ProcessTree(
                parsing: "PID PPID TTY COMM\n" + ordered.joined(separator: "\n"),
                argumentsByPID: [220: ["codex"]])
            let agents = AgentScanner.agents(panes: [pane(1)], tree: tree, focusedPaneID: nil)
            #expect(agents.count == 1)
            #expect(agents.first?.processID == 110)
        }
    }

    @Test func codexCaffeinateDoesNotImplyRunning() {
        let tree = ProcessTree(
            parsing: "PID PPID TTY COMM\n100 1 ttys001 codex\n200 100 ttys001 caffeinate",
            argumentsByPID: [100: ["codex"]])
        let agents = AgentScanner.agents(panes: [pane(1)], tree: tree, focusedPaneID: nil)
        #expect(agents.first?.status == .unknown)
    }

    private func pane(_ id: Int) -> WezTermPane {
        WezTermPane(
            paneId: id, tabId: id, workspace: "default", title: "Project",
            cwd: "file:///tmp/project",
            ttyName: "/dev/ttys00\(id)", isActive: false)
    }
}

struct ProcessArgumentsTests {
    @Test func parsesExactArgumentsWithoutEnvironment() {
        let arguments = [
            "/path with spaces/codex", "-C", "/project with spaces", "", "fix app-server",
        ]
        var count = Int32(arguments.count)
        var bytes = withUnsafeBytes(of: &count) { Array($0) }
        bytes += Array("/path with spaces/codex".utf8) + [0, 0, 0]
        for argument in arguments { bytes += Array(argument.utf8) + [0] }
        bytes += Array("SECRET=not-an-argument".utf8) + [0]
        #expect(ProcessArguments.parse(bytes) == arguments)
        #expect(ProcessArguments.parse(Array(bytes.prefix(8))) == nil)
        #expect(ProcessArguments.parse([]) == nil)
    }
}
