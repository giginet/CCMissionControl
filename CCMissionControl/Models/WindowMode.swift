import Foundation

enum WindowMode: String, CaseIterable {
    case dropdown
    case floating
    case followWezTerm

    static var current: WindowMode {
        WindowMode(rawValue: UserDefaults.standard.string(forKey: "windowMode") ?? "dropdown")
            ?? .dropdown
    }
}

/// Width of the panel in `WindowMode.followWezTerm`. Persisted in UserDefaults.
enum FollowPanelWidth {
    static let key = "followPanelWidth"
    static let defaultValue: CGFloat = 360
    static let range: ClosedRange<CGFloat> = 320...1000

    static var current: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: key)
            return stored > 0 ? clamped(stored) : defaultValue
        }
        set {
            UserDefaults.standard.set(Double(clamped(newValue)), forKey: key)
        }
    }

    nonisolated static func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, range.lowerBound), range.upperBound)
    }
}
