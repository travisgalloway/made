import SwiftUI
import MadeCore

/// Interactive 2D drawing canvas rendering sized sheets, borders, margins, zone marks, title block, and tab navigation.
struct DrawingCanvasView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var sheetToRename: DrawingSheet?
    @State private var renameText: String = ""
    @State private var dragTranslations: [UUID: CGSize] = [:]

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                        .ignoresSafeArea()

                    if let activeSheet = workspace.document.activeSheet {
                        sheetCanvas(for: activeSheet, in: geometry.size)
                    } else {
                        ContentUnavailableView("No Drawing Sheets", systemImage: "doc.text")
                    }
                }
            }

            Divider()
            sheetTabBar
        }
        .sheet(item: $sheetToRename) { sheet in
            renameSheetSheet(sheet)
        }
        .accessibilityIdentifier("drawing-canvas-view")
    }

    // MARK: - Canvas Rendering

    @ViewBuilder
    private func sheetCanvas(for sheet: DrawingSheet, in containerSize: CGSize) -> some View {
        let mm = sheet.dimensionsMM
        let padding: Double = 32.0
        let availableWidth = max(100.0, containerSize.width - (padding * 2))
        let availableHeight = max(100.0, containerSize.height - (padding * 2))
        let fitScale = min(availableWidth / mm.width, availableHeight / mm.height)

        let paperWidth = mm.width * fitScale
        let paperHeight = mm.height * fitScale
        let marginMM = 10.0
        let marginPt = marginMM * fitScale

        let sheetIndex = (workspace.document.sheets.firstIndex(where: { $0.id == sheet.id }) ?? 0) + 1
        let totalSheets = max(1, workspace.document.sheets.count)
        let titleProps = sheet.resolvedTitleBlockProperties(
            documentMetadata: workspace.document.metadata,
            sheetIndex: sheetIndex,
            totalSheets: totalSheets
        )

        ZStack(alignment: .topLeading) {
            // Paper base
            Rectangle()
                .fill(Color.white)
                .frame(width: paperWidth, height: paperHeight)
                .overlay(
                    Rectangle()
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)

            // Outer margin border
            Rectangle()
                .stroke(Color.black, lineWidth: 1.5)
                .frame(
                    width: max(0, paperWidth - (marginPt * 2)),
                    height: max(0, paperHeight - (marginPt * 2))
                )
                .offset(x: marginPt, y: marginPt)

            // Placed drawing views
            ForEach(sheet.views) { view in
                drawingViewItem(view: view, sheet: sheet, fitScale: fitScale)
            }

            // Placed drawing annotations and dimensions (BL-DRW-05)
            ForEach(sheet.annotations) { annotation in
                drawingAnnotationItem(annotation: annotation, sheet: sheet, fitScale: fitScale)
            }

            // Zone reference marks (1-4 on top & bottom, A-D on left & right)
            zoneMarks(
                paperWidth: paperWidth,
                paperHeight: paperHeight,
                marginPt: marginPt,
                fitScale: fitScale
            )

            // Title block in bottom-right corner
            if sheet.titleBlockTemplate != .none {
                titleBlock(
                    template: sheet.titleBlockTemplate,
                    properties: titleProps,
                    paperWidth: paperWidth,
                    paperHeight: paperHeight,
                    marginPt: marginPt,
                    fitScale: fitScale
                )
            }
        }
        .frame(width: paperWidth, height: paperHeight)
        .position(x: containerSize.width / 2, y: containerSize.height / 2)
        .contextMenu {
            Menu("Add Base View") {
                Button("Front") { _ = workspace.addBaseView(standardView: .front) }
                Button("Top") { _ = workspace.addBaseView(standardView: .top) }
                Button("Right") { _ = workspace.addBaseView(standardView: .right) }
                Button("Back") { _ = workspace.addBaseView(standardView: .back) }
                Button("Bottom") { _ = workspace.addBaseView(standardView: .bottom) }
                Button("Left") { _ = workspace.addBaseView(standardView: .left) }
                Divider()
                Button("Isometric") { _ = workspace.addBaseView(standardView: .isometric) }
            }
            Divider()
            Menu("Add Sheet Dimension") {
                Button("Linear Dimension") {
                    _ = workspace.addLinearDimension(start: SIMD2(50.0, 100.0), end: SIMD2(150.0, 100.0))
                }
                Button("Angular Dimension") {
                    _ = workspace.addAngularDimension(vertex: SIMD2(50.0, 50.0), start: SIMD2(100.0, 50.0), end: SIMD2(50.0, 100.0))
                }
                Button("Radial Dimension") {
                    _ = workspace.addRadialDimension(center: SIMD2(100.0, 100.0), arcPoint: SIMD2(120.0, 100.0))
                }
                Button("Ordinate Dimension") {
                    _ = workspace.addOrdinateDimension(datum: SIMD2(50.0, 50.0), location: SIMD2(120.0, 50.0), axis: .x)
                }
                Button("Baseline Dimension") {
                    _ = workspace.addBaselineDimension(basePoint: SIMD2(50.0, 80.0), targets: [SIMD2(80.0, 80.0), SIMD2(120.0, 80.0)])
                }
            }
            Menu("Add Sheet Annotation") {
                Button("Note") {
                    _ = workspace.addNote(position: SIMD2(50.0, 50.0), text: "GENERAL NOTE")
                }
                Button("Leader") {
                    _ = workspace.addLeader(arrowPoint: SIMD2(60.0, 60.0), elbowPoint: SIMD2(90.0, 80.0), text: "SHEET NOTE")
                }
            }
        }
    }

    // MARK: - Drawing View Item Rendering

    @ViewBuilder
    private func drawingViewItem(view: DrawingView, sheet: DrawingSheet, fitScale: Double) -> some View {
        let isSelected = workspace.selectedDrawingViewId == view.id
        let effectiveScale = view.scale.scaleFactor * fitScale
        let dragOffset = dragTranslations[view.id] ?? .zero
        let viewCenterX = (view.positionMM.x * fitScale) + dragOffset.width
        let viewCenterY = (view.positionMM.y * fitScale) + dragOffset.height

        let hlr = view.cachedHLR
        let visibleEdges = hlr?.visibleEdges ?? []
        let hiddenEdges = (view.displayStyle == .hiddenLinesVisible) ? (hlr?.hiddenEdges ?? []) : []

        let box = computeBoundingBox(for: hlr, viewCenterX: viewCenterX, viewCenterY: viewCenterY, effectiveScale: effectiveScale)
        let boxWidth = box.width
        let boxHeight = box.height
        let boxCenterX = box.centerX
        let boxCenterY = box.centerY

        ZStack {
            // Visible edges
            if !visibleEdges.isEmpty {
                Path { path in
                    for edge in visibleEdges {
                        guard let first = edge.points2D.first else { continue }
                        path.move(to: CGPoint(
                            x: viewCenterX + (first.x * effectiveScale),
                            y: viewCenterY - (first.y * effectiveScale)
                        ))
                        for pt in edge.points2D.dropFirst() {
                            path.addLine(to: CGPoint(
                                x: viewCenterX + (pt.x * effectiveScale),
                                y: viewCenterY - (pt.y * effectiveScale)
                            ))
                        }
                    }
                }
                .stroke(Color.black, lineWidth: view.kind == .section ? 0.6 : 1.0)
            }

            // Hidden edges
            if !hiddenEdges.isEmpty {
                Path { path in
                    for edge in hiddenEdges {
                        guard let first = edge.points2D.first else { continue }
                        path.move(to: CGPoint(
                            x: viewCenterX + (first.x * effectiveScale),
                            y: viewCenterY - (first.y * effectiveScale)
                        ))
                        for pt in edge.points2D.dropFirst() {
                            path.addLine(to: CGPoint(
                                x: viewCenterX + (pt.x * effectiveScale),
                                y: viewCenterY - (pt.y * effectiveScale)
                            ))
                        }
                    }
                }
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
            }

            // Detail view circular boundary border and label
            if view.kind == .detail, let detDef = view.detailDefinition {
                let rPt = detDef.radiusMM * effectiveScale
                Circle()
                    .stroke(Color.black, lineWidth: 1.2)
                    .frame(width: rPt * 2, height: rPt * 2)
                    .position(x: viewCenterX, y: viewCenterY)

                Text("DETAIL \(detDef.label) · SCALE \(view.scale.displayString)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.primary)
                    .position(x: viewCenterX, y: viewCenterY + rPt + 12)
            }

            // Parent overlays for dependent derived views
            parentOverlays(for: view, sheet: sheet, viewCenterX: viewCenterX, viewCenterY: viewCenterY, effectiveScale: effectiveScale)

            // Empty placeholder when no edges exist
            if visibleEdges.isEmpty && hiddenEdges.isEmpty {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: boxWidth, height: boxHeight)
                    .position(x: boxCenterX, y: boxCenterY)
                    .overlay(
                        Text("Empty View")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .position(x: boxCenterX, y: boxCenterY)
                    )
            }

            // Selection highlight and badge
            if isSelected {
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, dash: [4, 2]))
                    .frame(width: boxWidth, height: boxHeight)
                    .position(x: boxCenterX, y: boxCenterY)

                Text("\(view.name) [\(view.scale.displayString)]")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .position(x: boxCenterX, y: max(10, boxCenterY - (boxHeight / 2) - 10))
            }
        }
        .contentShape(Rectangle().path(in: CGRect(
            x: boxCenterX - boxWidth / 2,
            y: boxCenterY - boxHeight / 2,
            width: boxWidth,
            height: boxHeight
        )))
        .onTapGesture {
            workspace.selectDrawingView(view.id)
        }
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    dragTranslations[view.id] = gesture.translation
                    if workspace.selectedDrawingViewId != view.id {
                        workspace.selectDrawingView(view.id)
                    }
                }
                .onEnded { gesture in
                    let translation = gesture.translation
                    dragTranslations.removeValue(forKey: view.id)
                    let deltaXMM = translation.width / fitScale
                    let deltaYMM = translation.height / fitScale
                    let targetX = max(10.0, min(sheet.dimensionsMM.width - 10.0, view.positionMM.x + deltaXMM))
                    let targetY = max(10.0, min(sheet.dimensionsMM.height - 10.0, view.positionMM.y + deltaYMM))
                    _ = workspace.repositionDrawingView(id: view.id, positionMM: SIMD2<Double>(targetX, targetY))
                }
        )
        .contextMenu {
            drawingViewContextMenu(view: view)
        }
        .accessibilityIdentifier("drawing-view-\(view.id.uuidString)")
    }

    @ViewBuilder
    private func drawingViewContextMenu(view: DrawingView) -> some View {
        Menu("Add Projected View") {
            Button("Right") {
                _ = workspace.addProjectedView(parentViewId: view.id, direction: .right)
            }
            Button("Left") {
                _ = workspace.addProjectedView(parentViewId: view.id, direction: .left)
            }
            Button("Above") {
                _ = workspace.addProjectedView(parentViewId: view.id, direction: .above)
            }
            Button("Below") {
                _ = workspace.addProjectedView(parentViewId: view.id, direction: .below)
            }
            Divider()
            Button("Isometric") {
                _ = workspace.addProjectedView(parentViewId: view.id, direction: .isometricTopRight)
            }
        }
        Menu("Add Derived View") {
            Button("Section View") {
                _ = workspace.addSectionView(parentViewId: view.id)
            }
            Button("Detail View") {
                _ = workspace.addDetailView(parentViewId: view.id)
            }
            Button("Auxiliary View") {
                _ = workspace.addAuxiliaryView(parentViewId: view.id)
            }
            Button("Broken View") {
                _ = workspace.addBrokenView(parentViewId: view.id)
            }
        }
        Divider()
        Menu("Add Dimension") {
            Button("Linear Dimension") {
                _ = workspace.addLinearDimension(viewId: view.id, start: SIMD2(-20.0, 0.0), end: SIMD2(20.0, 0.0))
            }
            Button("Angular Dimension") {
                _ = workspace.addAngularDimension(viewId: view.id, vertex: SIMD2(0.0, 0.0), start: SIMD2(20.0, 0.0), end: SIMD2(0.0, 20.0))
            }
            Button("Radial Dimension") {
                _ = workspace.addRadialDimension(viewId: view.id, center: SIMD2(0.0, 0.0), arcPoint: SIMD2(15.0, 0.0))
            }
            Button("Ordinate Dimension") {
                _ = workspace.addOrdinateDimension(viewId: view.id, datum: SIMD2(0.0, 0.0), location: SIMD2(25.0, 0.0), axis: .x)
            }
            Button("Baseline Dimension") {
                _ = workspace.addBaselineDimension(viewId: view.id, basePoint: SIMD2(-30.0, -20.0), targets: [SIMD2(-10.0, -20.0), SIMD2(10.0, -20.0)])
            }
        }
        Menu("Add Annotation") {
            Button("Note") {
                _ = workspace.addNote(viewId: view.id, position: SIMD2(0.0, 30.0), text: "VIEW NOTE")
            }
            Button("Leader") {
                _ = workspace.addLeader(viewId: view.id, arrowPoint: SIMD2(10.0, 10.0), elbowPoint: SIMD2(25.0, 25.0), text: "SURFACE")
            }
            Button("Center Mark") {
                _ = workspace.addCenterMark(viewId: view.id, center: SIMD2(0.0, 0.0))
            }
            Button("Centerline") {
                _ = workspace.addCenterline(viewId: view.id, start: SIMD2(0.0, -25.0), end: SIMD2(0.0, 25.0))
            }
            Button("Hole Callout") {
                let holeParam = workspace.document.features.compactMap { feat -> HoleParams? in
                    if case .hole(let data) = feat.operation { return data }
                    return nil
                }.first
                if let holeParam {
                    _ = workspace.addHoleCalloutFromHoleWizard(viewId: view.id, anchor: SIMD2(10.0, 0.0), elbow: SIMD2(25.0, 15.0), holeParams: holeParam)
                } else {
                    _ = workspace.addHoleCallout(viewId: view.id, anchor: SIMD2(10.0, 0.0), elbow: SIMD2(25.0, 15.0), holeData: HoleCalloutAnnotationData(anchorPointMM: SIMD2(10.0, 0.0), elbowPointMM: SIMD2(25.0, 15.0)))
                }
            }
        }
        Divider()
        Button("Delete View", role: .destructive) {
            _ = workspace.removeDrawingView(id: view.id)
        }
    }

    @ViewBuilder
    private func parentOverlays(
        for parent: DrawingView,
        sheet: DrawingSheet,
        viewCenterX: Double,
        viewCenterY: Double,
        effectiveScale: Double
    ) -> some View {
        let children = sheet.views.filter { $0.parentViewId == parent.id }
        ForEach(children) { child in
            switch child.kind {
            case .section:
                if let secDef = child.sectionDefinition {
                    let startX = viewCenterX + (secDef.startPointMM.x * effectiveScale)
                    let startY = viewCenterY - (secDef.startPointMM.y * effectiveScale)
                    let endX = viewCenterX + (secDef.endPointMM.x * effectiveScale)
                    let endY = viewCenterY - (secDef.endPointMM.y * effectiveScale)

                    // Cutting plane line
                    Path { p in
                        p.move(to: CGPoint(x: startX, y: startY))
                        p.addLine(to: CGPoint(x: endX, y: endY))
                    }
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 1.5, dash: [8, 3, 2, 3]))

                    // Arrows and reference letters at ends
                    let arrowLen = 14.0
                    let arrX = secDef.arrowDirection.x * arrowLen
                    let arrY = -secDef.arrowDirection.y * arrowLen

                    // Start arrow
                    Path { p in
                        p.move(to: CGPoint(x: startX, y: startY))
                        p.addLine(to: CGPoint(x: startX + arrX, y: startY + arrY))
                    }
                    .stroke(Color.black, lineWidth: 1.5)

                    Text(secDef.label)
                        .font(.system(size: 9, weight: .bold))
                        .position(x: startX + arrX * 1.5, y: startY + arrY * 1.5)

                    // End arrow
                    Path { p in
                        p.move(to: CGPoint(x: endX, y: endY))
                        p.addLine(to: CGPoint(x: endX + arrX, y: endY + arrY))
                    }
                    .stroke(Color.black, lineWidth: 1.5)

                    Text(secDef.label)
                        .font(.system(size: 9, weight: .bold))
                        .position(x: endX + arrX * 1.5, y: endY + arrY * 1.5)
                }

            case .detail:
                if let detDef = child.detailDefinition {
                    let cX = viewCenterX + (detDef.centerMM.x * effectiveScale)
                    let cY = viewCenterY - (detDef.centerMM.y * effectiveScale)
                    let rPt = detDef.radiusMM * effectiveScale

                    // Callout circle
                    Circle()
                        .stroke(Color.black, style: StrokeStyle(lineWidth: 1.0, dash: [4, 2]))
                        .frame(width: rPt * 2, height: rPt * 2)
                        .position(x: cX, y: cY)

                    // Label badge
                    Text(detDef.label)
                        .font(.system(size: 9, weight: .bold))
                        .padding(2)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Circle())
                        .position(x: cX + rPt + 6, y: cY - rPt - 6)
                }

            case .auxiliary:
                if let auxDef = child.auxiliaryDefinition {
                    let rad = auxDef.angleDegrees * .pi / 180.0
                    let dist = 32.0
                    let aX = viewCenterX + cos(rad) * dist
                    let aY = viewCenterY - sin(rad) * dist

                    Path { p in
                        p.move(to: CGPoint(x: aX, y: aY))
                        p.addLine(to: CGPoint(x: viewCenterX, y: viewCenterY))
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, dash: [4, 2]))

                    Text("VIEW \(auxDef.label)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .position(x: aX + cos(rad) * 10, y: aY - sin(rad) * 10)
                }

            case .base, .projected, .broken:
                EmptyView()
            }
        }
    }

    private func computeBoundingBox(for hlr: HLRResult?, viewCenterX: Double, viewCenterY: Double, effectiveScale: Double) -> (width: Double, height: Double, centerX: Double, centerY: Double) {
        if let b = hlr?.bounds2D, (b.width > 0 || b.height > 0) {
            let width = max(24.0, b.width * effectiveScale + 16.0)
            let height = max(24.0, b.height * effectiveScale + 16.0)
            let centerX = viewCenterX + (b.center.x * effectiveScale)
            let centerY = viewCenterY - (b.center.y * effectiveScale)
            return (width, height, centerX, centerY)
        } else {
            return (60.0, 40.0, viewCenterX, viewCenterY)
        }
    }

    // MARK: - Zone Reference Marks

    @ViewBuilder
    private func zoneMarks(
        paperWidth: Double,
        paperHeight: Double,
        marginPt: Double,
        fitScale: Double
    ) -> some View {
        let innerWidth = paperWidth - (marginPt * 2)
        let innerHeight = paperHeight - (marginPt * 2)
        let fontSize = max(8.0, min(11.0, 10.0 * fitScale))

        // Numbers 1 to 4 along horizontal margins
        let colStep = innerWidth / 4.0
        ForEach(0..<4, id: \.self) { i in
            let label = "\(i + 1)"
            let xPos = marginPt + (Double(i) + 0.5) * colStep

            // Top margin label
            Text(label)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .position(x: xPos, y: marginPt / 2.0)

            // Bottom margin label
            Text(label)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .position(x: xPos, y: paperHeight - (marginPt / 2.0))
        }

        // Letters A to D along vertical margins
        let letters = ["A", "B", "C", "D"]
        let rowStep = innerHeight / 4.0
        ForEach(0..<4, id: \.self) { i in
            let label = letters[i]
            let yPos = marginPt + (Double(i) + 0.5) * rowStep

            // Left margin label
            Text(label)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .position(x: marginPt / 2.0, y: yPos)

            // Right margin label
            Text(label)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .position(x: paperWidth - (marginPt / 2.0), y: yPos)
        }
    }

    // MARK: - Title Block Rendering

    @ViewBuilder
    private func titleBlock(
        template: TitleBlockTemplate,
        properties: [String: String],
        paperWidth: Double,
        paperHeight: Double,
        marginPt: Double,
        fitScale: Double
    ) -> some View {
        let blockWidthMM: Double = (template == .minimal) ? 120.0 : 170.0
        let blockHeightMM: Double = (template == .minimal) ? 36.0 : 54.0

        let maxAvailableWidth = max(80.0, paperWidth - (marginPt * 2))
        let maxAvailableHeight = max(40.0, paperHeight - (marginPt * 2))

        let blockWidth = min(maxAvailableWidth, blockWidthMM * fitScale)
        let blockHeight = min(maxAvailableHeight, blockHeightMM * fitScale)

        let posX = paperWidth - marginPt - blockWidth
        let posY = paperHeight - marginPt - blockHeight

        let title = properties["title"] ?? properties[CustomPropertyKey.description] ?? "Untitled"
        let partNum = properties[CustomPropertyKey.partNumber] ?? "DRW-001"
        let rev = properties[CustomPropertyKey.revision] ?? "A"
        let author = properties["author"] ?? NSFullUserName()
        let date = properties["date"] ?? ""
        let scale = properties["scale"] ?? "1:1"
        let sheetText = properties["sheet"] ?? "Sheet 1 of 1"
        let vendor = properties[CustomPropertyKey.vendor] ?? ""

        VStack(spacing: 0) {
            if template == .minimal {
                // Minimal title block: 2 rows
                HStack(spacing: 0) {
                    titleBlockCell(label: "TITLE", value: title)
                    Divider().overlay(Color.black)
                    titleBlockCell(label: "DWG NO.", value: partNum, width: CGFloat(blockWidth * 0.35))
                }
                .frame(maxHeight: .infinity)

                Divider().overlay(Color.black)

                HStack(spacing: 0) {
                    titleBlockCell(label: "REV", value: rev, width: CGFloat(blockWidth * 0.2))
                    Divider().overlay(Color.black)
                    titleBlockCell(label: "SCALE", value: scale, width: CGFloat(blockWidth * 0.3))
                    Divider().overlay(Color.black)
                    titleBlockCell(label: "SHEET", value: sheetText)
                }
                .frame(height: blockHeight * 0.45)
            } else {
                // Standard ISO / ANSI Title Block
                if !vendor.isEmpty {
                    HStack(spacing: 0) {
                        Text(vendor.uppercased())
                            .font(.system(size: max(8, 10 * fitScale), weight: .bold))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                        Spacer()
                    }
                    .frame(height: blockHeight * 0.22)
                    .background(Color.secondary.opacity(0.08))

                    Divider().overlay(Color.black)
                }

                HStack(spacing: 0) {
                    titleBlockCell(label: "TITLE / DESCRIPTION", value: title)
                    Divider().overlay(Color.black)
                    titleBlockCell(label: "DRAWING NO.", value: partNum, width: CGFloat(blockWidth * 0.4))
                }
                .frame(maxHeight: .infinity)

                Divider().overlay(Color.black)

                HStack(spacing: 0) {
                    titleBlockCell(label: "REV", value: rev, width: CGFloat(blockWidth * 0.15))
                    Divider().overlay(Color.black)
                    titleBlockCell(label: "AUTHOR", value: author, width: CGFloat(blockWidth * 0.28))
                    Divider().overlay(Color.black)
                    titleBlockCell(label: "DATE", value: date, width: CGFloat(blockWidth * 0.25))
                    Divider().overlay(Color.black)
                    titleBlockCell(label: "SCALE", value: scale, width: CGFloat(blockWidth * 0.16))
                    Divider().overlay(Color.black)
                    titleBlockCell(label: "SHEET", value: sheetText)
                }
                .frame(height: blockHeight * 0.35)
            }
        }
        .frame(width: blockWidth, height: blockHeight)
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(Color.black, lineWidth: 1.5)
        )
        .offset(x: posX, y: posY)
        .accessibilityIdentifier("drawing-title-block")
    }

    private func titleBlockCell(label: String, value: String, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Bottom Sheet Tab Bar

    private var sheetTabBar: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(workspace.document.sheets) { sheet in
                        sheetTabButton(for: sheet)
                    }
                }
                .padding(.horizontal, 4)
            }

            Divider()
                .frame(height: 16)

            Button {
                _ = workspace.addSheet()
            } label: {
                Image(systemName: "plus")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
            .help("Add Sheet")
            .accessibilityIdentifier("drawing-add-sheet-tab-button")
        }
        .padding(.vertical, 4)
        .frame(height: 30)
        .background(.bar)
    }

    private func sheetTabButton(for sheet: DrawingSheet) -> some View {
        let isActive = workspace.document.activeSheetId == sheet.id
        return Button {
            workspace.setActiveSheetId(sheet.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .imageScale(.small)
                Text(sheet.name)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Duplicate") {
                _ = workspace.duplicateSheet(id: sheet.id)
            }
            Button("Rename…") {
                renameText = sheet.name
                sheetToRename = sheet
            }
            Divider()
            Button("Delete Sheet", role: .destructive) {
                _ = workspace.removeSheet(id: sheet.id)
            }
            .disabled(workspace.document.sheets.count <= 1)
        }
        .accessibilityIdentifier("drawing-sheet-tab-\(sheet.name)")
    }

    // MARK: - Rename Sheet Modal

    private func renameSheetSheet(_ sheet: DrawingSheet) -> some View {
        VStack(spacing: 16) {
            Text("Rename Sheet")
                .font(.headline)
            TextField("Sheet Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            HStack {
                Button("Cancel") {
                    sheetToRename = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        var updated = sheet
                        updated.name = trimmed
                        _ = workspace.updateSheet(updated)
                    }
                    sheetToRename = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    // MARK: - Annotation Item Rendering (BL-DRW-05)

    private func toCanvasPoint(_ pointMM: SIMD2<Double>, viewId: UUID?, sheet: DrawingSheet, fitScale: Double) -> CGPoint {
        if let viewId, let view = sheet.views.first(where: { $0.id == viewId }) {
            let dragOffset = dragTranslations[view.id] ?? .zero
            let viewCenterX = (view.positionMM.x * fitScale) + dragOffset.width
            let viewCenterY = (view.positionMM.y * fitScale) + dragOffset.height
            let effectiveScale = view.scale.scaleFactor * fitScale
            return CGPoint(
                x: viewCenterX + (pointMM.x * effectiveScale),
                y: viewCenterY - (pointMM.y * effectiveScale)
            )
        } else {
            return CGPoint(
                x: pointMM.x * fitScale,
                y: pointMM.y * fitScale
            )
        }
    }

    private func toCanvasScale(viewId: UUID?, sheet: DrawingSheet, fitScale: Double) -> Double {
        if let viewId, let view = sheet.views.first(where: { $0.id == viewId }) {
            return view.scale.scaleFactor * fitScale
        }
        return fitScale
    }

    private func appendArrowhead(to path: inout Path, tip: CGPoint, angle: Double, length: CGFloat = 8.0, width: CGFloat = 4.0) {
        let leftAngle = angle + .pi - atan2(width, length)
        let rightAngle = angle + .pi + atan2(width, length)
        let leftPt = CGPoint(x: tip.x + cos(leftAngle) * length, y: tip.y + sin(leftAngle) * length)
        let rightPt = CGPoint(x: tip.x + cos(rightAngle) * length, y: tip.y + sin(rightAngle) * length)
        path.move(to: tip)
        path.addLine(to: leftPt)
        path.addLine(to: rightPt)
        path.closeSubpath()
    }

    @ViewBuilder
    private func drawingAnnotationItem(annotation: DrawingAnnotation, sheet: DrawingSheet, fitScale: Double) -> some View {
        let isSelected = workspace.selectedDrawingAnnotationId == annotation.id
        let strokeColor = isSelected ? Color.accentColor : Color.black
        let lineWidth: CGFloat = isSelected ? 1.5 : 1.0
        let scale = toCanvasScale(viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)

        ZStack {
            switch annotation.data {
            case .linear(let data):
                renderLinearDimension(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, scale: scale, strokeColor: strokeColor, lineWidth: lineWidth)

            case .angular(let data):
                renderAngularDimension(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, scale: scale, strokeColor: strokeColor, lineWidth: lineWidth)

            case .radial(let data):
                renderRadialDimension(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, scale: scale, strokeColor: strokeColor, lineWidth: lineWidth)

            case .ordinate(let data):
                renderOrdinateDimension(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, scale: scale, strokeColor: strokeColor, lineWidth: lineWidth)

            case .baseline(let data):
                renderBaselineDimension(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, scale: scale, strokeColor: strokeColor, lineWidth: lineWidth)

            case .note(let data):
                renderNote(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, strokeColor: strokeColor)

            case .leader(let data):
                renderLeader(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, scale: scale, strokeColor: strokeColor, lineWidth: lineWidth)

            case .centerMark(let data):
                renderCenterMark(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, scale: scale, strokeColor: strokeColor, lineWidth: lineWidth)

            case .centerline(let data):
                renderCenterline(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, scale: scale, strokeColor: strokeColor, lineWidth: lineWidth)

            case .holeCallout(let data):
                renderHoleCallout(data: data, annotation: annotation, sheet: sheet, fitScale: fitScale, scale: scale, strokeColor: strokeColor, lineWidth: lineWidth)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.selectDrawingAnnotation(annotation.id)
        }
        .contextMenu {
            Button("Delete Annotation", role: .destructive) {
                _ = workspace.removeDrawingAnnotation(id: annotation.id)
            }
        }
        .accessibilityIdentifier("drawing-annotation-\(annotation.id.uuidString)")
    }

    private struct LinearDimensionGeometry {
        let d1: CGPoint
        let d2: CGPoint
        let w1End: CGPoint
        let w2End: CGPoint
        let midPt: CGPoint
        let angle: Double
    }

    private func computeLinearPoints(data: LinearDimensionData, p1: CGPoint, p2: CGPoint, scale: Double) -> LinearDimensionGeometry {
        let offset = data.offsetMM * scale
        switch data.orientation {
        case .aligned:
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let len = hypot(dx, dy)
            let nx = len > 1e-4 ? -dy / len : 0.0
            let ny = len > 1e-4 ? dx / len : -1.0
            let d1 = CGPoint(x: p1.x + nx * offset, y: p1.y + ny * offset)
            let d2 = CGPoint(x: p2.x + nx * offset, y: p2.y + ny * offset)
            let w1End = CGPoint(x: d1.x + nx * 2, y: d1.y + ny * 2)
            let w2End = CGPoint(x: d2.x + nx * 2, y: d2.y + ny * 2)
            let midPt = CGPoint(x: (d1.x + d2.x) * 0.5, y: (d1.y + d2.y) * 0.5)
            let angle = atan2(d2.y - d1.y, d2.x - d1.x)
            return LinearDimensionGeometry(d1: d1, d2: d2, w1End: w1End, w2End: w2End, midPt: midPt, angle: angle)

        case .horizontal:
            let dimY = p1.y + offset
            let d1 = CGPoint(x: p1.x, y: dimY)
            let d2 = CGPoint(x: p2.x, y: dimY)
            let extY: CGFloat = offset >= 0 ? 3.0 : -3.0
            let w1End = CGPoint(x: p1.x, y: dimY + extY)
            let w2End = CGPoint(x: p2.x, y: dimY + extY)
            let midPt = CGPoint(x: (d1.x + d2.x) * 0.5, y: dimY)
            return LinearDimensionGeometry(d1: d1, d2: d2, w1End: w1End, w2End: w2End, midPt: midPt, angle: 0.0)

        case .vertical:
            let dimX = p1.x + offset
            let d1 = CGPoint(x: dimX, y: p1.y)
            let d2 = CGPoint(x: dimX, y: p2.y)
            let extX: CGFloat = offset >= 0 ? 3.0 : -3.0
            let w1End = CGPoint(x: dimX + extX, y: p1.y)
            let w2End = CGPoint(x: dimX + extX, y: p2.y)
            let midPt = CGPoint(x: dimX, y: (d1.y + d2.y) * 0.5)
            return LinearDimensionGeometry(d1: d1, d2: d2, w1End: w1End, w2End: w2End, midPt: midPt, angle: .pi * 0.5)
        }
    }

    @ViewBuilder
    private func renderLinearDimension(
        data: LinearDimensionData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        scale: Double,
        strokeColor: Color,
        lineWidth: CGFloat
    ) -> some View {
        let p1 = toCanvasPoint(data.startPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let p2 = toCanvasPoint(data.endPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let geom = computeLinearPoints(data: data, p1: p1, p2: p2, scale: scale)

        ZStack {
            Path { path in
                path.move(to: p1)
                path.addLine(to: geom.w1End)
                path.move(to: p2)
                path.addLine(to: geom.w2End)
                path.move(to: geom.d1)
                path.addLine(to: geom.d2)
            }
            .stroke(strokeColor, lineWidth: lineWidth)

            Path { path in
                appendArrowhead(to: &path, tip: geom.d1, angle: geom.angle)
                appendArrowhead(to: &path, tip: geom.d2, angle: geom.angle + .pi)
            }
            .fill(strokeColor)

            Text(data.formattedText)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 3)
                .background(Color.white)
                .foregroundStyle(strokeColor)
                .position(geom.midPt)
        }
    }

    @ViewBuilder
    private func renderAngularDimension(
        data: AngularDimensionData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        scale: Double,
        strokeColor: Color,
        lineWidth: CGFloat
    ) -> some View {
        let vCenter = toCanvasPoint(data.vertexMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let p1 = toCanvasPoint(data.startPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let p2 = toCanvasPoint(data.endPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let arcRadius = data.arcRadiusMM * scale
        let angle1 = atan2(p1.y - vCenter.y, p1.x - vCenter.x)
        let angle2 = atan2(p2.y - vCenter.y, p2.x - vCenter.x)

        let startPt = CGPoint(x: vCenter.x + cos(angle1) * arcRadius, y: vCenter.y + sin(angle1) * arcRadius)
        let endPt = CGPoint(x: vCenter.x + cos(angle2) * arcRadius, y: vCenter.y + sin(angle2) * arcRadius)
        let midAngle = (angle1 + angle2) * 0.5
        let textPos = CGPoint(x: vCenter.x + cos(midAngle) * (arcRadius + 10), y: vCenter.y + sin(midAngle) * (arcRadius + 10))

        ZStack {
            Path { path in
                path.move(to: vCenter)
                path.addLine(to: p1)
                path.move(to: vCenter)
                path.addLine(to: p2)
                path.move(to: startPt)
                path.addArc(center: vCenter, radius: arcRadius, startAngle: Angle(radians: angle1), endAngle: Angle(radians: angle2), clockwise: false)
            }
            .stroke(strokeColor, lineWidth: lineWidth)

            Path { path in
                let tangent1 = angle1 + .pi * 0.5
                let tangent2 = angle2 - .pi * 0.5
                appendArrowhead(to: &path, tip: startPt, angle: tangent1)
                appendArrowhead(to: &path, tip: endPt, angle: tangent2)
            }
            .fill(strokeColor)

            Text(data.formattedText)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 3)
                .background(Color.white)
                .foregroundStyle(strokeColor)
                .position(textPos)
        }
    }

    @ViewBuilder
    private func renderRadialDimension(
        data: RadialDimensionData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        scale: Double,
        strokeColor: Color,
        lineWidth: CGFloat
    ) -> some View {
        let center = toCanvasPoint(data.centerMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let arcPt = toCanvasPoint(data.arcPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let angle = atan2(arcPt.y - center.y, arcPt.x - center.x)
        let leaderOffset = data.leaderOffsetMM * scale
        let elbow = CGPoint(x: arcPt.x + cos(angle) * leaderOffset, y: arcPt.y + sin(angle) * leaderOffset)
        let shelfDir: CGFloat = elbow.x >= center.x ? 1.0 : -1.0
        let shelfEnd = CGPoint(x: elbow.x + shelfDir * 14.0, y: elbow.y)
        let textPos = CGPoint(x: elbow.x + shelfDir * 24.0, y: elbow.y - 6.0)

        ZStack {
            Path { path in
                path.move(to: center)
                path.addLine(to: arcPt)
                path.addLine(to: elbow)
                path.addLine(to: shelfEnd)
            }
            .stroke(strokeColor, lineWidth: lineWidth)

            Path { path in
                appendArrowhead(to: &path, tip: arcPt, angle: angle)
            }
            .fill(strokeColor)

            Text(data.formattedText)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 2)
                .foregroundStyle(strokeColor)
                .position(textPos)
        }
    }

    @ViewBuilder
    private func renderOrdinateDimension(
        data: OrdinateDimensionData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        scale: Double,
        strokeColor: Color,
        lineWidth: CGFloat
    ) -> some View {
        let datumPt = toCanvasPoint(data.datumOriginMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let locPt = toCanvasPoint(data.locationMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let jog = data.jogOffsetMM * scale

        ZStack {
            if data.isDatum {
                Circle()
                    .stroke(strokeColor, lineWidth: lineWidth)
                    .frame(width: 8, height: 8)
                    .position(datumPt)

                Path { path in
                    path.move(to: CGPoint(x: datumPt.x - 6, y: datumPt.y))
                    path.addLine(to: CGPoint(x: datumPt.x + 6, y: datumPt.y))
                    path.move(to: CGPoint(x: datumPt.x, y: datumPt.y - 6))
                    path.addLine(to: CGPoint(x: datumPt.x, y: datumPt.y + 6))
                }
                .stroke(strokeColor, lineWidth: lineWidth)

                Text("0")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(strokeColor)
                    .position(x: datumPt.x + 10, y: datumPt.y - 8)
            } else if data.axis == .x {
                let endPt = CGPoint(x: locPt.x, y: locPt.y - jog)
                Path { path in
                    path.move(to: locPt)
                    path.addLine(to: endPt)
                }
                .stroke(strokeColor, lineWidth: lineWidth)

                Text(data.formattedText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(strokeColor)
                    .position(x: endPt.x, y: endPt.y - 8)
            } else {
                let endPt = CGPoint(x: locPt.x + jog, y: locPt.y)
                Path { path in
                    path.move(to: locPt)
                    path.addLine(to: endPt)
                }
                .stroke(strokeColor, lineWidth: lineWidth)

                Text(data.formattedText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(strokeColor)
                    .position(x: endPt.x + 14, y: endPt.y)
            }
        }
    }

    @ViewBuilder
    private func renderBaselineDimension(
        data: BaselineDimensionData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        scale: Double,
        strokeColor: Color,
        lineWidth: CGFloat
    ) -> some View {
        let basePt = toCanvasPoint(data.basePointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)

        ZStack {
            ForEach(data.targetPointsMM.indices, id: \.self) { index in
                let targetPt = toCanvasPoint(data.targetPointsMM[index], viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
                let offset = data.stackOffsetMM(forTargetIndex: index) * scale
                let dimY = basePt.y + offset
                let d1 = CGPoint(x: basePt.x, y: dimY)
                let d2 = CGPoint(x: targetPt.x, y: dimY)
                let midPt = CGPoint(x: (d1.x + d2.x) * 0.5, y: dimY)

                Path { path in
                    path.move(to: basePt)
                    path.addLine(to: CGPoint(x: basePt.x, y: dimY + 3))
                    path.move(to: targetPt)
                    path.addLine(to: CGPoint(x: targetPt.x, y: dimY + 3))
                    path.move(to: d1)
                    path.addLine(to: d2)
                }
                .stroke(strokeColor, lineWidth: lineWidth)

                Path { path in
                    appendArrowhead(to: &path, tip: d1, angle: 0.0)
                    appendArrowhead(to: &path, tip: d2, angle: .pi)
                }
                .fill(strokeColor)

                Text(data.formattedText(forTargetIndex: index))
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 2)
                    .background(Color.white)
                    .foregroundStyle(strokeColor)
                    .position(midPt)
            }
        }
    }

    @ViewBuilder
    private func renderNote(
        data: NoteAnnotationData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        strokeColor: Color
    ) -> some View {
        let pos = toCanvasPoint(data.positionMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)

        Text(data.text)
            .font(.system(size: CGFloat(data.fontSizePt), weight: data.isBold ? .bold : .regular))
            .foregroundStyle(strokeColor)
            .padding(4)
            .overlay(
                data.hasBorder ? Rectangle().stroke(strokeColor, lineWidth: 1.0) : nil
            )
            .position(pos)
    }

    @ViewBuilder
    private func renderLeader(
        data: LeaderAnnotationData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        scale: Double,
        strokeColor: Color,
        lineWidth: CGFloat
    ) -> some View {
        let arrowPt = toCanvasPoint(data.arrowPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let elbowPt = toCanvasPoint(data.elbowPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let shelfDir: CGFloat = elbowPt.x >= arrowPt.x ? 1.0 : -1.0
        let shelfLen = max(10.0, data.landingLengthMM * scale)
        let shelfEnd = CGPoint(x: elbowPt.x + shelfDir * shelfLen, y: elbowPt.y)
        let angle = atan2(elbowPt.y - arrowPt.y, elbowPt.x - arrowPt.x)
        let textPos = CGPoint(x: elbowPt.x + shelfDir * (shelfLen + 15.0), y: elbowPt.y)

        ZStack {
            Path { path in
                path.move(to: arrowPt)
                path.addLine(to: elbowPt)
                path.addLine(to: shelfEnd)
            }
            .stroke(strokeColor, lineWidth: lineWidth)

            Path { path in
                appendArrowhead(to: &path, tip: arrowPt, angle: angle + .pi)
            }
            .fill(strokeColor)

            Text(data.text)
                .font(.system(size: CGFloat(data.fontSizePt), weight: .medium))
                .foregroundStyle(strokeColor)
                .position(textPos)
        }
    }

    @ViewBuilder
    private func renderCenterMark(
        data: CenterMarkData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        scale: Double,
        strokeColor: Color,
        lineWidth: CGFloat
    ) -> some View {
        let center = toCanvasPoint(data.centerMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let size = data.markSizeMM * scale
        let ext = data.extensionMM * scale
        let total = size + ext

        Path { path in
            path.move(to: CGPoint(x: center.x - total, y: center.y))
            path.addLine(to: CGPoint(x: center.x - 2, y: center.y))
            path.move(to: CGPoint(x: center.x + 2, y: center.y))
            path.addLine(to: CGPoint(x: center.x + total, y: center.y))
            path.move(to: CGPoint(x: center.x, y: center.y - total))
            path.addLine(to: CGPoint(x: center.x, y: center.y - 2))
            path.move(to: CGPoint(x: center.x, y: center.y + 2))
            path.addLine(to: CGPoint(x: center.x, y: center.y + total))
        }
        .rotation(Angle(degrees: data.rotationDegrees), anchor: .center)
        .stroke(strokeColor, lineWidth: lineWidth)
    }

    @ViewBuilder
    private func renderCenterline(
        data: CenterlineData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        scale: Double,
        strokeColor: Color,
        lineWidth: CGFloat
    ) -> some View {
        let p1 = toCanvasPoint(data.startPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let p2 = toCanvasPoint(data.endPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let ext = data.extensionMM * scale
        let angle = atan2(p2.y - p1.y, p2.x - p1.x)
        let startExt = CGPoint(x: p1.x - cos(angle) * ext, y: p1.y - sin(angle) * ext)
        let endExt = CGPoint(x: p2.x + cos(angle) * ext, y: p2.y + sin(angle) * ext)

        Path { path in
            path.move(to: startExt)
            path.addLine(to: endExt)
        }
        .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, dash: [10, 3, 3, 3]))
    }

    @ViewBuilder
    private func renderHoleCallout(
        data: HoleCalloutAnnotationData,
        annotation: DrawingAnnotation,
        sheet: DrawingSheet,
        fitScale: Double,
        scale: Double,
        strokeColor: Color,
        lineWidth: CGFloat
    ) -> some View {
        let anchor = toCanvasPoint(data.anchorPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let elbow = toCanvasPoint(data.elbowPointMM, viewId: annotation.viewId, sheet: sheet, fitScale: fitScale)
        let shelfDir: CGFloat = elbow.x >= anchor.x ? 1.0 : -1.0
        let shelfLen = max(18.0, data.landingLengthMM * scale)
        let shelfEnd = CGPoint(x: elbow.x + shelfDir * shelfLen, y: elbow.y)
        let angle = atan2(elbow.y - anchor.y, elbow.x - anchor.x)
        let textPos = CGPoint(x: elbow.x + shelfDir * (shelfLen + 30.0), y: elbow.y)

        ZStack {
            Path { path in
                path.move(to: anchor)
                path.addLine(to: elbow)
                path.addLine(to: shelfEnd)
            }
            .stroke(strokeColor, lineWidth: lineWidth)

            Path { path in
                appendArrowhead(to: &path, tip: anchor, angle: angle + .pi)
            }
            .fill(strokeColor)

            Text(data.formattedCalloutText)
                .font(.system(size: 8, weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(strokeColor)
                .position(textPos)
        }
    }
}
