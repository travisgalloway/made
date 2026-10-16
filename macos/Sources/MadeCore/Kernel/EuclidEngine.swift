import Foundation
import Euclid
import simd

/// Pure-Swift Constructive Solid Geometry (CSG) engine powered by `nicklockwood/Euclid` (0.9.6).
///
/// **Tier 1 Fast CSG Engine (ADR-D1, ADR-D9 #247)**:
/// Euclid is permanently retained as `made`'s Tier 1 pure-Swift fast CSG preview engine and unit test backend.
/// It provides zero-C++ build times, sub-millisecond interactive parameter scrubbing in the Inspector,
/// instant procedural shape tree evaluation (`ShapeEvaluator`), and an in-process test fixture backend,
/// while OpenCASCADE Technology (OCCT) serves as the Tier 2 canonical B-Rep kernel (ADR-D1).
///
/// Adheres strictly to Invariant 4 (engine-neutral wire contract via `MeshPayload`) and
/// Invariant 1 (off-main-thread kernel execution).
public enum EuclidEngine {
    /// Converts a Euclid.Mesh into a GPU-ready indexed MeshPayload in right-handed Z-up coordinates.
    /// Counts triangles first so the vertices are written once, straight into shared storage.
    public static func toMeshPayload(_ mesh: Mesh) -> MeshPayload {
        let polygons = mesh.makeWatertight().triangulate().polygons.filter { $0.vertices.count >= 3 }
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
        var seenPositions = Set<SIMD3<Float>>()
        var vertexPoints: [VertexPoint] = []
        var nextVertexId = 0
        for polygon in polygons {
            for v in polygon.vertices {
                let p = SIMD3<Float>(Float(v.position.x), Float(v.position.y), Float(v.position.z))
                if seenPositions.insert(p).inserted {
                    vertexPoints.append(VertexPoint(vertexId: nextVertexId, position: p))
                    nextVertexId += 1
                }
            }
        }

        let faceRanges: [FaceTriangleRange] = triangleCount > 0 ? [FaceTriangleRange(faceId: 0, triangleRange: 0..<triangleCount)] : []
        return MeshPayload(
            storage: storage,
            faceRanges: faceRanges,
            edgePolylines: [],
            edgeSegmentRanges: [],
            vertexPoints: vertexPoints
        )
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
    
    /// Generates a sphere mesh centered at the origin with poles along the Z axis using Euclid.
    public static func makeSphere(radius: Float, slices: Int = 32) -> Mesh {
        let sph = Mesh.sphere(
            radius: Double(radius),
            slices: max(8, slices)
        )
        return sph.rotated(by: .pitch(.halfPi))
    }
    
    /// Generates a cone or frustum mesh aligned along the +Z axis using Euclid.
    public static func makeCone(bottomRadius: Float, topRadius: Float = 0, height: Float, slices: Int = 32) -> Mesh {
        let segs = max(8, slices)
        if topRadius <= 0 {
            let cone = Mesh.cone(
                radius: Double(bottomRadius),
                height: Double(height),
                slices: segs
            )
            return cone.rotated(by: .pitch(-.halfPi))
        }
        let h2 = Double(height) / 2.0
        let rBot = Double(bottomRadius)
        let rTop = Double(topRadius)
        let profile = Path([
            .point(0, h2),
            .point(-rTop, h2),
            .point(-rBot, -h2),
            .point(0, -h2),
        ])
        return Mesh.lathe(profile, slices: segs).rotated(by: .pitch(-.halfPi))
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
