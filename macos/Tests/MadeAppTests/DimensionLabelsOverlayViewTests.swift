import Testing
import SwiftUI
@testable import MadeApp
import MadeCore
import simd

@Suite(.serialized) struct DimensionLabelsOverlayViewTests {

    @Test @MainActor func testBuildCandidatesFallbackToMmWhenUnitIsEmpty() {
        let workspace = WorkspaceModel()
        let session = CommandSession(
            title: "Test Session",
            inputs: [
                CommandInput(id: "length", label: "Length", value: .number(25.0, range: 0.0...100.0, step: 1.0, unit: ""))
            ]
        )
        session.dimensionAnchorsProvider = {
            ["length": SIMD3<Float>(10, 0, 0)]
        }

        let candidates = DimensionLabelsOverlayView.buildCandidates(session: session, workspace: workspace)
        #expect(candidates.count == 1)
        #expect(candidates.first?.id == "length")
        #expect(candidates.first?.label == "Length")
        #expect(candidates.first?.value == 25.0)
        #expect(candidates.first?.unit == "mm")
        #expect(candidates.first?.worldAnchor == SIMD3<Float>(10, 0, 0))
    }

    @Test @MainActor func testBuildCandidatesExplicitUnitPreserved() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeAddBox(workspace: workspace)

        let candidates = DimensionLabelsOverlayView.buildCandidates(session: session, workspace: workspace)
        #expect(candidates.count == 3)
        let candidateIds = Set(candidates.map(\.id))
        #expect(candidateIds == ["width", "depth", "height"])

        for candidate in candidates {
            #expect(candidate.unit == "mm")
            #expect(candidate.value == 30.0)
        }
    }

    @Test @MainActor func testBuildCandidatesCustomUnitPreserved() {
        let workspace = WorkspaceModel()
        let session = CommandSession(
            title: "Test Session",
            inputs: [
                CommandInput(id: "angle", label: "Angle", value: .number(45.0, range: 0.0...360.0, step: 1.0, unit: "deg"))
            ]
        )
        session.dimensionAnchorsProvider = {
            ["angle": SIMD3<Float>(0, 5, 10)]
        }

        let candidates = DimensionLabelsOverlayView.buildCandidates(session: session, workspace: workspace)
        #expect(candidates.count == 1)
        #expect(candidates.first?.id == "angle")
        #expect(candidates.first?.value == 45.0)
        #expect(candidates.first?.unit == "deg")
        #expect(candidates.first?.worldAnchor == SIMD3<Float>(0, 5, 10))
    }

    @Test @MainActor func testBuildCandidatesSkipsNonNumericInputs() {
        let workspace = WorkspaceModel()
        let session = CommandSession(
            title: "Test Session",
            inputs: [
                CommandInput(id: "name", label: "Name", value: .text("test")),
                CommandInput(id: "enabled", label: "Enabled", value: .toggle(true)),
                CommandInput(id: "option", label: "Option", value: .choice("A", options: ["A", "B"]))
            ]
        )
        session.dimensionAnchorsProvider = {
            [
                "name": SIMD3<Float>(0, 0, 0),
                "enabled": SIMD3<Float>(1, 1, 1),
                "option": SIMD3<Float>(2, 2, 2)
            ]
        }

        let candidates = DimensionLabelsOverlayView.buildCandidates(session: session, workspace: workspace)
        #expect(candidates.isEmpty)
    }

    @Test @MainActor func testBuildCandidatesSkipsInputsWithoutAnchor() {
        let workspace = WorkspaceModel()
        let session = CommandSession(
            title: "Test Session",
            inputs: [
                CommandInput(id: "width", label: "Width", value: .number(20.0, range: 1.0...50.0, step: 1.0, unit: "mm")),
                CommandInput(id: "height", label: "Height", value: .number(30.0, range: 1.0...50.0, step: 1.0, unit: "mm"))
            ]
        )

        let candidates = DimensionLabelsOverlayView.buildCandidates(session: session, workspace: workspace)
        #expect(candidates.isEmpty)
    }

    @Test @MainActor func testBuildCandidatesSkipsDatumPlaneWithoutExplicitAnchors() {
        let workspace = WorkspaceModel()
        let session = CommandSession.makeDatumPlane(workspace: workspace)
        let candidates = DimensionLabelsOverlayView.buildCandidates(session: session, workspace: workspace)
        #expect(candidates.isEmpty)
    }
}
