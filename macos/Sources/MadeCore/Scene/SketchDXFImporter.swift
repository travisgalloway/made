import Foundation
import simd

/// AutoCAD layer representation parsed from DXF TABLES or ENTITIES.
public struct DXFLayer: Sendable, Equatable, Hashable, Codable {
    public var name: String
    public var color: Int
    public var lineType: String
    public var isFrozen: Bool
    public var isLocked: Bool

    public init(
        name: String,
        color: Int = 7,
        lineType: String = "CONTINUOUS",
        isFrozen: Bool = false,
        isLocked: Bool = false
    ) {
        self.name = name
        self.color = color
        self.lineType = lineType
        self.isFrozen = isFrozen
        self.isLocked = isLocked
    }
}

/// Options configuring AutoCAD ASCII DXF parsing and sketch entity generation.
public struct DXFImportOptions: Sendable, Equatable {
    /// Optional length unit override superseding $INSUNITS.
    public var unitOverride: LengthUnit?
    /// Additional uniform scale factor applied to all coordinates and dimensions.
    public var scale: Double
    /// Translation offset in millimeters applied after scaling.
    public var offset: SIMD2<Double>
    /// Optional layer filter. When non-nil, only entities on matching layers are imported.
    public var layerFilter: Set<String>?
    /// Layer names designated as construction geometry (case-insensitive).
    public var constructionLayers: Set<String>
    /// Linetype names designated as construction geometry (case-insensitive).
    public var constructionLinetypes: Set<String>
    /// When true, forces all imported entities to have `isConstruction == true`.
    public var markAllConstruction: Bool
    /// When true, snaps nearby endpoints and generates coincident constraints.
    public var weldEndpoints: Bool
    /// Maximum distance in millimeters between endpoints to consider them coincident.
    public var weldTolerance: Double
    /// Number of piecewise linear segments used to discretize B-splines.
    public var splineIntervals: Int
    /// Minimum geometry threshold below which degenerate entities are skipped.
    public var tolerance: Double

    public init(
        unitOverride: LengthUnit? = nil,
        scale: Double = 1.0,
        offset: SIMD2<Double> = .zero,
        layerFilter: Set<String>? = nil,
        constructionLayers: Set<String> = ["CONSTRUCTION", "CENTER", "HIDDEN", "DEFPOINTS"],
        constructionLinetypes: Set<String> = ["CENTER", "HIDDEN", "DASHED", "PHANTOM"],
        markAllConstruction: Bool = false,
        weldEndpoints: Bool = true,
        weldTolerance: Double = 1e-3,
        splineIntervals: Int = 32,
        tolerance: Double = 1e-6
    ) {
        self.unitOverride = unitOverride
        self.scale = scale
        self.offset = offset
        self.layerFilter = layerFilter
        self.constructionLayers = constructionLayers
        self.constructionLinetypes = constructionLinetypes
        self.markAllConstruction = markAllConstruction
        self.weldEndpoints = weldEndpoints
        self.weldTolerance = weldTolerance
        self.splineIntervals = splineIntervals
        self.tolerance = tolerance
    }
}

/// Parsed DXF file container containing metadata, layers, entities, and constraints.
public struct DXFDocument: Sendable {
    public var headerUnits: LengthUnit?
    public var insunitsRaw: Int?
    public var layers: [DXFLayer]
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]

    public init(
        headerUnits: LengthUnit? = nil,
        insunitsRaw: Int? = nil,
        layers: [DXFLayer] = [],
        entities: [SketchEntity] = [],
        constraints: [SketchConstraint] = []
    ) {
        self.headerUnits = headerUnits
        self.insunitsRaw = insunitsRaw
        self.layers = layers
        self.entities = entities
        self.constraints = constraints
    }
}

/// Result returned from importing DXF content into sketch structures.
public struct DXFParseResult: Sendable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]
    public var layers: [DXFLayer]
    public var detectedUnit: LengthUnit?

    public init(
        entities: [SketchEntity],
        constraints: [SketchConstraint] = [],
        layers: [DXFLayer] = [],
        detectedUnit: LengthUnit? = nil
    ) {
        self.entities = entities
        self.constraints = constraints
        self.layers = layers
        self.detectedUnit = detectedUnit
    }
}

/// Pure-Swift ASCII DXF parser converting 2D AutoCAD entities into sketch geometry.
public enum SketchDXFImporter {

    /// DXF group code and value token pair.
    private struct DXFPair {
        let code: Int
        let value: String
    }

    /// Vertex representation used during LWPOLYLINE and POLYLINE parsing.
    private struct PolyVertex {
        var pt: SIMD2<Double>
        var bulge: Double = 0.0
    }

    // MARK: - Public Entry Points

    /// Parses an ASCII DXF string and returns a complete `DXFDocument`.
    public static func parseDXF(
        dxfText: String,
        options: DXFImportOptions = DXFImportOptions()
    ) throws -> DXFDocument {
        let pairs = tokenize(dxfText)
        guard !pairs.isEmpty else {
            throw SketchError.invalidEntity("DXF file is empty or contains no valid group codes")
        }

        var insunitsRaw: Int?
        var layersDict: [String: DXFLayer] = [:]
        var entities: [SketchEntity] = []

        var index = 0
        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0 && pair.value == "SECTION" {
                index += 1
                guard index < pairs.count && pairs[index].code == 2 else { continue }
                let sectionName = pairs[index].value.uppercased()
                index += 1

                switch sectionName {
                case "HEADER":
                    parseHeader(pairs: pairs, index: &index, insunitsRaw: &insunitsRaw)
                case "TABLES":
                    parseTables(pairs: pairs, index: &index, layersDict: &layersDict)
                case "ENTITIES":
                    parseEntities(
                        pairs: pairs,
                        index: &index,
                        insunitsRaw: insunitsRaw,
                        layersDict: &layersDict,
                        options: options,
                        entities: &entities
                    )
                default:
                    skipSection(pairs: pairs, index: &index)
                }
            } else if pair.code == 0 && pair.value == "EOF" {
                break
            } else {
                index += 1
            }
        }

        let detectedUnit = mapINSUNITSToLengthUnit(insunitsRaw)
        var constraints: [SketchConstraint] = []

        if options.weldEndpoints && !entities.isEmpty {
            weldEndpoints(in: &entities, constraints: &constraints, tolerance: options.weldTolerance)
        }

        return DXFDocument(
            headerUnits: detectedUnit,
            insunitsRaw: insunitsRaw,
            layers: Array(layersDict.values).sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }),
            entities: entities,
            constraints: constraints
        )
    }

    /// Imports DXF text and returns sketch entities and constraints ready for addition to a sketch feature.
    public static func importDXF(
        dxfText: String,
        options: DXFImportOptions = DXFImportOptions()
    ) throws -> DXFParseResult {
        let doc = try parseDXF(dxfText: dxfText, options: options)
        return DXFParseResult(
            entities: doc.entities,
            constraints: doc.constraints,
            layers: doc.layers,
            detectedUnit: doc.headerUnits
        )
    }

    // MARK: - Tokenizer

    private static func tokenize(_ text: String) -> [DXFPair] {
        var pairs: [DXFPair] = []
        pairs.reserveCapacity(text.count / 20)

        var pendingCode: Int? = nil

        text.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }

            if let code = pendingCode {
                if code != 999 { // Skip comment lines
                    pairs.append(DXFPair(code: code, value: trimmed))
                }
                pendingCode = nil
                if code == 0 && trimmed == "EOF" {
                    stop = true
                }
            } else {
                if let code = Int(trimmed) {
                    pendingCode = code
                }
            }
        }

        return pairs
    }

    // MARK: - Section Parsers

    private static func skipSection(pairs: [DXFPair], index: inout Int) {
        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0 && (pair.value == "ENDSEC" || pair.value == "EOF") {
                if pair.value == "ENDSEC" { index += 1 }
                break
            }
            index += 1
        }
    }

    private static func parseHeader(
        pairs: [DXFPair],
        index: inout Int,
        insunitsRaw: inout Int?
    ) {
        var currentVar: String? = nil
        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0 && (pair.value == "ENDSEC" || pair.value == "EOF") {
                if pair.value == "ENDSEC" { index += 1 }
                break
            }

            if pair.code == 9 {
                currentVar = pair.value.uppercased()
            } else if pair.code == 70 && currentVar == "$INSUNITS" {
                insunitsRaw = Int(pair.value)
            }
            index += 1
        }
    }

    private static func parseTables(
        pairs: [DXFPair],
        index: inout Int,
        layersDict: inout [String: DXFLayer]
    ) {
        var inLayerTable = false

        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0 && (pair.value == "ENDSEC" || pair.value == "EOF") {
                if pair.value == "ENDSEC" { index += 1 }
                break
            }

            if pair.code == 0 && pair.value == "TABLE" {
                index += 1
                if index < pairs.count && pairs[index].code == 2 {
                    inLayerTable = (pairs[index].value.uppercased() == "LAYER")
                    index += 1
                }
                continue
            }

            if pair.code == 0 && pair.value == "ENDTAB" {
                inLayerTable = false
                index += 1
                continue
            }

            if inLayerTable && pair.code == 0 && pair.value == "LAYER" {
                index += 1
                var name = ""
                var color = 7
                var lineType = "CONTINUOUS"
                var isFrozen = false
                var isLocked = false

                while index < pairs.count {
                    let p = pairs[index]
                    if p.code == 0 { break }
                    switch p.code {
                    case 2:
                        name = p.value
                    case 62:
                        color = Int(p.value) ?? 7
                    case 6:
                        lineType = p.value
                    case 70:
                        let flags = Int(p.value) ?? 0
                        isFrozen = (flags & 1) != 0
                        isLocked = (flags & 4) != 0
                    default:
                        break
                    }
                    index += 1
                }

                if !name.isEmpty {
                    let key = name.uppercased()
                    layersDict[key] = DXFLayer(
                        name: name,
                        color: color,
                        lineType: lineType,
                        isFrozen: isFrozen,
                        isLocked: isLocked
                    )
                }
                continue
            }

            index += 1
        }
    }

    private static func parseEntities(
        pairs: [DXFPair],
        index: inout Int,
        insunitsRaw: Int?,
        layersDict: inout [String: DXFLayer],
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        let effectiveScale = computeEffectiveScale(insunitsRaw: insunitsRaw, options: options)

        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0 && (pair.value == "ENDSEC" || pair.value == "EOF") {
                if pair.value == "ENDSEC" { index += 1 }
                break
            }

            if pair.code == 0 {
                let entityType = pair.value.uppercased()
                index += 1

                // Collect pairs belonging to this entity
                var entityPairs: [DXFPair] = []
                while index < pairs.count && pairs[index].code != 0 {
                    entityPairs.append(pairs[index])
                    index += 1
                }

                if entityType == "POLYLINE" {
                    // Collect following VERTEX entities until SEQEND
                    var vertexEntities: [[DXFPair]] = []
                    while index < pairs.count {
                        let nextCode = pairs[index].code
                        let nextVal = pairs[index].value.uppercased()
                        if nextCode == 0 {
                            if nextVal == "VERTEX" {
                                index += 1
                                var vPairs: [DXFPair] = []
                                while index < pairs.count && pairs[index].code != 0 {
                                    vPairs.append(pairs[index])
                                    index += 1
                                }
                                vertexEntities.append(vPairs)
                                continue
                            } else if nextVal == "SEQEND" {
                                index += 1
                                while index < pairs.count && pairs[index].code != 0 {
                                    index += 1
                                }
                                break
                            } else {
                                break
                            }
                        } else {
                            index += 1
                        }
                    }

                    parsePolyline(
                        headerPairs: entityPairs,
                        vertexEntities: vertexEntities,
                        effectiveScale: effectiveScale,
                        layersDict: &layersDict,
                        options: options,
                        entities: &entities
                    )
                    continue
                }

                convertEntity(
                    type: entityType,
                    pairs: entityPairs,
                    effectiveScale: effectiveScale,
                    layersDict: &layersDict,
                    options: options,
                    entities: &entities
                )
                continue
            }

            index += 1
        }
    }

    // MARK: - Scale & Layer Helpers

    public static func mapINSUNITSToLengthUnit(_ insunits: Int?) -> LengthUnit? {
        guard let insunits else { return nil }
        switch insunits {
        case 1: return .inches
        case 2: return .feet
        case 4: return .millimeters
        case 5: return .centimeters
        case 6: return .meters
        default: return nil
        }
    }

    private static func computeEffectiveScale(
        insunitsRaw: Int?,
        options: DXFImportOptions
    ) -> Double {
        let baseUnitScale: Double
        if let override = options.unitOverride {
            baseUnitScale = override.toMillimeters(1.0)
        } else if let raw = insunitsRaw {
            switch raw {
            case 1: baseUnitScale = 25.4      // Inches
            case 2: baseUnitScale = 304.8     // Feet
            case 4: baseUnitScale = 1.0       // Millimeters
            case 5: baseUnitScale = 10.0      // Centimeters
            case 6: baseUnitScale = 1000.0    // Meters
            case 14: baseUnitScale = 100.0    // Decimeters
            default: baseUnitScale = 1.0      // Unspecified
            }
        } else {
            baseUnitScale = 1.0
        }
        return baseUnitScale * options.scale
    }

    private static func isLayerIncluded(
        layer: String,
        options: DXFImportOptions
    ) -> Bool {
        guard let filter = options.layerFilter else { return true }
        return filter.contains { $0.caseInsensitiveCompare(layer) == .orderedSame }
    }

    private static func isConstructionEntity(
        layer: String,
        lineType: String?,
        options: DXFImportOptions
    ) -> Bool {
        if options.markAllConstruction { return true }
        if options.constructionLayers.contains(where: { $0.caseInsensitiveCompare(layer) == .orderedSame }) {
            return true
        }
        if let lt = lineType, options.constructionLinetypes.contains(where: { $0.caseInsensitiveCompare(lt) == .orderedSame }) {
            return true
        }
        return false
    }

    private static func transformPoint(
        _ pt: SIMD2<Double>,
        effectiveScale: Double,
        offset: SIMD2<Double>
    ) -> SIMD2<Double> {
        SIMD2<Double>(
            pt.x * effectiveScale + offset.x,
            pt.y * effectiveScale + offset.y
        )
    }

    // MARK: - Entity Converters

    private static func convertEntity(
        type: String,
        pairs: [DXFPair],
        effectiveScale: Double,
        layersDict: inout [String: DXFLayer],
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var layer = "0"
        var lineType: String? = nil

        for pair in pairs {
            if pair.code == 8 {
                layer = pair.value
            } else if pair.code == 6 {
                lineType = pair.value
            }
        }

        // Auto-register discovered layers
        let layerKey = layer.uppercased()
        if layersDict[layerKey] == nil {
            layersDict[layerKey] = DXFLayer(name: layer, lineType: lineType ?? "CONTINUOUS")
        }

        guard isLayerIncluded(layer: layer, options: options) else { return }
        let effectiveLineType = lineType ?? layersDict[layerKey]?.lineType
        let isConstruction = isConstructionEntity(layer: layer, lineType: effectiveLineType, options: options)

        switch type {
        case "LINE":
            convertLine(pairs: pairs, effectiveScale: effectiveScale, isConstruction: isConstruction, options: options, entities: &entities)
        case "CIRCLE":
            convertCircle(pairs: pairs, effectiveScale: effectiveScale, isConstruction: isConstruction, options: options, entities: &entities)
        case "ARC":
            convertArc(pairs: pairs, effectiveScale: effectiveScale, isConstruction: isConstruction, options: options, entities: &entities)
        case "ELLIPSE":
            convertEllipse(pairs: pairs, effectiveScale: effectiveScale, isConstruction: isConstruction, options: options, entities: &entities)
        case "LWPOLYLINE":
            convertLWPolyline(pairs: pairs, effectiveScale: effectiveScale, isConstruction: isConstruction, options: options, entities: &entities)
        case "POINT":
            convertPoint(pairs: pairs, effectiveScale: effectiveScale, isConstruction: isConstruction, options: options, entities: &entities)
        case "TEXT", "MTEXT":
            convertText(pairs: pairs, effectiveScale: effectiveScale, isConstruction: isConstruction, options: options, entities: &entities)
        case "SPLINE":
            convertSpline(pairs: pairs, effectiveScale: effectiveScale, isConstruction: isConstruction, options: options, entities: &entities)
        default:
            break
        }
    }

    // LINE
    private static func convertLine(
        pairs: [DXFPair],
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var startX = 0.0, startY = 0.0
        var endX = 0.0, endY = 0.0

        for pair in pairs {
            switch pair.code {
            case 10: startX = Double(pair.value) ?? 0.0
            case 20: startY = Double(pair.value) ?? 0.0
            case 11: endX = Double(pair.value) ?? 0.0
            case 21: endY = Double(pair.value) ?? 0.0
            default: break
            }
        }

        let s = transformPoint(SIMD2(startX, startY), effectiveScale: effectiveScale, offset: options.offset)
        let e = transformPoint(SIMD2(endX, endY), effectiveScale: effectiveScale, offset: options.offset)

        if simd_distance(s, e) >= options.tolerance {
            entities.append(SketchEntity.line(start: s, end: e, isConstruction: isConstruction))
        }
    }

    // CIRCLE
    private static func convertCircle(
        pairs: [DXFPair],
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var cx = 0.0, cy = 0.0
        var radius = 0.0

        for pair in pairs {
            switch pair.code {
            case 10: cx = Double(pair.value) ?? 0.0
            case 20: cy = Double(pair.value) ?? 0.0
            case 40: radius = Double(pair.value) ?? 0.0
            default: break
            }
        }

        let c = transformPoint(SIMD2(cx, cy), effectiveScale: effectiveScale, offset: options.offset)
        let r = radius * effectiveScale

        if r >= options.tolerance {
            entities.append(SketchEntity.circle(center: c, radius: r, isConstruction: isConstruction))
        }
    }

    // ARC
    private static func convertArc(
        pairs: [DXFPair],
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var cx = 0.0, cy = 0.0
        var radius = 0.0
        var startDeg = 0.0
        var endDeg = 0.0

        for pair in pairs {
            switch pair.code {
            case 10: cx = Double(pair.value) ?? 0.0
            case 20: cy = Double(pair.value) ?? 0.0
            case 40: radius = Double(pair.value) ?? 0.0
            case 50: startDeg = Double(pair.value) ?? 0.0
            case 51: endDeg = Double(pair.value) ?? 0.0
            default: break
            }
        }

        let c = transformPoint(SIMD2(cx, cy), effectiveScale: effectiveScale, offset: options.offset)
        let r = radius * effectiveScale

        guard r >= options.tolerance else { return }

        let startRad = startDeg * .pi / 180.0
        let endRad = endDeg * .pi / 180.0

        let s = SIMD2<Double>(c.x + r * cos(startRad), c.y + r * sin(startRad))
        let e = SIMD2<Double>(c.x + r * cos(endRad), c.y + r * sin(endRad))

        entities.append(SketchEntity.arc(
            start: s,
            end: e,
            center: c,
            clockwise: false,
            isConstruction: isConstruction
        ))
    }

    // ELLIPSE
    private static func convertEllipse(
        pairs: [DXFPair],
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var cx = 0.0, cy = 0.0
        var majorVecX = 1.0, majorVecY = 0.0
        var ratio = 1.0
        var startParam = 0.0
        var endParam = 2.0 * .pi

        for pair in pairs {
            switch pair.code {
            case 10: cx = Double(pair.value) ?? 0.0
            case 20: cy = Double(pair.value) ?? 0.0
            case 11: majorVecX = Double(pair.value) ?? 1.0
            case 21: majorVecY = Double(pair.value) ?? 0.0
            case 40: ratio = Double(pair.value) ?? 1.0
            case 41: startParam = Double(pair.value) ?? 0.0
            case 42: endParam = Double(pair.value) ?? (2.0 * .pi)
            default: break
            }
        }

        let c = transformPoint(SIMD2(cx, cy), effectiveScale: effectiveScale, offset: options.offset)
        let majorLen = hypot(majorVecX, majorVecY) * effectiveScale
        let minorLen = majorLen * max(1e-6, min(1.0, ratio))
        let rotation = atan2(majorVecY, majorVecX)

        guard majorLen >= options.tolerance && minorLen >= options.tolerance else { return }

        let sweep = abs(endParam - startParam)
        if sweep >= (2.0 * .pi - 1e-4) {
            entities.append(SketchEntity.ellipse(
                center: c,
                radiusX: majorLen,
                radiusY: minorLen,
                rotation: rotation,
                isConstruction: isConstruction
            ))
        } else {
            entities.append(SketchEntity.ellipticalArc(
                center: c,
                radiusX: majorLen,
                radiusY: minorLen,
                rotation: rotation,
                startAngle: startParam,
                endAngle: endParam,
                clockwise: false,
                isConstruction: isConstruction
            ))
        }
    }

    // LWPOLYLINE
    private static func convertLWPolyline(
        pairs: [DXFPair],
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var flags = 0
        var vertices: [PolyVertex] = []
        var currentVertex: PolyVertex? = nil

        for pair in pairs {
            switch pair.code {
            case 70:
                flags = Int(pair.value) ?? 0
            case 10:
                if let v = currentVertex {
                    vertices.append(v)
                }
                currentVertex = PolyVertex(pt: SIMD2(Double(pair.value) ?? 0.0, 0.0), bulge: 0.0)
            case 20:
                currentVertex?.pt.y = Double(pair.value) ?? 0.0
            case 42:
                currentVertex?.bulge = Double(pair.value) ?? 0.0
            default:
                break
            }
        }
        if let v = currentVertex {
            vertices.append(v)
        }

        guard vertices.count >= 2 else { return }
        let isClosed = (flags & 1) != 0

        emitPolylineSegments(
            vertices: vertices,
            isClosed: isClosed,
            effectiveScale: effectiveScale,
            isConstruction: isConstruction,
            options: options,
            entities: &entities
        )
    }

    // POLYLINE & VERTEX
    private static func parsePolyline(
        headerPairs: [DXFPair],
        vertexEntities: [[DXFPair]],
        effectiveScale: Double,
        layersDict: inout [String: DXFLayer],
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var layer = "0"
        var lineType: String? = nil
        var flags = 0

        for pair in headerPairs {
            switch pair.code {
            case 8: layer = pair.value
            case 6: lineType = pair.value
            case 70: flags = Int(pair.value) ?? 0
            default: break
            }
        }

        let layerKey = layer.uppercased()
        if layersDict[layerKey] == nil {
            layersDict[layerKey] = DXFLayer(name: layer, lineType: lineType ?? "CONTINUOUS")
        }

        guard isLayerIncluded(layer: layer, options: options) else { return }
        let effectiveLineType = lineType ?? layersDict[layerKey]?.lineType
        let isConstruction = isConstructionEntity(layer: layer, lineType: effectiveLineType, options: options)

        var vertices: [PolyVertex] = []
        for vPairs in vertexEntities {
            var x = 0.0, y = 0.0, bulge = 0.0
            for p in vPairs {
                switch p.code {
                case 10: x = Double(p.value) ?? 0.0
                case 20: y = Double(p.value) ?? 0.0
                case 42: bulge = Double(p.value) ?? 0.0
                default: break
                }
            }
            vertices.append(PolyVertex(pt: SIMD2(x, y), bulge: bulge))
        }

        guard vertices.count >= 2 else { return }
        let isClosed = (flags & 1) != 0

        emitPolylineSegments(
            vertices: vertices,
            isClosed: isClosed,
            effectiveScale: effectiveScale,
            isConstruction: isConstruction,
            options: options,
            entities: &entities
        )
    }

    private static func emitPolylineSegments(
        vertices: [PolyVertex],
        isClosed: Bool,
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        let count = vertices.count
        for i in 0..<(count - 1) {
            if let entity = createSegment(
                from: vertices[i].pt,
                to: vertices[i + 1].pt,
                bulge: vertices[i].bulge,
                effectiveScale: effectiveScale,
                isConstruction: isConstruction,
                options: options
            ) {
                entities.append(entity)
            }
        }

        if isClosed {
            if let entity = createSegment(
                from: vertices[count - 1].pt,
                to: vertices[0].pt,
                bulge: vertices[count - 1].bulge,
                effectiveScale: effectiveScale,
                isConstruction: isConstruction,
                options: options
            ) {
                entities.append(entity)
            }
        }
    }

    private static func createSegment(
        from p1Raw: SIMD2<Double>,
        to p2Raw: SIMD2<Double>,
        bulge: Double,
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions
    ) -> SketchEntity? {
        let p1 = transformPoint(p1Raw, effectiveScale: effectiveScale, offset: options.offset)
        let p2 = transformPoint(p2Raw, effectiveScale: effectiveScale, offset: options.offset)

        let chord = p2 - p1
        let d = simd_length(chord)
        guard d >= options.tolerance else { return nil }

        if abs(bulge) < 1e-6 {
            return SketchEntity.line(start: p1, end: p2, isConstruction: isConstruction)
        }

        let b = bulge
        let b2 = b * b
        let r = (d * (1.0 + b2)) / (4.0 * abs(b))
        guard r >= options.tolerance && r.isFinite else {
            return SketchEntity.line(start: p1, end: p2, isConstruction: isConstruction)
        }

        let m = (p1 + p2) * 0.5
        let normal = SIMD2<Double>(-chord.y / d, chord.x / d)
        let h = (d * (1.0 - b2)) / (4.0 * abs(b))
        let center = m + (b > 0 ? 1.0 : -1.0) * h * normal

        guard center.x.isFinite && center.y.isFinite else {
            return SketchEntity.line(start: p1, end: p2, isConstruction: isConstruction)
        }

        return SketchEntity.arc(
            start: p1,
            end: p2,
            center: center,
            clockwise: b < 0.0,
            isConstruction: isConstruction
        )
    }

    // POINT
    private static func convertPoint(
        pairs: [DXFPair],
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var x = 0.0, y = 0.0
        for pair in pairs {
            switch pair.code {
            case 10: x = Double(pair.value) ?? 0.0
            case 20: y = Double(pair.value) ?? 0.0
            default: break
            }
        }
        let pt = transformPoint(SIMD2(x, y), effectiveScale: effectiveScale, offset: options.offset)
        entities.append(SketchEntity.point(position: pt, isConstruction: isConstruction))
    }

    // TEXT & MTEXT
    private static func convertText(
        pairs: [DXFPair],
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var x = 0.0, y = 0.0
        var height = 2.5
        var textFragments: [String] = []

        for pair in pairs {
            switch pair.code {
            case 10: x = Double(pair.value) ?? 0.0
            case 20: y = Double(pair.value) ?? 0.0
            case 40: height = Double(pair.value) ?? 2.5
            case 1, 3: textFragments.append(pair.value)
            default: break
            }
        }

        let fullRaw = textFragments.joined()
        let cleaned = cleanMText(fullRaw)
        guard !cleaned.isEmpty else { return }

        let origin = transformPoint(SIMD2(x, y), effectiveScale: effectiveScale, offset: options.offset)
        let fontSize = max(1.0, height * effectiveScale)

        entities.append(SketchEntity.text(
            text: cleaned,
            origin: origin,
            fontSize: fontSize,
            isConstruction: isConstruction
        ))
    }

    private static func cleanMText(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\\P", with: "\n")
        if let regex = try? NSRegularExpression(pattern: "\\\\[A-Za-z0-9]+;?", options: []) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.replacingOccurrences(of: "\\{", with: "{")
            .replacingOccurrences(of: "\\}", with: "}")
            .replacingOccurrences(of: "\\\\", with: "\\")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // SPLINE
    private static func convertSpline(
        pairs: [DXFPair],
        effectiveScale: Double,
        isConstruction: Bool,
        options: DXFImportOptions,
        entities: inout [SketchEntity]
    ) {
        var degree = 3
        var knots: [Double] = []
        var controlPoints: [SIMD2<Double>] = []
        var fitPoints: [SIMD2<Double>] = []

        var currentCp: SIMD2<Double>? = nil
        var currentFp: SIMD2<Double>? = nil

        for pair in pairs {
            switch pair.code {
            case 71:
                degree = Int(pair.value) ?? 3
            case 40:
                if let k = Double(pair.value) {
                    knots.append(k)
                }
            case 10:
                if let cp = currentCp {
                    controlPoints.append(cp)
                }
                currentCp = SIMD2(Double(pair.value) ?? 0.0, 0.0)
            case 20:
                currentCp?.ptY(Double(pair.value) ?? 0.0)
            case 11:
                if let fp = currentFp {
                    fitPoints.append(fp)
                }
                currentFp = SIMD2(Double(pair.value) ?? 0.0, 0.0)
            case 21:
                currentFp?.ptY(Double(pair.value) ?? 0.0)
            default:
                break
            }
        }
        if let cp = currentCp {
            controlPoints.append(cp)
        }
        if let fp = currentFp {
            fitPoints.append(fp)
        }

        let n = controlPoints.count
        let p = max(1, degree)
        let m = knots.count

        // Check if knot vector and control points can evaluate B-spline via de Boor
        if n >= p + 1 && m >= n + p + 1 {
            let uMin = knots[p]
            let uMax = knots[n]
            if uMax > uMin + 1e-9 {
                let intervals = max(4, options.splineIntervals)
                var sampledPoints: [SIMD2<Double>] = []
                sampledPoints.reserveCapacity(intervals + 1)

                for step in 0...intervals {
                    let t = uMin + (uMax - uMin) * (Double(step) / Double(intervals))
                    let pt = evaluateDeBoor(degree: p, knots: knots, controlPoints: controlPoints, t: t)
                    let transformed = transformPoint(pt, effectiveScale: effectiveScale, offset: options.offset)
                    sampledPoints.append(transformed)
                }

                for i in 0..<(sampledPoints.count - 1) {
                    let s = sampledPoints[i]
                    let e = sampledPoints[i + 1]
                    if simd_distance(s, e) >= options.tolerance {
                        entities.append(SketchEntity.line(start: s, end: e, isConstruction: isConstruction))
                    }
                }
                return
            }
        }

        // Fallback 1: Interpolate fit points if available
        if fitPoints.count >= 2 {
            for i in 0..<(fitPoints.count - 1) {
                let s = transformPoint(fitPoints[i], effectiveScale: effectiveScale, offset: options.offset)
                let e = transformPoint(fitPoints[i + 1], effectiveScale: effectiveScale, offset: options.offset)
                if simd_distance(s, e) >= options.tolerance {
                    entities.append(SketchEntity.line(start: s, end: e, isConstruction: isConstruction))
                }
            }
            return
        }

        // Fallback 2: Connect control points directly
        if controlPoints.count >= 2 {
            for i in 0..<(controlPoints.count - 1) {
                let s = transformPoint(controlPoints[i], effectiveScale: effectiveScale, offset: options.offset)
                let e = transformPoint(controlPoints[i + 1], effectiveScale: effectiveScale, offset: options.offset)
                if simd_distance(s, e) >= options.tolerance {
                    entities.append(SketchEntity.line(start: s, end: e, isConstruction: isConstruction))
                }
            }
        }
    }

    /// Evaluates a 2D B-spline at parameter `t` using de Boor's algorithm.
    private static func evaluateDeBoor(
        degree p: Int,
        knots: [Double],
        controlPoints: [SIMD2<Double>],
        t: Double
    ) -> SIMD2<Double> {
        let n = controlPoints.count - 1
        var k = p
        while k < n && knots[k + 1] <= t {
            k += 1
        }

        var d = Array(controlPoints[(k - p)...k])

        for r in 1...p {
            for j in stride(from: p, through: r, by: -1) {
                let i = k - p + j
                let denom = knots[i + p + 1 - r] - knots[i]
                let alpha = denom > 1e-12 ? (t - knots[i]) / denom : 0.0
                d[j] = (1.0 - alpha) * d[j - 1] + alpha * d[j]
            }
        }

        return d[p]
    }

    // MARK: - Endpoint Welding

    private struct EndpointRef {
        var entityIndex: Int
        var isStart: Bool
        var pos: SIMD2<Double>
    }

    private static func weldEndpoints(
        in entities: inout [SketchEntity],
        constraints: inout [SketchConstraint],
        tolerance: Double
    ) {
        var endpoints: [EndpointRef] = []
        endpoints.reserveCapacity(entities.count * 2)

        for (idx, entity) in entities.enumerated() {
            if let sp = entity.startPoint {
                endpoints.append(EndpointRef(entityIndex: idx, isStart: true, pos: sp))
            }
            if let ep = entity.endPoint {
                endpoints.append(EndpointRef(entityIndex: idx, isStart: false, pos: ep))
            }
        }

        guard endpoints.count >= 2 else { return }

        // Disjoint-set union to find connected clusters within tolerance
        var parent = Array(0..<endpoints.count)
        func find(_ i: Int) -> Int {
            var curr = i
            while curr != parent[curr] {
                parent[curr] = parent[parent[curr]]
                curr = parent[curr]
            }
            return curr
        }
        func union(_ i: Int, _ j: Int) {
            let rootI = find(i)
            let rootJ = find(j)
            if rootI != rootJ {
                parent[rootJ] = rootI
            }
        }

        let tolSq = tolerance * tolerance
        for i in 0..<endpoints.count {
            for j in (i + 1)..<endpoints.count {
                let d = endpoints[i].pos - endpoints[j].pos
                if (d.x * d.x + d.y * d.y) <= tolSq {
                    union(i, j)
                }
            }
        }

        // Group into clusters
        var clusters: [Int: [Int]] = [:]
        for i in 0..<endpoints.count {
            let root = find(i)
            clusters[root, default: []].append(i)
        }

        var seenConstraintPairs: Set<String> = []

        for (_, indices) in clusters where indices.count > 1 {
            // Compute cluster centroid
            var sum = SIMD2<Double>.zero
            for idx in indices {
                sum += endpoints[idx].pos
            }
            let centroid = sum / Double(indices.count)

            // Snap endpoints to centroid
            for idx in indices {
                let ref = endpoints[idx]
                if ref.isStart {
                    entities[ref.entityIndex].startPoint = centroid
                } else {
                    entities[ref.entityIndex].endPoint = centroid
                }
            }

            // Generate coincident constraints between distinct entities
            let entityIndicesInCluster = Array(Set(indices.map { endpoints[$0].entityIndex }))
            guard entityIndicesInCluster.count >= 2 else { continue }

            for k in 0..<(entityIndicesInCluster.count - 1) {
                let e1 = entities[entityIndicesInCluster[k]]
                let e2 = entities[entityIndicesInCluster[k + 1]]
                let pairKey = e1.id < e2.id ? "\(e1.id)-\(e2.id)" : "\(e2.id)-\(e1.id)"
                if !seenConstraintPairs.contains(pairKey) {
                    seenConstraintPairs.insert(pairKey)
                    constraints.append(SketchConstraint(
                        kind: .coincident,
                        entityIds: [e1.id, e2.id]
                    ))
                }
            }
        }
    }
}

private extension SIMD2 where Scalar == Double {
    mutating func ptY(_ val: Double) {
        self.y = val
    }
}
