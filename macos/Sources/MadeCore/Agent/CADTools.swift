import Foundation
import simd

public protocol SnapshotProvider: AnyObject, Sendable {
    func captureSnapshotPngBase64() async -> String?
}

public final class CADToolRegistry: @unchecked Sendable {
    private let document: DocumentModel
    private let kernelClient: KernelClientProtocol
    private weak var snapshotProvider: (any SnapshotProvider)?
    
    public init(
        document: DocumentModel,
        kernelClient: KernelClientProtocol,
        snapshotProvider: (any SnapshotProvider)? = nil
    ) {
        self.document = document
        self.kernelClient = kernelClient
        self.snapshotProvider = snapshotProvider
    }
    
    public func setSnapshotProvider(_ provider: any SnapshotProvider) {
        self.snapshotProvider = provider
    }
    
    public var tools: [MCPToolDefinition] {
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
                        "posX": MCPProperty(type: "number", description: "X world position in mm (default 0)"),
                        "posY": MCPProperty(type: "number", description: "Y world position in mm (default 0)"),
                        "posZ": MCPProperty(type: "number", description: "Z world position in mm (default 0)")
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
                        "param": MCPProperty(type: "string", description: "The parameter name: 'width', 'depth', 'height', or 'radius'"),
                        "value": MCPProperty(type: "number", description: "The new numeric value in mm")
                    ],
                    required: ["id", "param", "value"]
                )
            ),
            MCPToolDefinition(
                name: "cad_set_transform",
                description: "Updates the 3D position or scale of an existing solid in world coordinates.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "The solid ID"),
                        "posX": MCPProperty(type: "number", description: "X position in mm"),
                        "posY": MCPProperty(type: "number", description: "Y position in mm"),
                        "posZ": MCPProperty(type: "number", description: "Z position in mm")
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
                description: "Performs a Constructive Solid Geometry (CSG) boolean operation (subtract, union, or intersect) between two solids in the scene.",
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
        
        let posX = arguments["posX"]?.floatValue ?? 0
        let posY = arguments["posY"]?.floatValue ?? 0
        let posZ = arguments["posZ"]?.floatValue ?? 0
        let transform = Transform(
            position: SIMD3<Float>(posX, posY, posZ),
            rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            scale: SIMD3<Float>(1, 1, 1)
        )
        
        let id: ObjectId
        if type == "box" {
            let w = arguments["width"]?.floatValue ?? 40.0
            let d = arguments["depth"]?.floatValue ?? 30.0
            let h = arguments["height"]?.floatValue ?? 20.0
            // The document model clamps to DocumentLimits.
            let params = BoxParams(width: w, depth: d, height: h)
            id = document.addObject(def: .box(params), transform: transform)
        } else if type == "cylinder" {
            let r = arguments["radius"]?.floatValue ?? 15.0
            let h = arguments["height"]?.floatValue ?? 40.0
            let params = CylinderParams(radius: r, height: h)
            id = document.addObject(def: .cylinder(params), transform: transform)
        } else {
            return .error("Unsupported solid type '\(type)'. Supported: 'box', 'cylinder'")
        }
        
        return .text("Successfully added solid with ID: \(id.rawValue)")
    }
    
    private func handleSetParam(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        guard let idStr = arguments["id"]?.stringValue else {
            return .error("Missing required argument 'id'")
        }
        guard let param = arguments["param"]?.stringValue else {
            return .error("Missing required argument 'param'")
        }
        guard let val = arguments["value"]?.floatValue else {
            return .error("Missing required argument 'value'")
        }
        
        let id = SolidId(idStr)
        guard document.paramsFor(id: id) != nil else {
            return .error("Solid '\(idStr)' not found in scene")
        }
        
        document.setParam(id: id, key: param, value: val)
        return .text("Updated parameter '\(param)' on solid '\(idStr)' to \(val)")
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
        if let x = arguments["posX"]?.floatValue { transform.position.x = x }
        if let y = arguments["posY"]?.floatValue { transform.position.y = y }
        if let z = arguments["posZ"]?.floatValue { transform.position.z = z }
        
        document.setTransform(id: id, transform: transform)
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
        
        document.removeObject(id: id)
        await kernelClient.dispose(solidId: id)
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
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: resultDict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return .text(str)
        }
        return .error("Failed to measure solid '\(idStr)'")
    }
    
    private func handleCaptureSnapshot() async -> MCPToolCallResult {
        guard let provider = snapshotProvider,
              let base64 = await provider.captureSnapshotPngBase64() else {
            return .error("Snapshot provider not available or failed to capture viewport frame")
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
        let outputId = SolidId("csg-\(UUID().uuidString.prefix(6))")
        
        let req = KernelRequest.booleanOperation(
            jobId: JobId("job-\(UUID().uuidString)"),
            solidId: outputId,
            op: op,
            solidA: solidA,
            solidB: solidB
        )
        
        let result = await kernelClient.request(req)
        if case .success = result {
            document.addObject(def: .imported(name: "\(opStr)(\(solidAStr), \(solidBStr))"))
            return .text("Successfully executed \(opStr) between '\(solidAStr)' and '\(solidBStr)'. Output registered as '\(outputId.rawValue)'")
        } else {
            return .error("Boolean \(opStr) failed: \(result.error?.message ?? "unknown error")")
        }
    }
}
