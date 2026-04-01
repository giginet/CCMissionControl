import Testing
import Foundation
@testable import CCMissionControl

// MARK: - ProcessTree Parsing

struct ProcessTreeParsingTests {
    /// 実際の `ps -eo pid,ppid,tty,comm` 出力を再現したテスト。
    /// TTYとCOMM間のダブルスペースでコマンド名に先頭スペースが混入するバグの再発防止。
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
        // PID=1 (launchd) はTTY "??" なので entriesByTTY には入らないが、
        // claudePIDs にも入らないことでヘッダー行がスキップされたことを間接確認
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
        // zsh (15096) の親は login (15095)。claude の祖先ではない
        let result = tree.ancestorClaude(of: 15096, claudePIDs: tree.claudePIDs)
        #expect(result == nil)
    }

    @Test func returnsNilForUnknownPID() {
        let tree = ProcessTree(parsing: Self.psOutput)
        let result = tree.ancestorClaude(of: 99999, claudePIDs: tree.claudePIDs)
        #expect(result == nil)
    }

    @Test func handlesCircularParentChain() {
        // ppid がループするような異常ケースでも無限ループしない
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
        // caffeinate (300) の親は 100 であり、claude (200) の子ではない
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

    @Test func noUnreadWhenActivePane_RunningToIdle() {
        let vm = AgentListViewModel()

        // running かつ active
        vm.applyResult([makeAgent(status: .running, isActive: true)])
        #expect(vm.unreadPaneIDs.isEmpty)

        // idle に遷移、まだ active → ベルマーク表示しない
        vm.applyResult([makeAgent(status: .idle, isActive: true)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    @Test func unreadWhenInactivePane_RunningToIdle() {
        let vm = AgentListViewModel()

        // running かつ inactive（別タブを見ている）
        vm.applyResult([makeAgent(status: .running, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)

        // idle に遷移、まだ inactive → ベルマーク表示する
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))
    }

    @Test func markAsReadClearsBadge() {
        let vm = AgentListViewModel()

        // inactive で running→idle → 未読
        vm.applyResult([makeAgent(status: .running, isActive: false)])
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))

        // クリックで既読化
        vm.markAsRead(makeAgent(status: .idle, isActive: false))
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    @Test func noUnreadWhenIdleToIdle() {
        let vm = AgentListViewModel()

        // 最初から idle
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)

        // idle のまま → ベルマーク表示しない
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    @Test func noUnreadOnFirstScan() {
        let vm = AgentListViewModel()

        // 初回スキャンで idle → previousStatus が nil なので未読にならない
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }

    @Test func multipleSessionsIndependent() {
        let vm = AgentListViewModel()

        // 2セッション、両方 running
        vm.applyResult([
            makeAgent(paneID: 0, status: .running, isActive: true),
            makeAgent(paneID: 1, status: .running, isActive: false),
        ])
        #expect(vm.unreadPaneIDs.isEmpty)

        // pane 0: active のまま idle → 未読にならない
        // pane 1: inactive のまま idle → 未読になる
        vm.applyResult([
            makeAgent(paneID: 0, status: .idle, isActive: true),
            makeAgent(paneID: 1, status: .idle, isActive: false),
        ])
        #expect(!vm.unreadPaneIDs.contains(0))
        #expect(vm.unreadPaneIDs.contains(1))
    }

    @Test func activeWhileRunning_InactiveWhenIdle_ShowsBadge() {
        let vm = AgentListViewModel()

        // running 中は active（ユーザーが見ている）
        vm.applyResult([makeAgent(status: .running, isActive: true)])

        // idle 遷移時に inactive（ユーザーが別タブに移動した）→ ベルマーク表示
        vm.applyResult([makeAgent(status: .idle, isActive: false)])
        #expect(vm.unreadPaneIDs.contains(0))
    }

    @Test func inactiveWhileRunning_ActiveWhenIdle_NoBadge() {
        let vm = AgentListViewModel()

        // running 中は inactive
        vm.applyResult([makeAgent(status: .running, isActive: false)])

        // idle 遷移時に active（ユーザーがちょうど戻ってきた）→ ベルマーク表示しない
        vm.applyResult([makeAgent(status: .idle, isActive: true)])
        #expect(vm.unreadPaneIDs.isEmpty)
    }
}
