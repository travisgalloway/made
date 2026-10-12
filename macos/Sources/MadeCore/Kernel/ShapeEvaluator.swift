import Foundation
import Euclid

/// Turns a validated shape tree into a Euclid mesh. Only `LocalKernelEngine` calls it, on the engine actor (invariant 1).
enum ShapeEvaluator {
    static func mesh(for node: ShapeNode) -> Euclid.Mesh {
        switch node {
        case .box(let p):
            return EuclidEngine.makeBox(width: p.width, depth: p.depth, height: p.height)
        case .cylinder(let p, let slices):
            return EuclidEngine.makeCylinder(radius: p.radius, height: p.height, slices: slices)
        case .translate(let child, let offset):
            return mesh(for: child).translated(by: Vector(Double(offset.x), Double(offset.y), Double(offset.z)))
        case .boolean(let op, let lhs, let rhs):
            let a = mesh(for: lhs), b = mesh(for: rhs)
            switch op {
            case .subtract: return EuclidEngine.subtract(a, b)
            case .union: return EuclidEngine.union(a, b)
            case .intersect: return EuclidEngine.intersect(a, b)
            }
        }
    }
}
