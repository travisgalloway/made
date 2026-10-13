import Testing
import Foundation
@testable import MadeCore

@Suite struct MCPLineFramerTests {
    /// A `tools/call` request of about 200 KB, padded with an unused string argument.
    static let largeMessage: Data = {
        let padding = String(repeating: "x", count: 200_000)
        return Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cad_get_scene","arguments":{"padding":"\#(padding)"}}}"#.utf8)
    }()

    /// Feeds `input` to a fresh framer in pieces of `size` bytes and returns every line, including the final flush.
    private func frame(_ input: Data, pieceSize size: Int) -> [MCPLineFramer.Frame] {
        var framer = MCPLineFramer()
        var lines: [MCPLineFramer.Frame] = []
        var offset = 0
        while offset < input.count {
            let end = min(offset + size, input.count)
            lines += framer.append(input.subdata(in: offset..<end))
            offset = end
        }
        return lines + framer.finish()
    }

    @Test func testOneMessageIn1BytePieces() {
        let lines = frame(Self.largeMessage + Data("\n".utf8), pieceSize: 1)
        #expect(lines == [.line(Self.largeMessage)])
    }

    @Test func testOneMessageIn7BytePieces() {
        let lines = frame(Self.largeMessage + Data("\n".utf8), pieceSize: 7)
        #expect(lines == [.line(Self.largeMessage)])
    }

    @Test func testOneMessageIn64KBPieces() {
        let lines = frame(Self.largeMessage + Data("\n".utf8), pieceSize: 65_536)
        #expect(lines == [.line(Self.largeMessage)])
    }

    @Test func testTwoMessagesInOneChunk() {
        var framer = MCPLineFramer()
        let lines = framer.append(Data("{\"id\":1}\n{\"id\":2}\n".utf8))
        #expect(lines == [.line(Data("{\"id\":1}".utf8)), .line(Data("{\"id\":2}".utf8))])
        #expect(framer.finish().isEmpty)
    }

    @Test func testSplitExactlyAtNewline() {
        var before = MCPLineFramer()
        #expect(before.append(Data("{\"id\":1}".utf8)).isEmpty)
        #expect(before.append(Data("\n{\"id\":2}\n".utf8)) == [.line(Data("{\"id\":1}".utf8)), .line(Data("{\"id\":2}".utf8))])

        var after = MCPLineFramer()
        #expect(after.append(Data("{\"id\":1}\n".utf8)) == [.line(Data("{\"id\":1}".utf8))])
        #expect(after.append(Data("{\"id\":2}\n".utf8)) == [.line(Data("{\"id\":2}".utf8))])
    }

    @Test func testNoTrailingNewlineFlushesOnFinish() {
        var framer = MCPLineFramer()
        #expect(framer.append(Data("{\"id\":1}".utf8)).isEmpty)
        #expect(framer.finish() == [.line(Data("{\"id\":1}".utf8))])
        #expect(framer.finish().isEmpty)
    }

    @Test func testMultiByteCharacterSplitAcrossReads() throws {
        let text = #"{"name":"café 🧊"}"#
        let bytes = Data((text + "\n").utf8)
        let accent = try #require(bytes.firstIndex(of: 0xC3))
        let emoji = try #require(bytes.firstIndex(of: 0xF0))
        var framer = MCPLineFramer()
        var lines: [MCPLineFramer.Frame] = []
        // Cut between the two bytes of "é" and between the second and third bytes of the emoji.
        lines += framer.append(bytes.subdata(in: 0..<(accent + 1)))
        lines += framer.append(bytes.subdata(in: (accent + 1)..<(emoji + 2)))
        lines += framer.append(bytes.subdata(in: (emoji + 2)..<bytes.count))
        #expect(lines.count == 1)
        guard case .line(let line) = lines.first else { return }
        #expect(String(data: line, encoding: .utf8) == text)
    }

    @Test func testOversizedLineIsReportedOnceAndDiscarded() {
        var framer = MCPLineFramer(maximumLineLength: 16)
        // The first piece crosses the limit with no newline, so the buffer is dropped at once.
        #expect(framer.append(Data(String(repeating: "x", count: 20).utf8)) == [.oversized])
        #expect(framer.append(Data(String(repeating: "x", count: 20).utf8)).isEmpty)
        #expect(framer.append(Data("xx\n{\"id\":2}\n".utf8)) == [.line(Data("{\"id\":2}".utf8))])
        #expect(framer.finish().isEmpty)
    }

    @Test func testOversizedLineWithinOneChunk() {
        var framer = MCPLineFramer(maximumLineLength: 16)
        let input = String(repeating: "x", count: 17) + "\n{\"id\":2}\n"
        #expect(framer.append(Data(input.utf8)) == [.oversized, .line(Data("{\"id\":2}".utf8))])
    }

    @Test func testLineAtTheLimitIsKept() {
        var framer = MCPLineFramer(maximumLineLength: 16)
        let line = String(repeating: "x", count: 16)
        #expect(framer.append(Data((line + "\n").utf8)) == [.line(Data(line.utf8))])
    }

    @Test func testOversizedLineWithoutNewlineProducesNothingOnFinish() {
        var framer = MCPLineFramer(maximumLineLength: 16)
        #expect(framer.append(Data(String(repeating: "x", count: 40).utf8)) == [.oversized])
        #expect(framer.finish().isEmpty)
        #expect(framer.append(Data("{\"id\":3}\n".utf8)) == [.line(Data("{\"id\":3}".utf8))])
    }

    @Test func testTrimsWhitespaceAndCarriageReturnAndSkipsBlankLines() {
        var framer = MCPLineFramer()
        let lines = framer.append(Data("  {\"id\":1}\r\n\n\t\n".utf8))
        #expect(lines == [.line(Data("{\"id\":1}".utf8))])
        #expect(framer.finish().isEmpty)
    }
}
