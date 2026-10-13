import Testing
import Foundation
import Network
import Synchronization
@testable import MadeCore

@Suite @MainActor struct MCPServerTests {
    @Test func testInitializeReturnsServerCapabilities() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        
        let requestJson = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
        """
        
        let responseJson = await server.processMessage(requestJson)
        #expect(responseJson != nil)
        guard let resp = responseJson else { return }
        
        #expect(resp.contains("made-native-cad"))
        #expect(resp.contains("protocolVersion"))
    }
    
    @Test func testToolsListReturnsAllCADTools() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        
        let requestJson = """
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
        """
        
        let responseJson = await server.processMessage(requestJson)
        #expect(responseJson != nil)
        guard let resp = responseJson else { return }
        
        #expect(resp.contains("cad_get_scene"))
        #expect(resp.contains("cad_add_solid"))
        #expect(resp.contains("cad_set_param"))
        #expect(resp.contains("cad_measure"))
        #expect(resp.contains("cad_capture_snapshot"))
    }
    
    @Test func testToolsCallExecutesTool() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        
        let requestJson = """
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "cad_set_param",
                "arguments": {
                    "id": "box-1",
                    "param": "height",
                    "value": 75.0
                }
            }
        }
        """
        
        let responseJson = await server.processMessage(requestJson)
        #expect(responseJson != nil)
        guard let resp = responseJson else { return }
        
        #expect(resp.contains("Updated parameter"))
        
        // Assert the document was mutated
        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            #expect(p.height == 75.0)
        } else {
            Issue.record("Expected box params to update")
        }
    }
    
    @Test func testUnknownMethodReturnsError() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        
        let requestJson = """
        {"jsonrpc":"2.0","id":4,"method":"unknown_method","params":{}}
        """
        
        let response = await errorResponse(server, requestJson)
        #expect(response.code == -32601)
        #expect(response.id as? Int == 4)
    }
    
    @Test func testEmptyStringReturnsParseError() async {
        let response = await errorResponse(makeServer(), "")
        #expect(response.code == -32700)
        #expect(response.id is NSNull)
    }
    
    @Test func testNonJSONTextReturnsParseError() async {
        let response = await errorResponse(makeServer(), "not json")
        #expect(response.code == -32700)
        #expect(response.id is NSNull)
    }
    
    @Test func testArrayReturnsInvalidRequest() async {
        let response = await errorResponse(makeServer(), "[1,2]")
        #expect(response.code == -32600)
        #expect(response.id is NSNull)
    }
    
    @Test func testScalarReturnsInvalidRequest() async {
        let response = await errorResponse(makeServer(), "5")
        #expect(response.code == -32600)
        #expect(response.id is NSNull)
    }
    
    @Test func testMissingMethodReturnsInvalidRequestWithNumericID() async {
        let response = await errorResponse(makeServer(), #"{"jsonrpc":"2.0","id":7}"#)
        #expect(response.code == -32600)
        #expect(response.id as? Int == 7)
    }
    
    @Test func testWrongTypeMethodReturnsInvalidRequestWithStringID() async {
        let response = await errorResponse(makeServer(), #"{"jsonrpc":"2.0","id":"abc","method":5}"#)
        #expect(response.code == -32600)
        #expect(response.id as? String == "abc")
    }
    
    @Test func testMissingMethodWithNullIDReturnsInvalidRequest() async {
        let response = await errorResponse(makeServer(), #"{"jsonrpc":"2.0","id":null}"#)
        #expect(response.code == -32600)
        #expect(response.id is NSNull)
    }
    
    @Test func testInvalidIDTypeReturnsInvalidRequest() async {
        let response = await errorResponse(makeServer(), #"{"jsonrpc":"2.0","id":[1],"method":"tools/list"}"#)
        #expect(response.code == -32600)
        #expect(response.id is NSNull)
    }
    
    @Test func testNonObjectParamsReturnsInvalidRequest() async {
        let response = await errorResponse(makeServer(), #"{"jsonrpc":"2.0","id":3,"method":"initialize","params":[1]}"#)
        #expect(response.code == -32600)
        #expect(response.id as? Int == 3)
    }
    
    @Test func testToolsCallWithoutNameReturnsInvalidParams() async {
        let response = await errorResponse(makeServer(), #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{}}"#)
        #expect(response.code == -32602)
        #expect(response.id as? Int == 5)
    }
    
    @Test func testEncodeFailureReturnsInternalError() async {
        let server = makeServer(encoder: ResponseOnlyEncoder())
        let response = await errorResponse(server, #"{"jsonrpc":"2.0","id":9,"method":"tools/list"}"#)
        #expect(response.code == -32603)
        #expect(response.id as? Int == 9)
    }
    
    @Test func testNullIDRequestEchoesNullID() async {
        let json = await decodedResponse(makeServer(), #"{"jsonrpc":"2.0","id":null,"method":"tools/list"}"#)
        #expect(json["result"] != nil)
        #expect(json.keys.contains("id"))
        #expect(json["id"] is NSNull)
    }
    
    @Test func testInitializedNotificationReturnsNoResponse() async {
        let response = await makeServer().processMessage(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(response == nil)
    }
    
    @Test func testNotificationWithParamsReturnsNoResponse() async {
        let response = await makeServer().processMessage(#"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#)
        #expect(response == nil)
    }
    
    @Test func testUnknownNotificationReturnsNoResponse() async {
        let response = await makeServer().processMessage(#"{"jsonrpc":"2.0","method":"notifications/unknown"}"#)
        #expect(response == nil)
    }
    
    @Test func testNotificationWithNonObjectParamsReturnsNoResponse() async {
        let response = await makeServer().processMessage(#"{"jsonrpc":"2.0","method":"notifications/initialized","params":[1]}"#)
        #expect(response == nil)
    }
    
    @Test func testNotificationBetweenRequestsReturnsNoResponse() async {
        let server = makeServer()
        let first = await decodedResponse(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        let middle = await server.processMessage(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        let last = await decodedResponse(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        #expect(first["id"] as? Int == 1)
        #expect(middle == nil)
        #expect(last["id"] as? Int == 2)
    }
    
    @Test func testMissingMethodWithoutIDReturnsInvalidRequest() async {
        let response = await errorResponse(makeServer(), #"{"jsonrpc":"2.0"}"#)
        #expect(response.code == -32600)
        #expect(response.id is NSNull)
    }
    
    @Test func testWrongTypeMethodWithoutIDReturnsInvalidRequest() async {
        let response = await errorResponse(makeServer(), #"{"jsonrpc":"2.0","method":5}"#)
        #expect(response.code == -32600)
        #expect(response.id is NSNull)
    }
    
    @Test func testInitializedWithIDReturnsMethodNotFound() async {
        let response = await errorResponse(makeServer(), #"{"jsonrpc":"2.0","id":4,"method":"notifications/initialized"}"#)
        #expect(response.code == -32601)
        #expect(response.id as? Int == 4)
    }
    
    private func makeServer(encoder: JSONEncoder = JSONEncoder(), maximumLineLength: Int = MCPLineFramer.defaultMaximumLineLength) -> MCPServer {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        return MCPServer(toolRegistry: registry, encoder: encoder, maximumLineLength: maximumLineLength)
    }
    
    private func decodedResponse(_ server: MCPServer, _ message: String) async -> [String: Any] {
        guard let response = await server.processMessage(message),
              let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Expected a JSON object response for \(message)")
            return [:]
        }
        return json
    }
    
    /// Returns the error code and the raw id member, which is nil only when the key is absent.
    private func errorResponse(_ server: MCPServer, _ message: String) async -> (code: Int?, id: Any?) {
        let json = await decodedResponse(server, message)
        let error = json["error"] as? [String: Any]
        return (error?["code"] as? Int, json["id"])
    }
    
    @Test func testStartAndStopTCPServer() throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        
        #expect(!server.isRunning)
        try server.start(port: 19820)
        #expect(server.isRunning)
        #expect(server.port == 19820)
        
        server.stop()
        #expect(!server.isRunning)
    }
    
    @Test(.timeLimit(.minutes(1))) func testTCPRequestLargerThanOneChunkGetsOneResponse() async throws {
        let server = makeServer()
        try server.start(port: 19821)
        defer { server.stop() }
        
        // A 2-byte character repeated, so the cut below lands between the bytes of one character.
        let padding = String(repeating: "é", count: 100_000)
        let large = Data((#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"padding":"\#(padding)"}}"# + "\n").utf8)
        let input = large + Data((#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"# + "\n").utf8)
        let paddingStart = try #require(large.firstIndex(of: 0xC3))
        let cut = paddingStart + 100_001
        let responses = try await exchangeTCP(port: 19821, parts: [input.subdata(in: 0..<cut), input.subdata(in: cut..<input.count)])
        
        #expect(responses.count == 2)
        #expect(responses.map { $0["id"] as? Int } == [1, 2])
        #expect(responses.allSatisfy { $0["error"] == nil })
    }
    
    @Test(.timeLimit(.minutes(1))) func testTCPInvalidUTF8LineGetsParseError() async throws {
        let server = makeServer()
        try server.start(port: 19822)
        defer { server.stop() }
        
        let input = Data([0xFF, 0xFE, 0x0A]) + Data((#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"# + "\n").utf8)
        let responses = try await exchangeTCP(port: 19822, parts: [input])
        
        #expect(responses.count == 2)
        #expect((responses.first?["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect(responses.first?["id"] is NSNull)
        #expect(responses.last?["id"] as? Int == 3)
    }
    
    @Test(.timeLimit(.minutes(1))) func testTCPOversizedLineGetsParseErrorAndClosesConnection() async throws {
        let server = makeServer(maximumLineLength: 1024)
        try server.start(port: 19823)
        defer { server.stop() }
        
        let first = Data((#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"# + "\n").utf8)
        let oversized = Data(String(repeating: "x", count: 4096).utf8)
        let after = Data((#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"# + "\n").utf8)
        let responses = try await exchangeTCP(port: 19823, parts: [first, oversized, after])
        
        // The request after the oversized line is never answered, because the server closed the connection.
        #expect(responses.count == 2)
        #expect(responses.first?["id"] as? Int == 1)
        #expect((responses.last?["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect(responses.last?["id"] is NSNull)
    }
    
    /// Sends `parts` to the listener on localhost, half-closes, and returns each response line read until EOF.
    private func exchangeTCP(port: UInt16, parts: [Data]) async throws -> [[String: Any]] {
        let connection = try await connectTCP(port: port)
        defer { connection.cancel() }
        for part in parts {
            connection.send(content: part, completion: .contentProcessed({ _ in }))
        }
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in }))
        
        var received = Data()
        while true {
            let (chunk, done) = await withCheckedContinuation { (continuation: CheckedContinuation<(Data, Bool), Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                    continuation.resume(returning: (content ?? Data(), isComplete || error != nil))
                }
            }
            received += chunk
            if done { break }
        }
        return received.split(separator: 0x0A).compactMap {
            try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
        }
    }
    
    /// Connects to localhost, retrying while the listener finishes becoming ready.
    private func connectTCP(port: UInt16) async throws -> NWConnection {
        let endpointPort = try #require(NWEndpoint.Port(rawValue: port))
        for _ in 0..<50 {
            let connection = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
            let ready = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let once = ResumeOnce(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: once.resume(true)
                    case .waiting, .failed, .cancelled: once.resume(false)
                    default: break
                    }
                }
                connection.start(queue: .global())
            }
            if ready { return connection }
            connection.cancel()
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Could not connect to the MCP listener on port \(port)")
        throw CancellationError()
    }
}

/// Resumes a continuation once, because a connection reports several terminal states.
private final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<Bool, Never>?>
    
    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = Mutex(continuation)
    }
    
    func resume(_ value: Bool) {
        continuation.withLock { $0.take() }?.resume(returning: value)
    }
}

/// Fails every encode except the final response, to drive the server's -32603 path.
// A stateless test double, so sharing it across isolation domains is safe.
private final class ResponseOnlyEncoder: JSONEncoder, @unchecked Sendable {
    override func encode<T: Encodable>(_ value: T) throws -> Data {
        guard T.self == JSONRPCResponse.self else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Injected failure"))
        }
        return try super.encode(value)
    }
}
