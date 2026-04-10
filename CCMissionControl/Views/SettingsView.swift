import Milepost
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

private let defaultWezTermPath = "/Applications/WezTerm.app/Contents/MacOS/wezterm"

struct SettingsView: View {
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("windowMode") private var windowMode = "dropdown"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notifyForeground") private var notifyForeground = false
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
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                Toggle("Show in Dock", isOn: $showInDock)
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
                                if let url = URL(
                                    string:
                                        "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                                ) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                if notificationsEnabled {
                    Toggle("Notify for Active Pane", isOn: $notifyForeground)
                    if notifyForeground {
                        Text("Notifications will be sent even when you are viewing the pane.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                                wezTermPath =
                                    url.appendingPathComponent("Contents/MacOS/wezterm").path
                            }
                        }
                        .fixedSize()
                    }
                }
            }

            Section {
                aboutSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .task {
            guard !skipNotificationCheck else { return }
            authorizationStatus = await SystemNotificationService.shared
                .getAuthorizationStatus()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Registration may fail silently
                }
            }
        )
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

    private var aboutSection: some View {
        VStack(spacing: 12) {
            Image(.icon)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("CCMissionControl")
                .font(.headline)

            let version =
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            if let revision = RevisionLoader.load() {
                Text("v\(version) (\(revision.shortHash))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("v\(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Link(
                "giginet/CCMissionControl",
                destination: URL(string: "https://github.com/giginet/CCMissionControl")!
            )
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

#Preview {
    SettingsView(previewAuthorizationStatus: .authorized)
}
