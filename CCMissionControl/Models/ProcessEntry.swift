import Foundation

struct ProcessEntry: Sendable {
    let pid: Int
    let ppid: Int
    let tty: String
    let command: String
    var arguments: [String]? = nil

    nonisolated var commandName: String {
        (command as NSString).lastPathComponent
    }
}
