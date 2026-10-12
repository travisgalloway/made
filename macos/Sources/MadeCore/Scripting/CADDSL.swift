import Foundation
import simd

// MARK: - Cadova-Inspired Declarative CAD DSL

/// A shape that only describes geometry. The kernel builds it, through `evaluate(on:solidId:jobId:)` (invariants 1 and 4).
public protocol CADShape: Sendable {
    var shapeDescription: ShapeNode { get }
}

public struct CSGCompositeShape: CADShape, Sendable {
    public let shapeDescription: ShapeNode
    
    public init(shapeDescription: ShapeNode) {
        self.shapeDescription = shapeDescription
    }
}

public struct Box: CADShape, Sendable {
    public var width: Float
    public var depth: Float
    public var height: Float
    public var offset: SIMD3<Float> = .zero
    
    public init(width: Float, depth: Float, height: Float) {
        self.width = width
        self.depth = depth
        self.height = height
    }
    
    public init(x: Float, y: Float, z: Float) {
        self.init(width: x, depth: y, height: z)
    }
    
    public var shapeDescription: ShapeNode {
        let node = ShapeNode.box(BoxParams(width: width, depth: depth, height: height))
        return offset == .zero ? node : .translate(node, offset: offset)
    }
}

public struct Cylinder: CADShape, Sendable {
    public var radius: Float
    public var height: Float
    public var slices: Int
    public var offset: SIMD3<Float> = .zero
    
    public init(radius: Float, height: Float, slices: Int = 32) {
        self.radius = radius
        self.height = height
        self.slices = slices
    }
    
    public init(diameter: Float, height: Float, slices: Int = 32) {
        self.init(radius: diameter / 2.0, height: height, slices: slices)
    }
    
    public var shapeDescription: ShapeNode {
        let node = ShapeNode.cylinder(CylinderParams(radius: radius, height: height), slices: slices)
        return offset == .zero ? node : .translate(node, offset: offset)
    }
}

// MARK: - Declarative Modifiers and Operators

extension CADShape {
    public func translated(x: Float = 0, y: Float = 0, z: Float = 0) -> CSGCompositeShape {
        CSGCompositeShape(shapeDescription: .translate(shapeDescription, offset: SIMD3(x, y, z)))
    }
    
    public func subtracting(_ other: any CADShape) -> CSGCompositeShape {
        CSGCompositeShape(shapeDescription: .boolean(.subtract, shapeDescription, other.shapeDescription))
    }
    
    public func subtracting(@CADShapeBuilder _ other: () -> any CADShape) -> CSGCompositeShape {
        return self.subtracting(other())
    }
    
    public func union(_ other: any CADShape) -> CSGCompositeShape {
        CSGCompositeShape(shapeDescription: .boolean(.union, shapeDescription, other.shapeDescription))
    }
    
    public func union(@CADShapeBuilder _ other: () -> any CADShape) -> CSGCompositeShape {
        return self.union(other())
    }
    
    public func intersecting(_ other: any CADShape) -> CSGCompositeShape {
        CSGCompositeShape(shapeDescription: .boolean(.intersect, shapeDescription, other.shapeDescription))
    }
    
    /// Sends the whole tree as one kernel request, so CSG runs on the kernel actor (invariants 1 and 4).
    public func evaluate(on kernel: any KernelClientProtocol, solidId: SolidId, jobId: JobId = JobId(UUID().uuidString)) async -> KernelResult<MeshPayload> {
        await kernel.request(.evaluateShape(jobId: jobId, solidId: solidId, shape: shapeDescription))
    }
}

// Operator overloads matching OCCTSwift and Cadova
public func - (lhs: any CADShape, rhs: any CADShape) -> CSGCompositeShape {
    return lhs.subtracting(rhs)
}

public func + (lhs: any CADShape, rhs: any CADShape) -> CSGCompositeShape {
    return lhs.union(rhs)
}

public func & (lhs: any CADShape, rhs: any CADShape) -> CSGCompositeShape {
    return lhs.intersecting(rhs)
}

@resultBuilder
public struct CADShapeBuilder {
    public static func buildBlock(_ shape: any CADShape) -> any CADShape {
        return shape
    }
}
