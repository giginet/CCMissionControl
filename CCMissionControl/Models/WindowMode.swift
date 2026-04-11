import Foundation

enum WindowMode: String, CaseIterable {
    case dropdown
    case floating

    static var current: WindowMode {
        WindowMode(rawValue: UserDefaults.standard.string(forKey: "windowMode") ?? "dropdown")
            ?? .dropdown
    }
}
