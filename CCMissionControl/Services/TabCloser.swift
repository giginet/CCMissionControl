import Foundation

nonisolated struct TabClosePlan: Sendable {
    let agent: Agent
    let panes: [WezTermPane]
    let sessions: [Agent]

    var requiresConfirmation: Bool { panes.count > 1 || sessions.count > 1 }

    var paneIDs: Set<Int> { Set(panes.map(\.paneId)) }
}

nonisolated enum TabCloseError: LocalizedError {
    case sessionChanged
    case tabChanged

    var errorDescription: String? {
        switch self {
        case .sessionChanged:
            String(localized: "This agent session is no longer in this tab. Refresh and try again.")
        case .tabChanged:
            String(localized: "The tab's panes or sessions changed. Review the tab and try again.")
        }
    }
}

nonisolated struct TabCloser: Sendable {
    var fetchPanes: @Sendable () async throws -> [WezTermPane] = {
        try await AgentScanner.fetchPanes()
    }
    var fetchAgents: @Sendable () async throws -> [Agent] = { try await AgentScanner.scan() }
    var killPane: @Sendable (Int) async throws -> Void = { try await AgentScanner.killPane(id: $0) }

    func prepare(for agent: Agent) async throws -> TabClosePlan {
        let sessions = try await fetchAgents().filter { $0.tabID == agent.tabID }
        guard sessions.contains(where: { $0.sessionIdentity == agent.sessionIdentity }) else {
            throw TabCloseError.sessionChanged
        }
        let panes = try await fetchPanes().filter { $0.tabId == agent.tabID }
        guard panes.contains(where: { $0.paneId == agent.paneID }) else {
            throw TabCloseError.sessionChanged
        }
        return TabClosePlan(agent: agent, panes: panes, sessions: sessions)
    }

    func close(_ plan: TabClosePlan) async throws {
        let current = try await prepare(for: plan.agent)
        guard current.paneIDs == plan.paneIDs,
            Set(current.sessions.map(\.sessionIdentity))
                == Set(plan.sessions.map(\.sessionIdentity))
        else { throw TabCloseError.tabChanged }

        // Close only the reviewed pane IDs, leaving the selected session until last.
        let ordered =
            plan.panes.filter { $0.paneId != plan.agent.paneID }
            + plan.panes.filter { $0.paneId == plan.agent.paneID }
        var remaining = plan.paneIDs
        for pane in ordered {
            let panes = try await fetchPanes().filter { $0.tabId == plan.agent.tabID }
            guard Set(panes.map(\.paneId)) == remaining,
                panes.allSatisfy({ current in
                    plan.panes.contains {
                        $0.paneId == current.paneId && $0.ttyName == current.ttyName
                    }
                })
            else { throw TabCloseError.tabChanged }
            try await killPane(pane.paneId)
            remaining.remove(pane.paneId)
        }
    }
}
