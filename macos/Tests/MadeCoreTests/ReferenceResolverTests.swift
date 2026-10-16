import Testing
import Foundation
@testable import MadeCore

@Suite @MainActor struct ReferenceResolverTests {
    @Test func testTargetBodyValidationValidTarget() {
        let doc = DocumentModel()
        // Default document has boxSolidId ("box-1") and cylinderSolidId ("cylinder-1")
        let cutFeature = Feature(
            name: "Cut 1",
            operation: .primitive(.cylinder(CylinderParams(radius: 5, height: 10))),
            outputSolidId: SolidId("cut-cyl"),
            bodyOperation: .cut,
            targetBodyId: boxSolidId
        )
        let error = ReferenceResolver.validateReferences(for: cutFeature, in: doc)
        #expect(error == nil)
    }

    @Test func testTargetBodyValidationMissingTarget() {
        let doc = DocumentModel()
        let cutFeature = Feature(
            name: "Cut Without Target",
            operation: .primitive(.cylinder(CylinderParams(radius: 5, height: 10))),
            outputSolidId: SolidId("cut-cyl"),
            bodyOperation: .cut,
            targetBodyId: nil
        )
        let error = ReferenceResolver.validateReferences(for: cutFeature, in: doc)
        #expect(error == .missingTargetBody(featureId: cutFeature.id, operation: .cut))
        #expect(error?.description.contains("must specify a targetBodyId") == true)
    }

    @Test func testTargetBodyValidationBodyNotFound() {
        let doc = DocumentModel()
        let ghostBody = SolidId("ghost-solid-404")
        let addFeature = Feature(
            name: "Add 1",
            operation: .primitive(.box(BoxParams(width: 10, depth: 10, height: 10))),
            outputSolidId: SolidId("add-box"),
            bodyOperation: .add,
            targetBodyId: ghostBody
        )
        let error = ReferenceResolver.validateReferences(for: addFeature, in: doc)
        #expect(error == .bodyNotFound(ghostBody))
    }

    @Test func testTargetBodyValidationSelfReference() {
        let doc = DocumentModel()
        let mySolidId = SolidId("self-referencing-solid")
        let selfFeature = Feature(
            name: "Self Ref",
            operation: .primitive(.box(BoxParams(width: 10, depth: 10, height: 10))),
            outputSolidId: mySolidId,
            bodyOperation: .intersect,
            targetBodyId: mySolidId
        )
        let error = ReferenceResolver.validateReferences(for: selfFeature, in: doc)
        #expect(error == .selfReference(selfFeature.id))
    }

    @Test func testTargetBodyValidationForwardReference() {
        let doc = DocumentModel(features: [])

        let featA = Feature.makeBox(
            solidId: SolidId("solid-a"),
            params: BoxParams(width: 10, depth: 10, height: 10)
        )
        let featB = Feature.makeBox(
            solidId: SolidId("solid-b"),
            params: BoxParams(width: 20, depth: 20, height: 20)
        )

        // featA is placed before featB, but featA declares targetBodyId as solid-b
        var forwardFeature = featA
        forwardFeature.bodyOperation = .add
        forwardFeature.targetBodyId = SolidId("solid-b")

        doc.reset(with: [forwardFeature, featB])

        let error = ReferenceResolver.validateReferences(for: forwardFeature, in: doc)
        #expect(error == .forwardReference(referencedFeatureId: featB.id, currentFeatureId: forwardFeature.id))
    }

    @Test func testTargetBodyValidationSuppressedTarget() {
        let doc = DocumentModel()
        // Suppress box-1
        let boxFeat = doc.feature(for: boxSolidId)!
        _ = doc.setFeatureSuppressed(id: boxFeat.id, isSuppressed: true)

        let addFeature = Feature(
            name: "Add to Suppressed",
            operation: .primitive(.cylinder(CylinderParams(radius: 5, height: 10))),
            outputSolidId: SolidId("new-cyl"),
            bodyOperation: .add,
            targetBodyId: boxSolidId
        )
        let error = ReferenceResolver.validateReferences(for: addFeature, in: doc)
        #expect(error == .targetFeatureSuppressed(boxFeat.id))
    }

    @Test func testTargetBodyValidationCreateIgnoresTargetBody() {
        let doc = DocumentModel()
        let createFeature = Feature(
            name: "Create Feature",
            operation: .primitive(.box(BoxParams(width: 10, depth: 10, height: 10))),
            outputSolidId: SolidId("brand-new-solid"),
            bodyOperation: .create,
            targetBodyId: nil
        )
        let error = ReferenceResolver.validateReferences(for: createFeature, in: doc)
        #expect(error == nil)
    }
}
