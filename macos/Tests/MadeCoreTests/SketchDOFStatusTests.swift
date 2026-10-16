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
}
