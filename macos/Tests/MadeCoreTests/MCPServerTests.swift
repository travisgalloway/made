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
        
        let responseJson = await server.processMessage(requestJson)
        #expect(responseJson != nil)
        guard let resp = responseJson else { return }
        
        #expect(resp.contains("-32601"))
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
