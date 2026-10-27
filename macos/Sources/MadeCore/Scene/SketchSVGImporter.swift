import Foundation
import simd

/// Options configuring Scalable Vector Graphics (SVG) parsing and sketch entity generation.
public struct SVGImportOptions: Sendable, Equatable {
    /// Optional length unit override superseding SVG document units.
    public var unitOverride: LengthUnit?
    /// Additional uniform scale factor applied to all coordinates and dimensions.
    public var scale: Double
    /// Translation offset in millimeters applied after scaling.
    public var offset: SIMD2<Double>
    /// Dots per inch used when converting unitless or px dimensions to millimeters (default 96.0).
    public var dpi: Double
    /// When true, inverts the Y-axis so SVG top-left origin matches CAD sketch plane conventions.
    public var invertY: Bool
    /// Optional layer filter. When non-nil, only elements in matching groups or layers are imported.
    public var layerFilter: Set<String>?
    /// Layer names designated as construction geometry (case-insensitive).
    public var constructionLayers: Set<String>
    /// When true, forces all imported entities to have `isConstruction == true`.
    public var markAllConstruction: Bool
    /// When true, snaps nearby endpoints and generates coincident constraints.
    public var weldEndpoints: Bool
    /// Maximum distance in millimeters between endpoints to consider them coincident.
    public var weldTolerance: Double
    /// Number of piecewise linear segments used to discretize Bézier curves and ellipses.
    public var curveIntervals: Int
    /// Minimum geometry threshold below which degenerate entities are skipped.
    public var tolerance: Double

    public init(
        unitOverride: LengthUnit? = nil,
        scale: Double = 1.0,
        offset: SIMD2<Double> = .zero,
        dpi: Double = 96.0,
        invertY: Bool = true,
        layerFilter: Set<String>? = nil,
        constructionLayers: Set<String> = ["CONSTRUCTION", "CENTER", "HIDDEN", "DEFPOINTS"],
        markAllConstruction: Bool = false,
        weldEndpoints: Bool = true,
        weldTolerance: Double = 1e-3,
        curveIntervals: Int = 32,
        tolerance: Double = 1e-6
    ) {
        self.unitOverride = unitOverride
        self.scale = scale
        self.offset = offset
        self.dpi = dpi
        self.invertY = invertY
        self.layerFilter = layerFilter
        self.constructionLayers = constructionLayers
        self.markAllConstruction = markAllConstruction
        self.weldEndpoints = weldEndpoints
        self.weldTolerance = weldTolerance
        self.curveIntervals = curveIntervals
        self.tolerance = tolerance
    }
}

/// Parsed SVG document container containing metadata, entities, and constraints.
public struct SVGDocument: Sendable {
    public var entities: [SketchEntity]
    public var constraints: [SketchConstraint]
    public var viewBox: SIMD4<Double>?
    public var width: Double?
    public var height: Double?
    public var layers: [String]

    public init(
        entities: [SketchEntity] = [],
        constraints: [SketchConstraint] = [],
        viewBox: SIMD4<Double>? = nil,
        width: Double? = nil,
        height: Double? = nil,
        layers: [String] = []
    ) {
        self.entities = entities
        self.constraints = constraints
        self.viewBox = viewBox
        self.width = width
        self.height = height
        self.layers = layers
    }
}

public typealias SVGParseResult = SVGDocument

/// Pure-Swift SVG importer parsing XML elements and path geometry into 2D sketch entities (BL-SKT-14, #362).
public enum SketchSVGImporter {

    /// Imports SVG XML text and returns an `SVGDocument` containing entities and constraints.
    public static func importSVG(
        svgText: String,
        options: SVGImportOptions = SVGImportOptions()
    ) throws -> SVGDocument {
        try parseSVG(svgText: svgText, options: options)
    }

    /// Parses SVG text into sketch entities with options.
    public static func parseSVG(
        svgText: String,
        options: SVGImportOptions = SVGImportOptions()
    ) throws -> SVGDocument {
        guard let data = svgText.data(using: .utf8), !data.isEmpty else {
            throw SketchError.emptySketch
        }

        let parserDelegate = SVGXMLParserDelegate(options: options)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parserDelegate
        xmlParser.shouldProcessNamespaces = false
        xmlParser.shouldReportNamespacePrefixes = false
        xmlParser.shouldResolveExternalEntities = false

        let success = xmlParser.parse()
        if !success, let parserError = xmlParser.parserError {
            // If some entities were parsed before a minor syntax glitch, accept them; otherwise throw
            if parserDelegate.entities.isEmpty {
                throw SketchError.invalidEntity("SVG parse failed: \(parserError.localizedDescription)")
            }
        }

        var entities = parserDelegate.entities
        var constraints: [SketchConstraint] = []

        if options.weldEndpoints {
            weldEndpoints(in: &entities, constraints: &constraints, tolerance: options.weldTolerance)
        }

        return SVGDocument(
            entities: entities,
            constraints: constraints,
            viewBox: parserDelegate.viewBox,
            width: parserDelegate.docWidth,
            height: parserDelegate.docHeight,
            layers: Array(parserDelegate.discoveredLayers).sorted()
        )
    }

    // MARK: - Endpoint Welding

    private struct EndpointRef {
        let entityIndex: Int
        let isStart: Bool
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

        // Disjoint-set union
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

        var clusters: [Int: [Int]] = [:]
        for i in 0..<endpoints.count {
            let root = find(i)
            clusters[root, default: []].append(i)
        }

        var seenConstraintPairs: Set<String> = []

        for (_, indices) in clusters where indices.count > 1 {
            var sum = SIMD2<Double>.zero
            for idx in indices {
                sum += endpoints[idx].pos
            }
            let centroid = sum / Double(indices.count)

            for idx in indices {
                let ref = endpoints[idx]
                if ref.isStart {
                    entities[ref.entityIndex].startPoint = centroid
                } else {
                    entities[ref.entityIndex].endPoint = centroid
                }
            }

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

// MARK: - 2D Affine Transform

struct SVGTransform2D: Sendable, Equatable {
    var a: Double = 1.0
    var b: Double = 0.0
    var c: Double = 0.0
    var d: Double = 1.0
    var e: Double = 0.0
    var f: Double = 0.0

    static let identity = SVGTransform2D()

    func applying(to p: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2<Double>(
            a * p.x + c * p.y + e,
            b * p.x + d * p.y + f
        )
    }

    /// Concatenates `other` into `self` (such that `other` is applied first, then `self`).
    func concatenating(_ other: SVGTransform2D) -> SVGTransform2D {
        SVGTransform2D(
            a: self.a * other.a + self.c * other.b,
            b: self.b * other.a + self.d * other.b,
            c: self.a * other.c + self.c * other.d,
            d: self.b * other.c + self.d * other.d,
            e: self.a * other.e + self.c * other.f + self.e,
            f: self.b * other.e + self.d * other.f + self.f
        )
    }

    static func translation(tx: Double, ty: Double) -> SVGTransform2D {
        SVGTransform2D(a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: tx, f: ty)
    }

    static func scaling(sx: Double, sy: Double) -> SVGTransform2D {
        SVGTransform2D(a: sx, b: 0.0, c: 0.0, d: sy, e: 0.0, f: 0.0)
    }

    static func rotation(radians: Double, cx: Double = 0.0, cy: Double = 0.0) -> SVGTransform2D {
        let cosA = cos(radians)
        let sinA = sin(radians)
        if abs(cx) < 1e-12 && abs(cy) < 1e-12 {
            return SVGTransform2D(a: cosA, b: sinA, c: -sinA, d: cosA, e: 0.0, f: 0.0)
        }
        // translate(cx, cy) * rotate(rad) * translate(-cx, -cy)
        return SVGTransform2D(
            a: cosA,
            b: sinA,
            c: -sinA,
            d: cosA,
            e: cx - cx * cosA + cy * sinA,
            f: cy - cx * sinA - cy * cosA
        )
    }

    static func parse(_ transformString: String) -> SVGTransform2D {
        var result = SVGTransform2D.identity
        let pattern = #"([a-zA-Z]+)\s*\(([^)]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }

        let nsString = transformString as NSString
        let matches = regex.matches(in: transformString, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let name = nsString.substring(with: match.range(at: 1)).lowercased()
            let rawArgs = nsString.substring(with: match.range(at: 2))
            let args = parseNumberList(rawArgs)

            var t = SVGTransform2D.identity
            switch name {
            case "translate":
                if args.count >= 2 {
                    t = .translation(tx: args[0], ty: args[1])
                } else if args.count == 1 {
                    t = .translation(tx: args[0], ty: 0.0)
                }
            case "scale":
                if args.count >= 2 {
                    t = .scaling(sx: args[0], sy: args[1])
                } else if args.count == 1 {
                    t = .scaling(sx: args[0], sy: args[0])
                }
            case "rotate":
                if args.count >= 3 {
                    let rad = args[0] * .pi / 180.0
                    t = .rotation(radians: rad, cx: args[1], cy: args[2])
                } else if args.count >= 1 {
                    let rad = args[0] * .pi / 180.0
                    t = .rotation(radians: rad)
                }
            case "matrix":
                if args.count >= 6 {
                    t = SVGTransform2D(a: args[0], b: args[1], c: args[2], d: args[3], e: args[4], f: args[5])
                }
            default:
                break
            }
            result = result.concatenating(t)
        }

        return result
    }

    static func parseNumberList(_ text: String) -> [Double] {
        let scanner = SVGPathScanner(text)
        var numbers: [Double] = []
        while let n = scanner.readNumber() {
            numbers.append(n)
        }
        return numbers
    }
}

// MARK: - XML Parser Delegate

private final class SVGXMLParserDelegate: NSObject, XMLParserDelegate {
    let options: SVGImportOptions

    var entities: [SketchEntity] = []
    var viewBox: SIMD4<Double>?
    var docWidth: Double?
    var docHeight: Double?
    var discoveredLayers: Set<String> = []

    private var unitScale: Double = 1.0

    private struct GroupContext {
        var transform: SVGTransform2D
        var layerName: String?
        var isConstruction: Bool
        var isHidden: Bool
    }

    private var groupStack: [GroupContext] = []

    init(options: SVGImportOptions) {
        self.options = options
        super.init()
    }

    private var currentContext: GroupContext {
        groupStack.last ?? GroupContext(
            transform: .identity,
            layerName: nil,
            isConstruction: options.markAllConstruction,
            isHidden: false
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let tag = elementName.lowercased()

        // Normalize attribute keys to lowercase
        var attrs: [String: String] = [:]
        for (k, v) in attributeDict {
            attrs[k.lowercased()] = v
        }

        switch tag {
        case "svg":
            handleSVGElement(attrs)

        case "g":
            handleGroupStart(attrs)

        case "line":
            handleLine(attrs)

        case "rect":
            handleRect(attrs)

        case "circle":
            handleCircle(attrs)

        case "ellipse":
            handleEllipse(attrs)

        case "polyline":
            handlePolyline(attrs, isClosed: false)

        case "polygon":
            handlePolyline(attrs, isClosed: true)

        case "path":
            handlePath(attrs)

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let tag = elementName.lowercased()
        if tag == "g" && !groupStack.isEmpty {
            groupStack.removeLast()
        }
    }

    // MARK: - Handlers

    private func handleSVGElement(_ attrs: [String: String]) {
        if let vbStr = attrs["viewbox"] {
            let nums = SVGTransform2D.parseNumberList(vbStr)
            if nums.count >= 4 {
                viewBox = SIMD4<Double>(nums[0], nums[1], nums[2], nums[3])
            }
        }

        if let wStr = attrs["width"], let wVal = parseLength(wStr) {
            docWidth = wVal
        }
        if let hStr = attrs["height"], let hVal = parseLength(hStr) {
            docHeight = hVal
        }

        // Determine effective unit scale to millimeters
        if let unitOverride = options.unitOverride {
            unitScale = unitOverride.toMillimeters(1.0)
        } else if let vb = viewBox, vb.z > 0, let w = docWidth {
            unitScale = w / vb.z
        } else if let vb = viewBox, vb.w > 0, let h = docHeight {
            unitScale = h / vb.w
        } else if docWidth != nil, (viewBox == nil || viewBox?.z == 0) {
            unitScale = 1.0
        } else {
            // Default: SVG px at DPI
            unitScale = 25.4 / options.dpi
        }
    }

    private func handleGroupStart(_ attrs: [String: String]) {
        let parentCtx = currentContext
        var transform = parentCtx.transform

        if let tfStr = attrs["transform"] {
            let localTf = SVGTransform2D.parse(tfStr)
            transform = transform.concatenating(localTf)
        }

        let layerName = attrs["inkscape:label"] ?? attrs["label"] ?? attrs["id"] ?? parentCtx.layerName
        if let ln = layerName {
            discoveredLayers.insert(ln)
        }

        var isConstr = parentCtx.isConstruction || options.markAllConstruction
        if let ln = layerName, options.constructionLayers.contains(ln.uppercased()) {
            isConstr = true
        }
        if hasStrokeDasharray(attrs) {
            isConstr = true
        }

        let isHidden = parentCtx.isHidden || isDisplayNone(attrs)

        groupStack.append(GroupContext(
            transform: transform,
            layerName: layerName,
            isConstruction: isConstr,
            isHidden: isHidden
        ))
    }

    private func elementShouldBeImported(_ attrs: [String: String]) -> (shouldImport: Bool, isConstruction: Bool, transform: SVGTransform2D) {
        let ctx = currentContext
        if ctx.isHidden || isDisplayNone(attrs) {
            return (false, false, .identity)
        }

        let layer = attrs["inkscape:label"] ?? attrs["label"] ?? attrs["id"] ?? ctx.layerName
        if let l = layer {
            discoveredLayers.insert(l)
        }

        if let filter = options.layerFilter {
            if let l = layer {
                if !filter.contains(l) && !filter.contains(l.uppercased()) {
                    return (false, false, .identity)
                }
            } else {
                return (false, false, .identity)
            }
        }

        var isConstr = ctx.isConstruction || options.markAllConstruction
        if let l = layer, options.constructionLayers.contains(l.uppercased()) {
            isConstr = true
        }
        if hasStrokeDasharray(attrs) {
            isConstr = true
        }

        var transform = ctx.transform
        if let tfStr = attrs["transform"] {
            let localTf = SVGTransform2D.parse(tfStr)
            transform = transform.concatenating(localTf)
        }

        return (true, isConstr, transform)
    }

    private func handleLine(_ attrs: [String: String]) {
        let check = elementShouldBeImported(attrs)
        guard check.shouldImport else { return }

        let x1 = parseCoordinate(attrs["x1"])
        let y1 = parseCoordinate(attrs["y1"])
        let x2 = parseCoordinate(attrs["x2"])
        let y2 = parseCoordinate(attrs["y2"])

        let p1 = mapToCAD(SIMD2<Double>(x1, y1), transform: check.transform)
        let p2 = mapToCAD(SIMD2<Double>(x2, y2), transform: check.transform)

        let d = p2 - p1
        if (d.x * d.x + d.y * d.y) >= (options.tolerance * options.tolerance) {
            entities.append(SketchEntity.line(start: p1, end: p2, isConstruction: check.isConstruction))
        }
    }

    private func handleRect(_ attrs: [String: String]) {
        let check = elementShouldBeImported(attrs)
        guard check.shouldImport else { return }

        let x = parseCoordinate(attrs["x"])
        let y = parseCoordinate(attrs["y"])
        guard let w = parseCoordinateOptional(attrs["width"]), w > 0,
              let h = parseCoordinateOptional(attrs["height"]), h > 0 else {
            return
        }

        var rx = parseCoordinateOptional(attrs["rx"]) ?? 0.0
        var ry = parseCoordinateOptional(attrs["ry"]) ?? 0.0
        if rx > 0 && ry <= 0 { ry = rx }
        if ry > 0 && rx <= 0 { rx = ry }
        rx = min(rx, w / 2.0)
        ry = min(ry, h / 2.0)

        if rx <= options.tolerance || ry <= options.tolerance {
            // Sharp rectangle: 4 lines
            let p0 = mapToCAD(SIMD2<Double>(x, y), transform: check.transform)
            let p1 = mapToCAD(SIMD2<Double>(x + w, y), transform: check.transform)
            let p2 = mapToCAD(SIMD2<Double>(x + w, y + h), transform: check.transform)
            let p3 = mapToCAD(SIMD2<Double>(x, y + h), transform: check.transform)

            entities.append(SketchEntity.line(start: p0, end: p1, isConstruction: check.isConstruction))
            entities.append(SketchEntity.line(start: p1, end: p2, isConstruction: check.isConstruction))
            entities.append(SketchEntity.line(start: p2, end: p3, isConstruction: check.isConstruction))
            entities.append(SketchEntity.line(start: p3, end: p0, isConstruction: check.isConstruction))
        } else {
            // Rounded rectangle
            let cTR = SIMD2<Double>(x + w - rx, y + ry)
            let cBR = SIMD2<Double>(x + w - rx, y + h - ry)
            let cBL = SIMD2<Double>(x + rx, y + h - ry)
            let cTL = SIMD2<Double>(x + rx, y + ry)

            // Top line
            if w > 2.0 * rx + options.tolerance {
                let pTopStart = mapToCAD(SIMD2<Double>(x + rx, y), transform: check.transform)
                let pTopEnd = mapToCAD(SIMD2<Double>(x + w - rx, y), transform: check.transform)
                entities.append(SketchEntity.line(start: pTopStart, end: pTopEnd, isConstruction: check.isConstruction))
            }

            // Top-right corner arc
            addQuarterArc(center: cTR, rx: rx, ry: ry, startAngle: -.pi / 2.0, sweepAngle: .pi / 2.0, transform: check.transform, isConstruction: check.isConstruction)

            // Right line
            if h > 2.0 * ry + options.tolerance {
                let pRightStart = mapToCAD(SIMD2<Double>(x + w, y + ry), transform: check.transform)
                let pRightEnd = mapToCAD(SIMD2<Double>(x + w, y + h - ry), transform: check.transform)
                entities.append(SketchEntity.line(start: pRightStart, end: pRightEnd, isConstruction: check.isConstruction))
            }

            // Bottom-right corner arc
            addQuarterArc(center: cBR, rx: rx, ry: ry, startAngle: 0.0, sweepAngle: .pi / 2.0, transform: check.transform, isConstruction: check.isConstruction)

            // Bottom line
            if w > 2.0 * rx + options.tolerance {
                let pBotStart = mapToCAD(SIMD2<Double>(x + w - rx, y + h), transform: check.transform)
                let pBotEnd = mapToCAD(SIMD2<Double>(x + rx, y + h), transform: check.transform)
                entities.append(SketchEntity.line(start: pBotStart, end: pBotEnd, isConstruction: check.isConstruction))
            }

            // Bottom-left corner arc
            addQuarterArc(center: cBL, rx: rx, ry: ry, startAngle: .pi / 2.0, sweepAngle: .pi / 2.0, transform: check.transform, isConstruction: check.isConstruction)

            // Left line
            if h > 2.0 * ry + options.tolerance {
                let pLeftStart = mapToCAD(SIMD2<Double>(x, y + h - ry), transform: check.transform)
                let pLeftEnd = mapToCAD(SIMD2<Double>(x, y + ry), transform: check.transform)
                entities.append(SketchEntity.line(start: pLeftStart, end: pLeftEnd, isConstruction: check.isConstruction))
            }

            // Top-left corner arc
            addQuarterArc(center: cTL, rx: rx, ry: ry, startAngle: .pi, sweepAngle: .pi / 2.0, transform: check.transform, isConstruction: check.isConstruction)
        }
    }

    private func addQuarterArc(
        center: SIMD2<Double>,
        rx: Double,
        ry: Double,
        startAngle: Double,
        sweepAngle: Double,
        transform: SVGTransform2D,
        isConstruction: Bool
    ) {
        if abs(rx - ry) < options.tolerance {
            let pStartSVG = center + SIMD2<Double>(rx * cos(startAngle), ry * sin(startAngle))
            let pEndSVG = center + SIMD2<Double>(rx * cos(startAngle + sweepAngle), ry * sin(startAngle + sweepAngle))
            let pMidSVG = center + SIMD2<Double>(rx * cos(startAngle + sweepAngle * 0.5), ry * sin(startAngle + sweepAngle * 0.5))

            let sCAD = mapToCAD(pStartSVG, transform: transform)
            let eCAD = mapToCAD(pEndSVG, transform: transform)
            let mCAD = mapToCAD(pMidSVG, transform: transform)
            let cCAD = mapToCAD(center, transform: transform)

            let isCW = isClockwiseCAD(start: sCAD, mid: mCAD, end: eCAD, center: cCAD)
            entities.append(SketchEntity.arc(start: sCAD, end: eCAD, center: cCAD, clockwise: isCW, isConstruction: isConstruction))
        } else {
            // Discretize into piecewise lines
            let steps = max(4, options.curveIntervals / 4)
            var prevCAD = mapToCAD(center + SIMD2<Double>(rx * cos(startAngle), ry * sin(startAngle)), transform: transform)
            for i in 1...steps {
                let theta = startAngle + sweepAngle * (Double(i) / Double(steps))
                let currCAD = mapToCAD(center + SIMD2<Double>(rx * cos(theta), ry * sin(theta)), transform: transform)
                entities.append(SketchEntity.line(start: prevCAD, end: currCAD, isConstruction: isConstruction))
                prevCAD = currCAD
            }
        }
    }

    private func handleCircle(_ attrs: [String: String]) {
        let check = elementShouldBeImported(attrs)
        guard check.shouldImport else { return }

        let cx = parseCoordinate(attrs["cx"])
        let cy = parseCoordinate(attrs["cy"])
        guard let r = parseCoordinateOptional(attrs["r"]), r > 0 else { return }

        let centerCAD = mapToCAD(SIMD2<Double>(cx, cy), transform: check.transform)
        let sx = sqrt(check.transform.a * check.transform.a + check.transform.b * check.transform.b)
        let sy = sqrt(check.transform.c * check.transform.c + check.transform.d * check.transform.d)

        if abs(sx - sy) < options.tolerance {
            let rCAD = r * sx * unitScale * options.scale
            entities.append(SketchEntity.circle(center: centerCAD, radius: rCAD, isConstruction: check.isConstruction))
        } else {
            let rxCAD = r * sx * unitScale * options.scale
            let ryCAD = r * sy * unitScale * options.scale
            var rot = atan2(check.transform.b, check.transform.a)
            if options.invertY { rot = -rot }
            entities.append(SketchEntity.ellipse(
                center: centerCAD,
                radiusX: rxCAD,
                radiusY: ryCAD,
                rotation: rot,
                isConstruction: check.isConstruction
            ))
        }
    }

    private func handleEllipse(_ attrs: [String: String]) {
        let check = elementShouldBeImported(attrs)
        guard check.shouldImport else { return }

        let cx = parseCoordinate(attrs["cx"])
        let cy = parseCoordinate(attrs["cy"])
        guard let rx = parseCoordinateOptional(attrs["rx"]), rx > 0,
              let ry = parseCoordinateOptional(attrs["ry"]), ry > 0 else {
            return
        }

        let centerCAD = mapToCAD(SIMD2<Double>(cx, cy), transform: check.transform)
        let sx = sqrt(check.transform.a * check.transform.a + check.transform.b * check.transform.b)
        let sy = sqrt(check.transform.c * check.transform.c + check.transform.d * check.transform.d)
        let rxCAD = rx * sx * unitScale * options.scale
        let ryCAD = ry * sy * unitScale * options.scale

        var rot = atan2(check.transform.b, check.transform.a)
        if options.invertY { rot = -rot }

        entities.append(SketchEntity.ellipse(
            center: centerCAD,
            radiusX: rxCAD,
            radiusY: ryCAD,
            rotation: rot,
            isConstruction: check.isConstruction
        ))
    }

    private func handlePolyline(_ attrs: [String: String], isClosed: Bool) {
        let check = elementShouldBeImported(attrs)
        guard check.shouldImport else { return }
        guard let ptsStr = attrs["points"] else { return }

        let nums = SVGTransform2D.parseNumberList(ptsStr)
        guard nums.count >= 4 else { return }

        var points: [SIMD2<Double>] = []
        points.reserveCapacity(nums.count / 2)
        var i = 0
        while i + 1 < nums.count {
            points.append(mapToCAD(SIMD2<Double>(nums[i], nums[i + 1]), transform: check.transform))
            i += 2
        }

        guard points.count >= 2 else { return }

        for k in 0..<(points.count - 1) {
            let p1 = points[k]
            let p2 = points[k + 1]
            let d = p2 - p1
            if (d.x * d.x + d.y * d.y) >= (options.tolerance * options.tolerance) {
                entities.append(SketchEntity.line(start: p1, end: p2, isConstruction: check.isConstruction))
            }
        }

        if isClosed {
            let pLast = points[points.count - 1]
            let pFirst = points[0]
            let d = pLast - pFirst
            if (d.x * d.x + d.y * d.y) >= (options.tolerance * options.tolerance) {
                entities.append(SketchEntity.line(start: pLast, end: pFirst, isConstruction: check.isConstruction))
            }
        }
    }

    private func handlePath(_ attrs: [String: String]) {
        let check = elementShouldBeImported(attrs)
        guard check.shouldImport else { return }
        guard let d = attrs["d"], !d.isEmpty else { return }

        let parser = SVGPathParser(
            pathString: d,
            transform: check.transform,
            isConstruction: check.isConstruction,
            options: options,
            mapToCAD: { [weak self] pt, tf in
                guard let self else { return pt }
                return self.mapToCAD(pt, transform: tf)
            }
        )
        let pathEntities = parser.parse()
        entities.append(contentsOf: pathEntities)
    }

    // MARK: - Coordinate Mapping

    private func mapToCAD(_ pt: SIMD2<Double>, transform: SVGTransform2D) -> SIMD2<Double> {
        let pXf = transform.applying(to: pt)
        let minX = viewBox?.x ?? 0.0
        let minY = viewBox?.y ?? 0.0
        let vbH = viewBox?.w ?? (docHeight ?? 0.0)

        let xNorm = pXf.x - minX
        let yNorm: Double
        if options.invertY {
            if vbH > 0 {
                yNorm = (minY + vbH) - pXf.y
            } else {
                yNorm = -pXf.y
            }
        } else {
            yNorm = pXf.y - minY
        }

        return SIMD2<Double>(
            xNorm * unitScale * options.scale + options.offset.x,
            yNorm * unitScale * options.scale + options.offset.y
        )
    }

    private func isClockwiseCAD(start: SIMD2<Double>, mid: SIMD2<Double>, end: SIMD2<Double>, center: SIMD2<Double>) -> Bool {
        let aS = atan2(start.y - center.y, start.x - center.x)
        let aE = atan2(end.y - center.y, end.x - center.x)
        let aM = atan2(mid.y - center.y, mid.x - center.x)

        let twoPi = 2.0 * .pi
        func norm(_ a: Double) -> Double {
            var v = a.truncatingRemainder(dividingBy: twoPi)
            if v < 0 { v += twoPi }
            return v
        }

        let deltaCCW = norm(aE - aS)
        let deltaM = norm(aM - aS)

        // If midpoint falls within counter-clockwise sweep from start to end, it's counter-clockwise
        return !(deltaM <= deltaCCW)
    }

    // MARK: - Utilities

    private func parseCoordinate(_ str: String?) -> Double {
        guard let str = str?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else {
            return 0.0
        }
        return parseLength(str) ?? 0.0
    }

    private func parseCoordinateOptional(_ str: String?) -> Double? {
        guard let str = str?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else {
            return nil
        }
        return parseLength(str)
    }

    private func parseLength(_ str: String) -> Double? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasSuffix("mm") {
            let num = String(trimmed.dropLast(2))
            return Double(num)
        } else if trimmed.hasSuffix("cm") {
            let num = String(trimmed.dropLast(2))
            return Double(num).map { $0 * 10.0 }
        } else if trimmed.hasSuffix("m") {
            let num = String(trimmed.dropLast(1))
            return Double(num).map { $0 * 1000.0 }
        } else if trimmed.hasSuffix("in") {
            let num = String(trimmed.dropLast(2))
            return Double(num).map { $0 * 25.4 }
        } else if trimmed.hasSuffix("pt") {
            let num = String(trimmed.dropLast(2))
            return Double(num).map { $0 * (25.4 / 72.0) }
        } else if trimmed.hasSuffix("pc") {
            let num = String(trimmed.dropLast(2))
            return Double(num).map { $0 * (25.4 / 6.0) }
        } else if trimmed.hasSuffix("px") {
            let num = String(trimmed.dropLast(2))
            return Double(num).map { $0 * (25.4 / options.dpi) }
        } else if trimmed.hasSuffix("%") {
            return nil
        } else {
            // Unitless: user units (interpreted as px in SVG)
            return Double(trimmed)
        }
    }

    private func hasStrokeDasharray(_ attrs: [String: String]) -> Bool {
        if let s = attrs["stroke-dasharray"], !s.isEmpty && s.lowercased() != "none" {
            return true
        }
        if let style = attrs["style"], style.contains("stroke-dasharray") {
            let parts = style.split(separator: ";")
            for part in parts {
                let kv = part.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 && kv[0].lowercased() == "stroke-dasharray" && kv[1].lowercased() != "none" {
                    return true
                }
            }
        }
        return false
    }

    private func isDisplayNone(_ attrs: [String: String]) -> Bool {
        if attrs["display"]?.lowercased() == "none" || attrs["visibility"]?.lowercased() == "hidden" {
            return true
        }
        if let style = attrs["style"] {
            if style.contains("display:none") || style.contains("display: none") {
                return true
            }
        }
        return false
    }
}

// MARK: - SVG Path Scanner

final class SVGPathScanner {
    private let text: String
    private var index: String.Index

    init(_ text: String) {
        self.text = text
        self.index = text.startIndex
    }

    var isAtEnd: Bool {
        index >= text.endIndex
    }

    func skipWhitespaceAndCommas() {
        while index < text.endIndex {
            let c = text[index]
            if c.isWhitespace || c == "," {
                index = text.index(after: index)
            } else {
                break
            }
        }
    }

    func peekCommand() -> Character? {
        skipWhitespaceAndCommas()
        guard index < text.endIndex else { return nil }
        let c = text[index]
        return c.isLetter ? c : nil
    }

    func readCommand() -> Character? {
        skipWhitespaceAndCommas()
        guard index < text.endIndex else { return nil }
        let c = text[index]
        if c.isLetter {
            index = text.index(after: index)
            return c
        }
        return nil
    }

    func readNumber() -> Double? {
        skipWhitespaceAndCommas()
        guard index < text.endIndex else { return nil }

        let start = index
        var curr = index

        if curr < text.endIndex && (text[curr] == "+" || text[curr] == "-") {
            curr = text.index(after: curr)
        }

        var hasDigits = false
        var hasDot = false

        while curr < text.endIndex {
            let c = text[curr]
            if c.isNumber {
                hasDigits = true
                curr = text.index(after: curr)
            } else if c == "." && !hasDot {
                hasDot = true
                curr = text.index(after: curr)
            } else {
                break
            }
        }

        guard hasDigits else { return nil }

        // Check scientific exponent
        if curr < text.endIndex && (text[curr] == "e" || text[curr] == "E") {
            let expStart = curr
            curr = text.index(after: curr)
            if curr < text.endIndex && (text[curr] == "+" || text[curr] == "-") {
                curr = text.index(after: curr)
            }
            var hasExpDigits = false
            while curr < text.endIndex && text[curr].isNumber {
                hasExpDigits = true
                curr = text.index(after: curr)
            }
            if !hasExpDigits {
                curr = expStart
            }
        }

        let token = String(text[start..<curr])
        index = curr
        return Double(token)
    }

    func readFlag() -> Int? {
        skipWhitespaceAndCommas()
        guard index < text.endIndex else { return nil }
        let c = text[index]
        if c == "0" {
            index = text.index(after: index)
            return 0
        } else if c == "1" {
            index = text.index(after: index)
            return 1
        }
        // Fallback if not single digit
        if let num = readNumber() {
            return num >= 0.5 ? 1 : 0
        }
        return nil
    }
}

// MARK: - SVG Path Parser

private final class SVGPathParser {
    let pathString: String
    let transform: SVGTransform2D
    let isConstruction: Bool
    let options: SVGImportOptions
    let mapToCAD: (SIMD2<Double>, SVGTransform2D) -> SIMD2<Double>

    init(
        pathString: String,
        transform: SVGTransform2D,
        isConstruction: Bool,
        options: SVGImportOptions,
        mapToCAD: @escaping (SIMD2<Double>, SVGTransform2D) -> SIMD2<Double>
    ) {
        self.pathString = pathString
        self.transform = transform
        self.isConstruction = isConstruction
        self.options = options
        self.mapToCAD = mapToCAD
    }

    func parse() -> [SketchEntity] {
        var entities: [SketchEntity] = []
        let scanner = SVGPathScanner(pathString)

        var currPt = SIMD2<Double>.zero
        var subpathStart = SIMD2<Double>.zero
        var lastCubicC2: SIMD2<Double>? = nil
        var lastQuadC1: SIMD2<Double>? = nil

        var activeCommand: Character? = nil

        while !scanner.isAtEnd {
            scanner.skipWhitespaceAndCommas()
            guard !scanner.isAtEnd else { break }

            if let cmd = scanner.peekCommand() {
                _ = scanner.readCommand()
                activeCommand = cmd
            }

            guard let cmd = activeCommand else { break }

            switch cmd {
            case "M", "m":
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else { break }
                let isRel = (cmd == "m")
                let pt = isRel ? (currPt + SIMD2<Double>(x, y)) : SIMD2<Double>(x, y)
                currPt = pt
                subpathStart = pt
                lastCubicC2 = nil
                lastQuadC1 = nil

                // Subsequent coordinate pairs are implicit L / l
                activeCommand = isRel ? "l" : "L"

            case "L", "l":
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else { break }
                let isRel = (cmd == "l")
                let nextPt = isRel ? (currPt + SIMD2<Double>(x, y)) : SIMD2<Double>(x, y)
                addLine(from: currPt, to: nextPt, into: &entities)
                currPt = nextPt
                lastCubicC2 = nil
                lastQuadC1 = nil

            case "H", "h":
                guard let x = scanner.readNumber() else { break }
                let isRel = (cmd == "h")
                let nextX = isRel ? (currPt.x + x) : x
                let nextPt = SIMD2<Double>(nextX, currPt.y)
                addLine(from: currPt, to: nextPt, into: &entities)
                currPt = nextPt
                lastCubicC2 = nil
                lastQuadC1 = nil

            case "V", "v":
                guard let y = scanner.readNumber() else { break }
                let isRel = (cmd == "v")
                let nextY = isRel ? (currPt.y + y) : y
                let nextPt = SIMD2<Double>(currPt.x, nextY)
                addLine(from: currPt, to: nextPt, into: &entities)
                currPt = nextPt
                lastCubicC2 = nil
                lastQuadC1 = nil

            case "Z", "z":
                if simd_distance(currPt, subpathStart) >= options.tolerance {
                    addLine(from: currPt, to: subpathStart, into: &entities)
                }
                currPt = subpathStart
                lastCubicC2 = nil
                lastQuadC1 = nil
                activeCommand = nil

            case "C", "c":
                guard let x1 = scanner.readNumber(), let y1 = scanner.readNumber(),
                      let x2 = scanner.readNumber(), let y2 = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber() else { break }

                let isRel = (cmd == "c")
                let p0 = currPt
                let p1 = isRel ? (currPt + SIMD2<Double>(x1, y1)) : SIMD2<Double>(x1, y1)
                let p2 = isRel ? (currPt + SIMD2<Double>(x2, y2)) : SIMD2<Double>(x2, y2)
                let p3 = isRel ? (currPt + SIMD2<Double>(x, y)) : SIMD2<Double>(x, y)

                addCubicBezier(p0: p0, p1: p1, p2: p2, p3: p3, into: &entities)
                currPt = p3
                lastCubicC2 = p2
                lastQuadC1 = nil

            case "S", "s":
                guard let x2 = scanner.readNumber(), let y2 = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber() else { break }

                let isRel = (cmd == "s")
                let p0 = currPt
                let p1: SIMD2<Double>
                if let prevC2 = lastCubicC2 {
                    p1 = 2.0 * p0 - prevC2
                } else {
                    p1 = p0
                }
                let p2 = isRel ? (currPt + SIMD2<Double>(x2, y2)) : SIMD2<Double>(x2, y2)
                let p3 = isRel ? (currPt + SIMD2<Double>(x, y)) : SIMD2<Double>(x, y)

                addCubicBezier(p0: p0, p1: p1, p2: p2, p3: p3, into: &entities)
                currPt = p3
                lastCubicC2 = p2
                lastQuadC1 = nil

            case "Q", "q":
                guard let x1 = scanner.readNumber(), let y1 = scanner.readNumber(),
                      let x = scanner.readNumber(), let y = scanner.readNumber() else { break }

                let isRel = (cmd == "q")
                let p0 = currPt
                let p1 = isRel ? (currPt + SIMD2<Double>(x1, y1)) : SIMD2<Double>(x1, y1)
                let p2 = isRel ? (currPt + SIMD2<Double>(x, y)) : SIMD2<Double>(x, y)

                addQuadBezier(p0: p0, p1: p1, p2: p2, into: &entities)
                currPt = p2
                lastQuadC1 = p1
                lastCubicC2 = nil

            case "T", "t":
                guard let x = scanner.readNumber(), let y = scanner.readNumber() else { break }

                let isRel = (cmd == "t")
                let p0 = currPt
                let p1: SIMD2<Double>
                if let prevQ1 = lastQuadC1 {
                    p1 = 2.0 * p0 - prevQ1
                } else {
                    p1 = p0
                }
                let p2 = isRel ? (currPt + SIMD2<Double>(x, y)) : SIMD2<Double>(x, y)

                addQuadBezier(p0: p0, p1: p1, p2: p2, into: &entities)
                currPt = p2
                lastQuadC1 = p1
                lastCubicC2 = nil

            case "A", "a":
                guard let rxRaw = scanner.readNumber(),
                      let ryRaw = scanner.readNumber(),
                      let rotDeg = scanner.readNumber(),
                      let fA = scanner.readFlag(),
                      let fS = scanner.readFlag(),
                      let x = scanner.readNumber(),
                      let y = scanner.readNumber() else { break }

                let isRel = (cmd == "a")
                let p2 = isRel ? (currPt + SIMD2<Double>(x, y)) : SIMD2<Double>(x, y)
                let p1 = currPt

                addEllipticalArc(
                    p1: p1,
                    p2: p2,
                    rx: abs(rxRaw),
                    ry: abs(ryRaw),
                    rotationDeg: rotDeg,
                    largeArcFlag: fA != 0,
                    sweepFlag: fS != 0,
                    into: &entities
                )
                currPt = p2
                lastCubicC2 = nil
                lastQuadC1 = nil

            default:
                // Unknown command; advance
                _ = scanner.readNumber()
            }
        }

        return entities
    }

    private func addLine(from p1: SIMD2<Double>, to p2: SIMD2<Double>, into entities: inout [SketchEntity]) {
        let startCAD = mapToCAD(p1, transform)
        let endCAD = mapToCAD(p2, transform)
        let d = endCAD - startCAD
        if (d.x * d.x + d.y * d.y) >= (options.tolerance * options.tolerance) {
            entities.append(SketchEntity.line(start: startCAD, end: endCAD, isConstruction: isConstruction))
        }
    }

    private func addCubicBezier(
        p0: SIMD2<Double>,
        p1: SIMD2<Double>,
        p2: SIMD2<Double>,
        p3: SIMD2<Double>,
        into entities: inout [SketchEntity]
    ) {
        let n = max(2, options.curveIntervals)
        var prevCAD = mapToCAD(p0, transform)

        for i in 1...n {
            let t = Double(i) / Double(n)
            let oneMinusT = 1.0 - t
            let b0 = oneMinusT * oneMinusT * oneMinusT
            let b1 = 3.0 * oneMinusT * oneMinusT * t
            let b2 = 3.0 * oneMinusT * t * t
            let b3 = t * t * t
            let pt = b0 * p0 + b1 * p1 + b2 * p2 + b3 * p3
            let currCAD = mapToCAD(pt, transform)

            let d = currCAD - prevCAD
            if (d.x * d.x + d.y * d.y) >= (options.tolerance * options.tolerance) {
                entities.append(SketchEntity.line(start: prevCAD, end: currCAD, isConstruction: isConstruction))
            }
            prevCAD = currCAD
        }
    }

    private func addQuadBezier(
        p0: SIMD2<Double>,
        p1: SIMD2<Double>,
        p2: SIMD2<Double>,
        into entities: inout [SketchEntity]
    ) {
        let n = max(2, options.curveIntervals)
        var prevCAD = mapToCAD(p0, transform)

        for i in 1...n {
            let t = Double(i) / Double(n)
            let oneMinusT = 1.0 - t
            let b0 = oneMinusT * oneMinusT
            let b1 = 2.0 * oneMinusT * t
            let b2 = t * t
            let pt = b0 * p0 + b1 * p1 + b2 * p2
            let currCAD = mapToCAD(pt, transform)

            let d = currCAD - prevCAD
            if (d.x * d.x + d.y * d.y) >= (options.tolerance * options.tolerance) {
                entities.append(SketchEntity.line(start: prevCAD, end: currCAD, isConstruction: isConstruction))
            }
            prevCAD = currCAD
        }
    }

    private func addEllipticalArc(
        p1: SIMD2<Double>,
        p2: SIMD2<Double>,
        rx: Double,
        ry: Double,
        rotationDeg: Double,
        largeArcFlag: Bool,
        sweepFlag: Bool,
        into entities: inout [SketchEntity]
    ) {
        let dist = simd_distance(p1, p2)
        guard dist >= options.tolerance else { return }

        if rx < options.tolerance || ry < options.tolerance {
            addLine(from: p1, to: p2, into: &entities)
            return
        }

        // SVG implementation notes F.6
        let phi = rotationDeg * .pi / 180.0
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx2 = (p1.x - p2.x) / 2.0
        let dy2 = (p1.y - p2.y) / 2.0

        let x1Prime = cosPhi * dx2 + sinPhi * dy2
        let y1Prime = -sinPhi * dx2 + cosPhi * dy2

        var rxScaled = rx
        var ryScaled = ry

        let lambda = (x1Prime * x1Prime) / (rxScaled * rxScaled) + (y1Prime * y1Prime) / (ryScaled * ryScaled)
        if lambda > 1.0 {
            let sqrtLambda = sqrt(lambda)
            rxScaled *= sqrtLambda
            ryScaled *= sqrtLambda
        }

        let rxSq = rxScaled * rxScaled
        let rySq = ryScaled * ryScaled
        let x1PrimeSq = x1Prime * x1Prime
        let y1PrimeSq = y1Prime * y1Prime

        let num = max(0.0, (rxSq * rySq) - (rxSq * y1PrimeSq) - (rySq * x1PrimeSq))
        let den = (rxSq * y1PrimeSq) + (rySq * x1PrimeSq)
        let factor = (largeArcFlag == sweepFlag ? -1.0 : 1.0) * sqrt(den > 0 ? num / den : 0.0)

        let cxPrime = factor * (rxScaled * y1Prime / ryScaled)
        let cyPrime = factor * (-ryScaled * x1Prime / rxScaled)

        let midX = (p1.x + p2.x) / 2.0
        let midY = (p1.y + p2.y) / 2.0

        let cx = cosPhi * cxPrime - sinPhi * cyPrime + midX
        let cy = sinPhi * cxPrime + cosPhi * cyPrime + midY
        let center = SIMD2<Double>(cx, cy)

        // Compute theta1 and deltaTheta
        func angleBetween(u: SIMD2<Double>, v: SIMD2<Double>) -> Double {
            let dot = u.x * v.x + u.y * v.y
            let len = sqrt((u.x * u.x + u.y * u.y) * (v.x * v.x + v.y * v.y))
            let sign = (u.x * v.y - u.y * v.x) < 0 ? -1.0 : 1.0
            let clamped = max(-1.0, min(1.0, len > 0 ? dot / len : 1.0))
            return sign * acos(clamped)
        }

        let u = SIMD2<Double>((x1Prime - cxPrime) / rxScaled, (y1Prime - cyPrime) / ryScaled)
        let v = SIMD2<Double>((-x1Prime - cxPrime) / rxScaled, (-y1Prime - cyPrime) / ryScaled)

        let theta1 = angleBetween(u: SIMD2<Double>(1.0, 0.0), v: u)
        var deltaTheta = angleBetween(u: u, v: v).truncatingRemainder(dividingBy: 2.0 * .pi)

        if !sweepFlag && deltaTheta > 0 {
            deltaTheta -= 2.0 * .pi
        } else if sweepFlag && deltaTheta < 0 {
            deltaTheta += 2.0 * .pi
        }

        // Circular arc optimization when rx == ry and transform has uniform scaling
        let sx = sqrt(transform.a * transform.a + transform.b * transform.b)
        let sy = sqrt(transform.c * transform.c + transform.d * transform.d)

        if abs(rxScaled - ryScaled) < options.tolerance && abs(sx - sy) < options.tolerance {
            let midTheta = theta1 + deltaTheta * 0.5
            let midPointSVG = center + SIMD2<Double>(
                rxScaled * cos(midTheta) * cosPhi - ryScaled * sin(midTheta) * sinPhi,
                rxScaled * cos(midTheta) * sinPhi + ryScaled * sin(midTheta) * cosPhi
            )

            let sCAD = mapToCAD(p1, transform)
            let eCAD = mapToCAD(p2, transform)
            let mCAD = mapToCAD(midPointSVG, transform)
            let cCAD = mapToCAD(center, transform)

            let aS = atan2(sCAD.y - cCAD.y, sCAD.x - cCAD.x)
            let aE = atan2(eCAD.y - cCAD.y, eCAD.x - cCAD.x)
            let aM = atan2(mCAD.y - cCAD.y, mCAD.x - cCAD.x)

            let twoPi = 2.0 * .pi
            func norm(_ a: Double) -> Double {
                var val = a.truncatingRemainder(dividingBy: twoPi)
                if val < 0 { val += twoPi }
                return val
            }

            let deltaCCW = norm(aE - aS)
            let deltaM = norm(aM - aS)
            let isCW = !(deltaM <= deltaCCW)

            entities.append(SketchEntity.arc(start: sCAD, end: eCAD, center: cCAD, clockwise: isCW, isConstruction: isConstruction))
        } else {
            // General elliptical arc discretization
            let n = max(4, options.curveIntervals)
            var prevCAD = mapToCAD(p1, transform)

            for i in 1...n {
                let t = Double(i) / Double(n)
                let theta = theta1 + deltaTheta * t
                let ptSVG = center + SIMD2<Double>(
                    rxScaled * cos(theta) * cosPhi - ryScaled * sin(theta) * sinPhi,
                    rxScaled * cos(theta) * sinPhi + ryScaled * sin(theta) * cosPhi
                )
                let currCAD = mapToCAD(ptSVG, transform)
                let d = currCAD - prevCAD
                if (d.x * d.x + d.y * d.y) >= (options.tolerance * options.tolerance) {
                    entities.append(SketchEntity.line(start: prevCAD, end: currCAD, isConstruction: isConstruction))
                }
                prevCAD = currCAD
            }
        }
    }
}
