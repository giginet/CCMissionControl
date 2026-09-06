import Foundation

nonisolated struct ProcessTree: Sendable {
    private let entriesByPID: [Int: ProcessEntry]
    private let childrenByPPID: [Int: [ProcessEntry]]
    private let entriesByTTY: [String: [ProcessEntry]]
    var entries: [ProcessEntry] { Array(entriesByPID.values) }

    func entry(for pid: Int) -> ProcessEntry? { entriesByPID[pid] }

    init(parsing output: String, argumentsByPID: [Int: [String]] = [:]) {
        var byPID: [Int: ProcessEntry] = [:]
        var byPPID: [Int: [ProcessEntry]] = [:]
        var byTTY: [String: [ProcessEntry]] = [:]

        let lines = output.components(separatedBy: "\n").dropFirst()  // skip header
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                .map(String.init)
            guard parts.count >= 4,
                let pid = Int(parts[0]),
                let ppid = Int(parts[1])
            else { continue }

            let entry = ProcessEntry(
                pid: pid,
                ppid: ppid,
                tty: parts[2],
                command: parts[3].trimmingCharacters(in: .whitespaces),
                arguments: argumentsByPID[pid]
            )

            byPID[pid] = entry
            byPPID[ppid, default: []].append(entry)
            if entry.tty != "??" {
                byTTY[entry.tty, default: []].append(entry)
            }
        }

        self.entriesByPID = byPID
        self.childrenByPPID = byPPID
        self.entriesByTTY = byTTY
    }

    func children(of pid: Int) -> [ProcessEntry] {
        childrenByPPID[pid] ?? []
    }

    func entries(onTTY tty: String) -> [ProcessEntry] {
        entriesByTTY[tty] ?? []
    }

    func ancestor(of pid: Int, matching pids: Set<Int>) -> Int? {
        var current = pid
        var visited = Set<Int>()
        while let entry = entriesByPID[current] {
            if pids.contains(current) {
                return current
            }
            if visited.contains(current) { break }
            visited.insert(current)
            current = entry.ppid
        }
        return nil
    }
}
