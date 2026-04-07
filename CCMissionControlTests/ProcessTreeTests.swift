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
