import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct DrawingViewTests {

    @Test func testScaleFactorAndPresets() {
        let full = DrawingViewScale.full
        #expect(full.scaleFactor == 1.0)
        #expect(full.displayString == "1:1")

        let half = DrawingViewScale.half
        #expect(half.scaleFactor == 0.5)
        #expect(half.displayString == "1:2")

        let double = DrawingViewScale.double
        #expect(double.scaleFactor == 2.0)
        #expect(double.displayString == "2:1")

        let tenth = DrawingViewScale.tenth
        #expect(tenth.scaleFactor == 0.1)
        #expect(tenth.displayString == "1:10")

        let fifth = DrawingViewScale.fifth
        #expect(fifth.scaleFactor == 0.2)
        #expect(fifth.displayString == "1:5")

        let quintuple = DrawingViewScale.quintuple
        #expect(quintuple.scaleFactor == 5.0)
        #expect(quintuple.displayString == "5:1")
    }

    @Test func testScaleParsingAndEdgeCases() {
        #expect(DrawingViewScale.parse("1:1") == .full)
        #expect(DrawingViewScale.parse("1/2") == .half)
        #expect(DrawingViewScale.parse(" 2 : 1 ") == .double)
        #expect(DrawingViewScale.parse("1:5") == .fifth)
        #expect(DrawingViewScale.parse("1:10") == .tenth)
        #expect(DrawingViewScale.parse("5:1") == .quintuple)

        // Single number parsing
        let single = DrawingViewScale.parse("2.5")
        #expect(single != nil)
        #expect(single?.scaleFactor == 2.5)

        // Malformed and zero/negative scales
        #expect(DrawingViewScale.parse("") == nil)
        #expect(DrawingViewScale.parse("abc") == nil)
        #expect(DrawingViewScale.parse("1:0") == nil)
        #expect(DrawingViewScale.parse("-1:2") == nil)
        #expect(DrawingViewScale.parse("1:-2") == nil)

        // Initializer clamps denominator to >= 1e-4
        let clamped = DrawingViewScale(1, 0)
        #expect(clamped.denominator >= 1e-4)
        #expect(clamped.scaleFactor <= 10000.0)
    }

    @Test func testProjectionAngleDerivations() {
        let first = DrawingProjectionAngle.firstAngle
        let third = DrawingProjectionAngle.thirdAngle

        // DoD 4: Third-angle projection from front view:
        // right placement yields right view
        #expect(third.projectedView(from: .front, direction: .right) == .right)
        // left placement yields left view
        #expect(third.projectedView(from: .front, direction: .left) == .left)
        // above placement yields top view
        #expect(third.projectedView(from: .front, direction: .above) == .top)
        // below placement yields bottom view
        #expect(third.projectedView(from: .front, direction: .below) == .bottom)

        // DoD 3: First-angle projection from front view:
        // right placement yields left view
        #expect(first.projectedView(from: .front, direction: .right) == .left)
        // left placement yields right view
        #expect(first.projectedView(from: .front, direction: .left) == .right)
        // above placement yields bottom view
        #expect(first.projectedView(from: .front, direction: .above) == .bottom)
        // below placement yields top view
        #expect(first.projectedView(from: .front, direction: .below) == .top)

        // Isometric directions
        #expect(third.projectedView(from: .front, direction: .isometricTopRight) == .isometricNE)
        #expect(first.projectedView(from: .front, direction: .isometricTopRight) == .isometricSW)
    }

    @Test func testDisplayStyleMapping() {
        let visibleOnly = DrawingDisplayStyle.visibleLinesOnly
        #expect(!visibleOnly.hlrOptions.includeHidden)
        #expect(visibleOnly.hlrOptions.includeTangent)
        #expect(visibleOnly.hlrOptions.includeSilhouette)

        let hiddenVis = DrawingDisplayStyle.hiddenLinesVisible
        #expect(hiddenVis.hlrOptions.includeHidden)
        #expect(hiddenVis.hlrOptions.includeTangent)
        #expect(hiddenVis.hlrOptions.includeSilhouette)

        let shaded = DrawingDisplayStyle.shaded
        #expect(!shaded.hlrOptions.includeHidden)
    }

    @Test func testDocumentModelDrawingViewMutationsAndUndo() {
        let doc = DocumentModel(documentType: .drawing)
        #expect(doc.sheets.count == 1)
        guard let sheet = doc.activeSheet else {
            Issue.record("Expected active sheet")
            return
        }

        // Add base view
        let baseView = DrawingView(
            name: "Front View",
            kind: .base,
            standardView: .front,
            positionMM: SIMD2(120, 150),
            scale: .full,
            displayStyle: .visibleLinesOnly
        )
        let added = doc.addDrawingView(baseView, to: sheet.id)
        #expect(added != nil)
        #expect(doc.activeSheet?.views.count == 1)
        #expect(doc.selectedDrawingViewId == baseView.id)
        #expect(doc.selectedDrawingView?.name == "Front View")

        // Undo add
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.views.isEmpty == true)

        // Redo add
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.views.count == 1)
        #expect(doc.activeSheet?.views.first?.id == baseView.id)
    }

    @Test func testDocumentModelRemoveDrawingViewUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let view = DrawingView(name: "Detail View", kind: .base, standardView: .top)
        _ = doc.addDrawingView(view, to: sheet.id)
        #expect(doc.activeSheet?.views.count == 1)
        doc.undoManager?.removeAllActions()

        let removed = doc.removeDrawingView(id: view.id, from: sheet.id)
        #expect(removed)
        #expect(doc.activeSheet?.views.isEmpty == true)

        // Undo removal
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.views.count == 1)
        #expect(doc.activeSheet?.views.first?.id == view.id)

        // Redo removal
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.views.isEmpty == true)
    }

    @Test func testDocumentModelUpdateDrawingViewUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let view = DrawingView(name: "Front", kind: .base, standardView: .front, displayStyle: .visibleLinesOnly)
        _ = doc.addDrawingView(view, to: sheet.id)
        doc.undoManager?.removeAllActions()

        var updatedView = view
        updatedView.name = "Front Re-styled"
        updatedView.displayStyle = .hiddenLinesVisible
        let updated = doc.updateDrawingView(updatedView, on: sheet.id)
        #expect(updated)
        #expect(doc.activeSheet?.views.first?.name == "Front Re-styled")
        #expect(doc.activeSheet?.views.first?.displayStyle == .hiddenLinesVisible)

        // Undo update
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.views.first?.name == "Front")
        #expect(doc.activeSheet?.views.first?.displayStyle == .visibleLinesOnly)

        // Redo update
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.views.first?.name == "Front Re-styled")
        #expect(doc.activeSheet?.views.first?.displayStyle == .hiddenLinesVisible)
    }

    @Test func testDocumentModelRepositionDrawingViewUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let view = DrawingView(name: "Iso View", kind: .base, standardView: .isometric, positionMM: SIMD2(100, 100))
        _ = doc.addDrawingView(view, to: sheet.id)
        doc.undoManager?.removeAllActions()

        let moved = doc.repositionDrawingView(id: view.id, positionMM: SIMD2(220, 180), on: sheet.id)
        #expect(moved)
        #expect(doc.activeSheet?.views.first?.positionMM == SIMD2(220, 180))

        // Undo reposition
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.views.first?.positionMM == SIMD2(100, 100))

        // Redo reposition
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.views.first?.positionMM == SIMD2(220, 180))
    }

    @Test func testParentViewDeletionUnlinksChildren() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let baseView = DrawingView(name: "Base View", kind: .base, standardView: .front)
        _ = doc.addDrawingView(baseView, to: sheet.id)

        let childView = DrawingView(
            name: "Child View",
            kind: .projected,
            standardView: .right,
            parentViewId: baseView.id,
            projectionDirection: .right
        )
        _ = doc.addDrawingView(childView, to: sheet.id)

        #expect(doc.activeSheet?.views.count == 2)
        #expect(doc.activeSheet?.views.first(where: { $0.id == childView.id })?.parentViewId == baseView.id)
        #expect(doc.activeSheet?.views.first(where: { $0.id == childView.id })?.kind == .projected)

        // Remove base view
        let removed = doc.removeDrawingView(id: baseView.id, from: sheet.id)
        #expect(removed)
        #expect(doc.activeSheet?.views.count == 1)

        // Verify child was unlinked cleanly
        let remaining = doc.activeSheet?.views.first
        #expect(remaining?.id == childView.id)
        #expect(remaining?.parentViewId == nil)
        #expect(remaining?.kind == .base)
    }

    @Test func testLegacyDrawingSheetDecodingDefaults() throws {
        // Legacy DrawingSheet JSON without projectionAngle or views
        let legacySheetJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "name": "Legacy Sheet",
            "size": "isoA3",
            "orientation": "landscape",
            "scale": "1:1",
            "titleBlockTemplate": "isoStandard",
            "customProperties": {}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let sheet = try decoder.decode(DrawingSheet.self, from: legacySheetJSON)

        #expect(sheet.name == "Legacy Sheet")
        #expect(sheet.size == .isoA3)
        // ISO defaults to first angle
        #expect(sheet.projectionAngle == .firstAngle)
        // Views defaults to empty array
        #expect(sheet.views.isEmpty)

        // ANSI sheet defaults to third angle
        let ansiSheetJSON = """
        {
            "id": "22222222-3333-4444-5555-666666666666",
            "name": "ANSI Sheet",
            "size": "ansiB",
            "orientation": "landscape",
            "scale": "1:1",
            "titleBlockTemplate": "ansiStandard",
            "customProperties": {}
        }
        """.data(using: .utf8)!

        let ansiSheet = try decoder.decode(DrawingSheet.self, from: ansiSheetJSON)
        #expect(ansiSheet.size == .ansiB)
        #expect(ansiSheet.projectionAngle == .thirdAngle)
        #expect(ansiSheet.views.isEmpty)
    }

    @Test func testDrawingViewKindsAndDisplayNames() {
        #expect(DrawingViewKind.base.displayName == "Base")
        #expect(DrawingViewKind.projected.displayName == "Projected")
        #expect(DrawingViewKind.section.displayName == "Section")
        #expect(DrawingViewKind.detail.displayName == "Detail")
        #expect(DrawingViewKind.auxiliary.displayName == "Auxiliary")
        #expect(DrawingViewKind.broken.displayName == "Broken")
        #expect(DrawingViewKind.allCases.count == 6)
    }

    @Test func testConfigurationDefinitionsAndClamping() {
        // Section definition: zero-length defaults to horizontal line
        let secZero = SectionLineDefinition(startPointMM: SIMD2(10, 10), endPointMM: SIMD2(10, 10))
        #expect(simd_distance(secZero.startPointMM, secZero.endPointMM) > 1.0)
        #expect(abs(simd_length(secZero.arrowDirection) - 1.0) < 1e-6)

        // Hatch pattern spacing minimum clamp
        let hatch = HatchPatternDefinition(style: .ansi32, angleDegrees: 30.0, spacingMM: 0.1)
        #expect(hatch.spacingMM >= 0.5)
        #expect(HatchPatternStyle.allCases.count == 4)

        // Detail circle radius minimum clamp
        let detail = DetailCircleDefinition(label: "D", centerMM: SIMD2(5, 5), radiusMM: -10.0)
        #expect(detail.radiusMM == 1.0)

        // Break view definition start/end ordering and compression offset
        let brk = BreakViewDefinition(orientation: .horizontal, startMM: 20.0, endMM: -10.0, gapMM: 5.0, style: .zigzag)
        #expect(brk.startMM == -10.0)
        #expect(brk.endMM == 20.0)
        #expect(brk.breakSpan == 30.0)
        #expect(brk.compressionOffset == 25.0)

        // Negative gap is clamped
        let brk2 = BreakViewDefinition(orientation: .vertical, startMM: 0, endMM: 10, gapMM: -3)
        #expect(brk2.gapMM >= 1.0)
    }

    @Test func testDrawingHatchGeneratorStyles() {
        let bounds = BoundingBox2D(min: SIMD2(-20, -20), max: SIMD2(20, 20))

        // ANSI31
        let ansi31Edges = DrawingHatchGenerator.generateHatchLines(
            in: bounds,
            pattern: HatchPatternDefinition(style: .ansi31, angleDegrees: 45.0, spacingMM: 5.0)
        )
        #expect(!ansi31Edges.isEmpty)
        for edge in ansi31Edges {
            #expect(edge.points2D.count == 2)
            #expect(edge.category.isVisible)
        }

        // ANSI32 produces paired lines (more edges than ANSI31)
        let ansi32Edges = DrawingHatchGenerator.generateHatchLines(
            in: bounds,
            pattern: HatchPatternDefinition(style: .ansi32, angleDegrees: 45.0, spacingMM: 5.0)
        )
        #expect(ansi32Edges.count > ansi31Edges.count)

        // CrossHatch produces orthogonal lines
        let crossEdges = DrawingHatchGenerator.generateHatchLines(
            in: bounds,
            pattern: HatchPatternDefinition(style: .crossHatch, angleDegrees: 45.0, spacingMM: 5.0)
        )
        #expect(crossEdges.count >= ansi31Edges.count * 2 - 2)

        // Solid produces dense lines
        let solidEdges = DrawingHatchGenerator.generateHatchLines(
            in: bounds,
            pattern: HatchPatternDefinition(style: .solid, angleDegrees: 45.0, spacingMM: 1.0)
        )
        #expect(solidEdges.count > ansi31Edges.count)

        // Degenerate bounds produce empty lines
        let emptyBounds = BoundingBox2D(min: SIMD2(0, 0), max: SIMD2(0, 0))
        #expect(DrawingHatchGenerator.generateHatchLines(in: emptyBounds, pattern: .standard).isEmpty)
    }

    @Test func testDrawingDetailProcessorClipping() {
        // Line crossing circle of radius 10 at (0, 0) from (-20, 0) to (20, 0)
        let testEdge = HLREdge(category: .visibleSharp, points2D: [SIMD2(-20, 0), SIMD2(20, 0)])
        let clipped = DrawingDetailProcessor.clipEdgesToCircle(
            edges: [testEdge],
            centerMM: .zero,
            radiusMM: 10.0
        )
        #expect(clipped.count == 1)
        guard let first = clipped.first, first.points2D.count == 2 else {
            Issue.record("Expected 1 clipped edge with 2 points")
            return
        }
        #expect(abs(first.points2D[0].x - (-10.0)) < 1e-4)
        #expect(abs(first.points2D[1].x - 10.0) < 1e-4)
        #expect(abs(first.points2D[0].y) < 1e-4)

        // Offset center: circle centered at (50, 50) with radius 10
        let offsetEdge = HLREdge(category: .visibleSharp, points2D: [SIMD2(30, 50), SIMD2(70, 50)])
        let offsetClipped = DrawingDetailProcessor.clipEdgesToCircle(
            edges: [offsetEdge],
            centerMM: SIMD2(50, 50),
            radiusMM: 10.0
        )
        #expect(offsetClipped.count == 1)
        // Center-relative points should be centered around (0, 0)
        #expect(abs(offsetClipped[0].points2D[0].x - (-10.0)) < 1e-4)
        #expect(abs(offsetClipped[0].points2D[1].x - 10.0) < 1e-4)

        // Edge entirely outside circle
        let outsideEdge = HLREdge(category: .visibleSharp, points2D: [SIMD2(100, 100), SIMD2(110, 110)])
        let outsideClipped = DrawingDetailProcessor.clipEdgesToCircle(
            edges: [outsideEdge],
            centerMM: .zero,
            radiusMM: 10.0
        )
        #expect(outsideClipped.isEmpty)
    }

    @Test func testDrawingAuxiliaryDerivation() {
        let baseDir = HLRStandardView.front.direction

        // 0 and 360 degrees preserve direction
        let dir0 = DrawingAuxiliaryDerivation.deriveDirection(from: baseDir, angleDegrees: 0.0)
        #expect(simd_distance(dir0, baseDir) < 1e-6)

        let dir360 = DrawingAuxiliaryDerivation.deriveDirection(from: baseDir, angleDegrees: 360.0)
        #expect(simd_distance(dir360, baseDir) < 1e-6)

        // 45 degrees produces normalized non-NaN vector
        let dir45 = DrawingAuxiliaryDerivation.deriveDirection(from: baseDir, angleDegrees: 45.0)
        #expect(!dir45.x.isNaN && !dir45.y.isNaN && !dir45.z.isNaN)
        #expect(abs(simd_length(dir45) - 1.0) < 1e-6)
        #expect(simd_distance(dir45, baseDir) > 0.1)

        // Zero-length input fallback
        let dirZero = DrawingAuxiliaryDerivation.deriveDirection(from: SIMD3(0, 0, 0), angleDegrees: 45.0)
        #expect(abs(simd_length(dirZero) - 1.0) < 1e-6)
    }

    @Test func testDrawingBreakProcessor() {
        // Horizontal bar along X from -30 to 30
        let edges = [
            HLREdge(category: .visibleSharp, points2D: [SIMD2(-30, 5), SIMD2(30, 5)]),
            HLREdge(category: .visibleSharp, points2D: [SIMD2(-30, -5), SIMD2(30, -5)])
        ]
        let baseHLR = HLRResult(edges: edges, viewDirection: SIMD3(0, 0, 1))

        let def = BreakViewDefinition(
            orientation: .horizontal,
            startMM: -10.0,
            endMM: 10.0,
            gapMM: 5.0,
            style: .zigzag
        )
        #expect(def.breakSpan == 20.0)
        #expect(def.compressionOffset == 15.0)

        let broken = DrawingBreakProcessor.applyBreak(to: baseHLR, definition: def)
        #expect(!broken.edges.isEmpty)

        // Geometry past end (30) is shifted by -15 -> 15
        let maxX = broken.edges.flatMap { $0.points2D }.map { $0.x }.max() ?? 0
        #expect(maxX <= 15.01)

        // Geometry before start (-30) remains at -30
        let minX = broken.edges.flatMap { $0.points2D }.map { $0.x }.min() ?? 0
        #expect(minX >= -30.01)

        // Zero span produces unchanged result
        let noopDef = BreakViewDefinition(orientation: .horizontal, startMM: 0, endMM: 0)
        let noopBroken = DrawingBreakProcessor.applyBreak(to: baseHLR, definition: noopDef)
        #expect(noopBroken.edges.count == baseHLR.edges.count)
    }

    @Test func testParentViewDeletionUnlinksAllDerivedChildren() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.activeSheet!

        let baseView = DrawingView(name: "Base View", kind: .base, standardView: .front)
        _ = doc.addDrawingView(baseView, to: sheet.id)

        let sectionView = DrawingView(name: "Section A-A", kind: .section, parentViewId: baseView.id)
        _ = doc.addDrawingView(sectionView, to: sheet.id)

        let detailView = DrawingView(name: "Detail B", kind: .detail, parentViewId: baseView.id)
        _ = doc.addDrawingView(detailView, to: sheet.id)

        let auxView = DrawingView(name: "Aux C", kind: .auxiliary, parentViewId: baseView.id)
        _ = doc.addDrawingView(auxView, to: sheet.id)

        let brokenView = DrawingView(name: "Broken D", kind: .broken, parentViewId: baseView.id)
        _ = doc.addDrawingView(brokenView, to: sheet.id)

        #expect(doc.activeSheet?.views.count == 5)

        // Reset undo stack to isolate remove action
        doc.undoManager?.removeAllActions()

        // Remove parent base view
        let removed = doc.removeDrawingView(id: baseView.id, from: sheet.id)
        #expect(removed)
        #expect(doc.activeSheet?.views.count == 4)

        // All children must be unlinked to base kind without parent ID
        for remainingView in doc.activeSheet?.views ?? [] {
            #expect(remainingView.parentViewId == nil)
            #expect(remainingView.kind == .base)
        }

        // Undo restores original kinds and parent IDs
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.views.count == 5)
        let restoredSection = doc.activeSheet?.views.first(where: { $0.id == sectionView.id })
        #expect(restoredSection?.kind == .section)
        #expect(restoredSection?.parentViewId == baseView.id)
    }

    @Test func testDrawingViewCodableRoundTripWithDerivedProperties() throws {
        let view = DrawingView(
            name: "Section View A-A",
            kind: .section,
            standardView: .front,
            parentViewId: UUID(),
            positionMM: SIMD2(120, 150),
            scale: .double,
            displayStyle: .visibleLinesOnly,
            sectionDefinition: SectionLineDefinition(label: "A", startPointMM: SIMD2(-15, 0), endPointMM: SIMD2(15, 0), arrowDirection: SIMD2(0, 1)),
            hatchPattern: HatchPatternDefinition(style: .ansi32, angleDegrees: 30.0, spacingMM: 4.0),
            detailDefinition: DetailCircleDefinition(label: "B", centerMM: SIMD2(10, 10), radiusMM: 20.0),
            auxiliaryDefinition: AuxiliaryViewDefinition(label: "C", angleDegrees: 60.0),
            breakDefinition: BreakViewDefinition(orientation: .vertical, startMM: -5, endMM: 5, gapMM: 3, style: .straight),
            customViewDirection: SIMD3(0.577, 0.577, 0.577)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(view)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DrawingView.self, from: data)

        #expect(decoded.name == view.name)
        #expect(decoded.kind == .section)
        #expect(decoded.sectionDefinition?.label == "A")
        #expect(decoded.hatchPattern?.style == .ansi32)
        #expect(decoded.detailDefinition?.radiusMM == 20.0)
        #expect(decoded.auxiliaryDefinition?.angleDegrees == 60.0)
        #expect(decoded.breakDefinition?.orientation == .vertical)
        #expect(decoded.customViewDirection != nil)
    }

    @Test func testLegacyDrawingViewDecodingWithoutOptionalFields() throws {
        let legacyViewJSON = """
        {
            "id": "33333333-4444-5555-6666-777777777777",
            "name": "Legacy Front View",
            "kind": "base",
            "standardView": "front",
            "positionMM": [100.0, 100.0],
            "scale": {
                "numerator": 1.0,
                "denominator": 1.0
            },
            "displayStyle": "visibleLinesOnly",
            "customProperties": {}
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DrawingView.self, from: legacyViewJSON)

        #expect(decoded.name == "Legacy Front View")
        #expect(decoded.kind == .base)
        #expect(decoded.sectionDefinition == nil)
        #expect(decoded.hatchPattern == nil)
        #expect(decoded.detailDefinition == nil)
        #expect(decoded.auxiliaryDefinition == nil)
        #expect(decoded.breakDefinition == nil)
        #expect(decoded.customViewDirection == nil)
        #expect(decoded.effectiveViewDirection == HLRStandardView.front.direction)
    }
}
