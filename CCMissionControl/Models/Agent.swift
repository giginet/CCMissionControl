import Foundation

struct Agent: Identifiable, Hashable, Sendable {
    let paneID: Int
    let workspace: String
    let project: String
    let cwd: String
    let title: String
    let status: Status

    var id: Int { paneID }

    enum Status: String, Sendable {
        case running
        case idle
    }
}
