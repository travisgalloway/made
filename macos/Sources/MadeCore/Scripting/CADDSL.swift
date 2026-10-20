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
    public static let emptyBlockMessage = "CADShapeBuilder block cannot be empty"

    #if DEBUG
    public nonisolated(unsafe) static var emptyBlockHandler: ((String) -> Void)?
    #endif

    public static func buildExpression(_ shape: any CADShape) -> [any CADShape] {
        [shape]
    }

    public static func buildBlock(_ components: [any CADShape]...) -> [any CADShape] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [any CADShape]?) -> [any CADShape] {
        component ?? []
    }

    public static func buildEither(first component: [any CADShape]) -> [any CADShape] {
        component
    }

    public static func buildEither(second component: [any CADShape]) -> [any CADShape] {
        component
    }

    public static func buildArray(_ components: [[any CADShape]]) -> [any CADShape] {
        components.flatMap { $0 }
    }

    public static func buildFinalResult(_ component: [any CADShape]) -> any CADShape {
        guard let first = component.first else {
            #if DEBUG
            if let handler = emptyBlockHandler {
                handler(emptyBlockMessage)
                return CSGCompositeShape(shapeDescription: .box(BoxParams(width: 0, depth: 0, height: 0)))
            }
            #endif
            preconditionFailure(emptyBlockMessage)
        }
        return component.dropFirst().reduce(first) { $0.union($1) }
    }
}

/// Evaluates a `@CADShapeBuilder` closure into a single `CADShape`.
public func shape(@CADShapeBuilder _ content: () -> any CADShape) -> any CADShape {
    content()
}

