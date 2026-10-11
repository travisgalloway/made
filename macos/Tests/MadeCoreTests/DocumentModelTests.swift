import XCTest
@testable import MadeCore

final class DocumentModelTests: XCTestCase {
    func testInitialDocumentHasTwoDefaultSolids() {
        let doc = DocumentModel()
        
        XCTAssertEqual(doc.objects.count, 2)
        XCTAssertEqual(doc.objects[0].id, boxSolidId)
        XCTAssertEqual(doc.objects[1].id, cylinderSolidId)
    }
    
    func testAddAndRemoveObject() {
        let doc = DocumentModel()
        
        let newId = doc.addObject(def: .box(BoxParams(width: 50, depth: 50, height: 50)))
        XCTAssertEqual(doc.objects.count, 3)
        XCTAssertTrue(newId.rawValue.starts(with: "box-"))
        
        doc.removeObject(id: newId)
        XCTAssertEqual(doc.objects.count, 2)
    }
    
    func testSetParamClampsWithinLimits() {
        let doc = DocumentModel()
        
        // Min limit is 5, max is 90
        doc.setParam(id: boxSolidId, key: "width", value: 1)
        if case .box(let params) = doc.paramsFor(id: boxSolidId) {
            XCTAssertEqual(params.width, 5.0)
        } else {
            XCTFail("Expected box params")
        }
        
        doc.setParam(id: boxSolidId, key: "width", value: 500)
        if case .box(let params) = doc.paramsFor(id: boxSolidId) {
            XCTAssertEqual(params.width, 90.0)
        } else {
            XCTFail("Expected box params")
        }
        
        doc.setParam(id: boxSolidId, key: "width", value: 45)
        if case .box(let params) = doc.paramsFor(id: boxSolidId) {
            XCTAssertEqual(params.width, 45.0)
        } else {
            XCTFail("Expected box params")
        }
    }
    
    func testExtendedDocumentProperties() {
        let doc = DocumentModel()
        
        doc.setName(id: boxSolidId, name: "Main Box")
        XCTAssertEqual(doc.objects[0].name, "Main Box")
        
        doc.setVisibility(id: boxSolidId, isVisible: false)
        XCTAssertFalse(doc.objects[0].isVisible)
        
        doc.setLocked(id: boxSolidId, isLocked: true)
        XCTAssertTrue(doc.objects[0].isLocked)
        
        let mat = MaterialAttributes(color: SIMD4<Float>(1, 0, 0, 1))
        doc.setMaterial(id: boxSolidId, material: mat)
        XCTAssertEqual(doc.objects[0].material.color, SIMD4<Float>(1, 0, 0, 1))
    }
}
