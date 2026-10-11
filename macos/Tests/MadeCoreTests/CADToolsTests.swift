import XCTest
@testable import MadeCore

final class CADToolsTests: XCTestCase {
    func testGetSceneReturnsDefaultSolids() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let result = await registry.callTool(name: "cad_get_scene", arguments: [:])
        
        XCTAssertEqual(result.isError, false)
        guard let text = result.content.first?.text else {
            XCTFail("Expected text content")
            return
        }
        
        XCTAssertTrue(text.contains("box-1"))
        XCTAssertTrue(text.contains("cylinder-1"))
    }
    
    func testAddSolidCreatesNewBox() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let args: [String: AnyCodableValue] = [
            "type": .string("box"),
            "width": .double(55),
            "depth": .double(35),
            "height": .double(25)
        ]
        
        let result = await registry.callTool(name: "cad_add_solid", arguments: args)
        
        XCTAssertEqual(result.isError, false)
        XCTAssertEqual(doc.objects.count, 3)
        let added = doc.objects.last
        XCTAssertNotNil(added)
        if case .box(let p) = added?.def {
            XCTAssertEqual(p.width, 55)
            XCTAssertEqual(p.depth, 35)
            XCTAssertEqual(p.height, 25)
        } else {
            XCTFail("Expected box solid")
        }
    }
    
    func testSetParamClampsAndUpdates() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let args: [String: AnyCodableValue] = [
            "id": .string("box-1"),
            "param": .string("width"),
            "value": .double(500) // Exceeds max 90
        ]
        
        let result = await registry.callTool(name: "cad_set_param", arguments: args)
        XCTAssertEqual(result.isError, false)
        
        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            XCTAssertEqual(p.width, 90.0) // Clamped to 90
        } else {
            XCTFail("Expected box params")
        }
    }
    
    func testMeasureReturnsCorrectVolume() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        // Default box: 40 x 30 x 20 = 24,000 mm3
        let result = await registry.callTool(name: "cad_measure", arguments: ["id": .string("box-1")])
        XCTAssertEqual(result.isError, false)
        
        guard let text = result.content.first?.text else {
            XCTFail("Expected text content")
            return
        }
        
        XCTAssertTrue(text.contains("24000"))
    }
    
    func testRemoveSolidDeletesFromDocument() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let result = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string("box-1")])
        XCTAssertEqual(result.isError, false)
        XCTAssertEqual(doc.objects.count, 1)
        XCTAssertFalse(doc.objects.contains(where: { $0.id == boxSolidId }))
    }
}
