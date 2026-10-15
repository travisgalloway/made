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
        
        // Box parameter clamping: width, depth, height clamped to 5...90 mm
        // Below min
        doc.setParam(id: boxSolidId, key: "width", value: 1)
        doc.setParam(id: boxSolidId, key: "depth", value: 0)
        doc.setParam(id: boxSolidId, key: "height", value: -10)
        #expect(box(doc, boxSolidId)?.width == 5.0)
        #expect(box(doc, boxSolidId)?.depth == 5.0)
        #expect(box(doc, boxSolidId)?.height == 5.0)
        
        // Above max
        doc.setParam(id: boxSolidId, key: "width", value: 500)
        doc.setParam(id: boxSolidId, key: "depth", value: 100)
        doc.setParam(id: boxSolidId, key: "height", value: 95)
        #expect(box(doc, boxSolidId)?.width == 90.0)
        #expect(box(doc, boxSolidId)?.depth == 90.0)
        #expect(box(doc, boxSolidId)?.height == 90.0)
        
        // Mid values
        doc.setParam(id: boxSolidId, key: "width", value: 45)
        doc.setParam(id: boxSolidId, key: "depth", value: 30)
        doc.setParam(id: boxSolidId, key: "height", value: 20)
        #expect(box(doc, boxSolidId)?.width == 45.0)
        #expect(box(doc, boxSolidId)?.depth == 30.0)
        #expect(box(doc, boxSolidId)?.height == 20.0)
        
        // NaN and infinities
        doc.setParam(id: boxSolidId, key: "width", value: .nan)
        #expect(box(doc, boxSolidId)?.width == 5.0)
        doc.setParam(id: boxSolidId, key: "width", value: -.infinity)
        #expect(box(doc, boxSolidId)?.width == 5.0)
        doc.setParam(id: boxSolidId, key: "width", value: .infinity)
        #expect(box(doc, boxSolidId)?.width == 90.0)
        doc.setParam(id: boxSolidId, key: "depth", value: .nan)
        #expect(box(doc, boxSolidId)?.depth == 5.0)
        doc.setParam(id: boxSolidId, key: "height", value: .nan)
        #expect(box(doc, boxSolidId)?.height == 5.0)
        
        // Cylinder parameter clamping: radius clamped to 5...50 mm, height clamped to 5...90 mm
        // Below min
        doc.setParam(id: cylinderSolidId, key: "radius", value: 0)
        doc.setParam(id: cylinderSolidId, key: "height", value: 0)
        #expect(cylinder(doc, cylinderSolidId)?.radius == 5.0)
        #expect(cylinder(doc, cylinderSolidId)?.height == 5.0)
        doc.setParam(id: cylinderSolidId, key: "height", value: -50)
        #expect(cylinder(doc, cylinderSolidId)?.height == 5.0)
        
        // Above max
        doc.setParam(id: cylinderSolidId, key: "radius", value: 500)
        doc.setParam(id: cylinderSolidId, key: "height", value: 200)
        #expect(cylinder(doc, cylinderSolidId)?.radius == 50.0)
        #expect(cylinder(doc, cylinderSolidId)?.height == 90.0)
        
        // Mid values
        doc.setParam(id: cylinderSolidId, key: "radius", value: 15)
        doc.setParam(id: cylinderSolidId, key: "height", value: 40)
        #expect(cylinder(doc, cylinderSolidId)?.radius == 15.0)
        #expect(cylinder(doc, cylinderSolidId)?.height == 40.0)
        
        // NaN
        doc.setParam(id: cylinderSolidId, key: "radius", value: .nan)
        doc.setParam(id: cylinderSolidId, key: "height", value: .nan)
        #expect(cylinder(doc, cylinderSolidId)?.radius == 5.0)
        #expect(cylinder(doc, cylinderSolidId)?.height == 5.0)
        
        // Unknown keys and non-existent IDs
        let boxBefore = box(doc, boxSolidId)
        doc.setParam(id: boxSolidId, key: "unknown", value: 10)
        doc.setParam(id: boxSolidId, key: "bogus", value: 50)
        #expect(box(doc, boxSolidId) == boxBefore)
        
        let cylinderBefore = cylinder(doc, cylinderSolidId)
        doc.setParam(id: cylinderSolidId, key: "depth", value: 25)
        doc.setParam(id: cylinderSolidId, key: "unknown", value: 10)
        #expect(cylinder(doc, cylinderSolidId) == cylinderBefore)
        
        // Non-existent ID returns cleanly without crashing or mutating objects
        let initialObjectCount = doc.objects.count
        doc.setParam(id: ObjectId("nonexistent"), key: "width", value: 20)
        #expect(doc.objects.count == initialObjectCount)
        #expect(box(doc, boxSolidId) == boxBefore)
        #expect(cylinder(doc, cylinderSolidId) == cylinderBefore)
    }

    @Test func testTypedDimensionEntryThroughSetParam() {
        let doc = DocumentModel()

        // Setting exact typed value 55.0 mm on box-1 (issue verification scenario)
        doc.setParam(id: boxSolidId, key: "width", value: 55.0)
        #expect(box(doc, boxSolidId)?.width == 55.0)

        // Setting exact fractional values
        doc.setParam(id: boxSolidId, key: "depth", value: 42.5)
        doc.setParam(id: boxSolidId, key: "height", value: 18.0)
        #expect(box(doc, boxSolidId)?.depth == 42.5)
        #expect(box(doc, boxSolidId)?.height == 18.0)

        // Setting exact values on cylinder
        doc.setParam(id: cylinderSolidId, key: "radius", value: 22.5)
        doc.setParam(id: cylinderSolidId, key: "height", value: 65.0)
        #expect(cylinder(doc, cylinderSolidId)?.radius == 22.5)
        #expect(cylinder(doc, cylinderSolidId)?.height == 65.0)

        // Out-of-range typed values clamp to DocumentLimits
        doc.setParam(id: boxSolidId, key: "width", value: 999.0)
        #expect(box(doc, boxSolidId)?.width == DocumentLimits.boxWidth.max)
        doc.setParam(id: boxSolidId, key: "width", value: -5.0)
        #expect(box(doc, boxSolidId)?.width == DocumentLimits.boxWidth.min)

        // Setting param on imported mesh is a no-op
        let importedId = doc.addObject(def: .imported(name: "bracket.step"))
        doc.setParam(id: importedId, key: "width", value: 55.0)
        if case .imported(let name) = doc.paramsFor(id: importedId) {
            #expect(name == "bracket.step")
        } else {
            Issue.record("Expected imported definition unchanged")
        }

        // Safe no-op on non-existent object IDs or invalid parameter keys
        let boxBefore = box(doc, boxSolidId)
        doc.setParam(id: ObjectId("missing-id"), key: "width", value: 55.0)
        doc.setParam(id: boxSolidId, key: "invalid-key", value: 55.0)
        #expect(box(doc, boxSolidId) == boxBefore)
    }

    @Test func testExtendedDocumentProperties() {
        let doc = DocumentModel()
        
        doc.setName(id: boxSolidId, name: "Main Box")
        #expect(doc.objects[0].name == "Main Box")
        
        doc.setVisibility(id: boxSolidId, isVisible: false)
        #expect(!doc.objects[0].isVisible)
        
        let mat = MaterialAttributes(color: SIMD4<Float>(1, 0, 0, 1))
        let matResult = doc.setMaterial(id: boxSolidId, material: mat)
        #expect(matResult == .success(()))
        #expect(doc.objects[0].material.color == (SIMD4<Float>(1, 0, 0, 1)))

        doc.setLocked(id: boxSolidId, isLocked: true)
        #expect(doc.objects[0].isLocked)
    }

    @Test func testLockedObjectRejectsMutations() {
        let doc = DocumentModel()
        doc.setLocked(id: boxSolidId, isLocked: true)
        #expect(doc.objects[0].isLocked)

        let initialBox = box(doc, boxSolidId)
        let initialTransform = doc.objects[0].transform
        let initialMaterial = doc.objects[0].material

        let paramResult = doc.setParam(id: boxSolidId, key: "width", value: 60)
        #expect(paramResult == .failure(.objectLocked(boxSolidId)))
        #expect(box(doc, boxSolidId) == initialBox)

        var newTransform = initialTransform
        newTransform.position.x = 100
        let transformResult = doc.setTransform(id: boxSolidId, transform: newTransform)
        #expect(transformResult == .failure(.objectLocked(boxSolidId)))
        #expect(doc.objects[0].transform == initialTransform)

        let newMaterial = MaterialAttributes(color: SIMD4<Float>(0, 1, 0, 1))
        let materialResult = doc.setMaterial(id: boxSolidId, material: newMaterial)
        #expect(materialResult == .failure(.objectLocked(boxSolidId)))
        #expect(doc.objects[0].material == initialMaterial)

        let removeResult = doc.removeObject(id: boxSolidId)
        #expect(removeResult == .failure(.objectLocked(boxSolidId)))
        #expect(doc.objects.contains(where: { $0.id == boxSolidId }))
        #expect(doc.selectedId == boxSolidId)
    }

    @Test func testLockingAndUnlockingRestoresMutations() {
        let doc = DocumentModel()
        doc.setLocked(id: boxSolidId, isLocked: true)
        #expect(doc.setParam(id: boxSolidId, key: "width", value: 60) == .failure(.objectLocked(boxSolidId)))

        doc.setLocked(id: boxSolidId, isLocked: false)
        #expect(!doc.objects[0].isLocked)

        let paramResult = doc.setParam(id: boxSolidId, key: "width", value: 60)
        #expect(paramResult == .success(()))
        #expect(box(doc, boxSolidId)?.width == 60)

        var t = doc.objects[0].transform
        t.position.y = 42
        #expect(doc.setTransform(id: boxSolidId, transform: t) == .success(()))
        #expect(doc.objects[0].transform.position.y == 42)

        let mat = MaterialAttributes(color: SIMD4<Float>(0, 0, 1, 1))
        #expect(doc.setMaterial(id: boxSolidId, material: mat) == .success(()))
        #expect(doc.objects[0].material.color == SIMD4<Float>(0, 0, 1, 1))

        #expect(doc.removeObject(id: boxSolidId) == .success(()))
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
    }

    @Test func testUnlockNonExistentIdIsNoOp() {
        let doc = DocumentModel()
        let countBefore = doc.objects.count
        let ghostId = ObjectId("ghost-solid-404")
        doc.setLocked(id: ghostId, isLocked: false)
        doc.setLocked(id: ghostId, isLocked: true)
        #expect(doc.objects.count == countBefore)
    }

    @Test func testLockHiddenObject() {
        let doc = DocumentModel()
        doc.setVisibility(id: boxSolidId, isVisible: false)
        #expect(!doc.objects[0].isVisible)

        doc.setLocked(id: boxSolidId, isLocked: true)
        #expect(doc.objects[0].isLocked)
        #expect(!doc.objects[0].isVisible)

        // Visibility can still be toggled while locked
        doc.setVisibility(id: boxSolidId, isVisible: true)
        #expect(doc.objects[0].isVisible)
        #expect(doc.objects[0].isLocked)

        doc.setVisibility(id: boxSolidId, isVisible: false)
        #expect(!doc.objects[0].isVisible)
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

    @Test func testInitialSelectionIsBox() {
        let doc = DocumentModel()
        #expect(doc.selectedId == boxSolidId)
    }

    @Test func testSettingNewSelectionTriggersObservation() {
        let doc = DocumentModel()
        let changeFired = OSAllocatedUnfairLock<Bool>(initialState: false)
        withObservationTracking {
            _ = doc.selectedId
        } onChange: {
            changeFired.withLock { $0 = true }
        }

        doc.selectedId = cylinderSolidId
        #expect(changeFired.withLock { $0 })
        #expect(doc.selectedId == cylinderSolidId)
    }

    @Test func testSettingUnchangedSelectionIsNoOp() {
        let doc = DocumentModel()
        let changeFired = OSAllocatedUnfairLock<Bool>(initialState: false)
        withObservationTracking {
            _ = doc.selectedId
        } onChange: {
            changeFired.withLock { $0 = true }
        }

        doc.selectedId = boxSolidId
        #expect(!changeFired.withLock { $0 })
        #expect(doc.selectedId == boxSolidId)
    }

    @Test func testRemovingSelectedObjectClearsSelection() {
        let doc = DocumentModel()
        #expect(doc.selectedId == boxSolidId)
        doc.removeObject(id: boxSolidId)
        #expect(doc.selectedId == nil)
    }

    @Test func testRemovingUnselectedObjectPreservesSelection() {
        let doc = DocumentModel()
        #expect(doc.selectedId == boxSolidId)
        doc.removeObject(id: cylinderSolidId)
        #expect(doc.selectedId == boxSolidId)
    }

    @Test func testRemoveUnknownIdIsNoOp() {
        let doc = DocumentModel()
        let initialCount = doc.objects.count
        let initialSelected = doc.selectedId
        doc.removeObject(id: ObjectId("non-existent"))
        #expect(doc.objects.count == initialCount)
        #expect(doc.selectedId == initialSelected)
    }

    @Test func testRemoveAllObjectsLeavesEmptyScene() {
        let doc = DocumentModel()
        for obj in doc.objects {
            doc.removeObject(id: obj.id)
        }
        #expect(doc.objects.isEmpty)
        #expect(doc.selectedId == nil)
    }
}

