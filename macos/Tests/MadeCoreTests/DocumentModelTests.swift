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
}
