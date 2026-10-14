import Testing
import Foundation
import Network
import Synchronization
import Darwin
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
    
    @Test(.timeLimit(.minutes(1))) func testWindowBoundTCPClientAddsEditsMovesAndCombinesSolids() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let sink = WindowStubSink()
        let registry = CADToolRegistry(
            document: doc,
            kernelClient: kernel,
            meshSink: sink,
            onViewportInvalidated: { sink.invalidations += 1 }
        )
        registry.scheduleRecompute(id: boxSolidId)
        registry.scheduleRecompute(id: cylinderSolidId)
        await registry.settleRecomputes(for: [boxSolidId, cylinderSolidId])
        sink.invalidations = 0
        
        let server = MCPServer(toolRegistry: registry)
        try server.start(port: 19824)
        defer { server.stop() }
        
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"cad_add_solid","arguments":{"type":"box","width":30,"depth":30,"height":30,"posX":10}}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cad_set_param","arguments":{"id":"box-2","param":"width","value":60}}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cad_set_transform","arguments":{"id":"box-2","posX":20}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"cad_boolean_operation","arguments":{"solidA":"box-2","solidB":"cylinder-1","operation":"union"}}}"#
        ]
        let payload = Data((lines.joined(separator: "\n") + "\n").utf8)
        let responses = try await exchangeTCP(port: 19824, parts: [payload])
        
        #expect(responses.count == 4)
        for response in responses {
            let result = response["result"] as? [String: Any]
            #expect(result?["isError"] as? Bool == false)
        }
        let addedId = SolidId("box-2")
        let booleanId = try #require(doc.objects.last?.id)
        #expect(booleanId.rawValue.hasPrefix("boolean-"))
        #expect(sink.meshes[addedId]?.transform.position.x == 20)
        #expect(sink.meshes[booleanId] != nil)
        #expect(sink.invalidations >= 2)
    }
    
    @Test func testLoopbackRestrictionConfiguredOnListener() throws {
        let server = makeServer()
        try server.start(port: 19825)
        defer { server.stop() }
        
        #expect(server.isRunning)
        #expect(server.listener?.parameters.requiredInterfaceType == .loopback)
    }
    
    @Test(.timeLimit(.minutes(1))) func testIPv6LoopbackConnectionSucceeds() async throws {
        let server = makeServer()
        try server.start(port: 19826)
        defer { server.stop() }
        
        let initRequest = Data((#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"# + "\n").utf8)
        let responses = try await exchangeTCP(host: "::1", port: 19826, parts: [initRequest])
        
        #expect(responses.count == 1)
        #expect(responses.first?["id"] as? Int == 1)
        let result = responses.first?["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == "2024-11-05")
    }
    
    @Test(.timeLimit(.minutes(1))) func testNonLoopbackConnectionRefused() async throws {
        let server = makeServer()
        try server.start(port: 19827)
        defer { server.stop() }
        
        #expect(server.listener?.parameters.requiredInterfaceType == .loopback)
        if let nonLoopbackIP = findLocalNonLoopbackIPv4Address() {
            let reachedReady = await connectTCPHost(nonLoopbackIP, port: 19827)
            #expect(!reachedReady)
        } else {
            #expect(server.listener?.parameters.requiredInterfaceType == .loopback)
        }
    }
    
    @Test(.timeLimit(.minutes(1))) func testServerStopAndRestartOnSamePort() async throws {
        let server = makeServer()
        try server.start(port: 19828)
        #expect(server.isRunning)
        #expect(server.listener?.parameters.requiredInterfaceType == .loopback)
        
        let initRequest = Data((#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"# + "\n").utf8)
        let responses1 = try await exchangeTCP(port: 19828, parts: [initRequest])
        #expect(responses1.count == 1)
        #expect(responses1.first?["id"] as? Int == 1)
        
        server.stop()
        #expect(!server.isRunning)
        #expect(server.listener == nil)
        
        try server.start(port: 19828)
        defer { server.stop() }
        #expect(server.isRunning)
        #expect(server.listener?.parameters.requiredInterfaceType == .loopback)
        
        let responses2 = try await exchangeTCP(port: 19828, parts: [initRequest])
        #expect(responses2.count == 1)
        #expect(responses2.first?["id"] as? Int == 1)
    }
    
    @Test(.timeLimit(.minutes(1))) func testStopClosesConnectedClientAndSubsequentToolsCallReceivesNoResponse() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        
        try server.start(port: 19829)
        defer { server.stop() }
        #expect(server.isRunning)
        #expect(server.activeConnectionCount == 0)
        
        let client = try await connectTCP(port: 19829)
        defer { client.cancel() }
        
        for _ in 0..<50 {
            if server.activeConnectionCount == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.activeConnectionCount == 1)
        
        // Verify initial communication works over the connected socket
        let initRequest = Data((#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"# + "\n").utf8)
        client.send(content: initRequest, completion: .contentProcessed({ _ in }))
        let (initResp, _) = await receiveChunk(from: client)
        #expect(!initResp.isEmpty)
        let initRespStr = String(data: initResp, encoding: .utf8) ?? ""
        #expect(initRespStr.contains("made-native-cad"))
        
        // Stop the server
        server.stop()
        #expect(!server.isRunning)
        #expect(server.activeConnectionCount == 0)
        
        // Subsequent tools/call from the disconnected client receives no response and does not mutate the document
        let mutateMsg = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cad_set_param","arguments":{"id":"box-1","param":"height","value":99.0}}}"# + "\n"
        client.send(content: Data(mutateMsg.utf8), completion: .contentProcessed({ _ in }))
        
        let (subsequentData, isDone) = await receiveChunk(from: client)
        #expect(subsequentData.isEmpty)
        #expect(isDone)
        
        // Assert the document was not mutated
        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            #expect(p.height == 20.0)
        } else {
            Issue.record("Expected initial box parameters to remain unchanged")
        }
    }
    
    @Test(.timeLimit(.minutes(1))) func testStopWithNoConnectedClient() throws {
        let server = makeServer()
        #expect(!server.isRunning)
        #expect(server.activeConnectionCount == 0)
        
        try server.start(port: 19830)
        #expect(server.isRunning)
        #expect(server.activeConnectionCount == 0)
        
        server.stop()
        #expect(!server.isRunning)
        #expect(server.activeConnectionCount == 0)
        
        // Repeated stop is a safe no-op
        server.stop()
        #expect(!server.isRunning)
        #expect(server.activeConnectionCount == 0)
    }
    
    @Test(.timeLimit(.minutes(1))) func testClientDisconnectsBeforeServerStop() async throws {
        let server = makeServer()
        try server.start(port: 19831)
        defer { server.stop() }
        #expect(server.isRunning)
        #expect(server.activeConnectionCount == 0)
        
        let client = try await connectTCP(port: 19831)
        defer { client.cancel() }
        for _ in 0..<50 {
            if server.activeConnectionCount == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.activeConnectionCount == 1)
        
        // Client cancels connection on its own
        client.cancel()
        
        for _ in 0..<50 {
            if server.activeConnectionCount == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.activeConnectionCount == 0)
        
        server.stop()
        #expect(!server.isRunning)
        #expect(server.activeConnectionCount == 0)
    }
    
    @Test(.timeLimit(.minutes(1))) func testStopWhileRequestIsInFlightDropsResponseAndClosesSocket() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let blocker = BlockingSnapshotProvider()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: blocker)
        let server = MCPServer(toolRegistry: registry)
        try server.start(port: 19832)
        defer {
            blocker.unblock()
            server.stop()
        }
        
        let client = try await connectTCP(port: 19832)
        defer { client.cancel() }
        
        for _ in 0..<50 {
            if server.activeConnectionCount == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.activeConnectionCount == 1)
        
        let snapshotReq = #"{"jsonrpc":"2.0","id":42,"method":"tools/call","params":{"name":"cad_capture_snapshot","arguments":{}}}"# + "\n"
        client.send(content: Data(snapshotReq.utf8), completion: .contentProcessed({ _ in }))
        
        // Await snapshot provider being entered (request is in flight)
        await blocker.waitForEntry()
        
        // Stop server while request is in flight
        server.stop()
        #expect(!server.isRunning)
        
        // Release snapshot provider
        blocker.unblock()
        
        // Client receives connection closure and zero response data
        let (data, isDone) = await receiveChunk(from: client)
        #expect(data.isEmpty)
        #expect(isDone)
        #expect(server.activeConnectionCount == 0)
    }
    
    @Test(.timeLimit(.minutes(1))) func testStopFollowedByImmediateStartOnSamePortDisconnectsOldClientAndAllowsNewClient() async throws {
        let server = makeServer()
        try server.start(port: 19833)
        #expect(server.isRunning)
        
        let oldClient = try await connectTCP(port: 19833)
        defer { oldClient.cancel() }
        
        for _ in 0..<50 {
            if server.activeConnectionCount == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.activeConnectionCount == 1)
        
        // Stop server immediately
        server.stop()
        #expect(!server.isRunning)
        #expect(server.activeConnectionCount == 0)
        
        // Immediately start server on same port
        try server.start(port: 19833)
        defer { server.stop() }
        #expect(server.isRunning)
        
        // Connect new client
        let newClient = try await connectTCP(port: 19833)
        defer { newClient.cancel() }
        
        // New client communicates successfully
        let initRequest = Data((#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"# + "\n").utf8)
        newClient.send(content: initRequest, completion: .contentProcessed({ _ in }))
        let (newResp, _) = await receiveChunk(from: newClient)
        #expect(!newResp.isEmpty)
        let newRespStr = String(data: newResp, encoding: .utf8) ?? ""
        #expect(newRespStr.contains("made-native-cad"))
        
        // Old client receives closure and cannot communicate
        let (oldData, oldDone) = await receiveChunk(from: oldClient)
        #expect(oldData.isEmpty)
        #expect(oldDone)
    }
    
    private func receiveChunk(from connection: NWConnection, timeout: Duration = .seconds(2)) async -> (data: Data, isDone: Bool) {
        await withTaskGroup(of: (Data, Bool).self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                        continuation.resume(returning: (content ?? Data(), isComplete || error != nil))
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return (Data(), true)
            }
            let result = await group.next() ?? (Data(), true)
            group.cancelAll()
            return result
        }
    }
    
    /// Sends `parts` to the listener on host, half-closes, and returns each response line read until EOF.
    private func exchangeTCP(host: String = "127.0.0.1", port: UInt16, parts: [Data]) async throws -> [[String: Any]] {
        let connection = try await connectTCP(host: host, port: port)
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
    
    /// Connects to host, retrying while the listener finishes becoming ready.
    private func connectTCP(host: String = "127.0.0.1", port: UInt16) async throws -> NWConnection {
        let endpointPort = try #require(NWEndpoint.Port(rawValue: port))
        let endpointHost = NWEndpoint.Host(host)
        for _ in 0..<50 {
            let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
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
        Issue.record("Could not connect to the MCP listener on \(host):\(port)")
        throw CancellationError()
    }
    
    /// Attempts a connection to `host:port` and waits up to `timeout` for `.ready`.
    private func connectTCPHost(_ host: String, port: UInt16, timeout: Duration = .milliseconds(500)) async -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        defer { connection.cancel() }
        
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    let once = ResumeOnce(continuation)
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            once.resume(true)
                        case .failed, .cancelled:
                            once.resume(false)
                        case .waiting(let error):
                            if case .posix(let code) = error, code == .ECONNREFUSED {
                                once.resume(false)
                            }
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global())
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
    
    /// Returns the first non-loopback active IPv4 address on the machine, if any.
    private func findLocalNonLoopbackIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback, let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ip = hostBuffer.withUnsafeBufferPointer { ptr in
                        ptr.baseAddress.map { String(cString: $0) } ?? ""
                    }
                    if !ip.isEmpty && ip != "0.0.0.0" {
                        return ip
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return nil
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

@MainActor
private final class WindowStubSink: SolidMeshSink {
    struct Entry {
        var payload: MeshPayload
        var transform: Transform
    }
    var meshes: [SolidId: Entry] = [:]
    var invalidations = 0

    func installMesh(_ payload: MeshPayload, for id: SolidId, transform: Transform, color: SIMD4<Float>, isHidden: Bool) -> Bool {
        meshes[id] = Entry(payload: payload, transform: transform)
        return true
    }

    func updateTransform(_ transform: Transform, for id: SolidId) -> Bool {
        guard var entry = meshes[id] else { return false }
        entry.transform = transform
        meshes[id] = entry
        return true
    }

    func removeMesh(for id: SolidId) -> Bool {
        meshes.removeValue(forKey: id) != nil
    }
}

private final class BlockingSnapshotProvider: SnapshotProvider, Sendable {
    private let enteredContinuation: Mutex<CheckedContinuation<Void, Never>?> = Mutex(nil)
    private let unblockContinuation: Mutex<CheckedContinuation<Void, Never>?> = Mutex(nil)
    private let enteredOnce: Mutex<Bool> = Mutex(false)
    
    func waitForEntry() async {
        let alreadyEntered = enteredOnce.withLock { $0 }
        if alreadyEntered { return }
        await withCheckedContinuation { continuation in
            enteredContinuation.withLock { $0 = continuation }
        }
    }
    
    func unblock() {
        unblockContinuation.withLock { $0.take() }?.resume()
    }
    
    func captureSnapshotPngBase64() async -> String? {
        enteredOnce.withLock { $0 = true }
        enteredContinuation.withLock { $0.take() }?.resume()
        await withCheckedContinuation { continuation in
            unblockContinuation.withLock { $0 = continuation }
        }
        return "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg=="
    }
    
    func captureSnapshotPngBase64(view: ViewportPerspective?) async -> String? {
        await captureSnapshotPngBase64()
    }
}
