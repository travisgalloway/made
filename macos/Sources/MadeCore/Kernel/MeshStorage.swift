import Darwin

/// One page-aligned, `MAP_SHARED` memory region holding a mesh's positions, then normals, then indices.
/// XPC can box such a region as `xpc_shmem` and the receiver maps the same pages (invariant 6).
// @unchecked Sendable: the region is written only inside init and is immutable afterwards.
public final class MeshStorage: @unchecked Sendable {
    let base: UnsafeMutableRawPointer?
    /// Mapped bytes, a whole number of pages; zero for an empty mesh.
    let length: Int
    public let positionCount: Int
    public let normalCount: Int
    public let indexCount: Int

    static let elementSize = 4

    var byteCount: Int { (positionCount + normalCount + indexCount) * Self.elementSize }

    /// Allocates the region and lets `fill` write each component once.
    public init(
        positionCount: Int,
        normalCount: Int,
        indexCount: Int,
        fill: (UnsafeMutableBufferPointer<Float>, UnsafeMutableBufferPointer<Float>, UnsafeMutableBufferPointer<UInt32>) -> Void
    ) {
        precondition(positionCount >= 0 && normalCount >= 0 && indexCount >= 0, "Mesh component counts must be non-negative")
        self.positionCount = positionCount
        self.normalCount = normalCount
        self.indexCount = indexCount
        let bytes = (positionCount + normalCount + indexCount) * Self.elementSize
        if bytes == 0 {
            base = nil
            length = 0
        } else {
            let page = Int(getpagesize())
            let rounded = (bytes + page - 1) / page * page
            let region = mmap(nil, rounded, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANON, -1, 0)
            precondition(region != MAP_FAILED && region != nil, "mmap of \(rounded) bytes for a mesh failed")
            base = region
            length = rounded
        }
        fill(Self.buffer(base, offset: 0, count: positionCount),
             Self.buffer(base, offset: positionCount * Self.elementSize, count: normalCount),
             Self.buffer(base, offset: (positionCount + normalCount) * Self.elementSize, count: indexCount))
    }

    /// Adopts a region mapped by `xpc_shmem_map`; the caller has checked that `length` covers the counts.
    init(adopting base: UnsafeMutableRawPointer, length: Int, positionCount: Int, normalCount: Int, indexCount: Int) {
        self.base = base
        self.length = length
        self.positionCount = positionCount
        self.normalCount = normalCount
        self.indexCount = indexCount
    }

    deinit {
        if let base { munmap(base, length) }
    }

    public var positions: MeshComponent<Float> { MeshComponent(storage: self, offset: 0, count: positionCount) }
    public var normals: MeshComponent<Float> { MeshComponent(storage: self, offset: positionCount * Self.elementSize, count: normalCount) }
    public var indices: MeshComponent<UInt32> {
        MeshComponent(storage: self, offset: (positionCount + normalCount) * Self.elementSize, count: indexCount)
    }

    private static func buffer<T>(_ base: UnsafeMutableRawPointer?, offset: Int, count: Int) -> UnsafeMutableBufferPointer<T> {
        guard let base, count > 0 else { return UnsafeMutableBufferPointer(start: nil, count: 0) }
        return UnsafeMutableBufferPointer(start: (base + offset).bindMemory(to: T.self, capacity: count), count: count)
    }
}

/// A read-only typed view of one component of a `MeshStorage` region. Keeps the region alive.
public struct MeshComponent<Element: BitwiseCopyable>: RandomAccessCollection, Sendable {
    let storage: MeshStorage
    let offset: Int
    public let count: Int

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public subscript(position: Int) -> Element {
        precondition(position >= 0 && position < count, "Mesh component index out of range")
        return storage.base!.load(fromByteOffset: offset + position * MemoryLayout<Element>.stride, as: Element.self)
    }

    /// The component's bytes, for a single copy into a GPU buffer.
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        guard let base = storage.base, count > 0 else { return try body(UnsafeRawBufferPointer(start: nil, count: 0)) }
        return try body(UnsafeRawBufferPointer(start: base + offset, count: count * MemoryLayout<Element>.stride))
    }
}

extension MeshComponent: Equatable where Element: Equatable {
    public static func == (lhs: MeshComponent, rhs: MeshComponent) -> Bool {
        lhs.elementsEqual(rhs)
    }
}
