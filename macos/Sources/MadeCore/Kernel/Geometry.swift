import Foundation
import simd

public enum NativeGeometryGenerator {
    /// Generates an indexed triangular mesh for a box with width (X), depth (Y), and height (Z).
    /// Follows the right-handed Z-up orientation convention (orientation.ts).
    public static func generateBox(width: Float, depth: Float, height: Float) -> MeshPayload {
        let hx = width / 2.0
        let hy = depth / 2.0
        let hz = height / 2.0
        
        // 6 faces, 4 vertices per face to ensure sharp flat face normals (24 vertices total)
        var positions: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []
        
        func addQuad(
            v0: SIMD3<Float>,
            v1: SIMD3<Float>,
            v2: SIMD3<Float>,
            v3: SIMD3<Float>,
            normal: SIMD3<Float>
        ) {
            let baseIndex = UInt32(positions.count / 3)
            let verts = [v0, v1, v2, v3]
            for v in verts {
                positions.append(contentsOf: [v.x, v.y, v.z])
                normals.append(contentsOf: [normal.x, normal.y, normal.z])
            }
            indices.append(contentsOf: [
                baseIndex, baseIndex + 1, baseIndex + 2,
                baseIndex, baseIndex + 2, baseIndex + 3
            ])
        }
        
        // +Z face (Top)
        addQuad(
            v0: SIMD3<Float>(-hx, -hy, hz),
            v1: SIMD3<Float>( hx, -hy, hz),
            v2: SIMD3<Float>( hx,  hy, hz),
            v3: SIMD3<Float>(-hx,  hy, hz),
            normal: SIMD3<Float>(0, 0, 1)
        )
        // -Z face (Bottom)
        addQuad(
            v0: SIMD3<Float>(-hx,  hy, -hz),
            v1: SIMD3<Float>( hx,  hy, -hz),
            v2: SIMD3<Float>( hx, -hy, -hz),
            v3: SIMD3<Float>(-hx, -hy, -hz),
            normal: SIMD3<Float>(0, 0, -1)
        )
        // +X face (Right)
        addQuad(
            v0: SIMD3<Float>(hx, -hy, -hz),
            v1: SIMD3<Float>(hx,  hy, -hz),
            v2: SIMD3<Float>(hx,  hy,  hz),
            v3: SIMD3<Float>(hx, -hy,  hz),
            normal: SIMD3<Float>(1, 0, 0)
        )
        // -X face (Left)
        addQuad(
            v0: SIMD3<Float>(-hx,  hy, -hz),
            v1: SIMD3<Float>(-hx, -hy, -hz),
            v2: SIMD3<Float>(-hx, -hy,  hz),
            v3: SIMD3<Float>(-hx,  hy,  hz),
            normal: SIMD3<Float>(-1, 0, 0)
        )
        // +Y face (Back / Away)
        addQuad(
            v0: SIMD3<Float>( hx, hy, -hz),
            v1: SIMD3<Float>(-hx, hy, -hz),
            v2: SIMD3<Float>(-hx, hy,  hz),
            v3: SIMD3<Float>( hx, hy,  hz),
            normal: SIMD3<Float>(0, 1, 0)
        )
        // -Y face (Front)
        addQuad(
            v0: SIMD3<Float>(-hx, -hy, -hz),
            v1: SIMD3<Float>( hx, -hy, -hz),
            v2: SIMD3<Float>( hx, -hy,  hz),
            v3: SIMD3<Float>(-hx, -hy,  hz),
            normal: SIMD3<Float>(0, -1, 0)
        )
        
        return MeshPayload(positions: positions, normals: normals, indices: indices)
    }
    
    /// Generates an indexed triangular mesh for a cylinder aligned with +Z height.
    public static func generateCylinder(radius: Float, height: Float, segments: Int = 32) -> MeshPayload {
        let hz = height / 2.0
        var positions: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []
        
        let segCount = max(8, segments)
        let angleStep = (2.0 * Float.pi) / Float(segCount)
        
        // 1. Side wall
        let sideBaseIndex = UInt32(positions.count / 3)
        for i in 0...segCount {
            let angle = Float(i) * angleStep
            let cosA = cos(angle)
            let sinA = sin(angle)
            let nx = cosA
            let ny = sinA
            
            // Bottom vertex
            positions.append(contentsOf: [radius * cosA, radius * sinA, -hz])
            normals.append(contentsOf: [nx, ny, 0])
            
            // Top vertex
            positions.append(contentsOf: [radius * cosA, radius * sinA, hz])
            normals.append(contentsOf: [nx, ny, 0])
        }
        
        for i in 0..<UInt32(segCount) {
            let b0 = sideBaseIndex + i * 2
            let t0 = b0 + 1
            let b1 = b0 + 2
            let t1 = b0 + 3
            indices.append(contentsOf: [b0, b1, t0, b1, t1, t0])
        }
        
        // 2. Top cap (+Z)
        let topCenterIndex = UInt32(positions.count / 3)
        positions.append(contentsOf: [0, 0, hz])
        normals.append(contentsOf: [0, 0, 1])
        
        let topRimBase = UInt32(positions.count / 3)
        for i in 0...segCount {
            let angle = Float(i) * angleStep
            positions.append(contentsOf: [radius * cos(angle), radius * sin(angle), hz])
            normals.append(contentsOf: [0, 0, 1])
        }
        for i in 0..<UInt32(segCount) {
            indices.append(contentsOf: [topCenterIndex, topRimBase + i, topRimBase + i + 1])
        }
        
        // 3. Bottom cap (-Z)
        let bottomCenterIndex = UInt32(positions.count / 3)
        positions.append(contentsOf: [0, 0, -hz])
        normals.append(contentsOf: [0, 0, -1])
        
        let bottomRimBase = UInt32(positions.count / 3)
        for i in 0...segCount {
            let angle = Float(i) * angleStep
            positions.append(contentsOf: [radius * cos(angle), radius * sin(angle), -hz])
            normals.append(contentsOf: [0, 0, -1])
        }
        for i in 0..<UInt32(segCount) {
            indices.append(contentsOf: [bottomCenterIndex, bottomRimBase + i + 1, bottomRimBase + i])
        }
        
        return MeshPayload(positions: positions, normals: normals, indices: indices)
    }
}
