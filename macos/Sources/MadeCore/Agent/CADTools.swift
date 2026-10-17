import Foundation
import simd

public protocol SnapshotProvider: AnyObject, Sendable {
    func captureSnapshotPngBase64() async -> String?
    func captureSnapshotPngBase64(view: ViewportPerspective?) async -> String?
}

public extension SnapshotProvider {
    func captureSnapshotPngBase64(view: ViewportPerspective?) async -> String? {
        await captureSnapshotPngBase64()
    }
}

@MainActor
public final class CADToolRegistry {
    private let document: DocumentModel
    private let kernelClient: KernelClientProtocol
    public private(set) var partReloadController: PartReloadController
    private weak var snapshotProvider: (any SnapshotProvider)?
    private weak var meshSink: (any SolidMeshSink)?
    private let onViewportInvalidated: (@MainActor () -> Void)?
    private let onRecomputeResult: (@MainActor (KernelResult<MeshPayload>, SolidId) -> Void)?
    private var inFlightRecomputes: [SolidId: (jobId: JobId, task: Task<KernelResult<MeshPayload>, Never>)] = [:]
    
    public init(
        document: DocumentModel,
        kernelClient: KernelClientProtocol,
        partReloadController: PartReloadController? = nil,
        snapshotProvider: (any SnapshotProvider)? = nil,
        meshSink: (any SolidMeshSink)? = nil,
        onViewportInvalidated: (@MainActor () -> Void)? = nil,
        onRecomputeResult: (@MainActor (KernelResult<MeshPayload>, SolidId) -> Void)? = nil
    ) {
        self.document = document
        self.kernelClient = kernelClient
        self.snapshotProvider = snapshotProvider
        self.meshSink = meshSink
        self.onViewportInvalidated = onViewportInvalidated
        self.onRecomputeResult = onRecomputeResult
        self.partReloadController = partReloadController ?? PartReloadController(
            document: document,
            kernelClient: kernelClient,
            meshSink: meshSink,
            onViewportInvalidated: onViewportInvalidated
        )
    }
    
    public func setPartReloadController(_ controller: PartReloadController) {
        self.partReloadController = controller
    }
    
    public func setSnapshotProvider(_ provider: any SnapshotProvider) {
        self.snapshotProvider = provider
    }
    
    public func setMeshSink(_ sink: (any SolidMeshSink)?) {
        self.meshSink = sink
        self.partReloadController.setMeshSink(sink)
    }
    
    public nonisolated var tools: [MCPToolDefinition] {
        return [
            MCPToolDefinition(
                name: "cad_get_scene",
                description: "Retrieves the full list of objects in the CAD document with their IDs, types, parameters, and transforms.",
                inputSchema: MCPInputSchema(properties: [:])
            ),
            MCPToolDefinition(
                name: "cad_add_solid",
                description: "Adds a new parametric solid (box, cylinder, sphere, cone, torus, or wedge) to the CAD document.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "type": MCPProperty(type: "string", description: "The solid type: 'box', 'cylinder', 'sphere', 'cone', 'torus', or 'wedge'", enum: ["box", "cylinder", "sphere", "cone", "torus", "wedge"]),
                        "width": MCPProperty(type: "number", description: "Width (X dimension) for a box or wedge in mm"),
                        "depth": MCPProperty(type: "number", description: "Depth (Y dimension) for a box or wedge in mm"),
                        "height": MCPProperty(type: "number", description: "Height (Z dimension) in mm"),
                        "radius": MCPProperty(type: "number", description: "Radius in mm for a cylinder or sphere"),
                        "bottomRadius": MCPProperty(type: "number", description: "Bottom radius in mm for a cone"),
                        "topRadius": MCPProperty(type: "number", description: "Top radius in mm for a cone (0 for sharp cone)"),
                        "majorRadius": MCPProperty(type: "number", description: "Major radius in mm for a torus"),
                        "minorRadius": MCPProperty(type: "number", description: "Minor radius in mm for a torus"),
                        "topWidth": MCPProperty(type: "number", description: "Top width (ltx) in mm for a wedge (0 for sharp wedge)"),
                        "posX": MCPProperty(type: "number", description: "X world position in mm, from -10000 to 10000 (default 0)"),
                        "posY": MCPProperty(type: "number", description: "Y world position in mm, from -10000 to 10000 (default 0)"),
                        "posZ": MCPProperty(type: "number", description: "Z world position in mm, from -10000 to 10000 (default 0)")
                    ],
                    required: ["type"]
                )
            ),
            MCPToolDefinition(
                name: "cad_set_param",
                description: "Modifies a specific dimension/parameter of an existing solid (e.g. width, depth, height, radius, bottomRadius, topRadius, majorRadius, minorRadius, topWidth). Automatically clamped to safe ranges.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "The solid ID (e.g. 'box-1', 'cylinder-1', 'sphere-1', 'cone-1', 'torus-1', 'wedge-1')"),
                        "param": MCPProperty(type: "string", description: "The parameter name. Box: 'width', 'depth', 'height'. Cylinder: 'radius', 'height'. Sphere: 'radius'. Cone: 'bottomRadius', 'topRadius', 'height'. Torus: 'majorRadius', 'minorRadius'. Wedge: 'width', 'depth', 'height', 'topWidth'. Imported solids have no editable parameters."),
                        "value": MCPProperty(type: "number", description: "The new numeric value in mm")
                    ],
                    required: ["id", "param", "value"]
                )
            ),
            MCPToolDefinition(
                name: "cad_set_transform",
                description: "Updates the world position and rotation of an existing solid. Omitted coordinates and angles are unchanged.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "The solid ID"),
                        "posX": MCPProperty(type: "number", description: "X position in mm, from -10000 to 10000. Omitted coordinates are unchanged."),
                        "posY": MCPProperty(type: "number", description: "Y position in mm, from -10000 to 10000. Omitted coordinates are unchanged."),
                        "posZ": MCPProperty(type: "number", description: "Z position in mm, from -10000 to 10000. Omitted coordinates are unchanged."),
                        "rotX": MCPProperty(type: "number", description: "X rotation in degrees. Omitted angles are unchanged."),
                        "rotY": MCPProperty(type: "number", description: "Y rotation in degrees. Omitted angles are unchanged."),
                        "rotZ": MCPProperty(type: "number", description: "Z rotation in degrees. Omitted angles are unchanged.")
                    ],
                    required: ["id"]
                )
            ),
            MCPToolDefinition(
                name: "cad_remove_solid",
                description: "Deletes a solid from the CAD scene by its ID.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "The solid ID to remove")
                    ],
                    required: ["id"]
                )
            ),
            MCPToolDefinition(
                name: "cad_measure",
                description: "Calculates bounding box dimensions and volume estimates for an object.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "The solid ID to measure")
                    ],
                    required: ["id"]
                )
            ),
            MCPToolDefinition(
                name: "cad_boolean_operation",
                description: "Performs a Constructive Solid Geometry (CSG) boolean operation (subtract, union, or intersect) between two solids in the scene. Returns the new solid's ID, usable with the other tools.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "solidA": MCPProperty(type: "string", description: "Target solid ID (e.g. 'box-1')"),
                        "solidB": MCPProperty(type: "string", description: "Tool/cutter solid ID (e.g. 'cylinder-1')"),
                        "operation": MCPProperty(type: "string", description: "Operation: 'subtract', 'union', or 'intersect'", enum: ["subtract", "union", "intersect"]),
                        "keepTool": MCPProperty(type: "boolean", description: "Optional: If true, keep the tool solid visible. If false, hide both operands. When omitted, operand visibility is preserved.")
                    ],
                    required: ["solidA", "solidB", "operation"]
                )
            ),
            MCPToolDefinition(
                name: "cad_reload",
                description: "Re-evaluates a `.part.ts` or `.part.js` part file immediately (or opens and evaluates a part file path) and returns structured evaluation metadata or `file:line:column` diagnostics on failure.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "Optional solid ID of an open part in the scene (e.g. 'part-1')."),
                        "file": MCPProperty(type: "string", description: "Optional path to a `.part.ts` or `.part.js` file on disk. Opens the part if it is not already in the scene.")
                    ]
                )
            ),
            MCPToolDefinition(
                name: "cad_get_diagnostics",
                description: "Returns the last evaluation errors and warnings for open part files, each with `file`, `line`, `column`, and `message`.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "Optional solid ID to filter diagnostics to a single part."),
                        "file": MCPProperty(type: "string", description: "Optional file path to filter diagnostics to a single part file.")
                    ]
                )
            ),
            MCPToolDefinition(
                name: "cad_verify",
                description: "Checks that each solid in the scene (or a specific solid) is a valid closed, manifold, positive-volume mesh and compares measured `volume`, `area`, and `bounds` against any `export const expected` block in a part file within tolerance.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "Optional solid ID to verify (e.g. 'part-1', 'box-1'). When omitted, verifies all solids in the scene.")
                    ]
                )
            ),
            MCPToolDefinition(
                name: "cad_capture_snapshot",
                description: "Captures a rendered image of the current 3D viewport for multimodal visual verification. Optionally renders from a named camera view preset (`front`, `top`, `right`, `isometric`, `perspective`).",
                inputSchema: MCPInputSchema(
                    properties: [
                        "view": MCPProperty(
                            type: "string",
                            description: "Optional named camera view preset: 'front', 'top', 'right', 'isometric', or 'perspective'. When omitted, captures the current viewport camera.",
                            enum: ["front", "top", "right", "isometric", "perspective"]
                        )
                    ]
                )
            ),
            MCPToolDefinition(
                name: "cad_rollback",
                description: "Rolls the CAD history timeline backward or forward to an earlier or later feature. Features after the rollback marker are excluded from evaluation and viewport rendering. New solids added while rolled back are inserted at the marker position.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "index": MCPProperty(type: "number", description: "Optional 0-based insertion index to position the rollback marker. When omitted and solidId is provided, rolls back to that solid."),
                        "solidId": MCPProperty(type: "string", description: "Optional solid ID to roll back to (marker placed after this solid). When 'end' or omitted with index omitted, rolls forward to the end.")
                    ]
                )
            )
        ]
    }
    
    public func callTool(name: String, arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        switch name {
        case "cad_get_scene":
            return handleGetScene()
            
        case "cad_add_solid":
            return handleAddSolid(arguments: arguments)

        case "cad_rollback":
            return await handleRollback(arguments: arguments)
            
        case "cad_boolean_operation":
            return await handleBooleanOperation(arguments: arguments)
            
        case "cad_set_param":
            return handleSetParam(arguments: arguments)
            
        case "cad_set_transform":
            return handleSetTransform(arguments: arguments)
            
        case "cad_remove_solid":
            return await handleRemoveSolid(arguments: arguments)
            
        case "cad_measure":
            return await handleMeasure(arguments: arguments)
            
        case "cad_reload":
            return await handleReload(arguments: arguments)
            
        case "cad_get_diagnostics":
            return await handleGetDiagnostics(arguments: arguments)
            
        case "cad_verify":
            return await handleVerify(arguments: arguments)
            
        case "cad_capture_snapshot":
            return await handleCaptureSnapshot(arguments: arguments)
            
        default:
            return .error("Unknown tool: '\(name)'")
        }
    }
    
    // MARK: - Tool Handlers
    
    private func handleGetScene() -> MCPToolCallResult {
        var summary: [[String: Any]] = []
        for obj in document.objects {
            var item: [String: Any] = [
                "id": obj.id.rawValue,
                "kind": obj.def.kind,
                "position": [obj.transform.position.x, obj.transform.position.y, obj.transform.position.z]
            ]
            switch obj.def {
            case .box(let p):
                item["params"] = ["width": p.width, "depth": p.depth, "height": p.height]
            case .cylinder(let p):
                item["params"] = ["radius": p.radius, "height": p.height]
            case .sphere(let p):
                item["params"] = ["radius": p.radius]
            case .cone(let p):
                item["params"] = ["bottomRadius": p.bottomRadius, "topRadius": p.topRadius, "height": p.height]
            case .torus(let p):
                item["params"] = ["majorRadius": p.majorRadius, "minorRadius": p.minorRadius]
            case .wedge(let p):
                item["params"] = ["width": p.width, "depth": p.depth, "height": p.height, "topWidth": p.topWidth]
            case .imported(let name, _, _):
                item["importedName"] = name
            case .boolean(let op, let solidA, let solidB):
                item["operation"] = op.rawValue
                item["operands"] = [solidA.rawValue, solidB.rawValue]
            case .part(let url, _):
                item["file"] = url.path
            case .extrude(let p):
                item["params"] = ["distance": p.distance, "isSymmetric": p.isSymmetric]
            }
            summary.append(item)
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: summary, options: .prettyPrinted)
            let jsonString = String(data: data, encoding: .utf8) ?? "[]"
            return .text(jsonString)
        } catch {
            return .error("Failed to serialize scene: \(error.localizedDescription)")
        }
    }
    
    private func handleAddSolid(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        guard let type = arguments["type"]?.stringValue else {
            return .error("Missing 'type' argument (must be 'box', 'cylinder', 'sphere', 'cone', 'torus', or 'wedge')")
        }
        
        let validTypes = ["box", "cylinder", "sphere", "cone", "torus", "wedge"]
        guard validTypes.contains(type) else {
            return .error("Unsupported solid type '\(type)'. Supported: \(validTypes.joined(separator: ", "))")
        }
        
        let transform: Transform
        let def: ObjectDef
        do {
            let posX = try Self.optionalPosition(arguments, "posX") ?? 0
            let posY = try Self.optionalPosition(arguments, "posY") ?? 0
            let posZ = try Self.optionalPosition(arguments, "posZ") ?? 0
            transform = Transform(
                position: SIMD3<Float>(posX, posY, posZ),
                rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                scale: SIMD3<Float>(1, 1, 1)
            )
            // The document model clamps sizes to its limits.
            switch type {
            case "box":
                let w = try Self.optionalDimension(arguments, "width") ?? 40.0
                let d = try Self.optionalDimension(arguments, "depth") ?? 30.0
                let h = try Self.optionalDimension(arguments, "height") ?? 20.0
                def = .box(BoxParams(width: w, depth: d, height: h))
            case "cylinder":
                let r = try Self.optionalDimension(arguments, "radius") ?? 15.0
                let h = try Self.optionalDimension(arguments, "height") ?? 40.0
                def = .cylinder(CylinderParams(radius: r, height: h))
            case "sphere":
                let r = try Self.optionalDimension(arguments, "radius") ?? 15.0
                def = .sphere(SphereParams(radius: r))
            case "cone":
                let br = try Self.optionalDimension(arguments, "bottomRadius") ?? 15.0
                let tr = try Self.optionalDimension(arguments, "topRadius") ?? 0.0
                let h = try Self.optionalDimension(arguments, "height") ?? 30.0
                def = .cone(ConeParams(bottomRadius: br, topRadius: tr, height: h))
            case "torus":
                let maj = try Self.optionalDimension(arguments, "majorRadius") ?? 20.0
                let minR = try Self.optionalDimension(arguments, "minorRadius") ?? 5.0
                def = .torus(TorusParams(majorRadius: maj, minorRadius: minR))
            case "wedge":
                let w = try Self.optionalDimension(arguments, "width") ?? 30.0
                let d = try Self.optionalDimension(arguments, "depth") ?? 30.0
                let h = try Self.optionalDimension(arguments, "height") ?? 30.0
                let tw = try Self.optionalDimension(arguments, "topWidth") ?? 0.0
                def = .wedge(WedgeParams(width: w, depth: d, height: h, topWidth: tw))
            default:
                return .error("Unsupported solid type '\(type)'")
            }
        } catch {
            return .error(error.message)
        }
        
        let clampedDef = DocumentLimits.clamp(def)
        let id = document.addObject(def: clampedDef, transform: transform)
        scheduleRecompute(id: id)
        
        let dimStr: String
        switch clampedDef {
        case .box(let p):
            dimStr = "with dimensions (width: \(p.width), depth: \(p.depth), height: \(p.height))"
        case .cylinder(let p):
            dimStr = "with dimensions (radius: \(p.radius), height: \(p.height))"
        case .sphere(let p):
            dimStr = "with dimensions (radius: \(p.radius))"
        case .cone(let p):
            dimStr = "with dimensions (bottomRadius: \(p.bottomRadius), topRadius: \(p.topRadius), height: \(p.height))"
        case .torus(let p):
            dimStr = "with dimensions (majorRadius: \(p.majorRadius), minorRadius: \(p.minorRadius))"
        case .wedge(let p):
            dimStr = "with dimensions (width: \(p.width), depth: \(p.depth), height: \(p.height), topWidth: \(p.topWidth))"
        case .extrude(let p):
            dimStr = "with distance \(p.distance)"
        default:
            dimStr = ""
        }
        return .text("Successfully added solid with ID: \(id.rawValue) \(dimStr) at position (\(transform.position.x), \(transform.position.y), \(transform.position.z))")
    }

    private func handleRollback(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        let oldObjects = document.objects
        let result: Result<Void, DocumentMutationError>

        if let rawIndex = arguments["index"] {
            guard let doubleVal = rawIndex.doubleValue, doubleVal.isFinite else {
                return .error("Argument 'index' must be a valid number")
            }
            let index = Int(doubleVal)
            result = document.setRollbackIndex(index)
        } else if let rawSolidId = (arguments["solidId"] ?? arguments["solid_id"])?.stringValue {
            if rawSolidId == "end" {
                result = document.rollForwardToEnd()
            } else {
                let solidId = SolidId(rawSolidId)
                guard let feat = document.feature(for: solidId) else {
                    return .error("Solid '\(rawSolidId)' not found in timeline")
                }
                result = document.rollBack(to: feat.id)
            }
        } else {
            result = document.rollForwardToEnd()
        }

        switch result {
        case .failure(let err):
            return .error("Rollback failed: \(err.description)")
        case .success:
            break
        }

        // Synchronize renderer meshes for removed objects
        let remaining = Set(document.objects.map(\.id))
        for obj in oldObjects where !remaining.contains(obj.id) {
            partReloadController.stopWatching(id: obj.id)
            await kernelClient.dispose(solidId: obj.id)
            if let sink = meshSink {
                _ = SolidMeshApplier.remove(id: obj.id, from: sink)
            }
        }

        // Schedule recomputes for newly active objects
        let oldSet = Set(oldObjects.map(\.id))
        for obj in document.objects where !oldSet.contains(obj.id) {
            scheduleRecompute(id: obj.id)
        }
        if !oldObjects.elementsEqual(document.objects, by: { $0.id == $1.id }) {
            onViewportInvalidated?()
        }

        let stateStr = document.isRolledBack ? "rolled back at index \(document.effectiveRollbackIndex)" : "fully rolled forward"
        return .text("Timeline \(stateStr). Active features: \(document.activeFeatures.count) / \(document.features.count). Objects in scene: \(document.objects.count).")
    }
    
    private func handleSetParam(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        guard let idStr = arguments["id"]?.stringValue else {
            return .error("Missing required argument 'id'")
        }
        guard let param = arguments["param"]?.stringValue else {
            return .error("Missing required argument 'param'")
        }
        guard let rawValue = arguments["value"]?.doubleValue else {
            return .error("Missing required argument 'value'")
        }
        guard rawValue.isFinite else {
            return .error("Parameter value must be a finite number")
        }
        let val = Float(rawValue)
        
        let id = SolidId(idStr)
        guard let def = document.paramsFor(id: id) else {
            return .error("Solid '\(idStr)' not found in scene")
        }
        guard let editable = Self.editableParams(of: def) else {
            let article = def.kind.first.map { "aeiou".contains($0) } == true ? "an" : "a"
            return .error("Solid '\(idStr)' is \(article) \(def.kind) solid and has no editable parameters")
        }
        guard editable.contains(where: { $0.name == param }) else {
            let names = editable.map { "'\($0.name)'" }.joined(separator: ", ")
            return .error("Unknown parameter '\(param)' for \(def.kind) solid '\(idStr)'. Supported: \(names)")
        }
        
        let result = document.setParam(id: id, key: param, value: val)
        switch result {
        case .failure(.objectLocked(let lockedId)):
            return .error("Solid '\(lockedId.rawValue)' is locked and cannot be edited")
        case .failure(.objectNotFound):
            return .error("Solid '\(idStr)' not found in scene")
        case .success:
            break
        }
        scheduleRecompute(id: id)
        let stored = document.paramsFor(id: id).flatMap { Self.editableParams(of: $0)?.first(where: { $0.name == param })?.value } ?? val
        return .text("Updated parameter '\(param)' on solid '\(idStr)' to \(stored)")
    }
    
    /// A tool argument that failed validation; the message is returned to the agent as an isError result.
    private struct ArgumentError: Error { let message: String }
    
    /// The finite numeric value of an optional argument, or nil when the key is absent.
    private static func optionalNumber(_ arguments: [String: AnyCodableValue], _ key: String) throws(ArgumentError) -> Double? {
        guard let raw = arguments[key] else { return nil }
        guard let value = raw.doubleValue else {
            throw ArgumentError(message: "Argument '\(key)' must be a number")
        }
        guard value.isFinite else {
            throw ArgumentError(message: "Argument '\(key)' must be a finite number")
        }
        return value
    }
    
    /// An optional position coordinate, checked against the position bound before conversion to Float.
    private static func optionalPosition(_ arguments: [String: AnyCodableValue], _ key: String) throws(ArgumentError) -> Float? {
        guard let value = try optionalNumber(arguments, key) else { return nil }
        let range = DocumentLimits.position
        guard value >= Double(range.min), value <= Double(range.max) else {
            throw ArgumentError(message: "Argument '\(key)' must be between \(Int(range.min)) and \(Int(range.max)) mm")
        }
        return Float(value)
    }
    
    /// An optional solid dimension, ensuring the value is numeric, finite as a Double, and finite when converted to Float.
    private static func optionalDimension(_ arguments: [String: AnyCodableValue], _ key: String) throws(ArgumentError) -> Float? {
        guard let value = try optionalNumber(arguments, key) else { return nil }
        let floatVal = Float(value)
        guard floatVal.isFinite else {
            throw ArgumentError(message: "Argument '\(key)' must be a finite number")
        }
        return floatVal
    }

    /// An optional rotation angle in degrees, ensuring the value is numeric, finite as a Double, and finite when converted to Float.
    private static func optionalAngle(_ arguments: [String: AnyCodableValue], _ key: String) throws(ArgumentError) -> Float? {
        guard let value = try optionalNumber(arguments, key) else { return nil }
        let floatVal = Float(value)
        guard floatVal.isFinite else {
            throw ArgumentError(message: "Argument '\(key)' must be a finite number")
        }
        return floatVal
    }
    
    /// Ordered name-and-value pairs of the parameters an agent may set, or nil for a solid with none.
    private static func editableParams(of def: ObjectDef) -> [(name: String, value: Float)]? {
        switch def {
        case .box(let p): return [("width", p.width), ("depth", p.depth), ("height", p.height)]
        case .cylinder(let p): return [("radius", p.radius), ("height", p.height)]
        case .sphere(let p): return [("radius", p.radius)]
        case .cone(let p): return [("bottomRadius", p.bottomRadius), ("topRadius", p.topRadius), ("height", p.height)]
        case .torus(let p): return [("majorRadius", p.majorRadius), ("minorRadius", p.minorRadius)]
        case .wedge(let p): return [("width", p.width), ("depth", p.depth), ("height", p.height), ("topWidth", p.topWidth)]
        case .extrude(let p): return [("distance", Float(p.distance))]
        case .imported, .boolean, .part: return nil
        }
    }
    
    private func handleSetTransform(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        guard let idStr = arguments["id"]?.stringValue else {
            return .error("Missing required argument 'id'")
        }
        let id = SolidId(idStr)
        guard let obj = document.objects.first(where: { $0.id == id }) else {
            return .error("Solid '\(idStr)' not found in scene")
        }
        
        var transform = obj.transform
        let rotX: Float?
        let rotY: Float?
        let rotZ: Float?
        do {
            let x = try Self.optionalPosition(arguments, "posX")
            let y = try Self.optionalPosition(arguments, "posY")
            let z = try Self.optionalPosition(arguments, "posZ")
            if let x { transform.position.x = x }
            if let y { transform.position.y = y }
            if let z { transform.position.z = z }

            rotX = try Self.optionalAngle(arguments, "rotX")
            rotY = try Self.optionalAngle(arguments, "rotY")
            rotZ = try Self.optionalAngle(arguments, "rotZ")
            if rotX != nil || rotY != nil || rotZ != nil {
                let degToRad = Float.pi / 180.0
                let qx = simd_quatf(angle: (rotX ?? 0) * degToRad, axis: SIMD3<Float>(1, 0, 0))
                let qy = simd_quatf(angle: (rotY ?? 0) * degToRad, axis: SIMD3<Float>(0, 1, 0))
                let qz = simd_quatf(angle: (rotZ ?? 0) * degToRad, axis: SIMD3<Float>(0, 0, 1))
                transform.rotation = qz * qy * qx
            }
        } catch {
            return .error(error.message)
        }
        
        let result = document.setTransform(id: id, transform: transform)
        switch result {
        case .failure(.objectLocked(let lockedId)):
            return .error("Solid '\(lockedId.rawValue)' is locked and cannot be moved")
        case .failure(.objectNotFound):
            return .error("Solid '\(idStr)' not found in scene")
        case .success:
            break
        }
        if let sink = meshSink, SolidMeshApplier.applyTransform(to: id, document: document, sink: sink) {
            onViewportInvalidated?()
        }
        if rotX != nil || rotY != nil || rotZ != nil {
            return .text("Updated transform for solid '\(idStr)' to position (\(transform.position.x), \(transform.position.y), \(transform.position.z)) and rotation (\(rotX ?? 0), \(rotY ?? 0), \(rotZ ?? 0))")
        }
        return .text("Updated transform for solid '\(idStr)' to position (\(transform.position.x), \(transform.position.y), \(transform.position.z))")
    }
    
    private func handleRemoveSolid(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        guard let idStr = arguments["id"]?.stringValue else {
            return .error("Missing required argument 'id'")
        }
        let id = SolidId(idStr)
        guard let obj = document.objects.first(where: { $0.id == id }) else {
            return .error("Solid '\(idStr)' not found in scene")
        }
        guard !obj.isLocked else {
            return .error("Solid '\(id.rawValue)' is locked and cannot be removed")
        }
        
        let inFlight = inFlightRecomputes.removeValue(forKey: id)
        partReloadController.stopWatching(id: id)
        let dependents = document.dependentObjects(of: id)
        document.removeObject(id: id)
        if let sink = meshSink, SolidMeshApplier.remove(id: id, from: sink) {
            onViewportInvalidated?()
        }
        await kernelClient.dispose(solidId: id)
        _ = await inFlight?.task.value
        for depId in dependents {
            scheduleRecompute(id: depId)
        }
        return .text("Removed solid '\(idStr)' from scene")
    }
    
    private func handleMeasure(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        guard let idStr = arguments["id"]?.stringValue else {
            return .error("Missing required argument 'id'")
        }
        let id = SolidId(idStr)
        guard let obj = document.objects.first(where: { $0.id == id }) else {
            return .error("Solid '\(idStr)' not found in scene")
        }
        
        var resultDict: [String: Any] = ["id": id.rawValue]
        switch obj.def {
        case .box(let p):
            let volume = p.width * p.depth * p.height
            let surfaceArea = 2.0 * (p.width * p.depth + p.depth * p.height + p.height * p.width)
            resultDict["type"] = "box"
            resultDict["bounds"] = ["x": p.width, "y": p.depth, "z": p.height]
            resultDict["volumeMm3"] = volume
            resultDict["surfaceAreaMm2"] = surfaceArea
            
        case .cylinder(let p):
            let volume = Float.pi * p.radius * p.radius * p.height
            let surfaceArea = 2.0 * Float.pi * p.radius * (p.radius + p.height)
            resultDict["type"] = "cylinder"
            resultDict["bounds"] = ["radius": p.radius, "height": p.height]
            resultDict["volumeMm3"] = volume
            resultDict["surfaceAreaMm2"] = surfaceArea

        case .sphere(let p):
            let volume = (4.0 / 3.0) * Float.pi * p.radius * p.radius * p.radius
            let surfaceArea = 4.0 * Float.pi * p.radius * p.radius
            resultDict["type"] = "sphere"
            resultDict["bounds"] = ["radius": p.radius]
            resultDict["volumeMm3"] = volume
            resultDict["surfaceAreaMm2"] = surfaceArea

        case .cone(let p):
            let r1 = p.bottomRadius
            let r2 = p.topRadius
            let h = p.height
            let volume = (Float.pi * h / 3.0) * (r1 * r1 + r1 * r2 + r2 * r2)
            let slant = sqrt((r1 - r2) * (r1 - r2) + h * h)
            let lateralArea = Float.pi * (r1 + r2) * slant
            let baseArea = Float.pi * r1 * r1 + Float.pi * r2 * r2
            let surfaceArea = lateralArea + baseArea
            resultDict["type"] = "cone"
            resultDict["bounds"] = ["bottomRadius": r1, "topRadius": r2, "height": h]
            resultDict["volumeMm3"] = volume
            resultDict["surfaceAreaMm2"] = surfaceArea

        case .torus(let p):
            let R = p.majorRadius
            let r = p.minorRadius
            let volume = 2.0 * Float.pi * Float.pi * R * r * r
            let surfaceArea = 4.0 * Float.pi * Float.pi * R * r
            resultDict["type"] = "torus"
            resultDict["bounds"] = ["majorRadius": R, "minorRadius": r]
            resultDict["volumeMm3"] = volume
            resultDict["surfaceAreaMm2"] = surfaceArea

        case .wedge(let p):
            let w = p.width
            let d = p.depth
            let h = p.height
            let tw = p.topWidth
            let volume = ((w + tw) * 0.5) * h * d
            let delta = (w - tw) * 0.5
            let slant = sqrt(delta * delta + h * h)
            let bottomArea = w * d
            let topArea = tw * d
            let frontBackArea = (w + tw) * h
            let slantedArea = 2.0 * slant * d
            let surfaceArea = bottomArea + topArea + frontBackArea + slantedArea
            resultDict["type"] = "wedge"
            resultDict["bounds"] = ["width": w, "depth": d, "height": h, "topWidth": tw]
            resultDict["volumeMm3"] = volume
            resultDict["surfaceAreaMm2"] = surfaceArea

        case .extrude(let p):
            resultDict["type"] = "extrude"
            resultDict["distance"] = p.distance
            resultDict["isSymmetric"] = p.isSymmetric
            await settleRecomputes(for: [id])
            if let payload = await meshForObject(obj),
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["bounds"] = measurements.bounds.toDictionary()
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }
            
        case .imported(let name, _, _):
            resultDict["type"] = "imported"
            resultDict["name"] = name
            
        case .boolean(let op, let solidA, let solidB):
            resultDict["type"] = "boolean"
            resultDict["operation"] = op.rawValue
            resultDict["operands"] = [solidA.rawValue, solidB.rawValue]
            await settleRecomputes(for: [id])
            if let payload = await meshForObject(obj),
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["bounds"] = measurements.bounds.toDictionary()
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }

        case .part(let url, _):
            resultDict["type"] = "part"
            resultDict["file"] = url.path
            await partReloadController.syncAndSettle(for: id, reloadIfDiskChanged: false)
            if let payload = partReloadController.lastOutputs[id]?.payload,
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["bounds"] = measurements.bounds.toDictionary()
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: resultDict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return .text(str)
        }
        return .error("Failed to measure solid '\(idStr)'")
    }
    
    private func handleReload(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        let idStr: String?
        if let rawId = arguments["id"] {
            guard let parsed = rawId.stringValue, !parsed.isEmpty else {
                return .error("Argument 'id' must be a non-empty string")
            }
            idStr = parsed
        } else {
            idStr = nil
        }

        let fileStr: String?
        if let rawFile = arguments["file"] {
            guard let parsed = rawFile.stringValue, !parsed.isEmpty else {
                return .error("Argument 'file' must be a non-empty string")
            }
            fileStr = parsed
        } else {
            fileStr = nil
        }

        var targetIds: [SolidId] = []
        if let idStr {
            let id = SolidId(idStr)
            guard let obj = document.objects.first(where: { $0.id == id }) else {
                return .error("Solid '\(idStr)' not found in scene")
            }
            guard case .part(let partURL, _) = obj.def else {
                return .error("Solid '\(idStr)' is a \(obj.def.kind) solid, not a reloadable part file")
            }
            if let fileStr {
                let requestedURL = URL(fileURLWithPath: fileStr).standardizedFileURL
                if requestedURL != partURL.standardizedFileURL {
                    return .error("Solid '\(idStr)' is bound to '\(partURL.path)', which does not match file '\(fileStr)'")
                }
            }
            partReloadController.syncWithDocument()
            _ = partReloadController.reloadNow(id: id)
            targetIds = [id]
        } else if let fileStr {
            let url = URL(fileURLWithPath: fileStr).standardizedFileURL
            let id = partReloadController.openPartFile(at: url)
            targetIds = [id]
        } else {
            partReloadController.syncWithDocument()
            let partObjects = document.objects.filter {
                if case .part = $0.def { return true }
                return false
            }
            guard !partObjects.isEmpty else {
                return .error("No part files are currently open in the scene. Pass a 'file' path to open and evaluate a part script.")
            }
            for obj in partObjects {
                _ = partReloadController.reloadNow(id: obj.id)
                targetIds.append(obj.id)
            }
        }

        var partEntries: [[String: Any]] = []
        var allErrors: [[String: Any]] = []
        var allWarnings: [[String: Any]] = []
        var anyFailed = false

        for id in targetIds {
            let result = await partReloadController.settle(for: id)
            let partURL: URL? = document.objects.first(where: { $0.id == id }).flatMap {
                if case .part(let url, _) = $0.def { return url }
                return nil
            }
            let filePath = partURL?.path ?? ""

            if let result {
                switch result {
                case .success(_, let output):
                    let warningItems = output.warnings.map { w -> [String: Any] in
                        [
                            "id": id.rawValue,
                            "severity": "warning",
                            "file": w.file,
                            "line": w.line,
                            "column": w.column,
                            "message": w.message
                        ]
                    }
                    allWarnings.append(contentsOf: warningItems)
                    partEntries.append([
                        "id": id.rawValue,
                        "file": filePath,
                        "status": "ok",
                        "triangleCount": output.payload.triangleCount,
                        "hasExpected": output.expected != nil,
                        "errors": [] as [[String: Any]],
                        "warnings": warningItems
                    ])

                case .failure(_, let error):
                    anyFailed = true
                    let diagDict: [String: Any] = [
                        "id": id.rawValue,
                        "severity": "error",
                        "code": error.code.rawValue,
                        "file": error.diagnostic.file,
                        "line": error.diagnostic.line,
                        "column": error.diagnostic.column,
                        "message": error.diagnostic.message
                    ]
                    allErrors.append(diagDict)
                    partEntries.append([
                        "id": id.rawValue,
                        "file": filePath,
                        "status": "error",
                        "code": error.code.rawValue,
                        "diagnostic": diagDict,
                        "errors": [diagDict],
                        "warnings": [] as [[String: Any]]
                    ])
                }
            } else if let error = partReloadController.lastErrors[id] {
                anyFailed = true
                let diagDict: [String: Any] = [
                    "id": id.rawValue,
                    "severity": "error",
                    "code": error.code.rawValue,
                    "file": error.diagnostic.file,
                    "line": error.diagnostic.line,
                    "column": error.diagnostic.column,
                    "message": error.diagnostic.message
                ]
                allErrors.append(diagDict)
                partEntries.append([
                    "id": id.rawValue,
                    "file": filePath,
                    "status": "error",
                    "code": error.code.rawValue,
                    "diagnostic": diagDict,
                    "errors": [diagDict],
                    "warnings": [] as [[String: Any]]
                ])
            } else if let output = partReloadController.lastOutputs[id] {
                let warningItems = output.warnings.map { w -> [String: Any] in
                    [
                        "id": id.rawValue,
                        "severity": "warning",
                        "file": w.file,
                        "line": w.line,
                        "column": w.column,
                        "message": w.message
                    ]
                }
                allWarnings.append(contentsOf: warningItems)
                partEntries.append([
                    "id": id.rawValue,
                    "file": filePath,
                    "status": "ok",
                    "triangleCount": output.payload.triangleCount,
                    "hasExpected": output.expected != nil,
                    "errors": [] as [[String: Any]],
                    "warnings": warningItems
                ])
            }
        }

        var response: [String: Any] = [
            "passed": !anyFailed,
            "parts": partEntries,
            "errors": allErrors,
            "warnings": allWarnings,
            "diagnostics": allErrors + allWarnings
        ]
        if partEntries.count == 1, let single = partEntries.first {
            for (k, v) in single where response[k] == nil {
                response[k] = v
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
              let jsonString = String(data: data, encoding: .utf8) else {
            return .error("Failed to serialize reload result")
        }
        return MCPToolCallResult(content: [.text(jsonString)], isError: anyFailed)
    }

    private func handleGetDiagnostics(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        let idStr: String?
        if let rawId = arguments["id"] {
            guard let parsed = rawId.stringValue, !parsed.isEmpty else {
                return .error("Argument 'id' must be a non-empty string")
            }
            idStr = parsed
        } else {
            idStr = nil
        }

        let fileStr: String?
        if let rawFile = arguments["file"] {
            guard let parsed = rawFile.stringValue, !parsed.isEmpty else {
                return .error("Argument 'file' must be a non-empty string")
            }
            fileStr = parsed
        } else {
            fileStr = nil
        }

        await partReloadController.syncAndSettle(reloadIfDiskChanged: false)

        let targetObjects: [SceneObject]
        if let idStr {
            let id = SolidId(idStr)
            guard let obj = document.objects.first(where: { $0.id == id }) else {
                return .error("Solid '\(idStr)' not found in scene")
            }
            targetObjects = [obj]
        } else if let fileStr {
            let canonical = URL(fileURLWithPath: fileStr).standardizedFileURL
            let matched = document.objects.filter { obj in
                if case .part(let url, _) = obj.def, url.standardizedFileURL == canonical {
                    return true
                }
                if let err = partReloadController.lastErrors[obj.id],
                   URL(fileURLWithPath: err.diagnostic.file).standardizedFileURL == canonical {
                    return true
                }
                if let out = partReloadController.lastOutputs[obj.id],
                   out.loadedFiles.contains(where: { URL(fileURLWithPath: $0).standardizedFileURL == canonical }) {
                    return true
                }
                return false
            }
            guard !matched.isEmpty else {
                return .error("Part file '\(fileStr)' is not open in the scene")
            }
            targetObjects = matched
        } else {
            targetObjects = document.objects
        }

        var errors: [[String: Any]] = []
        var warnings: [[String: Any]] = []

        for obj in targetObjects {
            if let error = partReloadController.lastErrors[obj.id] {
                errors.append([
                    "id": obj.id.rawValue,
                    "severity": "error",
                    "code": error.code.rawValue,
                    "file": error.diagnostic.file,
                    "line": error.diagnostic.line,
                    "column": error.diagnostic.column,
                    "message": error.diagnostic.message
                ])
            }
            if let output = partReloadController.lastOutputs[obj.id] {
                for warning in output.warnings {
                    warnings.append([
                        "id": obj.id.rawValue,
                        "severity": "warning",
                        "file": warning.file,
                        "line": warning.line,
                        "column": warning.column,
                        "message": warning.message
                    ])
                }
            }
        }

        let response: [String: Any] = [
            "errors": errors,
            "warnings": warnings,
            "diagnostics": errors + warnings
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
              let jsonString = String(data: data, encoding: .utf8) else {
            return .error("Failed to serialize diagnostics")
        }
        return .text(jsonString)
    }

    private func handleVerify(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        let targetObjects: [SceneObject]
        if let rawId = arguments["id"] {
            guard let idStr = rawId.stringValue, !idStr.isEmpty else {
                return .error("Argument 'id' must be a non-empty string")
            }
            let id = SolidId(idStr)
            guard let obj = document.objects.first(where: { $0.id == id }) else {
                return .error("Solid '\(idStr)' not found in scene")
            }
            targetObjects = [obj]
        } else {
            targetObjects = document.objects
            guard !targetObjects.isEmpty else {
                return .error("No solids in scene to verify")
            }
        }

        await settleRecomputes(for: targetObjects.map(\.id))
        await partReloadController.syncAndSettle(reloadIfDiskChanged: false)

        var reports: [SolidVerificationReport] = []
        for obj in targetObjects {
            let report = await verifySceneObject(obj)
            reports.append(report)
        }

        let allValid = !reports.isEmpty && reports.allSatisfy(\.valid)
        let allFailures = reports.flatMap(\.failures)

        var response: [String: Any] = [
            "valid": allValid,
            "passed": allValid,
            "solids": reports.map { $0.toDictionary() },
            "failures": allFailures
        ]
        if reports.count == 1, let single = reports.first?.toDictionary() {
            for (k, v) in single where response[k] == nil {
                response[k] = v
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: response, options: .prettyPrinted),
              let jsonString = String(data: data, encoding: .utf8) else {
            return .error("Failed to serialize verification report")
        }
        return MCPToolCallResult(content: [.text(jsonString)], isError: !allValid)
    }

    private func verifySceneObject(_ obj: SceneObject) async -> SolidVerificationReport {
        switch obj.def {
        case .part:
            if let err = partReloadController.lastErrors[obj.id] {
                return SolidVerifier.verify(
                    object: obj,
                    payload: nil,
                    expected: partReloadController.lastOutputs[obj.id]?.expected,
                    diagnostic: err.diagnostic
                )
            }
            let output = partReloadController.lastOutputs[obj.id]
            let payload: MeshPayload?
            if let existingPayload = output?.payload {
                payload = existingPayload
            } else {
                payload = await meshForObject(obj)
            }
            return SolidVerifier.verify(
                object: obj,
                payload: payload,
                expected: output?.expected,
                diagnostic: nil
            )

        case .box, .cylinder, .sphere, .cone, .torus, .wedge, .boolean, .extrude:
            let payload = await meshForObject(obj)
            return SolidVerifier.verify(
                object: obj,
                payload: payload,
                expected: nil,
                diagnostic: nil
            )

        case .imported:
            return SolidVerifier.verify(
                object: obj,
                payload: nil,
                expected: nil,
                diagnostic: nil
            )
        }
    }

    private func meshForObject(_ obj: SceneObject) async -> MeshPayload? {
        let firstJob = JobId("verify-\(UUID().uuidString)")
        let retryJob = JobId("verify-\(UUID().uuidString)")
        guard let first = KernelRegeneration.request(for: obj, jobId: firstJob),
              let retry = KernelRegeneration.request(for: obj, jobId: retryJob) else {
            return nil
        }
        let result = await kernelClient.request(first)
        if case .success(_, let payload) = result {
            return payload
        }
        if case .failure(_, let err) = result, err.code == .cancelled {
            let retryResult = await kernelClient.request(retry)
            if case .success(_, let payload) = retryResult {
                return payload
            }
        }
        return nil
    }
    
    private func handleCaptureSnapshot(arguments: [String: AnyCodableValue] = [:]) async -> MCPToolCallResult {
        var perspective: ViewportPerspective? = nil
        if let rawView = arguments["view"] {
            guard let viewName = rawView.stringValue else {
                return .error("Argument 'view' must be a string")
            }
            switch viewName.lowercased() {
            case "front":
                perspective = .front
            case "top":
                perspective = .top
            case "right":
                perspective = .right
            case "isometric":
                perspective = .isometric
            case "perspective":
                perspective = .perspective
            default:
                return .error("Invalid 'view' value '\(viewName)'. Supported views: 'front', 'top', 'right', 'isometric', 'perspective'")
            }
        }

        await settleRecomputes(for: document.objects.map(\.id))
        await partReloadController.syncAndSettle(reloadIfDiskChanged: false)

        guard let provider = snapshotProvider else {
            return .error("Snapshot unavailable: no Metal 4 device is available to render the viewport")
        }
        guard let base64 = await provider.captureSnapshotPngBase64(view: perspective) else {
            return .error("Snapshot capture failed: the viewport frame could not be rendered or encoded")
        }
        return MCPToolCallResult(content: [.image(base64: base64, mimeType: "image/png")], isError: false)
    }
    
    private func handleBooleanOperation(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        guard let solidAStr = arguments["solidA"]?.stringValue else {
            return .error("Missing required argument 'solidA'")
        }
        guard let solidBStr = arguments["solidB"]?.stringValue else {
            return .error("Missing required argument 'solidB'")
        }
        guard let opStr = arguments["operation"]?.stringValue,
              let op = BooleanOp(rawValue: opStr) else {
            return .error("Invalid or missing 'operation'. Expected: 'subtract', 'union', or 'intersect'")
        }
        
        let solidA = SolidId(solidAStr)
        let solidB = SolidId(solidBStr)
        let operands = [(solidA, solidAStr), (solidB, solidBStr)]
        if let missing = missingOperand(operands) {
            return .error("Solid '\(missing)' not found in scene")
        }
        guard solidA != solidB else {
            return .error("Operands 'solidA' and 'solidB' must be different solids, but both are '\(solidAStr)'")
        }
        let keepTool: Bool?
        if let raw = arguments["keepTool"] {
            guard let b = raw.boolValue else {
                return .error("Argument 'keepTool' must be a boolean")
            }
            keepTool = b
        } else {
            keepTool = nil
        }
        await settleRecomputes(for: [solidA, solidB])
        let def = ObjectDef.boolean(op: op, solidA: solidA, solidB: solidB)
        let outputId = document.reserveId(for: def)
        
        let req = KernelRequest.booleanOperation(
            jobId: JobId("job-\(UUID().uuidString)"),
            solidId: outputId,
            op: op,
            solidA: solidA,
            solidB: solidB
        )
        
        let result = await kernelClient.request(req)
        if case .success = result {
            if let missing = missingOperand(operands) {
                await kernelClient.dispose(solidId: outputId)
                return .error("Solid '\(missing)' was removed while the boolean \(opStr) was running")
            }
            document.addObject(outputId, def: def)
            if let keepTool {
                document.setVisibility(id: solidA, isVisible: false)
                document.setVisibility(id: solidB, isVisible: keepTool)
            }
            if let sink = meshSink, SolidMeshApplier.apply(result, to: outputId, document: document, sink: sink) {
                onViewportInvalidated?()
            }
            return .text("Successfully executed \(opStr) between '\(solidAStr)' and '\(solidBStr)'. Output registered as '\(outputId.rawValue)'")
        } else {
            return .error("Boolean \(opStr) failed: \(result.error?.message ?? "unknown error")")
        }
    }
    
    /// Returns the first operand name with no matching object in the document.
    private func missingOperand(_ operands: [(SolidId, String)]) -> String? {
        operands.first { id, _ in !document.objects.contains(where: { $0.id == id }) }?.1
    }
    
    // MARK: - Recompute & Viewport Synchronization
    
    /// Runs the kernel recompute path for `id` in the background, keeping `KernelClient`'s 60 ms conflation.
    /// When `meshSink` is bound, installs the resulting mesh using the live document state and invalidates the viewport.
    @discardableResult
    public func scheduleRecompute(id: SolidId) -> Task<KernelResult<MeshPayload>, Never>? {
        let jobId = JobId("job-\(UUID().uuidString)")
        guard let obj = document.objects.first(where: { $0.id == id }),
              let request = KernelRegeneration.request(for: obj, jobId: jobId) else {
            return nil
        }
        let client = kernelClient
        let task = Task { @MainActor [weak self] () -> KernelResult<MeshPayload> in
            guard let self, self.document.objects.contains(where: { $0.id == id }) else {
                return .failure(jobId: jobId, error: KernelError(code: .cancelled, message: "Solid removed before recompute started"))
            }
            let result = await client.request(request)
            if self.inFlightRecomputes[id]?.jobId == jobId {
                self.inFlightRecomputes.removeValue(forKey: id)
            }
            await self.finishRecompute(result, for: id)
            return result
        }
        inFlightRecomputes[id] = (jobId, task)
        return task
    }
    
    /// Awaits any in-flight recomputes for `ids`, continuing if a newer edit replaced a conflated request.
    public func settleRecomputes(for ids: [SolidId]) async {
        for id in ids {
            while let entry = inFlightRecomputes[id] {
                _ = await entry.task.value
                if inFlightRecomputes[id]?.jobId == entry.jobId {
                    inFlightRecomputes.removeValue(forKey: id)
                    break
                }
            }
        }
    }
    
    private func finishRecompute(_ result: KernelResult<MeshPayload>, for id: SolidId) async {
        // The solid was removed while the request was in flight; release what it repopulated.
        guard document.objects.contains(where: { $0.id == id }) else {
            if case .success = result {
                await kernelClient.dispose(solidId: id)
            }
            return
        }
        // A failure leaves the previous mesh installed; only the message changes.
        onRecomputeResult?(result, id)
        switch result {
        case .failure(_, let err):
            if let feat = document.feature(for: id) {
                document.setFeatureError(
                    id: feat.id,
                    error: FeatureErrorState(code: err.code.rawValue, message: err.message, severity: .error)
                )
                for depFeat in document.dependentFeatures(referencing: feat.id) {
                    document.setFeatureError(
                        id: depFeat.id,
                        error: FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
                    )
                }
            }
        case .success:
            if let feat = document.feature(for: id) {
                document.setFeatureError(id: feat.id, error: nil)
            }
            for depId in document.directDependentObjects(of: id) {
                if let depFeat = document.feature(for: depId), depFeat.errorState?.code == "parent-failed" {
                    document.setFeatureError(id: depFeat.id, error: nil)
                }
                scheduleRecompute(id: depId)
            }
        }
        guard let sink = meshSink,
              SolidMeshApplier.apply(result, to: id, document: document, sink: sink) else { return }
        onViewportInvalidated?()
    }
}
