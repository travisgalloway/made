import Foundation
import simd
import OCCTSwift

/// Serializes and reads binary Stereolithography (STL) files with streaming buffer management.
public struct STLExporter: Sendable {
    public enum STLExportError: LocalizedError, Sendable, Equatable {
        case invalidTolerance(Double)
        case noVisibleObjects
        case writeFailed(String)
        case invalidSTLData

        public var errorDescription: String? {
            switch self {
            case .invalidTolerance(let tol):
                return "Invalid tessellation tolerance: \(tol). Tolerance must be positive."
            case .noVisibleObjects:
                return "No visible objects to export"
            case .writeFailed(let message):
                return "Failed to write STL file: \(message)"
            case .invalidSTLData:
                return "Invalid STL data"
            }
        }
    }

    /// Validates that tessellation tolerance is positive, finite, and not NaN.
    public static func validateTolerance(_ tolerance: Double) -> Bool {
        tolerance > 0 && !tolerance.isNaN && !tolerance.isInfinite
    }

    /// Serializes multiple mesh payloads to binary STL at the specified destination.
    ///
    /// - Parameters:
    ///   - meshes: Meshes and their associated spatial transforms.
    ///   - unit: Length unit for coordinate scaling (defaults to millimeters).
    ///   - destinationURL: Target file URL for the written STL.
    /// - Returns: Total number of triangles written.
    @discardableResult
    public static func export(
        meshes: [(mesh: MeshPayload, transform: Transform)],
        unit: LengthUnit = .millimeters,
        to destinationURL: URL
    ) throws -> Int {
        let totalTriangles = meshes.reduce(0) { $0 + $1.mesh.triangleCount }
        guard totalTriangles > 0 else {
            throw STLExportError.writeFailed("No geometry to export")
        }
        guard totalTriangles <= Int(UInt32.max) else {
            throw STLExportError.writeFailed("Triangle count exceeds maximum supported by binary STL (\(UInt32.max))")
        }

        let destinationDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationDir.path) {
            do {
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            } catch {
                throw STLExportError.writeFailed("Cannot create directory \(destinationDir.path): \(error.localizedDescription)")
            }
        }

        let tempURL = destinationDir.appendingPathComponent(".tmp.\(UUID().uuidString).stl")
        guard let stream = OutputStream(url: tempURL, append: false) else {
            throw STLExportError.writeFailed("Could not create output stream for \(tempURL.path)")
        }

        stream.open()
        defer {
            stream.close()
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        if stream.streamStatus == .error || stream.streamError != nil {
            let errorMsg = stream.streamError?.localizedDescription ?? "Could not open stream for writing"
            throw STLExportError.writeFailed(errorMsg)
        }

        // Buffer: 64 KB chunk size for streaming flushes
        var buffer = [UInt8]()
        buffer.reserveCapacity(65536)

        func flushBuffer() throws {
            guard !buffer.isEmpty else { return }
            var bytesWritten = 0
            let total = buffer.count
            while bytesWritten < total {
                let count = total - bytesWritten
                let written = buffer.withUnsafeBytes { rawPtr -> Int in
                    guard let base = rawPtr.baseAddress else { return 0 }
                    return stream.write(base.advanced(by: bytesWritten).assumingMemoryBound(to: UInt8.self), maxLength: count)
                }
                if written <= 0 {
                    let err = stream.streamError?.localizedDescription ?? "Stream write returned \(written)"
                    throw STLExportError.writeFailed(err)
                }
                bytesWritten += written
            }
            buffer.removeAll(keepingCapacity: true)
        }

        // 80-byte binary STL header (avoid leading "solid" to prevent ASCII misdetection)
        var header = [UInt8](repeating: 0, count: 80)
        let headerText = "MADE CAD Binary STL Export"
        if let ascii = headerText.data(using: .ascii) {
            for (idx, byte) in ascii.prefix(80).enumerated() {
                header[idx] = byte
            }
        }
        buffer.append(contentsOf: header)

        // 4-byte unsigned integer triangle count (little-endian)
        var triangleCountLE = UInt32(totalTriangles).littleEndian
        withUnsafeBytes(of: &triangleCountLE) { buffer.append(contentsOf: $0) }

        // Scale factor converting CAD scene internal millimeters to chosen unit
        let scaleFactor = Float(unit.fromMillimeters(1.0))

        // Write triangle records (50 bytes each)
        for (mesh, transform) in meshes {
            let positions = mesh.positions
            let normals = mesh.normals
            let indices = mesh.indices
            let normalMatrix = transform.normalMatrix
            let triCount = mesh.triangleCount

            for triIndex in 0..<triCount {
                let i0 = Int(indices[triIndex * 3])
                let i1 = Int(indices[triIndex * 3 + 1])
                let i2 = Int(indices[triIndex * 3 + 2])

                let p0 = SIMD3<Float>(positions[i0 * 3], positions[i0 * 3 + 1], positions[i0 * 3 + 2])
                let p1 = SIMD3<Float>(positions[i1 * 3], positions[i1 * 3 + 1], positions[i1 * 3 + 2])
                let p2 = SIMD3<Float>(positions[i2 * 3], positions[i2 * 3 + 1], positions[i2 * 3 + 2])

                let v0 = transform.transformPoint(p0) * scaleFactor
                let v1 = transform.transformPoint(p1) * scaleFactor
                let v2 = transform.transformPoint(p2) * scaleFactor

                let e1 = v1 - v0
                let e2 = v2 - v0
                let cross = simd_cross(e1, e2)
                let lenSq = simd_length_squared(cross)
                let normal: SIMD3<Float>
                if lenSq > 1e-12 && !lenSq.isNaN && !lenSq.isInfinite {
                    normal = simd_normalize(cross)
                } else if normals.count >= (i0 + 1) * 3 {
                    let n0 = SIMD3<Float>(normals[i0 * 3], normals[i0 * 3 + 1], normals[i0 * 3 + 2])
                    let transformedN = normalMatrix * n0
                    let nLenSq = simd_length_squared(transformedN)
                    if nLenSq > 1e-12 && !nLenSq.isNaN && !nLenSq.isInfinite {
                        normal = simd_normalize(transformedN)
                    } else {
                        normal = SIMD3<Float>(0, 0, 0)
                    }
                } else {
                    normal = SIMD3<Float>(0, 0, 0)
                }

                // Normal vector (3x Float32 LE)
                appendFloatLE(normal.x, to: &buffer)
                appendFloatLE(normal.y, to: &buffer)
                appendFloatLE(normal.z, to: &buffer)

                // Vertex 1 (3x Float32 LE)
                appendFloatLE(v0.x, to: &buffer)
                appendFloatLE(v0.y, to: &buffer)
                appendFloatLE(v0.z, to: &buffer)

                // Vertex 2 (3x Float32 LE)
                appendFloatLE(v1.x, to: &buffer)
                appendFloatLE(v1.y, to: &buffer)
                appendFloatLE(v1.z, to: &buffer)

                // Vertex 3 (3x Float32 LE)
                appendFloatLE(v2.x, to: &buffer)
                appendFloatLE(v2.y, to: &buffer)
                appendFloatLE(v2.z, to: &buffer)

                // Attribute byte count (UInt16 LE = 0)
                var attr: UInt16 = 0
                withUnsafeBytes(of: &attr) { buffer.append(contentsOf: $0) }

                if buffer.count >= 65536 {
                    try flushBuffer()
                }
            }
        }

        // Flush any remaining buffered data
        try flushBuffer()
        stream.close()

        // Atomically move or replace temporary file to final destination
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL, backupItemName: nil, options: .withoutDeletingBackupItem)
            } else {
                try fileManager.moveItem(at: tempURL, to: destinationURL)
            }
        } catch {
            throw STLExportError.writeFailed("Failed to atomically replace destination file: \(error.localizedDescription)")
        }

        return totalTriangles
    }

    /// Tessellates visible scene objects with the given tolerance and exports them to binary STL.
    @discardableResult
    public static func export(
        objects: [SceneObject],
        tolerance: Double,
        unit: LengthUnit = .millimeters,
        to destinationURL: URL,
        cachedShapes: [SolidId: Shape] = [:],
        cachedMeshes: [SolidId: MeshPayload] = [:]
    ) throws -> Int {
        let visibleObjects = objects.filter { $0.isVisible }
        guard !visibleObjects.isEmpty else {
            throw STLExportError.noVisibleObjects
        }
        guard validateTolerance(tolerance) else {
            throw STLExportError.invalidTolerance(tolerance)
        }

        var meshes: [(mesh: MeshPayload, transform: Transform)] = []
        for obj in visibleObjects {
            var meshPayload: MeshPayload?
            if let shape = cachedShapes[obj.id] ?? (try? OCCTEngine.buildShape(for: obj.def, cachedShape: cachedShapes[obj.id])) {
                meshPayload = OCCTEngine.toMeshPayload(shape, deflection: tolerance)
            }
            if meshPayload == nil, let cached = cachedMeshes[obj.id] {
                meshPayload = cached
            }
            if let meshPayload, meshPayload.triangleCount > 0 {
                meshes.append((mesh: meshPayload, transform: obj.transform))
            }
        }

        guard !meshes.isEmpty else {
            throw STLExportError.writeFailed("No geometry to export")
        }

        return try export(meshes: meshes, unit: unit, to: destinationURL)
    }

    /// Reads the triangle count from a binary STL file header and verifies file size.
    public static func readTriangleCount(from url: URL) throws -> Int {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard fileSize >= 84 else {
            throw STLExportError.invalidSTLData
        }

        try handle.seek(toOffset: 80)
        guard let countData = try handle.read(upToCount: 4), countData.count == 4 else {
            throw STLExportError.invalidSTLData
        }

        let rawCount = countData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let triangleCount = Int(UInt32(littleEndian: rawCount))
        let expectedSize = UInt64(84 + triangleCount * 50)
        guard fileSize == expectedSize else {
            throw STLExportError.invalidSTLData
        }

        return triangleCount
    }

    /// Reads the axis-aligned bounding box from a binary STL file by streaming triangle vertex coordinates.
    public static func readBounds(from url: URL) throws -> AxisAlignedBoundingBox {
        let triangleCount = try readTriangleCount(from: url)
        guard triangleCount > 0 else {
            throw STLExportError.invalidSTLData
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: 84)

        var minX = Double.infinity
        var minY = Double.infinity
        var minZ = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        var maxZ = -Double.infinity

        let trianglesPerChunk = 1024
        var remainingTriangles = triangleCount

        while remainingTriangles > 0 {
            let toReadTriangles = min(remainingTriangles, trianglesPerChunk)
            let toReadBytes = toReadTriangles * 50
            guard let chunk = try handle.read(upToCount: toReadBytes), chunk.count == toReadBytes else {
                throw STLExportError.invalidSTLData
            }

            chunk.withUnsafeBytes { rawPtr in
                var offset = 0
                for _ in 0..<toReadTriangles {
                    // Skip normal vector (12 bytes)
                    offset += 12

                    // Vertex 1
                    let v0x = Double(Float(bitPattern: UInt32(littleEndian: rawPtr.loadUnaligned(fromByteOffset: offset, as: UInt32.self))))
                    let v0y = Double(Float(bitPattern: UInt32(littleEndian: rawPtr.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))))
                    let v0z = Double(Float(bitPattern: UInt32(littleEndian: rawPtr.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self))))
                    offset += 12

                    // Vertex 2
                    let v1x = Double(Float(bitPattern: UInt32(littleEndian: rawPtr.loadUnaligned(fromByteOffset: offset, as: UInt32.self))))
                    let v1y = Double(Float(bitPattern: UInt32(littleEndian: rawPtr.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))))
                    let v1z = Double(Float(bitPattern: UInt32(littleEndian: rawPtr.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self))))
                    offset += 12

                    // Vertex 3
                    let v2x = Double(Float(bitPattern: UInt32(littleEndian: rawPtr.loadUnaligned(fromByteOffset: offset, as: UInt32.self))))
                    let v2y = Double(Float(bitPattern: UInt32(littleEndian: rawPtr.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))))
                    let v2z = Double(Float(bitPattern: UInt32(littleEndian: rawPtr.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self))))
                    offset += 12

                    // Skip attribute byte count (2 bytes)
                    offset += 2

                    minX = min(minX, v0x, v1x, v2x)
                    minY = min(minY, v0y, v1y, v2y)
                    minZ = min(minZ, v0z, v1z, v2z)
                    maxX = max(maxX, v0x, v1x, v2x)
                    maxY = max(maxY, v0y, v1y, v2y)
                    maxZ = max(maxZ, v0z, v1z, v2z)
                }
            }

            remainingTriangles -= toReadTriangles
        }

        return AxisAlignedBoundingBox(
            min: SIMD3<Double>(minX, minY, minZ),
            max: SIMD3<Double>(maxX, maxY, maxZ)
        )
    }

    @inline(__always)
    private static func appendFloatLE(_ value: Float, to buffer: inout [UInt8]) {
        var le = value.bitPattern.littleEndian
        withUnsafeBytes(of: &le) { buffer.append(contentsOf: $0) }
    }
}
