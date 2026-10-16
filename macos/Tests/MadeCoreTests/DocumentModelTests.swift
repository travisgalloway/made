import Testing
import Foundation
import Observation
import os
import simd
@testable import MadeCore

@Suite @MainActor struct DocumentModelTests {
    @Test func testInitialDocumentHasTwoDefaultSolids() {
        let doc = DocumentModel()
        
        #expect(doc.features.count == 2)
        #expect(doc.features[0].outputSolidId == boxSolidId)
        #expect(doc.features[0].name == "box-1")
        #expect(doc.features[1].outputSolidId == cylinderSolidId)
        #expect(doc.features[1].name == "cylinder-1")

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
        if case .imported(let name, _, _) = doc.paramsFor(id: id) {
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
        if case .imported(let name, _, _) = doc.paramsFor(id: id) {
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

        // Verify input expressions on features reflect latest parameters
        #expect(doc.features[0].inputExpressions["width"]?.value == 90.0)
        #expect(doc.features[0].inputExpressions["depth"]?.value == 5.0)
        #expect(doc.features[0].inputExpressions["height"]?.value == 5.0)
        #expect(doc.features[1].inputExpressions["radius"]?.value == 5.0)
        #expect(doc.features[1].inputExpressions["height"]?.value == 5.0)
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
        if case .imported(let name, _, _) = doc.paramsFor(id: importedId) {
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

    @Test func testSetMaterialMultipleObjectsImportedAndNonExistent() {
        let doc = DocumentModel()
        let red = MaterialAttributes(color: SIMD4<Float>(1, 0, 0, 1))
        let green = MaterialAttributes(color: SIMD4<Float>(0, 1, 0, 1))

        #expect(doc.setMaterial(id: boxSolidId, material: red) == .success(()))
        #expect(doc.setMaterial(id: cylinderSolidId, material: green) == .success(()))

        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.material.color == SIMD4<Float>(1, 0, 0, 1))
        #expect(doc.objects.first(where: { $0.id == cylinderSolidId })?.material.color == SIMD4<Float>(0, 1, 0, 1))

        // Imported object definition
        let importedId = doc.addObject(def: .imported(name: "step-bracket"))
        let yellow = MaterialAttributes(color: SIMD4<Float>(1, 1, 0, 1))
        #expect(doc.setMaterial(id: importedId, material: yellow) == .success(()))
        #expect(doc.objects.first(where: { $0.id == importedId })?.material.color == SIMD4<Float>(1, 1, 0, 1))

        // Non-existent ID returns .failure(.objectNotFound)
        let ghostId = ObjectId("nonexistent-solid")
        #expect(doc.setMaterial(id: ghostId, material: red) == .failure(.objectNotFound(ghostId)))
    }

    @Test func testParameterSummaryForEachKind() {
        // Box with integer dimensions
        let boxInt = ObjectDef.box(BoxParams(width: 40, depth: 30, height: 20))
        #expect(boxInt.parameterSummary == "40 × 30 × 20 mm")

        // Box with fractional dimensions
        let boxFrac = ObjectDef.box(BoxParams(width: 10.5, depth: 20.25, height: 30))
        #expect(boxFrac.parameterSummary == "10.5 × 20.25 × 30 mm")

        // Cylinder with integer parameters
        let cylInt = ObjectDef.cylinder(CylinderParams(radius: 10, height: 25))
        #expect(cylInt.parameterSummary == "r 10 × h 25 mm")

        // Cylinder with fractional parameters
        let cylFrac = ObjectDef.cylinder(CylinderParams(radius: 12.5, height: 35.75))
        #expect(cylFrac.parameterSummary == "r 12.5 × h 35.75 mm")

        // Imported with filename
        let importedNamed = ObjectDef.imported(name: "bracket.step")
        #expect(importedNamed.parameterSummary == "bracket.step")

        // Imported with empty string
        let importedEmpty = ObjectDef.imported(name: "")
        #expect(importedEmpty.parameterSummary == "Imported mesh")

        // Boolean operation
        let boolDef = ObjectDef.boolean(op: .subtract, solidA: ObjectId("box-1"), solidB: ObjectId("cylinder-1"))
        #expect(boolDef.parameterSummary == "subtract(box-1, cylinder-1)")

        // Part with URL
        let partDef = ObjectDef.part(url: URL(fileURLWithPath: "/workspace/models/wheel.part.ts"))
        #expect(partDef.parameterSummary == "wheel.part.ts")

        // Part with root/empty path fallback
        let partEmpty = ObjectDef.part(url: URL(string: "file:///")!)
        #expect(partEmpty.parameterSummary == "part")

        // NaN and infinity guards
        let boxNaN = ObjectDef.box(BoxParams(width: .nan, depth: .infinity, height: 10))
        #expect(boxNaN.parameterSummary == "— × — × 10 mm")

        let cylNaN = ObjectDef.cylinder(CylinderParams(radius: .nan, height: .infinity))
        #expect(cylNaN.parameterSummary == "r — × h — mm")

        // SceneObject forwarding properties
        let sceneObj = SceneObject(id: ObjectId("box-1"), def: boxInt)
        #expect(sceneObj.parameterSummary == "40 × 30 × 20 mm")
        #expect(sceneObj.kind == "box")
    }

    @Test func testFiveHundredObjectsResponsivenessAndSelection() {
        let doc = DocumentModel()
        // Clear default solids to manage explicit 500 items
        for obj in doc.objects {
            doc.removeObject(id: obj.id)
        }
        #expect(doc.objects.isEmpty)

        var addedIds: [ObjectId] = []
        addedIds.reserveCapacity(500)
        for i in 1...500 {
            let id = doc.addObject(def: .box(BoxParams(width: Float(i % 50 + 10), depth: 30, height: 20)))
            addedIds.append(id)
        }
        #expect(doc.objects.count == 500)

        let firstId = addedIds[0]
        let midId = addedIds[250]
        let lastId = addedIds[499]

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            doc.selectedId = firstId
            #expect(doc.selectedId == firstId)
            doc.selectedId = midId
            #expect(doc.selectedId == midId)
            doc.selectedId = lastId
            #expect(doc.selectedId == lastId)
        }
        #expect(elapsed < .milliseconds(50))

        // Removing the selected object sets selectedId = nil
        doc.removeObject(id: lastId)
        #expect(doc.selectedId == nil)

        // Reset selection and remove an unselected object
        doc.selectedId = midId
        #expect(doc.selectedId == midId)
        doc.removeObject(id: firstId)
        #expect(doc.selectedId == midId)
    }

    // MARK: - Undo / Redo Tests (Issue #39, DOC-16)

    @Test func testEmptyUndoStackDisablesUndo() {
        let doc = DocumentModel()
        #expect(!doc.canUndo)
        #expect(!doc.canRedo)
        #expect(doc.undoActionTitle == "Undo")
        #expect(doc.redoActionTitle == "Redo")
        #expect(doc.undoTitle == "Undo")
        #expect(doc.redoTitle == "Redo")
    }

    @Test func testUndoRedoParamMutation() {
        let doc = DocumentModel()
        let boxId = boxSolidId
        var recordedMutations: [DocumentMutation] = []
        doc.onUndoRedoMutation = { recordedMutations.append($0) }

        #expect(!doc.canUndo)
        let result = doc.setParam(id: boxId, key: "width", value: 60)
        #expect(result == .success(()))
        #expect(box(doc, boxId)?.width == 60)
        #expect(doc.canUndo)
        #expect(doc.undoActionTitle == "Undo Change Width")

        doc.undo()
        #expect(box(doc, boxId)?.width == 40)
        #expect(recordedMutations == [.paramChanged(boxId, key: "width", value: 40)])
        #expect(!doc.canUndo)
        #expect(doc.canRedo)
        #expect(doc.redoActionTitle == "Redo Change Width")

        doc.redo()
        #expect(box(doc, boxId)?.width == 60)
        #expect(recordedMutations == [
            .paramChanged(boxId, key: "width", value: 40),
            .paramChanged(boxId, key: "width", value: 60)
        ])
        #expect(doc.canUndo)
        #expect(!doc.canRedo)
    }

    @Test func testUndoRedoTransformMutation() {
        let doc = DocumentModel()
        let boxId = boxSolidId
        guard let initialTransform = doc.objects.first(where: { $0.id == boxId })?.transform else {
            Issue.record("Default box not found")
            return
        }
        var recordedMutations: [DocumentMutation] = []
        doc.onUndoRedoMutation = { recordedMutations.append($0) }

        var newTransform = initialTransform
        newTransform.position = SIMD3<Float>(10, 20, 30)

        let result = doc.setTransform(id: boxId, transform: newTransform)
        #expect(result == .success(()))
        #expect(doc.objects.first(where: { $0.id == boxId })?.transform == newTransform)
        #expect(doc.canUndo)
        #expect(doc.undoActionTitle == "Undo Move Solid")

        doc.undo()
        #expect(doc.objects.first(where: { $0.id == boxId })?.transform == initialTransform)
        #expect(recordedMutations == [.transformChanged(boxId, transform: initialTransform)])
        #expect(!doc.canUndo)
        #expect(doc.canRedo)
        #expect(doc.redoActionTitle == "Redo Move Solid")

        doc.redo()
        #expect(doc.objects.first(where: { $0.id == boxId })?.transform == newTransform)
        #expect(recordedMutations == [
            .transformChanged(boxId, transform: initialTransform),
            .transformChanged(boxId, transform: newTransform)
        ])
        #expect(doc.canUndo)
        #expect(!doc.canRedo)
    }

    @Test func testUndoRedoAddObject() {
        let doc = DocumentModel()
        var recordedMutations: [DocumentMutation] = []
        doc.onUndoRedoMutation = { recordedMutations.append($0) }

        let newId = doc.addObject(def: .box(BoxParams(width: 50, depth: 50, height: 50)))
        #expect(doc.objects.count == 3)
        #expect(doc.canUndo)
        #expect(doc.undoActionTitle == "Undo Add Box")

        doc.undo()
        #expect(doc.objects.count == 2)
        #expect(!doc.objects.contains(where: { $0.id == newId }))
        #expect(recordedMutations == [.removed(newId)])
        #expect(!doc.canUndo)
        #expect(doc.canRedo)
        #expect(doc.redoActionTitle == "Redo Add Box")

        doc.redo()
        #expect(doc.objects.count == 3)
        #expect(doc.objects.contains(where: { $0.id == newId }))
        #expect(recordedMutations == [.removed(newId), .added(newId)])
        #expect(doc.canUndo)
        #expect(!doc.canRedo)
    }

    @Test func testUndoRedoRemoveObjectRestoresSameId() {
        let doc = DocumentModel()
        guard let initialBox = doc.objects.first(where: { $0.id == boxSolidId }) else {
            Issue.record("Default box not found")
            return
        }
        var recordedMutations: [DocumentMutation] = []
        doc.onUndoRedoMutation = { recordedMutations.append($0) }

        let removeResult = doc.removeObject(id: boxSolidId)
        #expect(removeResult == .success(()))
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
        #expect(doc.selectedId == nil)
        #expect(doc.canUndo)
        #expect(doc.undoActionTitle == "Undo Delete \(initialBox.name)")

        doc.undo()
        #expect(doc.objects.contains(where: { $0.id == boxSolidId }))
        guard let restoredBox = doc.objects.first(where: { $0.id == boxSolidId }) else {
            Issue.record("Restored box not found")
            return
        }
        #expect(restoredBox.id == initialBox.id)
        #expect(restoredBox.name == initialBox.name)
        #expect(restoredBox.def == initialBox.def)
        #expect(restoredBox.transform == initialBox.transform)
        #expect(restoredBox.material == initialBox.material)
        #expect(restoredBox.isVisible == initialBox.isVisible)
        #expect(restoredBox.isLocked == initialBox.isLocked)
        #expect(doc.selectedId == boxSolidId)
        #expect(recordedMutations == [.added(boxSolidId)])
        #expect(!doc.canUndo)
        #expect(doc.canRedo)
        #expect(doc.redoActionTitle == "Redo Delete \(initialBox.name)")

        doc.redo()
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
        #expect(doc.selectedId == nil)
        #expect(recordedMutations == [.added(boxSolidId), .removed(boxSolidId)])
        #expect(doc.canUndo)
        #expect(!doc.canRedo)
    }

    @Test func testRedoClearedAfterNewEdit() {
        let doc = DocumentModel()
        doc.setParam(id: boxSolidId, key: "width", value: 50)
        #expect(doc.canUndo)
        #expect(!doc.canRedo)

        doc.undo()
        #expect(!doc.canUndo)
        #expect(doc.canRedo)

        // A new edit must clear the redo stack
        doc.setParam(id: boxSolidId, key: "height", value: 35)
        #expect(doc.canUndo)
        #expect(!doc.canRedo)
    }

    @Test func testUndoRedoLockedObjectRejection() {
        let doc = DocumentModel()
        var recordedMutations: [DocumentMutation] = []
        doc.onUndoRedoMutation = { recordedMutations.append($0) }

        doc.setParam(id: boxSolidId, key: "width", value: 60)
        #expect(doc.canUndo)

        // Lock the object
        doc.setLocked(id: boxSolidId, isLocked: true)

        // Undo should be rejected because the target solid is locked
        doc.undo()
        #expect(box(doc, boxSolidId)?.width == 60)
        #expect(recordedMutations.isEmpty)

        // Unlock and unlock restore normal undo operation
        doc.setLocked(id: boxSolidId, isLocked: false)

        // Test locked addition undo rejection
        let addedId = doc.addObject(def: .box(BoxParams(width: 20, depth: 20, height: 20)))
        #expect(doc.objects.contains(where: { $0.id == addedId }))
        doc.setLocked(id: addedId, isLocked: true)

        // Undo should not remove locked object
        doc.undo()
        #expect(doc.objects.contains(where: { $0.id == addedId }))
    }

    @Test func testCoalescedSliderParamEdit() {
        let doc = DocumentModel()
        var recordedMutations: [DocumentMutation] = []
        doc.onUndoRedoMutation = { recordedMutations.append($0) }

        doc.beginInteractiveParamEdit(id: boxSolidId, key: "width")
        doc.setParam(id: boxSolidId, key: "width", value: 42)
        doc.setParam(id: boxSolidId, key: "width", value: 48)
        doc.setParam(id: boxSolidId, key: "width", value: 55)
        doc.setParam(id: boxSolidId, key: "width", value: 60)
        doc.endInteractiveParamEdit(id: boxSolidId, key: "width")

        #expect(box(doc, boxSolidId)?.width == 60)
        #expect(doc.canUndo)
        #expect(doc.undoActionTitle == "Undo Change Width")

        // Undoing must revert to initial value (40) in a single step
        doc.undo()
        #expect(box(doc, boxSolidId)?.width == 40)
        #expect(recordedMutations == [.paramChanged(boxSolidId, key: "width", value: 40)])
        #expect(!doc.canUndo)
        #expect(doc.canRedo)
        #expect(doc.redoActionTitle == "Redo Change Width")

        // Redoing restores final value (60) in a single step
        doc.redo()
        #expect(box(doc, boxSolidId)?.width == 60)
        #expect(recordedMutations == [
            .paramChanged(boxSolidId, key: "width", value: 40),
            .paramChanged(boxSolidId, key: "width", value: 60)
        ])
        #expect(doc.canUndo)
        #expect(!doc.canRedo)
    }

    // MARK: - Persistence & Serialization (Issue #83)

    @Test func testDocumentModelSerializationRoundTrip() throws {
        let doc = DocumentModel()
        // Add all types of objects
        let boxId = doc.addObject(
            ObjectId("custom-box-1"),
            def: .box(BoxParams(width: 50, depth: 40, height: 30)),
            transform: Transform(
                position: SIMD3<Float>(10, 20, 30),
                rotation: simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 0, 1)),
                scale: SIMD3<Float>(2, 2, 2)
            )
        )
        doc.setName(id: boxId, name: "My Box")
        doc.setVisibility(id: boxId, isVisible: false)
        _ = doc.setMaterial(id: boxId, material: MaterialAttributes(color: SIMD4<Float>(1, 0, 0, 1)))
        doc.setLocked(id: boxId, isLocked: true)

        let cylinderId = doc.addObject(
            ObjectId("custom-cyl-2"),
            def: .cylinder(CylinderParams(radius: 20, height: 60))
        )

        let importedId = doc.addObject(
            ObjectId("custom-imp-3"),
            def: .imported(name: "bracket.step", sourceURL: URL(fileURLWithPath: "assets/bracket.step"))
        )

        let boolId = doc.addObject(
            ObjectId("custom-bool-4"),
            def: .boolean(op: .union, solidA: boxId, solidB: cylinderId)
        )

        let partId = doc.addObject(
            ObjectId("custom-part-5"),
            def: .part(url: URL(fileURLWithPath: "/tmp/bracket.part.ts"))
        )

        doc.selectedId = boolId

        // Encode
        let encodedData = try DocumentModelCoder.encode(document: doc)
        #expect(!encodedData.isEmpty)
        #expect(encodedData.last == UInt8(ascii: "\n"))

        // Decode
        let decodedData = try DocumentModelCoder.decode(from: encodedData)
        #expect(decodedData.schemaVersion == DocumentData.currentSchemaVersion)
        #expect(decodedData.selectedId == boolId)
        #expect(decodedData.objects.count == doc.objects.count)

        // Verify restoration into new DocumentModel
        let restoredDoc = DocumentModel(objects: decodedData.objects, selectedId: decodedData.selectedId)
        #expect(restoredDoc.objects.count == doc.objects.count)
        #expect(restoredDoc.selectedId == boolId)

        // Verify custom box properties
        guard let restoredBox = restoredDoc.objects.first(where: { $0.id == boxId }) else {
            Issue.record("Missing restored box")
            return
        }
        #expect(restoredBox.name == "My Box")
        #expect(!restoredBox.isVisible)
        #expect(restoredBox.isLocked)
        #expect(restoredBox.material.color == SIMD4<Float>(1, 0, 0, 1))
        #expect(restoredBox.transform.position == SIMD3<Float>(10, 20, 30))
        #expect(restoredBox.transform.scale == SIMD3<Float>(2, 2, 2))
        if case .box(let p) = restoredBox.def {
            #expect(p.width == 50)
            #expect(p.depth == 40)
            #expect(p.height == 30)
        } else {
            Issue.record("Expected box def")
        }

        // Verify cylinder
        guard let restoredCyl = restoredDoc.objects.first(where: { $0.id == cylinderId }) else {
            Issue.record("Missing restored cylinder")
            return
        }
        if case .cylinder(let p) = restoredCyl.def {
            #expect(p.radius == 20)
            #expect(p.height == 60)
        } else {
            Issue.record("Expected cylinder def")
        }

        // Verify imported
        guard let restoredImp = restoredDoc.objects.first(where: { $0.id == importedId }) else {
            Issue.record("Missing restored imported object")
            return
        }
        if case .imported(let name, let url, _) = restoredImp.def {
            #expect(name == "bracket.step")
            #expect(url?.lastPathComponent == "bracket.step")
        } else {
            Issue.record("Expected imported def")
        }

        // Verify boolean
        guard let restoredBool = restoredDoc.objects.first(where: { $0.id == boolId }) else {
            Issue.record("Missing restored boolean")
            return
        }
        if case .boolean(let op, let a, let b) = restoredBool.def {
            #expect(op == .union)
            #expect(a == boxId)
            #expect(b == cylinderId)
        } else {
            Issue.record("Expected boolean def")
        }

        // Verify part
        guard let restoredPart = restoredDoc.objects.first(where: { $0.id == partId }) else {
            Issue.record("Missing restored part")
            return
        }
        if case .part(let url, _) = restoredPart.def {
            #expect(url.lastPathComponent == "bracket.part.ts")
        } else {
            Issue.record("Expected part def")
        }
    }

    @Test func testDocumentModelDecodeClampsOutOfBoundsParameters() throws {
        let json = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "def": {
                "kind": "box",
                "params": {
                  "width": 999.0,
                  "depth": -50.0,
                  "height": 0.0
                }
              }
            },
            {
              "id": "cylinder-1",
              "def": {
                "kind": "cylinder",
                "params": {
                  "radius": 500.0,
                  "height": 2.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: json)
        #expect(decoded.objects.count == 2)

        if case .box(let p) = decoded.objects[0].def {
            #expect(p.width == DocumentLimits.boxWidth.max)
            #expect(p.depth == DocumentLimits.boxDepth.min)
            #expect(p.height == DocumentLimits.boxHeight.min)
        } else {
            Issue.record("Expected box def")
        }

        if case .cylinder(let p) = decoded.objects[1].def {
            #expect(p.radius == DocumentLimits.cylinderRadius.max)
            #expect(p.height == DocumentLimits.cylinderHeight.min)
        } else {
            Issue.record("Expected cylinder def")
        }
    }

    @Test func testDocumentModelDecodeDefaultsMissingOptionalFields() throws {
        let json = """
        {
          "objects": [
            {
              "id": "minimal-box",
              "def": {
                "kind": "box",
                "params": {
                  "width": 20.0,
                  "depth": 20.0,
                  "height": 20.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: json)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.objects.count == 1)

        let obj = decoded.objects[0]
        #expect(obj.id == ObjectId("minimal-box"))
        #expect(obj.name == "minimal-box")
        #expect(obj.transform == .identity)
        #expect(obj.isVisible == true)
        #expect(obj.isLocked == false)
        #expect(obj.material == MaterialAttributes())
    }

    @Test func testDocumentModelRejectsCorruptAndTruncatedJSON() {
        let truncated = "{ \"objects\": [ { \"id\": \"box-1\"".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try DocumentModelCoder.decode(from: truncated)
        }

        let invalidKind = """
        {
          "objects": [
            {
              "id": "obj-1",
              "def": {
                "kind": "unknown_shape"
              }
            }
          ]
        }
        """.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try DocumentModelCoder.decode(from: invalidKind)
        }
    }

    @Test func testDocumentModelResetAndInitMaintainsSequenceCounter() {
        let initialObjects = [
            SceneObject(id: ObjectId("box-5"), def: .box(BoxParams(width: 10, depth: 10, height: 10))),
            SceneObject(id: ObjectId("cylinder-12"), def: .cylinder(CylinderParams(radius: 10, height: 10))),
            SceneObject(id: ObjectId("boolean-3"), def: .boolean(op: .union, solidA: ObjectId("box-5"), solidB: ObjectId("cylinder-12")))
        ]

        let doc = DocumentModel(objects: initialObjects, selectedId: ObjectId("cylinder-12"))
        #expect(doc.selectedId == ObjectId("cylinder-12"))

        // Next reserved ID should be 13 (max 12 + 1)
        let nextId = doc.reserveId(for: .box(BoxParams(width: 10, depth: 10, height: 10)))
        #expect(nextId == ObjectId("box-13"))

        // Reset with new objects with max sequence 42
        let resetObjects = [
            SceneObject(id: ObjectId("part-42"), def: .part(url: URL(fileURLWithPath: "/tmp/foo.part.ts")))
        ]
        doc.reset(with: resetObjects)
        #expect(doc.objects.count == 1)
        #expect(doc.selectedId == ObjectId("part-42"))

        let nextAfterReset = doc.reserveId(for: .cylinder(CylinderParams(radius: 10, height: 10)))
        #expect(nextAfterReset == ObjectId("cylinder-43"))
    }

    @Test func testQuaternionKeyedAndUnkeyedDecoding() throws {
        // Keyed {w, x, y, z}
        let keyedJSON = "{\"w\": 1.0, \"x\": 0.0, \"y\": 0.0, \"z\": 0.0}".data(using: .utf8)!
        let qKeyed = try JSONDecoder().decode(simd_quatf.self, from: keyedJSON)
        #expect(qKeyed.real == 1.0)
        #expect(qKeyed.imag == SIMD3<Float>(0, 0, 0))

        // Unkeyed [x, y, z, w]
        let unkeyedJSON = "[0.0, 0.0, 0.0, 1.0]".data(using: .utf8)!
        let qUnkeyed = try JSONDecoder().decode(simd_quatf.self, from: unkeyedJSON)
        #expect(qUnkeyed.real == 1.0)
        #expect(qUnkeyed.imag == SIMD3<Float>(0, 0, 0))

        // Alternative keyed {r, ix, iy, iz}
        let altKeyedJSON = "{\"r\": 1.0, \"ix\": 0.0, \"iy\": 0.0, \"iz\": 0.0}".data(using: .utf8)!
        let qAltKeyed = try JSONDecoder().decode(simd_quatf.self, from: altKeyedJSON)
        #expect(qAltKeyed.real == 1.0)
        #expect(qAltKeyed.imag == SIMD3<Float>(0, 0, 0))
    }

    @Test func testSelectedSubElementLifecycle() {
        let doc = DocumentModel()
        #expect(doc.selectedSubElement == nil)

        // Select a sub-element
        doc.selectedSubElement = SelectedSubElement(solidId: boxSolidId, elementType: .face, elementId: 2)
        #expect(doc.selectedSubElement?.solidId == boxSolidId)
        #expect(doc.selectedSubElement?.elementType == .face)
        #expect(doc.selectedSubElement?.elementId == 2)

        // Switching selectedId resets selectedSubElement
        doc.selectedId = cylinderSolidId
        #expect(doc.selectedSubElement == nil)

        // Select edge
        doc.selectedSubElement = SelectedSubElement(solidId: cylinderSolidId, elementType: .edge, elementId: 0)
        #expect(doc.selectedSubElement?.elementType == .edge)

        // Clearing selectedId resets selectedSubElement
        doc.selectedId = nil
        #expect(doc.selectedSubElement == nil)

        // doc.reset resets selectedSubElement
        doc.selectedSubElement = SelectedSubElement(solidId: boxSolidId, elementType: .vertex, elementId: 1)
        doc.reset(with: [SceneObject]())
        #expect(doc.selectedSubElement == nil)
    }

    // MARK: - Rollback Marker (BL-FND-05)

    @Test func testAddFeatureInsertsAtRollbackMarker() {
        let doc = DocumentModel()
        #expect(doc.features.count == 2)

        // Roll back to index 1 (between box-1 and cylinder-1)
        doc.setRollbackIndex(1)
        #expect(doc.rollbackIndex == 1)
        #expect(doc.activeFeatures.count == 1)

        // Insert new box feature
        let newBox = Feature.makeBox(solidId: SolidId("box-2"), params: BoxParams(width: 25, depth: 25, height: 25))
        let addedId = doc.addFeature(newBox)

        #expect(doc.features.count == 3)
        #expect(doc.features[0].outputSolidId == boxSolidId)
        #expect(doc.features[1].id == addedId)
        #expect(doc.features[1].outputSolidId == SolidId("box-2"))
        #expect(doc.features[2].outputSolidId == cylinderSolidId)

        // Marker advanced by 1 so new feature is active, but cylinder-1 is still rolled back
        #expect(doc.rollbackIndex == 2)
        #expect(doc.isRolledBack)
        #expect(doc.activeFeatures.count == 2)
        #expect(doc.objects.count == 2)
        #expect(doc.objects.map(\.id) == [boxSolidId, SolidId("box-2")])
    }

    @Test func testAddObjectInsertsAtRollbackMarker() {
        let doc = DocumentModel()
        #expect(doc.features.count == 2)

        // Roll back to 0 (all rolled back)
        doc.setRollbackIndex(0)
        #expect(doc.rollbackIndex == 0)
        #expect(doc.activeFeatures.isEmpty)
        #expect(doc.objects.isEmpty)

        // Add object at marker 0
        let newId = doc.addObject(def: .box(BoxParams(width: 30, depth: 30, height: 30)))
        #expect(doc.features.count == 3)
        #expect(doc.features[0].outputSolidId == newId)
        #expect(doc.features[1].outputSolidId == boxSolidId)
        #expect(doc.features[2].outputSolidId == cylinderSolidId)

        // Marker advanced to 1: new box is active, previous two remain rolled back
        #expect(doc.rollbackIndex == 1)
        #expect(doc.isRolledBack)
        #expect(doc.activeFeatures.count == 1)
        #expect(doc.objects.count == 1)
        #expect(doc.objects.first?.id == newId)
    }

    @Test func testUndoRedoAddFeatureAtMarker() {
        let doc = DocumentModel()
        doc.undoManager?.groupsByEvent = false

        doc.undoManager?.beginUndoGrouping()
        doc.setRollbackIndex(1)
        doc.undoManager?.endUndoGrouping()
        #expect(doc.rollbackIndex == 1)

        let newBox = Feature.makeBox(solidId: SolidId("box-2"), params: BoxParams(width: 25, depth: 25, height: 25))
        doc.undoManager?.beginUndoGrouping()
        _ = doc.addFeature(newBox)
        doc.undoManager?.endUndoGrouping()
        #expect(doc.rollbackIndex == 2)
        #expect(doc.features.count == 3)

        // Undo: removes feature and restores rollbackIndex to 1
        doc.undo()
        #expect(doc.features.count == 2)
        #expect(doc.features.map(\.outputSolidId) == [boxSolidId, cylinderSolidId])
        #expect(doc.rollbackIndex == 1)
        #expect(doc.activeFeatures.count == 1)
        #expect(doc.objects.count == 1)

        // Redo: re-inserts feature and restores rollbackIndex to 2
        doc.redo()
        #expect(doc.features.count == 3)
        #expect(doc.features[1].outputSolidId == SolidId("box-2"))
        #expect(doc.rollbackIndex == 2)
        #expect(doc.activeFeatures.count == 2)
        #expect(doc.objects.count == 2)
    }

    @Test func testUndoRedoRollbackMarker() {
        let doc = DocumentModel()
        doc.undoManager?.groupsByEvent = false
        #expect(doc.rollbackIndex == nil)

        // Roll back to 1
        doc.undoManager?.beginUndoGrouping()
        doc.setRollbackIndex(1)
        doc.undoManager?.endUndoGrouping()
        #expect(doc.rollbackIndex == 1)

        // Roll back to 0
        doc.undoManager?.beginUndoGrouping()
        doc.setRollbackIndex(0)
        doc.undoManager?.endUndoGrouping()
        #expect(doc.rollbackIndex == 0)

        // Undo once -> restores 1
        doc.undo()
        #expect(doc.rollbackIndex == 1)

        // Undo again -> restores nil (fully rolled forward)
        doc.undo()
        #expect(doc.rollbackIndex == nil)
        #expect(!doc.isRolledBack)

        // Redo once -> 1
        doc.redo()
        #expect(doc.rollbackIndex == 1)

        // Redo again -> 0
        doc.redo()
        #expect(doc.rollbackIndex == 0)
    }

    @Test func testRemoveFeatureAdjustsRollbackMarker() {
        let doc = DocumentModel()
        let f3 = Feature.makeBox(solidId: SolidId("box-3"), params: BoxParams(width: 20, depth: 20, height: 20))
        doc.addFeature(f3)
        #expect(doc.features.count == 3)

        // Roll back to 2 (features 0 and 1 active; feature 2 inactive)
        doc.setRollbackIndex(2)
        #expect(doc.rollbackIndex == 2)

        // Removing an inactive feature (index 2) leaves marker position invariant (still 2, which is now == count, so normalized to nil)
        let removedInactive = doc.features[2].id
        doc.removeFeature(id: removedInactive)
        #expect(doc.features.count == 2)
        #expect(doc.rollbackIndex == nil)

        // Re-add a feature and roll back to 2
        let f4 = Feature.makeBox(solidId: SolidId("box-4"), params: BoxParams(width: 20, depth: 20, height: 20))
        let f5 = Feature.makeBox(solidId: SolidId("box-5"), params: BoxParams(width: 20, depth: 20, height: 20))
        doc.addFeature(f4)
        doc.addFeature(f5)
        #expect(doc.features.count == 4)

        doc.setRollbackIndex(2)
        #expect(doc.rollbackIndex == 2)

        // Removing an active feature before marker (index 0) decrements marker by 1
        let firstId = doc.features[0].id
        doc.removeFeature(id: firstId)
        #expect(doc.features.count == 3)
        #expect(doc.rollbackIndex == 1)
        #expect(doc.activeFeatures.count == 1)
    }

    @Test func testSelectedIdClearedWhenSelectedFeatureRolledBack() {
        let doc = DocumentModel()
        doc.selectedId = cylinderSolidId
        #expect(doc.selectedId == cylinderSolidId)

        // Roll back before cylinder (to index 1)
        doc.rollBack(to: boxSolidId)
        #expect(doc.rollbackIndex == 1)
        #expect(doc.objects.count == 1)
        #expect(doc.objects.first?.id == boxSolidId)

        // selectedId was cylinder-1, which is now rolled back, so it should be cleared
        #expect(doc.selectedId == nil)
    }

    // MARK: - Document Settings Tests (BL-FND-11)

    @Test func testDocumentSettingsMutationsAndUndoRedo() {
        let doc = DocumentModel()
        #expect(doc.settings == DocumentSettings())

        let customSettings = DocumentSettings(
            units: UnitSettings(lengthUnit: .inches, angleUnit: .radians, decimalPrecision: 4),
            tolerances: KernelTolerances(linearTolerance: 0.005, angularTolerance: 0.2, chordalTolerance: 0.02),
            defaultMaterial: MaterialAttributes(color: SIMD4<Float>(0.8, 0.2, 0.2, 1.0))
        )

        doc.setSettings(customSettings)
        #expect(doc.settings == customSettings)
        #expect(doc.canUndo)
        #expect(doc.undoTitle.contains("Change Document Settings"))

        // Undo restores initial settings
        doc.undo()
        #expect(doc.settings == DocumentSettings())
        #expect(doc.canRedo)

        // Redo reapplies custom settings
        doc.redo()
        #expect(doc.settings == customSettings)

        // Test convenience mutator setUnits
        let newUnits = UnitSettings(lengthUnit: .meters, angleUnit: .degrees, decimalPrecision: 3)
        doc.setUnits(newUnits)
        #expect(doc.settings.units == newUnits)
        #expect(doc.settings.tolerances == customSettings.tolerances)
        #expect(doc.settings.defaultMaterial == customSettings.defaultMaterial)

        doc.undo()
        #expect(doc.settings.units == customSettings.units)

        // Test convenience mutator setTolerances
        let newTols = KernelTolerances(linearTolerance: 0.01, angularTolerance: 0.5, chordalTolerance: 0.05)
        doc.setTolerances(newTols)
        #expect(doc.settings.tolerances == newTols.clamped())

        doc.undo()
        #expect(doc.settings.tolerances == customSettings.tolerances)

        // Test convenience mutator setDefaultMaterial
        let newMat = MaterialAttributes(color: SIMD4<Float>(0.1, 0.9, 0.1, 1.0))
        doc.setDefaultMaterial(newMat)
        #expect(doc.settings.defaultMaterial == newMat)

        doc.undo()
        #expect(doc.settings.defaultMaterial == customSettings.defaultMaterial)
    }

    @Test func testNewObjectsInheritDefaultMaterial() {
        let doc = DocumentModel()
        let customColor = SIMD4<Float>(0.9, 0.1, 0.5, 1.0)
        let customMaterial = MaterialAttributes(color: customColor)
        doc.setDefaultMaterial(customMaterial)

        // Newly added box without explicit material inherits document default material
        let boxId = doc.addObject(def: .box(BoxParams(width: 20, depth: 20, height: 20)))
        let boxObj = doc.objects.first(where: { $0.id == boxId })
        #expect(boxObj?.material == customMaterial)

        // Newly added cylinder with explicit material preserves explicit material
        let explicitColor = SIMD4<Float>(0.1, 0.2, 0.3, 1.0)
        let explicitMaterial = MaterialAttributes(color: explicitColor)
        let cylId = doc.addObject(def: .cylinder(CylinderParams(radius: 10, height: 25)), material: explicitMaterial)
        let cylObj = doc.objects.first(where: { $0.id == cylId })
        #expect(cylObj?.material == explicitMaterial)
    }

    @Test func testAddPartInheritsDefaultMaterial() {
        let doc = DocumentModel()
        let customColor = SIMD4<Float>(0.3, 0.7, 0.2, 1.0)
        let customMaterial = MaterialAttributes(color: customColor)
        doc.setDefaultMaterial(customMaterial)

        let tempURL = URL(fileURLWithPath: "/tmp/test.part.ts")
        let partId = doc.addPart(url: tempURL)
        let partObj = doc.objects.first(where: { $0.id == partId })
        #expect(partObj?.material == customMaterial)
        let partFeat = doc.features.first(where: { $0.outputSolidId == partId })
        #expect(partFeat?.material == customMaterial)
    }

    @Test func testResetPreservesOrUpdatesSettings() {
        let doc = DocumentModel()
        let custom = DocumentSettings(
            units: UnitSettings(lengthUnit: .feet, angleUnit: .radians, decimalPrecision: 1),
            tolerances: KernelTolerances(linearTolerance: 0.1, angularTolerance: 1.0, chordalTolerance: 0.1),
            defaultMaterial: MaterialAttributes(color: SIMD4<Float>(0.5, 0.5, 0.5, 1.0))
        )

        doc.reset(with: [SceneObject](), settings: custom)
        #expect(doc.settings == custom)
    }

    // MARK: - Body Operation Dependency Tracking (BL-FND-12)

    @Test func testDirectDependenciesTracksTargetBodyId() {
        let doc = DocumentModel()
        let boxFeat = doc.feature(for: boxSolidId)!

        // Create feature (no target dependency)
        let createFeat = Feature(
            name: "New Solid",
            operation: .primitive(.box(BoxParams(width: 10, depth: 10, height: 10))),
            outputSolidId: SolidId("new-solid-1"),
            bodyOperation: .create,
            targetBodyId: nil
        )
        #expect(doc.directDependencies(of: createFeat).isEmpty)

        // Add operation targeting box-1
        let addFeat = Feature(
            name: "Boss Feature",
            operation: .primitive(.cylinder(CylinderParams(radius: 5, height: 10))),
            outputSolidId: SolidId("boss-1"),
            bodyOperation: .add,
            targetBodyId: boxSolidId
        )
        let addDeps = doc.directDependencies(of: addFeat)
        #expect(addDeps.contains(boxFeat.id))

        // Cut operation targeting box-1
        let cutFeat = Feature(
            name: "Pocket Feature",
            operation: .primitive(.cylinder(CylinderParams(radius: 4, height: 8))),
            outputSolidId: SolidId("pocket-1"),
            bodyOperation: .cut,
            targetBodyId: boxSolidId
        )
        let cutDeps = doc.directDependencies(of: cutFeat)
        #expect(cutDeps.contains(boxFeat.id))
    }

    // MARK: - Feature Naming & Visibility (BL-FND-13, #240)

    @Test func testFeatureNamingAndVisibility() {
        let doc = DocumentModel()
        let boxFeat = doc.features.first(where: { $0.outputSolidId == boxSolidId })!
        let boxFeatId = boxFeat.id

        // Initial state
        #expect(boxFeat.name == "box-1")
        #expect(boxFeat.isVisible == true)
        #expect(boxFeat.isLocked == false)
        #expect(doc.body(for: boxSolidId)?.name == "box-1")
        #expect(doc.body(for: boxSolidId)?.isVisible == true)
        #expect(doc.body(for: boxSolidId)?.isLocked == false)

        // Rename feature
        let renameRes = doc.setFeatureName(id: boxFeatId, name: "Base Extrude")
        #expect(renameRes == .success(()))
        #expect(doc.feature(for: boxFeatId)?.name == "Base Extrude")
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.name == "Base Extrude")
        #expect(doc.body(for: boxSolidId)?.name == "Base Extrude")

        // Set visibility
        let hideRes = doc.setFeatureVisibility(id: boxFeatId, isVisible: false)
        #expect(hideRes == .success(()))
        #expect(doc.feature(for: boxFeatId)?.isVisible == false)
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.isVisible == false)
        #expect(doc.body(for: boxSolidId)?.isVisible == false)

        // Set locked
        let lockRes = doc.setFeatureLocked(id: boxFeatId, isLocked: true)
        #expect(lockRes == .success(()))
        #expect(doc.feature(for: boxFeatId)?.isLocked == true)
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.isLocked == true)
        #expect(doc.body(for: boxSolidId)?.isLocked == true)
    }

    @Test func testFeatureRenameEmptyNameRejection() {
        let doc = DocumentModel()
        let boxFeatId = doc.features[0].id

        let initialName = doc.features[0].name
        #expect(doc.setFeatureName(id: boxFeatId, name: "") == .success(()))
        #expect(doc.features[0].name == initialName)

        #expect(doc.setFeatureName(id: boxFeatId, name: "    \t\n   ") == .success(()))
        #expect(doc.features[0].name == initialName)

        // Whitespace trimming on valid name
        #expect(doc.setFeatureName(id: boxFeatId, name: "  Clean Name  ") == .success(()))
        #expect(doc.features[0].name == "Clean Name")
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.name == "Clean Name")
    }

    @Test func testLockedFeatureRejectsRename() {
        let doc = DocumentModel()
        let boxFeatId = doc.features[0].id
        _ = doc.setFeatureLocked(id: boxFeatId, isLocked: true)

        let initialName = doc.features[0].name
        let result = doc.setFeatureName(id: boxFeatId, name: "Should Fail")
        #expect(result == .failure(.objectLocked(boxSolidId)))
        #expect(doc.features[0].name == initialName)

        // Locked feature allows visibility toggle
        let visResult = doc.setFeatureVisibility(id: boxFeatId, isVisible: false)
        #expect(visResult == .success(()))
        #expect(doc.features[0].isVisible == false)
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.isVisible == false)
        #expect(doc.body(for: boxSolidId)?.isVisible == false)
    }

    @Test func testUndoRedoFeatureMutations() {
        let doc = DocumentModel()
        let boxFeatId = doc.features[0].id
        let initialName = doc.features[0].name

        // Rename undo/redo
        _ = doc.setFeatureName(id: boxFeatId, name: "New Feature Name")
        #expect(doc.features[0].name == "New Feature Name")
        #expect(doc.canUndo)
        #expect(doc.undoActionTitle == "Undo Rename Feature")

        doc.undo()
        #expect(doc.features[0].name == initialName)
        #expect(doc.canRedo)
        #expect(doc.redoActionTitle == "Redo Rename Feature")

        doc.redo()
        #expect(doc.features[0].name == "New Feature Name")

        // Visibility hide undo/redo
        _ = doc.setFeatureVisibility(id: boxFeatId, isVisible: false)
        #expect(doc.features[0].isVisible == false)
        #expect(doc.canUndo)
        #expect(doc.undoActionTitle == "Undo Hide Feature")

        doc.undo()
        #expect(doc.features[0].isVisible == true)
        #expect(doc.canRedo)
        #expect(doc.redoActionTitle == "Redo Hide Feature")

        doc.redo()
        #expect(doc.features[0].isVisible == false)

        // Visibility show undo/redo
        _ = doc.setFeatureVisibility(id: boxFeatId, isVisible: true)
        #expect(doc.features[0].isVisible == true)
        #expect(doc.undoActionTitle == "Undo Show Feature")

        doc.undo()
        #expect(doc.features[0].isVisible == false)
        #expect(doc.redoActionTitle == "Redo Show Feature")

        doc.redo()
        #expect(doc.features[0].isVisible == true)
    }

    @Test func testNonSolidFeatureNamingAndVisibility() {
        let doc = DocumentModel()
        let sketchFeat = Feature(
            name: "Sketch 1",
            operation: .sketch(SketchFeatureData()),
            outputSolidId: nil
        )
        let sketchId = sketchFeat.id
        doc.addFeature(sketchFeat)

        let initialObjectsCount = doc.objects.count
        let initialBodiesCount = doc.bodies.count

        // Rename non-solid feature
        let renameRes = doc.setFeatureName(id: sketchId, name: "Base Profile")
        #expect(renameRes == .success(()))
        #expect(doc.feature(for: sketchId)?.name == "Base Profile")
        #expect(doc.objects.count == initialObjectsCount)
        #expect(doc.bodies.count == initialBodiesCount)

        // Visibility toggle on non-solid feature
        let hideRes = doc.setFeatureVisibility(id: sketchId, isVisible: false)
        #expect(hideRes == .success(()))
        #expect(doc.feature(for: sketchId)?.isVisible == false)
        #expect(doc.objects.count == initialObjectsCount)
        #expect(doc.bodies.count == initialBodiesCount)
    }

    @Test func testObjectAndBodyRenameEmptyNameRejection() {
        let doc = DocumentModel()

        // setName rejects empty / whitespace
        doc.setName(id: boxSolidId, name: "")
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.name == "box-1")
        doc.setName(id: boxSolidId, name: "   \t\n  ")
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.name == "box-1")

        // setName trims valid input
        doc.setName(id: boxSolidId, name: "  Clean Box  ")
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.name == "Clean Box")

        // setBodyName rejects empty / whitespace
        doc.setBodyName(id: cylinderSolidId, name: "")
        #expect(doc.body(for: cylinderSolidId)?.name == "cylinder-1")
        doc.setBodyName(id: cylinderSolidId, name: "   ")
        #expect(doc.body(for: cylinderSolidId)?.name == "cylinder-1")

        // setBodyName trims valid input
        doc.setBodyName(id: cylinderSolidId, name: "  Clean Cylinder  ")
        #expect(doc.body(for: cylinderSolidId)?.name == "Clean Cylinder")
    }

    @Test func testLockedObjectRejectsRename() {
        let doc = DocumentModel()
        doc.setLocked(id: boxSolidId, isLocked: true)

        // setName on locked object is rejected
        doc.setName(id: boxSolidId, name: "Renamed While Locked")
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.name == "box-1")

        // setBodyName on locked body is rejected
        doc.setBodyName(id: boxSolidId, name: "Body Renamed While Locked")
        #expect(doc.body(for: boxSolidId)?.name == "box-1")
    }

    @Test func testDocumentModelSerializationPreservesFeatureAndBodyNamingAndVisibility() throws {
        let doc = DocumentModel()

        // Customize box
        _ = doc.setFeatureName(id: doc.features[0].id, name: "Base Extrude Plate")
        _ = doc.setFeatureVisibility(id: doc.features[0].id, isVisible: false)
        _ = doc.setFeatureLocked(id: doc.features[0].id, isLocked: true)

        // Customize cylinder
        doc.setBodyName(id: cylinderSolidId, name: "Pin Body")

        // Add non-solid sketch
        let sketchFeat = Feature(
            name: "Mounting Holes Sketch",
            operation: .sketch(SketchFeatureData()),
            outputSolidId: nil,
            isVisible: false,
            isLocked: true
        )
        doc.addFeature(sketchFeat)

        // Encode
        let encodedData = try DocumentModelCoder.encode(document: doc)

        // Decode into fresh DocumentModel
        let restoredDoc = DocumentModel()
        try DocumentModelCoder.decode(into: restoredDoc, from: encodedData)

        // Verify box feature, object, and body
        let restoredBoxFeat = restoredDoc.feature(for: doc.features[0].id)
        #expect(restoredBoxFeat?.name == "Base Extrude Plate")
        #expect(restoredBoxFeat?.isVisible == false)
        #expect(restoredBoxFeat?.isLocked == true)

        let restoredBoxObj = restoredDoc.objects.first(where: { $0.id == boxSolidId })
        #expect(restoredBoxObj?.name == "Base Extrude Plate")
        #expect(restoredBoxObj?.isVisible == false)
        #expect(restoredBoxObj?.isLocked == true)

        let restoredBoxBody = restoredDoc.body(for: boxSolidId)
        #expect(restoredBoxBody?.name == "Base Extrude Plate")
        #expect(restoredBoxBody?.isVisible == false)
        #expect(restoredBoxBody?.isLocked == true)

        // Verify cylinder body
        let restoredCylBody = restoredDoc.body(for: cylinderSolidId)
        #expect(restoredCylBody?.name == "Pin Body")

        // Verify sketch feature
        let restoredSketch = restoredDoc.feature(for: sketchFeat.id)
        #expect(restoredSketch?.name == "Mounting Holes Sketch")
        #expect(restoredSketch?.isVisible == false)
        #expect(restoredSketch?.isLocked == true)
    }
}

