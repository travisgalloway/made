import Testing
import SwiftUI
import AppKit
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct ViewportStatusBarTests {
    @Test @MainActor func testStatusBarUnitsDisplayTracksDocumentSettings() {
        let workspace = WorkspaceModel()

        // Default length unit is millimeters (mm)
        #expect(workspace.document.settings.units.lengthUnit == .millimeters)
        #expect(workspace.document.settings.units.lengthUnit.symbol == "mm")

        // Switch to inches
        workspace.setDocumentUnits(UnitSettings(lengthUnit: .inches))
        #expect(workspace.document.settings.units.lengthUnit == .inches)
        #expect(workspace.document.settings.units.lengthUnit.symbol == "in")

        // Switch to centimeters
        workspace.setDocumentUnits(UnitSettings(lengthUnit: .centimeters))
        #expect(workspace.document.settings.units.lengthUnit == .centimeters)
        #expect(workspace.document.settings.units.lengthUnit.symbol == "cm")

        // Switch to meters
        workspace.setDocumentUnits(UnitSettings(lengthUnit: .meters))
        #expect(workspace.document.settings.units.lengthUnit == .meters)
        #expect(workspace.document.settings.units.lengthUnit.symbol == "m")

        // Switch to feet
        workspace.setDocumentUnits(UnitSettings(lengthUnit: .feet))
        #expect(workspace.document.settings.units.lengthUnit == .feet)
        #expect(workspace.document.settings.units.lengthUnit.symbol == "ft")
    }

    @Test @MainActor func testStatusBarSketchDOFDisplayAndStyling() {
        let workspace = WorkspaceModel()

        // Inactive (default)
        workspace.setSketchDOFStatus(.inactive)
        #expect(workspace.sketchDOFStatus == .inactive)
        #expect(workspace.sketchDOFStatus.statusText == "DOF: --")
        #expect(ViewportStatusBar.dofColor(for: workspace.sketchDOFStatus) == nil)
        #expect(ViewportStatusBar.dofSystemImage(for: workspace.sketchDOFStatus) == nil)

        // Under-constrained with 3 degrees of freedom
        workspace.setSketchDOFStatus(.underConstrained(dof: 3))
        #expect(workspace.sketchDOFStatus == .underConstrained(dof: 3))
        #expect(workspace.sketchDOFStatus.statusText == "DOF: 3 under")
        #expect(ViewportStatusBar.dofColor(for: workspace.sketchDOFStatus) == .blue)
        #expect(ViewportStatusBar.dofSystemImage(for: workspace.sketchDOFStatus) == "pencil.and.ruler")

        // Fully constrained
        workspace.setSketchDOFStatus(.fullyConstrained)
        #expect(workspace.sketchDOFStatus == .fullyConstrained)
        #expect(workspace.sketchDOFStatus.statusText == "DOF: fully constrained")
        #expect(ViewportStatusBar.dofColor(for: workspace.sketchDOFStatus) == .green)
        #expect(ViewportStatusBar.dofSystemImage(for: workspace.sketchDOFStatus) == "checkmark.circle.fill")

        // Over-constrained
        workspace.setSketchDOFStatus(.overConstrained())
        #expect(workspace.sketchDOFStatus == .overConstrained(dof: 0))
        #expect(workspace.sketchDOFStatus.statusText == "DOF: over-constrained")
        #expect(ViewportStatusBar.dofColor(for: workspace.sketchDOFStatus) == .red)
        #expect(ViewportStatusBar.dofSystemImage(for: workspace.sketchDOFStatus) == "exclamationmark.triangle.fill")

        // Over-constrained with specific count
        workspace.setSketchDOFStatus(.overConstrained(dof: 2))
        #expect(workspace.sketchDOFStatus == .overConstrained(dof: 2))
        #expect(workspace.sketchDOFStatus.statusText == "DOF: over-constrained")
        #expect(ViewportStatusBar.dofColor(for: workspace.sketchDOFStatus) == .red)
        #expect(ViewportStatusBar.dofSystemImage(for: workspace.sketchDOFStatus) == "exclamationmark.triangle.fill")
    }

    @Test @MainActor func testStatusBarSelectionCountTracksDocumentSelection() {
        let workspace = WorkspaceModel()

        // Initial state has default box selected (count == 1)
        #expect(workspace.document.selection.count == 1)

        // Clear selection -> count == 0
        workspace.document.clearSelection()
        #expect(workspace.document.selection.count == 0)

        // Select a single solid reference -> count == 1
        let boxSolidId = ObjectId("box-1")
        workspace.document.select(solidId: boxSolidId)
        #expect(workspace.document.selection.count == 1)

        // Add additional references for multi-selection
        let cylinderSolidId = ObjectId("cylinder-1")
        let customSolidId = ObjectId("solid-custom-3")
        workspace.document.select(Reference.body(cylinderSolidId))
        #expect(workspace.document.selection.count == 2)

        workspace.document.select(Reference.body(customSolidId))
        #expect(workspace.document.selection.count == 3)

        // Add feature references for multi-selection
        let featureA = UUID()
        let featureB = UUID()
        workspace.document.select(Reference.feature(featureA))
        #expect(workspace.document.selection.count == 4)

        workspace.document.select(Reference.feature(featureB))
        #expect(workspace.document.selection.count == 5)

        // Deselect single element
        workspace.document.deselect(Reference.feature(featureB))
        #expect(workspace.document.selection.count == 4)

        // Clear again -> count == 0
        workspace.document.clearSelection()
        #expect(workspace.document.selection.count == 0)
    }

    @Test @MainActor func testStatusBarRegenerationDurationFormatting() {
        let workspace = WorkspaceModel()

        // nil -> "--"
        workspace.setLastRegenerationDuration(nil)
        #expect(workspace.lastRegenerationDuration == nil)
        #expect(workspace.formattedRegenerationDuration == "--")

        // Sub-millisecond (< 1 ms)
        workspace.setLastRegenerationDuration(Duration.zero)
        #expect(workspace.formattedRegenerationDuration == "< 1 ms")

        workspace.setLastRegenerationDuration(Duration.microseconds(450))
        #expect(workspace.formattedRegenerationDuration == "< 1 ms")

        workspace.setLastRegenerationDuration(Duration.nanoseconds(999_999))
        #expect(workspace.formattedRegenerationDuration == "< 1 ms")

        // Millisecond range (< 1 s)
        workspace.setLastRegenerationDuration(Duration.milliseconds(1))
        #expect(workspace.formattedRegenerationDuration == "1 ms")

        workspace.setLastRegenerationDuration(Duration.milliseconds(12))
        #expect(workspace.formattedRegenerationDuration == "12 ms")

        workspace.setLastRegenerationDuration(Duration.milliseconds(350))
        #expect(workspace.formattedRegenerationDuration == "350 ms")

        // Second range (>= 1 s)
        workspace.setLastRegenerationDuration(Duration.milliseconds(1420))
        #expect(workspace.formattedRegenerationDuration == "1.42 s")

        workspace.setLastRegenerationDuration(Duration.seconds(3))
        #expect(workspace.formattedRegenerationDuration == "3.00 s")

        workspace.setLastRegenerationDuration(Duration.seconds(10) + Duration.milliseconds(50))
        #expect(workspace.formattedRegenerationDuration == "10.05 s")
    }

    @Test @MainActor func testStatusBarInstantiatesCleanly() {
        let workspace = WorkspaceModel()
        let statusBar = ViewportStatusBar().environment(workspace)
        let hostingView = NSHostingView(rootView: statusBar)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: BarMetrics.height)
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.frame.height == BarMetrics.height)
        #expect(hostingView.frame.width == 800)
    }
}
