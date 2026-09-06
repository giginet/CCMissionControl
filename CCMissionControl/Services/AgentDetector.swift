import Foundation

nonisolated struct AgentDetection: Sendable {
    let pid: Int
    let kind: AgentKind
    let status: Agent.Status
}

nonisolated protocol AgentDetector: Sendable {
    func requiresArguments(for process: ProcessEntry) -> Bool
    func status(for detection: AgentDetection, pane: WezTermPane) -> Agent.Status
    func detect(_ process: ProcessEntry, in tree: ProcessTree) -> AgentDetection?
}

extension AgentDetector {
    nonisolated func requiresArguments(for process: ProcessEntry) -> Bool { false }

    nonisolated func status(for detection: AgentDetection, pane: WezTermPane) -> Agent.Status {
        detection.status
    }
}

nonisolated struct ClaudeCodeDetector: AgentDetector {
    func detect(_ process: ProcessEntry, in tree: ProcessTree) -> AgentDetection? {
        // Preserve the existing Claude Code process-name matching behavior.
        guard process.commandName.localizedCaseInsensitiveContains("claude") else { return nil }
        let running = tree.children(of: process.pid).contains { $0.commandName == "caffeinate" }
        return AgentDetection(
            pid: process.pid, kind: .claudeCode, status: running ? .running : .idle)
    }
}

nonisolated struct CodexDetector: AgentDetector {
    func requiresArguments(for process: ProcessEntry) -> Bool {
        process.commandName == "codex"
    }

    func detect(_ process: ProcessEntry, in tree: ProcessTree) -> AgentDetection? {
        // npm installs launch a native codex child; count that child, not the Node wrapper.
        guard process.commandName == "codex",
            let arguments = process.arguments, Self.isInteractive(arguments)
        else { return nil }
        // Neither helper processes nor the absence of caffeinate indicates Codex turn state.
        return AgentDetection(pid: process.pid, kind: .codex, status: .unknown)
    }

    func status(for detection: AgentDetection, pane: WezTermPane) -> Agent.Status {
        let status = Self.status(fromTitle: pane.title)
        guard status == .unknown else { return status }
        // The default ["spinner", "project"] title drops the spinner while idle.
        // Limit this fallback to a confirmed Codex pane with a matching project title;
        // arbitrary titles (including shell titles) must not imply completion.
        let cwd = pane.cwd.hasPrefix("file://") ? URL(string: pane.cwd)?.path : pane.cwd
        guard let cwd, !cwd.isEmpty else { return .unknown }
        let project = (cwd as NSString).lastPathComponent
        let title = pane.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !project.isEmpty && title == project ? .idle : .unknown
    }

    static func status(fromTitle title: String) -> Agent.Status {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only interpret the leading activity item; a project or thread name may contain
        // words such as "Ready" or "Working". Unknown/custom titles stay unknown.
        for marker in ["[ ! ] Action Required", "[ . ] Action Required"] {
            if title == marker || title.hasPrefix(marker + " | ") { return .waiting }
        }
        let spinnerFrames: Set<Character> = Set("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
        if let first = title.first, spinnerFrames.contains(first),
            title.count == 1 || title.dropFirst().first?.isWhitespace == true
        {
            return .running
        }
        let activity = title.components(separatedBy: " | ").first ?? ""
        switch activity {
        case "Ready": return .idle
        case "Working", "Thinking": return .running
        default: return .unknown
        }
    }

    static func isInteractive(_ arguments: [String]) -> Bool {
        guard !arguments.isEmpty else { return false }
        let valueOptions: Set<String> = [
            "-c", "--config", "--enable", "--disable", "--remote", "--remote-auth-token-env",
            "-i", "--image", "-m", "--model", "--local-provider", "-p", "--profile",
            "-s", "--sandbox", "-C", "--cd", "--add-dir", "-a", "--ask-for-approval",
        ]
        let flagOptions: Set<String> = [
            "--strict-config", "--oss", "--approve-for-me", "--full-auto",
            "--dangerously-bypass-approvals-and-sandbox", "--dangerously-bypass-hook-trust",
            "--search", "--no-alt-screen",
        ]
        let nonInteractiveCommands: Set<String> = [
            "exec", "e", "review", "login", "logout", "mcp", "plugin", "mcp-server",
            "app-server", "remote-control", "app", "completion", "update", "doctor",
            "sandbox", "debug", "apply", "a", "queue", "archive", "delete",
            "migrate-rollouts", "unarchive", "cloud", "exec-server", "features", "help",
        ]
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { return true }  // Remaining arguments are the prompt.
            if ["-h", "--help", "-V", "--version"].contains(argument) { return false }
            if valueOptions.contains(argument) {
                guard index + 1 < arguments.count else { return false }
                index += 2
                continue
            }
            if flagOptions.contains(argument) {
                index += 1
                continue
            }
            if argument.hasPrefix("--"), let equal = argument.firstIndex(of: "="),
                valueOptions.contains(String(argument[..<equal]))
            {
                index += 1
                continue
            }
            if argument.hasPrefix("-"), !argument.hasPrefix("--"), argument.count > 2,
                valueOptions.contains(String(argument.prefix(2)))
            {
                index += 1
                continue
            }
            // Unknown options are conservatively excluded until their arity is known.
            if argument.hasPrefix("-") { return false }
            if nonInteractiveCommands.contains(argument) { return false }
            if ["resume", "fork", "agents"].contains(argument) {
                return !arguments.dropFirst(index + 1).contains(where: {
                    ["-h", "--help", "-V", "--version"].contains($0)
                })
            }
            return true  // A positional prompt, including spaces, is one argv element.
        }
        return true
    }
}
