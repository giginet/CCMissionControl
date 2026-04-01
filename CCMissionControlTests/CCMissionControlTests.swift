import Testing
import Foundation
@testable import CCMissionControl

// MARK: - ProcessTree Parsing

struct ProcessTreeParsingTests {
    /// Test with realistic `ps -eo pid,ppid,tty,comm` output.
    /// Regression test for the bug where double spaces between TTY and COMM caused a leading space in command names.
    static let realisticPSOutput = """
      PID  PPID TTY      COMM
        1     0 ??       /sbin/launchd
      331     1 ??       /usr/libexec/logd
    15096 15095 ttys000  /bin/zsh
    15494 15096 ttys000  claude
    15511 15494 ttys000  npx
    15512 15494 ttys000  bun
    29869 15494 ttys000  caffeinate
    22190 22189 ttys009  /bin/zsh
    22257 22190 ttys009  claude
    """

    @Test func parsesProcessEntries() {
        let tree = ProcessTree(parsing: Self.realisticPSOutput)
        let entries = tree.entries(onTTY: "ttys000")
        #expect(entries.count == 5)
    }

    @Test func skipsHeaderLine() {
        let tree = ProcessTree(parsing: Self.realisticPSOutput)
        // PID=1 (launchd) has TTY "??" so it won't be in entriesByTTY.
        // Verify the header line was skipped by confirming PID 0 is not in claudePIDs.
        #expect(!tree.claudePIDs.contains(0))
    }

    @Test func detectsClaudePIDs() {
        let tree = ProcessTree(parsing: Self.realisticPSOutput)
        #expect(tree.claudePIDs == [15494, 22257])
    }

    @Test func commandNameTrimsLeadingWhitespace() {
        let tree = ProcessTree(parsing: Self.realisticPSOutput)
        let children = tree.children(of: 15494)
        let caffeinate = children.first { $0.pid == 29869 }
        #expect(caffeinate != nil)
        #expect(caffeinate?.command == "caffeinate")
        #expect(caffeinate?.commandName == "caffeinate")
    }

    @Test func excludesQuestionMarkTTYFromTTYIndex() {
        let tree = ProcessTree(parsing: Self.realisticPSOutput)
        #expect(tree.entries(onTTY: "??").isEmpty)
    }

    @Test func handlesEmptyOutput() {
        let tree = ProcessTree(parsing: "  PID  PPID TTY      COMM\n")
        #expect(tree.claudePIDs.isEmpty)
    }

    @Test func handlesFullPathClaudeCommand() {
        let output = """
          PID  PPID TTY      COMM
          100    99 ttys001  /usr/local/bin/claude
        """
        let tree = ProcessTree(parsing: output)
        #expect(tree.claudePIDs == [100])
    }
}

// MARK: - Ancestor Detection

struct AncestorDetectionTests {
    static let psOutput = """
      PID  PPID TTY      COMM
    15095 15094 ttys000  login
    15096 15095 ttys000  /bin/zsh
    15494 15096 ttys000  claude
    15511 15494 ttys000  npx
    15655 15511 ttys000  node
    """

    @Test func findsDirectClaudeProcess() {
        let tree = ProcessTree(parsing: Self.psOutput)
        let result = tree.ancestorClaude(of: 15494, claudePIDs: tree.claudePIDs)
        #expect(result == 15494)
    }

    @Test func findsClaudeAsAncestorOfChild() {
        let tree = ProcessTree(parsing: Self.psOutput)
        let result = tree.ancestorClaude(of: 15511, claudePIDs: tree.claudePIDs)
        #expect(result == 15494)
    }

    @Test func findsClaudeAsAncestorOfGrandchild() {
        let tree = ProcessTree(parsing: Self.psOutput)
        let result = tree.ancestorClaude(of: 15655, claudePIDs: tree.claudePIDs)
        #expect(result == 15494)
    }

    @Test func returnsNilForNonClaudeAncestry() {
        let tree = ProcessTree(parsing: Self.psOutput)
        // zsh (15096) has parent login (15095), not a descendant of claude
        let result = tree.ancestorClaude(of: 15096, claudePIDs: tree.claudePIDs)
        #expect(result == nil)
    }

    @Test func returnsNilForUnknownPID() {
        let tree = ProcessTree(parsing: Self.psOutput)
        let result = tree.ancestorClaude(of: 99999, claudePIDs: tree.claudePIDs)
        #expect(result == nil)
    }

    @Test func handlesCircularParentChain() {
        // Must not infinite-loop when ppid chain forms a cycle
        let output = """
          PID  PPID TTY      COMM
          100   200 ttys000  /bin/zsh
          200   100 ttys000  /bin/zsh
        """
        let tree = ProcessTree(parsing: output)
        let result = tree.ancestorClaude(of: 100, claudePIDs: [])
        #expect(result == nil)
    }
}

// MARK: - Caffeinate (Status) Detection

struct StatusDetectionTests {
    @Test func detectsRunningWhenCaffeinateIsChild() {
        let output = """
          PID  PPID TTY      COMM
          100    99 ttys000  /bin/zsh
          200   100 ttys000  claude
          300   200 ttys000  caffeinate
        """
        let tree = ProcessTree(parsing: output)
        let children = tree.children(of: 200)
        let hasCaffeinate = children.contains { $0.commandName == "caffeinate" }
        #expect(hasCaffeinate)
    }

    @Test func detectsIdleWhenNoCaffeinate() {
        let output = """
          PID  PPID TTY      COMM
          100    99 ttys000  /bin/zsh
          200   100 ttys000  claude
          300   200 ttys000  npx
        """
        let tree = ProcessTree(parsing: output)
        let children = tree.children(of: 200)
        let hasCaffeinate = children.contains { $0.commandName == "caffeinate" }
        #expect(!hasCaffeinate)
    }

    @Test func caffeinateOnDifferentParentDoesNotCount() {
        let output = """
          PID  PPID TTY      COMM
          200   100 ttys000  claude
          300   100 ttys000  caffeinate
        """
        let tree = ProcessTree(parsing: output)
        // caffeinate (300) has parent 100, not a child of claude (200)
        let children = tree.children(of: 200)
        let hasCaffeinate = children.contains { $0.commandName == "caffeinate" }
        #expect(!hasCaffeinate)
    }
}

// MARK: - WezTermPane JSON Decoding

struct WezTermPaneDecodingTests {
    @Test func decodesRealWezTermJSON() throws {
        let json = """
        [
          {
            "window_id": 0,
            "tab_id": 0,
            "pane_id": 0,
            "workspace": "default",
            "size": { "rows": 54, "cols": 106, "pixel_width": 2014, "pixel_height": 2052, "dpi": 144 },
            "title": "⠂ cc-mission-control-impl",
            "cwd": "file:///Users/giginet/work/Swift/CCMissionControl",
            "cursor_x": 2,
            "cursor_y": 47,
            "cursor_shape": "Default",
            "cursor_visibility": "Hidden",
            "left_col": 0,
            "top_row": 0,
            "tab_title": "",
            "window_title": "⠂ cc-mission-control-impl",
            "is_active": true,
            "is_zoomed": false,
            "tty_name": "/dev/ttys000"
          }
        ]
        """
        let panes = try JSONDecoder().decode([WezTermPane].self, from: Data(json.utf8))
        #expect(panes.count == 1)
        #expect(panes[0].paneId == 0)
        #expect(panes[0].workspace == "default")
        #expect(panes[0].title == "⠂ cc-mission-control-impl")
        #expect(panes[0].cwd == "file:///Users/giginet/work/Swift/CCMissionControl")
        #expect(panes[0].ttyName == "/dev/ttys000")
    }

    @Test func decodesMultiplePanes() throws {
        let json = """
        [
          { "pane_id": 0, "tab_id": 0, "workspace": "default", "title": "zsh", "cwd": "file:///tmp", "tty_name": "/dev/ttys000", "is_active": true },
          { "pane_id": 1, "tab_id": 1, "workspace": "work", "title": "vim", "cwd": "file:///home", "tty_name": "/dev/ttys001", "is_active": false }
        ]
        """
        let panes = try JSONDecoder().decode([WezTermPane].self, from: Data(json.utf8))
        #expect(panes.count == 2)
        #expect(panes[1].workspace == "work")
    }
}

// MARK: - ProcessEntry

struct ProcessEntryTests {
    @Test func commandNameReturnsLastPathComponent() {
        let entry = ProcessEntry(pid: 1, ppid: 0, tty: "ttys000", command: "/usr/local/bin/claude")
        #expect(entry.commandName == "claude")
    }

    @Test func commandNameForBareCommand() {
        let entry = ProcessEntry(pid: 1, ppid: 0, tty: "ttys000", command: "caffeinate")
        #expect(entry.commandName == "caffeinate")
    }

    @Test func commandNameForDeepPath() {
        let entry = ProcessEntry(pid: 1, ppid: 0, tty: "??", command: "/Applications/Xcode.app/Contents/Developer/usr/bin/sourcekit-lsp")
        #expect(entry.commandName == "sourcekit-lsp")
    }
}

// MARK: - AgentListViewModel Unread Badge Logic
//
// isActive is determined by matching focused_pane_id from list-clients.
// Only the pane the user is actually viewing is true.

@MainActor
struct UnreadBadgeTests {
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
        let vm = AgentListViewModel()

        // User keeps focus on this pane during running→idle
        vm.applyResult([makeAgent(status: .running, isActive: true)])
        vm.applyResult([makeAgent(status: .idle, isActive: true)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - Badge for unfocused pane

    @Test func unreadWhenUnfocusedPane_RunningToIdle() {
        let vm = AgentListViewModel()

        // Claude Code running in another tab (unfocused) transitions to idle
        vm.applyResult([makeAgent(status: .running, isActive: false)])
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))
    }

    // MARK: - Mark as read on click

    @Test func markAsReadClearsBadge() {
        let vm = AgentListViewModel()

        vm.applyResult([makeAgent(status: .running, isActive: false)])
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))

        vm.markAsRead(makeAgent(status: .idle, isActive: false))
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - No badge for idle→idle

    @Test func noUnreadWhenIdleToIdle() {
        let vm = AgentListViewModel()

        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - No badge on first scan

    @Test func noUnreadOnFirstScan() {
        let vm = AgentListViewModel()

        // previousStatus is nil → not a running→idle transition, so no unread
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - Multiple sessions are independent

    @Test func multipleSessionsIndependent() {
        let vm = AgentListViewModel()

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
        let vm = AgentListViewModel()

        // Focused while running
        vm.applyResult([makeAgent(status: .running, isActive: true)])

        // Focus moved to another pane when transitioning to idle → show badge
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))
    }

    @Test func unfocusedWhileRunning_FocusedWhenIdle_NoBadge() {
        let vm = AgentListViewModel()

        // Unfocused while running
        vm.applyResult([makeAgent(status: .running, isActive: false)])

        // User returned focus just as it went idle → no badge
        vm.applyResult([makeAgent(status: .idle, isActive: true)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    // MARK: - Unread cleared when focus returns

    @Test func unreadClearedByFocusReturn() {
        let vm = AgentListViewModel()

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
        let vm = AgentListViewModel()

        vm.applyResult([makeAgent(status: .running, isActive: false)])
        vm.applyResult([makeAgent(status: .running, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }
}
