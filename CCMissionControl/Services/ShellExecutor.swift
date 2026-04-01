import Foundation

enum ShellExecutor {
    nonisolated static func run(
        executablePath: String,
        arguments: [String] = []
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                continuation.resume(
                    throwing: ShellError.nonZeroExit(process.terminationStatus)
                )
                return
            }

            let output = String(data: data, encoding: .utf8) ?? ""
            continuation.resume(returning: output)
        }
    }

    enum ShellError: LocalizedError {
        case nonZeroExit(Int32)

        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let code):
                "Command exited with status \(code)"
            }
        }
    }
}
