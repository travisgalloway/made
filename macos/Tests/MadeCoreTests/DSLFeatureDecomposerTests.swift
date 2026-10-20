import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct DSLFeatureDecomposerTests {

    @Test func testPrimitivesDecomposeWithExactDimensions() throws {
        // Box
        let boxParams = BoxParams(width: 40, depth: 30, height: 20)
        let boxResult = try DSLFeatureDecomposer.decompose(.box(boxParams))
        #expect(boxResult.features.count == 1)
        let boxFeature = boxResult.features[0]
        #expect(boxFeature.name == "Box 1")
        #expect(boxFeature.isVisible == true)
        #expect(boxFeature.outputSolidId == SolidId("box-1"))
        guard case .primitive(.box(let p)) = boxFeature.operation else {
            Issue.record("Expected box primitive operation")
            return
        }
        #expect(p.width == 40)
        #expect(p.depth == 30)
        #expect(p.height == 20)

        // Cylinder
        let cylParams = CylinderParams(radius: 5, height: 15)
        let cylResult = try DSLFeatureDecomposer.decompose(.cylinder(cylParams, slices: 32))
        #expect(cylResult.features.count == 1)
        let cylFeature = cylResult.features[0]
        #expect(cylFeature.name == "Cylinder 1")
        #expect(cylFeature.outputSolidId == SolidId("cylinder-1"))
        guard case .primitive(.cylinder(let cp)) = cylFeature.operation else {
            Issue.record("Expected cylinder primitive operation")
            return
        }
        #expect(cp.radius == 5)
        #expect(cp.height == 15)

        // Sphere
        let sphereParams = SphereParams(radius: 12)
        let sphereResult = try DSLFeatureDecomposer.decompose(.sphere(sphereParams, slices: 32))
        #expect(sphereResult.features.count == 1)
        let sphereFeature = sphereResult.features[0]
        #expect(sphereFeature.name == "Sphere 1")
        #expect(sphereFeature.outputSolidId == SolidId("sphere-1"))
        guard case .primitive(.sphere(let sp)) = sphereFeature.operation else {
            Issue.record("Expected sphere primitive operation")
            return
        }
        #expect(sp.radius == 12)

        // Cone
        let coneParams = ConeParams(bottomRadius: 10, topRadius: 4, height: 25)
        let coneResult = try DSLFeatureDecomposer.decompose(.cone(coneParams, slices: 32))
        #expect(coneResult.features.count == 1)
        let coneFeature = coneResult.features[0]
        #expect(coneFeature.name == "Cone 1")
        #expect(coneFeature.outputSolidId == SolidId("cone-1"))
        guard case .primitive(.cone(let cnp)) = coneFeature.operation else {
            Issue.record("Expected cone primitive operation")
            return
        }
        #expect(cnp.bottomRadius == 10)
        #expect(cnp.topRadius == 4)
        #expect(cnp.height == 25)
    }

    @Test func testExtrudeDecomposesToSketchAndExtrudeFeatures() throws {
        let profile = SketchProfile(
            plane: .xy,
            points: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(10, 0),
                SIMD2<Float>(10, 10),
                SIMD2<Float>(0, 10)
            ]
        )
        let extrudeNode = ShapeNode.extrude(profile: profile, distance: 35, centered: false)
        let result = try DSLFeatureDecomposer.decompose(extrudeNode)

        #expect(result.features.count == 2)

        // Feature 0: Sketch
        let sketchFeat = result.features[0]
        #expect(sketchFeat.name == "Sketch 1")
        #expect(sketchFeat.outputSolidId == nil)
        guard case .sketch(let sketchData) = sketchFeat.operation else {
            Issue.record("Expected sketch operation for feature 0")
            return
        }
        #expect(sketchData.planeName == "XY")
        #expect(sketchData.entities.count == 4)
        #expect(sketchData.entities.allSatisfy { $0.kind == "line" })

        // Check closed boundary lines
        let e0 = sketchData.entities[0]
        #expect(e0.data["startX"] == 0 && e0.data["startY"] == 0)
        #expect(e0.data["endX"] == 10 && e0.data["endY"] == 0)

        // Feature 1: Extrude
        let extrudeFeat = result.features[1]
        #expect(extrudeFeat.name == "Extrude 1")
        #expect(extrudeFeat.outputSolidId == SolidId("extrude-1"))
        #expect(extrudeFeat.isVisible == true)
        guard case .extrude(let extrudeData) = extrudeFeat.operation else {
            Issue.record("Expected extrude operation for feature 1")
            return
        }
        #expect(extrudeData.sketchFeatureId == sketchFeat.id)
        #expect(extrudeData.distance == 35)
        #expect(extrudeData.isSymmetric == false)
        #expect(extrudeFeat.references.contains(where: { $0.role == "sketchProfile" && $0.target == .feature(sketchFeat.id) }))
        #expect(extrudeFeat.inputExpressions["distance"]?.value == 35)
    }

    @Test func testMultiHoleSketchProfileDecomposesInnerLoops() throws {
        let outer = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(100, 0),
            SIMD2<Float>(100, 100),
            SIMD2<Float>(0, 100)
        ]
        let hole1 = [
            SIMD2<Float>(10, 10),
            SIMD2<Float>(20, 10),
            SIMD2<Float>(20, 20),
            SIMD2<Float>(10, 20)
        ]
        let hole2 = [
            SIMD2<Float>(50, 50),
            SIMD2<Float>(70, 50),
            SIMD2<Float>(70, 70),
            SIMD2<Float>(50, 70)
        ]
        let profile = SketchProfile(plane: .xz, points: outer, holes: [hole1, hole2])
        let extrudeNode = ShapeNode.extrude(profile: profile, distance: 20, centered: true)

        let result = try DSLFeatureDecomposer.decompose(extrudeNode)
        #expect(result.features.count == 2)

        let sketchFeat = result.features[0]
        guard case .sketch(let sketchData) = sketchFeat.operation else {
            Issue.record("Expected sketch operation")
            return
        }
        #expect(sketchData.planeName == "XZ")
        // 4 outer lines + 4 hole1 lines + 4 hole2 lines = 12 line entities
        #expect(sketchData.entities.count == 12)
        #expect(sketchData.entities.allSatisfy { $0.kind == "line" })
    }

    @Test func testNestedBooleansEstablishDependenciesAndHideIntermediateOperands() throws {
        // (Box union Cylinder) subtract Box2
        let box1 = ShapeNode.box(BoxParams(width: 50, depth: 50, height: 10))
        let cyl = ShapeNode.cylinder(CylinderParams(radius: 10, height: 20), slices: 32)
        let unionNode = ShapeNode.boolean(.union, box1, cyl)
        let box2 = ShapeNode.box(BoxParams(width: 5, depth: 5, height: 30))
        let cutNode = ShapeNode.boolean(.subtract, unionNode, box2)

        let result = try DSLFeatureDecomposer.decompose(cutNode)

        // Features in topological order:
        // 1: Box 1 (solidId: box-1, isVisible: false)
        // 2: Cylinder 1 (solidId: cylinder-2, isVisible: false)
        // 3: Boolean 1 (union, target: box-1, tool: cylinder-2, solidId: boolean-3, isVisible: false)
        // 4: Box 2 (solidId: box-4, isVisible: false)
        // 5: Boolean 2 (subtract, target: boolean-3, tool: box-4, solidId: boolean-5, isVisible: true)
        #expect(result.features.count == 5)

        let f1 = result.features[0]
        let f2 = result.features[1]
        let f3 = result.features[2]
        let f4 = result.features[3]
        let f5 = result.features[4]

        #expect(f1.outputSolidId == SolidId("box-1"))
        #expect(f1.isVisible == false)

        #expect(f2.outputSolidId == SolidId("cylinder-2"))
        #expect(f2.isVisible == false)

        #expect(f3.outputSolidId == SolidId("boolean-3"))
        #expect(f3.isVisible == false)
        guard case .boolean(let boolData1) = f3.operation else {
            Issue.record("Expected boolean operation for feature 3")
            return
        }
        #expect(boolData1.op == .union)
        #expect(boolData1.targetSolidId == SolidId("box-1"))
        #expect(boolData1.toolSolidId == SolidId("cylinder-2"))

        #expect(f4.outputSolidId == SolidId("box-4"))
        #expect(f4.isVisible == false)

        #expect(f5.outputSolidId == SolidId("boolean-5"))
        #expect(f5.isVisible == true)
        guard case .boolean(let boolData2) = f5.operation else {
            Issue.record("Expected boolean operation for feature 5")
            return
        }
        #expect(boolData2.op == .subtract)
        #expect(boolData2.targetSolidId == SolidId("boolean-3"))
        #expect(boolData2.toolSolidId == SolidId("box-4"))

        #expect(result.rootSolidId == SolidId("boolean-5"))
    }

    @Test func testNestedTransformsAccumulate() throws {
        let box = ShapeNode.box(BoxParams(width: 10, depth: 10, height: 10))
        let scaled = ShapeNode.scale(box, factor: SIMD3<Float>(2, 3, 4))
        let rotated = ShapeNode.rotate(scaled, axis: SIMD3<Float>(0, 0, 1), angleDegrees: 90)
        let translated = ShapeNode.translate(rotated, offset: SIMD3<Float>(10, 20, 30))

        let result = try DSLFeatureDecomposer.decompose(translated)
        #expect(result.features.count == 1)

        let feat = result.features[0]
        #expect(feat.transform.position.x == 10)
        #expect(feat.transform.position.y == 20)
        #expect(feat.transform.position.z == 30)

        #expect(feat.transform.scale.x == 2)
        #expect(feat.transform.scale.y == 3)
        #expect(feat.transform.scale.z == 4)

        // Rotation around Z by 90 degrees
        let expectedRad = 90.0 * Float.pi / 180.0
        let expectedQuat = simd_quatf(angle: expectedRad, axis: SIMD3<Float>(0, 0, 1))
        #expect(abs(feat.transform.rotation.real - expectedQuat.real) < 1e-4)
        #expect(abs(feat.transform.rotation.imag.z - expectedQuat.imag.z) < 1e-4)
    }

    @Test @MainActor func testCADShapeTargetFeaturesPopulatesDocument() throws {
        let doc = DocumentModel()
        let initialFeatureCount = doc.features.count

        let shape = Box(width: 25, depth: 15, height: 10)
        let imported = try shape.targetFeatures(in: doc)

        #expect(imported.count == 1)
        #expect(doc.features.count == initialFeatureCount + 1)
        #expect(doc.objects.contains(where: { $0.id == imported[0].outputSolidId }))
        #expect(doc.selectedId == imported[0].outputSolidId)
    }

    @Test @MainActor func testGroupedUndoRedoRestoresDocument() throws {
        let doc = DocumentModel()
        let initialCount = doc.features.count

        let box = ShapeNode.box(BoxParams(width: 20, depth: 20, height: 20))
        let cyl = ShapeNode.cylinder(CylinderParams(radius: 5, height: 30), slices: 16)
        let shape = ShapeNode.boolean(.subtract, box, cyl)

        let imported = try doc.importFeatures(from: shape, baseName: "bracket")
        #expect(imported.count == 3)
        #expect(doc.features.count == initialCount + 3)
        #expect(doc.objects.contains(where: { $0.id == imported[2].outputSolidId }))

        // Undo
        doc.undoManager?.undo()
        #expect(doc.features.count == initialCount)
        #expect(!doc.objects.contains(where: { $0.id == imported[2].outputSolidId }))

        // Redo
        doc.undoManager?.redo()
        #expect(doc.features.count == initialCount + 3)
        #expect(doc.objects.contains(where: { $0.id == imported[2].outputSolidId }))
    }

    @Test func testUnsupportedAndInvalidNodesThrowErrors() {
        // Revolve
        let profile = SketchProfile(
            plane: .xy,
            points: [
                SIMD2<Float>(5, 0),
                SIMD2<Float>(10, 0),
                SIMD2<Float>(10, 10),
                SIMD2<Float>(5, 10)
            ]
        )
        let revolveNode = ShapeNode.revolve(profile: profile, angleDegrees: 360, slices: 32)
        #expect(throws: DSLDecompositionError.self) {
            try DSLFeatureDecomposer.decompose(revolveNode)
        }

        // Invalid box (negative width)
        let invalidBox = ShapeNode.box(BoxParams(width: -10, depth: 10, height: 10))
        #expect(throws: DSLDecompositionError.self) {
            try DSLFeatureDecomposer.decompose(invalidBox)
        }

        // Invalid profile (fewer than 3 points)
        let invalidProfile = SketchProfile(
            plane: .xy,
            points: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(10, 0)
            ]
        )
        let invalidExtrude = ShapeNode.extrude(profile: invalidProfile, distance: 10, centered: false)
        #expect(throws: DSLDecompositionError.self) {
            try DSLFeatureDecomposer.decompose(invalidExtrude)
        }
    }
}
