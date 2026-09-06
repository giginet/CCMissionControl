import Foundation

struct Agent: Identifiable, Hashable, Sendable {
    let paneID: Int
    let tabID: Int
    let workspace: String
    let project: String
    let cwd: String
    let title: String
    let status: Status
    var isActive: Bool
    var kind: AgentKind = .claudeCode
    var processID: Int? = nil

    var sessionIdentity: SessionIdentity {
        SessionIdentity(paneID: paneID, kind: kind, processID: processID)
    }

    struct SessionIdentity: Hashable {
        let paneID: Int
        let kind: AgentKind
        let processID: Int?
    }

    var id: Int { paneID }

    enum Status: String, Sendable {
        case running
        case idle
        case waiting
        case unknown

        nonisolated var sortOrder: Int {
            switch self {
            case .running: 0
            case .waiting: 1
            case .idle: 2
            case .unknown: 3
            }
        }
    }
}

nonisolated enum AgentKind: String, Sendable {
    case claudeCode
    case codex

    var displayName: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        }
    }

}
