import SwiftUI

struct AgentRowView: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(status: agent.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.project)
                        .font(.headline)
                    Text(agent.workspace)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(agent.status.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            agent.status == .running
                                ? Color.green.opacity(0.15)
                                : Color.gray.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(agent.status == .running ? .green : .secondary)
                }
                Text(agent.cwd)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !agent.title.isEmpty {
                    Text(agent.title)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
