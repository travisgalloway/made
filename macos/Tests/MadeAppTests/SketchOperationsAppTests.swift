import Testing
import Foundation
import simd
@testable import MadeCore
@testable import MadeApp

@Suite struct SketchOperationsAppTests {

    @Test @MainActor func testDocumentModelAtomicOffsetAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(40, 0))
        let l2 = SketchEntity.line(start: SIMD2(40, 0), end: SIMD2(40, 30))
        let l3 = SketchEntity.line(start: SIMD2(40, 30), end: SIMD2(0, 30))
        let l4 = SketchEntity.line(start: SIMD2(0, 30), end: SIMD2(0, 0))

        let sketch = document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        document.undoManager?.removeAllActions()

        let offset = try SketchOffset.makeOffset(entities: [l1, l2, l3, l4], distance: 5.0)
        let addResult = document.addSketchEntitiesAndConstraints(
            to: sketch.id,
            entities: offset.entities,
            constraints: offset.constraints,
            actionName: "Offset Entities"
        )
        guard case .success = addResult else {
            Issue.record("Expected successful batch addition for offset")
            return
        }

        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 8)
            #expect(data.constraints.count == offset.constraints.count)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single undo step rolls back offset entities and constraints
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 4)
            #expect(data.constraints.isEmpty)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single redo step restores offset entities and constraints
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 8)
            #expect(data.constraints.count == offset.constraints.count)
        } else {
            Issue.record("Expected sketch operation")
        }
    }

    @Test @MainActor func testDocumentModelAtomicMirrorAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let axis = SketchEntity.line(start: SIMD2(0, -50), end: SIMD2(0, 50), isConstruction: true)
        let line = SketchEntity.line(start: SIMD2(10, 0), end: SIMD2(25, 20))

        let sketch = document.addSketchFeature(planeName: "xy", entities: [axis, line])
        document.undoManager?.removeAllActions()

        let mirror = try SketchMirror.makeMirror(entities: [line], mirrorLine: axis)
        let addResult = document.addSketchEntitiesAndConstraints(
            to: sketch.id,
            entities: mirror.entities,
            constraints: mirror.constraints,
            actionName: "Mirror Entities"
        )
        guard case .success = addResult else {
            Issue.record("Expected successful batch addition for mirror")
            return
        }

        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 3)
            #expect(data.constraints.count == mirror.constraints.count)
        }

        // Undo
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 2)
            #expect(data.constraints.isEmpty)
        }

        // Redo
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 3)
            #expect(data.constraints.count == mirror.constraints.count)
        }
    }

    @Test @MainActor func testDocumentModelAtomicPatternAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let circle = SketchEntity.circle(center: SIMD2(10, 10), radius: 5)
        let sketch = document.addSketchFeature(planeName: "xy", entities: [circle])
        document.undoManager?.removeAllActions()

        let pattern = try SketchPattern.makeLinearPattern(
            entities: [circle],
            direction1: SIMD2(1, 0),
            spacing1: 20,
            count1: 3
        )
        let addResult = document.addSketchEntitiesAndConstraints(
            to: sketch.id,
            entities: pattern.entities,
            constraints: pattern.constraints,
            actionName: "Linear Pattern Entities"
        )
        guard case .success = addResult else {
            Issue.record("Expected successful batch addition for pattern")
            return
        }

        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 3)
            #expect(data.constraints.count == 2)
        }

        // Undo
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 1)
            #expect(data.constraints.isEmpty)
        }

        // Redo
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 3)
            #expect(data.constraints.count == 2)
        }
    }

    @Test @MainActor func testWorkspaceMutatorsAndExtrusion() async throws {
        let workspace = WorkspaceModel()

        // 1. Offset mutator on closed rectangle and extrude
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(50, 0))
        let l2 = SketchEntity.line(start: SIMD2(50, 0), end: SIMD2(50, 40))
        let l3 = SketchEntity.line(start: SIMD2(50, 40), end: SIMD2(0, 40))
        let l4 = SketchEntity.line(start: SIMD2(0, 40), end: SIMD2(0, 0))

        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        let offsetRes = try workspace.offsetSketchEntities(in: sketch.id, distance: 5.0)
        #expect(offsetRes.entities.count == 4)

        // 2. Pattern mutator in a new sketch
        let sketch2 = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        let circle = SketchEntity.circle(center: SIMD2(0, 0), radius: 10.0)
        workspace.addSketchEntity(to: sketch2.id, entity: circle)

        let patternRes = try workspace.linearPatternSketchEntities(
            in: sketch2.id,
            spacing1: 30.0,
            count1: 2
        )
        #expect(patternRes.entities.count == 1)

        // Extrude sketch with patterned circles
        let solidId = await workspace.extrudeSketch(sketchFeatureId: sketch2.id, distance: 15.0)
        let sid = try #require(solidId)
        let extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)
    }

    @Test @MainActor func testCADToolsMCPPatternAndOffsetEndpoints() async throws {
        let document = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: document, kernelClient: kernel)

        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(30, 0))
        let l2 = SketchEntity.line(start: SIMD2(30, 0), end: SIMD2(30, 20))
        let axis = SketchEntity.line(start: SIMD2(0, -10), end: SIMD2(0, 50), isConstruction: true)
        let circle = SketchEntity.circle(center: SIMD2(15, 10), radius: 4)

        let sketch = document.addSketchFeature(planeName: "xy", entities: [l1, l2, axis, circle])
        let sketchIdStr = sketch.id.uuidString

        // 1. offset_sketch_entities
        let offsetResult = await registry.callTool(
            name: "offset_sketch_entities",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "distance": .double(5.0)
            ]
        )
        #expect(offsetResult.isError == false)

        // 2. mirror_sketch_entities
        let mirrorResult = await registry.callTool(
            name: "mirror_sketch_entities",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "mirrorLineId": .string(axis.id.uuidString)
            ]
        )
        #expect(mirrorResult.isError == false)

        // 3. linear_pattern_sketch_entities
        let linearResult = await registry.callTool(
            name: "linear_pattern_sketch_entities",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "spacing1": .double(25.0),
                "count1": .int(2),
                "entityIds": .array([.string(circle.id.uuidString)])
            ]
        )
        #expect(linearResult.isError == false)

        // 4. circular_pattern_sketch_entities
        let circularResult = await registry.callTool(
            name: "circular_pattern_sketch_entities",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "centerX": .double(0.0),
                "centerY": .double(0.0),
                "count": .int(3),
                "entityIds": .array([.string(circle.id.uuidString)])
            ]
        )
        #expect(circularResult.isError == false)
    }
}
