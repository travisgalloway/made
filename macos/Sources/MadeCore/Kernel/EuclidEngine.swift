import Foundation
import Euclid
import simd

public enum EuclidEngine {
    /// Converts a Euclid.Mesh into a GPU-ready indexed MeshPayload in right-handed Z-up coordinates.
    /// Counts triangles first so the vertices are written once, straight into shared storage.
    public static func toMeshPayload(_ mesh: Mesh) -> MeshPayload {
        let polygons = mesh.triangulate().polygons.filter { $0.vertices.count >= 3 }
        let triangleCount = polygons.reduce(0) { $0 + $1.vertices.count - 2 }
        let floatCount = triangleCount * 9
        
        let storage = MeshStorage(positionCount: floatCount, normalCount: floatCount, indexCount: triangleCount * 3) { positions, normals, indices in
            var f = 0
            var currentIndex: UInt32 = 0
            for polygon in polygons {
                let verts = polygon.vertices
                // Standard triangulation (fan or 3-vert polygon)
                for i in 1..<(verts.count - 1) {
                    for v in [verts[0], verts[i], verts[i + 1]] {
                        positions[f] = Float(v.position.x)
                        positions[f + 1] = Float(v.position.y)
                        positions[f + 2] = Float(v.position.z)
                        normals[f] = Float(v.normal.x)
                        normals[f + 1] = Float(v.normal.y)
                        normals[f + 2] = Float(v.normal.z)
                        f += 3
                        indices[Int(currentIndex)] = currentIndex
                        currentIndex += 1
                    }
                }
            }
        }
        return MeshPayload(storage: storage)
    }
    
    /// Generates a box mesh using Euclid.
    public static func makeBox(width: Float, depth: Float, height: Float) -> Mesh {
        return Mesh.cube(
            size: Vector(Double(width), Double(depth), Double(height))
        )
    }
    
    /// Generates a cylinder mesh aligned along the Z axis using Euclid.
    public static func makeCylinder(radius: Float, height: Float, slices: Int = 32) -> Mesh {
        // Euclid cylinders default along Y axis or Z axis; we rotate or orient to Z-up
        let cyl = Mesh.cylinder(
            radius: Double(radius),
            height: Double(height),
            slices: max(8, slices)
        )
        // Orient so height is along +Z axis
        return cyl.rotated(by: .pitch(.halfPi))
    }
    
    /// Performs a Constructive Solid Geometry (CSG) boolean difference: meshA - meshB
    public static func subtract(_ meshA: Mesh, _ meshB: Mesh) -> Mesh {
        return meshA.subtracting(meshB)
    }
    
    /// Performs a CSG boolean union: meshA + meshB
    public static func union(_ meshA: Mesh, _ meshB: Mesh) -> Mesh {
        return meshA.union(meshB)
    }
    
    /// Performs a CSG boolean intersection: meshA & meshB
    public static func intersect(_ meshA: Mesh, _ meshB: Mesh) -> Mesh {
        return meshA.intersection(meshB)
    }
}
