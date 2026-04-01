import SwiftUI

struct StatusBadge: View {
    let status: Agent.Status

    var body: some View {
        Circle()
            .fill(status == .running ? .green : .gray)
            .frame(width: 10, height: 10)
    }
}
