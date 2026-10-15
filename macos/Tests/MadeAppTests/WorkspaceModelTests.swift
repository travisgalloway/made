import Testing
@testable import MadeApp
import MadeCore

@Suite struct WorkspaceModelTests {
    @Test @MainActor func testSetTransformLogsConsoleEntry() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        let initialLogsCount = model.logs.count

        var newTransform = Transform()
        newTransform.position = SIMD3<Float>(15.0, 0.0, 0.0)
        newTransform.scale = SIMD3<Float>(2.0, 2.0, 2.0)

        model.setTransform(id, newTransform)

        #expect(model.logs.count == initialLogsCount + 1)
        guard let lastLog = model.logs.last else {
            Issue.record("Expected log entry")
            return
        }
        #expect(lastLog.subsystem == "Scene")
        #expect(lastLog.level == .info)
        #expect(lastLog.message.contains("box-1"))
        #expect(lastLog.message.contains("15.0"))
        #expect(lastLog.message.contains("2.0"))
    }

    @Test @MainActor func testSetTransformUnchangedValueAddsNoLogEntry() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        guard let current = model.document.objects.first(where: { $0.id == id }) else {
            Issue.record("Default box-1 not found")
            return
        }
        let initialLogsCount = model.logs.count

        model.setTransform(id, current.transform)

        #expect(model.logs.count == initialLogsCount)
    }

    @Test @MainActor func testSetTransformNonExistentIdAddsNoLogEntry() {
        let model = WorkspaceModel()
        let fakeId = ObjectId("nonexistent-solid-999")
        let initialLogsCount = model.logs.count

        model.setTransform(fakeId, Transform(position: SIMD3<Float>(10, 10, 10)))

        #expect(model.logs.count == initialLogsCount)
    }

    @Test @MainActor func testSetTransformLockedObjectAddsNoLogEntry() {
        let model = WorkspaceModel()
        let id = ObjectId("box-1")
        model.document.setLocked(id: id, isLocked: true)
        let initialLogsCount = model.logs.count

        model.setTransform(id, Transform(position: SIMD3<Float>(50, 0, 0)))

        #expect(model.logs.count == initialLogsCount)
    }
}
