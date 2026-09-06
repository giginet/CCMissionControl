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
    private nonisolated static let detectors: [any AgentDetector] = [
        ClaudeCodeDetector(), CodexDetector(),
    ]

    nonisolated static func scan() async throws -> [Agent] {
        async let panesResult = fetchPanes()
        async let processResult = fetchProcessTree(detectors: detectors)
        async let focusedResult = fetchFocusedPaneID()

        let panes = try await panesResult
        let tree = try await processResult
        let focusedPaneID = try await focusedResult

        return agents(panes: panes, tree: tree, focusedPaneID: focusedPaneID, detectors: detectors)
    }

    nonisolated static func agents(
        panes: [WezTermPane], tree: ProcessTree, focusedPaneID: Int?,
        detectors: [any AgentDetector] = AgentScanner.detectors
    ) -> [Agent] {
        let detected = tree.entries.compactMap {
            entry -> (detection: AgentDetection, detector: any AgentDetector)? in
            for detector in detectors {
                if let detection = detector.detect(entry, in: tree) {
                    return (detection, detector)
                }
            }
            return nil
        }
        let byPID = Dictionary(uniqueKeysWithValues: detected.map { ($0.detection.pid, $0) })
        let agentPIDs = Set(byPID.keys)
        var seen = Set<Int>()
        var agents: [Agent] = []

        for pane in panes {
            let tty = normalizeTTY(pane.ttyName)
            let candidates = Set(
                tree.entries(onTTY: tty).compactMap {
                    tree.ancestor(of: $0.pid, matching: agentPIDs)
                })
            // Keep one row per pane. Prefer the outer session over nested tool invocations,
            // with PID order as a stable tie-breaker for unrelated background sessions.
            let roots = candidates.filter { pid in
                guard let entry = tree.entry(for: pid) else { return false }
                return tree.ancestor(of: entry.ppid, matching: candidates) == nil
            }
            guard let pid = roots.min(), let match = byPID[pid],
                seen.insert(pid).inserted
            else { continue }

            let detection = match.detection
            let status = match.detector.status(for: detection, pane: pane)
            let cwdPath = parseCWD(pane.cwd)
            let project = (cwdPath as NSString).lastPathComponent
            let displayCWD = cwdPath.replacingOccurrences(
                of: NSHomeDirectory(),
                with: "~"
            )
            let cleanTitle =
                detection.kind == .codex
                ? pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
                : cleanUpTitle(pane.title)

            agents.append(
                Agent(
                    paneID: pane.paneId,
                    tabID: pane.tabId,
                    workspace: pane.workspace,
                    project: project,
                    cwd: displayCWD,
                    title: cleanTitle,
                    status: status,
                    isActive: pane.paneId == focusedPaneID,
                    kind: detection.kind,
                    processID: pid
                ))
        }

        agents.sort { a, b in
            if a.status.sortOrder != b.status.sortOrder {
                return a.status.sortOrder < b.status.sortOrder
            }
            if a.workspace != b.workspace { return a.workspace < b.workspace }
            return a.paneID < b.paneID
        }

        return agents
    }

    nonisolated static func activateTab(for agent: Agent) async {
        guard let wezterm = findWezTerm() else { return }
        _ = try? await ShellExecutor.run(
            executablePath: wezterm,
            arguments: ["cli", "activate-tab", "--tab-id", String(agent.tabID)]
        )
        _ = try? await ShellExecutor.run(
            executablePath: wezterm,
            arguments: ["cli", "activate-pane", "--pane-id", String(agent.paneID)]
        )
        _ = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.github.wez.wezterm")
                .first?.activate()
        }
    }

    // MARK: - Private

    private nonisolated static let wezTermPaths = [
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

    private nonisolated static func fetchProcessTree(
        detectors: [any AgentDetector]
    ) async throws -> ProcessTree {
        let output = try await ShellExecutor.run(
            executablePath: "/bin/ps",
            arguments: ["-eo", "pid,ppid,tty,comm"]
        )
        let snapshot = ProcessTree(parsing: output)
        var argumentsByPID: [Int: [String]] = [:]
        for entry in snapshot.entries
        where detectors.contains(where: { $0.requiresArguments(for: entry) }) {
            argumentsByPID[entry.pid] = ProcessArguments.read(pid: entry.pid)
        }
        return ProcessTree(parsing: output, argumentsByPID: argumentsByPID)
    }

    private nonisolated static func normalizeTTY(_ tty: String) -> String {
        if tty.hasPrefix("/dev/") {
            return String(tty.dropFirst(5))
        }
        return tty
    }

    private nonisolated static func parseCWD(_ cwd: String) -> String {
        if cwd.hasPrefix("file://"),
            let url = URL(string: cwd)
        {
            return url.path
        }
        return cwd
    }

    private nonisolated static func cleanUpTitle(_ title: String) -> String {
        var result = title
        // Strip leading braille/spinner characters and whitespace
        while let first = result.unicodeScalars.first,
            !first.properties.isAlphabetic && !first.properties.isASCIIHexDigit && first != " "
        {
            result = String(result.unicodeScalars.dropFirst())
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
