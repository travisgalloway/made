import Foundation

/// Buffers raw bytes across reads, because a read may end mid-message or mid-character.
/// Splitting on byte 0x0A is safe for UTF-8, since that byte never occurs inside a multi-byte sequence.
public struct MCPLineFramer: Sendable {
    /// One framed result: a complete line, or a line that exceeded the limit and was discarded.
    public enum Frame: Equatable, Sendable {
        case line(Data)
        case oversized
    }

    /// 16 MiB, far above any real request, so a peer that never sends a newline cannot grow memory without bound.
    public static let defaultMaximumLineLength = 16 * 1024 * 1024

    public let maximumLineLength: Int
    private var buffer = Data()
    /// True after an oversized line was reported, until the newline that ends it.
    private var discarding = false

    public init(maximumLineLength: Int = MCPLineFramer.defaultMaximumLineLength) {
        self.maximumLineLength = maximumLineLength
    }

    /// Appends one read and returns every frame it completes, in order. Lines are trimmed, and blank lines are skipped.
    public mutating func append(_ chunk: Data) -> [Frame] {
        var frames: [Frame] = []
        var start = chunk.startIndex
        // Search only the new chunk, so feeding a long message in small pieces stays linear.
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            if discarding {
                discarding = false
            } else {
                buffer.append(chunk[start..<newline])
                if buffer.count > maximumLineLength {
                    frames.append(.oversized)
                } else if let line = Self.trimmed(buffer) {
                    frames.append(.line(line))
                }
            }
            buffer = Data()
            start = chunk.index(after: newline)
        }
        if !discarding {
            buffer.append(chunk[start...])
            if buffer.count > maximumLineLength {
                buffer = Data()
                discarding = true
                frames.append(.oversized)
            }
        }
        return frames
    }

    /// Returns the buffered remainder as a final line when input ends without a newline.
    public mutating func finish() -> [Frame] {
        defer {
            buffer = Data()
            discarding = false
        }
        return Self.trimmed(buffer).map { [.line($0)] } ?? []
    }

    /// Strips spaces, tabs, and carriage returns from both ends, and returns nil for a blank line.
    private static func trimmed(_ bytes: Data) -> Data? {
        let isPadding: (UInt8) -> Bool = { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
        guard let first = bytes.firstIndex(where: { !isPadding($0) }),
              let last = bytes.lastIndex(where: { !isPadding($0) }) else { return nil }
        return Data(bytes[first...last])
    }
}
