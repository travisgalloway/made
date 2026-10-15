import Testing
import Foundation
@testable import MadeCore

@Suite struct RecomputeFailuresTests {
    private let box = SolidId("box-1")
    private let cylinder = SolidId("cylinder-1")
    private let success = KernelResult<MeshPayload>.success(
        jobId: JobId("j"),
        value: MeshPayload(positions: [0, 0, 0, 1, 0, 0, 0, 1, 0], normals: [0, 0, 1, 0, 0, 1, 0, 0, 1], indices: [0, 1, 2])
    )

    private func failure(_ code: KernelErrorCode, _ message: String = "boom") -> KernelResult<MeshPayload> {
        .failure(jobId: JobId("j"), error: KernelError(code: code, message: message))
    }

    @Test(arguments: [
        (KernelErrorCode.kernelInitFailed, "box-1 failed to recompute (kernel-init-failed): boom"),
        (.invalidParams, "box-1 failed to recompute (invalid-params): boom"),
        (.geometryFailed, "box-1 failed to recompute (geometry-failed): boom"),
        (.unknownSolid, "box-1 failed to recompute (unknown-solid): boom"),
        (.workerCrashed, "box-1 failed to recompute (worker-crashed): boom"),
        (.topologicalReferenceBroken, "box-1 failed to recompute (topological-reference-broken): boom"),
    ])
    func messageMapsEveryErrorCode(code: KernelErrorCode, expected: String) {
        #expect(RecomputeFailures.message(for: KernelError(code: code, message: "boom"), solidId: box) == expected)
        var failures = RecomputeFailures()
        #expect(failures.record(failure(code), for: box) == expected)
        #expect(failures.message(for: box) == expected)
    }

    @Test func cancelledMapsToNoMessage() {
        #expect(RecomputeFailures.message(for: KernelError(code: .cancelled, message: "superseded"), solidId: box) == nil)
    }

    @Test func successAfterFailureClearsMessage() {
        var failures = RecomputeFailures()
        _ = failures.record(failure(.geometryFailed), for: box)
        #expect(failures.record(success, for: box) == nil)
        #expect(failures.message(for: box) == nil)
        #expect(failures.errors.isEmpty)
    }

    @Test func twoFailuresInARowKeepTheLatest() {
        var failures = RecomputeFailures()
        _ = failures.record(failure(.geometryFailed, "first"), for: box)
        _ = failures.record(failure(.invalidParams, "second"), for: box)
        #expect(failures.message(for: box) == "box-1 failed to recompute (invalid-params): second")
    }

    @Test func cancelledResultLeavesStateUnchanged() {
        var empty = RecomputeFailures()
        #expect(empty.record(failure(.cancelled), for: box) == nil)
        #expect(empty == RecomputeFailures())

        var failures = RecomputeFailures()
        _ = failures.record(failure(.geometryFailed), for: box)
        let before = failures
        #expect(failures.record(failure(.cancelled), for: box) == nil)
        #expect(failures == before)
        #expect(failures.message(for: box) == "box-1 failed to recompute (geometry-failed): boom")
    }

    @Test func clearRemovesMessageForRemovedSolid() {
        var failures = RecomputeFailures()
        _ = failures.record(failure(.geometryFailed), for: box)
        failures.clear(box)
        #expect(failures.message(for: box) == nil)
    }

    @Test func failuresArePerSolid() {
        var failures = RecomputeFailures()
        _ = failures.record(failure(.geometryFailed), for: box)
        #expect(failures.message(for: cylinder) == nil)
        _ = failures.record(success, for: cylinder)
        #expect(failures.message(for: box) != nil)
    }
}
