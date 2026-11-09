import Testing
import Foundation
@testable import MadeCore

@Suite struct SketchDOFStatusTests {
    @Test func testStatusTextFormatting() {
        #expect(SketchDOFStatus.inactive.statusText == "DOF: --")
        #expect(SketchDOFStatus.underConstrained(dof: 1).statusText == "DOF: 1 under")
        #expect(SketchDOFStatus.underConstrained(dof: 5).statusText == "DOF: 5 under")
        #expect(SketchDOFStatus.fullyConstrained.statusText == "DOF: fully constrained")
        #expect(SketchDOFStatus.overConstrained().statusText == "DOF: over-constrained")
        #expect(SketchDOFStatus.overConstrained(dof: 2).statusText == "DOF: over-constrained")
    }

    @Test func testEquality() {
        #expect(SketchDOFStatus.inactive == SketchDOFStatus.inactive)
        #expect(SketchDOFStatus.underConstrained(dof: 2) == SketchDOFStatus.underConstrained(dof: 2))
        #expect(SketchDOFStatus.underConstrained(dof: 2) != SketchDOFStatus.underConstrained(dof: 3))
        #expect(SketchDOFStatus.fullyConstrained == SketchDOFStatus.fullyConstrained)
        #expect(SketchDOFStatus.overConstrained() == SketchDOFStatus.overConstrained(dof: 0))
        #expect(SketchDOFStatus.overConstrained(dof: 1) != SketchDOFStatus.overConstrained(dof: 2))
        #expect(SketchDOFStatus.inactive != SketchDOFStatus.fullyConstrained)
        #expect(SketchDOFStatus.underConstrained(dof: 0) != SketchDOFStatus.fullyConstrained)
    }

    @Test func testCodableRoundTrip() throws {
        let cases: [SketchDOFStatus] = [
            .inactive,
            .underConstrained(dof: 3),
            .fullyConstrained,
            .overConstrained(),
            .overConstrained(dof: 4)
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in cases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(SketchDOFStatus.self, from: data)
            #expect(decoded == original)
        }
    }

    @Test func testRemainingDOF() {
        #expect(SketchDOFStatus.inactive.remainingDOF == nil)
        #expect(SketchDOFStatus.underConstrained(dof: 1).remainingDOF == 1)
        #expect(SketchDOFStatus.underConstrained(dof: 4).remainingDOF == 4)
        #expect(SketchDOFStatus.fullyConstrained.remainingDOF == 0)
        #expect(SketchDOFStatus.overConstrained().remainingDOF == 0)
        #expect(SketchDOFStatus.overConstrained(dof: 3).remainingDOF == 3)
    }

    @Test func testBadgeText() {
        #expect(SketchDOFStatus.inactive.badgeText == "")
        #expect(SketchDOFStatus.underConstrained(dof: 1).badgeText == "1 DOF")
        #expect(SketchDOFStatus.underConstrained(dof: 3).badgeText == "3 DOF")
        #expect(SketchDOFStatus.fullyConstrained.badgeText == "Fully Defined")
        #expect(SketchDOFStatus.overConstrained().badgeText == "Over-constrained")
        #expect(SketchDOFStatus.overConstrained(dof: 2).badgeText == "Over-constrained")
    }

    @Test func testSummaryDescription() {
        #expect(SketchDOFStatus.inactive.summaryDescription == "No entities")
        #expect(SketchDOFStatus.underConstrained(dof: 1).summaryDescription == "1 DOF remaining")
        #expect(SketchDOFStatus.underConstrained(dof: 5).summaryDescription == "5 DOF remaining")
        #expect(SketchDOFStatus.fullyConstrained.summaryDescription == "Fully constrained")
        #expect(SketchDOFStatus.overConstrained().summaryDescription == "Over-constrained")
        #expect(SketchDOFStatus.overConstrained(dof: 2).summaryDescription == "Over-constrained")
    }

    @Test func testStateBooleans() {
        let inactive = SketchDOFStatus.inactive
        #expect(inactive.isInactive)
        #expect(!inactive.isUnderConstrained)
        #expect(!inactive.isFullyConstrained)
        #expect(!inactive.isOverConstrained)

        let under = SketchDOFStatus.underConstrained(dof: 2)
        #expect(!under.isInactive)
        #expect(under.isUnderConstrained)
        #expect(!under.isFullyConstrained)
        #expect(!under.isOverConstrained)

        let fully = SketchDOFStatus.fullyConstrained
        #expect(!fully.isInactive)
        #expect(!fully.isUnderConstrained)
        #expect(fully.isFullyConstrained)
        #expect(!fully.isOverConstrained)

        let over = SketchDOFStatus.overConstrained(dof: 1)
        #expect(!over.isInactive)
        #expect(!over.isUnderConstrained)
        #expect(!over.isFullyConstrained)
        #expect(over.isOverConstrained)
    }

    // MARK: - Sketch Geometry Wireframe DOF Coloring Tests

    @Test func testSketchGeometryGeneratorDOFColoring() {
        let lineUnder = SketchEntity(
            kind: "line",
            data: ["startX": 0, "startY": 0, "endX": 10, "endY": 0]
        )
        let lineFully = SketchEntity(
            kind: "line",
            data: ["startX": 0, "startY": 0, "endX": 0, "endY": 10]
        )
        let lineOver = SketchEntity(
            kind: "line",
            data: ["startX": 10, "startY": 0, "endX": 10, "endY": 10]
        )
        let lineConstruction = SketchEntity(
            kind: "line",
            data: ["startX": 0, "startY": 0, "endX": 5, "endY": 5],
            isConstruction: true
        )
        let lineProjected = SketchEntity(
            kind: "line",
            data: ["startX": 5, "startY": 0, "endX": 10, "endY": 5],
            reference: Reference(target: .body(SolidId("solid-1")))
        )

        // 1. Overall under-constrained
        let geomUnder = SketchGeometryGenerator.generateGeometry(
            entities: [lineUnder],
            overallDOFStatus: .underConstrained(dof: 2)
        )
        #expect(geomUnder.colors[0] == SketchGeometryGenerator.underConstrainedColor.x)
        #expect(geomUnder.colors[1] == SketchGeometryGenerator.underConstrainedColor.y)
        #expect(geomUnder.colors[2] == SketchGeometryGenerator.underConstrainedColor.z)

        // 2. Overall fully-constrained
        let geomFully = SketchGeometryGenerator.generateGeometry(
            entities: [lineFully],
            overallDOFStatus: .fullyConstrained
        )
        #expect(geomFully.colors[0] == SketchGeometryGenerator.fullyConstrainedColor.x)
        #expect(geomFully.colors[1] == SketchGeometryGenerator.fullyConstrainedColor.y)
        #expect(geomFully.colors[2] == SketchGeometryGenerator.fullyConstrainedColor.z)

        // 3. Overall over-constrained
        let geomOver = SketchGeometryGenerator.generateGeometry(
            entities: [lineOver],
            overallDOFStatus: .overConstrained(dof: 1)
        )
        #expect(geomOver.colors[0] == SketchGeometryGenerator.overConstrainedColor.x)
        #expect(geomOver.colors[1] == SketchGeometryGenerator.overConstrainedColor.y)
        #expect(geomOver.colors[2] == SketchGeometryGenerator.overConstrainedColor.z)

        // 4. Per-entity override
        let geomMixed = SketchGeometryGenerator.generateGeometry(
            entities: [lineUnder, lineFully],
            entityDOFStatus: [
                lineUnder.id: .underConstrained(dof: 1),
                lineFully.id: .fullyConstrained
            ],
            overallDOFStatus: .inactive
        )
        // First entity is underConstrainedColor
        #expect(geomMixed.colors[0] == SketchGeometryGenerator.underConstrainedColor.x)
        // Second entity starts at index 8 (2 vertices * 4 color components)
        #expect(geomMixed.colors[8] == SketchGeometryGenerator.fullyConstrainedColor.x)

        // 5. Construction entity priority
        let geomConst = SketchGeometryGenerator.generateGeometry(
            entities: [lineConstruction],
            overallDOFStatus: .fullyConstrained
        )
        #expect(geomConst.colors[0] == SketchGeometryGenerator.defaultConstructionColor.x)

        // 6. Projected entity priority
        let geomProj = SketchGeometryGenerator.generateGeometry(
            entities: [lineProjected],
            overallDOFStatus: .underConstrained(dof: 1)
        )
        #expect(geomProj.colors[0] == SketchGeometryGenerator.drivenReferenceColor.x)

        // 7. Selection priority
        let geomSelected = SketchGeometryGenerator.generateGeometry(
            entities: [lineUnder],
            selectedEntityIds: [lineUnder.id],
            overallDOFStatus: .underConstrained(dof: 1)
        )
        #expect(geomSelected.colors[0] == SketchGeometryGenerator.defaultSelectedColor.x)

        // 8. Hover priority
        let geomHovered = SketchGeometryGenerator.generateGeometry(
            entities: [lineUnder],
            hoveredEntityId: lineUnder.id,
            overallDOFStatus: .underConstrained(dof: 1)
        )
        #expect(geomHovered.colors[0] == SketchGeometryGenerator.defaultHoveredColor.x)
    }
}
