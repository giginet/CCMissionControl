import SwiftUI

struct StatusBadge: View {
    let status: Agent.Status
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(status == .running ? .green : .gray)
            .opacity(status == .running ? (pulsing ? 0.3 : 1.0) : 1.0)
            .frame(width: 10, height: 10)
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
