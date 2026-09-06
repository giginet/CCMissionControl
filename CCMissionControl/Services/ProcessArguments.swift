import Darwin
import Foundation

nonisolated enum ProcessArguments {
    static func read(pid: Int) -> [String]? {
        var size = 0
        var argMax = [CTL_KERN, KERN_ARGMAX]
        var argMaxSize = MemoryLayout<Int32>.size
        var maximum: Int32 = 0
        guard sysctl(&argMax, 2, &maximum, &argMaxSize, nil, 0) == 0, maximum > 0 else {
            return nil
        }
        size = Int(maximum)
        var buffer = [UInt8](repeating: 0, count: size)
        var mib = [CTL_KERN, KERN_PROCARGS2, Int32(pid)]
        let result = buffer.withUnsafeMutableBytes {
            sysctl(&mib, 3, $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }  // Exited process or inaccessible arguments.
        return parse(Array(buffer.prefix(size)))
    }

    static func parse(_ bytes: [UInt8]) -> [String]? {
        let headerSize = MemoryLayout<Int32>.size
        guard bytes.count > headerSize else { return nil }
        let count = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard count > 0, count <= bytes.count - headerSize else { return nil }
        // KERN_PROCARGS2: argc, executable path, NUL padding, argv, then environment.
        guard let pathEnd = bytes[headerSize...].firstIndex(of: 0) else { return nil }
        var cursor = pathEnd
        while cursor < bytes.count && bytes[cursor] == 0 { cursor += 1 }
        var arguments: [String] = []
        for _ in 0..<Int(count) {
            guard cursor < bytes.count, let end = bytes[cursor...].firstIndex(of: 0),
                let argument = String(bytes: bytes[cursor..<end], encoding: .utf8)
            else { return nil }
            arguments.append(argument)
            cursor = end + 1
        }
        return arguments
    }
}
