import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct DrawingAssociativityTests {

    @Test func testDrawingViewsUpdateWhenFeaturesChange() {
        let doc = DocumentModel()
        let sheet = doc.addSheet()
        let view = DrawingView(name: "Front View", standardView: .front)
        _ = doc.addDrawingView(view, to: sheet.id)

        doc.updateDrawingAssociativity()
        let initialHLR = doc.activeSheet?.views.first?.cachedHLR
        #expect(initialHLR != nil)
        #expect(!initialHLR!.edges.isEmpty)

        // Adding a 3D feature regenerates scene objects and triggers associativity sync
        let newBox = Feature.makeBox(
            solidId: ObjectId("extra-box"),
            name: "Extra Box",
            params: BoxParams(width: 80, depth: 80, height: 80)
        )
        doc.addFeature(newBox)

        let updatedHLR = doc.activeSheet?.views.first?.cachedHLR
        #expect(updatedHLR != nil)
        #expect(updatedHLR != initialHLR)
    }

    @Test func testHoleCalloutUpdatesWhenHoleWizardFeatureChanges() {
        let doc = DocumentModel()
        let sheet = doc.addSheet()
        let view = DrawingView(name: "Top View", standardView: .top)
        _ = doc.addDrawingView(view, to: sheet.id)

        let holeParams = HoleParams(
            targetSolidId: SolidId("part-1"),
            faceReference: TopologicalReference(sourceFeatureId: UUID(), elementType: .face),
            points: [SIMD2(0, 0), SIMD2(10, 0)],
            holeType: .counterbore,
            diameter: 6.0,
            depth: 15.0,
            isThrough: false,
            counterboreDiameter: 10.0,
            counterboreDepth: 3.0
        )
        let holeFeature = Feature(name: "Counterbore Hole", operation: .hole(holeParams))
        doc.addFeature(holeFeature)

        let calloutData = HoleCalloutAnnotationData(
            anchorPointMM: SIMD2(10, 10),
            elbowPointMM: SIMD2(25, 25),
            holeParams: holeParams,
            holeCount: 2
        )
        let annotation = DrawingAnnotation(
            name: "Hole Callout 1",
            viewId: view.id,
            data: .holeCallout(calloutData),
            sourceFeatureId: holeFeature.id,
            attachment: DrawingAnnotationAttachment(featureId: holeFeature.id)
        )
        _ = doc.addDrawingAnnotation(annotation, to: sheet.id)

        // Initial formatted check
        if case .holeCallout(let d) = doc.activeSheet?.annotations.first?.data {
            #expect(d.diameter == 6.0)
            #expect(d.depth == 15.0)
            #expect(d.counterboreDiameter == 10.0)
            #expect(d.counterboreDepth == 3.0)
            #expect(d.holeCount == 2)
            #expect(d.formattedCalloutLines.contains(where: { $0.contains("2x") }))
        } else {
            Issue.record("Expected holeCallout annotation data")
        }

        // Modify hole parameters in 3D timeline
        var updatedParams = holeParams
        updatedParams.diameter = 8.5
        updatedParams.depth = 22.0
        updatedParams.counterboreDiameter = 14.0
        updatedParams.counterboreDepth = 5.0
        updatedParams.points = [SIMD2(0, 0), SIMD2(10, 0), SIMD2(20, 0)]
        var updatedFeature = holeFeature
        updatedFeature.operation = .hole(updatedParams)
        _ = doc.updateFeature(updatedFeature)

        // Verify annotation updated automatically
        guard let updatedAnnotation = doc.activeSheet?.annotations.first,
              case .holeCallout(let updatedData) = updatedAnnotation.data else {
            Issue.record("Missing updated callout data")
            return
        }
        #expect(!updatedAnnotation.isDangling)
        #expect(updatedData.diameter == 8.5)
        #expect(updatedData.depth == 22.0)
        #expect(updatedData.counterboreDiameter == 14.0)
        #expect(updatedData.counterboreDepth == 5.0)
        #expect(updatedData.holeCount == 3)
        #expect(updatedData.formattedCalloutLines.contains(where: { $0.contains("3x") }))
    }

    @Test func testAnnotationFlaggedAsDanglingWhenFeatureSuppressed() {
        let doc = DocumentModel()
        let sheet = doc.addSheet()
        let view = DrawingView(name: "Front View", standardView: .front)
        _ = doc.addDrawingView(view, to: sheet.id)

        let holeParams = HoleParams(
            targetSolidId: SolidId("part-1"),
            faceReference: TopologicalReference(sourceFeatureId: UUID(), elementType: .face),
            diameter: 5.0,
            depth: 10.0
        )
        let holeFeature = Feature(name: "Hole", operation: .hole(holeParams))
        doc.addFeature(holeFeature)

        let callout = DrawingAnnotation(
            name: "Callout",
            viewId: view.id,
            data: .holeCallout(HoleCalloutAnnotationData(anchorPointMM: .zero, elbowPointMM: SIMD2(10, 10), holeParams: holeParams)),
            sourceFeatureId: holeFeature.id
        )
        _ = doc.addDrawingAnnotation(callout, to: sheet.id)
        #expect(doc.activeSheet?.annotations.first?.isDangling == false)

        // Suppress feature
        _ = doc.setFeatureSuppressed(id: holeFeature.id, isSuppressed: true)
        #expect(doc.activeSheet?.annotations.first?.isDangling == true)
    }

    @Test func testAnnotationRecoversWhenFeatureUnsuppressed() {
        let doc = DocumentModel()
        let sheet = doc.addSheet()
        let view = DrawingView(name: "Front View", standardView: .front)
        _ = doc.addDrawingView(view, to: sheet.id)

        let holeParams = HoleParams(
            targetSolidId: SolidId("part-1"),
            faceReference: TopologicalReference(sourceFeatureId: UUID(), elementType: .face),
            diameter: 5.0,
            depth: 10.0
        )
        let holeFeature = Feature(name: "Hole", operation: .hole(holeParams))
        doc.addFeature(holeFeature)

        let callout = DrawingAnnotation(
            name: "Callout",
            viewId: view.id,
            data: .holeCallout(HoleCalloutAnnotationData(anchorPointMM: .zero, elbowPointMM: SIMD2(10, 10), holeParams: holeParams)),
            sourceFeatureId: holeFeature.id
        )
        _ = doc.addDrawingAnnotation(callout, to: sheet.id)

        // Suppress
        _ = doc.setFeatureSuppressed(id: holeFeature.id, isSuppressed: true)
        #expect(doc.activeSheet?.annotations.first?.isDangling == true)

        // Unsuppress
        _ = doc.setFeatureSuppressed(id: holeFeature.id, isSuppressed: false)
        #expect(doc.activeSheet?.annotations.first?.isDangling == false)
    }

    @Test func testAnnotationFlaggedAsDanglingWhenFeatureDeleted() {
        let doc = DocumentModel()
        let sheet = doc.addSheet()
        let view = DrawingView(name: "Front View", standardView: .front)
        _ = doc.addDrawingView(view, to: sheet.id)

        let holeParams = HoleParams(
            targetSolidId: SolidId("part-1"),
            faceReference: TopologicalReference(sourceFeatureId: UUID(), elementType: .face),
            diameter: 5.0,
            depth: 10.0
        )
        let holeFeature = Feature(name: "Hole", operation: .hole(holeParams))
        doc.addFeature(holeFeature)

        let callout = DrawingAnnotation(
            name: "Callout",
            viewId: view.id,
            data: .holeCallout(HoleCalloutAnnotationData(anchorPointMM: .zero, elbowPointMM: SIMD2(10, 10), holeParams: holeParams)),
            sourceFeatureId: holeFeature.id
        )
        _ = doc.addDrawingAnnotation(callout, to: sheet.id)
        #expect(doc.activeSheet?.annotations.first?.isDangling == false)

        // Delete feature
        _ = doc.removeFeature(id: holeFeature.id)
        #expect(doc.activeSheet?.annotations.first?.isDangling == true)
    }

    @Test func testAnnotationFlaggedAsDanglingWhenFeatureHasError() {
        let doc = DocumentModel()
        let sheet = doc.addSheet()
        let view = DrawingView(name: "Front View", standardView: .front)
        _ = doc.addDrawingView(view, to: sheet.id)

        let holeParams = HoleParams(
            targetSolidId: SolidId("part-1"),
            faceReference: TopologicalReference(sourceFeatureId: UUID(), elementType: .face),
            diameter: 5.0,
            depth: 10.0
        )
        let holeFeature = Feature(name: "Hole", operation: .hole(holeParams))
        doc.addFeature(holeFeature)

        let callout = DrawingAnnotation(
            name: "Callout",
            viewId: view.id,
            data: .holeCallout(HoleCalloutAnnotationData(anchorPointMM: .zero, elbowPointMM: SIMD2(10, 10), holeParams: holeParams)),
            sourceFeatureId: holeFeature.id
        )
        _ = doc.addDrawingAnnotation(callout, to: sheet.id)
        #expect(doc.activeSheet?.annotations.first?.isDangling == false)

        // Set feature error
        let errorState = FeatureErrorState(code: "geom-error", message: "Hole generation failed")
        doc.setFeatureError(id: holeFeature.id, error: errorState)
        #expect(doc.activeSheet?.annotations.first?.isDangling == true)

        // Clear error
        doc.setFeatureError(id: holeFeature.id, error: nil)
        #expect(doc.activeSheet?.annotations.first?.isDangling == false)
    }

    @Test func testDrawingViewPoint3DProjection() {
        let p = SIMD3<Double>(10.0, 20.0, 30.0)

        // Top view: (x, y)
        let topView = DrawingView(name: "Top", standardView: .top)
        #expect(topView.project(point3D: p) == SIMD2<Double>(10.0, 20.0))

        // Bottom view: (x, -y)
        let bottomView = DrawingView(name: "Bottom", standardView: .bottom)
        #expect(bottomView.project(point3D: p) == SIMD2<Double>(10.0, -20.0))

        // Front view: (x, z)
        let frontView = DrawingView(name: "Front", standardView: .front)
        #expect(frontView.project(point3D: p) == SIMD2<Double>(10.0, 30.0))

        // Back view: (-x, z)
        let backView = DrawingView(name: "Back", standardView: .back)
        #expect(backView.project(point3D: p) == SIMD2<Double>(-10.0, 30.0))

        // Right view: (-y, z)
        let rightView = DrawingView(name: "Right", standardView: .right)
        #expect(rightView.project(point3D: p) == SIMD2<Double>(-20.0, 30.0))

        // Left view: (y, z)
        let leftView = DrawingView(name: "Left", standardView: .left)
        #expect(leftView.project(point3D: p) == SIMD2<Double>(20.0, 30.0))

        // Isometric view: deterministic projection
        let isoView = DrawingView(name: "Isometric", standardView: .isometric)
        let isoProj = isoView.project(point3D: p)
        #expect(isoProj.x != 0.0)
        #expect(isoProj.y != 0.0)

        // Custom view direction
        let customView = DrawingView(
            name: "Custom",
            kind: .auxiliary,
            customViewDirection: SIMD3<Double>(0, 1, 0)
        )
        let customProj = customView.project(point3D: p)
        #expect(customProj.x != 0.0 || customProj.y != 0.0)
    }

    @Test func testDimension3DPointReprojection() {
        let doc = DocumentModel()
        let sheet = doc.addSheet()
        let view = DrawingView(name: "Front View", standardView: .front)
        _ = doc.addDrawingView(view, to: sheet.id)

        let p1 = SIMD3<Double>(0.0, 0.0, 0.0)
        let p2 = SIMD3<Double>(40.0, 0.0, 30.0)
        let attachment = DrawingAnnotationAttachment(modelPoints: [p1, p2])

        let dimData = LinearDimensionData(
            startPointMM: view.project(point3D: p1),
            endPointMM: view.project(point3D: p2)
        )
        let annotation = DrawingAnnotation(
            name: "3D Dim",
            viewId: view.id,
            data: .linear(dimData),
            attachment: attachment
        )
        _ = doc.addDrawingAnnotation(annotation, to: sheet.id)

        // Initial check
        if case .linear(let d) = doc.activeSheet?.annotations.first?.data {
            #expect(d.startPointMM == SIMD2(0, 0))
            #expect(d.endPointMM == SIMD2(40, 30))
            #expect(abs(d.measuredValue - 50.0) < 1e-4)
        } else {
            Issue.record("Expected linear dimension")
        }

        // Update model points on attachment (e.g., geometry scaled or moved)
        let newP2 = SIMD3<Double>(60.0, 0.0, 80.0)
        if var ann = doc.activeSheet?.annotations.first {
            ann.attachment?.modelPoints = [p1, newP2]
            _ = doc.updateDrawingAnnotation(ann)
        }

        doc.updateDrawingAssociativity()

        // Reprojected value check
        if case .linear(let d) = doc.activeSheet?.annotations.first?.data {
            #expect(d.startPointMM == SIMD2(0, 0))
            #expect(d.endPointMM == SIMD2(60, 80))
            #expect(abs(d.measuredValue - 100.0) < 1e-4)
        } else {
            Issue.record("Expected linear dimension after update")
        }
    }

    @Test func testPreserveAnnotationsAsDanglingOnViewDeletion() {
        let doc = DocumentModel()
        let sheet = doc.addSheet()
        let view = DrawingView(name: "Front View", standardView: .front)
        _ = doc.addDrawingView(view, to: sheet.id)

        let annotation = DrawingAnnotation(
            name: "Attached Note",
            viewId: view.id,
            data: .note(NoteAnnotationData(positionMM: SIMD2(20, 20), text: "Part Note"))
        )
        _ = doc.addDrawingAnnotation(annotation, to: sheet.id)
        #expect(doc.activeSheet?.annotations.count == 1)
        #expect(doc.activeSheet?.annotations.first?.isDangling == false)

        doc.undoManager?.removeAllActions()

        // Delete view while preserving annotations
        _ = doc.removeDrawingView(id: view.id, from: sheet.id, preserveAnnotationsAsDangling: true)
        #expect(doc.activeSheet?.views.isEmpty == true)
        #expect(doc.activeSheet?.annotations.count == 1)
        #expect(doc.activeSheet?.annotations.first?.isDangling == true)

        // Undo view removal
        doc.undo()
        #expect(doc.activeSheet?.views.count == 1)
        #expect(doc.activeSheet?.annotations.first?.isDangling == false)

        // Redo view removal
        doc.redo()
        #expect(doc.activeSheet?.views.isEmpty == true)
        #expect(doc.activeSheet?.annotations.count == 1)
        #expect(doc.activeSheet?.annotations.first?.isDangling == true)
    }

    @Test func testDrawingAnnotationCodableBackwardCompatibility() throws {
        // Legacy JSON without isDangling, sourceFeatureId, or attachment
        let legacyJSON = """
        {
            "id": "22222222-3333-4444-5555-666666666666",
            "name": "Legacy Dimension",
            "isVisible": true,
            "customProperties": {},
            "data": {
                "linear": {
                    "_0": {
                        "startPointMM": [0.0, 0.0],
                        "endPointMM": [50.0, 0.0],
                        "offsetMM": 10.0,
                        "orientation": "aligned",
                        "prefix": "",
                        "suffix": "",
                        "precision": 2
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DrawingAnnotation.self, from: legacyJSON)

        #expect(decoded.name == "Legacy Dimension")
        #expect(decoded.isDangling == false)
        #expect(decoded.sourceFeatureId == nil)
        #expect(decoded.attachment == nil)
        #expect(decoded.kind == .linear)

        // Round-trip encoding preserves new associative properties
        var modern = decoded
        modern.isDangling = true
        let featureId = UUID()
        modern.sourceFeatureId = featureId
        modern.attachment = DrawingAnnotationAttachment(
            modelPoints: [SIMD3(1, 2, 3)],
            featureId: featureId
        )

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(modern)
        let roundTripped = try decoder.decode(DrawingAnnotation.self, from: encoded)

        #expect(roundTripped.isDangling == true)
        #expect(roundTripped.sourceFeatureId == featureId)
        #expect(roundTripped.attachment?.featureId == featureId)
        #expect(roundTripped.attachment?.modelPoints == [SIMD3(1, 2, 3)])
    }

    @Test func testAssociativityUndoRedo() {
        let doc = DocumentModel()
        let sheet = doc.addSheet()
        let view = DrawingView(name: "Front View", standardView: .front)
        _ = doc.addDrawingView(view, to: sheet.id)

        let holeParams = HoleParams(
            targetSolidId: SolidId("part-1"),
            faceReference: TopologicalReference(sourceFeatureId: UUID(), elementType: .face),
            diameter: 5.0,
            depth: 10.0
        )
        let holeFeature = Feature(name: "Hole", operation: .hole(holeParams))
        doc.addFeature(holeFeature)

        let callout = DrawingAnnotation(
            name: "Hole Callout",
            viewId: view.id,
            data: .holeCallout(HoleCalloutAnnotationData(anchorPointMM: .zero, elbowPointMM: SIMD2(10, 10), holeParams: holeParams)),
            sourceFeatureId: holeFeature.id,
            attachment: DrawingAnnotationAttachment(featureId: holeFeature.id)
        )
        _ = doc.addDrawingAnnotation(callout, to: sheet.id)

        // Verify initial state
        if case .holeCallout(let d) = doc.activeSheet?.annotations.first?.data {
            #expect(d.diameter == 5.0)
        }

        // Update feature diameter to 15.0
        var newParams = holeParams
        newParams.diameter = 15.0
        var updatedFeature = holeFeature
        updatedFeature.operation = .hole(newParams)
        _ = doc.updateFeature(updatedFeature)

        // Check updated
        if case .holeCallout(let d) = doc.activeSheet?.annotations.first?.data {
            #expect(d.diameter == 15.0)
        }

        // Single-step undo restores feature and hole callout
        doc.undo()
        if case .holeCallout(let d) = doc.activeSheet?.annotations.first?.data {
            #expect(d.diameter == 5.0)
        }

        // Single-step redo restores updated state
        doc.redo()
        if case .holeCallout(let d) = doc.activeSheet?.annotations.first?.data {
            #expect(d.diameter == 15.0)
        }
    }
}
