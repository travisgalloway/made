import Foundation
import Euclid
import simd

public enum EuclidEngine {
    /// Converts a Euclid.Mesh into a GPU-ready indexed MeshPayload in right-handed Z-up coordinates.
    public static func toMeshPayload(_ mesh: Mesh) -> MeshPayload {
        let triangulated = mesh.triangulate()
        var positions: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []
        
        var currentIndex: UInt32 = 0
        for polygon in triangulated.polygons {
            let verts = polygon.vertices
            guard verts.count >= 3 else { continue }
            
            // Standard triangulation (fan or 3-vert polygon)
            for i in 1..<(verts.count - 1) {
                let v0 = verts[0]
                let v1 = verts[i]
                let v2 = verts[i + 1]
                
                positions.append(Float(v0.position.x))
                positions.append(Float(v0.position.y))
                positions.append(Float(v0.position.z))
                normals.append(Float(v0.normal.x))
                normals.append(Float(v0.normal.y))
                normals.append(Float(v0.normal.z))
                
                positions.append(Float(v1.position.x))
                positions.append(Float(v1.position.y))
                positions.append(Float(v1.position.z))
                normals.append(Float(v1.normal.x))
                normals.append(Float(v1.normal.y))
                normals.append(Float(v1.normal.z))
                
                positions.append(Float(v2.position.x))
                positions.append(Float(v2.position.y))
                positions.append(Float(v2.position.z))
                normals.append(Float(v2.normal.x))
                normals.append(Float(v2.normal.y))
                normals.append(Float(v2.normal.z))
                
                indices.append(currentIndex)
                indices.append(currentIndex + 1)
                indices.append(currentIndex + 2)
                currentIndex += 3
            }
        }
        
        return MeshPayload(positions: positions, normals: normals, indices: indices)
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
