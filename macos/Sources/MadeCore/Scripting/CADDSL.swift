import Foundation
import Euclid
import simd

// MARK: - Cadova-Inspired Declarative CAD DSL

public protocol CADShape: Sendable {
    func buildMesh() -> Mesh
}

public struct CSGCompositeShape: CADShape, Sendable {
    private let mesh: Mesh
    
    public init(mesh: Mesh) {
        self.mesh = mesh
    }
    
    public func buildMesh() -> Mesh {
        return mesh
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
    
    public func buildMesh() -> Mesh {
        var m = EuclidEngine.makeBox(width: width, depth: depth, height: height)
        if offset != .zero {
            m = m.translated(by: Vector(Double(offset.x), Double(offset.y), Double(offset.z)))
        }
        return m
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
    
    public func buildMesh() -> Mesh {
        var m = EuclidEngine.makeCylinder(radius: radius, height: height, slices: slices)
        if offset != .zero {
            m = m.translated(by: Vector(Double(offset.x), Double(offset.y), Double(offset.z)))
        }
        return m
    }
}

// MARK: - Declarative Modifiers and Operators

extension CADShape {
    public func translated(x: Float = 0, y: Float = 0, z: Float = 0) -> CSGCompositeShape {
        let m = self.buildMesh().translated(by: Vector(Double(x), Double(y), Double(z)))
        return CSGCompositeShape(mesh: m)
    }
    
    public func subtracting(_ other: any CADShape) -> CSGCompositeShape {
        let result = EuclidEngine.subtract(self.buildMesh(), other.buildMesh())
        return CSGCompositeShape(mesh: result)
    }
    
    public func subtracting(@CADShapeBuilder _ other: () -> any CADShape) -> CSGCompositeShape {
        return self.subtracting(other())
    }
    
    public func union(_ other: any CADShape) -> CSGCompositeShape {
        let result = EuclidEngine.union(self.buildMesh(), other.buildMesh())
        return CSGCompositeShape(mesh: result)
    }
    
    public func union(@CADShapeBuilder _ other: () -> any CADShape) -> CSGCompositeShape {
        return self.union(other())
    }
    
    public func intersecting(_ other: any CADShape) -> CSGCompositeShape {
        let result = EuclidEngine.intersect(self.buildMesh(), other.buildMesh())
        return CSGCompositeShape(mesh: result)
    }
    
    public func toMeshPayload() -> MeshPayload {
        return EuclidEngine.toMeshPayload(self.buildMesh())
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
