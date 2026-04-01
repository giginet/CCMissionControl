import Foundation

struct WezTermPane: Decodable, Sendable {
    let paneId: Int
    let tabId: Int
    let workspace: String
    let title: String
    let cwd: String
    let ttyName: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case tabId = "tab_id"
        case workspace
        case title
        case cwd
        case ttyName = "tty_name"
        case isActive = "is_active"
    }
}

struct WezTermClient: Decodable, Sendable {
    let focusedPaneId: Int

    enum CodingKeys: String, CodingKey {
        case focusedPaneId = "focused_pane_id"
    }
}
