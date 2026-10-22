import Testing
import Foundation
import SwiftUI
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct DrawingAssociativityAppTests {

    @Test func testWorkspaceFeatureLinkedHoleCallout() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        let baseView = ws.addBaseView(standardView: .front, scale: .full, displayStyle: .visibleLinesOnly)
        #expect(baseView != nil)

        let holeParams = HoleParams(
            targetSolidId: SolidId("part-1"),
            faceReference: TopologicalReference(sourceFeatureId: UUID(), elementType: .face),
            diameter: 6.0,
            depth: 14.0,
            counterboreDiameter: 11.0,
            counterboreDepth: 4.5
        )
        let holeFeature = Feature(name: "Mounting Hole", operation: .hole(holeParams))
        ws.document.addFeature(holeFeature)

        let callout = ws.addHoleCalloutFromFeature(
            featureId: holeFeature.id,
            viewId: baseView?.id,
            anchor: SIMD2(10.0, 15.0),
            elbow: SIMD2(25.0, 30.0)
        )
        #expect(callout != nil)
        #expect(callout?.sourceFeatureId == holeFeature.id)
        #expect(callout?.attachment?.featureId == holeFeature.id)
        #expect(callout?.isDangling == false)
        #expect(ws.isDocumentModified)

        // Verify callout data matches Hole Wizard feature
        if case .holeCallout(let d) = callout?.data {
            #expect(d.diameter == 6.0)
            #expect(d.depth == 14.0)
            #expect(d.counterboreDiameter == 11.0)
            #expect(d.counterboreDepth == 4.5)
        } else {
            Issue.record("Expected holeCallout annotation")
        }

        // Recompute drawing view HLR routes through document associativity
        if let viewId = baseView?.id {
            ws.recomputeDrawingViewHLR(viewId: viewId)
            #expect(ws.document.activeSheet?.annotations.first?.isDangling == false)
        }
    }

    @Test func testWorkspaceAssociativityPackageRoundTrip() throws {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        let view = ws.addBaseView(standardView: .front, scale: .half, displayStyle: .visibleLinesOnly)
        #expect(view != nil)

        let featureId = UUID()
        let modelPoints = [SIMD3<Double>(0, 0, 0), SIMD3<Double>(100, 50, 0)]
        let attachment = DrawingAnnotationAttachment(
            modelPoints: modelPoints,
            featureId: featureId
        )
        let dim = ws.addLinearDimension(
            viewId: view?.id,
            start: SIMD2(0, 0),
            end: SIMD2(100, 50),
            sourceFeatureId: featureId,
            attachment: attachment
        )
        #expect(dim != nil)

        // Flag annotation as dangling (e.g. Broken association)
        if var ann = ws.document.activeSheet?.annotations.first {
            ann.isDangling = true
            _ = ws.updateDrawingAnnotation(ann)
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("AssociativityPackageTest.made")
        let package = try ws.makePackage()
        try package.write(to: packageURL)

        // Reopen package in fresh workspace
        let ws2 = WorkspaceModel()
        let opened = ws2.openDocument(at: packageURL)
        #expect(opened)
        #expect(ws2.document.documentType == .drawing)
        #expect(ws2.document.sheets.count == 1)

        let reloadedAnnotation = ws2.document.activeSheet?.annotations.first
        #expect(reloadedAnnotation != nil)
        #expect(reloadedAnnotation?.isDangling == true)
        #expect(reloadedAnnotation?.sourceFeatureId == featureId)
        #expect(reloadedAnnotation?.attachment?.featureId == featureId)
        #expect(reloadedAnnotation?.attachment?.modelPoints == modelPoints)
    }

    @Test func testWorkspaceAnnotationDanglingVisualState() {
        let ws = WorkspaceModel()
        ws.newDrawingDocument()

        let view = ws.addBaseView(standardView: .front, scale: .full, displayStyle: .visibleLinesOnly)
        guard let viewId = view?.id else {
            Issue.record("Missing view ID")
            return
        }

        let ann = ws.addLinearDimension(
            viewId: viewId,
            start: SIMD2(0, 0),
            end: SIMD2(50, 50)
        )
        guard let annId = ann?.id else {
            Issue.record("Missing annotation ID")
            return
        }

        // Delete view preserving annotation as dangling
        let removed = ws.removeDrawingView(id: viewId, preserveAnnotationsAsDangling: true)
        #expect(removed)

        let danglingAnnotation = ws.document.activeSheet?.annotations.first(where: { $0.id == annId })
        #expect(danglingAnnotation != nil)
        #expect(danglingAnnotation?.isDangling == true)

        // Selection reflects dangling annotation in inspector/navigator bindings
        ws.selectDrawingAnnotation(annId)
        #expect(ws.selectedDrawingAnnotationId == annId)
        #expect(ws.document.selectedDrawingAnnotation?.isDangling == true)
    }
}
