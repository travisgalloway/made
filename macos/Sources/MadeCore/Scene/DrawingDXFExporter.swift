import Foundation
import simd

/// Exporter generating layered AutoCAD 2000 ASCII DXF (AC1015) text from 2D engineering drawing sheets.
@MainActor
public enum DrawingDXFExporter {

    // MARK: - Public Export API

    /// Exports a drawing sheet into AutoCAD 2000 (AC1015) ASCII DXF text format.
    public static func exportDXF(sheet: DrawingSheet, document: DocumentModel) -> String {
        let items: [BOMItem]
        if let firstTable = sheet.bomTables.first {
            items = firstTable.resolvedItems(from: document)
        } else {
            items = []
        }
        return exportDXF(sheet: sheet, metadata: document.metadata, bomItems: items)
    }

    /// Exports a drawing sheet to a destination file URL in DXF format.
    public static func exportDXF(sheet: DrawingSheet, document: DocumentModel, to url: URL) throws {
        let dxfText = exportDXF(sheet: sheet, document: document)
        try dxfText.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Decoupled export overload with resolved metadata and BOM items.
    public static func exportDXF(
        sheet: DrawingSheet,
        metadata: [String: String] = [:],
        bomItems: [BOMItem] = []
    ) -> String {
        let writer = DXFWriter()
        let sheetDim = sheet.dimensionsMM
        let sheetW = sheetDim.width
        let sheetH = sheetDim.height

        // 1. HEADER SECTION
        writer.writeSection("HEADER")
        writer.writeCode(9, "$ACADVER")
        writer.writeCode(1, "AC1015")
        writer.writeCode(9, "$INSUNITS")
        writer.writeCode(70, 4) // Millimeters
        writer.writeCode(9, "$MEASUREMENT")
        writer.writeCode(70, 1) // Metric
        writer.writeCode(9, "$EXTMIN")
        writer.writePoint3D(codeX: 10, SIMD3<Double>(0.0, 0.0, 0.0))
        writer.writeCode(9, "$EXTMAX")
        writer.writePoint3D(codeX: 10, SIMD3<Double>(sheetW, sheetH, 0.0))
        writer.writeEndSec()

        // 2. TABLES SECTION
        writer.writeSection("TABLES")

        // VPORT Table
        writer.writeTable("VPORT", count: 1)
        writer.writeCode(0, "VPORT")
        writer.writeCode(2, "*ACTIVE")
        writer.writeCode(70, 0)
        writer.writePoint2D(codeX: 10, SIMD2<Double>(0.0, 0.0))
        writer.writePoint2D(codeX: 11, SIMD2<Double>(1.0, 1.0))
        writer.writePoint2D(codeX: 12, SIMD2<Double>(sheetW * 0.5, sheetH * 0.5))
        writer.writeCode(40, sheetH)
        writer.writeCode(41, sheetW / max(1.0, sheetH))
        writer.writeEndTab()

        // LTYPE Table
        writer.writeTable("LTYPE", count: 4)
        writeLinetype(writer, name: "CONTINUOUS", description: "Solid line")
        writeLinetype(writer, name: "HIDDEN", description: "Hidden __ __ __ __", length: 9.525, dashes: [6.35, -3.175])
        writeLinetype(writer, name: "CENTER", description: "Center ____ _ ____ _", length: 15.875, dashes: [9.525, -3.175, 0.0, -3.175])
        writeLinetype(writer, name: "PHANTOM", description: "Phantom ______ _ _ _____", length: 22.225, dashes: [9.525, -3.175, 0.0, -3.175, 0.0, -3.175])
        writer.writeEndTab()

        // LAYER Table
        writer.writeTable("LAYER", count: 10)
        writeLayer(writer, name: "0", color: 7, lineweight: 25)
        writeLayer(writer, name: "BORDER", color: 7, lineweight: 70)
        writeLayer(writer, name: "TITLE_BLOCK", color: 7, lineweight: 35)
        writeLayer(writer, name: "VISIBLE", color: 7, lineweight: 50)
        writeLayer(writer, name: "HIDDEN", color: 8, lineweight: 25, linetype: "HIDDEN")
        writeLayer(writer, name: "DIMENSIONS", color: 3, lineweight: 25) // Green
        writeLayer(writer, name: "ANNOTATIONS", color: 4, lineweight: 25) // Cyan
        writeLayer(writer, name: "CENTER", color: 1, lineweight: 25, linetype: "CENTER") // Red
        writeLayer(writer, name: "BOM", color: 7, lineweight: 25)
        writeLayer(writer, name: "HATCH", color: 8, lineweight: 25) // Dark Gray
        writer.writeEndTab()

        // STYLE Table
        writer.writeTable("STYLE", count: 1)
        writer.writeCode(0, "STYLE")
        writer.writeCode(2, "STANDARD")
        writer.writeCode(70, 0)
        writer.writeCode(40, 0.0)
        writer.writeCode(41, 1.0)
        writer.writeCode(50, 0.0)
        writer.writeCode(71, 0)
        writer.writeCode(42, 2.5)
        writer.writeCode(3, "txt")
        writer.writeCode(4, "")
        writer.writeEndTab()

        writer.writeEndSec()

        // 3. BLOCKS SECTION
        writer.writeSection("BLOCKS")
        writer.writeEndSec()

        // 4. ENTITIES SECTION
        writer.writeSection("ENTITIES")

        // Coordinate transformer: converts sheet mm (origin top-left) to CAD mm (origin bottom-left)
        func toCAD(_ sheetPtMM: SIMD2<Double>) -> SIMD2<Double> {
            SIMD2<Double>(sheetPtMM.x, sheetH - sheetPtMM.y)
        }

        // 4.1 Border lines (10 mm margin)
        let m = 10.0
        let bP1 = SIMD2<Double>(m, m)
        let bP2 = SIMD2<Double>(sheetW - m, m)
        let bP3 = SIMD2<Double>(sheetW - m, sheetH - m)
        let bP4 = SIMD2<Double>(m, sheetH - m)

        writer.writeLine(layer: "BORDER", start: bP1, end: bP2)
        writer.writeLine(layer: "BORDER", start: bP2, end: bP3)
        writer.writeLine(layer: "BORDER", start: bP3, end: bP4)
        writer.writeLine(layer: "BORDER", start: bP4, end: bP1)

        // 4.2 Zone reference marks (1-4 top/bottom, A-D left/right)
        let innerW = sheetW - (m * 2.0)
        let innerH = sheetH - (m * 2.0)
        let colStep = innerW / 4.0
        for i in 0..<4 {
            let label = "\(i + 1)"
            let xPos = m + (Double(i) + 0.5) * colStep
            // Top margin mark (CAD Y: sheetH - m * 0.5)
            writer.writeText(layer: "BORDER", text: label, point: SIMD2<Double>(xPos, sheetH - (m * 0.5)), height: 3.0, hAlign: 1, vAlign: 2)
            // Bottom margin mark (CAD Y: m * 0.5)
            writer.writeText(layer: "BORDER", text: label, point: SIMD2<Double>(xPos, m * 0.5), height: 3.0, hAlign: 1, vAlign: 2)
        }

        let letters = ["A", "B", "C", "D"]
        let rowStep = innerH / 4.0
        for i in 0..<4 {
            let label = letters[i]
            // A at top row, D at bottom row
            let yCAD = sheetH - m - ((Double(i) + 0.5) * rowStep)
            // Left margin mark
            writer.writeText(layer: "BORDER", text: label, point: SIMD2<Double>(m * 0.5, yCAD), height: 3.0, hAlign: 1, vAlign: 2)
            // Right margin mark
            writer.writeText(layer: "BORDER", text: label, point: SIMD2<Double>(sheetW - (m * 0.5), yCAD), height: 3.0, hAlign: 1, vAlign: 2)
        }

        // 4.3 Title block
        if sheet.titleBlockTemplate != .none {
            let titleProps = sheet.resolvedTitleBlockProperties(
                documentMetadata: metadata,
                sheetIndex: 1,
                totalSheets: 1
            )
            writeDXFTitleBlock(
                writer: writer,
                template: sheet.titleBlockTemplate,
                properties: titleProps,
                sheetW: sheetW,
                margin: m
            )
        }

        // 4.4 Placed views
        for view in sheet.views {
            writeDXFView(writer: writer, view: view, sheet: sheet, sheetH: sheetH, toCAD: toCAD)
        }

        // 4.5 Annotations
        for annotation in sheet.annotations where annotation.isVisible {
            writeDXFAnnotation(writer: writer, annotation: annotation, sheet: sheet, sheetH: sheetH, toCAD: toCAD)
        }

        // 4.6 BOM Tables
        for table in sheet.bomTables {
            let items = bomItems.isEmpty ? [DrawingBOMTable.placeholderItem] : bomItems
            writeDXFBOMTable(writer: writer, table: table, items: items, sheetH: sheetH)
        }

        writer.writeEndSec()

        // 5. EOF
        writer.writeCode(0, "EOF")

        return writer.output
    }

    // MARK: - DXF Title Block

    private static func writeDXFTitleBlock(
        writer: DXFWriter,
        template: TitleBlockTemplate,
        properties: [String: String],
        sheetW: Double,
        margin: Double
    ) {
        let blockW = (template == .minimal) ? 120.0 : 170.0
        let blockH = (template == .minimal) ? 36.0 : 54.0

        let x0 = sheetW - margin - blockW
        let x1 = sheetW - margin
        let y0 = margin
        let y1 = margin + blockH

        // Frame
        writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(x0, y0), end: SIMD2<Double>(x1, y0))
        writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(x1, y0), end: SIMD2<Double>(x1, y1))
        writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(x1, y1), end: SIMD2<Double>(x0, y1))
        writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(x0, y1), end: SIMD2<Double>(x0, y0))

        let title = properties["title"] ?? properties[CustomPropertyKey.description] ?? "Untitled"
        let partNum = properties[CustomPropertyKey.partNumber] ?? "DRW-001"
        let rev = properties[CustomPropertyKey.revision] ?? "A"
        let author = properties["author"] ?? NSFullUserName()
        let date = properties["date"] ?? ""
        let scale = properties["scale"] ?? "1:1"
        let sheetText = properties["sheet"] ?? "Sheet 1 of 1"
        let vendor = properties[CustomPropertyKey.vendor] ?? ""

        if template == .minimal {
            let midY = y0 + (blockH * 0.45)
            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(x0, midY), end: SIMD2<Double>(x1, midY))

            let divTopX = x0 + (blockW * 0.65)
            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(divTopX, midY), end: SIMD2<Double>(divTopX, y1))

            // Labels and values
            writer.writeText(layer: "TITLE_BLOCK", text: "TITLE", point: SIMD2<Double>(x0 + 2.0, y1 - 4.0), height: 2.0)
            writer.writeText(layer: "TITLE_BLOCK", text: title, point: SIMD2<Double>(x0 + 2.0, midY + 4.0), height: 3.0)

            writer.writeText(layer: "TITLE_BLOCK", text: "DWG NO.", point: SIMD2<Double>(divTopX + 2.0, y1 - 4.0), height: 2.0)
            writer.writeText(layer: "TITLE_BLOCK", text: partNum, point: SIMD2<Double>(divTopX + 2.0, midY + 4.0), height: 3.0)

            let b1 = x0 + (blockW * 0.20)
            let b2 = x0 + (blockW * 0.50)
            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(b1, y0), end: SIMD2<Double>(b1, midY))
            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(b2, y0), end: SIMD2<Double>(b2, midY))

            writer.writeText(layer: "TITLE_BLOCK", text: "REV", point: SIMD2<Double>(x0 + 2.0, midY - 3.5), height: 1.8)
            writer.writeText(layer: "TITLE_BLOCK", text: rev, point: SIMD2<Double>(x0 + 2.0, y0 + 3.0), height: 2.5)

            writer.writeText(layer: "TITLE_BLOCK", text: "SCALE", point: SIMD2<Double>(b1 + 2.0, midY - 3.5), height: 1.8)
            writer.writeText(layer: "TITLE_BLOCK", text: scale, point: SIMD2<Double>(b1 + 2.0, y0 + 3.0), height: 2.5)

            writer.writeText(layer: "TITLE_BLOCK", text: "SHEET", point: SIMD2<Double>(b2 + 2.0, midY - 3.5), height: 1.8)
            writer.writeText(layer: "TITLE_BLOCK", text: sheetText, point: SIMD2<Double>(b2 + 2.0, y0 + 3.0), height: 2.5)
        } else {
            let hasVendor = !vendor.isEmpty
            let vendorH = hasVendor ? (blockH * 0.22) : 0.0
            let bottomH = blockH * 0.35
            let bottomY = y0 + bottomH
            let topY = y1 - vendorH

            if hasVendor {
                writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(x0, topY), end: SIMD2<Double>(x1, topY))
                writer.writeText(layer: "TITLE_BLOCK", text: vendor.uppercased(), point: SIMD2<Double>(x0 + 4.0, topY + (vendorH * 0.4)), height: 3.5)
            }

            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(x0, bottomY), end: SIMD2<Double>(x1, bottomY))

            let midDivX = x0 + (blockW * 0.60)
            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(midDivX, bottomY), end: SIMD2<Double>(midDivX, topY))

            writer.writeText(layer: "TITLE_BLOCK", text: "TITLE / DESCRIPTION", point: SIMD2<Double>(x0 + 2.0, topY - 3.5), height: 2.0)
            writer.writeText(layer: "TITLE_BLOCK", text: title, point: SIMD2<Double>(x0 + 2.0, bottomY + 4.0), height: 3.0)

            writer.writeText(layer: "TITLE_BLOCK", text: "DRAWING NO.", point: SIMD2<Double>(midDivX + 2.0, topY - 3.5), height: 2.0)
            writer.writeText(layer: "TITLE_BLOCK", text: partNum, point: SIMD2<Double>(midDivX + 2.0, bottomY + 4.0), height: 3.0)

            let d1 = x0 + (blockW * 0.15)
            let d2 = d1 + (blockW * 0.28)
            let d3 = d2 + (blockW * 0.25)
            let d4 = d3 + (blockW * 0.16)

            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(d1, y0), end: SIMD2<Double>(d1, bottomY))
            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(d2, y0), end: SIMD2<Double>(d2, bottomY))
            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(d3, y0), end: SIMD2<Double>(d3, bottomY))
            writer.writeLine(layer: "TITLE_BLOCK", start: SIMD2<Double>(d4, y0), end: SIMD2<Double>(d4, bottomY))

            writer.writeText(layer: "TITLE_BLOCK", text: "REV", point: SIMD2<Double>(x0 + 2.0, bottomY - 3.5), height: 1.8)
            writer.writeText(layer: "TITLE_BLOCK", text: rev, point: SIMD2<Double>(x0 + 2.0, y0 + 3.0), height: 2.5)

            writer.writeText(layer: "TITLE_BLOCK", text: "AUTHOR", point: SIMD2<Double>(d1 + 2.0, bottomY - 3.5), height: 1.8)
            writer.writeText(layer: "TITLE_BLOCK", text: author, point: SIMD2<Double>(d1 + 2.0, y0 + 3.0), height: 2.5)

            writer.writeText(layer: "TITLE_BLOCK", text: "DATE", point: SIMD2<Double>(d2 + 2.0, bottomY - 3.5), height: 1.8)
            writer.writeText(layer: "TITLE_BLOCK", text: date, point: SIMD2<Double>(d2 + 2.0, y0 + 3.0), height: 2.5)

            writer.writeText(layer: "TITLE_BLOCK", text: "SCALE", point: SIMD2<Double>(d3 + 2.0, bottomY - 3.5), height: 1.8)
            writer.writeText(layer: "TITLE_BLOCK", text: scale, point: SIMD2<Double>(d3 + 2.0, y0 + 3.0), height: 2.5)

            writer.writeText(layer: "TITLE_BLOCK", text: "SHEET", point: SIMD2<Double>(d4 + 2.0, bottomY - 3.5), height: 1.8)
            writer.writeText(layer: "TITLE_BLOCK", text: sheetText, point: SIMD2<Double>(d4 + 2.0, y0 + 3.0), height: 2.5)
        }
    }

    // MARK: - DXF Views

    private static func writeDXFView(
        writer: DXFWriter,
        view: DrawingView,
        sheet: DrawingSheet,
        sheetH: Double,
        toCAD: (SIMD2<Double>) -> SIMD2<Double>
    ) {
        let centerCAD = toCAD(view.positionMM)
        let scale = view.scale.scaleFactor

        func modelToCAD(_ pt: SIMD2<Double>) -> SIMD2<Double> {
            SIMD2<Double>(
                centerCAD.x + (pt.x * scale),
                centerCAD.y + (pt.y * scale)
            )
        }

        if let hlr = view.cachedHLR {
            // Visible edges
            for edge in hlr.visibleEdges {
                guard edge.points2D.count >= 2 else { continue }
                for i in 0..<(edge.points2D.count - 1) {
                    let p1 = modelToCAD(edge.points2D[i])
                    let p2 = modelToCAD(edge.points2D[i + 1])
                    writer.writeLine(layer: "VISIBLE", start: p1, end: p2)
                }
            }

            // Hidden edges
            if view.displayStyle == .hiddenLinesVisible {
                for edge in hlr.hiddenEdges {
                    guard edge.points2D.count >= 2 else { continue }
                    for i in 0..<(edge.points2D.count - 1) {
                        let p1 = modelToCAD(edge.points2D[i])
                        let p2 = modelToCAD(edge.points2D[i + 1])
                        writer.writeLine(layer: "HIDDEN", start: p1, end: p2, linetype: "HIDDEN")
                    }
                }
            }

            // Section hatching
            if view.kind == .section || view.hatchPattern != nil {
                let pattern = view.hatchPattern ?? .standard
                if let bounds = hlr.bounds2D {
                    let hatchEdges = DrawingHatchGenerator.generateHatchLines(in: bounds, pattern: pattern)
                    for edge in hatchEdges {
                        guard let p1 = edge.startPoint2D, let p2 = edge.endPoint2D else { continue }
                        writer.writeLine(layer: "HATCH", start: modelToCAD(p1), end: modelToCAD(p2))
                    }
                }
            }
        }

        // Detail View callout circle and label
        if view.kind == .detail, let detDef = view.detailDefinition {
            let radiusCAD = detDef.radiusMM * scale
            writer.writeCircle(layer: "ANNOTATIONS", center: centerCAD, radius: radiusCAD)
            let label = "DETAIL \(detDef.label) · SCALE \(view.scale.displayString)"
            writer.writeText(layer: "ANNOTATIONS", text: label, point: SIMD2<Double>(centerCAD.x, centerCAD.y - radiusCAD - 5.0), height: 3.0, hAlign: 1, vAlign: 2)
        }

        // Parent overlays for child section views or detail views
        let children = sheet.views.filter { $0.parentViewId == view.id }
        for child in children {
            if child.kind == .section, let secDef = child.sectionDefinition {
                let p1 = modelToCAD(secDef.startPointMM)
                let p2 = modelToCAD(secDef.endPointMM)
                writer.writeLine(layer: "ANNOTATIONS", start: p1, end: p2, linetype: "PHANTOM")

                // Arrows
                let arrowLen = 5.0
                let arrDir = secDef.arrowDirection
                let arrOffset = SIMD2<Double>(arrDir.x * arrowLen, arrDir.y * arrowLen)
                writeDXFArrowhead(writer: writer, layer: "ANNOTATIONS", tip: p1 + arrOffset, from: p1)
                writeDXFArrowhead(writer: writer, layer: "ANNOTATIONS", tip: p2 + arrOffset, from: p2)

                writer.writeText(layer: "ANNOTATIONS", text: secDef.label, point: p1 + (arrOffset * 1.5), height: 3.5, hAlign: 1, vAlign: 2)
                writer.writeText(layer: "ANNOTATIONS", text: secDef.label, point: p2 + (arrOffset * 1.5), height: 3.5, hAlign: 1, vAlign: 2)
            } else if child.kind == .detail, let detDef = child.detailDefinition {
                let c = modelToCAD(detDef.centerMM)
                let r = detDef.radiusMM * scale
                writer.writeCircle(layer: "ANNOTATIONS", center: c, radius: r)
                writer.writeText(layer: "ANNOTATIONS", text: detDef.label, point: SIMD2<Double>(c.x + r + 2.0, c.y + r + 2.0), height: 3.0)
            }
        }
    }

    // MARK: - DXF Annotations

    private static func writeDXFAnnotation(
        writer: DXFWriter,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        sheetH: Double,
        toCAD: (SIMD2<Double>) -> SIMD2<Double>
    ) {
        func toCADPoint(_ ptMM: SIMD2<Double>) -> SIMD2<Double> {
            if let viewId = annotation.viewId, let view = sheet.views.first(where: { $0.id == viewId }) {
                let sheetPt = SIMD2<Double>(
                    view.positionMM.x + (ptMM.x * view.scale.scaleFactor),
                    view.positionMM.y - (ptMM.y * view.scale.scaleFactor)
                )
                return toCAD(sheetPt)
            } else {
                return toCAD(ptMM)
            }
        }

        switch annotation.data {
        case .linear(let d):
            let p1 = toCADPoint(d.startPointMM)
            let p2 = toCADPoint(d.endPointMM)
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let len = hypot(dx, dy)
            guard len > 1e-4 else { break }

            let offset = d.offsetMM
            let nx = -dy / len
            let ny = dx / len

            let dimP1 = SIMD2<Double>(p1.x + nx * offset, p1.y + ny * offset)
            let dimP2 = SIMD2<Double>(p2.x + nx * offset, p2.y + ny * offset)

            let overshoot = 2.0
            let extP1End = SIMD2<Double>(dimP1.x + nx * overshoot, dimP1.y + ny * overshoot)
            let extP2End = SIMD2<Double>(dimP2.x + nx * overshoot, dimP2.y + ny * overshoot)

            writer.writeLine(layer: "DIMENSIONS", start: p1, end: extP1End)
            writer.writeLine(layer: "DIMENSIONS", start: p2, end: extP2End)
            writer.writeLine(layer: "DIMENSIONS", start: dimP1, end: dimP2)

            writeDXFArrowhead(writer: writer, layer: "DIMENSIONS", tip: dimP1, from: dimP2)
            writeDXFArrowhead(writer: writer, layer: "DIMENSIONS", tip: dimP2, from: dimP1)

            let midPt = (dimP1 + dimP2) * 0.5
            writer.writeText(layer: "DIMENSIONS", text: d.formattedText, point: midPt, height: 2.5, hAlign: 1, vAlign: 2)

        case .angular(let d):
            let v = toCADPoint(d.vertexMM)
            let p1 = toCADPoint(d.startPointMM)
            let p2 = toCADPoint(d.endPointMM)
            let r = d.arcRadiusMM

            var a1 = atan2(p1.y - v.y, p1.x - v.x) * 180.0 / .pi
            var a2 = atan2(p2.y - v.y, p2.x - v.x) * 180.0 / .pi
            if a1 < 0 { a1 += 360.0 }
            if a2 < 0 { a2 += 360.0 }
            if a2 < a1 { a2 += 360.0 }

            writer.writeLine(layer: "DIMENSIONS", start: v, end: p1)
            writer.writeLine(layer: "DIMENSIONS", start: v, end: p2)
            writer.writeArc(layer: "DIMENSIONS", center: v, radius: r, startAngleDeg: a1, endAngleDeg: a2)

            let midAngleRad = ((a1 + a2) * 0.5) * .pi / 180.0
            let textPt = SIMD2<Double>(v.x + cos(midAngleRad) * (r + 3.0), v.y + sin(midAngleRad) * (r + 3.0))
            writer.writeText(layer: "DIMENSIONS", text: d.formattedText, point: textPt, height: 2.5, hAlign: 1, vAlign: 2)

        case .radial(let d):
            let center = toCADPoint(d.centerMM)
            let arcPt = toCADPoint(d.arcPointMM)
            let delta = arcPt - center
            let dist = hypot(delta.x, delta.y)
            let dir = dist > 1e-4 ? delta / dist : SIMD2<Double>(1, 0)

            let shoulder = arcPt + (dir * d.leaderOffsetMM)
            let endPt = SIMD2<Double>(shoulder.x + (dir.x >= 0 ? 8.0 : -8.0), shoulder.y)

            writer.writeLine(layer: "DIMENSIONS", start: arcPt, end: shoulder)
            writer.writeLine(layer: "DIMENSIONS", start: shoulder, end: endPt)
            writeDXFArrowhead(writer: writer, layer: "DIMENSIONS", tip: arcPt, from: shoulder)

            let textPt = SIMD2<Double>(endPt.x + (dir.x >= 0 ? 2.0 : -2.0), endPt.y)
            writer.writeText(layer: "DIMENSIONS", text: d.formattedText, point: textPt, height: 2.5, hAlign: dir.x >= 0 ? 0 : 2, vAlign: 2)

        case .ordinate(let d):
            let datum = toCADPoint(d.datumOriginMM)
            let loc = toCADPoint(d.locationMM)
            writer.writeCircle(layer: "DIMENSIONS", center: datum, radius: 1.0)

            let textPt: SIMD2<Double>
            if d.axis == .x {
                let extEnd = SIMD2<Double>(loc.x, loc.y + d.jogOffsetMM)
                writer.writeLine(layer: "DIMENSIONS", start: loc, end: extEnd)
                textPt = SIMD2<Double>(extEnd.x, extEnd.y + 2.0)
            } else {
                let extEnd = SIMD2<Double>(loc.x + d.jogOffsetMM, loc.y)
                writer.writeLine(layer: "DIMENSIONS", start: loc, end: extEnd)
                textPt = SIMD2<Double>(extEnd.x + 2.0, extEnd.y)
            }
            writer.writeText(layer: "DIMENSIONS", text: d.formattedText, point: textPt, height: 2.5, hAlign: 1, vAlign: 2)

        case .baseline(let d):
            let base = toCADPoint(d.basePointMM)
            for (idx, target) in d.targetPointsMM.enumerated() {
                let tPt = toCADPoint(target)
                let stepOffset = d.stackOffsetMM(forTargetIndex: idx)
                let bDim = SIMD2<Double>(base.x, base.y + stepOffset)
                let tDim = SIMD2<Double>(tPt.x, tPt.y + stepOffset)

                writer.writeLine(layer: "DIMENSIONS", start: base, end: bDim)
                writer.writeLine(layer: "DIMENSIONS", start: tPt, end: tDim)
                writer.writeLine(layer: "DIMENSIONS", start: bDim, end: tDim)
                writeDXFArrowhead(writer: writer, layer: "DIMENSIONS", tip: bDim, from: tDim)
                writeDXFArrowhead(writer: writer, layer: "DIMENSIONS", tip: tDim, from: bDim)

                let text = d.formattedText(forTargetIndex: idx)
                writer.writeText(layer: "DIMENSIONS", text: text, point: (bDim + tDim) * 0.5, height: 2.2, hAlign: 1, vAlign: 2)
            }

        case .note(let d):
            let pt = toCADPoint(d.positionMM)
            writer.writeText(layer: "ANNOTATIONS", text: d.text, point: pt, height: d.fontSizePt * 0.35)

        case .leader(let d):
            let arrow = toCADPoint(d.arrowPointMM)
            let elbow = toCADPoint(d.elbowPointMM)
            let isRight = d.elbowPointMM.x >= d.arrowPointMM.x
            let shoulderPtMM = SIMD2<Double>(d.elbowPointMM.x + (isRight ? d.landingLengthMM : -d.landingLengthMM), d.elbowPointMM.y)
            let shoulder = toCADPoint(shoulderPtMM)

            writer.writeLine(layer: "ANNOTATIONS", start: arrow, end: elbow)
            writer.writeLine(layer: "ANNOTATIONS", start: elbow, end: shoulder)
            writeDXFArrowhead(writer: writer, layer: "ANNOTATIONS", tip: arrow, from: elbow)

            let textPt = SIMD2<Double>(shoulder.x + (isRight ? 2.0 : -2.0), shoulder.y)
            writer.writeText(layer: "ANNOTATIONS", text: d.text, point: textPt, height: d.fontSizePt * 0.35, hAlign: isRight ? 0 : 2, vAlign: 2)

        case .centerMark(let d):
            let c = toCADPoint(d.centerMM)
            let s = (d.markSizeMM * 0.5) + d.extensionMM
            let gap = 1.0
            writer.writeLine(layer: "CENTER", start: SIMD2<Double>(c.x - s, c.y), end: SIMD2<Double>(c.x - gap, c.y))
            writer.writeLine(layer: "CENTER", start: SIMD2<Double>(c.x + gap, c.y), end: SIMD2<Double>(c.x + s, c.y))
            writer.writeLine(layer: "CENTER", start: SIMD2<Double>(c.x, c.y - s), end: SIMD2<Double>(c.x, c.y - gap))
            writer.writeLine(layer: "CENTER", start: SIMD2<Double>(c.x, c.y + gap), end: SIMD2<Double>(c.x, c.y + s))

        case .centerline(let d):
            let p1 = toCADPoint(d.startPointMM)
            let p2 = toCADPoint(d.endPointMM)
            let delta = p2 - p1
            let len = hypot(delta.x, delta.y)
            guard len > 1e-4 else { break }
            let dir = delta / len
            let extP1 = p1 - (dir * d.extensionMM)
            let extP2 = p2 + (dir * d.extensionMM)
            writer.writeLine(layer: "CENTER", start: extP1, end: extP2, linetype: "CENTER")

        case .holeCallout(let d):
            let anchor = toCADPoint(d.anchorPointMM)
            let elbow = toCADPoint(d.elbowPointMM)
            let landingPt = SIMD2<Double>(elbow.x + d.landingLengthMM, elbow.y)

            writer.writeLine(layer: "ANNOTATIONS", start: anchor, end: elbow)
            writer.writeLine(layer: "ANNOTATIONS", start: elbow, end: landingPt)
            writeDXFArrowhead(writer: writer, layer: "ANNOTATIONS", tip: anchor, from: elbow)

            let lines = d.formattedCalloutLines
            for (idx, line) in lines.enumerated() {
                let yPos = elbow.y + 1.0 - (Double(idx) * 3.5)
                writer.writeText(layer: "ANNOTATIONS", text: line, point: SIMD2<Double>(landingPt.x + 1.5, yPos), height: 2.5)
            }

        case .balloon(let d):
            let anchor = toCADPoint(d.anchorPointMM)
            let center = toCADPoint(d.balloonCenterMM)
            let r = d.sizeMM * 0.5

            let delta = center - anchor
            let dist = hypot(delta.x, delta.y)
            let contact = dist > r ? center - ((delta / dist) * r) : center

            writer.writeLine(layer: "ANNOTATIONS", start: anchor, end: contact)
            writeDXFArrowhead(writer: writer, layer: "ANNOTATIONS", tip: anchor, from: contact)

            switch d.shape {
            case .circular:
                writer.writeCircle(layer: "ANNOTATIONS", center: center, radius: r)
                writer.writeText(layer: "ANNOTATIONS", text: d.formattedText, point: center, height: 3.0, hAlign: 1, vAlign: 2)

            case .splitCircular:
                writer.writeCircle(layer: "ANNOTATIONS", center: center, radius: r)
                writer.writeLine(layer: "ANNOTATIONS", start: SIMD2<Double>(center.x - r, center.y), end: SIMD2<Double>(center.x + r, center.y))
                writer.writeText(layer: "ANNOTATIONS", text: d.formattedText, point: SIMD2<Double>(center.x, center.y + (r * 0.45)), height: 2.2, hAlign: 1, vAlign: 2)
                writer.writeText(layer: "ANNOTATIONS", text: d.formattedQuantityText, point: SIMD2<Double>(center.x, center.y - (r * 0.45)), height: 2.2, hAlign: 1, vAlign: 2)

            case .box:
                let x0 = center.x - r
                let x1 = center.x + r
                let y0 = center.y - r
                let y1 = center.y + r
                writer.writeLine(layer: "ANNOTATIONS", start: SIMD2<Double>(x0, y0), end: SIMD2<Double>(x1, y0))
                writer.writeLine(layer: "ANNOTATIONS", start: SIMD2<Double>(x1, y0), end: SIMD2<Double>(x1, y1))
                writer.writeLine(layer: "ANNOTATIONS", start: SIMD2<Double>(x1, y1), end: SIMD2<Double>(x0, y1))
                writer.writeLine(layer: "ANNOTATIONS", start: SIMD2<Double>(x0, y1), end: SIMD2<Double>(x0, y0))
                let text = d.showQuantity ? "\(d.formattedText) (\(d.formattedQuantityText))" : d.formattedText
                writer.writeText(layer: "ANNOTATIONS", text: text, point: center, height: 2.5, hAlign: 1, vAlign: 2)

            case .hexagon:
                for i in 0..<6 {
                    let a1 = (Double(i) * .pi / 3.0) - (.pi / 6.0)
                    let a2 = (Double(i + 1) * .pi / 3.0) - (.pi / 6.0)
                    let p1 = SIMD2<Double>(center.x + cos(a1) * r, center.y + sin(a1) * r)
                    let p2 = SIMD2<Double>(center.x + cos(a2) * r, center.y + sin(a2) * r)
                    writer.writeLine(layer: "ANNOTATIONS", start: p1, end: p2)
                }
                writer.writeText(layer: "ANNOTATIONS", text: d.formattedText, point: center, height: 2.5, hAlign: 1, vAlign: 2)

            case .none:
                let text = d.showQuantity ? "\(d.formattedText) (\(d.formattedQuantityText))" : d.formattedText
                writer.writeText(layer: "ANNOTATIONS", text: text, point: center, height: 3.0, hAlign: 1, vAlign: 2)
            }
        }
    }

    // MARK: - DXF BOM Table

    private static func writeDXFBOMTable(
        writer: DXFWriter,
        table: DrawingBOMTable,
        items: [BOMItem],
        sheetH: Double
    ) {
        let totalW = table.totalWidthMM
        let rowH = table.rowHeightMM
        let titleH = table.showTitle ? rowH : 0.0
        let headerH = rowH
        let dataH = Double(max(1, items.count)) * rowH
        let totalH = titleH + headerH + dataH

        // Top-left in sheet mm converts to CAD Y top
        let x0 = table.positionMM.x
        let x1 = x0 + totalW
        let yTop = sheetH - table.positionMM.y
        let yBottom = yTop - totalH

        // Outer border
        writer.writeLine(layer: "BOM", start: SIMD2<Double>(x0, yBottom), end: SIMD2<Double>(x1, yBottom))
        writer.writeLine(layer: "BOM", start: SIMD2<Double>(x1, yBottom), end: SIMD2<Double>(x1, yTop))
        writer.writeLine(layer: "BOM", start: SIMD2<Double>(x1, yTop), end: SIMD2<Double>(x0, yTop))
        writer.writeLine(layer: "BOM", start: SIMD2<Double>(x0, yTop), end: SIMD2<Double>(x0, yBottom))

        var curY = yTop

        // Title row
        if table.showTitle {
            let nextY = curY - rowH
            writer.writeLine(layer: "BOM", start: SIMD2<Double>(x0, nextY), end: SIMD2<Double>(x1, nextY))
            writer.writeText(layer: "BOM", text: table.title, point: SIMD2<Double>(x0 + (totalW * 0.5), curY - (rowH * 0.5)), height: 3.5, hAlign: 1, vAlign: 2)
            curY = nextY
        }

        // Header row
        let headerBottomY = curY - rowH
        writer.writeLine(layer: "BOM", start: SIMD2<Double>(x0, headerBottomY), end: SIMD2<Double>(x1, headerBottomY))

        var curX = x0
        for (colIdx, col) in table.columns.enumerated() {
            let colW = table.width(for: col)
            if colIdx > 0 {
                writer.writeLine(layer: "BOM", start: SIMD2<Double>(curX, yBottom), end: SIMD2<Double>(curX, curY))
            }
            writer.writeText(layer: "BOM", text: col.displayName, point: SIMD2<Double>(curX + (colW * 0.5), curY - (rowH * 0.5)), height: 2.8, hAlign: 1, vAlign: 2)
            curX += colW
        }
        curY = headerBottomY

        // Data rows
        for item in items {
            let nextY = curY - rowH
            writer.writeLine(layer: "BOM", start: SIMD2<Double>(x0, nextY), end: SIMD2<Double>(x1, nextY))

            var cellX = x0
            for col in table.columns {
                let colW = table.width(for: col)
                let val = col.value(for: item)
                writer.writeText(layer: "BOM", text: val, point: SIMD2<Double>(cellX + 2.0, curY - (rowH * 0.5)), height: 2.5, hAlign: 0, vAlign: 2)
                cellX += colW
            }
            curY = nextY
        }
    }

    // MARK: - DXF Table/Layer Writers

    private static func writeLinetype(_ writer: DXFWriter, name: String, description: String, length: Double = 0.0, dashes: [Double] = []) {
        writer.writeCode(0, "LTYPE")
        writer.writeCode(2, name)
        writer.writeCode(70, 0)
        writer.writeCode(3, description)
        writer.writeCode(72, 65)
        writer.writeCode(73, dashes.count)
        writer.writeCode(40, length)
        for dash in dashes {
            writer.writeCode(49, dash)
        }
    }

    private static func writeLayer(
        _ writer: DXFWriter,
        name: String,
        color: Int,
        lineweight: Int,
        linetype: String = "CONTINUOUS"
    ) {
        writer.writeCode(0, "LAYER")
        writer.writeCode(2, name)
        writer.writeCode(70, 0)
        writer.writeCode(62, color)
        writer.writeCode(6, linetype)
        writer.writeCode(370, lineweight) // Lineweight in 1/100 mm (25, 35, 50, 70)
    }

    private static func writeDXFArrowhead(
        writer: DXFWriter,
        layer: String,
        tip: SIMD2<Double>,
        from base: SIMD2<Double>,
        length: Double = 3.0,
        width: Double = 1.0
    ) {
        let delta = tip - base
        let dist = hypot(delta.x, delta.y)
        guard dist > 1e-4 else { return }
        let angle = atan2(delta.y, delta.x)

        let p1 = SIMD2<Double>(
            tip.x - (cos(angle) * length) + (sin(angle) * (width * 0.5)),
            tip.y - (sin(angle) * length) - (cos(angle) * (width * 0.5))
        )
        let p2 = SIMD2<Double>(
            tip.x - (cos(angle) * length) - (sin(angle) * (width * 0.5)),
            tip.y - (sin(angle) * length) + (cos(angle) * (width * 0.5))
        )

        // DXF SOLID triangular entity
        writer.writeCode(0, "SOLID")
        writer.writeCode(8, layer)
        writer.writeCode(10, tip.x)
        writer.writeCode(20, tip.y)
        writer.writeCode(30, 0.0)
        writer.writeCode(11, p1.x)
        writer.writeCode(21, p1.y)
        writer.writeCode(31, 0.0)
        writer.writeCode(12, p2.x)
        writer.writeCode(22, p2.y)
        writer.writeCode(32, 0.0)
        writer.writeCode(13, p2.x)
        writer.writeCode(23, p2.y)
        writer.writeCode(33, 0.0)
    }
}

// MARK: - DXF String Stream Helper

final class DXFWriter {
    var output = ""

    func writeCode(_ code: Int, _ value: String) {
        output.append("\(code)\n\(value)\n")
    }

    func writeCode(_ code: Int, _ value: Int) {
        output.append("\(code)\n\(value)\n")
    }

    func writeCode(_ code: Int, _ value: Double) {
        if abs(value) < 1e-9 {
            output.append("\(code)\n0.0\n")
        } else {
            output.append("\(code)\(String(format: "\n%.4f\n", value))")
        }
    }

    func writeSection(_ name: String) {
        writeCode(0, "SECTION")
        writeCode(2, name)
    }

    func writeEndSec() {
        writeCode(0, "ENDSEC")
    }

    func writeTable(_ name: String, count: Int) {
        writeCode(0, "TABLE")
        writeCode(2, name)
        writeCode(70, count)
    }

    func writeEndTab() {
        writeCode(0, "ENDTAB")
    }

    func writePoint2D(codeX: Int, _ pt: SIMD2<Double>) {
        writeCode(codeX, pt.x)
        writeCode(codeX + 10, pt.y)
    }

    func writePoint3D(codeX: Int, _ pt: SIMD3<Double>) {
        writeCode(codeX, pt.x)
        writeCode(codeX + 10, pt.y)
        writeCode(codeX + 20, pt.z)
    }

    func writeLine(layer: String, start: SIMD2<Double>, end: SIMD2<Double>, linetype: String? = nil) {
        writeCode(0, "LINE")
        writeCode(8, layer)
        if let linetype {
            writeCode(6, linetype)
        }
        writePoint3D(codeX: 10, SIMD3<Double>(start.x, start.y, 0.0))
        writePoint3D(codeX: 11, SIMD3<Double>(end.x, end.y, 0.0))
    }

    func writeCircle(layer: String, center: SIMD2<Double>, radius: Double) {
        writeCode(0, "CIRCLE")
        writeCode(8, layer)
        writePoint3D(codeX: 10, SIMD3<Double>(center.x, center.y, 0.0))
        writeCode(40, radius)
    }

    func writeArc(layer: String, center: SIMD2<Double>, radius: Double, startAngleDeg: Double, endAngleDeg: Double) {
        writeCode(0, "ARC")
        writeCode(8, layer)
        writePoint3D(codeX: 10, SIMD3<Double>(center.x, center.y, 0.0))
        writeCode(40, radius)
        writeCode(50, startAngleDeg)
        writeCode(51, endAngleDeg)
    }

    func writeText(
        layer: String,
        text: String,
        point: SIMD2<Double>,
        height: Double,
        rotation: Double = 0.0,
        hAlign: Int = 0,
        vAlign: Int = 0
    ) {
        guard !text.isEmpty else { return }
        writeCode(0, "TEXT")
        writeCode(8, layer)
        writePoint3D(codeX: 10, SIMD3<Double>(point.x, point.y, 0.0))
        writeCode(40, height)
        writeCode(1, text)
        if rotation != 0.0 {
            writeCode(50, rotation)
        }
        if hAlign != 0 || vAlign != 0 {
            writeCode(72, hAlign)
            writePoint3D(codeX: 11, SIMD3<Double>(point.x, point.y, 0.0))
            writeCode(73, vAlign)
        }
    }
}
