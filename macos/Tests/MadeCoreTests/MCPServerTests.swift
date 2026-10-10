import XCTest
@testable import MadeCore

final class MCPServerTests: XCTestCase {
    func testInitializeReturnsServerCapabilities() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        
        let requestJson = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
        """
        
        let responseJson = await server.processMessage(requestJson)
        XCTAssertNotNil(responseJson)
        guard let resp = responseJson else { return }
        
        XCTAssertTrue(resp.contains("made-native-cad"))
        XCTAssertTrue(resp.contains("protocolVersion"))
    }
    
    func testToolsListReturnsAllCADTools() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        
        let requestJson = """
        {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
        """
        
        let responseJson = await server.processMessage(requestJson)
        XCTAssertNotNil(responseJson)
        guard let resp = responseJson else { return }
        
        XCTAssertTrue(resp.contains("cad_get_scene"))
        XCTAssertTrue(resp.contains("cad_add_solid"))
        XCTAssertTrue(resp.contains("cad_set_param"))
        XCTAssertTrue(resp.contains("cad_measure"))
        XCTAssertTrue(resp.contains("cad_capture_snapshot"))
    }
    
    func testToolsCallExecutesTool() async {
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
        XCTAssertNotNil(responseJson)
        guard let resp = responseJson else { return }
        
        XCTAssertTrue(resp.contains("Updated parameter"))
        
        // Assert the document was mutated
        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            XCTAssertEqual(p.height, 75.0)
        } else {
            XCTFail("Expected box params to update")
        }
    }
    
    func testUnknownMethodReturnsError() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        
        let requestJson = """
        {"jsonrpc":"2.0","id":4,"method":"unknown_method","params":{}}
        """
        
        let responseJson = await server.processMessage(requestJson)
        XCTAssertNotNil(responseJson)
        guard let resp = responseJson else { return }
        
        XCTAssertTrue(resp.contains("-32601"))
    }
}
