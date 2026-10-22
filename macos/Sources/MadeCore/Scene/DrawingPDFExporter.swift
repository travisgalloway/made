import Foundation
import CoreGraphics
import CoreText
import AppKit
import simd

/// Errors produced during drawing vector PDF export.
public enum DrawingPDFExporterError: Error, LocalizedError, Equatable {
    case contextCreationFailed
    case emptySheetsList
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return "Failed to create CoreGraphics PDF context."
        case .emptySheetsList:
            return "Cannot export an empty list of drawing sheets."
        case .writeFailed(let reason):
            return "Failed to write PDF: \(reason)"
        }
    }
}

/// Vector PDF generator for 2D engineering drawings using CoreGraphics and CoreText.
@MainActor
public enum DrawingPDFExporter {
    /// Standard Points per Millimeter factor at 72 DPI (72 / 25.4 ≈ 2.83464567 pt/mm).
    public static let pointsPerMM: Double = 72.0 / 25.4

    // Standard drafting line weights in millimeters converted to points
    public static let borderLineWidthPt: CGFloat = CGFloat(0.70 * pointsPerMM)
    public static let titleBlockFrameLineWidthPt: CGFloat = CGFloat(0.70 * pointsPerMM)
    public static let titleBlockGridLineWidthPt: CGFloat = CGFloat(0.35 * pointsPerMM)
    public static let visibleOutlineLineWidthPt: CGFloat = CGFloat(0.50 * pointsPerMM)
    public static let hiddenLineWidthPt: CGFloat = CGFloat(0.25 * pointsPerMM)
    public static let dimensionLineWidthPt: CGFloat = CGFloat(0.25 * pointsPerMM)
    public static let annotationLineWidthPt: CGFloat = CGFloat(0.25 * pointsPerMM)
    public static let balloonLineWidthPt: CGFloat = CGFloat(0.35 * pointsPerMM)
    public static let centerlineLineWidthPt: CGFloat = CGFloat(0.25 * pointsPerMM)
    public static let sectionCutLineWidthPt: CGFloat = CGFloat(0.70 * pointsPerMM)
    public static let bomFrameLineWidthPt: CGFloat = CGFloat(0.50 * pointsPerMM)
    public static let bomGridLineWidthPt: CGFloat = CGFloat(0.25 * pointsPerMM)

    // MARK: - Public Export API

    /// Exports multiple drawing sheets into a single multi-page vector PDF document.
    public static func exportPDF(sheets: [DrawingSheet], document: DocumentModel) throws -> Data {
        guard !sheets.isEmpty else {
            throw DrawingPDFExporterError.emptySheetsList
        }
        var bomMap: [UUID: [BOMItem]] = [:]
        for sheet in sheets {
            for table in sheet.bomTables {
                bomMap[table.id] = table.resolvedItems(from: document)
            }
        }
        return try renderSheetsToPDF(sheets: sheets, metadata: document.metadata, bomItemsMap: bomMap)
    }

    /// Exports a single drawing sheet to vector PDF data.
    public static func exportPDF(sheet: DrawingSheet, document: DocumentModel) throws -> Data {
        try exportPDF(sheets: [sheet], document: document)
    }

    /// Exports multiple drawing sheets to a destination file URL.
    public static func exportPDF(sheets: [DrawingSheet], document: DocumentModel, to url: URL) throws {
        let data = try exportPDF(sheets: sheets, document: document)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw DrawingPDFExporterError.writeFailed(error.localizedDescription)
        }
    }

    /// Exports a single drawing sheet to a destination file URL.
    public static func exportPDF(sheet: DrawingSheet, document: DocumentModel, to url: URL) throws {
        try exportPDF(sheets: [sheet], document: document, to: url)
    }

    /// Overload allowing decoupled testing without full DocumentModel instantiation.
    public static func exportPDF(
        sheets: [DrawingSheet],
        metadata: [String: String] = [:],
        bomItemsMap: [UUID: [BOMItem]] = [:]
    ) throws -> Data {
        guard !sheets.isEmpty else {
            throw DrawingPDFExporterError.emptySheetsList
        }
        return try renderSheetsToPDF(sheets: sheets, metadata: metadata, bomItemsMap: bomItemsMap)
    }

    /// Overload for a single sheet with metadata and resolved BOM items.
    public static func exportPDF(
        sheet: DrawingSheet,
        metadata: [String: String] = [:],
        bomItems: [BOMItem] = []
    ) throws -> Data {
        var map: [UUID: [BOMItem]] = [:]
        for table in sheet.bomTables {
            map[table.id] = bomItems.isEmpty ? [DrawingBOMTable.placeholderItem] : bomItems
        }
        return try renderSheetsToPDF(sheets: [sheet], metadata: metadata, bomItemsMap: map)
    }

    // MARK: - Core Rendering Engine

    private static func renderSheetsToPDF(
        sheets: [DrawingSheet],
        metadata: [String: String],
        bomItemsMap: [UUID: [BOMItem]]
    ) throws -> Data {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw DrawingPDFExporterError.contextCreationFailed
        }

        let firstSheet = sheets[0]
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(firstSheet.dimensionsPoints.width),
            height: CGFloat(firstSheet.dimensionsPoints.height)
        )

        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw DrawingPDFExporterError.contextCreationFailed
        }

        let totalSheets = sheets.count
        for (index, sheet) in sheets.enumerated() {
            let sheetIndex = index + 1
            var pageMediaBox = CGRect(
                x: 0,
                y: 0,
                width: CGFloat(sheet.dimensionsPoints.width),
                height: CGFloat(sheet.dimensionsPoints.height)
            )

            context.beginPage(mediaBox: &pageMediaBox)
            renderSheet(
                in: context,
                sheet: sheet,
                sheetIndex: sheetIndex,
                totalSheets: totalSheets,
                metadata: metadata,
                bomItemsMap: bomItemsMap
            )
            context.endPage()
        }

        context.closePDF()
        return pdfData as Data
    }

    private static func renderSheet(
        in context: CGContext,
        sheet: DrawingSheet,
        sheetIndex: Int,
        totalSheets: Int,
        metadata: [String: String],
        bomItemsMap: [UUID: [BOMItem]]
    ) {
        let sheetDimMM = sheet.dimensionsMM
        let sheetH_MM = sheetDimMM.height
        let sheetW_Pt = CGFloat(sheetDimMM.width * pointsPerMM)
        let sheetH_Pt = CGFloat(sheetDimMM.height * pointsPerMM)
        let marginMM = 10.0
        let marginPt = CGFloat(marginMM * pointsPerMM)

        // Helper to convert sheet mm coordinates (top-left origin) to PDF page points (bottom-left origin)
        func toPoint(_ sheetPtMM: SIMD2<Double>) -> CGPoint {
            CGPoint(
                x: CGFloat(sheetPtMM.x * pointsPerMM),
                y: CGFloat((sheetH_MM - sheetPtMM.y) * pointsPerMM)
            )
        }

        // 1. Paper Border (10 mm inset rectangle)
        let innerBorderRect = CGRect(
            x: marginPt,
            y: marginPt,
            width: max(0, sheetW_Pt - (marginPt * 2.0)),
            height: max(0, sheetH_Pt - (marginPt * 2.0))
        )
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
        context.setLineWidth(borderLineWidthPt)
        context.stroke(innerBorderRect)
        context.restoreGState()

        // 2. Zone Reference Marks (1-4 top/bottom, A-D left/right)
        renderZoneMarks(
            in: context,
            sheetW_Pt: sheetW_Pt,
            sheetH_Pt: sheetH_Pt,
            marginPt: marginPt
        )

        // 3. Title Block
        if sheet.titleBlockTemplate != .none {
            let titleProps = sheet.resolvedTitleBlockProperties(
                documentMetadata: metadata,
                sheetIndex: sheetIndex,
                totalSheets: totalSheets
            )
            renderTitleBlock(
                in: context,
                template: sheet.titleBlockTemplate,
                properties: titleProps,
                sheetW_Pt: sheetW_Pt,
                marginPt: marginPt
            )
        }

        // 4. Placed Drawing Views
        for view in sheet.views {
            renderDrawingView(
                in: context,
                view: view,
                sheet: sheet,
                toPoint: toPoint
            )
        }

        // 5. Annotations
        for annotation in sheet.annotations where annotation.isVisible {
            renderAnnotation(
                in: context,
                annotation: annotation,
                sheet: sheet,
                toPoint: toPoint
            )
        }

        // 6. BOM Tables
        for table in sheet.bomTables {
            let items = bomItemsMap[table.id] ?? [DrawingBOMTable.placeholderItem]
            renderBOMTable(
                in: context,
                table: table,
                items: items,
                sheetH_MM: sheetH_MM,
                toPoint: toPoint
            )
        }
    }

    // MARK: - Zone Reference Marks

    private static func renderZoneMarks(
        in context: CGContext,
        sheetW_Pt: CGFloat,
        sheetH_Pt: CGFloat,
        marginPt: CGFloat
    ) {
        let innerW = sheetW_Pt - (marginPt * 2.0)
        let innerH = sheetH_Pt - (marginPt * 2.0)
        let fontSize: CGFloat = 8.0
        let grayColor = CGColor(gray: 0.35, alpha: 1.0)

        // Digits 1 to 4 along horizontal margins
        let colStep = innerW / 4.0
        for i in 0..<4 {
            let label = "\(i + 1)"
            let xPos = marginPt + (CGFloat(i) + 0.5) * colStep

            // Top margin label (y near sheetH_Pt - marginPt/2)
            drawText(
                in: context,
                text: label,
                at: CGPoint(x: xPos, y: sheetH_Pt - (marginPt * 0.5)),
                fontSize: fontSize,
                color: grayColor,
                hAlign: .center,
                vAlign: .center
            )

            // Bottom margin label (y near marginPt/2)
            drawText(
                in: context,
                text: label,
                at: CGPoint(x: xPos, y: marginPt * 0.5),
                fontSize: fontSize,
                color: grayColor,
                hAlign: .center,
                vAlign: .center
            )
        }

        // Letters A to D along vertical margins
        let letters = ["A", "B", "C", "D"]
        let rowStep = innerH / 4.0
        for i in 0..<4 {
            let label = letters[i]
            // Note: In engineering drawings, A is top row, D is bottom row
            // Top row y is sheetH_Pt - marginPt - (0.5 * rowStep)
            let yPos = sheetH_Pt - marginPt - ((CGFloat(i) + 0.5) * rowStep)

            // Left margin label
            drawText(
                in: context,
                text: label,
                at: CGPoint(x: marginPt * 0.5, y: yPos),
                fontSize: fontSize,
                color: grayColor,
                hAlign: .center,
                vAlign: .center
            )

            // Right margin label
            drawText(
                in: context,
                text: label,
                at: CGPoint(x: sheetW_Pt - (marginPt * 0.5), y: yPos),
                fontSize: fontSize,
                color: grayColor,
                hAlign: .center,
                vAlign: .center
            )
        }
    }

    // MARK: - Title Block

    private static func renderTitleBlock(
        in context: CGContext,
        template: TitleBlockTemplate,
        properties: [String: String],
        sheetW_Pt: CGFloat,
        marginPt: CGFloat
    ) {
        let blockWidthMM: Double = (template == .minimal) ? 120.0 : 170.0
        let blockHeightMM: Double = (template == .minimal) ? 36.0 : 54.0

        let blockWidthPt = CGFloat(blockWidthMM * pointsPerMM)
        let blockHeightPt = CGFloat(blockHeightMM * pointsPerMM)

        // Title block sits in bottom-right corner inside the 10mm border
        let originX = sheetW_Pt - marginPt - blockWidthPt
        let originY = marginPt // bottom margin in PDF coordinates

        let frameRect = CGRect(x: originX, y: originY, width: blockWidthPt, height: blockHeightPt)

        context.saveGState()
        // White opaque fill
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(frameRect)

        // Outer border
        context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
        context.setLineWidth(titleBlockFrameLineWidthPt)
        context.stroke(frameRect)

        // Extract metadata values
        let title = properties["title"] ?? properties[CustomPropertyKey.description] ?? "Untitled"
        let partNum = properties[CustomPropertyKey.partNumber] ?? "DRW-001"
        let rev = properties[CustomPropertyKey.revision] ?? "A"
        let author = properties["author"] ?? NSFullUserName()
        let date = properties["date"] ?? ""
        let scale = properties["scale"] ?? "1:1"
        let sheetText = properties["sheet"] ?? "Sheet 1 of 1"
        let vendor = properties[CustomPropertyKey.vendor] ?? ""

        context.setLineWidth(titleBlockGridLineWidthPt)

        if template == .minimal {
            // Minimal layout: 2 rows
            let midY = originY + (blockHeightPt * 0.45)
            // Horizontal divider
            context.strokeLineSegments(between: [
                CGPoint(x: originX, y: midY),
                CGPoint(x: originX + blockWidthPt, y: midY)
            ])

            // Top row divider at 65% width
            let topDivX = originX + (blockWidthPt * 0.65)
            context.strokeLineSegments(between: [
                CGPoint(x: topDivX, y: midY),
                CGPoint(x: topDivX, y: originY + blockHeightPt)
            ])

            // Top row cells
            drawTitleBlockCell(
                in: context,
                label: "TITLE",
                value: title,
                rect: CGRect(x: originX, y: midY, width: blockWidthPt * 0.65, height: blockHeightPt * 0.55)
            )
            drawTitleBlockCell(
                in: context,
                label: "DWG NO.",
                value: partNum,
                rect: CGRect(x: topDivX, y: midY, width: blockWidthPt * 0.35, height: blockHeightPt * 0.55)
            )

            // Bottom row dividers (REV 20%, SCALE 30%, SHEET remainder)
            let b1X = originX + (blockWidthPt * 0.20)
            let b2X = originX + (blockWidthPt * 0.50)
            context.strokeLineSegments(between: [
                CGPoint(x: b1X, y: originY),
                CGPoint(x: b1X, y: midY),
                CGPoint(x: b2X, y: originY),
                CGPoint(x: b2X, y: midY)
            ])

            drawTitleBlockCell(
                in: context,
                label: "REV",
                value: rev,
                rect: CGRect(x: originX, y: originY, width: blockWidthPt * 0.20, height: blockHeightPt * 0.45)
            )
            drawTitleBlockCell(
                in: context,
                label: "SCALE",
                value: scale,
                rect: CGRect(x: b1X, y: originY, width: blockWidthPt * 0.30, height: blockHeightPt * 0.45)
            )
            drawTitleBlockCell(
                in: context,
                label: "SHEET",
                value: sheetText,
                rect: CGRect(x: b2X, y: originY, width: blockWidthPt * 0.50, height: blockHeightPt * 0.45)
            )
        } else {
            // Standard ISO / ANSI Title Block (3 rows or 2 rows + vendor)
            let hasVendor = !vendor.isEmpty
            let vendorH: CGFloat = hasVendor ? (blockHeightPt * 0.22) : 0.0
            let bottomH: CGFloat = blockHeightPt * 0.35
            let midH = blockHeightPt - vendorH - bottomH

            let bottomY = originY + bottomH
            let topY = originY + blockHeightPt - vendorH

            // Vendor header row
            if hasVendor {
                let vendorRect = CGRect(x: originX, y: topY, width: blockWidthPt, height: vendorH)
                context.setFillColor(CGColor(gray: 0.94, alpha: 1.0))
                context.fill(vendorRect)
                context.strokeLineSegments(between: [
                    CGPoint(x: originX, y: topY),
                    CGPoint(x: originX + blockWidthPt, y: topY)
                ])
                drawText(
                    in: context,
                    text: vendor.uppercased(),
                    at: CGPoint(x: originX + 6, y: topY + (vendorH * 0.5)),
                    fontSize: 8.5,
                    bold: true,
                    color: CGColor(gray: 0.1, alpha: 1.0),
                    hAlign: .left,
                    vAlign: .center
                )
            }

            // Horizontal divider above bottom row
            context.strokeLineSegments(between: [
                CGPoint(x: originX, y: bottomY),
                CGPoint(x: originX + blockWidthPt, y: bottomY)
            ])

            // Middle row divider (Title 60%, Drawing No 40%)
            let midDivX = originX + (blockWidthPt * 0.60)
            context.strokeLineSegments(between: [
                CGPoint(x: midDivX, y: bottomY),
                CGPoint(x: midDivX, y: topY)
            ])

            drawTitleBlockCell(
                in: context,
                label: "TITLE / DESCRIPTION",
                value: title,
                rect: CGRect(x: originX, y: bottomY, width: blockWidthPt * 0.60, height: midH)
            )
            drawTitleBlockCell(
                in: context,
                label: "DRAWING NO.",
                value: partNum,
                rect: CGRect(x: midDivX, y: bottomY, width: blockWidthPt * 0.40, height: midH)
            )

            // Bottom row columns: REV (15%), AUTHOR (28%), DATE (25%), SCALE (16%), SHEET (16%)
            let d1 = originX + (blockWidthPt * 0.15)
            let d2 = d1 + (blockWidthPt * 0.28)
            let d3 = d2 + (blockWidthPt * 0.25)
            let d4 = d3 + (blockWidthPt * 0.16)

            context.strokeLineSegments(between: [
                CGPoint(x: d1, y: originY), CGPoint(x: d1, y: bottomY),
                CGPoint(x: d2, y: originY), CGPoint(x: d2, y: bottomY),
                CGPoint(x: d3, y: originY), CGPoint(x: d3, y: bottomY),
                CGPoint(x: d4, y: originY), CGPoint(x: d4, y: bottomY)
            ])

            drawTitleBlockCell(
                in: context,
                label: "REV",
                value: rev,
                rect: CGRect(x: originX, y: originY, width: blockWidthPt * 0.15, height: bottomH)
            )
            drawTitleBlockCell(
                in: context,
                label: "AUTHOR",
                value: author,
                rect: CGRect(x: d1, y: originY, width: blockWidthPt * 0.28, height: bottomH)
            )
            drawTitleBlockCell(
                in: context,
                label: "DATE",
                value: date,
                rect: CGRect(x: d2, y: originY, width: blockWidthPt * 0.25, height: bottomH)
            )
            drawTitleBlockCell(
                in: context,
                label: "SCALE",
                value: scale,
                rect: CGRect(x: d3, y: originY, width: blockWidthPt * 0.16, height: bottomH)
            )
            drawTitleBlockCell(
                in: context,
                label: "SHEET",
                value: sheetText,
                rect: CGRect(x: d4, y: originY, width: sheetW_Pt - marginPt - d4, height: bottomH)
            )
        }
        context.restoreGState()
    }

    private static func drawTitleBlockCell(
        in context: CGContext,
        label: String,
        value: String,
        rect: CGRect
    ) {
        let padX: CGFloat = 4.0
        let padY: CGFloat = 3.0
        // Label at top of cell
        drawText(
            in: context,
            text: label,
            at: CGPoint(x: rect.minX + padX, y: rect.maxY - padY - 4.0),
            fontSize: 5.5,
            bold: true,
            color: CGColor(gray: 0.45, alpha: 1.0),
            hAlign: .left,
            vAlign: .center
        )
        // Value in middle/bottom of cell
        drawText(
            in: context,
            text: value,
            at: CGPoint(x: rect.minX + padX, y: rect.minY + padY + 4.5),
            fontSize: 7.5,
            bold: false,
            color: CGColor(gray: 0.0, alpha: 1.0),
            hAlign: .left,
            vAlign: .center
        )
    }

    // MARK: - Placed Drawing Views

    private static func renderDrawingView(
        in context: CGContext,
        view: DrawingView,
        sheet: DrawingSheet,
        toPoint: (SIMD2<Double>) -> CGPoint
    ) {
        let centerPt = toPoint(view.positionMM)
        let scale = CGFloat(view.scale.scaleFactor * pointsPerMM)

        // Helper to project view model 2D point into PDF point space
        func viewPointToPDF(_ pt: SIMD2<Double>) -> CGPoint {
            CGPoint(
                x: centerPt.x + (CGFloat(pt.x) * scale),
                y: centerPt.y + (CGFloat(pt.y) * scale)
            )
        }

        // Visible edges (0.50 mm stroke)
        if let hlr = view.cachedHLR {
            let visibleEdges = hlr.visibleEdges
            if !visibleEdges.isEmpty {
                context.saveGState()
                context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
                context.setLineWidth(visibleOutlineLineWidthPt)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                for edge in visibleEdges {
                    guard let first = edge.points2D.first else { continue }
                    context.beginPath()
                    context.move(to: viewPointToPDF(first))
                    for pt in edge.points2D.dropFirst() {
                        context.addLine(to: viewPointToPDF(pt))
                    }
                    context.strokePath()
                }
                context.restoreGState()
            }

            // Hidden edges (0.25 mm stroke, dashed)
            if view.displayStyle == .hiddenLinesVisible {
                let hiddenEdges = hlr.hiddenEdges
                if !hiddenEdges.isEmpty {
                    context.saveGState()
                    context.setStrokeColor(CGColor(gray: 0.3, alpha: 1.0))
                    context.setLineWidth(hiddenLineWidthPt)
                    let dashLengths: [CGFloat] = [3.0 * CGFloat(pointsPerMM), 2.0 * CGFloat(pointsPerMM)]
                    context.setLineDash(phase: 0, lengths: dashLengths)
                    for edge in hiddenEdges {
                        guard let first = edge.points2D.first else { continue }
                        context.beginPath()
                        context.move(to: viewPointToPDF(first))
                        for pt in edge.points2D.dropFirst() {
                            context.addLine(to: viewPointToPDF(pt))
                        }
                        context.strokePath()
                    }
                    context.restoreGState()
                }
            }

            // Crosshatch lines for section views
            if view.kind == .section || view.hatchPattern != nil {
                let pattern = view.hatchPattern ?? .standard
                if let bounds = hlr.bounds2D {
                    let hatchEdges = DrawingHatchGenerator.generateHatchLines(in: bounds, pattern: pattern)
                    if !hatchEdges.isEmpty {
                        context.saveGState()
                        context.setStrokeColor(CGColor(gray: 0.4, alpha: 1.0))
                        context.setLineWidth(CGFloat(0.25 * pointsPerMM))
                        for edge in hatchEdges {
                            guard let p1 = edge.startPoint2D, let p2 = edge.endPoint2D else { continue }
                            context.beginPath()
                            context.move(to: viewPointToPDF(p1))
                            context.addLine(to: viewPointToPDF(p2))
                            context.strokePath()
                        }
                        context.restoreGState()
                    }
                }
            }
        }

        // Detail View callout circle and label
        if view.kind == .detail, let detDef = view.detailDefinition {
            let radiusPt = CGFloat(detDef.radiusMM) * scale
            context.saveGState()
            context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            context.setLineWidth(visibleOutlineLineWidthPt)
            context.strokeEllipse(in: CGRect(
                x: centerPt.x - radiusPt,
                y: centerPt.y - radiusPt,
                width: radiusPt * 2.0,
                height: radiusPt * 2.0
            ))
            context.restoreGState()

            let labelText = "DETAIL \(detDef.label) · SCALE \(view.scale.displayString)"
            drawText(
                in: context,
                text: labelText,
                at: CGPoint(x: centerPt.x, y: centerPt.y - radiusPt - 10.0),
                fontSize: 8.0,
                bold: true,
                color: CGColor(gray: 0.0, alpha: 1.0),
                hAlign: .center,
                vAlign: .center
            )
        }

        // Parent overlays for dependent child views (section cutting lines, detail circles)
        let children = sheet.views.filter { $0.parentViewId == view.id }
        for child in children {
            if child.kind == .section, let secDef = child.sectionDefinition {
                let startPt = viewPointToPDF(secDef.startPointMM)
                let endPt = viewPointToPDF(secDef.endPointMM)

                context.saveGState()
                context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
                context.setLineWidth(sectionCutLineWidthPt)
                let dashLengths: [CGFloat] = [8.0, 2.0, 2.0, 2.0, 2.0, 2.0]
                context.setLineDash(phase: 0, lengths: dashLengths)
                context.beginPath()
                context.move(to: startPt)
                context.addLine(to: endPt)
                context.strokePath()
                context.restoreGState()

                // Arrows and reference labels
                let arrowLen: CGFloat = 12.0
                let arrOffset = CGPoint(
                    x: CGFloat(secDef.arrowDirection.x) * arrowLen,
                    y: CGFloat(secDef.arrowDirection.y) * arrowLen
                )

                drawArrowhead(in: context, tip: CGPoint(x: startPt.x + arrOffset.x, y: startPt.y + arrOffset.y), from: startPt)
                drawArrowhead(in: context, tip: CGPoint(x: endPt.x + arrOffset.x, y: endPt.y + arrOffset.y), from: endPt)

                drawText(
                    in: context,
                    text: secDef.label,
                    at: CGPoint(x: startPt.x + arrOffset.x * 1.5, y: startPt.y + arrOffset.y * 1.5),
                    fontSize: 9.0,
                    bold: true,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .center,
                    vAlign: .center
                )
                drawText(
                    in: context,
                    text: secDef.label,
                    at: CGPoint(x: endPt.x + arrOffset.x * 1.5, y: endPt.y + arrOffset.y * 1.5),
                    fontSize: 9.0,
                    bold: true,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .center,
                    vAlign: .center
                )
            } else if child.kind == .detail, let detDef = child.detailDefinition {
                let childCenter = viewPointToPDF(detDef.centerMM)
                let childRadius = CGFloat(detDef.radiusMM) * scale

                context.saveGState()
                context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
                context.setLineWidth(annotationLineWidthPt)
                let dashLengths: [CGFloat] = [4.0, 2.0]
                context.setLineDash(phase: 0, lengths: dashLengths)
                context.strokeEllipse(in: CGRect(
                    x: childCenter.x - childRadius,
                    y: childCenter.y - childRadius,
                    width: childRadius * 2.0,
                    height: childRadius * 2.0
                ))
                context.restoreGState()

                drawText(
                    in: context,
                    text: detDef.label,
                    at: CGPoint(x: childCenter.x + childRadius + 4.0, y: childCenter.y + childRadius + 4.0),
                    fontSize: 8.5,
                    bold: true,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .left,
                    vAlign: .center,
                    backgroundColor: CGColor(gray: 1.0, alpha: 0.85)
                )
            }
        }
    }

    // MARK: - Annotations

    private static func renderAnnotation(
        in context: CGContext,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        toPoint: (SIMD2<Double>) -> CGPoint
    ) {
        // Coordinate resolver: maps annotation point to PDF coordinates
        func toPDF(_ ptMM: SIMD2<Double>) -> CGPoint {
            if let viewId = annotation.viewId, let view = sheet.views.first(where: { $0.id == viewId }) {
                let sheetPt = SIMD2<Double>(
                    view.positionMM.x + (ptMM.x * view.scale.scaleFactor),
                    view.positionMM.y - (ptMM.y * view.scale.scaleFactor)
                )
                return toPoint(sheetPt)
            } else {
                return toPoint(ptMM)
            }
        }

        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
        context.setLineWidth(dimensionLineWidthPt)
        context.setFillColor(CGColor(gray: 0.0, alpha: 1.0))

        let arrowLen = CGFloat(sheet.draftingStandards.arrows.lengthPoints)
        let arrowWidth = CGFloat(sheet.draftingStandards.arrows.widthPoints)
        let arrowStyle = sheet.draftingStandards.arrows.style

        switch annotation.data {
        case .linear(let d):
            let p1 = toPDF(d.startPointMM)
            let p2 = toPDF(d.endPointMM)
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let len = hypot(dx, dy)
            guard len > 1e-4 else { break }

            let offsetPt = CGFloat(d.offsetMM * pointsPerMM)
            let nx = -dy / len
            let ny = dx / len

            let dimP1 = CGPoint(x: p1.x + nx * offsetPt, y: p1.y + ny * offsetPt)
            let dimP2 = CGPoint(x: p2.x + nx * offsetPt, y: p2.y + ny * offsetPt)

            // Extension overshoot (2 mm)
            let overshootPt = CGFloat(2.0 * pointsPerMM)
            let extP1End = CGPoint(x: dimP1.x + nx * overshootPt, y: dimP1.y + ny * overshootPt)
            let extP2End = CGPoint(x: dimP2.x + nx * overshootPt, y: dimP2.y + ny * overshootPt)

            // Extension lines
            context.strokeLineSegments(between: [p1, extP1End, p2, extP2End])

            // Dimension line
            context.strokeLineSegments(between: [dimP1, dimP2])

            // Arrowheads pointing outward from inside
            drawArrowhead(in: context, tip: dimP1, from: dimP2, length: arrowLen, width: arrowWidth, style: arrowStyle)
            drawArrowhead(in: context, tip: dimP2, from: dimP1, length: arrowLen, width: arrowWidth, style: arrowStyle)

            // Dimension text with white cutout
            let midPt = CGPoint(x: (dimP1.x + dimP2.x) * 0.5, y: (dimP1.y + dimP2.y) * 0.5)
            drawText(
                in: context,
                text: d.formattedText(using: sheet.draftingStandards),
                at: midPt,
                fontSize: 8.0,
                bold: false,
                color: CGColor(gray: 0.0, alpha: 1.0),
                hAlign: .center,
                vAlign: .center,
                backgroundColor: CGColor(gray: 1.0, alpha: 1.0)
            )

        case .angular(let d):
            let v = toPDF(d.vertexMM)
            let p1 = toPDF(d.startPointMM)
            let p2 = toPDF(d.endPointMM)
            let rPt = CGFloat(d.arcRadiusMM * pointsPerMM)

            let a1 = atan2(p1.y - v.y, p1.x - v.x)
            let a2 = atan2(p2.y - v.y, p2.x - v.x)

            // Extension lines from vertex
            context.strokeLineSegments(between: [v, p1, v, p2])

            // Arc
            context.beginPath()
            context.addArc(center: v, radius: rPt, startAngle: a1, endAngle: a2, clockwise: false)
            context.strokePath()

            // Arc arrowheads
            let tip1 = CGPoint(x: v.x + cos(a1) * rPt, y: v.y + sin(a1) * rPt)
            let tip2 = CGPoint(x: v.x + cos(a2) * rPt, y: v.y + sin(a2) * rPt)
            drawArrowhead(in: context, tip: tip1, angle: a1 + .pi / 2.0, length: arrowLen, width: arrowWidth, style: arrowStyle)
            drawArrowhead(in: context, tip: tip2, angle: a2 - .pi / 2.0, length: arrowLen, width: arrowWidth, style: arrowStyle)

            // Text
            let midAngle = (a1 + a2) * 0.5
            let textPt = CGPoint(x: v.x + cos(midAngle) * (rPt + 6.0), y: v.y + sin(midAngle) * (rPt + 6.0))
            drawText(
                in: context,
                text: d.formattedText(using: sheet.draftingStandards),
                at: textPt,
                fontSize: 8.0,
                color: CGColor(gray: 0.0, alpha: 1.0),
                hAlign: .center,
                vAlign: .center,
                backgroundColor: CGColor(gray: 1.0, alpha: 1.0)
            )

        case .radial(let d):
            let center = toPDF(d.centerMM)
            let arcPt = toPDF(d.arcPointMM)
            let dx = arcPt.x - center.x
            let dy = arcPt.y - center.y
            let dist = hypot(dx, dy)
            let dir = dist > 1e-4 ? CGPoint(x: dx / dist, y: dy / dist) : CGPoint(x: 1, y: 0)

            let shoulderLen: CGFloat = 10.0
            let shoulderPt = CGPoint(x: arcPt.x + dir.x * CGFloat(d.leaderOffsetMM * pointsPerMM), y: arcPt.y + dir.y * CGFloat(d.leaderOffsetMM * pointsPerMM))
            let endPt = CGPoint(x: shoulderPt.x + (dir.x >= 0 ? shoulderLen : -shoulderLen), y: shoulderPt.y)

            context.strokeLineSegments(between: [arcPt, shoulderPt, shoulderPt, endPt])
            drawArrowhead(in: context, tip: arcPt, from: shoulderPt, length: arrowLen, width: arrowWidth, style: arrowStyle)

            let textX = dir.x >= 0 ? endPt.x + 4.0 : endPt.x - 4.0
            drawText(
                in: context,
                text: d.formattedText(using: sheet.draftingStandards),
                at: CGPoint(x: textX, y: endPt.y),
                fontSize: 8.0,
                color: CGColor(gray: 0.0, alpha: 1.0),
                hAlign: dir.x >= 0 ? .left : .right,
                vAlign: .center
            )

        case .ordinate(let d):
            let datum = toPDF(d.datumOriginMM)
            let loc = toPDF(d.locationMM)
            let offsetPt = CGFloat(d.jogOffsetMM * pointsPerMM)

            // Datum circle
            context.strokeEllipse(in: CGRect(x: datum.x - 2, y: datum.y - 2, width: 4, height: 4))

            // Extension line
            let textPt: CGPoint
            if d.axis == .x {
                let extEnd = CGPoint(x: loc.x, y: loc.y + offsetPt)
                context.strokeLineSegments(between: [loc, extEnd])
                textPt = CGPoint(x: extEnd.x, y: extEnd.y + 4.0)
            } else {
                let extEnd = CGPoint(x: loc.x + offsetPt, y: loc.y)
                context.strokeLineSegments(between: [loc, extEnd])
                textPt = CGPoint(x: extEnd.x + 4.0, y: extEnd.y)
            }

            drawText(
                in: context,
                text: d.formattedText(using: sheet.draftingStandards),
                at: textPt,
                fontSize: 8.0,
                color: CGColor(gray: 0.0, alpha: 1.0),
                hAlign: .center,
                vAlign: .center
            )

        case .baseline(let d):
            let base = toPDF(d.basePointMM)
            for (idx, target) in d.targetPointsMM.enumerated() {
                let tPt = toPDF(target)
                let stepOffset = CGFloat(d.stackOffsetMM(forTargetIndex: idx) * pointsPerMM)
                let bDim = CGPoint(x: base.x, y: base.y + stepOffset)
                let tDim = CGPoint(x: tPt.x, y: tPt.y + stepOffset)

                context.strokeLineSegments(between: [base, bDim, tPt, tDim, bDim, tDim])
                drawArrowhead(in: context, tip: bDim, from: tDim, length: arrowLen, width: arrowWidth, style: arrowStyle)
                drawArrowhead(in: context, tip: tDim, from: bDim, length: arrowLen, width: arrowWidth, style: arrowStyle)

                let text = d.formattedText(forTargetIndex: idx, using: sheet.draftingStandards)
                drawText(
                    in: context,
                    text: text,
                    at: CGPoint(x: (bDim.x + tDim.x) * 0.5, y: bDim.y),
                    fontSize: 7.5,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .center,
                    vAlign: .center,
                    backgroundColor: CGColor(gray: 1.0, alpha: 1.0)
                )
            }

        case .note(let d):
            let pt = toPDF(d.positionMM)
            drawText(
                in: context,
                text: d.text,
                at: pt,
                fontSize: CGFloat(d.fontSizePt),
                color: CGColor(gray: 0.0, alpha: 1.0),
                hAlign: .left,
                vAlign: .center
            )

        case .leader(let d):
            let arrow = toPDF(d.arrowPointMM)
            let elbow = toPDF(d.elbowPointMM)
            let isRight = d.elbowPointMM.x >= d.arrowPointMM.x
            let shoulderPtMM = SIMD2<Double>(d.elbowPointMM.x + (isRight ? d.landingLengthMM : -d.landingLengthMM), d.elbowPointMM.y)
            let shoulder = toPDF(shoulderPtMM)

            context.strokeLineSegments(between: [arrow, elbow, elbow, shoulder])
            drawArrowhead(in: context, tip: arrow, from: elbow, length: arrowLen, width: arrowWidth, style: arrowStyle)

            drawText(
                in: context,
                text: d.text,
                at: CGPoint(x: shoulder.x + (isRight ? 4.0 : -4.0), y: shoulder.y),
                fontSize: CGFloat(d.fontSizePt),
                color: CGColor(gray: 0.0, alpha: 1.0),
                hAlign: isRight ? .left : .right,
                vAlign: .center
            )

        case .centerMark(let d):
            let c = toPDF(d.centerMM)
            let s = CGFloat(((d.markSizeMM * 0.5) + d.extensionMM) * pointsPerMM)
            let gap = CGFloat(1.5 * pointsPerMM)

            context.strokeLineSegments(between: [
                CGPoint(x: c.x - s, y: c.y), CGPoint(x: c.x - gap, y: c.y),
                CGPoint(x: c.x + gap, y: c.y), CGPoint(x: c.x + s, y: c.y),
                CGPoint(x: c.x, y: c.y - s), CGPoint(x: c.x, y: c.y - gap),
                CGPoint(x: c.x, y: c.y + gap), CGPoint(x: c.x, y: c.y + s)
            ])

        case .centerline(let d):
            let p1 = toPDF(d.startPointMM)
            let p2 = toPDF(d.endPointMM)
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let len = hypot(dx, dy)
            guard len > 1e-4 else { break }

            let ext = CGFloat(d.extensionMM * pointsPerMM)
            let dir = CGPoint(x: dx / len, y: dy / len)
            let extP1 = CGPoint(x: p1.x - dir.x * ext, y: p1.y - dir.y * ext)
            let extP2 = CGPoint(x: p2.x + dir.x * ext, y: p2.y + dir.y * ext)

            context.saveGState()
            context.setLineWidth(centerlineLineWidthPt)
            let dashLengths: [CGFloat] = [8.0, 2.0, 2.0, 2.0]
            context.setLineDash(phase: 0, lengths: dashLengths)
            context.strokeLineSegments(between: [extP1, extP2])
            context.restoreGState()

        case .holeCallout(let d):
            let anchor = toPDF(d.anchorPointMM)
            let elbow = toPDF(d.elbowPointMM)
            let landingPt = CGPoint(x: elbow.x + CGFloat(d.landingLengthMM * pointsPerMM), y: elbow.y)

            context.strokeLineSegments(between: [anchor, elbow, elbow, landingPt])
            drawArrowhead(in: context, tip: anchor, from: elbow, length: arrowLen, width: arrowWidth, style: arrowStyle)

            let lines = d.formattedCalloutLines
            for (idx, line) in lines.enumerated() {
                let lineY = elbow.y + 4.0 - (CGFloat(idx) * 9.5)
                drawText(
                    in: context,
                    text: line,
                    at: CGPoint(x: landingPt.x + 4.0, y: lineY),
                    fontSize: 7.5,
                    bold: idx == 0,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .left,
                    vAlign: .center
                )
            }

        case .balloon(let d):
            let anchor = toPDF(d.anchorPointMM)
            let center = toPDF(d.balloonCenterMM)
            let rPt = CGFloat(d.sizeMM * 0.5 * pointsPerMM)

            let dx = center.x - anchor.x
            let dy = center.y - anchor.y
            let dist = hypot(dx, dy)
            let contactPt: CGPoint
            if dist > rPt {
                contactPt = CGPoint(x: center.x - (dx / dist) * rPt, y: center.y - (dy / dist) * rPt)
            } else {
                contactPt = center
            }

            // Leader
            context.strokeLineSegments(between: [anchor, contactPt])
            drawArrowhead(in: context, tip: anchor, from: contactPt, length: arrowLen, width: arrowWidth, style: arrowStyle)

            // Balloon bubble
            context.saveGState()
            context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            context.setLineWidth(balloonLineWidthPt)

            let bubbleRect = CGRect(x: center.x - rPt, y: center.y - rPt, width: rPt * 2.0, height: rPt * 2.0)
            switch d.shape {
            case .circular:
                context.fillEllipse(in: bubbleRect)
                context.strokeEllipse(in: bubbleRect)
                drawText(
                    in: context,
                    text: d.formattedText,
                    at: center,
                    fontSize: rPt * 0.85,
                    bold: true,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .center,
                    vAlign: .center
                )

            case .splitCircular:
                context.fillEllipse(in: bubbleRect)
                context.strokeEllipse(in: bubbleRect)
                context.strokeLineSegments(between: [
                    CGPoint(x: center.x - rPt, y: center.y),
                    CGPoint(x: center.x + rPt, y: center.y)
                ])
                drawText(
                    in: context,
                    text: d.formattedText,
                    at: CGPoint(x: center.x, y: center.y + (rPt * 0.45)),
                    fontSize: rPt * 0.65,
                    bold: true,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .center,
                    vAlign: .center
                )
                drawText(
                    in: context,
                    text: d.formattedQuantityText,
                    at: CGPoint(x: center.x, y: center.y - (rPt * 0.45)),
                    fontSize: rPt * 0.65,
                    bold: false,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .center,
                    vAlign: .center
                )

            case .box:
                context.fill(bubbleRect)
                context.stroke(bubbleRect)
                let text = d.showQuantity ? "\(d.formattedText) (\(d.formattedQuantityText))" : d.formattedText
                drawText(
                    in: context,
                    text: text,
                    at: center,
                    fontSize: rPt * 0.75,
                    bold: true,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .center,
                    vAlign: .center
                )

            case .hexagon:
                context.beginPath()
                for i in 0..<6 {
                    let angle = (Double(i) * .pi / 3.0) - (.pi / 6.0)
                    let p = CGPoint(x: center.x + CGFloat(cos(angle)) * rPt, y: center.y + CGFloat(sin(angle)) * rPt)
                    if i == 0 { context.move(to: p) } else { context.addLine(to: p) }
                }
                context.closePath()
                context.fillPath()
                context.beginPath()
                for i in 0..<6 {
                    let angle = (Double(i) * .pi / 3.0) - (.pi / 6.0)
                    let p = CGPoint(x: center.x + CGFloat(cos(angle)) * rPt, y: center.y + CGFloat(sin(angle)) * rPt)
                    if i == 0 { context.move(to: p) } else { context.addLine(to: p) }
                }
                context.closePath()
                context.strokePath()
                drawText(
                    in: context,
                    text: d.formattedText,
                    at: center,
                    fontSize: rPt * 0.8,
                    bold: true,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .center,
                    vAlign: .center
                )

            case .none:
                let text = d.showQuantity ? "\(d.formattedText) (\(d.formattedQuantityText))" : d.formattedText
                drawText(
                    in: context,
                    text: text,
                    at: center,
                    fontSize: rPt * 0.85,
                    bold: true,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .center,
                    vAlign: .center,
                    backgroundColor: CGColor(gray: 1.0, alpha: 1.0)
                )
            }
            context.restoreGState()
        }
        context.restoreGState()
    }

    // MARK: - BOM Tables

    private static func renderBOMTable(
        in context: CGContext,
        table: DrawingBOMTable,
        items: [BOMItem],
        sheetH_MM: Double,
        toPoint: (SIMD2<Double>) -> CGPoint
    ) {
        let totalW_Pt = CGFloat(table.totalWidthMM * pointsPerMM)
        let rowH_Pt = CGFloat(table.rowHeightMM * pointsPerMM)
        let titleH_Pt = table.showTitle ? rowH_Pt : 0.0
        let headerH_Pt = rowH_Pt
        let dataH_Pt = CGFloat(max(1, items.count)) * rowH_Pt
        let totalH_Pt = titleH_Pt + headerH_Pt + dataH_Pt

        // Table origin in sheet mm: top-left corner
        let originPt = toPoint(table.positionMM)
        // In PDF coordinates (y up): table extends DOWN from originPt.y
        let tableMinY = originPt.y - totalH_Pt
        let frameRect = CGRect(x: originPt.x, y: tableMinY, width: totalW_Pt, height: totalH_Pt)

        context.saveGState()
        // White background fill
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(frameRect)

        // Outer frame
        context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
        context.setLineWidth(bomFrameLineWidthPt)
        context.stroke(frameRect)

        context.setLineWidth(bomGridLineWidthPt)

        var curTopY = originPt.y

        // Title row
        if table.showTitle {
            let rowBottomY = curTopY - rowH_Pt
            context.strokeLineSegments(between: [
                CGPoint(x: originPt.x, y: rowBottomY),
                CGPoint(x: originPt.x + totalW_Pt, y: rowBottomY)
            ])
            drawText(
                in: context,
                text: table.title,
                at: CGPoint(x: originPt.x + (totalW_Pt * 0.5), y: curTopY - (rowH_Pt * 0.5)),
                fontSize: CGFloat(table.fontSizePt),
                bold: true,
                color: CGColor(gray: 0.0, alpha: 1.0),
                hAlign: .center,
                vAlign: .center
            )
            curTopY = rowBottomY
        }

        // Header row
        let headerBottomY = curTopY - rowH_Pt
        context.strokeLineSegments(between: [
            CGPoint(x: originPt.x, y: headerBottomY),
            CGPoint(x: originPt.x + totalW_Pt, y: headerBottomY)
        ])

        var curColX = originPt.x
        for (colIdx, col) in table.columns.enumerated() {
            let colW_Pt = CGFloat(table.width(for: col) * pointsPerMM)
            if colIdx > 0 {
                context.strokeLineSegments(between: [
                    CGPoint(x: curColX, y: tableMinY),
                    CGPoint(x: curColX, y: curTopY)
                ])
            }
            drawText(
                in: context,
                text: col.displayName,
                at: CGPoint(x: curColX + (colW_Pt * 0.5), y: curTopY - (rowH_Pt * 0.5)),
                fontSize: CGFloat(table.fontSizePt * 0.9),
                bold: true,
                color: CGColor(gray: 0.0, alpha: 1.0),
                hAlign: .center,
                vAlign: .center
            )
            curColX += colW_Pt
        }
        curTopY = headerBottomY

        // Data rows
        for item in items {
            let nextRowY = curTopY - rowH_Pt
            context.strokeLineSegments(between: [
                CGPoint(x: originPt.x, y: nextRowY),
                CGPoint(x: originPt.x + totalW_Pt, y: nextRowY)
            ])

            var cellX = originPt.x
            for col in table.columns {
                let colW_Pt = CGFloat(table.width(for: col) * pointsPerMM)
                let val = col.value(for: item)
                drawText(
                    in: context,
                    text: val,
                    at: CGPoint(x: cellX + 4.0, y: curTopY - (rowH_Pt * 0.5)),
                    fontSize: CGFloat(table.fontSizePt * 0.85),
                    bold: false,
                    color: CGColor(gray: 0.0, alpha: 1.0),
                    hAlign: .left,
                    vAlign: .center
                )
                cellX += colW_Pt
            }
            curTopY = nextRowY
        }

        context.restoreGState()
    }

    // MARK: - Drawing Helpers

    private static func drawArrowhead(
        in context: CGContext,
        tip: CGPoint,
        from base: CGPoint,
        length: CGFloat = 8.0,
        width: CGFloat = 2.8,
        style: ArrowheadStyle = .closedFilled
    ) {
        let dx = tip.x - base.x
        let dy = tip.y - base.y
        let angle = atan2(dy, dx)
        drawArrowhead(in: context, tip: tip, angle: angle, length: length, width: width, style: style)
    }

    private static func drawArrowhead(
        in context: CGContext,
        tip: CGPoint,
        angle: CGFloat,
        length: CGFloat = 8.0,
        width: CGFloat = 2.8,
        style: ArrowheadStyle = .closedFilled
    ) {
        let p1 = CGPoint(
            x: tip.x - (cos(angle) * length) + (sin(angle) * (width * 0.5)),
            y: tip.y - (sin(angle) * length) - (cos(angle) * (width * 0.5))
        )
        let p2 = CGPoint(
            x: tip.x - (cos(angle) * length) - (sin(angle) * (width * 0.5)),
            y: tip.y - (sin(angle) * length) + (cos(angle) * (width * 0.5))
        )

        context.saveGState()
        switch style {
        case .closedFilled:
            context.setFillColor(CGColor(gray: 0.0, alpha: 1.0))
            context.beginPath()
            context.move(to: tip)
            context.addLine(to: p1)
            context.addLine(to: p2)
            context.closePath()
            context.fillPath()
        case .open:
            context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            context.setLineWidth(1.0)
            context.beginPath()
            context.move(to: p1)
            context.addLine(to: tip)
            context.addLine(to: p2)
            context.strokePath()
        case .tick:
            let tickAngle = angle + .pi * 0.25
            let half = length * 0.6
            context.setStrokeColor(CGColor(gray: 0.0, alpha: 1.0))
            context.setLineWidth(1.2)
            context.beginPath()
            context.move(to: CGPoint(x: tip.x - cos(tickAngle) * half, y: tip.y - sin(tickAngle) * half))
            context.addLine(to: CGPoint(x: tip.x + cos(tickAngle) * half, y: tip.y + sin(tickAngle) * half))
            context.strokePath()
        }
        context.restoreGState()
    }

    public enum TextHorizontalAlignment {
        case left
        case center
        case right
    }

    public enum TextVerticalAlignment {
        case top
        case center
        case bottom
        case baseline
    }

    private static func drawText(
        in context: CGContext,
        text: String,
        at point: CGPoint,
        fontSize: CGFloat,
        bold: Bool = false,
        color: CGColor = CGColor(gray: 0.0, alpha: 1.0),
        hAlign: TextHorizontalAlignment = .left,
        vAlign: TextVerticalAlignment = .baseline,
        backgroundColor: CGColor? = nil,
        bgPadding: CGFloat = 2.0
    ) {
        guard !text.isEmpty else { return }

        let font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: color) ?? .black
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString as CFAttributedString)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let lineHeight = ascent + descent

        var textX = point.x
        switch hAlign {
        case .left:
            textX = point.x
        case .center:
            textX = point.x - (lineWidth * 0.5)
        case .right:
            textX = point.x - lineWidth
        }

        var textY = point.y
        switch vAlign {
        case .baseline:
            textY = point.y
        case .center:
            textY = point.y - (ascent - descent) * 0.5
        case .top:
            textY = point.y - ascent
        case .bottom:
            textY = point.y + descent
        }

        if let bg = backgroundColor {
            context.saveGState()
            context.setFillColor(bg)
            let bgRect = CGRect(
                x: textX - bgPadding,
                y: textY - descent - bgPadding,
                width: lineWidth + (bgPadding * 2.0),
                height: lineHeight + (bgPadding * 2.0)
            )
            context.fill(bgRect)
            context.restoreGState()
        }

        context.saveGState()
        context.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
