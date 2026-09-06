import SwiftUI

extension Agent.Status {
    var color: Color {
        switch self {
        case .running: .green
        case .waiting: .orange
        case .idle, .unknown: .gray
        }
    }

    var helpText: String {
        switch self {
        case .running: "The agent is working."
        case .waiting: "The agent needs approval or input."
        case .idle: "The agent is ready for a new prompt."
        case .unknown:
            "Activity status is unavailable. For custom Codex titles, include status as the first terminal title item."
        }
    }
}

struct StatusBadge: View {
    let status: Agent.Status
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .opacity(status == .running ? (pulsing ? 0.3 : 1.0) : 1.0)
            .frame(width: 10, height: 10)
            .accessibilityLabel(status.rawValue)
            .animation(
                status == .running
                    ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
            .onChange(of: status) {
                pulsing = status == .running
            }
            .onAppear {
                pulsing = status == .running
            }
    }
}
