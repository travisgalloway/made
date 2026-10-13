import Foundation

/// Buffers raw bytes across reads, because a read may end mid-message or mid-character.
/// Splitting on byte 0x0A is safe for UTF-8, since that byte never occurs inside a multi-byte sequence.
public struct MCPLineFramer: Sendable {
    private var buffer = Data()

    public init() {}

    /// Appends one read and returns every line it completes, trimmed, in order. Blank lines are skipped.
    public mutating func append(_ chunk: Data) -> [Data] {
        var lines: [Data] = []
        var start = chunk.startIndex
        // Search only the new chunk, so feeding a long message in small pieces stays linear.
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            buffer.append(chunk[start..<newline])
            if let line = Self.trimmed(buffer) { lines.append(line) }
            buffer = Data()
            start = chunk.index(after: newline)
        }
        buffer.append(chunk[start...])
        return lines
    }

    /// Returns the buffered remainder as a final line when input ends without a newline.
    public mutating func finish() -> [Data] {
        defer { buffer = Data() }
        return Self.trimmed(buffer).map { [$0] } ?? []
    }

    /// Strips spaces, tabs, and carriage returns from both ends, and returns nil for a blank line.
    private static func trimmed(_ bytes: Data) -> Data? {
        let isPadding: (UInt8) -> Bool = { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
        guard let first = bytes.firstIndex(where: { !isPadding($0) }),
              let last = bytes.lastIndex(where: { !isPadding($0) }) else { return nil }
        return Data(bytes[first...last])
    }
}
