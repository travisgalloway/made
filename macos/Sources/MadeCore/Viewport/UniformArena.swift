import Foundation
import Metal

/// Bump allocator for per-draw uniforms. Metal 4 has no `setVertexBytes`, so uniforms live in a shared buffer
/// whose GPU address goes into the argument table. One arena belongs to one frame in flight.
final class UniformArena {
    static let alignment = 256

    let buffer: MTLBuffer
    private var offset = 0

    init?(device: MTLDevice, capacity: Int) {
        guard let buffer = device.makeBuffer(length: max(capacity, Self.alignment), options: .storageModeShared) else { return nil }
        buffer.label = "Uniform Arena"
        self.buffer = buffer
    }

    var capacity: Int { buffer.length }

    func reset() { offset = 0 }

    /// Copies `value` into the arena and returns its GPU address, or nil when the arena is full.
    func push<T: BitwiseCopyable>(_ value: T) -> MTLGPUAddress? {
        let size = MemoryLayout<T>.stride
        guard offset + size <= buffer.length else { return nil }
        withUnsafeBytes(of: value) { bytes in
            buffer.contents().advanced(by: offset).copyMemory(from: bytes.baseAddress!, byteCount: size)
        }
        let address = buffer.gpuAddress + UInt64(offset)
        offset = (offset + size + Self.alignment - 1) / Self.alignment * Self.alignment
        return address
    }

    /// Bytes needed for `draws` uniform blocks of at most `blockSize` bytes each.
    static func capacity(forDraws draws: Int, blockSize: Int) -> Int {
        let aligned = (blockSize + alignment - 1) / alignment * alignment
        return max(draws, 1) * aligned
    }
}
