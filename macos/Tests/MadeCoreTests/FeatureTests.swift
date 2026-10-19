import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct FeatureTests {
    @Test func testFeatureCreationAndDefaults() {
        let featureId = UUID()
        let feature = Feature(
            id: featureId,
            name: "Custom Feature",
            operation: .primitive(.box(BoxParams(width: 10, depth: 20, height: 30))),
            inputExpressions: ["width": FeatureExpression(value: 10.0)],
            outputSolidId: SolidId("custom-1")
        )

        #expect(feature.id == featureId)
        #expect(feature.name == "Custom Feature")
        #expect(feature.outputSolidId == SolidId("custom-1"))
        #expect(!feature.isSuppressed)
        #expect(feature.errorState == nil)
        #expect(feature.isVisible)
        #expect(!feature.isLocked)
        #expect(feature.inputExpressions["width"]?.value == 10.0)
    }

    @Test func testDefaultBoxAndCylinderPrimitiveFeatures() {
        let fixedBoxId = UUID()
        let box = Feature.makeBox(
            id: fixedBoxId,
            solidId: boxSolidId,
            params: BoxParams(width: 40, depth: 30, height: 20)
        )
        #expect(box.outputSolidId == boxSolidId)
        #expect(box.inputExpressions["width"]?.value == 40.0)
        #expect(box.inputExpressions["depth"]?.value == 30.0)
        #expect(box.inputExpressions["height"]?.value == 20.0)
        #expect(box.generatedTopology.count == 26)

        // 6 Faces
        let expectedFaces = ["face:top", "face:bottom", "face:front", "face:back", "face:left", "face:right"]
        for faceKey in expectedFaces {
            let ref = box.generatedTopology[faceKey]
            #expect(ref != nil, "Missing face \(faceKey)")
            #expect(ref?.elementType == .face)
            #expect(ref?.disambiguator?.surfaceOrCurveType == "plane")
        }
        #expect(box.generatedTopology["face:top"]?.disambiguator?.normal == SIMD3<Float>(0, 0, 1))

        // 12 Edges
        let expectedEdges = [
            "edge:top-front", "edge:top-back", "edge:top-left", "edge:top-right",
            "edge:bottom-front", "edge:bottom-back", "edge:bottom-left", "edge:bottom-right",
            "edge:front-left", "edge:front-right", "edge:back-left", "edge:back-right"
        ]
        for edgeKey in expectedEdges {
            let ref = box.generatedTopology[edgeKey]
            #expect(ref != nil, "Missing edge \(edgeKey)")
            #expect(ref?.elementType == .edge)
            #expect(ref?.disambiguator?.surfaceOrCurveType == "line")
        }

        // 8 Vertices
        let expectedVertices = [
            "vertex:top-front-left", "vertex:top-front-right", "vertex:top-back-left", "vertex:top-back-right",
            "vertex:bottom-front-left", "vertex:bottom-front-right", "vertex:bottom-back-left", "vertex:bottom-back-right"
        ]
        for vertKey in expectedVertices {
            let ref = box.generatedTopology[vertKey]
            #expect(ref != nil, "Missing vertex \(vertKey)")
            #expect(ref?.elementType == .vertex)
            #expect(ref?.disambiguator?.centroid != nil)
        }

        // Deterministic ID invariance under dimension change
        let resizedBox = Feature.makeBox(
            id: fixedBoxId,
            solidId: boxSolidId,
            params: BoxParams(width: 80, depth: 50, height: 35)
        )
        #expect(resizedBox.generatedTopology.count == 26)
        for key in box.generatedTopology.keys {
            #expect(box.generatedTopology[key]?.id == resizedBox.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }

        let fixedCylinderId = UUID()
        let cylinder = Feature.makeCylinder(
            id: fixedCylinderId,
            solidId: cylinderSolidId,
            params: CylinderParams(radius: 15, height: 40)
        )
        #expect(cylinder.outputSolidId == cylinderSolidId)
        #expect(cylinder.inputExpressions["radius"]?.value == 15.0)
        #expect(cylinder.inputExpressions["height"]?.value == 40.0)
        #expect(cylinder.generatedTopology.count == 8)

        #expect(cylinder.generatedTopology["face:top"]?.elementType == .face)
        #expect(cylinder.generatedTopology["face:bottom"]?.elementType == .face)
        #expect(cylinder.generatedTopology["face:side"]?.elementType == .face)
        #expect(cylinder.generatedTopology["face:side"]?.disambiguator?.surfaceOrCurveType == "cylinder")

        #expect(cylinder.generatedTopology["edge:top"]?.elementType == .edge)
        #expect(cylinder.generatedTopology["edge:bottom"]?.elementType == .edge)
        #expect(cylinder.generatedTopology["edge:seam"]?.elementType == .edge)
        #expect(cylinder.generatedTopology["edge:top"]?.disambiguator?.surfaceOrCurveType == "circle")
        #expect(cylinder.generatedTopology["edge:seam"]?.disambiguator?.surfaceOrCurveType == "line")

        #expect(cylinder.generatedTopology["vertex:top-seam"]?.elementType == .vertex)
        #expect(cylinder.generatedTopology["vertex:bottom-seam"]?.elementType == .vertex)

        // Cylinder deterministic ID invariance under dimension change
        let resizedCylinder = Feature.makeCylinder(
            id: fixedCylinderId,
            solidId: cylinderSolidId,
            params: CylinderParams(radius: 30, height: 80)
        )
        #expect(resizedCylinder.generatedTopology.count == 8)
        for key in cylinder.generatedTopology.keys {
            #expect(cylinder.generatedTopology[key]?.id == resizedCylinder.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }
    }

    @Test func testSphereConeTorusWedgePrimitiveFeatures() {
        // 1. Sphere
        let fixedSphereId = UUID()
        let sphereSolidId = SolidId("sphere-1")
        let sphere = Feature.makeSphere(
            id: fixedSphereId,
            solidId: sphereSolidId,
            params: SphereParams(radius: 15)
        )
        #expect(sphere.outputSolidId == sphereSolidId)
        #expect(sphere.inputExpressions["radius"]?.value == 15.0)
        #expect(sphere.generatedTopology.count == 4)
        #expect(sphere.generatedTopology["face:surface"]?.elementType == .face)
        #expect(sphere.generatedTopology["face:surface"]?.disambiguator?.surfaceOrCurveType == "sphere")
        #expect(sphere.generatedTopology["edge:seam"]?.elementType == .edge)
        #expect(sphere.generatedTopology["edge:seam"]?.disambiguator?.surfaceOrCurveType == "circle")
        #expect(sphere.generatedTopology["vertex:north-pole"]?.elementType == .vertex)
        #expect(sphere.generatedTopology["vertex:south-pole"]?.elementType == .vertex)

        let resizedSphere = Feature.makeSphere(
            id: fixedSphereId,
            solidId: sphereSolidId,
            params: SphereParams(radius: 35)
        )
        #expect(resizedSphere.generatedTopology.count == 4)
        for key in sphere.generatedTopology.keys {
            #expect(sphere.generatedTopology[key]?.id == resizedSphere.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }

        // 2. Cone
        let fixedConeId = UUID()
        let coneSolidId = SolidId("cone-1")
        // 2a. Pointy cone (topRadius == 0) -> 6 topological elements
        let cone = Feature.makeCone(
            id: fixedConeId,
            solidId: coneSolidId,
            params: ConeParams(bottomRadius: 15, topRadius: 0, height: 30)
        )
        #expect(cone.outputSolidId == coneSolidId)
        #expect(cone.inputExpressions["bottomRadius"]?.value == 15.0)
        #expect(cone.inputExpressions["topRadius"]?.value == 0.0)
        #expect(cone.inputExpressions["height"]?.value == 30.0)
        #expect(cone.generatedTopology.count == 6)
        #expect(cone.generatedTopology["face:bottom"]?.elementType == .face)
        #expect(cone.generatedTopology["face:side"]?.elementType == .face)
        #expect(cone.generatedTopology["face:side"]?.disambiguator?.surfaceOrCurveType == "cone")
        #expect(cone.generatedTopology["edge:bottom"]?.elementType == .edge)
        #expect(cone.generatedTopology["edge:seam"]?.elementType == .edge)
        #expect(cone.generatedTopology["vertex:apex"]?.elementType == .vertex)
        #expect(cone.generatedTopology["vertex:bottom-seam"]?.elementType == .vertex)

        let resizedCone = Feature.makeCone(
            id: fixedConeId,
            solidId: coneSolidId,
            params: ConeParams(bottomRadius: 30, topRadius: 0, height: 60)
        )
        #expect(resizedCone.generatedTopology.count == 6)
        for key in cone.generatedTopology.keys {
            #expect(cone.generatedTopology[key]?.id == resizedCone.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }

        // 2b. Frustum cone (topRadius > 0) -> 8 topological elements
        let frustumCone = Feature.makeCone(
            id: fixedConeId,
            solidId: coneSolidId,
            params: ConeParams(bottomRadius: 15, topRadius: 5, height: 30)
        )
        #expect(frustumCone.generatedTopology.count == 8)
        #expect(frustumCone.generatedTopology["face:top"]?.elementType == .face)
        #expect(frustumCone.generatedTopology["edge:top"]?.elementType == .edge)
        #expect(frustumCone.generatedTopology["vertex:top-seam"]?.elementType == .vertex)

        let resizedFrustumCone = Feature.makeCone(
            id: fixedConeId,
            solidId: coneSolidId,
            params: ConeParams(bottomRadius: 30, topRadius: 10, height: 60)
        )
        #expect(resizedFrustumCone.generatedTopology.count == 8)
        for key in frustumCone.generatedTopology.keys {
            #expect(frustumCone.generatedTopology[key]?.id == resizedFrustumCone.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }

        // 3. Torus
        let fixedTorusId = UUID()
        let torusSolidId = SolidId("torus-1")
        let torus = Feature.makeTorus(
            id: fixedTorusId,
            solidId: torusSolidId,
            params: TorusParams(majorRadius: 20, minorRadius: 5)
        )
        #expect(torus.outputSolidId == torusSolidId)
        #expect(torus.inputExpressions["majorRadius"]?.value == 20.0)
        #expect(torus.inputExpressions["minorRadius"]?.value == 5.0)
        #expect(torus.generatedTopology.count == 4)
        #expect(torus.generatedTopology["face:surface"]?.elementType == .face)
        #expect(torus.generatedTopology["face:surface"]?.disambiguator?.surfaceOrCurveType == "torus")
        #expect(torus.generatedTopology["edge:major-seam"]?.elementType == .edge)
        #expect(torus.generatedTopology["edge:minor-seam"]?.elementType == .edge)
        #expect(torus.generatedTopology["vertex:seam"]?.elementType == .vertex)

        let resizedTorus = Feature.makeTorus(
            id: fixedTorusId,
            solidId: torusSolidId,
            params: TorusParams(majorRadius: 40, minorRadius: 10)
        )
        #expect(resizedTorus.generatedTopology.count == 4)
        for key in torus.generatedTopology.keys {
            #expect(torus.generatedTopology[key]?.id == resizedTorus.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }

        // 4. Wedge
        let fixedWedgeId = UUID()
        let wedgeSolidId = SolidId("wedge-1")
        // 4a. Pointy wedge (topWidth == 0) -> 20 topological elements
        let wedge = Feature.makeWedge(
            id: fixedWedgeId,
            solidId: wedgeSolidId,
            params: WedgeParams(width: 30, depth: 30, height: 30, topWidth: 0)
        )
        #expect(wedge.outputSolidId == wedgeSolidId)
        #expect(wedge.inputExpressions["width"]?.value == 30.0)
        #expect(wedge.inputExpressions["depth"]?.value == 30.0)
        #expect(wedge.inputExpressions["height"]?.value == 30.0)
        #expect(wedge.inputExpressions["topWidth"]?.value == 0.0)
        #expect(wedge.generatedTopology.count == 20)
        #expect(wedge.generatedTopology["face:bottom"]?.elementType == .face)
        #expect(wedge.generatedTopology["face:front"]?.elementType == .face)
        #expect(wedge.generatedTopology["face:back"]?.elementType == .face)
        #expect(wedge.generatedTopology["face:left"]?.elementType == .face)
        #expect(wedge.generatedTopology["face:slanted"]?.elementType == .face)
        #expect(wedge.generatedTopology["edge:top-knife"]?.elementType == .edge)
        #expect(wedge.generatedTopology["vertex:top-front-knife"]?.elementType == .vertex)
        #expect(wedge.generatedTopology["vertex:top-back-knife"]?.elementType == .vertex)

        let resizedWedge = Feature.makeWedge(
            id: fixedWedgeId,
            solidId: wedgeSolidId,
            params: WedgeParams(width: 50, depth: 40, height: 45, topWidth: 0)
        )
        #expect(resizedWedge.generatedTopology.count == 20)
        for key in wedge.generatedTopology.keys {
            #expect(wedge.generatedTopology[key]?.id == resizedWedge.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }

        // 4b. Frustum wedge (topWidth > 0) -> 26 topological elements
        let frustumWedge = Feature.makeWedge(
            id: fixedWedgeId,
            solidId: wedgeSolidId,
            params: WedgeParams(width: 30, depth: 30, height: 30, topWidth: 10)
        )
        #expect(frustumWedge.generatedTopology.count == 26)
        #expect(frustumWedge.generatedTopology["face:top"]?.elementType == .face)
        #expect(frustumWedge.generatedTopology["edge:top-front"]?.elementType == .edge)

        let resizedFrustumWedge = Feature.makeWedge(
            id: fixedWedgeId,
            solidId: wedgeSolidId,
            params: WedgeParams(width: 50, depth: 40, height: 45, topWidth: 15)
        )
        #expect(resizedFrustumWedge.generatedTopology.count == 26)
        for key in frustumWedge.generatedTopology.keys {
            #expect(frustumWedge.generatedTopology[key]?.id == resizedFrustumWedge.generatedTopology[key]?.id, "UUID mismatch for \(key)")
        }
    }

    @Test func testSphereConeTorusWedgeSceneObjectConversions() {
        let sphereObj = SceneObject(id: SolidId("sph-1"), name: "Sphere", def: .sphere(SphereParams(radius: 12)))
        let sphereFeat = Feature(from: sphereObj)
        let backSphere = sphereFeat.toSceneObject()
        #expect(backSphere?.id == sphereObj.id)
        if case .sphere(let p) = backSphere?.def {
            #expect(p.radius == 12)
        } else {
            Issue.record("Expected sphere def")
        }

        let coneObj = SceneObject(id: SolidId("cn-1"), name: "Cone", def: .cone(ConeParams(bottomRadius: 10, topRadius: 2, height: 25)))
        let coneFeat = Feature(from: coneObj)
        let backCone = coneFeat.toSceneObject()
        #expect(backCone?.id == coneObj.id)
        if case .cone(let p) = backCone?.def {
            #expect(p.bottomRadius == 10)
            #expect(p.topRadius == 2)
            #expect(p.height == 25)
        } else {
            Issue.record("Expected cone def")
        }

        let torusObj = SceneObject(id: SolidId("tor-1"), name: "Torus", def: .torus(TorusParams(majorRadius: 25, minorRadius: 6)))
        let torusFeat = Feature(from: torusObj)
        let backTorus = torusFeat.toSceneObject()
        #expect(backTorus?.id == torusObj.id)
        if case .torus(let p) = backTorus?.def {
            #expect(p.majorRadius == 25)
            #expect(p.minorRadius == 6)
        } else {
            Issue.record("Expected torus def")
        }

        let wedgeObj = SceneObject(id: SolidId("wdg-1"), name: "Wedge", def: .wedge(WedgeParams(width: 20, depth: 15, height: 30, topWidth: 5)))
        let wedgeFeat = Feature(from: wedgeObj)
        let backWedge = wedgeFeat.toSceneObject()
        #expect(backWedge?.id == wedgeObj.id)
        if case .wedge(let p) = backWedge?.def {
            #expect(p.width == 20)
            #expect(p.depth == 15)
            #expect(p.height == 30)
            #expect(p.topWidth == 5)
        } else {
            Issue.record("Expected wedge def")
        }
    }

    @Test func testAllFeatureOperations() {
        let sketchEntity = SketchEntity(kind: "line", data: ["length": 25.0])
        let sketchData = SketchFeatureData(planeName: "XY", entities: [sketchEntity])
        let sketchFeature = Feature(name: "Sketch 1", operation: .sketch(sketchData))
        if case .sketch(let data) = sketchFeature.operation {
            #expect(data.planeName == "XY")
            #expect(data.entities.count == 1)
            #expect(data.entities[0].data["length"] == 25.0)
        } else {
            Issue.record("Expected sketch operation")
        }

        let extrudeData = ExtrudeFeatureData(
            sketchFeatureId: sketchFeature.id,
            distance: 50.0,
            isSymmetric: true,
            draftAngle: 1.5
        )
        let extrudeFeature = Feature(name: "Extrude 1", operation: .extrude(extrudeData))
        if case .extrude(let data) = extrudeFeature.operation {
            #expect(data.sketchFeatureId == sketchFeature.id)
            #expect(data.distance == 50.0)
            #expect(data.isSymmetric)
            #expect(data.draftAngle == 1.5)
        } else {
            Issue.record("Expected extrude operation")
        }

        let booleanData = BooleanFeatureData(
            op: .subtract,
            targetSolidId: boxSolidId,
            toolSolidId: cylinderSolidId
        )
        let booleanFeature = Feature(name: "Boolean 1", operation: .boolean(booleanData))
        if case .boolean(let data) = booleanFeature.operation {
            #expect(data.op == .subtract)
            #expect(data.targetSolidId == boxSolidId)
            #expect(data.toolSolidId == cylinderSolidId)
        } else {
            Issue.record("Expected boolean operation")
        }

        let partData = PartFeatureData(url: URL(fileURLWithPath: "/parts/bracket.part.ts"), shape: nil)
        let partFeature = Feature(name: "Part 1", operation: .part(partData))
        if case .part(let data) = partFeature.operation {
            #expect(data.url.lastPathComponent == "bracket.part.ts")
            #expect(data.shape == nil)
        } else {
            Issue.record("Expected part operation")
        }

        let importedData = ImportedFeatureData(name: "model.step", data: Data([10, 20, 30]))
        let importedFeature = Feature(name: "Imported 1", operation: .imported(importedData))
        if case .imported(let data) = importedFeature.operation {
            #expect(data.name == "model.step")
            #expect(data.data == Data([10, 20, 30]))
        } else {
            Issue.record("Expected imported operation")
        }
    }

    @Test func testFeatureExpressionStorageAndEvaluation() {
        let exprWithFormula = FeatureExpression(formula: "width * 2", value: 80.0)
        #expect(exprWithFormula.formula == "width * 2")
        #expect(exprWithFormula.value == 80.0)

        let exprFromDouble = FeatureExpression(value: 42.5)
        #expect(exprFromDouble.formula == "42.5")
        #expect(exprFromDouble.value == 42.5)

        let exprFromFloat = FeatureExpression(value: Float(15.25))
        #expect(exprFromFloat.value == Double(Float(15.25)))
    }

    @Test func testTypedTopologicalReferences() {
        let sourceId = UUID()
        let step = HistoryStep(kind: .generated, label: "face:top", sourceIndex: 0)
        let sig = GeometricSignature(
            surfaceOrCurveType: "plane",
            normal: SIMD3<Float>(0, 0, 1),
            centroid: SIMD3<Float>(0, 0, 10),
            areaOrLength: 1200.0
        )
        let ref = TopologicalReference(
            sourceFeatureId: sourceId,
            elementType: .face,
            historyPath: [step],
            disambiguator: sig
        )

        #expect(ref.sourceFeatureId == sourceId)
        #expect(ref.elementType == .face)
        #expect(ref.historyPath.count == 1)
        #expect(ref.historyPath[0].kind == .generated)
        #expect(ref.disambiguator?.normal == SIMD3<Float>(0, 0, 1))
        #expect(ref.disambiguator?.areaOrLength == 1200.0)
    }

    @Test func testSuppressionExcludesFromProjectedObjects() {
        let doc = DocumentModel()
        #expect(doc.features.count == 2)
        #expect(doc.objects.count == 2)

        let boxFeature = doc.features[0]
        #expect(boxFeature.outputSolidId == boxSolidId)

        let suppressResult = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: true)
        #expect(suppressResult == .success(()))
        #expect(doc.features[0].isSuppressed)
        #expect(doc.objects.count == 1)
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
        #expect(doc.objects.first?.id == cylinderSolidId)

        let unsuppressResult = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: false)
        #expect(unsuppressResult == .success(()))
        #expect(!doc.features[0].isSuppressed)
        #expect(doc.objects.count == 2)
        #expect(doc.objects.contains(where: { $0.id == boxSolidId }))
    }

    @Test func testUndoRedoFeatureSuppression() {
        let doc = DocumentModel()
        let boxFeature = doc.features[0]

        _ = doc.setFeatureSuppressed(id: boxFeature.id, isSuppressed: true)
        #expect(doc.objects.count == 1)
        #expect(doc.canUndo)
        #expect(doc.undoActionTitle == "Undo Suppress Feature")

        doc.undo()
        #expect(doc.objects.count == 2)
        #expect(doc.canRedo)
        #expect(doc.redoActionTitle == "Redo Suppress Feature")

        doc.redo()
        #expect(doc.objects.count == 1)
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
    }

    @Test func testFeatureErrorStateRecordingAndClearing() {
        let doc = DocumentModel()
        let boxFeature = doc.features[0]

        let error = FeatureErrorState(code: "geometry-failed", message: "Non-manifold boolean result")
        doc.setFeatureError(id: boxFeature.id, error: error)

        #expect(doc.features[0].errorState?.code == "geometry-failed")
        #expect(doc.features[0].errorState?.message == "Non-manifold boolean result")
        #expect(doc.features[0].errorState?.severity == .error)

        doc.setFeatureError(id: boxFeature.id, error: nil)
        #expect(doc.features[0].errorState == nil)
    }

    @Test func testFeatureErrorSeverityDefaultAndCustomValues() {
        let defaultError = FeatureErrorState(code: "invalid-params", message: "Negative width")
        #expect(defaultError.severity == .error)

        let customWarning = FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
        #expect(customWarning.severity == .warning)
        #expect(customWarning.code == "parent-failed")
        #expect(customWarning.message == "parent failed")
    }

    @Test func testFeatureErrorStateBackwardCompatibleDecoding() throws {
        let legacyJSON = """
        {
          "code": "legacy-error",
          "message": "Legacy failure message"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FeatureErrorState.self, from: legacyJSON)
        #expect(decoded.code == "legacy-error")
        #expect(decoded.message == "Legacy failure message")
        #expect(decoded.severity == .error)
    }

    @Test func testFeatureErrorStateCodableRoundTripWithWarning() throws {
        let state = FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(state)
        let decoded = try decoder.decode(FeatureErrorState.self, from: data)

        #expect(decoded.code == "parent-failed")
        #expect(decoded.message == "parent failed")
        #expect(decoded.severity == .warning)
    }

    @Test func testJSONSerializationRoundTrip() throws {
        let boxFeature = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 40, depth: 30, height: 20)
        )

        let encoder = DocumentModelCoder.makeJSONEncoder()
        let decoder = DocumentModelCoder.makeJSONDecoder()

        let data = try encoder.encode(boxFeature)
        let decoded = try decoder.decode(Feature.self, from: data)

        #expect(decoded.id == boxFeature.id)
        #expect(decoded.name == boxFeature.name)
        #expect(decoded.outputSolidId == boxFeature.outputSolidId)
        #expect(decoded.inputExpressions == boxFeature.inputExpressions)
        #expect(decoded.generatedTopology.count == boxFeature.generatedTopology.count)

        // DocumentData round trip
        let doc = DocumentModel()
        let encodedDoc = try DocumentModelCoder.encode(document: doc)
        let decodedData = try DocumentModelCoder.decode(from: encodedDoc)

        #expect(decodedData.features?.count == 2)
        #expect(decodedData.objects.count == 2)
        #expect(decodedData.features?[0].outputSolidId == boxSolidId)
        #expect(decodedData.features?[1].outputSolidId == cylinderSolidId)
    }

    @Test func testLegacyDocumentDataSynthesizesFeatures() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "def": {
                "kind": "box",
                "params": {
                  "width": 30.0,
                  "depth": 20.0,
                  "height": 10.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyJSON)
        #expect(decoded.objects.count == 1)
        #expect(decoded.features?.count == 1)

        let synthesized = try #require(decoded.features?.first)
        #expect(synthesized.outputSolidId == boxSolidId)
        #expect(synthesized.inputExpressions["width"]?.value == 30.0)
        #expect(synthesized.inputExpressions["depth"]?.value == 20.0)
        #expect(synthesized.inputExpressions["height"]?.value == 10.0)
    }

    @Test func testBooleanFeatureDataKeepToolSerializationAndBackwardCompatibility() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // With keepTool: true
        let dataWithKeepTool = BooleanFeatureData(op: .union, targetSolidId: SolidId("a"), toolSolidId: SolidId("b"), keepTool: true)
        let encoded = try encoder.encode(dataWithKeepTool)
        let decoded = try decoder.decode(BooleanFeatureData.self, from: encoded)
        #expect(decoded.op == .union)
        #expect(decoded.targetSolidId == SolidId("a"))
        #expect(decoded.toolSolidId == SolidId("b"))
        #expect(decoded.keepTool == true)

        // Legacy JSON without keepTool key defaults to false
        let legacyJSON = """
        {
          "op": "subtract",
          "targetSolidId": "box-1",
          "toolSolidId": "cylinder-1"
        }
        """.data(using: .utf8)!
        let legacyDecoded = try decoder.decode(BooleanFeatureData.self, from: legacyJSON)
        #expect(legacyDecoded.op == .subtract)
        #expect(legacyDecoded.targetSolidId == SolidId("box-1"))
        #expect(legacyDecoded.toolSolidId == SolidId("cylinder-1"))
        #expect(legacyDecoded.keepTool == false)
    }

    // MARK: - Rollback Marker (BL-FND-05)

    @Test func testRollbackMarkerExcludesFromProjectedObjects() {
        let doc = DocumentModel()
        #expect(doc.features.count == 2)
        #expect(doc.activeFeatures.count == 2)
        #expect(doc.objects.count == 2)
        #expect(!doc.isRolledBack)
        #expect(doc.rollbackIndex == nil)
        #expect(doc.effectiveRollbackIndex == 2)

        // Roll back to 1
        doc.setRollbackIndex(1)
        #expect(doc.isRolledBack)
        #expect(doc.rollbackIndex == 1)
        #expect(doc.effectiveRollbackIndex == 1)
        #expect(doc.activeFeatures.count == 1)
        #expect(doc.rolledBackFeatures.count == 1)
        #expect(doc.objects.count == 1)
        #expect(doc.objects.first?.id == boxSolidId)

        // Roll back to 0
        doc.setRollbackIndex(0)
        #expect(doc.isRolledBack)
        #expect(doc.rollbackIndex == 0)
        #expect(doc.effectiveRollbackIndex == 0)
        #expect(doc.activeFeatures.isEmpty)
        #expect(doc.rolledBackFeatures.count == 2)
        #expect(doc.objects.isEmpty)
        #expect(doc.selectedId == nil)
    }

    @Test func testRollbackMarkerClamping() {
        let doc = DocumentModel()
        #expect(doc.features.count == 2)

        // Negative index clamps to 0
        doc.setRollbackIndex(-5)
        #expect(doc.rollbackIndex == 0)
        #expect(doc.isRolledBack)

        // Index >= count normalizes to nil (unrolled)
        doc.setRollbackIndex(2)
        #expect(doc.rollbackIndex == nil)
        #expect(!doc.isRolledBack)

        doc.setRollbackIndex(100)
        #expect(doc.rollbackIndex == nil)
        #expect(!doc.isRolledBack)
    }

    @Test func testRollbackDataSerializationRoundTrip() throws {
        let f1 = Feature.makeBox(solidId: boxSolidId, params: BoxParams(width: 20, depth: 20, height: 20))
        let f2 = Feature.makeCylinder(solidId: cylinderSolidId, params: CylinderParams(radius: 10, height: 30))
        let docData = DocumentData(
            schemaVersion: 1,
            features: [f1, f2],
            selectedId: boxSolidId,
            rollbackIndex: 1
        )

        let encoded = try DocumentModelCoder.encode(docData)
        let decoded = try DocumentModelCoder.decode(from: encoded)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.rollbackIndex == 1)
        #expect(decoded.features?.count == 2)
        #expect(decoded.objects.count == 1)
        #expect(decoded.objects.first?.id == boxSolidId)
    }

    @Test func testRollbackDataBackwardCompatibility() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "objects": [
            {
              "id": "box-1",
              "def": {
                "kind": "box",
                "params": {
                  "width": 30.0,
                  "depth": 20.0,
                  "height": 10.0
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: legacyJSON)
        #expect(decoded.rollbackIndex == nil)
        #expect(decoded.objects.count == 1)
        #expect(decoded.features?.count == 1)
    }

    // MARK: - Body Operation & Target Body Tests (BL-FND-12)

    @Test func testFeatureBodyOperationAndTargetDefaults() {
        let f = Feature.makeBox(solidId: boxSolidId, params: BoxParams(width: 10, depth: 10, height: 10))
        #expect(f.bodyOperation == .create)
        #expect(f.targetBodyId == nil)

        let fCut = Feature.makeCylinder(
            solidId: SolidId("cut-1"),
            params: CylinderParams(radius: 5, height: 10),
            bodyOperation: .cut,
            targetBodyId: boxSolidId
        )
        #expect(fCut.bodyOperation == .cut)
        #expect(fCut.targetBodyId == boxSolidId)
    }

    @Test func testFeatureBodyOperationSerializationRoundTrip() throws {
        let feature = Feature(
            name: "Boolean Add",
            operation: .primitive(.box(BoxParams(width: 20, depth: 20, height: 20))),
            outputSolidId: SolidId("box-add"),
            bodyOperation: .add,
            targetBodyId: SolidId("target-solid-1")
        )

        let encoder = DocumentModelCoder.makeJSONEncoder()
        let data = try encoder.encode(feature)
        let decoder = DocumentModelCoder.makeJSONDecoder()
        let decoded = try decoder.decode(Feature.self, from: data)

        #expect(decoded.bodyOperation == .add)
        #expect(decoded.targetBodyId == SolidId("target-solid-1"))
        #expect(decoded.name == "Boolean Add")
    }

    @Test func testFeatureLegacyPayloadDecodesWithDefaultBodyOperationAndNilTargetBodyId() throws {
        let boxFeature = Feature.makeBox(
            solidId: boxSolidId,
            params: BoxParams(width: 40, depth: 30, height: 20)
        )
        let encoder = DocumentModelCoder.makeJSONEncoder()
        let data = try encoder.encode(boxFeature)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "bodyOperation")
        dict.removeValue(forKey: "targetBodyId")
        let legacyData = try JSONSerialization.data(withJSONObject: dict)

        let decoder = DocumentModelCoder.makeJSONDecoder()
        let decoded = try decoder.decode(Feature.self, from: legacyData)

        #expect(decoded.bodyOperation == .create)
        #expect(decoded.targetBodyId == nil)
        #expect(decoded.outputSolidId == boxSolidId)
        #expect(decoded.name == boxFeature.name)
    }

    // MARK: - Issue #561 Golden Fixture and Explicit CodingKeys Tests

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/document.json")
    }

    static func makeCanonicalGoldenDocumentData() -> DocumentData {
        let features: [Feature] = [
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Box Primitive",
                operation: .primitive(.box(BoxParams(width: 40, depth: 30, height: 20)))
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Cylinder Primitive",
                operation: .primitive(.cylinder(CylinderParams(radius: 15, height: 40)))
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Sphere Primitive",
                operation: .primitive(.sphere(SphereParams(radius: 25)))
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                name: "Cone Primitive",
                operation: .primitive(.cone(ConeParams(bottomRadius: 20, topRadius: 5, height: 35)))
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                name: "Torus Primitive",
                operation: .primitive(.torus(TorusParams(majorRadius: 30, minorRadius: 8)))
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
                name: "Wedge Primitive",
                operation: .primitive(.wedge(WedgeParams(width: 30, depth: 25, height: 20, topWidth: 10)))
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
                name: "Sketch Feature",
                operation: .sketch(
                    SketchFeatureData(
                        planeName: "XY",
                        entities: [
                            SketchEntity(
                                id: UUID(uuidString: "00000000-0000-0000-0001-000000000001")!,
                                kind: "line",
                                data: ["length": 25.0]
                            )
                        ]
                    )
                )
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
                name: "Extrude Feature",
                operation: .extrude(
                    ExtrudeFeatureData(
                        distance: 50.0,
                        isSymmetric: true,
                        draftAngle: 1.5
                    )
                )
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
                name: "Boolean Feature",
                operation: .boolean(
                    BooleanFeatureData(
                        op: .subtract,
                        targetSolidId: SolidId("solid-a"),
                        toolSolidId: SolidId("solid-b")
                    )
                )
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                name: "Part Feature",
                operation: .part(
                    PartFeatureData(url: URL(fileURLWithPath: "/parts/bracket.part.ts"))
                )
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                name: "Imported Feature",
                operation: .imported(
                    ImportedFeatureData(name: "model.step", data: Data([10, 20, 30]))
                )
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                name: "Datum Plane Feature",
                operation: .datumPlane(
                    DatumPlaneFeatureData(mode: .origin, originPreset: "XY", offsetDistance: 10.0)
                )
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
                name: "Datum Axis Feature",
                operation: .datumAxis(
                    DatumAxisFeatureData(mode: .preset, presetName: "Z")
                )
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
                name: "Datum Point Feature",
                operation: .datumPoint(
                    DatumPointFeatureData(mode: .coordinates)
                )
            ),
            Feature(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
                name: "Datum Coordinate System Feature",
                operation: .datumCoordinateSystem(
                    DatumCoordinateSystemFeatureData(mode: .originAndAxes)
                )
            )
        ]
        return DocumentData(schemaVersion: 1, features: features, objects: [])
    }

    static func ensureFixtureExists() throws {
        let fixtureURL = Self.fixtureURL
        if !FileManager.default.fileExists(atPath: fixtureURL.path) {
            try FileManager.default.createDirectory(at: fixtureURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let canonical = makeCanonicalGoldenDocumentData()
            let canonicalData = try DocumentModelCoder.encode(canonical)
            try canonicalData.write(to: fixtureURL)
        }
    }

    @Test func testFeatureOperationAndPrimitiveCodingKeysGoldenFixture() throws {
        try Self.ensureFixtureExists()
        let fixtureURL = Self.fixtureURL
        #expect(FileManager.default.fileExists(atPath: fixtureURL.path), "Fixture must exist at \(fixtureURL.path)")
        let data = try Data(contentsOf: fixtureURL)
        let decoded = try DocumentModelCoder.decode(from: data)
        let features = try #require(decoded.features)
        #expect(features.count == 15)

        // 1. Primitive Box
        guard case .primitive(.box(let box)) = features[0].operation else {
            Issue.record("Expected .primitive(.box)")
            return
        }
        #expect(box.width == 40 && box.depth == 30 && box.height == 20)

        // 2. Primitive Cylinder
        guard case .primitive(.cylinder(let cylinder)) = features[1].operation else {
            Issue.record("Expected .primitive(.cylinder)")
            return
        }
        #expect(cylinder.radius == 15 && cylinder.height == 40)

        // 3. Primitive Sphere
        guard case .primitive(.sphere(let sphere)) = features[2].operation else {
            Issue.record("Expected .primitive(.sphere)")
            return
        }
        #expect(sphere.radius == 25)

        // 4. Primitive Cone
        guard case .primitive(.cone(let cone)) = features[3].operation else {
            Issue.record("Expected .primitive(.cone)")
            return
        }
        #expect(cone.bottomRadius == 20 && cone.topRadius == 5 && cone.height == 35)

        // 5. Primitive Torus
        guard case .primitive(.torus(let torus)) = features[4].operation else {
            Issue.record("Expected .primitive(.torus)")
            return
        }
        #expect(torus.majorRadius == 30 && torus.minorRadius == 8)

        // 6. Primitive Wedge
        guard case .primitive(.wedge(let wedge)) = features[5].operation else {
            Issue.record("Expected .primitive(.wedge)")
            return
        }
        #expect(wedge.width == 30 && wedge.depth == 25 && wedge.height == 20 && wedge.topWidth == 10)

        // 7. Sketch
        guard case .sketch(let sketch) = features[6].operation else {
            Issue.record("Expected .sketch")
            return
        }
        #expect(sketch.planeName == "XY")
        #expect(sketch.entities.count == 1)
        #expect(sketch.entities.first?.kind == "line")

        // 8. Extrude
        guard case .extrude(let extrude) = features[7].operation else {
            Issue.record("Expected .extrude")
            return
        }
        #expect(extrude.distance == 50.0 && extrude.isSymmetric && extrude.draftAngle == 1.5)

        // 9. Boolean
        guard case .boolean(let boolean) = features[8].operation else {
            Issue.record("Expected .boolean")
            return
        }
        #expect(boolean.op == .subtract && boolean.targetSolidId == SolidId("solid-a") && boolean.toolSolidId == SolidId("solid-b"))

        // 10. Part
        guard case .part(let part) = features[9].operation else {
            Issue.record("Expected .part")
            return
        }
        #expect(part.url.lastPathComponent == "bracket.part.ts")

        // 11. Imported
        guard case .imported(let imported) = features[10].operation else {
            Issue.record("Expected .imported")
            return
        }
        #expect(imported.name == "model.step")
        #expect(imported.data == Data([10, 20, 30]))

        // 12. Datum Plane
        guard case .datumPlane(let datumPlane) = features[11].operation else {
            Issue.record("Expected .datumPlane")
            return
        }
        #expect(datumPlane.mode == .origin && datumPlane.originPreset == "XY" && datumPlane.offsetDistance == 10.0)

        // 13. Datum Axis
        guard case .datumAxis(let datumAxis) = features[12].operation else {
            Issue.record("Expected .datumAxis")
            return
        }
        #expect(datumAxis.mode == .preset && datumAxis.presetName == "Z")

        // 14. Datum Point
        guard case .datumPoint(let datumPoint) = features[13].operation else {
            Issue.record("Expected .datumPoint")
            return
        }
        #expect(datumPoint.mode == .coordinates)

        // 15. Datum Coordinate System
        guard case .datumCoordinateSystem(let dcs) = features[14].operation else {
            Issue.record("Expected .datumCoordinateSystem")
            return
        }
        #expect(dcs.mode == .originAndAxes)
    }

    @Test func testFeatureOperationAndPrimitiveCodingKeysReencodeInvariance() throws {
        try Self.ensureFixtureExists()
        let fixtureURL = Self.fixtureURL
        let originalData = try Data(contentsOf: fixtureURL)
        let decoded = try DocumentModelCoder.decode(from: originalData)
        let reencodedData = try DocumentModelCoder.encode(decoded)

        let originalString = String(decoding: originalData, as: UTF8.self)
        let reencodedString = String(decoding: reencodedData, as: UTF8.self)
        #expect(reencodedString == originalString)
    }

    @Test func testFeatureOperationUnknownKeyThrowsDataCorrupted() throws {
        try Self.ensureFixtureExists()
        let fixtureURL = Self.fixtureURL
        let originalData = try Data(contentsOf: fixtureURL)
        var jsonString = String(decoding: originalData, as: UTF8.self)
        #expect(jsonString.contains("\"primitive\" : {"))
        jsonString = jsonString.replacingOccurrences(of: "\"primitive\" : {", with: "\"primitiveRenamed\" : {")
        let mutatedData = Data(jsonString.utf8)

        #expect(throws: DecodingError.self) {
            try DocumentModelCoder.decode(from: mutatedData)
        }
        do {
            _ = try DocumentModelCoder.decode(from: mutatedData)
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("Unknown FeatureOperation key"))
        } catch {
            Issue.record("Expected DecodingError.dataCorrupted, got \(error)")
        }
    }

    @Test func testPrimitiveFeatureDataUnknownKeyThrowsDataCorrupted() throws {
        try Self.ensureFixtureExists()
        let fixtureURL = Self.fixtureURL
        let originalData = try Data(contentsOf: fixtureURL)
        var jsonString = String(decoding: originalData, as: UTF8.self)
        #expect(jsonString.contains("\"box\" : {"))
        jsonString = jsonString.replacingOccurrences(of: "\"box\" : {", with: "\"boxRenamed\" : {")
        let mutatedData = Data(jsonString.utf8)

        #expect(throws: DecodingError.self) {
            try DocumentModelCoder.decode(from: mutatedData)
        }
        do {
            _ = try DocumentModelCoder.decode(from: mutatedData)
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription.contains("Unknown PrimitiveFeatureData key"))
        } catch {
            Issue.record("Expected DecodingError.dataCorrupted, got \(error)")
        }
    }

    @Test func testFeatureOperationDirectPayloadCompatibility() throws {
        let directJSON = """
        {
          "schemaVersion": 1,
          "objects": [],
          "features": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "Direct Box",
              "operation": {
                "primitive": {
                  "box": {
                    "width": 100.0,
                    "depth": 50.0,
                    "height": 25.0
                  }
                }
              }
            },
            {
              "id": "00000000-0000-0000-0000-000000000002",
              "name": "Direct Extrude",
              "operation": {
                "extrude": {
                  "distance": 75.0,
                  "draftAngle": 0.0,
                  "isSymmetric": false
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try DocumentModelCoder.decode(from: directJSON)
        let features = try #require(decoded.features)
        #expect(features.count == 2)

        guard case .primitive(.box(let box)) = features[0].operation else {
            Issue.record("Expected direct box primitive")
            return
        }
        #expect(box.width == 100.0 && box.depth == 50.0 && box.height == 25.0)

        guard case .extrude(let extrude) = features[1].operation else {
            Issue.record("Expected direct extrude operation")
            return
        }
        #expect(extrude.distance == 75.0 && !extrude.isSymmetric)
    }

    @Test func testPartAndImportedFeatureDataPackageRelativeCoding() throws {
        let packageDir = URL(fileURLWithPath: "/tmp/SampleProject.made")
        let partFeature = Feature(
            name: "Bracket Part",
            operation: .part(PartFeatureData(url: URL(fileURLWithPath: "/Users/alice/Code/bracket.part.ts")))
        )
        let importedFeature = Feature(
            name: "Housing STEP",
            operation: .imported(ImportedFeatureData(name: "Housing", sourceURL: URL(fileURLWithPath: "/Users/alice/Downloads/housing.step"), data: nil))
        )

        let doc = DocumentData(features: [partFeature, importedFeature])
        let encodedData = try DocumentModelCoder.encode(doc, packageURL: packageDir)
        let encodedString = String(decoding: encodedData, as: UTF8.self)

        // Must encode relative paths, never leaking absolute local paths
        #expect(encodedString.contains("\"url\" : \"parts/bracket.part.ts\""))
        #expect(encodedString.contains("\"sourceURL\" : \"assets/housing.step\""))
        #expect(!encodedString.contains("/Users/alice"))

        // Decode with packageURL resolves to package directory
        let decodedWithPackage = try DocumentModelCoder.decode(from: encodedData, packageURL: packageDir)
        let featsWithPackage = try #require(decodedWithPackage.features)
        guard case .part(let partResolved) = featsWithPackage[0].operation else {
            Issue.record("Expected .part")
            return
        }
        #expect(partResolved.url == packageDir.appendingPathComponent("parts/bracket.part.ts"))

        guard case .imported(let impResolved) = featsWithPackage[1].operation else {
            Issue.record("Expected .imported")
            return
        }
        #expect(impResolved.sourceURL == packageDir.appendingPathComponent("assets/housing.step"))

        // Decode without packageURL keeps relative path
        let decodedWithoutPackage = try DocumentModelCoder.decode(from: encodedData)
        let featsWithoutPackage = try #require(decodedWithoutPackage.features)
        guard case .part(let partRelative) = featsWithoutPackage[0].operation else {
            Issue.record("Expected .part")
            return
        }
        #expect(partRelative.url.lastPathComponent == "bracket.part.ts")

        // Legacy file:// URL decoding backward compatibility
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "features": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "Legacy Part",
              "operation": {
                "part": {
                  "_0": {
                    "url": "file:///old/path/parts/bracket.part.ts"
                  }
                }
              }
            },
            {
              "id": "00000000-0000-0000-0000-000000000002",
              "name": "Legacy Imported",
              "operation": {
                "imported": {
                  "_0": {
                    "name": "model.step",
                    "sourceURL": "file:///old/path/assets/model.step"
                  }
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let legacyDecoded = try DocumentModelCoder.decode(from: legacyJSON, packageURL: packageDir)
        let legacyFeatures = try #require(legacyDecoded.features)
        guard case .part(let legacyPart) = legacyFeatures[0].operation else {
            Issue.record("Expected legacy .part")
            return
        }
        #expect(legacyPart.url == packageDir.appendingPathComponent("parts/bracket.part.ts"))

        guard case .imported(let legacyImported) = legacyFeatures[1].operation else {
            Issue.record("Expected legacy .imported")
            return
        }
        #expect(legacyImported.sourceURL == packageDir.appendingPathComponent("assets/model.step"))
    }
}
