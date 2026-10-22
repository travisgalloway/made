import SwiftUI
import MadeCore

/// Interactive 2D drawing canvas rendering sized sheets, borders, margins, zone marks, title block, and tab navigation.
struct DrawingCanvasView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var sheetToRename: DrawingSheet?
    @State private var renameText: String = ""

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
}
