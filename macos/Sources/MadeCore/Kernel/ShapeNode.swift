import Foundation
import simd

/// A shape description: an operation tree a script or the Swift DSL builds, and the kernel evaluates in one request (ADR-D6).
public indirect enum ShapeNode: Sendable, Codable, Equatable {
    case box(BoxParams)
    case cylinder(CylinderParams, slices: Int)
    case translate(ShapeNode, offset: SIMD3<Float>)
    case boolean(BooleanOp, ShapeNode, ShapeNode)
}

/// Bounds on a shape tree, shared by every producer so the kernel rejects a runaway tree before evaluating it.
public enum ShapeLimits {
    /// Nesting levels below the root, so a chain of `maxDepth` translates around a leaf is allowed.
    public static let maxDepth = 64
    public static let maxNodes = 4096
    public static let minSlices = 3
    public static let maxSlices = 512
}

extension ShapeNode {
    /// Returns the first problem found, or nil for a tree the kernel can evaluate.
    /// Iterative, so validating a hostile tree cannot overflow the stack.
    public func validate() -> KernelError? {
        var stack: [(node: ShapeNode, depth: Int)] = [(self, 0)]
        var count = 0
        while let (node, depth) = stack.popLast() {
            count += 1
            if count > ShapeLimits.maxNodes {
                return Self.invalid("Shape tree exceeds \(ShapeLimits.maxNodes) nodes")
            }
            if depth > ShapeLimits.maxDepth {
                return Self.invalid("Shape tree exceeds depth \(ShapeLimits.maxDepth)")
            }
            switch node {
            case .box(let p):
                if !Self.isPositive(p.width) || !Self.isPositive(p.depth) || !Self.isPositive(p.height) {
                    return Self.invalid("Shape tree box dimensions must be positive and finite")
                }
            case .cylinder(let p, let slices):
                if !Self.isPositive(p.radius) || !Self.isPositive(p.height) {
                    return Self.invalid("Shape tree cylinder dimensions must be positive and finite")
                }
                if !(ShapeLimits.minSlices...ShapeLimits.maxSlices).contains(slices) {
                    return Self.invalid("Shape tree cylinder slices must be within \(ShapeLimits.minSlices)...\(ShapeLimits.maxSlices)")
                }
            case .translate(let child, let offset):
                if !offset.x.isFinite || !offset.y.isFinite || !offset.z.isFinite {
                    return Self.invalid("Shape tree translate offset must be finite")
                }
                stack.append((child, depth + 1))
            case .boolean(_, let lhs, let rhs):
                stack.append((rhs, depth + 1))
                stack.append((lhs, depth + 1))
            }
        }
        return nil
    }

    private static func isPositive(_ value: Float) -> Bool { value.isFinite && value > 0 }

    private static func invalid(_ message: String) -> KernelError {
        KernelError(code: .invalidParams, message: message)
    }
}
