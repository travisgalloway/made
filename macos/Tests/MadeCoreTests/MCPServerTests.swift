import Testing
import Foundation
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
    
    private func makeServer(encoder: JSONEncoder = JSONEncoder()) -> MCPServer {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        return MCPServer(toolRegistry: registry, encoder: encoder)
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
