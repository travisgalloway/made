import Testing
import Foundation
import CoreGraphics
import simd
@testable import MadeCore

@Suite @MainActor struct SimulationReportTests {

    private func makeSampleCompletedStudy() -> SimulationStudy {
        var study = SimulationStudy(
            name: "Cantilever Beam Analysis",
            studyType: .linearStatic,
            targets: [SimulationGeometryReference(targetId: UUID(), targetName: "Beam Body")],
            materials: [SimulationMaterialAssignment(name: "Structural Steel Mat", materialId: "structural-steel")],
            fixtures: [
                SimulationFixture(
                    name: "Fixed Root",
                    kind: .fixed,
                    targetReferences: [SimulationGeometryReference(targetId: UUID())],
                    isRestrainedX: true,
                    isRestrainedY: true,
                    isRestrainedZ: true
                )
            ],
            loads: [
                SimulationLoad(
                    name: "Tip Force",
                    kind: .force,
                    targetReferences: [SimulationGeometryReference(targetId: UUID())],
                    magnitude: 1000.0,
                    direction: SIMD3<Double>(0, 0, -1)
                )
            ]
        )
        study.factorOfSafetySettings.targetDesignFactor = 1.5

        study.mesh.elementOrder = .linear

        let qualityReport = MeshQualityReport(
            aspectRatioSummary: MeshQualityMetricSummary(kind: .aspectRatio, minValue: 1.1, maxValue: 3.2, averageValue: 1.8),
            scaledJacobianSummary: MeshQualityMetricSummary(kind: .scaledJacobian, minValue: 0.7, maxValue: 0.99, averageValue: 0.88),
            skewnessSummary: MeshQualityMetricSummary(kind: .skewness, minValue: 0.05, maxValue: 0.45, averageValue: 0.22)
        )
        let meshStats = SimulationMeshStatistics(
            nodeCount: 120,
            elementCount: 350,
            minElementQuality: 0.65,
            avgElementQuality: 0.82,
            qualityReport: qualityReport
        )

        let extrema = [
            SimulationFieldExtrema(fieldName: "von Mises Stress", unitSymbol: "MPa", minValue: 12.5, maxValue: 180.0),
            SimulationFieldExtrema(fieldName: "Displacement Magnitude", unitSymbol: "mm", minValue: 0.0, maxValue: 0.45)
        ]

        let rxn = SimulationConstraintReaction(
            id: study.fixtures[0].id,
            fixtureName: "Fixed Root",
            reactionForce: SIMD3<Double>(0, 0, 1000.0),
            reactionMoment: SIMD3<Double>(0, 50.0, 0),
            referencePoint: SIMD3<Double>(0, 0, 0),
            nodeCount: 15
        )

        let fos = FactorOfSafetyResult(
            basis: .yield,
            criterion: .vonMises,
            allowableStrengthMPa: 250.0,
            minFactorOfSafety: 2.1,
            maxFactorOfSafety: 12.0,
            criticalNodeId: 42,
            criticalStressMPa: 180.0,
            targetDesignFactor: 1.5,
            meetsDesignFactor: true
        )

        study.results = SimulationStudyResults(
            status: .completed,
            runtimeDuration: 1.25,
            meshStatistics: meshStats,
            extrema: extrema,
            nodalVonMisesStresses: [42: 180.0],
            factorOfSafety: fos,
            constraintReactions: [rxn]
        )

        return study
    }

    @Test func testReportDataExtractionFromCompletedStudy() {
        let study = makeSampleCompletedStudy()
        let data = SimulationReportGenerator.buildReportData(study: study)

        #expect(data.studyName == "Cantilever Beam Analysis")
        #expect(data.materials.count == 1)
        #expect(data.materials[0].name.contains("Structural Steel"))
        #expect(data.fixtures.count == 1)
        #expect(data.fixtures[0].name == "Fixed Root")
        #expect(data.loads.count == 1)
        #expect(data.loads[0].name == "Tip Force")
        #expect(data.nodeCount == 120)
        #expect(data.elementCount == 350)
        #expect(data.extrema.count == 2)
        #expect(data.reactions.count == 1)
        #expect(data.reactions[0].forceMag == 1000.0)
        #expect(data.conclusions.overallVerdict == .pass)
        #expect(data.conclusions.minFactorOfSafety == 2.1)
    }

    @Test func testConclusionsSynthesisPassingFoS() {
        let study = makeSampleCompletedStudy()
        let conclusions = SimulationReportGenerator.synthesizeConclusions(study: study)

        #expect(conclusions.overallVerdict == .pass)
        #expect(conclusions.minFactorOfSafety == 2.1)
        #expect(conclusions.targetDesignFactor == 1.5)
        #expect(conclusions.marginOfSafety != nil)
        if let margin = conclusions.marginOfSafety {
            #expect(margin > 0.3)
        }
        #expect(conclusions.factorOfSafetyAssessment.contains("satisfied"))
    }

    @Test func testConclusionsSynthesisFailingFoS() {
        var study = makeSampleCompletedStudy()

        // 1. Marginal case: minFoS 1.2 between 1.0 and target (1.5)
        var marginalFos = study.results.factorOfSafety!
        marginalFos.minFactorOfSafety = 1.2
        marginalFos.meetsDesignFactor = false
        study.results.factorOfSafety = marginalFos

        let marginalConclusions = SimulationReportGenerator.synthesizeConclusions(study: study)
        #expect(marginalConclusions.overallVerdict == .marginal)
        #expect(marginalConclusions.factorOfSafetyAssessment.contains("marginal"))

        // 2. Failing case: minFoS 0.75 below 1.0
        var failingFos = study.results.factorOfSafety!
        failingFos.minFactorOfSafety = 0.75
        failingFos.meetsDesignFactor = false
        study.results.factorOfSafety = failingFos

        let failingConclusions = SimulationReportGenerator.synthesizeConclusions(study: study)
        #expect(failingConclusions.overallVerdict == .fail)
        #expect(failingConclusions.factorOfSafetyAssessment.contains("failure"))
    }

    @Test func testConclusionsSynthesisStaticEquilibriumCheck() {
        var study = makeSampleCompletedStudy()

        // Exact balance: applied load is (0, 0, -1000) and reaction is (0, 0, 1000)
        let passingConclusions = SimulationReportGenerator.synthesizeConclusions(study: study)
        #expect(passingConclusions.isEquilibriumSatisfied == true)
        #expect(passingConclusions.reactionForceResidualN == 0.0)
        #expect(passingConclusions.staticEquilibriumAssessment?.contains("satisfied") == true)

        // Imbalance: reaction is only (0, 0, 500)
        let unbalancedRxn = SimulationConstraintReaction(
            id: study.fixtures[0].id,
            fixtureName: "Fixed Root",
            reactionForce: SIMD3<Double>(0, 0, 500.0),
            reactionMoment: .zero,
            referencePoint: .zero,
            nodeCount: 10
        )
        study.results.constraintReactions = [unbalancedRxn]

        let failingConclusions = SimulationReportGenerator.synthesizeConclusions(study: study)
        #expect(failingConclusions.isEquilibriumSatisfied == false)
        #expect(failingConclusions.reactionForceResidualN == 500.0)
        #expect(failingConclusions.staticEquilibriumAssessment?.contains("exceeds") == true)
    }

    @Test func testHTMLReportGenerationStructure() {
        let study = makeSampleCompletedStudy()
        let html = SimulationReportGenerator.generateHTML(study: study)

        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<html lang=\"en\">"))
        #expect(html.contains("Cantilever Beam Analysis"))
        #expect(html.contains("VERDICT: PASS"))
        #expect(html.contains("Study Setup &amp; Discretization"))
        #expect(html.contains("Mesh Statistics &amp; Discretization Quality"))
        #expect(html.contains("Results Extrema &amp; Graphical Plots"))
        #expect(html.contains("Constraint Reactions &amp; Static Equilibrium"))
        #expect(html.contains("Engineering Conclusions &amp; Synthesis"))
        #expect(html.contains("<svg"))
        #expect(html.contains("Factor of Safety Gauge"))
    }

    @Test func testHTMLReportWithProbesAndReactions() {
        var study = makeSampleCompletedStudy()
        let p1 = SimulationProbePoint(
            name: "Probe Point 1",
            kind: .point,
            position: SIMD3<Double>(10.0, 5.0, 2.0),
            nodeId: 42,
            fieldValues: [.vonMisesStress: 175.5]
        )
        study.probeTable.probes = [p1]

        let html = SimulationReportGenerator.generateHTML(study: study)
        #expect(html.contains("Probes &amp; Inspection Results"))
        #expect(html.contains("Probe Point 1"))
        #expect(html.contains("175.50"))
        #expect(html.contains("Fixed Root"))
        #expect(html.contains("1000.00"))
    }

    @Test func testPDFReportGeneration() throws {
        let study = makeSampleCompletedStudy()
        let pdfData = try SimulationReportGenerator.generatePDF(study: study)

        #expect(!pdfData.isEmpty)
        let header = String(decoding: pdfData.prefix(5), as: UTF8.self)
        #expect(header == "%PDF-")

        guard let provider = CGDataProvider(data: pdfData as CFData),
              let cgDoc = CGPDFDocument(provider) else {
            Issue.record("Failed to load generated PDF document")
            return
        }

        #expect(cgDoc.numberOfPages == 2)

        // Adding probe points should trigger Page 3 generation
        var studyWithProbes = study
        studyWithProbes.probeTable.probes = [
            SimulationProbePoint(name: "P1", position: .zero, fieldValues: [:])
        ]
        let pdfData3 = try SimulationReportGenerator.generatePDF(study: studyWithProbes)
        guard let provider3 = CGDataProvider(data: pdfData3 as CFData),
              let cgDoc3 = CGPDFDocument(provider3) else {
            Issue.record("Failed to load 3-page PDF document")
            return
        }
        #expect(cgDoc3.numberOfPages == 3)
    }

    @Test func testImperialUnitConversionInReport() {
        let study = makeSampleCompletedStudy()
        var options = SimulationReportOptions()
        options.lengthUnit = .inches

        let data = SimulationReportGenerator.buildReportData(study: study, options: options)
        #expect(data.stressUnitSymbol == "psi")
        #expect(data.forceUnitSymbol == "lbf")
        #expect(data.lengthUnitSymbol == "in")
        #expect(data.momentUnitSymbol == "lbf·in")

        // Peak stress 180 MPa should convert to psi: 180 * 145.0377... ≈ 26106.8 psi
        if let peak = data.peakStress {
            #expect(peak > 25000.0 && peak < 27000.0)
        }

        let html = SimulationReportGenerator.generateHTML(study: study, options: options)
        #expect(html.contains("psi"))
        #expect(html.contains("lbf"))
    }

    @Test func testEmptyOrUnsolvedStudyHandling() throws {
        let unrunStudy = SimulationStudy(name: "Empty Fresh Study", studyType: .linearStatic)
        let conclusions = SimulationReportGenerator.synthesizeConclusions(study: unrunStudy)

        #expect(conclusions.overallVerdict == .inconclusive)
        #expect(conclusions.factorOfSafetyAssessment.contains("not completed"))

        let html = SimulationReportGenerator.generateHTML(study: unrunStudy)
        #expect(html.contains("VERDICT: INCONCLUSIVE"))
        #expect(html.contains("No material assignments defined"))
        #expect(html.contains("No boundary fixtures defined"))

        let pdfData = try SimulationReportGenerator.generatePDF(study: unrunStudy)
        #expect(!pdfData.isEmpty)
        let header = String(decoding: pdfData.prefix(5), as: UTF8.self)
        #expect(header == "%PDF-")
    }
}
