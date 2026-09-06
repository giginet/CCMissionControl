import SwiftUI

struct AgentRowView: View {
    let agent: Agent
    var isUnread: Bool = false
    var isActive: Bool = false

    private var agentColor: Color {
        switch agent.kind {
        case .claudeCode: .orange
        case .codex: .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(status: agent.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(agent.kind.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(agentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(agentColor.opacity(0.12), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(agentColor.opacity(0.4), lineWidth: 1)
                        }
                        .fixedSize()
                    Text(agent.project)
                        .font(.headline)
                    if isUnread {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    if agent.workspace != "default" {
                        Text(agent.workspace)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(agent.status.rawValue)
                        .help(agent.status.helpText)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(agent.status.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(agent.status.color)
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
        .padding(.horizontal, 8)
        .background(
            isActive ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
