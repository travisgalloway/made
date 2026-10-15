import Foundation
import simd
import CoreGraphics

/// Pure mathematical model for the interactive 3D View Cube widget.
/// Complies with Invariant 2 (on-demand redraws) and Invariant 8 (gesture separation).
public struct ViewCube: Sendable {

    /// Standard 6 orthogonal cube faces.
    public enum Face: String, CaseIterable, Identifiable, Sendable, Comparable {
        case top = "TOP"
        case bottom = "BOTTOM"
        case front = "FRONT"
        case back = "BACK"
        case right = "RIGHT"
        case left = "LEFT"

        public var id: String { rawValue }

        public static func < (lhs: Face, rhs: Face) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// Outward unit normal vector in right-handed +Z up coordinate space.
        public var normal: SIMD3<Float> {
            switch self {
            case .top:    return SIMD3<Float>(0, 0, 1)
            case .bottom: return SIMD3<Float>(0, 0, -1)
            case .front:  return SIMD3<Float>(0, -1, 0)
            case .back:   return SIMD3<Float>(0, 1, 0)
            case .right:  return SIMD3<Float>(1, 0, 0)
            case .left:   return SIMD3<Float>(-1, 0, 0)
            }
        }

        /// Corresponding viewport perspective preset.
        public var perspective: ViewportPerspective {
            switch self {
            case .top:    return .top
            case .bottom: return .bottom
            case .front:  return .front
            case .back:   return .back
            case .right:  return .right
            case .left:   return .left
            }
        }

        /// 4 vertices in counter-clockwise winding order on the unit cube $[-1, 1]^3$.
        public var vertices3D: [SIMD3<Float>] {
            switch self {
            case .top:
                return [
                    SIMD3<Float>(-1, -1, 1),
                    SIMD3<Float>(1, -1, 1),
                    SIMD3<Float>(1, 1, 1),
                    SIMD3<Float>(-1, 1, 1)
                ]
            case .bottom:
                return [
                    SIMD3<Float>(-1, -1, -1),
                    SIMD3<Float>(-1, 1, -1),
                    SIMD3<Float>(1, 1, -1),
                    SIMD3<Float>(1, -1, -1)
                ]
            case .front:
                return [
                    SIMD3<Float>(-1, -1, -1),
                    SIMD3<Float>(1, -1, -1),
                    SIMD3<Float>(1, -1, 1),
                    SIMD3<Float>(-1, -1, 1)
                ]
            case .back:
                return [
                    SIMD3<Float>(1, 1, -1),
                    SIMD3<Float>(-1, 1, -1),
                    SIMD3<Float>(-1, 1, 1),
                    SIMD3<Float>(1, 1, 1)
                ]
            case .right:
                return [
                    SIMD3<Float>(1, -1, -1),
                    SIMD3<Float>(1, 1, -1),
                    SIMD3<Float>(1, 1, 1),
                    SIMD3<Float>(1, -1, 1)
                ]
            case .left:
                return [
                    SIMD3<Float>(-1, 1, -1),
                    SIMD3<Float>(-1, -1, -1),
                    SIMD3<Float>(-1, -1, 1),
                    SIMD3<Float>(-1, 1, 1)
                ]
            }
        }
    }

    /// Selectable regions: 6 faces, 12 edges, 8 corners, and 1 home reset.
    public enum Region: Sendable, Equatable, Hashable {
        case face(Face)
        case edge(Face, Face)
        case corner(Face, Face, Face)
        case home

        /// Normalized camera view direction vector for this region.
        public var direction: SIMD3<Float> {
            switch self {
            case .home:
                return simd_normalize(SIMD3<Float>(1, -1, 1))
            case .face(let f):
                return f.normal
            case .edge(let f1, let f2):
                return simd_normalize(f1.normal + f2.normal)
            case .corner(let f1, let f2, let f3):
                return simd_normalize(f1.normal + f2.normal + f3.normal)
            }
        }

        /// Returns true if this region contains or borders the given face.
        public func contains(face: Face) -> Bool {
            switch self {
            case .home:
                return false
            case .face(let f):
                return f == face
            case .edge(let f1, let f2):
                return f1 == face || f2 == face
            case .corner(let f1, let f2, let f3):
                return f1 == face || f2 == face || f3 == face
            }
        }

        public static func == (lhs: Region, rhs: Region) -> Bool {
            switch (lhs, rhs) {
            case (.home, .home):
                return true
            case (.face(let f1), .face(let f2)):
                return f1 == f2
            case (.edge(let a1, let a2), .edge(let b1, let b2)):
                return (a1 == b1 && a2 == b2) || (a1 == b2 && a2 == b1)
            case (.corner(let a1, let a2, let a3), .corner(let b1, let b2, let b3)):
                let setA = Set([a1, a2, a3])
                let setB = Set([b1, b2, b3])
                return setA == setB
            default:
                return false
            }
        }

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .home:
                hasher.combine(0)
            case .face(let f):
                hasher.combine(1)
                hasher.combine(f)
            case .edge(let f1, let f2):
                hasher.combine(2)
                if f1 < f2 {
                    hasher.combine(f1)
                    hasher.combine(f2)
                } else {
                    hasher.combine(f2)
                    hasher.combine(f1)
                }
            case .corner(let f1, let f2, let f3):
                hasher.combine(3)
                let sorted = [f1, f2, f3].sorted()
                hasher.combine(sorted[0])
                hasher.combine(sorted[1])
                hasher.combine(sorted[2])
            }
        }

        public var displayName: String {
            switch self {
            case .home:
                return "Home"
            case .face(let f):
                return f.rawValue
            case .edge(let f1, let f2):
                let sorted = [f1, f2].sorted()
                return "\(sorted[0].rawValue)-\(sorted[1].rawValue)"
            case .corner(let f1, let f2, let f3):
                let sorted = [f1, f2, f3].sorted()
                return "\(sorted[0].rawValue)-\(sorted[1].rawValue)-\(sorted[2].rawValue)"
            }
        }
    }

    /// Projected 2D face geometry ready for SwiftUI Canvas/Path rendering.
    public struct ProjectedFace: Sendable, Identifiable {
        public var id: String { face.rawValue }
        public let face: Face
        public let vertices: [SIMD2<Float>]
        public let center: SIMD2<Float>
        public let depth: Float

        public init(face: Face, vertices: [SIMD2<Float>], center: SIMD2<Float>, depth: Float) {
            self.face = face
            self.vertices = vertices
            self.center = center
            self.depth = depth
        }
    }

    /// Extracts the 3x3 camera rotation matrix from Orientation.makeLookAt.
    public static func rotationMatrix(for camera: Camera) -> simd_float3x3 {
        let V = Orientation.makeLookAt(eye: camera.position, target: camera.target)
        return simd_float3x3(
            SIMD3<Float>(V.columns.0.x, V.columns.0.y, V.columns.0.z),
            SIMD3<Float>(V.columns.1.x, V.columns.1.y, V.columns.1.z),
            SIMD3<Float>(V.columns.2.x, V.columns.2.y, V.columns.2.z)
        )
    }

    /// Computes projected 2D visible faces with back-face culling for the current camera.
    public static func projectedFaces(
        camera: Camera,
        size: CGSize,
        scaleFactor: Float = 0.28
    ) -> [ProjectedFace] {
        let scale = Float(min(size.width, size.height)) * scaleFactor
        guard scale > 1e-4 else { return [] }
        let cx = Float(size.width) * 0.5
        let cy = Float(size.height) * 0.5

        let R = rotationMatrix(for: camera)
        let eyeDir = simd_normalize(camera.position - camera.target)

        var visibleFaces: [ProjectedFace] = []

        for face in Face.allCases {
            // Front-facing test: face normal points toward camera eye
            let dot = simd_dot(face.normal, eyeDir)
            guard dot > 0.001 else { continue }

            var vertices2D: [SIMD2<Float>] = []
            for v in face.vertices3D {
                let camV = R * v
                let px = cx + camV.x * scale
                let py = cy - camV.y * scale
                vertices2D.append(SIMD2<Float>(px, py))
            }

            let camCenter = R * face.normal
            let center2D = SIMD2<Float>(cx + camCenter.x * scale, cy - camCenter.y * scale)

            visibleFaces.append(ProjectedFace(
                face: face,
                vertices: vertices2D,
                center: center2D,
                depth: camCenter.z
            ))
        }

        // Sort by depth ascending so further faces are drawn first
        return visibleFaces.sorted { $0.depth < $1.depth }
    }

    /// Hit-tests a 2D screen coordinate against the 3D cube partitioned into faces, edges, and corners.
    public static func hitTest(
        point: CGPoint,
        in size: CGSize,
        camera: Camera,
        edgeThreshold: Float = 0.65,
        scaleFactor: Float = 0.28
    ) -> Region? {
        let scale = Float(min(size.width, size.height)) * scaleFactor
        guard scale > 1e-4 else { return nil }
        let cx = Float(size.width) * 0.5
        let cy = Float(size.height) * 0.5

        let px = Float(point.x)
        let py = Float(point.y)

        // Screen coordinate maps to camera-space orthographic ray
        let camRayOrigin = SIMD3<Float>((px - cx) / scale, -(py - cy) / scale, 5.0)
        let camRayDir = SIMD3<Float>(0, 0, -1)

        // Unproject ray into world cube space
        let R = rotationMatrix(for: camera)
        let invR = R.transpose
        let worldRayOrigin = invR * camRayOrigin
        let worldRayDir = invR * camRayDir

        // Intersect ray with unit cube [-1, 1]^3 using standard slab method
        var tMin: Float = -Float.greatestFiniteMagnitude
        var tMax: Float = Float.greatestFiniteMagnitude

        for i in 0..<3 {
            let o = worldRayOrigin[i]
            let d = worldRayDir[i]
            if abs(d) < 1e-6 {
                if o < -1.0 || o > 1.0 {
                    return nil
                }
            } else {
                let invD = 1.0 / d
                var t1 = (-1.0 - o) * invD
                var t2 = (1.0 - o) * invD
                if t1 > t2 { swap(&t1, &t2) }
                tMin = max(tMin, t1)
                tMax = min(tMax, t2)
                if tMin > tMax {
                    return nil
                }
            }
        }

        guard tMax >= 0 else { return nil }
        let tHit = tMin > 0 ? tMin : 0.0
        let rawHit = worldRayOrigin + worldRayDir * tHit
        let h = SIMD3<Float>(
            min(max(rawHit.x, -1.0), 1.0),
            min(max(rawHit.y, -1.0), 1.0),
            min(max(rawHit.z, -1.0), 1.0)
        )

        // Determine primary face by maximum absolute coordinate
        let absX = abs(h.x)
        let absY = abs(h.y)
        let absZ = abs(h.z)

        let primaryFace: Face
        let c1Val: Float
        let c2Val: Float
        let faceForC1: Face
        let faceForC2: Face

        if absX >= absY && absX >= absZ {
            primaryFace = h.x > 0 ? .right : .left
            c1Val = h.y
            c2Val = h.z
            faceForC1 = h.y > 0 ? .back : .front
            faceForC2 = h.z > 0 ? .top : .bottom
        } else if absY >= absX && absY >= absZ {
            primaryFace = h.y > 0 ? .back : .front
            c1Val = h.x
            c2Val = h.z
            faceForC1 = h.x > 0 ? .right : .left
            faceForC2 = h.z > 0 ? .top : .bottom
        } else {
            primaryFace = h.z > 0 ? .top : .bottom
            c1Val = h.x
            c2Val = h.y
            faceForC1 = h.x > 0 ? .right : .left
            faceForC2 = h.y > 0 ? .back : .front
        }

        let c1Edge = abs(c1Val) >= edgeThreshold
        let c2Edge = abs(c2Val) >= edgeThreshold

        if c1Edge && c2Edge {
            return .corner(primaryFace, faceForC1, faceForC2)
        } else if c1Edge {
            return .edge(primaryFace, faceForC1)
        } else if c2Edge {
            return .edge(primaryFace, faceForC2)
        } else {
            return .face(primaryFace)
        }
    }

    /// Computes a safe, properly framed camera oriented toward the given region.
    public static func camera(
        for region: Region,
        target: SIMD3<Float> = Camera.defaultTarget,
        distance: Float = 150.0
    ) -> Camera {
        switch region {
        case .home:
            return Camera.preset(.isometric, target: target, distance: distance)
        case .face(let face):
            return Camera.preset(face.perspective, target: target, distance: distance)
        case .edge, .corner:
            var dir = region.direction
            // Singular up-vector protection: if dir is parallel to worldUp, apply tiny offset
            if abs(dir.z) > 0.999 && abs(dir.x) < 1e-3 && abs(dir.y) < 1e-3 {
                dir = simd_normalize(dir + SIMD3<Float>(0, 0.001, 0))
            }
            return Camera(position: target + dir * distance, target: target)
        }
    }
}
