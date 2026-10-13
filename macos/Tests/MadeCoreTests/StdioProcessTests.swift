import Testing
import Foundation
import ImageIO

/// Drives the built `MadeApp --mcp-stdio` executable over its real stdin and stdout.
/// The binary opens its window while it runs (AGENT-1), and each test ends the process by PID.
@Suite struct StdioProcessTests {
    /// SwiftPM puts the test bundle and the app executable in the same products directory.
    static let binary: URL? = {
        // `Bundle.allBundles` omits the test bundle under `swiftpm-testing-helper`, so locate it through a class it defines.
        let url = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("MadeApp")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }()

    @Test(.enabled(if: binary != nil, "MadeApp executable not built"), .timeLimit(.minutes(1)))
    func testCaptureSnapshotOverStdio() async throws {
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cad_add_solid","arguments":{"type":"box"}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"cad_get_scene","arguments":{}}}"#,
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"cad_capture_snapshot","arguments":{}}}"#,
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"cad_get_scene","arguments":{}}}"#,
        ]
        let responses = try await Self.run(try #require(Self.binary), input: lines)

        let tools = try #require(responses[2]?["result"] as? [String: Any])["tools"] as? [[String: Any]]
        #expect(tools?.contains { $0["name"] as? String == "cad_capture_snapshot" } == true)
        let scene = try #require(responses[4]?["result"] as? [String: Any])
        #expect(scene["isError"] as? Bool == false)

        let snapshot = try #require(responses[5]?["result"] as? [String: Any])
        let content = try #require((snapshot["content"] as? [[String: Any]])?.first)
        if MetalTestSupport.isMetal4Available {
            #expect(snapshot["isError"] as? Bool == false)
            #expect(content["mimeType"] as? String == "image/png")
            let data = try #require((content["data"] as? String).flatMap { Data(base64Encoded: $0) })
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 800)
            #expect(image.height == 600)
        } else {
            #expect(snapshot["isError"] as? Bool == true)
            #expect((content["text"] as? String)?.contains("no Metal 4 device") == true)
        }
        // The server keeps answering after the snapshot, whichever branch ran.
        #expect(responses[6] != nil)
    }

    /// Writes `input` as newline-delimited JSON, closes stdin, and returns the responses keyed by request ID.
    private static func run(_ binary: URL, input: [String]) async throws -> [Int: [String: Any]] {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--mcp-stdio"]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let pid = process.processIdentifier
        defer {
            if process.isRunning { kill(pid, SIGKILL) }
            process.waitUntilExit()
        }

        // The server exits when stdin closes; the watchdog ends a process that stops responding.
        let reader = stdout.fileHandleForReading
        let output = Task.detached { reader.readDataToEndOfFile() }
        let watchdog = Task.detached {
            try await Task.sleep(for: .seconds(30))
            kill(pid, SIGTERM)
        }
        defer { watchdog.cancel() }
        stdin.fileHandleForWriting.write(Data((input.joined(separator: "\n") + "\n").utf8))
        try stdin.fileHandleForWriting.close()
        let data = await output.value

        var responses: [Int: [String: Any]] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = object["id"] as? Int else { continue }
            responses[id] = object
        }
        return responses
    }
}

private final class BundleMarker {}
