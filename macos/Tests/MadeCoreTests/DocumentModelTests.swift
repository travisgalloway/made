import Testing
import Foundation
import Observation
import os
@testable import MadeCore

@Suite @MainActor struct DocumentModelTests {
    @Test func testInitialDocumentHasTwoDefaultSolids() {
        let doc = DocumentModel()
        
        #expect(doc.objects.count == 2)
        #expect(doc.objects[0].id == boxSolidId)
        #expect(doc.objects[0].transform.position == SIMD3<Float>(-25, 0, 0))
        #expect(doc.objects[1].id == cylinderSolidId)
        #expect(doc.objects[1].transform.position == SIMD3<Float>(25, 0, 0))
    }
    
    @Test func testAddAndRemoveObject() {
        let doc = DocumentModel()
        
        let newId = doc.addObject(def: .box(BoxParams(width: 50, depth: 50, height: 50)))
        #expect(doc.objects.count == 3)
        #expect(newId.rawValue.starts(with: "box-"))
        
        doc.removeObject(id: newId)
        #expect(doc.objects.count == 2)
    }
    
    private func box(_ doc: DocumentModel, _ id: ObjectId) -> BoxParams? {
        if case .box(let p) = doc.paramsFor(id: id) { return p }
        return nil
    }

    private func cylinder(_ doc: DocumentModel, _ id: ObjectId) -> CylinderParams? {
        if case .cylinder(let p) = doc.paramsFor(id: id) { return p }
        return nil
    }

    @Test func testAddObjectClampsBoxAboveMax() {
        let doc = DocumentModel()
        let id = doc.addObject(def: .box(BoxParams(width: 500, depth: 30, height: 20)))
        let p = box(doc, id)
        #expect(p?.width == 90)
        #expect(p?.depth == 30)
        #expect(p?.height == 20)
    }

    @Test func testAddObjectClampsCylinderRadiusZero() {
        let doc = DocumentModel()
        let id = doc.addObject(def: .cylinder(CylinderParams(radius: 0, height: 40)))
        #expect(cylinder(doc, id)?.radius == 5)
        #expect(cylinder(doc, id)?.height == 40)
    }

    @Test func testAddObjectClampsNonFiniteAndNegative() {
        let doc = DocumentModel()
        let b = doc.addObject(def: .box(BoxParams(width: .nan, depth: .infinity, height: -10)))
        #expect(box(doc, b)?.width == 5)
        #expect(box(doc, b)?.depth == 90)
        #expect(box(doc, b)?.height == 5)
        let c = doc.addObject(def: .cylinder(CylinderParams(radius: -.infinity, height: .nan)))
        #expect(cylinder(doc, c)?.radius == 5)
        #expect(cylinder(doc, c)?.height == 5)
    }

    @Test func testAddObjectKeepsValuesAtLimits() {
        let doc = DocumentModel()
        let b = doc.addObject(def: .box(BoxParams(width: 5, depth: 90, height: 5)))
        #expect(box(doc, b) == BoxParams(width: 5, depth: 90, height: 5))
        let c = doc.addObject(def: .cylinder(CylinderParams(radius: 50, height: 90)))
        #expect(cylinder(doc, c) == CylinderParams(radius: 50, height: 90))
    }

    @Test func testAddObjectPassesImportedThrough() {
        let doc = DocumentModel()
        let id = doc.addObject(def: .imported(name: "x"))
        if case .imported(let name) = doc.paramsFor(id: id) {
            #expect(name == "x")
        } else {
            Issue.record("Expected imported def")
        }
    }

    @Test func testReserveIdIsNeverReused() {
        let doc = DocumentModel()
        let def = ObjectDef.boolean(op: .union, solidA: boxSolidId, solidB: cylinderSolidId)
        let first = doc.addObject(doc.reserveId(for: def), def: def)
        doc.removeObject(id: first)
        let second = doc.reserveId(for: def)
        #expect(first != second)
        #expect(second.rawValue.hasPrefix("boolean-"))
        #expect(Int(second.rawValue.dropFirst("boolean-".count))! > Int(first.rawValue.dropFirst("boolean-".count))!)
    }

    @Test func testAddObjectWithReservedIdKeepsId() {
        let doc = DocumentModel()
        let def = ObjectDef.boolean(op: .subtract, solidA: boxSolidId, solidB: cylinderSolidId)
        let reserved = doc.reserveId(for: def)
        #expect(doc.paramsFor(id: reserved) == nil)
        let added = doc.addObject(reserved, def: def)
        #expect(added == reserved)
        #expect(doc.objects.last?.id == reserved)
        #expect(doc.paramsFor(id: reserved) == def)
    }

    @Test func testSetParamClampsCylinderAndNaN() {
        let doc = DocumentModel()
        doc.setParam(id: ObjectId(cylinderSolidId.rawValue), key: "radius", value: 0)
        #expect(cylinder(doc, ObjectId(cylinderSolidId.rawValue))?.radius == 5)
        doc.setParam(id: ObjectId(cylinderSolidId.rawValue), key: "radius", value: 500)
        #expect(cylinder(doc, ObjectId(cylinderSolidId.rawValue))?.radius == 50)
        doc.setParam(id: ObjectId(cylinderSolidId.rawValue), key: "height", value: .nan)
        #expect(cylinder(doc, ObjectId(cylinderSolidId.rawValue))?.height == 5)
        doc.setParam(id: ObjectId(boxSolidId.rawValue), key: "width", value: .infinity)
        #expect(box(doc, ObjectId(boxSolidId.rawValue))?.width == 90)
    }

    @Test func testSetParamIgnoresImported() {
        let doc = DocumentModel()
        let id = doc.addObject(def: .imported(name: "x"))
        doc.setParam(id: id, key: "width", value: 50)
        if case .imported(let name) = doc.paramsFor(id: id) {
            #expect(name == "x")
        } else {
            Issue.record("Expected imported def")
        }
    }

    @Test func testSetParamClampsWithinLimits() {
        let doc = DocumentModel()
        
        // Min limit is 5, max is 90
        doc.setParam(id: boxSolidId, key: "width", value: 1)
        if case .box(let params) = doc.paramsFor(id: boxSolidId) {
            #expect(params.width == 5.0)
        } else {
            Issue.record("Expected box params")
        }
        
        doc.setParam(id: boxSolidId, key: "width", value: 500)
        if case .box(let params) = doc.paramsFor(id: boxSolidId) {
            #expect(params.width == 90.0)
        } else {
            Issue.record("Expected box params")
        }
        
        doc.setParam(id: boxSolidId, key: "width", value: 45)
        if case .box(let params) = doc.paramsFor(id: boxSolidId) {
            #expect(params.width == 45.0)
        } else {
            Issue.record("Expected box params")
        }
    }
    
    @Test func testExtendedDocumentProperties() {
        let doc = DocumentModel()
        
        doc.setName(id: boxSolidId, name: "Main Box")
        #expect(doc.objects[0].name == "Main Box")
        
        doc.setVisibility(id: boxSolidId, isVisible: false)
        #expect(!doc.objects[0].isVisible)
        
        doc.setLocked(id: boxSolidId, isLocked: true)
        #expect(doc.objects[0].isLocked)
        
        let mat = MaterialAttributes(color: SIMD4<Float>(1, 0, 0, 1))
        doc.setMaterial(id: boxSolidId, material: mat)
        #expect(doc.objects[0].material.color == (SIMD4<Float>(1, 0, 0, 1)))
    }
    @Test func testConcurrentAgentMutationsWhileMainActorReads() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        let addCount = 16

        var tasks: [Task<Void, Never>] = []
        for i in 0..<addCount {
            // The add goes through `processMessage`, the path the stdio and TCP transports share.
            tasks.append(Task.detached {
                let line = #"{"jsonrpc":"2.0","id":\#(i),"method":"tools/call","params":{"name":"cad_add_solid","arguments":{"type":"box","posX":\#(i)}}}"#
                _ = await server.processMessage(line)
            })
            tasks.append(Task.detached {
                _ = await registry.callTool(name: "cad_set_param", arguments: [
                    "id": .string("box-1"), "param": .string("width"), "value": .double(Double(100 + i))
                ])
                _ = await registry.callTool(name: "cad_set_transform", arguments: [
                    "id": .string("box-1"), "posX": .double(Double(i))
                ])
            })
        }

        for _ in 0..<200 {
            var total: Float = 0
            for obj in doc.objects { total += obj.transform.position.x }
            _ = (doc.objects.count, total)
            await Task.yield()
        }
        for task in tasks { await task.value }

        #expect(doc.objects.count == 2 + addCount)
        #expect(Set(doc.objects.map(\.id)).count == doc.objects.count)
        if case .box(let params) = doc.paramsFor(id: boxSolidId) {
            #expect(params.width == DocumentLimits.boxWidth.max)
        } else {
            Issue.record("Expected box params")
        }
    }

    @Test func testToolMutationRunsOnMainActor() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)
        let observedOnMain = OSAllocatedUnfairLock<Bool?>(initialState: nil)

        // SwiftUI observes the document through the same tracking, so this is the thread a view sees the change on.
        withObservationTracking {
            _ = doc.objects
        } onChange: {
            let isMain = Thread.isMainThread
            observedOnMain.withLock { $0 = isMain }
        }

        await Task.detached {
            let line = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"cad_add_solid","arguments":{"type":"cylinder"}}}"#
            _ = await server.processMessage(line)
        }.value

        #expect(doc.objects.count == 3)
        #expect(observedOnMain.withLock { $0 } == true)
    }
}
