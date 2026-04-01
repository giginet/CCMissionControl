import Foundation

struct WezTermPane: Decodable, Sendable {
    let paneId: Int
    let workspace: String
    let title: String
    let cwd: String
    let ttyName: String

    enum CodingKeys: String, CodingKey {
        case paneId = "pane_id"
        case workspace
        case title
        case cwd
        case ttyName = "tty_name"
    }
}
