import Foundation
import Observation
import simd

public typealias ObjectId = SolidId

public struct Transform: Sendable, Equatable {
    public var position: SIMD3<Float>
    public var rotation: simd_quatf
    public var scale: SIMD3<Float>
    
    public static let identity = Transform(
        position: SIMD3<Float>(0, 0, 0),
        rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        scale: SIMD3<Float>(1, 1, 1)
    )
    
    public init(
        position: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
    
    public func transformPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let scaled = point * scale
        let rotated = rotation.act(scaled)
        return rotated + position
    }
}

public enum ObjectDef: Sendable, Equatable {
    case box(BoxParams)
    case cylinder(CylinderParams)
    case imported(name: String)
    
    public var kind: String {
        switch self {
        case .box: return "box"
        case .cylinder: return "cylinder"
        case .imported: return "imported"
        }
    }
}

public struct MaterialAttributes: Sendable, Equatable {
    public var color: SIMD4<Float>
    public var roughness: Float
    public var opacity: Float
    
    public init(
        color: SIMD4<Float> = SIMD4<Float>(0.35, 0.65, 0.95, 1.0),
        roughness: Float = 0.5,
        opacity: Float = 1.0
    ) {
        self.color = color
        self.roughness = roughness
        self.opacity = opacity
    }
}

public enum SimulationBodyType: String, Sendable, CaseIterable, Identifiable {
    case dynamicBody = "Dynamic"
    case staticBody = "Static"
    case kinematicBody = "Kinematic"
    
    public var id: String { rawValue }
}

public struct SimulationParameters: Sendable, Equatable {
    public var bodyType: SimulationBodyType
    public var mass: Float // kg
    public var friction: Float
    public var restitution: Float // bounciness
    
    public init(
        bodyType: SimulationBodyType = .dynamicBody,
        mass: Float = 1.0,
        friction: Float = 0.5,
        restitution: Float = 0.1
    ) {
        self.bodyType = bodyType
        self.mass = mass
        self.friction = friction
        self.restitution = restitution
    }
}

public struct SceneObject: Identifiable, Sendable, Equatable {
    public let id: ObjectId
    public var name: String
    public var def: ObjectDef
    public var transform: Transform
    public var layer: String
    public var isVisible: Bool
    public var isLocked: Bool
    public var material: MaterialAttributes
    public var simulation: SimulationParameters
    
    public init(
        id: ObjectId,
        name: String? = nil,
        def: ObjectDef,
        transform: Transform = .identity,
        layer: String = "Default Layer",
        isVisible: Bool = true,
        isLocked: Bool = false,
        material: MaterialAttributes = MaterialAttributes(),
        simulation: SimulationParameters = SimulationParameters()
    ) {
        self.id = id
        self.name = name ?? id.rawValue
        self.def = def
        self.transform = transform
        self.layer = layer
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.material = material
        self.simulation = simulation
    }
}

public struct ParamRange: Sendable {
    public let min: Float
    public let max: Float
    
    public func clamp(_ value: Float) -> Float {
        if value.isNaN { return min }
        return Swift.min(max, Swift.max(min, value))
    }
}

public enum DocumentLimits {
    public static let boxWidth = ParamRange(min: 5, max: 90)
    public static let boxDepth = ParamRange(min: 5, max: 90)
    public static let boxHeight = ParamRange(min: 5, max: 90)
    
    public static let cylinderRadius = ParamRange(min: 5, max: 50)
    public static let cylinderHeight = ParamRange(min: 5, max: 90)
    
    public static func clampBox(key: String, value: Float) -> Float {
        switch key {
        case "width": return boxWidth.clamp(value)
        case "depth": return boxDepth.clamp(value)
        case "height": return boxHeight.clamp(value)
        default: return value
        }
    }
    
    public static func clampCylinder(key: String, value: Float) -> Float {
        switch key {
        case "radius": return cylinderRadius.clamp(value)
        case "height": return cylinderHeight.clamp(value)
        default: return value
        }
    }
}

public let boxSolidId = SolidId("box-1")
public let cylinderSolidId = SolidId("cylinder-1")

@Observable
public final class DocumentModel: @unchecked Sendable {
    public private(set) var objects: [SceneObject] = []
    private var seq: Int = 1
    
    public init() {
        // Initialize with default box and cylinder matching document.svelte.ts
        objects = [
            SceneObject(
                id: boxSolidId,
                def: .box(BoxParams(width: 40, depth: 30, height: 20)),
                transform: .identity
            ),
            SceneObject(
                id: cylinderSolidId,
                def: .cylinder(CylinderParams(radius: 15, height: 40)),
                transform: .identity
            )
        ]
    }
    
    public func paramsFor(id: ObjectId) -> ObjectDef? {
        return objects.first(where: { $0.id == id })?.def
    }
    
    @discardableResult
    public func addObject(def: ObjectDef, transform: Transform = .identity) -> ObjectId {
        seq += 1
        let id = ObjectId("\(def.kind)-\(seq)")
        let obj = SceneObject(id: id, def: def, transform: transform)
        objects.append(obj)
        return id
    }
    
    public func removeObject(id: ObjectId) {
        objects.removeAll(where: { $0.id == id })
    }
    
    public func setParam(id: ObjectId, key: String, value: Float) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        switch objects[index].def {
        case .box(var params):
            switch key {
            case "width": params.width = DocumentLimits.clampBox(key: "width", value: value)
            case "depth": params.depth = DocumentLimits.clampBox(key: "depth", value: value)
            case "height": params.height = DocumentLimits.clampBox(key: "height", value: value)
            default: break
            }
            objects[index].def = .box(params)
            
        case .cylinder(var params):
            switch key {
            case "radius": params.radius = DocumentLimits.clampCylinder(key: "radius", value: value)
            case "height": params.height = DocumentLimits.clampCylinder(key: "height", value: value)
            default: break
            }
            objects[index].def = .cylinder(params)
            
        case .imported:
            break
        }
    }
    
    public func setTransform(id: ObjectId, transform: Transform) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index].transform = transform
    }
    
    public func setName(id: ObjectId, name: String) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index].name = name
    }
    
    public func setVisibility(id: ObjectId, isVisible: Bool) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index].isVisible = isVisible
    }
    
    public func setLocked(id: ObjectId, isLocked: Bool) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index].isLocked = isLocked
    }
    
    public func setLayer(id: ObjectId, layer: String) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index].layer = layer
    }
    
    public func setMaterial(id: ObjectId, material: MaterialAttributes) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index].material = material
    }
    
    public func setSimulation(id: ObjectId, simulation: SimulationParameters) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index].simulation = simulation
    }
}
