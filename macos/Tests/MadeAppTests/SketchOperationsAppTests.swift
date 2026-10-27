import Testing
import Foundation
import CoreGraphics
import ImageIO
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

    @Test @MainActor func testDocumentModelAtomicFilletAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(40, 0))
        let l2 = SketchEntity.line(start: SIMD2(40, 0), end: SIMD2(40, 30))
        let l3 = SketchEntity.line(start: SIMD2(40, 30), end: SIMD2(0, 30))
        let l4 = SketchEntity.line(start: SIMD2(0, 30), end: SIMD2(0, 0))

        let sketch = document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        document.undoManager?.removeAllActions()

        let filletRes = document.filletSketchCorner(in: sketch.id, line1Id: l1.id, line2Id: l2.id, radius: 5.0)
        guard case .success(let result) = filletRes else {
            Issue.record("Expected successful fillet corner mutation")
            return
        }

        #expect(result.constraints.count == 4)
        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 5)
            #expect(data.constraints.count == 4)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single undo step restores original 4 lines
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 4)
            #expect(data.constraints.isEmpty)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single redo step restores fillet
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 5)
            #expect(data.constraints.count == 4)
        } else {
            Issue.record("Expected sketch operation")
        }
    }

    @Test @MainActor func testDocumentModelAtomicChamferAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(40, 0))
        let l2 = SketchEntity.line(start: SIMD2(40, 0), end: SIMD2(40, 30))
        let l3 = SketchEntity.line(start: SIMD2(40, 30), end: SIMD2(0, 30))
        let l4 = SketchEntity.line(start: SIMD2(0, 30), end: SIMD2(0, 0))

        let sketch = document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        document.undoManager?.removeAllActions()

        let chamferRes = document.chamferSketchCorner(
            in: sketch.id,
            line1Id: l1.id,
            line2Id: l2.id,
            distance1: 6.0,
            distance2: 8.0
        )
        guard case .success(let result) = chamferRes else {
            Issue.record("Expected successful chamfer corner mutation")
            return
        }

        #expect(result.constraints.count == 2)
        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 5)
            #expect(data.constraints.count == 2)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single undo step restores original 4 lines
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 4)
            #expect(data.constraints.isEmpty)
        } else {
            Issue.record("Expected sketch operation")
        }

        // Single redo step restores chamfer
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 5)
            #expect(data.constraints.count == 2)
        } else {
            Issue.record("Expected sketch operation")
        }
    }

    @Test @MainActor func testWorkspaceFilletAndChamferMutatorsWithExtrusion() async throws {
        let workspace = WorkspaceModel()

        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(60, 0))
        let l2 = SketchEntity.line(start: SIMD2(60, 0), end: SIMD2(60, 40))
        let l3 = SketchEntity.line(start: SIMD2(60, 40), end: SIMD2(0, 40))
        let l4 = SketchEntity.line(start: SIMD2(0, 40), end: SIMD2(0, 0))

        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        // 1. Fillet corner between l1 and l2 with radius 8.0
        let filletRes = try workspace.filletSketchCorner(in: sketch.id, entity1Id: l1.id, entity2Id: l2.id, radius: 8.0)
        #expect(filletRes.filletArc.kind == "arc")

        // 2. Chamfer corner between l3 and l4 with distance 6.0
        let chamferRes = try workspace.chamferSketchCorner(in: sketch.id, entity1Id: l3.id, entity2Id: l4.id, distance1: 6.0)
        #expect(chamferRes.chamferLine.kind == "line")

        // 3. Extrude modified closed profile
        let solidId = await workspace.extrudeSketch(sketchFeatureId: sketch.id, distance: 20.0)
        let sid = try #require(solidId)
        let extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)
    }

    @Test @MainActor func testCADToolsMCPFilletAndChamferEndpoints() async throws {
        let document = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: document, kernelClient: kernel)

        let l1 = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(50, 0))
        let l2 = SketchEntity.line(start: SIMD2(50, 0), end: SIMD2(50, 40))
        let l3 = SketchEntity.line(start: SIMD2(50, 40), end: SIMD2(0, 40))
        let l4 = SketchEntity.line(start: SIMD2(0, 40), end: SIMD2(0, 0))

        let sketch = document.addSketchFeature(planeName: "xy", entities: [l1, l2, l3, l4])
        let sketchIdStr = sketch.id.uuidString

        // 1. fillet_sketch_corner
        let filletCallResult = await registry.callTool(
            name: "fillet_sketch_corner",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "line1Id": .string(l1.id.uuidString),
                "line2Id": .string(l2.id.uuidString),
                "radius": .double(5.0)
            ]
        )
        #expect(filletCallResult.isError == false)

        // 2. chamfer_sketch_corner
        let chamferCallResult = await registry.callTool(
            name: "chamfer_sketch_corner",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "line1Id": .string(l3.id.uuidString),
                "line2Id": .string(l4.id.uuidString),
                "distance1": .double(6.0),
                "distance2": .double(8.0)
            ]
        )
        #expect(chamferCallResult.isError == false)
    }

    @Test @MainActor func testDocumentModelAtomicDXFImportAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        document.undoManager?.removeAllActions()

        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        0
        10
        0.0
        20
        0.0
        11
        50.0
        21
        0.0
        0
        LINE
        8
        0
        10
        50.0
        20
        0.0
        11
        50.0
        21
        30.0
        0
        ENDSEC
        0
        EOF
        """

        let result = document.importDXFEntities(to: sketch.id, dxfText: dxf)
        guard case .success(let (entities, _)) = result else {
            Issue.record("Expected successful DXF import")
            return
        }
        #expect(entities.count == 2)

        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 2)
        }

        // Single undo step removes all imported entities
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.isEmpty)
        }

        // Single redo step restores all imported entities
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 2)
        }
    }

    @Test @MainActor func testWorkspaceDXFImportAndExtrusion() async throws {
        let workspace = WorkspaceModel()
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        let dxfRectangle = """
        0
        SECTION
        2
        ENTITIES
        0
        LWPOLYLINE
        8
        0
        70
        1
        90
        4
        10
        0.0
        20
        0.0
        10
        40.0
        20
        0.0
        10
        40.0
        20
        25.0
        10
        0.0
        20
        25.0
        0
        ENDSEC
        0
        EOF
        """

        let (importedEntities, _) = try workspace.importDXFIntoSketch(featureId: sketch.id, dxfText: dxfRectangle)
        #expect(importedEntities.count == 4)

        // Extrude imported DXF loop into 3D solid
        let solidId = await workspace.extrudeSketch(sketchFeatureId: sketch.id, distance: 15.0)
        let sid = try #require(solidId)
        let extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)
    }

    @Test @MainActor func testCADToolsMCPImportDXFToSketch() async throws {
        let document = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: document, kernelClient: kernel)

        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        let sketchIdStr = sketch.id.uuidString

        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        CIRCLE
        8
        0
        10
        10.0
        20
        10.0
        40
        5.0
        0
        ENDSEC
        0
        EOF
        """

        let result = await registry.callTool(
            name: "cad_import_dxf_to_sketch",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "dxfContent": .string(dxf)
            ]
        )
        #expect(result.isError == false)
        guard let responseText = result.content.first?.text else {
            Issue.record("Expected text response")
            return
        }
        #expect(responseText.contains("entitiesImported"))
        #expect(responseText.contains("1"))

        // Also test alias import_dxf_to_sketch
        let aliasResult = await registry.callTool(
            name: "import_dxf_to_sketch",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "dxfContent": .string(dxf)
            ]
        )
        #expect(aliasResult.isError == false)
    }

    @Test @MainActor func testDocumentModelAtomicSVGImportAndSymmetricUndoRedo() throws {
        let document = DocumentModel()
        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        document.undoManager?.removeAllActions()

        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <line x1="0" y1="0" x2="50" y2="0" />
            <line x1="50" y1="0" x2="50" y2="30" />
        </svg>
        """

        let result = document.importSVGEntities(to: sketch.id, svgText: svg)
        guard case .success(let (entities, _)) = result else {
            Issue.record("Expected successful SVG import")
            return
        }
        #expect(entities.count == 2)

        var feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 2)
        }

        // Single undo step removes all imported entities
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.isEmpty)
        }

        // Single redo step restores all imported entities
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let data) = feat.operation {
            #expect(data.entities.count == 2)
        }
    }

    @Test @MainActor func testWorkspaceSVGImportAndExtrusion() async throws {
        let workspace = WorkspaceModel()
        let sketch = workspace.document.addSketchFeature(planeName: "xy", entities: [])
        workspace.selectedId = ObjectId(sketch.id.uuidString)

        let svgRectangle = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <rect x="0" y="0" width="40" height="25" />
        </svg>
        """

        let (importedEntities, _) = try workspace.importSVGIntoSketch(featureId: sketch.id, svgText: svgRectangle)
        #expect(importedEntities.count == 4)

        // Extrude imported SVG loop into 3D solid
        let solidId = await workspace.extrudeSketch(sketchFeatureId: sketch.id, distance: 15.0)
        let sid = try #require(solidId)
        let extrudeFeat = try #require(workspace.document.feature(for: sid))
        #expect(extrudeFeat.errorState == nil)
    }

    @Test @MainActor func testCADToolsMCPImportSVGToSketch() async throws {
        let document = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: document, kernelClient: kernel)

        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        let sketchIdStr = sketch.id.uuidString

        let svg = """
        <svg viewBox="0 0 100 100" width="100mm" height="100mm" xmlns="http://www.w3.org/2000/svg">
            <circle cx="20" cy="20" r="10" />
        </svg>
        """

        let result = await registry.callTool(
            name: "cad_import_svg_to_sketch",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "svgContent": .string(svg)
            ]
        )
        #expect(result.isError == false)
        guard let responseText = result.content.first?.text else {
            Issue.record("Expected text response")
            return
        }
        #expect(responseText.contains("entitiesImported"))
        #expect(responseText.contains("1"))

        // Also test alias import_svg_to_sketch
        let aliasResult = await registry.callTool(
            name: "import_svg_to_sketch",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "svgContent": .string(svg)
            ]
        )
        #expect(aliasResult.isError == false)
    }

    private static func makeTestImageData(width: Int = 120, height: Int = 80) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test @MainActor func testDocumentModelAtomicUnderlayMutationsAndUndoRedo() throws {
        let document = DocumentModel()
        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        document.undoManager?.removeAllActions()

        let pngData = Self.makeTestImageData(width: 100, height: 60)
        let underlay = try SketchImageUnderlay(
            name: "Initial Underlay",
            imageData: pngData,
            origin: SIMD2<Double>(10, 20),
            opacity: 0.75
        )

        // 1. Add underlay
        document.addSketchImageUnderlay(to: sketch.id, underlay: underlay)
        var feat = try #require(document.feature(for: sketch.id))
        guard case .sketch(let data) = feat.operation else {
            Issue.record("Expected sketch operation")
            return
        }
        #expect(data.underlays.count == 1)
        #expect(data.underlays[0].name == "Initial Underlay")
        #expect(data.underlays[0].opacity == 0.75)

        // Undo addition
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let undoneData) = feat.operation {
            #expect(undoneData.underlays.isEmpty)
        }

        // Redo addition
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let redoneData) = feat.operation {
            #expect(redoneData.underlays.count == 1)
        }

        // 2. Update underlay
        var updated = underlay
        updated.opacity = 0.4
        updated.isLocked = true
        document.updateSketchImageUnderlay(in: sketch.id, underlay: updated)
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let updatedData) = feat.operation {
            #expect(updatedData.underlays[0].opacity == 0.4)
            #expect(updatedData.underlays[0].isLocked == true)
        }

        // Undo update
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let undoneUpdateData) = feat.operation {
            #expect(undoneUpdateData.underlays[0].opacity == 0.75)
            #expect(undoneUpdateData.underlays[0].isLocked == false)
        }

        // Redo update
        document.undoManager?.redo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let redoneUpdateData) = feat.operation {
            #expect(redoneUpdateData.underlays[0].opacity == 0.4)
            #expect(redoneUpdateData.underlays[0].isLocked == true)
        }

        // 3. Calibrate underlay
        let calibrated = try document.calibrateSketchImageUnderlay(
            in: sketch.id,
            underlayId: underlay.id,
            point1: SIMD2<Double>(0, 0),
            point2: SIMD2<Double>(100, 0),
            targetDistance: 250.0
        )
        #expect(calibrated.width == 250.0)
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let calibratedData) = feat.operation {
            #expect(calibratedData.underlays[0].width == 250.0)
            #expect(calibratedData.underlays[0].height == 150.0)
        }

        // Undo calibration
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let undoneCalData) = feat.operation {
            #expect(undoneCalData.underlays[0].width == 100.0)
        }

        // 4. Remove underlay
        document.removeSketchImageUnderlay(from: sketch.id, underlayId: underlay.id)
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let removedData) = feat.operation {
            #expect(removedData.underlays.isEmpty)
        }

        // Undo removal
        document.undoManager?.undo()
        feat = try #require(document.feature(for: sketch.id))
        if case .sketch(let restoredData) = feat.operation {
            #expect(restoredData.underlays.count == 1)
        }
    }

    @Test @MainActor func testCADToolsMCPPlaceAndCalibrateImageUnderlay() async throws {
        let document = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: document, kernelClient: kernel)

        let sketch = document.addSketchFeature(planeName: "xy", entities: [])
        let sketchIdStr = sketch.id.uuidString

        let pngData = Self.makeTestImageData(width: 80, height: 40)
        let base64String = pngData.base64EncodedString()

        // Test cad_place_image_underlay
        let placeResult = await registry.callTool(
            name: "cad_place_image_underlay",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "imageBase64": .string(base64String),
                "name": .string("Test Floorplan"),
                "opacity": .double(0.6)
            ]
        )
        #expect(placeResult.isError == false)
        guard let placeResponseText = placeResult.content.first?.text else {
            Issue.record("Expected text response from cad_place_image_underlay")
            return
        }
        #expect(placeResponseText.contains("underlayId"))
        #expect(placeResponseText.contains("Test Floorplan"))

        // Extract underlayId from JSON response
        guard let responseData = placeResponseText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let underlayIdStr = json["underlayId"] as? String else {
            Issue.record("Failed to parse underlayId from response")
            return
        }

        // Test cad_calibrate_image_underlay
        let calibrateResult = await registry.callTool(
            name: "cad_calibrate_image_underlay",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "underlayId": .string(underlayIdStr),
                "point1": .array([.double(0), .double(0)]),
                "point2": .array([.double(80), .double(0)]),
                "targetDistance": .double(160.0)
            ]
        )
        #expect(calibrateResult.isError == false)
        guard let calResponseText = calibrateResult.content.first?.text else {
            Issue.record("Expected text response from cad_calibrate_image_underlay")
            return
        }
        #expect(calResponseText.contains("160"))
        #expect(calResponseText.contains("scaleFactor"))

        // Also test alias calibrate_image_underlay
        let aliasCalibrateResult = await registry.callTool(
            name: "calibrate_image_underlay",
            arguments: [
                "sketchId": .string(sketchIdStr),
                "underlayId": .string(underlayIdStr),
                "point1": .array([.double(0), .double(0)]),
                "point2": .array([.double(80), .double(0)]),
                "targetDistance": .double(240.0)
            ]
        )
        #expect(aliasCalibrateResult.isError == false)

        // Test error when sketch does not exist
        let nonExistentResult = await registry.callTool(
            name: "cad_place_image_underlay",
            arguments: [
                "sketchId": .string(UUID().uuidString),
                "imageBase64": .string(base64String)
            ]
        )
        #expect(nonExistentResult.isError == true)
    }

    @Test @MainActor func testPackageSaveAndReloadPreservesUnderlays() throws {
        let ws = WorkspaceModel()
        let sketch = ws.document.addSketchFeature(planeName: "xy", entities: [])
        let pngData = Self.makeTestImageData(width: 50, height: 50)
        let underlay = try SketchImageUnderlay(
            name: "Icon",
            imageData: pngData,
            origin: SIMD2<Double>(5, 5),
            opacity: 0.9
        )
        ws.document.addSketchImageUnderlay(to: sketch.id, underlay: underlay)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("UnderlayTest.made")
        let package = try ws.makePackage()
        try package.write(to: packageURL)

        // Reload package in new workspace
        let ws2 = WorkspaceModel()
        let opened = ws2.openDocument(at: packageURL)
        #expect(opened)

        let reloadedSketch = try #require(ws2.document.feature(for: sketch.id))
        guard case .sketch(let data) = reloadedSketch.operation else {
            Issue.record("Expected sketch operation")
            return
        }
        #expect(data.underlays.count == 1)
        #expect(data.underlays[0].name == "Icon")
        #expect(data.underlays[0].width == 50.0)
        #expect(data.underlays[0].height == 50.0)
        #expect(data.underlays[0].opacity == 0.9)
        #expect(data.underlays[0].imageData != nil)
        #expect(data.underlays[0].imageData?.count == pngData.count)
    }
}

