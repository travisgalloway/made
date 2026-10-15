import Testing
import Foundation
import simd
@testable import MadeCore

@MainActor
private final class StubSink: SolidMeshSink {
    struct Call {
        let id: SolidId
        let transform: Transform
        let color: SIMD4<Float>
        let isHidden: Bool
    }
    var calls: [Call] = []
    var installed: [SolidId: Transform] = [:]
    var installedColors: [SolidId: SIMD4<Float>] = [:]
    var succeeds = true

    func installMesh(_ payload: MeshPayload, for id: SolidId, transform: Transform, color: SIMD4<Float>, isHidden: Bool) -> Bool {
        calls.append(Call(id: id, transform: transform, color: color, isHidden: isHidden))
        if succeeds {
            installed[id] = transform
            installedColors[id] = color
        }
        return succeeds
    }

    func updateTransform(_ transform: Transform, for id: SolidId) -> Bool {
        guard installed[id] != nil else { return false }
        installed[id] = transform
        return true
    }

    func updateColor(_ color: SIMD4<Float>, for id: SolidId) -> Bool {
        guard installed[id] != nil else { return false }
        installedColors[id] = color
        return true
    }

    func removeMesh(for id: SolidId) -> Bool {
        installedColors.removeValue(forKey: id)
        return installed.removeValue(forKey: id) != nil
    }
}

@MainActor
@Suite struct SolidMeshApplierTests {
    private let success = KernelResult<MeshPayload>.success(
        jobId: JobId("j"),
        value: MeshPayload(positions: [0, 0, 0, 1, 0, 0, 0, 1, 0], normals: [0, 0, 1, 0, 0, 1, 0, 0, 1], indices: [0, 1, 2])
    )

    private func moved(_ x: Float) -> Transform {
        var t = Transform.identity
        t.position = SIMD3<Float>(x, 2, 3)
        return t
    }

    @Test func testAppliesTransformSetAfterRequest() {
        let doc = DocumentModel()
        let sink = StubSink()
        let t = moved(7)
        doc.setTransform(id: boxSolidId, transform: t)

        #expect(SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink))
        #expect(sink.calls.count == 1)
        #expect(sink.calls[0].transform.position == t.position)
    }

    @Test func testRemovedObjectIsNotResurrected() {
        let doc = DocumentModel()
        let sink = StubSink()
        doc.removeObject(id: boxSolidId)

        #expect(!SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink))
        #expect(sink.calls.isEmpty)
    }

    @Test func testLastOfTwoTransformEditsWins() {
        let doc = DocumentModel()
        let sink = StubSink()
        doc.setTransform(id: boxSolidId, transform: moved(5))
        doc.setTransform(id: boxSolidId, transform: moved(9))

        _ = SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink)
        #expect(sink.calls[0].transform.position == moved(9).position)
    }

    @Test func testParamAndTransformEditBothApply() {
        let doc = DocumentModel()
        let sink = StubSink()
        doc.setParam(id: boxSolidId, key: "width", value: 60)
        doc.setTransform(id: boxSolidId, transform: moved(4))

        #expect(SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink))
        #expect(sink.calls[0].transform.position == moved(4).position)
    }

    @Test func testFailedResultInstallsNothing() {
        let doc = DocumentModel()
        let sink = StubSink()
        let failure = KernelResult<MeshPayload>.failure(
            jobId: JobId("j"),
            error: KernelError(code: .geometryFailed, message: "boom")
        )

        #expect(!SolidMeshApplier.apply(failure, to: boxSolidId, document: doc, sink: sink))
        #expect(sink.calls.isEmpty)
    }

    @Test func testReadsLiveColorAndVisibility() {
        let doc = DocumentModel()
        let sink = StubSink()
        let color = SIMD4<Float>(1, 0, 0, 1)
        doc.setVisibility(id: boxSolidId, isVisible: false)
        doc.setMaterial(id: boxSolidId, material: MaterialAttributes(color: color))

        _ = SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink)
        #expect(sink.calls[0].isHidden)
        #expect(sink.calls[0].color == color)
    }

    @Test func testDirectTransformPassthrough() {
        let doc = DocumentModel()
        let sink = StubSink()

        _ = SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink)
        _ = SolidMeshApplier.apply(success, to: cylinderSolidId, document: doc, sink: sink)

        #expect(sink.calls[0].transform == doc.objects.first(where: { $0.id == boxSolidId })?.transform)
        #expect(sink.calls[1].transform == doc.objects.first(where: { $0.id == cylinderSolidId })?.transform)
    }

    @Test func testSinkFailureReturnsFalse() {
        let doc = DocumentModel()
        let sink = StubSink()
        sink.succeeds = false

        #expect(!SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink))
    }

    @Test func testApplyTransformUpdatesInstalledMesh() {
        let doc = DocumentModel()
        let sink = StubSink()
        _ = SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink)
        doc.setTransform(id: boxSolidId, transform: moved(14))

        #expect(SolidMeshApplier.applyTransform(to: boxSolidId, document: doc, sink: sink))
        #expect(sink.installed[boxSolidId]?.position == moved(14).position)
        #expect(!SolidMeshApplier.applyTransform(to: SolidId("missing"), document: doc, sink: sink))
    }

    @Test func testRemoveDropsInstalledMesh() {
        let doc = DocumentModel()
        let sink = StubSink()
        _ = SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink)

        #expect(SolidMeshApplier.remove(id: boxSolidId, from: sink))
        #expect(sink.installed[boxSolidId] == nil)
        #expect(!SolidMeshApplier.remove(id: boxSolidId, from: sink))
    }

    @Test func testApplyMaterialUpdatesColorWithoutRecompute() {
        let doc = DocumentModel()
        let sink = StubSink()
        _ = SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink)
        #expect(sink.calls.count == 1)
        let initialColor = sink.calls[0].color
        #expect(sink.installedColors[boxSolidId] == initialColor)

        let newColor = SIMD4<Float>(0.2, 0.8, 0.4, 1.0)
        _ = doc.setMaterial(id: boxSolidId, material: MaterialAttributes(color: newColor))

        #expect(SolidMeshApplier.applyMaterial(to: boxSolidId, document: doc, sink: sink))
        #expect(sink.installedColors[boxSolidId] == newColor)
        // Verify installMesh was not called again (no recompute / buffer churn)
        #expect(sink.calls.count == 1)

        // Missing ID returns false
        #expect(!SolidMeshApplier.applyMaterial(to: SolidId("missing"), document: doc, sink: sink))

        // Subsequent recompute retains live material color
        _ = SolidMeshApplier.apply(success, to: boxSolidId, document: doc, sink: sink)
        #expect(sink.calls.count == 2)
        #expect(sink.calls[1].color == newColor)
    }
}
