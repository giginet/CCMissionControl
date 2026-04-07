import AppKit
import Foundation

enum ScanError: LocalizedError {
    case wezTermNotFound
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .wezTermNotFound:
            "WezTerm CLI not found. Make sure WezTerm is installed."
        case .parseFailed(let detail):
            "Failed to parse data: \(detail)"
        }
    }
}

enum AgentScanner {
    nonisolated static func scan() async throws -> [Agent] {
        async let panesResult = fetchPanes()
        async let processResult = fetchProcessTree()
        async let focusedResult = fetchFocusedPaneID()

        let panes = try await panesResult
        let tree = try await processResult
        let focusedPaneID = try await focusedResult

        let claudePIDs = tree.claudePIDs
        var claudeStatus: [Int: Agent.Status] = [:]
        for cpid in claudePIDs {
            let children = tree.children(of: cpid)
            let hasCaffeinate = children.contains { $0.commandName == "caffeinate" }
            claudeStatus[cpid] = hasCaffeinate ? .running : .idle
        }

        var seen = Set<Int>()
        var agents: [Agent] = []

        for pane in panes {
            let tty = normalizeTTY(pane.ttyName)
            let entriesOnTTY = tree.entries(onTTY: tty)

            var foundClaudePID: Int?
            for entry in entriesOnTTY {
                if let cpid = tree.ancestorClaude(of: entry.pid, claudePIDs: claudePIDs) {
                    foundClaudePID = cpid
                    break
                }
            }

            guard let cpid = foundClaudePID, !seen.contains(cpid) else { continue }
            seen.insert(cpid)

            let cwdPath = parseCWD(pane.cwd)
            let project = (cwdPath as NSString).lastPathComponent
            let displayCWD = cwdPath.replacingOccurrences(
                of: NSHomeDirectory(),
                with: "~"
            )
            let cleanTitle = cleanUpTitle(pane.title)

            agents.append(Agent(
                paneID: pane.paneId,
                tabID: pane.tabId,
                workspace: pane.workspace,
                project: project,
                cwd: displayCWD,
                title: cleanTitle,
                status: claudeStatus[cpid] ?? .idle,
                isActive: pane.paneId == focusedPaneID
            ))
        }

        agents.sort { a, b in
            if a.status != b.status {
                return a.status == .running
            }
            return a.workspace < b.workspace
        }

        return agents
    }

    nonisolated static func activateTab(for agent: Agent) async {
        guard let wezterm = findWezTerm() else { return }
        _ = try? await ShellExecutor.run(
            executablePath: wezterm,
            arguments: ["cli", "activate-tab", "--tab-id", String(agent.tabID)]
        )
        await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.wez.wezterm")
                .first?.activate()
        }
    }

    // MARK: - Private

    private static let wezTermPaths = [
        "/Applications/WezTerm.app/Contents/MacOS/wezterm",
        "/opt/homebrew/bin/wezterm",
        "/usr/local/bin/wezterm",
    ]

    private nonisolated static func findWezTerm() -> String? {
        let customPath = UserDefaults.standard.string(forKey: "wezTermPath") ?? ""
        if !customPath.isEmpty && FileManager.default.isExecutableFile(atPath: customPath) {
            return customPath
        }
        return wezTermPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func fetchPanes() async throws -> [WezTermPane] {
        guard let wezterm = findWezTerm() else {
            throw ScanError.wezTermNotFound
        }
        do {
            let output = try await ShellExecutor.run(
                executablePath: wezterm,
                arguments: ["cli", "list", "--format", "json"]
            )
            let data = Data(output.utf8)
            return try JSONDecoder().decode([WezTermPane].self, from: data)
        } catch is ShellExecutor.ShellError {
            throw ScanError.wezTermNotFound
        }
    }

    private nonisolated static func fetchFocusedPaneID() async throws -> Int? {
        guard let wezterm = findWezTerm() else { return nil }
        do {
            let output = try await ShellExecutor.run(
                executablePath: wezterm,
                arguments: ["cli", "list-clients", "--format", "json"]
            )
            let data = Data(output.utf8)
            let clients = try JSONDecoder().decode([WezTermClient].self, from: data)
            return clients.first?.focusedPaneId
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchProcessTree() async throws -> ProcessTree {
        let output = try await ShellExecutor.run(
            executablePath: "/bin/ps",
            arguments: ["-eo", "pid,ppid,tty,comm"]
        )
        return ProcessTree(parsing: output)
    }

    private nonisolated static func normalizeTTY(_ tty: String) -> String {
        if tty.hasPrefix("/dev/") {
            return String(tty.dropFirst(5))
        }
        return tty
    }

    private nonisolated static func parseCWD(_ cwd: String) -> String {
        if cwd.hasPrefix("file://"),
           let url = URL(string: cwd) {
            return url.path
        }
        return cwd
    }

    private nonisolated static func cleanUpTitle(_ title: String) -> String {
        var result = title
        // Strip leading braille/spinner characters and whitespace
        while let first = result.unicodeScalars.first,
              !first.properties.isAlphabetic && !first.properties.isASCIIHexDigit && first != " " {
            result = String(result.unicodeScalars.dropFirst())
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

nonisolated struct ProcessTree: Sendable {
    private let entriesByPID: [Int: ProcessEntry]
    private let childrenByPPID: [Int: [ProcessEntry]]
    private let entriesByTTY: [String: [ProcessEntry]]
    let claudePIDs: Set<Int>

    init(parsing output: String) {
        var byPID: [Int: ProcessEntry] = [:]
        var byPPID: [Int: [ProcessEntry]] = [:]
        var byTTY: [String: [ProcessEntry]] = [:]
        var claudes: Set<Int> = []

        let lines = output.components(separatedBy: "\n").dropFirst() // skip header
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                .map(String.init)
            guard parts.count >= 4,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]) else { continue }

            let entry = ProcessEntry(
                pid: pid,
                ppid: ppid,
                tty: parts[2],
                command: parts[3].trimmingCharacters(in: .whitespaces)
            )

            byPID[pid] = entry
            byPPID[ppid, default: []].append(entry)
            if entry.tty != "??" {
                byTTY[entry.tty, default: []].append(entry)
            }

            if entry.commandName.localizedCaseInsensitiveContains("claude") {
                claudes.insert(pid)
            }
        }

        self.entriesByPID = byPID
        self.childrenByPPID = byPPID
        self.entriesByTTY = byTTY
        self.claudePIDs = claudes
    }

    func children(of pid: Int) -> [ProcessEntry] {
        childrenByPPID[pid] ?? []
    }

    func entries(onTTY tty: String) -> [ProcessEntry] {
        entriesByTTY[tty] ?? []
    }

    func ancestorClaude(of pid: Int, claudePIDs: Set<Int>) -> Int? {
        var current = pid
        var visited = Set<Int>()
        while let entry = entriesByPID[current] {
            if claudePIDs.contains(current) {
                return current
            }
            if visited.contains(current) { break }
            visited.insert(current)
            current = entry.ppid
        }
        return nil
    }
}
