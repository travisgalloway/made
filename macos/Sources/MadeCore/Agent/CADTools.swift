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
                description: "Retrieves the list of objects in the CAD document with pagination (limit and cursor).",
                inputSchema: MCPInputSchema(
                    properties: [
                        "limit": MCPProperty(
                            type: "integer",
                            description: "Maximum number of objects to return (default 50, maximum 500)"
                        ),
                        "cursor": MCPProperty(
                            type: "string",
                            description: "Opaque cursor string from a previous cad_get_scene call"
                        )
                    ]
                )
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
                description: "Modifies a specific dimension/parameter of an existing solid (e.g. width, depth, height, radius, bottomRadius, topRadius, majorRadius, minorRadius, topWidth, distance). Automatically clamped to safe ranges.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "id": MCPProperty(type: "string", description: "The solid ID (e.g. 'box-1', 'cylinder-1', 'extrude-1') or feature UUID"),
                        "param": MCPProperty(type: "string", description: "The parameter name. Box: 'width', 'depth', 'height'. Cylinder: 'radius', 'height'. Sphere: 'radius'. Cone: 'bottomRadius', 'topRadius', 'height'. Torus: 'majorRadius', 'minorRadius'. Wedge: 'width', 'depth', 'height', 'topWidth'. Extrude: 'distance'. Imported solids have no editable parameters."),
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
                        "index": MCPProperty(type: "integer", description: "Optional 0-based insertion index to position the rollback marker. When omitted and solidId is provided, rolls back to that solid."),
                        "solidId": MCPProperty(type: "string", description: "Optional solid ID to roll back to (marker placed after this solid). When 'end' or omitted with index omitted, rolls forward to the end.")
                    ]
                )
            ),
            MCPToolDefinition(
                name: "cad_create_sketch",
                description: "Creates a new 2D sketch on a specified plane ('XY', 'XZ', 'YZ', or a datum plane name/ID) with optional initial geometric entities (lines, arcs, circles). Returns the sketch feature ID and details.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "plane": MCPProperty(type: "string", description: "The sketch plane: 'XY', 'XZ', 'YZ', or the name/ID of an existing datum plane (default 'XY')"),
                        "entities": MCPProperty(type: "array", description: "Optional initial geometric entities to add to the sketch")
                    ]
                )
            ),
            MCPToolDefinition(
                name: "cad_add_sketch_entity",
                description: "Adds a 2D geometric entity (line, arc, or circle) to an existing sketch in the document.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "sketchId": MCPProperty(type: "string", description: "The UUID of the sketch feature to add the entity to"),
                        "type": MCPProperty(type: "string", description: "The entity type: 'line', 'arc', or 'circle'", enum: ["line", "arc", "circle"]),
                        "startX": MCPProperty(type: "number", description: "Start X coordinate for line or arc"),
                        "startY": MCPProperty(type: "number", description: "Start Y coordinate for line or arc"),
                        "endX": MCPProperty(type: "number", description: "End X coordinate for line or arc"),
                        "endY": MCPProperty(type: "number", description: "End Y coordinate for line or arc"),
                        "centerX": MCPProperty(type: "number", description: "Center X coordinate for arc or circle"),
                        "centerY": MCPProperty(type: "number", description: "Center Y coordinate for arc or circle"),
                        "radius": MCPProperty(type: "number", description: "Radius for circle (must be > 0)"),
                        "clockwise": MCPProperty(type: "boolean", description: "Optional: True if arc is oriented clockwise (default false)"),
                        "isConstruction": MCPProperty(type: "boolean", description: "Optional: True if entity is a construction guide (default false)")
                    ],
                    required: ["sketchId", "type"]
                )
            ),
            MCPToolDefinition(
                name: "cad_add_constraint",
                description: "Applies a geometric constraint (coincident, parallel, perpendicular, horizontal, vertical, tangent, concentric, or symmetric) between entities in a sketch.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "sketchId": MCPProperty(type: "string", description: "The UUID of the sketch feature"),
                        "type": MCPProperty(
                            type: "string",
                            description: "Constraint kind: 'parallel', 'perpendicular', 'tangent', 'concentric', 'symmetric', 'coincident', 'horizontal', 'vertical'",
                            enum: ["parallel", "perpendicular", "tangent", "concentric", "symmetric", "coincident", "horizontal", "vertical"]
                        ),
                        "entityIds": MCPProperty(type: "array", description: "Array of entity UUID strings that this constraint applies to"),
                        "referenceEntityId": MCPProperty(type: "string", description: "Optional reference entity UUID for symmetry or alignment constraints"),
                        "isDriven": MCPProperty(type: "boolean", description: "Whether the constraint is driven (reference dimension) and does not constrain degrees of freedom")
                    ],
                    required: ["sketchId", "type", "entityIds"]
                )
            ),
            MCPToolDefinition(
                name: "cad_extrude",
                description: "Extrudes a closed 2D sketch into a 3D parametric solid by a specified distance, creating an Extrude feature in the history tree.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "sketchId": MCPProperty(type: "string", description: "The UUID of the closed sketch feature to extrude"),
                        "distance": MCPProperty(type: "number", description: "Extrusion distance in mm"),
                        "isSymmetric": MCPProperty(type: "boolean", description: "Optional: If true, extrude symmetrically in both directions (default false)"),
                        "draftAngle": MCPProperty(type: "number", description: "Optional: Draft angle in degrees (default 0)"),
                        "regionId": MCPProperty(type: "string", description: "Optional UUID of a specific closed planar region in the sketch")
                    ],
                    required: ["sketchId", "distance"]
                )
            ),
            MCPToolDefinition(
                name: "cad_fillet",
                description: "Applies a topological fillet (blend) of specified radius to an edge of a solid by topological reference label (e.g. 'edge:top-front') or topological reference UUID.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "solidId": MCPProperty(type: "string", description: "The solid ID (e.g. 'box-1')"),
                        "edge": MCPProperty(type: "string", description: "Edge topological reference label (e.g. 'edge:top-front') or UUID string"),
                        "radius": MCPProperty(type: "number", description: "Fillet blend radius in mm (must be positive)")
                    ],
                    required: ["solidId", "edge", "radius"]
                )
            ),
            MCPToolDefinition(
                name: "cad_query_tree",
                description: "Queries the document's feature history tree, returning features, operations, parameters, output solids, suppression status, and generated topological references for sub-element addressing.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "featureId": MCPProperty(type: "string", description: "Optional feature UUID to query a specific feature instead of the entire tree")
                    ]
                )
            ),
            MCPToolDefinition(
                name: "cad_query_topology",
                description: "Queries 3D topological sub-elements (faces, edges, vertices) of a solid or feature, returning deterministic IDs, labels, surface/curve types, normal vectors, centroids, areas, and lengths for downstream reference selection.",
                inputSchema: MCPInputSchema(
                    properties: [
                        "solidId": MCPProperty(type: "string", description: "Optional solid ID in the scene (e.g. 'box-1'). If omitted and featureId is omitted, returns topology for all solids in the document."),
                        "featureId": MCPProperty(type: "string", description: "Optional feature UUID to query topology of a specific feature directly"),
                        "elementType": MCPProperty(type: "string", description: "Optional filter to restrict returned topology elements", enum: ["face", "edge", "vertex"])
                    ]
                )
            )
        ]
    }
    
    public func callTool(name: String, arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        switch name {
        case "cad_get_scene":
            return handleGetScene(arguments: arguments)
            
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

        case "cad_create_sketch":
            return handleCreateSketch(arguments: arguments)

        case "cad_add_sketch_entity":
            return handleAddSketchEntity(arguments: arguments)

        case "cad_add_constraint":
            return handleAddConstraint(arguments: arguments)

        case "cad_extrude":
            return handleExtrude(arguments: arguments)

        case "cad_fillet":
            return await handleFillet(arguments: arguments)

        case "cad_query_tree":
            return handleQueryTree(arguments: arguments)

        case "cad_query_topology":
            return await handleQueryTopology(arguments: arguments)
            
        default:
            return .error("Unknown tool: '\(name)'")
        }
    }
    
    // MARK: - Tool Handlers
    
    private struct SceneCursor: Codable, Sendable {
        var lastId: String?
        var recentIds: [String]?
        var offset: Int?
        var isEnd: Bool?
    }

    private func handleGetScene(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        var limit = 50
        if let rawLimit = arguments["limit"] {
            guard let intVal = rawLimit.intValue, (rawLimit.doubleValue == nil || Double(intVal) == rawLimit.doubleValue) else {
                return .error("Argument 'limit' must be an integer")
            }
            guard intVal > 0 else {
                return .error("Argument 'limit' must be greater than 0")
            }
            limit = min(intVal, 500)
        }

        let totalCount = document.objects.count
        var startIndex = 0

        if let rawCursor = arguments["cursor"] {
            guard let cursorStr = rawCursor.stringValue else {
                return .error("Argument 'cursor' must be a string")
            }
            if !cursorStr.isEmpty {
                let cursor: SceneCursor
                if cursorStr == "past-the-end" || cursorStr == "end" {
                    cursor = SceneCursor(lastId: nil, recentIds: nil, offset: totalCount, isEnd: true)
                } else if let offset = Int(cursorStr) {
                    cursor = SceneCursor(lastId: nil, recentIds: nil, offset: offset, isEnd: nil)
                } else if let data = Data(base64Encoded: cursorStr),
                          let decoded = try? JSONDecoder().decode(SceneCursor.self, from: data) {
                    cursor = decoded
                } else if let data = cursorStr.data(using: .utf8),
                          let decoded = try? JSONDecoder().decode(SceneCursor.self, from: data) {
                    cursor = decoded
                } else {
                    return .error("Argument 'cursor' is invalid")
                }

                if cursor.isEnd == true || (cursor.lastId == nil && (cursor.offset ?? 0) >= totalCount) {
                    startIndex = totalCount
                } else if let lastId = cursor.lastId, let matchIndex = document.objects.firstIndex(where: { $0.id.rawValue == lastId }) {
                    startIndex = matchIndex + 1
                } else if let recentIds = cursor.recentIds,
                          let matchedSolid = recentIds.reversed().compactMap({ id in
                              document.objects.firstIndex(where: { $0.id.rawValue == id })
                          }).first {
                    startIndex = matchedSolid + 1
                } else if let off = cursor.offset, off >= totalCount {
                    startIndex = totalCount
                } else if cursor.lastId != nil {
                    startIndex = 0
                } else if let off = cursor.offset {
                    startIndex = min(max(off, 0), totalCount)
                } else {
                    startIndex = 0
                }
            }
        }

        startIndex = min(max(startIndex, 0), totalCount)
        let sliceEnd = min(startIndex + limit, totalCount)
        let slice = startIndex < totalCount ? Array(document.objects[startIndex..<sliceEnd]) : []

        var summary: [[String: Any]] = []
        for obj in slice {
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
            case .imported(let name, _, _, _, _, _):
                item["importedName"] = name
            case .boolean(let op, let solidA, let solidB):
                item["operation"] = op.rawValue
                item["operands"] = [solidA.rawValue, solidB.rawValue]
            case .part(let url, _):
                item["file"] = url.path
            case .extrude(let p):
                item["params"] = ["distance": p.distance, "isSymmetric": p.isSymmetric]
            case .revolve(let p):
                item["params"] = ["mode": p.mode.rawValue, "angle": p.angle, "angle2": p.angle2]
            case .chamfer(let p):
                item["params"] = ["mode": p.mode.rawValue, "distance": p.distance, "distance2": p.distance2, "angle": p.angle]
            case .shell(let p):
                item["params"] = ["thickness": p.thickness, "removedFacesCount": p.removedFaceReferences.count, "overridesCount": p.perFaceOverrides.count]
            case .hole(let p):
                item["params"] = [
                    "type": p.holeType.rawValue,
                    "standard": p.standard.rawValue,
                    "diameter": p.diameter,
                    "depth": p.depth,
                    "isThrough": p.isThrough
                ]
            case .pattern(let p):
                item["params"] = [
                    "patternType": p.patternType.rawValue,
                    "targetType": p.targetType.rawValue,
                    "targetSolidId": p.targetSolidId.rawValue,
                    "count": p.count,
                    "linearSpacing": p.linearSpacing,
                    "totalAngle": p.totalAngle,
                    "skippedCount": p.skippedIndices.count
                ]
            case .mirror(let p):
                item["params"] = [
                    "targetType": p.targetType.rawValue,
                    "targetSolidId": p.targetSolidId.rawValue,
                    "planeNormal": [p.planeNormal.x, p.planeNormal.y, p.planeNormal.z],
                    "planeOrigin": [p.planeOrigin.x, p.planeOrigin.y, p.planeOrigin.z],
                    "keepOriginal": p.keepOriginal
                ]
            }
            summary.append(item)
        }

        var response: [String: Any] = [
            "objects": summary,
            "total": totalCount
        ]
        if sliceEnd < totalCount, let lastObj = slice.last {
            let nextCursorObj = SceneCursor(
                lastId: lastObj.id.rawValue,
                recentIds: slice.map(\.id.rawValue),
                offset: sliceEnd,
                isEnd: false
            )
            if let data = try? JSONEncoder().encode(nextCursorObj) {
                response["nextCursor"] = data.base64EncodedString()
            }
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
            let jsonString = String(data: data, encoding: .utf8) ?? "{}"
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
        let id = document.addObject(def: clampedDef, transform: transform, actionName: "Agent: cad_add_solid")
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
        case .revolve(let p):
            dimStr = "with angle \(p.angle)"
        case .chamfer(let p):
            dimStr = "with distance \(p.distance)"
        case .shell(let p):
            dimStr = "with thickness \(p.thickness)"
        case .hole(let p):
            dimStr = "with diameter \(p.diameter)"
        case .pattern(let p):
            dimStr = "with count \(p.count)"
        case .mirror(let p):
            dimStr = "mirrored about normal [\(p.planeNormal.x), \(p.planeNormal.y), \(p.planeNormal.z)]"
        default:
            dimStr = ""
        }
        return .text("Successfully added solid with ID: \(id.rawValue) \(dimStr) at position (\(transform.position.x), \(transform.position.y), \(transform.position.z))")
    }

    private func handleRollback(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        let oldObjects = document.objects
        let result: Result<Void, DocumentMutationError>

        if let rawIndex = arguments["index"] {
            guard let index = rawIndex.intValue else {
                return .error("Argument 'index' must be an integer")
            }
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
        
        var id = SolidId(idStr)
        if document.paramsFor(id: id) == nil {
            if let uuid = UUID(uuidString: idStr),
               let feat = document.features.first(where: { $0.id == uuid }),
               let outId = feat.outputSolidId {
                id = outId
            }
        }
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
        
        let result = document.setParam(id: id, key: param, value: val, actionName: "Agent: cad_set_param")
        switch result {
        case .failure(.objectLocked(let lockedId)):
            return .error("Solid '\(lockedId.rawValue)' is locked and cannot be edited")
        case .failure(.objectNotFound):
            return .error("Solid '\(idStr)' not found in scene")
        case .failure(.sketchError(let err)):
            return .error("Sketch error: \(err.localizedDescription)")
        case .failure(.referenceResolutionFailed(let err)):
            return .error("Reference resolution error: \(err.description)")
        case .failure(.invalidOperation(let msg)):
            return .error("Invalid operation: \(msg)")
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
        case .revolve(let p):
            if p.mode == .twoDirection {
                return [("angle", Float(p.angle)), ("angle2", Float(p.angle2))]
            } else {
                return [("angle", Float(p.angle))]
            }
        case .chamfer(let p):
            switch p.mode {
            case .equalDistance:
                return [("distance", Float(p.distance))]
            case .twoDistances:
                return [("distance", Float(p.distance)), ("distance2", Float(p.distance2))]
            case .distanceAngle:
                return [("distance", Float(p.distance)), ("angle", Float(p.angle))]
            }
        case .shell(let p):
            return [("thickness", Float(p.thickness))]
        case .hole(let p):
            var params: [(String, Float)] = [("diameter", Float(p.diameter))]
            if !p.isThrough {
                params.append(("depth", Float(p.depth)))
            }
            if p.holeType == .counterbore {
                params.append(("counterboreDiameter", Float(p.counterboreDiameter)))
                params.append(("counterboreDepth", Float(p.counterboreDepth)))
            } else if p.holeType == .countersink {
                params.append(("countersinkDiameter", Float(p.countersinkDiameter)))
                params.append(("countersinkAngle", Float(p.countersinkAngle)))
            }
            return params
        case .pattern(let p):
            var params: [(String, Float)] = [("count", Float(p.count))]
            if p.patternType == .linear {
                params.append(("linearSpacing", Float(p.linearSpacing)))
            } else {
                params.append(("totalAngle", Float(p.totalAngle)))
            }
            return params
        case .mirror(let p):
            return [
                ("normalX", Float(p.planeNormal.x)),
                ("normalY", Float(p.planeNormal.y)),
                ("normalZ", Float(p.planeNormal.z))
            ]
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
        
        let result = document.setTransform(id: id, transform: transform, actionName: "Agent: cad_set_transform")
        switch result {
        case .failure(.objectLocked(let lockedId)):
            return .error("Solid '\(lockedId.rawValue)' is locked and cannot be moved")
        case .failure(.objectNotFound):
            return .error("Solid '\(idStr)' not found in scene")
        case .failure(.sketchError(let err)):
            return .error("Sketch error: \(err.localizedDescription)")
        case .failure(.referenceResolutionFailed(let err)):
            return .error("Reference resolution error: \(err.description)")
        case .failure(.invalidOperation(let msg)):
            return .error("Invalid operation: \(msg)")
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
        document.removeObject(id: id, actionName: "Agent: cad_remove_solid")
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

        case .revolve(let p):
            resultDict["type"] = "revolve"
            resultDict["mode"] = p.mode.rawValue
            resultDict["angle"] = p.angle
            resultDict["angle2"] = p.angle2
            await settleRecomputes(for: [id])
            if let payload = await meshForObject(obj),
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["bounds"] = measurements.bounds.toDictionary()
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }

        case .chamfer(let p):
            resultDict["type"] = "chamfer"
            resultDict["mode"] = p.mode.rawValue
            resultDict["distance"] = p.distance
            resultDict["distance2"] = p.distance2
            resultDict["angle"] = p.angle
            await settleRecomputes(for: [id])
            if let payload = await meshForObject(obj),
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["bounds"] = measurements.bounds.toDictionary()
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }

        case .shell(let p):
            resultDict["type"] = "shell"
            resultDict["thickness"] = p.thickness
            resultDict["targetSolidId"] = p.targetSolidId.rawValue
            resultDict["removedFacesCount"] = p.removedFaceReferences.count
            resultDict["overridesCount"] = p.perFaceOverrides.count
            await settleRecomputes(for: [id])
            if let payload = await meshForObject(obj),
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["bounds"] = measurements.bounds.toDictionary()
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }

        case .hole(let p):
            resultDict["type"] = "hole"
            resultDict["holeType"] = p.holeType.rawValue
            resultDict["standard"] = p.standard.rawValue
            resultDict["diameter"] = p.diameter
            resultDict["depth"] = p.depth
            resultDict["isThrough"] = p.isThrough
            resultDict["targetSolidId"] = p.targetSolidId.rawValue
            await settleRecomputes(for: [id])
            if let payload = await meshForObject(obj),
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["bounds"] = measurements.bounds.toDictionary()
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }
            
        case .pattern(let p):
            resultDict["type"] = "pattern"
            resultDict["patternType"] = p.patternType.rawValue
            resultDict["count"] = p.count
            resultDict["linearSpacing"] = p.linearSpacing
            resultDict["totalAngle"] = p.totalAngle
            resultDict["targetSolidId"] = p.targetSolidId.rawValue
            await settleRecomputes(for: [id])
            if let payload = await meshForObject(obj),
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["bounds"] = measurements.bounds.toDictionary()
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }
            
        case .mirror(let p):
            resultDict["type"] = "mirror"
            resultDict["targetSolidId"] = p.targetSolidId.rawValue
            resultDict["keepOriginal"] = p.keepOriginal
            resultDict["planeNormal"] = [p.planeNormal.x, p.planeNormal.y, p.planeNormal.z]
            resultDict["planeOrigin"] = [p.planeOrigin.x, p.planeOrigin.y, p.planeOrigin.z]
            await settleRecomputes(for: [id])
            if let payload = await meshForObject(obj),
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["bounds"] = measurements.bounds.toDictionary()
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }
            
        case .imported(let name, _, _, _, _, _):
            resultDict["type"] = "imported"
            resultDict["name"] = name
            await settleRecomputes(for: [id])
            var candidate = meshSink?.candidateMesh(for: id)
            var payload: MeshPayload? = nil
            if candidate == nil {
                if let resolvedPayload = await meshForObject(obj) {
                    payload = resolvedPayload
                    candidate = CandidateMesh(id: id, payload: resolvedPayload, transform: obj.transform)
                }
            }
            if payload == nil, let c = candidate, c.indices.count >= 3 {
                var rawPos: [Float] = []
                rawPos.reserveCapacity(c.positions.count * 3)
                for p in c.positions {
                    rawPos.append(contentsOf: [p.x, p.y, p.z])
                }
                let rawNormals: [Float] = Array(repeating: 0, count: rawPos.count)
                payload = MeshPayload(
                    positions: rawPos,
                    normals: rawNormals,
                    indices: c.indices,
                    faceRanges: c.faceRanges,
                    edgePolylines: c.edgePolylines,
                    vertexPoints: c.vertexPoints
                )
            }
            if let payload,
               let measurements = SolidVerifier.analyzeMesh(payload, transform: obj.transform).measurements {
                resultDict["volumeMm3"] = measurements.volume
                resultDict["surfaceAreaMm2"] = measurements.area
            }
            if let candidate, let boxes = BoundingBoxCalculator.boxes(for: candidate) {
                resultDict["bounds"] = boxes.axisAligned.toDictionary()
                resultDict["axisAlignedBox"] = boxes.axisAligned.toDictionary()
                resultDict["orientedBox"] = boxes.oriented.toDictionary()
            }
            
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
        
        if resultDict["axisAlignedBox"] == nil {
            let candidates = meshSink?.candidateMesh(for: id).map { [$0] } ?? []
            if let boxes = BoundingBoxCalculator.boxes(for: id, in: document, candidateMeshes: candidates) {
                resultDict["axisAlignedBox"] = boxes.axisAligned.toDictionary()
                resultDict["orientedBox"] = boxes.oriented.toDictionary()
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

        case .box, .cylinder, .sphere, .cone, .torus, .wedge, .boolean, .extrude, .revolve, .chamfer, .shell, .hole, .pattern, .mirror:
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
            document.addBooleanObject(outputId, def: def, keepTool: keepTool, actionName: "Agent: cad_boolean_operation")
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

    // MARK: - Feature-Level Tool Handlers

    private func handleCreateSketch(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        let planeArg = arguments["plane"]?.stringValue ?? "XY"
        let planeUpper = planeArg.uppercased()
        let resolvedPlaneName: String
        if ["XY", "XZ", "YZ"].contains(planeUpper) {
            resolvedPlaneName = planeUpper
        } else if let datumFeat = document.features.first(where: { feat in
            if case .datumPlane = feat.operation {
                return feat.name.caseInsensitiveCompare(planeArg) == .orderedSame || feat.id.uuidString.caseInsensitiveCompare(planeArg) == .orderedSame
            }
            return false
        }) {
            resolvedPlaneName = datumFeat.name
        } else {
            return .error("Invalid plane '\(planeArg)'. Must be 'XY', 'XZ', 'YZ', or an existing datum plane name/ID.")
        }

        var entities: [SketchEntity] = []
        if let rawEntities = arguments["entities"]?.arrayValue {
            for (idx, rawEnt) in rawEntities.enumerated() {
                guard let dict = rawEnt.dictionaryValue else {
                    return .error("Entity at index \(idx) must be an object")
                }
                do {
                    let entity = try Self.parseSketchEntity(from: dict)
                    entities.append(entity)
                } catch {
                    return .error(error.message)
                }
            }
        }

        let feature = document.addSketchFeature(planeName: resolvedPlaneName, entities: entities)
        let summary: [String: Any] = [
            "id": feature.id.uuidString,
            "name": feature.name,
            "plane": resolvedPlaneName,
            "entityCount": entities.count
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys, .prettyPrinted]),
              let jsonText = String(data: jsonData, encoding: .utf8) else {
            return .text("Created sketch '\(feature.name)' with ID \(feature.id.uuidString) on plane \(resolvedPlaneName)")
        }
        return .text(jsonText)
    }

    private func handleAddSketchEntity(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        guard let sketchIdStr = arguments["sketchId"]?.stringValue else {
            return .error("Missing required argument 'sketchId'")
        }
        guard let sketchUUID = UUID(uuidString: sketchIdStr) else {
            return .error("Invalid UUID for 'sketchId': '\(sketchIdStr)'")
        }
        guard let feature = document.feature(for: sketchUUID) else {
            return .error("Sketch '\(sketchIdStr)' not found in document")
        }
        guard case .sketch = feature.operation else {
            return .error("Feature '\(sketchIdStr)' is not a sketch")
        }

        let entity: SketchEntity
        do {
            entity = try Self.parseSketchEntity(from: arguments)
        } catch {
            return .error(error.message)
        }

        let result = document.addSketchEntity(to: sketchUUID, entity: entity)
        switch result {
        case .success:
            return .text("Added \(entity.kind) entity '\(entity.id.uuidString)' to sketch '\(sketchIdStr)'")
        case .failure(let err):
            return .error("Failed to add entity to sketch: \(err)")
        }
    }

    private static func parseSketchEntity(from dict: [String: AnyCodableValue]) throws(ArgumentError) -> SketchEntity {
        guard let type = dict["type"]?.stringValue ?? dict["kind"]?.stringValue else {
            throw ArgumentError(message: "Entity missing required 'type' ('line', 'arc', or 'circle')")
        }
        let isConstruction = dict["isConstruction"]?.boolValue ?? false
        switch type.lowercased() {
        case "line":
            guard let sx = dict["startX"]?.doubleValue, sx.isFinite else {
                throw ArgumentError(message: "Line entity missing or invalid 'startX'")
            }
            guard let sy = dict["startY"]?.doubleValue, sy.isFinite else {
                throw ArgumentError(message: "Line entity missing or invalid 'startY'")
            }
            guard let ex = dict["endX"]?.doubleValue, ex.isFinite else {
                throw ArgumentError(message: "Line entity missing or invalid 'endX'")
            }
            guard let ey = dict["endY"]?.doubleValue, ey.isFinite else {
                throw ArgumentError(message: "Line entity missing or invalid 'endY'")
            }
            return SketchEntity.line(start: SIMD2(sx, sy), end: SIMD2(ex, ey), isConstruction: isConstruction)

        case "arc":
            guard let sx = dict["startX"]?.doubleValue, sx.isFinite else {
                throw ArgumentError(message: "Arc entity missing or invalid 'startX'")
            }
            guard let sy = dict["startY"]?.doubleValue, sy.isFinite else {
                throw ArgumentError(message: "Arc entity missing or invalid 'startY'")
            }
            guard let ex = dict["endX"]?.doubleValue, ex.isFinite else {
                throw ArgumentError(message: "Arc entity missing or invalid 'endX'")
            }
            guard let ey = dict["endY"]?.doubleValue, ey.isFinite else {
                throw ArgumentError(message: "Arc entity missing or invalid 'endY'")
            }
            guard let cx = dict["centerX"]?.doubleValue, cx.isFinite else {
                throw ArgumentError(message: "Arc entity missing or invalid 'centerX'")
            }
            guard let cy = dict["centerY"]?.doubleValue, cy.isFinite else {
                throw ArgumentError(message: "Arc entity missing or invalid 'centerY'")
            }
            let clockwise = dict["clockwise"]?.boolValue ?? false
            return SketchEntity.arc(start: SIMD2(sx, sy), end: SIMD2(ex, ey), center: SIMD2(cx, cy), clockwise: clockwise, isConstruction: isConstruction)

        case "circle":
            guard let cx = dict["centerX"]?.doubleValue, cx.isFinite else {
                throw ArgumentError(message: "Circle entity missing or invalid 'centerX'")
            }
            guard let cy = dict["centerY"]?.doubleValue, cy.isFinite else {
                throw ArgumentError(message: "Circle entity missing or invalid 'centerY'")
            }
            guard let r = dict["radius"]?.doubleValue, r.isFinite, r > 0 else {
                throw ArgumentError(message: "Circle entity missing or invalid 'radius' (must be > 0)")
            }
            return SketchEntity.circle(center: SIMD2(cx, cy), radius: r, isConstruction: isConstruction)

        default:
            throw ArgumentError(message: "Unknown entity type '\(type)' (supported: 'line', 'arc', 'circle')")
        }
    }

    private func handleAddConstraint(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        guard let sketchIdStr = arguments["sketchId"]?.stringValue else {
            return .error("Missing required argument 'sketchId'")
        }
        guard let sketchUUID = UUID(uuidString: sketchIdStr) else {
            return .error("Invalid UUID for 'sketchId': '\(sketchIdStr)'")
        }
        guard let feature = document.feature(for: sketchUUID) else {
            return .error("Sketch '\(sketchIdStr)' not found in document")
        }
        guard case .sketch(let sketchData) = feature.operation else {
            return .error("Feature '\(sketchIdStr)' is not a sketch")
        }
        guard let typeStr = arguments["type"]?.stringValue else {
            return .error("Missing required argument 'type'")
        }
        guard let kind = SketchConstraint.Kind(rawValue: typeStr.lowercased()) else {
            return .error("Unknown constraint kind '\(typeStr)'. Supported: parallel, perpendicular, tangent, concentric, symmetric, coincident, horizontal, vertical")
        }
        guard let entityIdsVal = arguments["entityIds"]?.arrayValue, !entityIdsVal.isEmpty else {
            return .error("Missing or empty required argument 'entityIds'")
        }

        var entityUUIDs: [UUID] = []
        for val in entityIdsVal {
            guard let idStr = val.stringValue, let uuid = UUID(uuidString: idStr) else {
                return .error("Invalid entity ID in 'entityIds'")
            }
            guard sketchData.entities.contains(where: { $0.id == uuid }) else {
                return .error("Entity '\(idStr)' not found in sketch '\(sketchIdStr)'")
            }
            entityUUIDs.append(uuid)
        }

        var refUUID: UUID? = nil
        if let refStr = arguments["referenceEntityId"]?.stringValue {
            guard let rUUID = UUID(uuidString: refStr) else {
                return .error("Invalid 'referenceEntityId'")
            }
            guard sketchData.entities.contains(where: { $0.id == rUUID }) else {
                return .error("Reference entity '\(refStr)' not found in sketch '\(sketchIdStr)'")
            }
            refUUID = rUUID
        }

        let isDriven = arguments["isDriven"]?.boolValue ?? false
        let constraint = SketchConstraint(kind: kind, entityIds: entityUUIDs, referenceEntityId: refUUID, isDriven: isDriven)
        let res = document.addSketchConstraint(to: sketchUUID, constraint: constraint)
        switch res {
        case .success:
            let statusSuffix = isDriven ? " (driven reference)" : ""
            return .text("Added \(kind.rawValue)\(statusSuffix) constraint '\(constraint.id.uuidString)' to sketch '\(sketchIdStr)'")
        case .failure(let err):
            return .error("Failed to add constraint to sketch: \(err)")
        }
    }

    private func handleExtrude(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        guard let sketchIdStr = arguments["sketchId"]?.stringValue else {
            return .error("Missing required argument 'sketchId'")
        }
        guard let sketchUUID = UUID(uuidString: sketchIdStr) else {
            return .error("Invalid UUID for 'sketchId': '\(sketchIdStr)'")
        }
        guard let feature = document.feature(for: sketchUUID) else {
            return .error("Sketch '\(sketchIdStr)' not found in document")
        }
        guard case .sketch = feature.operation else {
            return .error("Feature '\(sketchIdStr)' is not a sketch")
        }
        guard let rawDistance = arguments["distance"]?.doubleValue, rawDistance.isFinite else {
            return .error("Missing or invalid 'distance' (must be a finite number)")
        }

        let isSymmetric = arguments["isSymmetric"]?.boolValue ?? false
        var draftAngle = 0.0
        if let da = arguments["draftAngle"]?.doubleValue {
            guard da.isFinite else {
                return .error("Argument 'draftAngle' must be a finite number")
            }
            draftAngle = da
        }

        var regionUUID: UUID? = nil
        if let rStr = arguments["regionId"]?.stringValue {
            guard let ruuid = UUID(uuidString: rStr) else {
                return .error("Invalid 'regionId': '\(rStr)'")
            }
            regionUUID = ruuid
        }

        do {
            let extrudeFeature = try document.extrudeSketch(
                sketchFeatureId: sketchUUID,
                distance: rawDistance,
                isSymmetric: isSymmetric,
                draftAngle: draftAngle,
                regionId: regionUUID
            )
            guard let solidId = extrudeFeature.outputSolidId else {
                return .error("Extrude feature did not produce an output solid")
            }
            scheduleRecompute(id: solidId)
            return .text("Created extrude feature '\(extrudeFeature.id.uuidString)' with solid '\(solidId.rawValue)' (distance: \(rawDistance) mm)")
        } catch {
            return .error("Failed to extrude sketch: \(error)")
        }
    }

    private func handleFillet(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        guard let solidIdStr = arguments["solidId"]?.stringValue else {
            return .error("Missing required argument 'solidId'")
        }
        let solidId = SolidId(solidIdStr)
        guard document.objects.contains(where: { $0.id == solidId }) else {
            return .error("Solid '\(solidIdStr)' not found in scene")
        }
        guard let rawRadius = arguments["radius"]?.doubleValue, rawRadius.isFinite, rawRadius > 0 else {
            return .error("Fillet radius must be a finite positive number")
        }
        guard let edgeStr = arguments["edge"]?.stringValue, !edgeStr.isEmpty else {
            return .error("Missing required argument 'edge'")
        }

        await settleRecomputes(for: [solidId])

        guard let feat = document.feature(for: solidId) else {
            return .error("Feature for solid '\(solidIdStr)' not found")
        }

        let edgeRef: TopologicalReference
        if let ref = feat.generatedTopology[edgeStr] {
            edgeRef = ref
        } else if let ref = feat.generatedTopology.values.first(where: {
            $0.id.uuidString.caseInsensitiveCompare(edgeStr) == .orderedSame && $0.elementType == .edge
        }) {
            edgeRef = ref
        } else {
            let available = feat.generatedTopology.filter { $0.value.elementType == .edge }.keys.sorted()
            return .error("Edge '\(edgeStr)' not found on solid '\(solidId.rawValue)'. Available edges: \(available.joined(separator: ", "))")
        }

        let jobId = JobId("fillet-\(UUID().uuidString)")
        let req = KernelRequest.fillet(jobId: jobId, solidId: solidId, edgeReference: edgeRef, radius: rawRadius)
        let res = await kernelClient.request(req)
        switch res {
        case .success:
            if let sink = meshSink {
                _ = SolidMeshApplier.apply(res, to: solidId, document: document, sink: sink)
            }
            onViewportInvalidated?()
            return .text("Successfully applied fillet of radius \(rawRadius) mm to edge '\(edgeStr)' on solid '\(solidId.rawValue)'")
        case .failure(_, let err):
            return .error("Fillet failed on solid '\(solidId.rawValue)': \(err.message)")
        }
    }

    private func handleQueryTree(arguments: [String: AnyCodableValue]) -> MCPToolCallResult {
        if let featIdStr = arguments["featureId"]?.stringValue {
            guard let uuid = UUID(uuidString: featIdStr) else {
                return .error("Invalid UUID for 'featureId': '\(featIdStr)'")
            }
            guard let feat = document.features.first(where: { $0.id == uuid }) else {
                return .error("Feature '\(featIdStr)' not found in document")
            }
            let dict = featureSummary(feat)
            guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted]),
                  let text = String(data: data, encoding: .utf8) else {
                return .error("Failed to serialize feature '\(featIdStr)'")
            }
            return .text(text)
        }

        let summaries = document.features.map { featureSummary($0) }
        let root: [String: Any] = ["features": summaries]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            return .error("Failed to serialize feature tree")
        }
        return .text(text)
    }

    private func featureSummary(_ feature: Feature) -> [String: Any] {
        var dict: [String: Any] = [
            "id": feature.id.uuidString,
            "name": feature.name,
            "isSuppressed": feature.isSuppressed,
            "isLocked": feature.isLocked
        ]
        if let solidId = feature.outputSolidId {
            dict["outputSolidId"] = solidId.rawValue
        }

        var paramsDict: [String: Any] = [:]
        for (k, expr) in feature.inputExpressions {
            paramsDict[k] = expr.value
        }
        dict["params"] = paramsDict

        var topologyDict: [String: String] = [:]
        for (k, topRef) in feature.generatedTopology {
            topologyDict[k] = topRef.id.uuidString
        }
        dict["generatedTopology"] = topologyDict

        switch feature.operation {
        case .primitive(let prim):
            dict["type"] = "primitive"
            switch prim {
            case .box: dict["primitiveKind"] = "box"
            case .cylinder: dict["primitiveKind"] = "cylinder"
            case .sphere: dict["primitiveKind"] = "sphere"
            case .cone: dict["primitiveKind"] = "cone"
            case .torus: dict["primitiveKind"] = "torus"
            case .wedge: dict["primitiveKind"] = "wedge"
            }
        case .sketch(let sketchData):
            dict["type"] = "sketch"
            dict["plane"] = sketchData.planeName ?? "XY"
            dict["entityCount"] = sketchData.entities.count
            dict["entities"] = sketchData.entities.map { ent -> [String: Any] in
                var ed: [String: Any] = [
                    "id": ent.id.uuidString,
                    "kind": ent.kind,
                    "isConstruction": ent.isConstruction
                ]
                for (k, v) in ent.data {
                    ed[k] = v
                }
                return ed
            }
            dict["constraints"] = sketchData.constraints.map { c -> [String: Any] in
                var cd: [String: Any] = [
                    "id": c.id.uuidString,
                    "kind": c.kind.rawValue,
                    "entityIds": c.entityIds.map(\.uuidString),
                    "isDriven": c.isDriven
                ]
                if let ref = c.referenceEntityId {
                    cd["referenceEntityId"] = ref.uuidString
                }
                return cd
            }
        case .extrude(let extrudeData):
            dict["type"] = "extrude"
            dict["distance"] = extrudeData.distance
            dict["isSymmetric"] = extrudeData.isSymmetric
            dict["draftAngle"] = extrudeData.draftAngle
            if let sfId = extrudeData.sketchFeatureId {
                dict["sketchFeatureId"] = sfId.uuidString
            }
            if let rId = extrudeData.regionId {
                dict["regionId"] = rId.uuidString
            }
        case .revolve(let revolveData):
            dict["type"] = "revolve"
            dict["mode"] = revolveData.mode.rawValue
            dict["angle"] = revolveData.angle
            dict["angle2"] = revolveData.angle2
            if let sfId = revolveData.sketchFeatureId {
                dict["sketchFeatureId"] = sfId.uuidString
            }
            if let rId = revolveData.regionId {
                dict["regionId"] = rId.uuidString
            }
            if let axisRef = revolveData.axisReference {
                dict["axisReference"] = axisRef.id.uuidString
            }
        case .chamfer(let chamferData):
            dict["type"] = "chamfer"
            dict["mode"] = chamferData.mode.rawValue
            dict["distance"] = chamferData.distance
            dict["distance2"] = chamferData.distance2
            dict["angle"] = chamferData.angle
            dict["targetSolidId"] = chamferData.targetSolidId.rawValue
            dict["edgeReferences"] = chamferData.edgeReferences.map { $0.id.uuidString }
        case .shell(let shellData):
            dict["type"] = "shell"
            dict["thickness"] = shellData.thickness
            dict["targetSolidId"] = shellData.targetSolidId.rawValue
            dict["removedFaceReferences"] = shellData.removedFaceReferences.map { $0.id.uuidString }
            dict["overridesCount"] = shellData.perFaceOverrides.count
        case .hole(let holeData):
            dict["type"] = "hole"
            dict["holeType"] = holeData.holeType.rawValue
            dict["standard"] = holeData.standard.rawValue
            dict["diameter"] = holeData.diameter
            dict["depth"] = holeData.depth
            dict["isThrough"] = holeData.isThrough
            dict["targetSolidId"] = holeData.targetSolidId.rawValue
            dict["faceReference"] = holeData.faceReference.id.uuidString
        case .boolean(let boolData):
            dict["type"] = "boolean"
            dict["operation"] = boolData.op.rawValue
            dict["targetSolidId"] = boolData.targetSolidId.rawValue
            dict["toolSolidId"] = boolData.toolSolidId.rawValue
        case .part(let partData):
            dict["type"] = "part"
            dict["url"] = partData.url.path
        case .imported(let impData):
            dict["type"] = "imported"
            dict["name"] = impData.name
        case .datumPlane(let datumData):
            dict["type"] = "datumPlane"
            dict["originPreset"] = datumData.originPreset
        case .datumAxis(let axisData):
            dict["type"] = "datumAxis"
            dict["presetName"] = axisData.presetName
        case .datumPoint(let pointData):
            dict["type"] = "datumPoint"
            dict["mode"] = pointData.mode.rawValue
        case .datumCoordinateSystem:
            dict["type"] = "datumCoordinateSystem"
        case .pattern(let patternData):
            dict["type"] = "pattern"
            dict["patternType"] = patternData.patternType.rawValue
            dict["targetType"] = patternData.targetType.rawValue
            dict["targetSolidId"] = patternData.targetSolidId.rawValue
            dict["count"] = patternData.count
            dict["linearSpacing"] = patternData.linearSpacing
            dict["direction"] = patternData.direction
            dict["isSymmetric"] = patternData.isSymmetric
            dict["axisOrigin"] = [patternData.axisOrigin.x, patternData.axisOrigin.y, patternData.axisOrigin.z]
            dict["axisDirection"] = [patternData.axisDirection.x, patternData.axisDirection.y, patternData.axisDirection.z]
            dict["totalAngle"] = patternData.totalAngle
            dict["isFullCircle"] = patternData.isFullCircle
            dict["skippedIndices"] = Array(patternData.skippedIndices)
        case .mirror(let mirrorData):
            dict["type"] = "mirror"
            dict["targetType"] = mirrorData.targetType.rawValue
            dict["targetSolidId"] = mirrorData.targetSolidId.rawValue
            dict["planeNormal"] = [mirrorData.planeNormal.x, mirrorData.planeNormal.y, mirrorData.planeNormal.z]
            dict["planeOrigin"] = [mirrorData.planeOrigin.x, mirrorData.planeOrigin.y, mirrorData.planeOrigin.z]
            dict["keepOriginal"] = mirrorData.keepOriginal
        case .combine(let combineData):
            dict["type"] = "combine"
            dict["operation"] = combineData.operation.rawValue
            dict["targetBodyId"] = combineData.targetBodyId.rawValue
            dict["toolBodyId"] = combineData.toolBodyId.rawValue
            dict["keepTool"] = combineData.keepTool
        case .moveBody(let moveData):
            dict["type"] = "moveBody"
            dict["targetBodyId"] = moveData.targetBodyId.rawValue
        case .copyBody(let copyData):
            dict["type"] = "copyBody"
            dict["sourceBodyId"] = copyData.sourceBodyId.rawValue
            dict["newBodyId"] = copyData.newBodyId.rawValue
        case .deleteBody(let deleteData):
            dict["type"] = "deleteBody"
            dict["targetBodyId"] = deleteData.targetBodyId.rawValue
        }

        return dict
    }

    private func handleQueryTopology(arguments: [String: AnyCodableValue]) async -> MCPToolCallResult {
        var filterType: SubelementType? = nil
        if let typeVal = arguments["elementType"]?.stringValue, !typeVal.isEmpty {
            switch typeVal.lowercased() {
            case "face":
                filterType = .face
            case "edge":
                filterType = .edge
            case "vertex":
                filterType = .vertex
            default:
                return .error("Invalid elementType: '\(typeVal)'. Expected 'face', 'edge', or 'vertex'")
            }
        }

        if let solidIdStr = arguments["solidId"]?.stringValue {
            let solidId = SolidId(solidIdStr)
            guard document.objects.contains(where: { $0.id == solidId }) else {
                return .error("Solid '\(solidIdStr)' not found in scene")
            }
            await settleRecomputes(for: [solidId])
            guard let feat = document.feature(for: solidId) else {
                return .error("Feature for solid '\(solidIdStr)' not found")
            }
            let summary = topologySummary(feature: feat, solidId: solidId, filter: filterType)
            guard let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys, .prettyPrinted]),
                  let text = String(data: data, encoding: .utf8) else {
                return .error("Failed to serialize topology for solid '\(solidIdStr)'")
            }
            return .text(text)
        } else if let featIdStr = arguments["featureId"]?.stringValue {
            guard let uuid = UUID(uuidString: featIdStr) else {
                return .error("Invalid UUID for 'featureId': '\(featIdStr)'")
            }
            guard let feat = document.features.first(where: { $0.id == uuid }) else {
                return .error("Feature '\(featIdStr)' not found in document")
            }
            if let solidId = feat.outputSolidId {
                await settleRecomputes(for: [solidId])
            }
            let summary = topologySummary(feature: feat, solidId: feat.outputSolidId, filter: filterType)
            guard let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys, .prettyPrinted]),
                  let text = String(data: data, encoding: .utf8) else {
                return .error("Failed to serialize topology for feature '\(featIdStr)'")
            }
            return .text(text)
        } else {
            await settleRecomputes(for: document.objects.map(\.id))
            var summaries: [[String: Any]] = []
            var totalCount = 0
            for obj in document.objects {
                if let feat = document.feature(for: obj.id) {
                    let summary = topologySummary(feature: feat, solidId: obj.id, filter: filterType)
                    summaries.append(summary)
                    if let count = summary["count"] as? Int {
                        totalCount += count
                    }
                }
            }
            let root: [String: Any] = [
                "solids": summaries,
                "count": totalCount
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted]),
                  let text = String(data: data, encoding: .utf8) else {
                return .error("Failed to serialize topology")
            }
            return .text(text)
        }
    }

    private func topologySummary(feature: Feature, solidId: SolidId?, filter: SubelementType?) -> [String: Any] {
        var faces: [[String: Any]] = []
        var edges: [[String: Any]] = []
        var vertices: [[String: Any]] = []

        for (label, ref) in feature.generatedTopology.sorted(by: { $0.key < $1.key }) {
            if let filter, ref.elementType != filter {
                continue
            }
            var elemDict: [String: Any] = [
                "id": ref.id.uuidString,
                "label": label,
                "elementType": ref.elementType.rawValue
            ]
            if let sig = ref.disambiguator {
                if let surfaceOrCurveType = sig.surfaceOrCurveType {
                    elemDict["type"] = surfaceOrCurveType
                }
                if let normal = sig.normal {
                    elemDict["normal"] = [Double(normal.x), Double(normal.y), Double(normal.z)]
                }
                if let centroid = sig.centroid {
                    elemDict["centroid"] = [Double(centroid.x), Double(centroid.y), Double(centroid.z)]
                }
                if let aol = sig.areaOrLength {
                    elemDict["areaOrLength"] = aol
                    if ref.elementType == .face {
                        elemDict["area"] = aol
                    } else if ref.elementType == .edge {
                        elemDict["length"] = aol
                    }
                }
            }
            switch ref.elementType {
            case .face:
                faces.append(elemDict)
            case .edge:
                edges.append(elemDict)
            case .vertex:
                vertices.append(elemDict)
            }
        }

        var dict: [String: Any] = [
            "featureId": feature.id.uuidString,
            "count": faces.count + edges.count + vertices.count
        ]
        if let solidId {
            dict["solidId"] = solidId.rawValue
        }
        if filter == nil || filter == .face {
            dict["faces"] = faces
        }
        if filter == nil || filter == .edge {
            dict["edges"] = edges
        }
        if filter == nil || filter == .vertex {
            dict["vertices"] = vertices
        }
        return dict
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

    /// Re-tessellates `id` with the specified or document tolerances in the background.
    /// When `meshSink` is bound, installs the resulting mesh using the live document state and invalidates the viewport.
    @discardableResult
    public func scheduleRetessellate(id: SolidId, tolerances: KernelTolerances? = nil) -> Task<KernelResult<MeshPayload>, Never>? {
        guard document.objects.contains(where: { $0.id == id }) else { return nil }
        let jobId = JobId("tess-\(UUID().uuidString)")
        let tol = (tolerances ?? document.settings.tolerances).clamped()
        let request = KernelRequest.tessellate(jobId: jobId, solidId: id, tolerances: tol)
        let client = kernelClient
        let priorTask = inFlightRecomputes[id]?.task
        let task = Task { @MainActor [weak self] () -> KernelResult<MeshPayload> in
            _ = await priorTask?.value
            guard let self, self.document.objects.contains(where: { $0.id == id }) else {
                return .failure(jobId: jobId, error: KernelError(code: .cancelled, message: "Solid removed before tessellation started"))
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

    /// Re-tessellates all solids in the document with the specified or document tolerances.
    @discardableResult
    public func scheduleRetessellateAll(tolerances: KernelTolerances? = nil) -> [Task<KernelResult<MeshPayload>, Never>] {
        let tol = (tolerances ?? document.settings.tolerances).clamped()
        var tasks: [Task<KernelResult<MeshPayload>, Never>] = []
        for obj in document.objects {
            if let task = scheduleRetessellate(id: obj.id, tolerances: tol) {
                tasks.append(task)
            }
        }
        return tasks
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
            guard err.code != .cancelled else { return }
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
