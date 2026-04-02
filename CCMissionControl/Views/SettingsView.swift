import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("wezTermPath") private var wezTermPath = ""
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Notifications") {
                LabeledContent("System Permission") {
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
                LabeledContent("Application Path") {
                    HStack {
                        TextField("Auto-detect", text: $wezTermPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.application]
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                wezTermPath = url.appendingPathComponent("Contents/MacOS/wezterm").path
                            }
                        }
                    }
                }
                if wezTermPath.isEmpty {
                    Text("Using auto-detected WezTerm installation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .task {
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
