import Foundation
import simd

public protocol SnapshotProvider: AnyObject, Sendable {
    func captureSnapshotPngBase64() async -> String?
}

@MainActor
public final class CADToolRegistry {
    private let document: DocumentModel
    private let kernelClient: KernelClientProtocol
    private weak var snapshotProvider: (any SnapshotProvider)?
    private weak var meshSink: (any SolidMeshSink)?
    private let onViewportInvalidated: (@MainActor () -> Void)?
    private let onRecomputeResult: (@MainActor (KernelResult<MeshPayload>, SolidId) -> Void)?
    private var inFlightRecomputes: [SolidId: (jobId: JobId, task: Task<KernelResult<MeshPayload>, Never>)] = [:]
    
    public init(
        document: DocumentModel,
        kernelClient: KernelClientProtocol,
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
    }
    
    public func setSnapshotProvider(_ provider: any SnapshotProvider) {
        self.snapshotProvider = provider
    }
    
    public func setMeshSink(_ sink: (any SolidMeshSink)?) {
        self.meshSink = sink
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
                description: "Adds a new parametric solid (box or cylinder) to the CAD document.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "type": MCPProperty(type: "string", description: "The solid type: 'box' or 'cylinder'", enum: ["box", "cylinder"]),
                        "width": MCPProperty(type: "number", description: "Width (X dimension) for a box in mm"),
                        "depth": MCPProperty(type: "number", description: "Depth (Y dimension) for a box in mm"),
                        "height": MCPProperty(type: "number", description: "Height (Z dimension) in mm"),
                        "radius": MCPProperty(type: "number", description: "Radius in mm for a cylinder"),
                        "posX": MCPProperty(type: "number", description: "X world position in mm, from -10000 to 10000 (default 0)"),
                        "posY": MCPProperty(type: "number", description: "Y world position in mm, from -10000 to 10000 (default 0)"),
                        "posZ": MCPProperty(type: "number", description: "Z world position in mm, from -10000 to 10000 (default 0)")
                    ],
                    required: ["type"]
                )
            ),
            MCPToolDefinition(
                name: "cad_set_param",
                description: "Modifies a specific dimension/parameter of an existing solid (e.g. width, depth, height, radius). Automatically clamped to safe ranges.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "The solid ID (e.g. 'box-1', 'cylinder-1')"),
                        "param": MCPProperty(type: "string", description: "The parameter name. Box: 'width', 'depth', 'height'. Cylinder: 'radius', 'height'. Imported solids have no editable parameters."),
                        "value": MCPProperty(type: "number", description: "The new numeric value in mm")
                    ],
                    required: ["id", "param", "value"]
                )
            ),
            MCPToolDefinition(
                name: "cad_set_transform",
                description: "Updates the world position of an existing solid. Omitted coordinates are unchanged.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "The solid ID"),
                        "posX": MCPProperty(type: "number", description: "X position in mm, from -10000 to 10000. Omitted coordinates are unchanged."),
                        "posY": MCPProperty(type: "number", description: "Y position in mm, from -10000 to 10000. Omitted coordinates are unchanged."),
                        "posZ": MCPProperty(type: "number", description: "Z position in mm, from -10000 to 10000. Omitted coordinates are unchanged.")
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
                        "operation": MCPProperty(type: "string", description: "Operation: 'subtract', 'union', or 'intersect'", enum: ["subtract", "union", "intersect"])
                    ],
                    required: ["solidA", "solidB", "operation"]
                )
            ),
            MCPToolDefinition(
                name: "cad_capture_snapshot",
                description: "Captures a rendered image of the current 3D viewport for multimodal visual verification.",
                inputSchema: MCPInputSchema(properties: [:])
            )
        ]
    }
    
    public func callTool(name: String, arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        switch name {
        case "cad_get_scene":
            return handleGetScene()
            
        case "cad_add_solid":
            return handleAddSolid(arguments: arguments)
            
        case "cad_boolean_operation":
            return await handleBooleanOperation(arguments: arguments)
            
        case "cad_set_param":
            return handleSetParam(arguments: arguments)
            
        case "cad_set_transform":
            return handleSetTransform(arguments: arguments)
            
        case "cad_remove_solid":
            return await handleRemoveSolid(arguments: arguments)
            
        case "cad_measure":
            return handleMeasure(arguments: arguments)
            
        case "cad_capture_snapshot":
            return await handleCaptureSnapshot()
            
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
            case .imported(let name):
                item["importedName"] = name
            case .boolean(let op, let solidA, let solidB):
                item["operation"] = op.rawValue
                item["operands"] = [solidA.rawValue, solidB.rawValue]
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
            return .error("Missing 'type' argument (must be 'box' or 'cylinder')")
        }
        
        guard type == "box" || type == "cylinder" else {
            return .error("Unsupported solid type '\(type)'. Supported: 'box', 'cylinder'")
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
            if type == "box" {
                let w = try Self.optionalNumber(arguments, "width").map(Float.init) ?? 40.0
                let d = try Self.optionalNumber(arguments, "depth").map(Float.init) ?? 30.0
                let h = try Self.optionalNumber(arguments, "height").map(Float.init) ?? 20.0
                def = .box(BoxParams(width: w, depth: d, height: h))
            } else {
                let r = try Self.optionalNumber(arguments, "radius").map(Float.init) ?? 15.0
                let h = try Self.optionalNumber(arguments, "height").map(Float.init) ?? 40.0
                def = .cylinder(CylinderParams(radius: r, height: h))
            }
        } catch {
            return .error(error.message)
        }
        
        let id = document.addObject(def: def, transform: transform)
        scheduleRecompute(id: id)
        
        return .text("Successfully added solid with ID: \(id.rawValue)")
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
        
        document.setParam(id: id, key: param, value: val)
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
    
    /// Ordered name-and-value pairs of the parameters an agent may set, or nil for a solid with none.
    private static func editableParams(of def: ObjectDef) -> [(name: String, value: Float)]? {
        switch def {
        case .box(let p): return [("width", p.width), ("depth", p.depth), ("height", p.height)]
        case .cylinder(let p): return [("radius", p.radius), ("height", p.height)]
        case .imported, .boolean: return nil
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
        do {
            let x = try Self.optionalPosition(arguments, "posX")
            let y = try Self.optionalPosition(arguments, "posY")
            let z = try Self.optionalPosition(arguments, "posZ")
            if let x { transform.position.x = x }
            if let y { transform.position.y = y }
            if let z { transform.position.z = z }
        } catch {
            return .error(error.message)
        }
        
        document.setTransform(id: id, transform: transform)
        if let sink = meshSink, SolidMeshApplier.applyTransform(to: id, document: document, sink: sink) {
            onViewportInvalidated?()
        }
        return .text("Updated transform for solid '\(idStr)' to position (\(transform.position.x), \(transform.position.y), \(transform.position.z))")
    }
    
    private func handleRemoveSolid(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        guard let idStr = arguments["id"]?.stringValue else {
            return .error("Missing required argument 'id'")
        }
        let id = SolidId(idStr)
        guard document.objects.contains(where: { $0.id == id }) else {
            return .error("Solid '\(idStr)' not found in scene")
        }
        
        let inFlight = inFlightRecomputes.removeValue(forKey: id)
        document.removeObject(id: id)
        if let sink = meshSink, SolidMeshApplier.remove(id: id, from: sink) {
            onViewportInvalidated?()
        }
        await kernelClient.dispose(solidId: id)
        _ = await inFlight?.task.value
        return .text("Removed solid '\(idStr)' from scene")
    }
    
    private func handleMeasure(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
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
            
        case .imported(let name):
            resultDict["type"] = "imported"
            resultDict["name"] = name
            
        case .boolean(let op, let solidA, let solidB):
            resultDict["type"] = "boolean"
            resultDict["operation"] = op.rawValue
            resultDict["operands"] = [solidA.rawValue, solidB.rawValue]
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: resultDict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return .text(str)
        }
        return .error("Failed to measure solid '\(idStr)'")
    }
    
    private func handleCaptureSnapshot() async -> MCPToolCallResult {
        guard let provider = snapshotProvider else {
            return .error("Snapshot unavailable: no Metal 4 device is available to render the viewport")
        }
        guard let base64 = await provider.captureSnapshotPngBase64() else {
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
        guard let sink = meshSink,
              SolidMeshApplier.apply(result, to: id, document: document, sink: sink) else { return }
        onViewportInvalidated?()
    }
}
