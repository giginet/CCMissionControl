import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

private let defaultWezTermPath = "/Applications/WezTerm.app/Contents/MacOS/wezterm"

struct SettingsView: View {
    @AppStorage("windowMode") private var windowMode = "dropdown"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("wezTermPath") private var wezTermPath = defaultWezTermPath
    @State private var authorizationStatus: UNAuthorizationStatus
    private let skipNotificationCheck: Bool

    init(previewAuthorizationStatus: UNAuthorizationStatus? = nil) {
        if let status = previewAuthorizationStatus {
            _authorizationStatus = State(initialValue: status)
            skipNotificationCheck = true
        } else {
            _authorizationStatus = State(initialValue: .notDetermined)
            skipNotificationCheck = false
        }
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Window Mode", selection: $windowMode) {
                    Text("Dropdown").tag("dropdown")
                    Text("Floating").tag("floating")
                }
                .pickerStyle(.segmented)
            }

            Section("Notifications") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Permission")
                        .font(.body)
                    HStack(spacing: 4) {
                        Image(systemName: permissionIcon)
                            .foregroundStyle(permissionColor)
                        Text(permissionText)
                        if authorizationStatus == .denied {
                            Button("Open Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                if !notificationsEnabled {
                    Text("Notifications are disabled in app settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("WezTerm") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WezTerm CLI Path")
                        .font(.body)
                    HStack(spacing: 8) {
                        TextField("", text: $wezTermPath)
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.application]
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                wezTermPath = url.appendingPathComponent("Contents/MacOS/wezterm").path
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .task {
            guard !skipNotificationCheck else { return }
            authorizationStatus = await SystemNotificationService.shared.getAuthorizationStatus()
        }
    }

    private var permissionIcon: String {
        switch authorizationStatus {
        case .authorized: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        default: "questionmark.circle"
        }
    }

    private var permissionColor: Color {
        switch authorizationStatus {
        case .authorized: .green
        case .denied: .red
        default: .secondary
        }
    }

    private var permissionText: String {
        switch authorizationStatus {
        case .authorized: "Authorized"
        case .denied: "Denied"
        case .provisional: "Provisional"
        default: "Not Determined"
        }
    }
}

#Preview {
    SettingsView(previewAuthorizationStatus: .authorized)
}
