import Testing
import Foundation
import XPC
@testable import MadeCore

@Suite struct MeshStorageTests {
    private let positions: [Float] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    private let normals: [Float] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
    private let indices: [UInt32] = [0, 1, 2]
    
    @Test func testRegionIsPageAligned() {
        let payload = MeshPayload(positions: positions, normals: normals, indices: indices)
        let page = Int(getpagesize())
        let base = try! #require(payload.storage.base)
        #expect(Int(bitPattern: base) % page == 0)
        #expect(payload.storage.length % page == 0)
        #expect(payload.storage.length >= payload.storage.byteCount)
    }
    
    @Test func testComponentsMatchInput() {
        let payload = MeshPayload(positions: positions, normals: normals, indices: indices)
        #expect(Array(payload.positions) == positions)
        #expect(Array(payload.normals) == normals)
        #expect(Array(payload.indices) == indices)
        #expect(payload.triangleCount == 1)
        #expect(payload.positions == MeshPayload(positions: positions, normals: [], indices: []).positions)
    }
    
    @Test func testEmptyPayloadAllocatesNothing() {
        let payload = MeshPayload(positions: [], normals: [], indices: [])
        #expect(payload.storage.base == nil)
        #expect(payload.storage.length == 0)
        #expect(payload.positions.isEmpty && payload.normals.isEmpty && payload.indices.isEmpty)
        #expect(payload.triangleCount == 0)
        payload.indices.withUnsafeBytes { #expect($0.isEmpty) }
    }
    
    @Test func testShmemRoundTripPreservesBytes() throws {
        let sent = EuclidEngine.toMeshPayload(EuclidEngine.makeBox(width: 4, depth: 5, height: 6))
        let reply = KernelWire.encodeReply(.success(jobId: JobId("j"), value: sent))
        #expect(reply[KernelWire.meshKey, as: XPC_TYPE_SHMEM] != nil)
        
        let received = try #require(KernelWire.decodeReply(reply, jobId: JobId("j")).value)
        #expect(received.storage.base != sent.storage.base) // a second mapping of the same pages, not a copy
        #expect(Array(received.positions) == Array(sent.positions))
        #expect(Array(received.normals) == Array(sent.normals))
        #expect(Array(received.indices) == Array(sent.indices))
    }
}
