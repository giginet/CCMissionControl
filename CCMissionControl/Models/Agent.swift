import Foundation

struct Agent: Identifiable, Hashable, Sendable {
    let paneID: Int
    let tabID: Int
    let workspace: String
    let project: String
    let cwd: String
    let title: String
    let status: Status
    let isActive: Bool

    var id: Int { paneID }

    enum Status: String, Sendable {
        case running
        case idle
    }
}
