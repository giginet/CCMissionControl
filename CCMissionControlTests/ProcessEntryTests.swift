import Testing
import Foundation
@testable import CCMissionControl

struct ProcessEntryModelTests {
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
