import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct DrawingAnnotationTests {

    @Test func testLinearDimensionCalculations() {
        // Aligned
        var aligned = LinearDimensionData(
            startPointMM: SIMD2(0.0, 0.0),
            endPointMM: SIMD2(30.0, 40.0),
            offsetMM: 10.0,
            orientation: .aligned,
            prefix: "REF ",
            suffix: " mm",
            precision: 2
        )
        #expect(abs(aligned.measuredValue - 50.0) < 1e-6)
        #expect(aligned.formattedText == "REF 50.00 mm")

        aligned.textOverride = "APPROX 50"
        #expect(aligned.formattedText == "APPROX 50")

        // Horizontal
        let horizontal = LinearDimensionData(
            startPointMM: SIMD2(10.0, 20.0),
            endPointMM: SIMD2(70.0, 80.0),
            orientation: .horizontal,
            precision: 1
        )
        #expect(abs(horizontal.measuredValue - 60.0) < 1e-6)
        #expect(horizontal.formattedText == "60.0")

        // Vertical
        let vertical = LinearDimensionData(
            startPointMM: SIMD2(10.0, 20.0),
            endPointMM: SIMD2(70.0, 95.0),
            orientation: .vertical,
            precision: 0
        )
        #expect(abs(vertical.measuredValue - 75.0) < 1e-6)
        #expect(vertical.formattedText == "75")
    }

    @Test func testAngularDimensionCalculations() {
        // 90 degrees
        let rightAngle = AngularDimensionData(
            vertexMM: SIMD2(0.0, 0.0),
            startPointMM: SIMD2(20.0, 0.0),
            endPointMM: SIMD2(0.0, 20.0),
            precision: 1
        )
        #expect(abs(rightAngle.measuredDegrees - 90.0) < 1e-4)
        #expect(rightAngle.formattedText == "90.0°")

        // 45 degrees
        let acuteAngle = AngularDimensionData(
            vertexMM: SIMD2(0.0, 0.0),
            startPointMM: SIMD2(10.0, 0.0),
            endPointMM: SIMD2(10.0, 10.0),
            precision: 1
        )
        #expect(abs(acuteAngle.measuredDegrees - 45.0) < 1e-4)
        #expect(acuteAngle.formattedText == "45.0°")

        // 180 degrees
        let straightAngle = AngularDimensionData(
            vertexMM: SIMD2(0.0, 0.0),
            startPointMM: SIMD2(10.0, 0.0),
            endPointMM: SIMD2(-10.0, 0.0),
            precision: 0
        )
        #expect(abs(straightAngle.measuredDegrees - 180.0) < 1e-4)
        #expect(straightAngle.formattedText == "180°")
    }

    @Test func testRadialDimensionCalculations() {
        // Radius mode
        let radiusDim = RadialDimensionData(
            centerMM: SIMD2(0.0, 0.0),
            arcPointMM: SIMD2(0.0, 25.0),
            isDiameter: false,
            precision: 2
        )
        #expect(abs(radiusDim.measuredValue - 25.0) < 1e-6)
        #expect(radiusDim.formattedText == "R25.00")

        // Diameter mode
        let diameterDim = RadialDimensionData(
            centerMM: SIMD2(10.0, 10.0),
            arcPointMM: SIMD2(10.0, 30.0),
            isDiameter: true,
            precision: 1
        )
        #expect(abs(diameterDim.measuredValue - 40.0) < 1e-6)
        #expect(diameterDim.formattedText == "Ø40.0")
    }

    @Test func testOrdinateDimensionCalculations() {
        let datum = SIMD2(10.0, 15.0)

        // Origin datum
        let origin = OrdinateDimensionData(
            datumOriginMM: datum,
            locationMM: datum,
            axis: .x
        )
        #expect(origin.isDatum)
        #expect(origin.formattedText == "0")

        // X-axis ordinate
        let xOrd = OrdinateDimensionData(
            datumOriginMM: datum,
            locationMM: SIMD2(45.0, 15.0),
            axis: .x,
            precision: 2
        )
        #expect(!xOrd.isDatum)
        #expect(abs(xOrd.measuredValue - 35.0) < 1e-6)
        #expect(xOrd.formattedText == "35.00")

        // Y-axis ordinate
        let yOrd = OrdinateDimensionData(
            datumOriginMM: datum,
            locationMM: SIMD2(10.0, 60.0),
            axis: .y,
            precision: 1
        )
        #expect(!yOrd.isDatum)
        #expect(abs(yOrd.measuredValue - 45.0) < 1e-6)
        #expect(yOrd.formattedText == "45.0")
    }

    @Test func testBaselineDimensionCalculations() {
        let baseline = BaselineDimensionData(
            basePointMM: SIMD2(0.0, 0.0),
            targetPointsMM: [
                SIMD2(20.0, 0.0),
                SIMD2(50.0, 0.0),
                SIMD2(90.0, 0.0)
            ],
            stackSpacingMM: 8.0,
            initialOffsetMM: 10.0,
            orientation: .horizontal,
            precision: 1
        )

        #expect(baseline.targetPointsMM.count == 3)
        #expect(abs(baseline.measuredValue(forTargetIndex: 0) - 20.0) < 1e-6)
        #expect(abs(baseline.measuredValue(forTargetIndex: 1) - 50.0) < 1e-6)
        #expect(abs(baseline.measuredValue(forTargetIndex: 2) - 90.0) < 1e-6)

        #expect(abs(baseline.stackOffsetMM(forTargetIndex: 0) - 10.0) < 1e-6)
        #expect(abs(baseline.stackOffsetMM(forTargetIndex: 1) - 18.0) < 1e-6)
        #expect(abs(baseline.stackOffsetMM(forTargetIndex: 2) - 26.0) < 1e-6)

        #expect(baseline.formattedText(forTargetIndex: 0) == "20.0")
        #expect(baseline.formattedText(forTargetIndex: 1) == "50.0")
    }

    @Test func testNoteAndLeaderDataProperties() {
        let note = NoteAnnotationData(
            positionMM: SIMD2(50.0, 100.0),
            text: "MATERIAL: 6061-T6 ALUMINUM",
            fontSizePt: 12.0,
            isBold: true,
            hasBorder: true
        )
        #expect(note.text == "MATERIAL: 6061-T6 ALUMINUM")
        #expect(note.isBold)
        #expect(note.hasBorder)

        let leader = LeaderAnnotationData(
            arrowPointMM: SIMD2(10.0, 10.0),
            elbowPointMM: SIMD2(25.0, 25.0),
            text: "DEBURR ALL SHARP EDGES",
            landingLengthMM: 10.0,
            fontSizePt: 9.0
        )
        #expect(leader.landingLengthMM == 10.0)
        #expect(leader.text == "DEBURR ALL SHARP EDGES")
    }

    @Test func testCenterMarkAndCenterlineGeometry() {
        let centerMark = CenterMarkData(
            centerMM: SIMD2(40.0, 50.0),
            markSizeMM: 6.0,
            extensionMM: 4.0,
            rotationDegrees: 45.0
        )
        #expect(centerMark.markSizeMM == 6.0)
        #expect(centerMark.extensionMM == 4.0)
        #expect(centerMark.rotationDegrees == 45.0)

        let centerline = CenterlineData(
            startPointMM: SIMD2(10.0, 0.0),
            endPointMM: SIMD2(10.0, 100.0),
            extensionMM: 5.0
        )
        #expect(centerline.extensionMM == 5.0)
    }

    @Test func testHoleCalloutFormatterSimpleAndThrough() {
        // Simple through hole
        let throughHole = HoleCalloutAnnotationData(
            anchorPointMM: .zero,
            elbowPointMM: .zero,
            holeType: .simple,
            diameter: 8.0,
            depth: 20.0,
            isThrough: true,
            holeCount: 1
        )
        let throughLines = throughHole.formattedCalloutLines
        #expect(throughLines.count == 1)
        #expect(throughLines[0] == "Ø8 THRU")

        // Simple blind hole with quantity
        let blindHole = HoleCalloutAnnotationData(
            anchorPointMM: .zero,
            elbowPointMM: .zero,
            holeType: .simple,
            diameter: 6.5,
            depth: 18.0,
            isThrough: false,
            holeCount: 4
        )
        let blindLines = blindHole.formattedCalloutLines
        #expect(blindLines.count == 1)
        #expect(blindLines[0] == "4x Ø6.5 ↧ 18")
    }

    @Test func testHoleCalloutFormatterCounterboreAndCountersink() {
        // Counterbore hole
        let cbHole = HoleCalloutAnnotationData(
            anchorPointMM: .zero,
            elbowPointMM: .zero,
            holeType: .counterbore,
            diameter: 5.5,
            depth: 25.0,
            isThrough: true,
            counterboreDiameter: 10.0,
            counterboreDepth: 6.0,
            holeCount: 2
        )
        let cbLines = cbHole.formattedCalloutLines
        #expect(cbLines.count == 2)
        #expect(cbLines[0] == "2x Ø5.5 THRU")
        #expect(cbLines[1] == "⌴ Ø10 ↧ 6")

        // Countersink hole
        let csHole = HoleCalloutAnnotationData(
            anchorPointMM: .zero,
            elbowPointMM: .zero,
            holeType: .countersink,
            diameter: 4.5,
            depth: 15.0,
            isThrough: false,
            countersinkDiameter: 9.0,
            countersinkAngle: 90.0,
            holeCount: 1
        )
        let csLines = csHole.formattedCalloutLines
        #expect(csLines.count == 2)
        #expect(csLines[0] == "Ø4.5 ↧ 15")
        #expect(csLines[1] == "⌵ Ø9 x 90°")
    }

    @Test func testHoleCalloutFormatterTapped() {
        // Tapped through hole
        let tappedThrough = HoleCalloutAnnotationData(
            anchorPointMM: .zero,
            elbowPointMM: .zero,
            holeType: .tapped,
            diameter: 5.0,
            depth: 12.0,
            isThrough: true,
            threadDesignation: "M6x1.0",
            holeCount: 6
        )
        let tappedLines = tappedThrough.formattedCalloutLines
        #expect(tappedLines.count == 1)
        #expect(tappedLines[0] == "6x M6x1.0 THRU")

        // Tapped blind hole
        let tappedBlind = HoleCalloutAnnotationData(
            anchorPointMM: .zero,
            elbowPointMM: .zero,
            holeType: .tapped,
            diameter: 4.2,
            depth: 14.0,
            isThrough: false,
            threadDesignation: "M5x0.8",
            holeCount: 1
        )
        let blindLines = tappedBlind.formattedCalloutLines
        #expect(blindLines.count == 2)
        #expect(blindLines[0] == "M5x0.8 ↧ 14")
        #expect(blindLines[1] == "TAP DRILL Ø4.2")
    }

    @Test func testHoleCalloutFromHoleWizardParams() {
        let faceRef = TopologicalReference(
            sourceFeatureId: UUID(),
            elementType: .face,
            historyPath: [HistoryStep(kind: .generated, label: "face:top")]
        )
        let holeParams = HoleParams(
            targetSolidId: SolidId("solid-plate"),
            faceReference: faceRef,
            points: [SIMD2(0.0, 0.0), SIMD2(20.0, 0.0)],
            holeType: .counterbore,
            standard: .isoMetric,
            sizeDesignation: "M6",
            diameter: 6.6,
            depth: 22.0,
            isThrough: false,
            counterboreDiameter: 11.0,
            counterboreDepth: 6.5
        )

        let calloutData = HoleCalloutAnnotationData(
            anchorPointMM: SIMD2(10.0, 5.0),
            elbowPointMM: SIMD2(25.0, 20.0),
            holeParams: holeParams,
            holeCount: 2
        )

        #expect(calloutData.holeType == HoleType.counterbore)
        #expect(calloutData.diameter == 6.6)
        #expect(calloutData.counterboreDiameter == 11.0)
        #expect(calloutData.counterboreDepth == 6.5)
        #expect(calloutData.holeCount == 2)
        #expect(calloutData.formattedCalloutLines[0] == "2x Ø6.6 ↧ 22")
        #expect(calloutData.formattedCalloutLines[1] == "⌴ Ø11 ↧ 6.5")
    }

    @Test func testDrawingSheetAnnotationMutations() {
        var sheet = DrawingSheet(name: "Test Sheet")
        #expect(sheet.annotations.isEmpty)

        let note = DrawingAnnotation(
            name: "Title Note",
            data: .note(NoteAnnotationData(positionMM: SIMD2(20.0, 20.0), text: "CONFIDENTIAL"))
        )
        sheet.annotations.append(note)
        #expect(sheet.annotations.count == 1)
        #expect(sheet.annotations[0].name == "Title Note")
        #expect(sheet.annotations[0].kind == .note)

        // Mutate annotation
        sheet.annotations[0].name = "Updated Note"
        #expect(sheet.annotations[0].name == "Updated Note")

        // Remove annotation
        sheet.annotations.removeAll { $0.id == note.id }
        #expect(sheet.annotations.isEmpty)
    }

    @Test func testLegacyDrawingSheetDecodingWithoutAnnotations() throws {
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "name": "Legacy Sheet",
            "size": "isoA3",
            "orientation": "landscape",
            "scale": "1:1",
            "titleBlockTemplate": "isoStandard",
            "views": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let sheet = try decoder.decode(DrawingSheet.self, from: legacyJSON)
        #expect(sheet.name == "Legacy Sheet")
        #expect(sheet.annotations.isEmpty)
    }

    @Test func testDocumentModelAnnotationUndoRedo() {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.addSheet(DrawingSheet(name: "Annotation Test Sheet"))
        doc.setActiveSheetId(sheet.id)

        let annotation = DrawingAnnotation(
            name: "Part Length",
            data: .linear(LinearDimensionData(startPointMM: SIMD2(0.0, 0.0), endPointMM: SIMD2(100.0, 0.0)))
        )

        // 1. Add annotation
        let added = doc.addDrawingAnnotation(annotation, to: sheet.id)
        #expect(added != nil)
        #expect(doc.activeSheet?.annotations.count == 1)
        #expect(doc.selectedDrawingAnnotationId == annotation.id)

        // Undo add
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.annotations.isEmpty == true)
        #expect(doc.selectedDrawingAnnotationId == nil)

        // Redo add
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.annotations.count == 1)
        #expect(doc.selectedDrawingAnnotationId == annotation.id)

        // 2. Update annotation
        var updated = annotation
        updated.name = "Total Overall Length"
        doc.updateDrawingAnnotation(updated, on: sheet.id)
        #expect(doc.activeSheet?.annotations.first?.name == "Total Overall Length")

        // Undo update
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.annotations.first?.name == "Part Length")

        // Redo update
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.annotations.first?.name == "Total Overall Length")

        // 3. Remove annotation
        doc.removeDrawingAnnotation(id: annotation.id, from: sheet.id)
        #expect(doc.activeSheet?.annotations.isEmpty == true)
        #expect(doc.selectedDrawingAnnotationId == nil)

        // Undo removal
        doc.undoManager?.undo()
        #expect(doc.activeSheet?.annotations.count == 1)
        #expect(doc.activeSheet?.annotations.first?.name == "Total Overall Length")
        #expect(doc.selectedDrawingAnnotationId == annotation.id)

        // Redo removal
        doc.undoManager?.redo()
        #expect(doc.activeSheet?.annotations.isEmpty == true)
    }

    @Test func testDrawingPackageWithAnnotationsRoundTrip() throws {
        let doc = DocumentModel(documentType: .drawing)
        let sheet = doc.addSheet(DrawingSheet(name: "Fabrication Sheet", size: .isoA2))
        doc.setActiveSheetId(sheet.id)

        let dim = DrawingAnnotation(
            name: "Flange OD",
            data: .radial(RadialDimensionData(centerMM: SIMD2(50.0, 50.0), arcPointMM: SIMD2(80.0, 50.0), isDiameter: true))
        )
        let note = DrawingAnnotation(
            name: "Spec Note",
            data: .note(NoteAnnotationData(positionMM: SIMD2(100.0, 30.0), text: "ANODIZE PER MIL-A-8625"))
        )

        doc.addDrawingAnnotation(dim, to: sheet.id)
        doc.addDrawingAnnotation(note, to: sheet.id)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("TestDrawingAnnotations.made")
        let manifest = MadeManifest(
            schemaVersion: MadeManifest.currentSchemaVersion,
            appVersion: "0.1",
            documentSettings: doc.settings,
            documentType: doc.documentType,
            metadata: doc.metadata
        )
        let docData = DocumentData(
            schemaVersion: DocumentData.currentSchemaVersion,
            features: doc.features,
            documentType: doc.documentType,
            sheets: doc.sheets,
            activeSheetId: doc.activeSheetId
        )
        let package = MadePackage(manifest: manifest, documentData: docData)
        try package.write(to: packageURL)

        let loadedPackage = try MadePackage(directoryURL: packageURL)
        #expect(loadedPackage.manifest.documentType == .drawing)

        let loadedSheets = loadedPackage.documentData.sheets ?? []
        let loadedSheet = loadedSheets.first(where: { $0.id == sheet.id })
        #expect(loadedSheet != nil)
        #expect(loadedSheet?.annotations.count == 2)
        let hasDim = loadedSheet?.annotations.contains(where: { $0.name == "Flange OD" && $0.kind == .radial }) ?? false
        let hasNote = loadedSheet?.annotations.contains(where: { $0.name == "Spec Note" && $0.kind == .note }) ?? false
        #expect(hasDim)
        #expect(hasNote)
    }

    @Test func testBalloonAnnotationDataFormattingAndShapes() {
        var balloon = BalloonAnnotationData(
            anchorPointMM: SIMD2(10.0, 10.0),
            balloonCenterMM: SIMD2(30.0, 30.0),
            sizeMM: 12.0,
            shape: .circular,
            itemNumber: "5",
            quantity: 3,
            showQuantity: true
        )

        #expect(balloon.formattedText == "5")
        #expect(balloon.formattedQuantityText == "3")
        #expect(balloon.shape == .circular)
        #expect(balloon.sizeMM == 12.0)

        // Text override
        balloon.textOverride = "CUSTOM-ITEM"
        #expect(balloon.formattedText == "CUSTOM-ITEM")

        // Shape options
        balloon.shape = .splitCircular
        #expect(balloon.shape.displayName == "Split Circular")

        balloon.shape = .box
        #expect(balloon.shape.displayName == "Box")

        balloon.shape = .hexagon
        #expect(balloon.shape.displayName == "Hexagon")

        balloon.shape = .none
        #expect(balloon.shape.displayName == "None (Text Only)")

        // Contact point calculation
        let contact = balloon.boundaryContactPointMM()
        let radius = balloon.sizeMM * 0.5
        let dist = hypot(contact.x - balloon.balloonCenterMM.x, contact.y - balloon.balloonCenterMM.y)
        #expect(abs(dist - radius) < 1e-4)
    }

    @Test func testBalloonDegenerateLeaderClamping() {
        // Coincident center and anchor points
        let coincident = BalloonAnnotationData(
            anchorPointMM: SIMD2(40.0, 40.0),
            balloonCenterMM: SIMD2(40.0, 40.0),
            sizeMM: 10.0
        )

        let contact = coincident.boundaryContactPointMM()
        #expect(!contact.x.isNaN && !contact.x.isInfinite)
        #expect(!contact.y.isNaN && !contact.y.isInfinite)

        let dist = hypot(contact.x - coincident.balloonCenterMM.x, contact.y - coincident.balloonCenterMM.y)
        #expect(dist >= 2.5)
    }

    @Test func testLegacyAnnotationDecodingCompatibility() throws {
        let legacyJson = """
        {
            "id": "\(UUID().uuidString)",
            "name": "General Note",
            "data": {
                "note": {
                    "_0": {
                        "positionMM": [10.0, 20.0],
                        "text": "DO NOT SCALE DRAWING",
                        "fontSizePt": 9.0,
                        "isBold": false,
                        "hasBorder": false
                    }
                }
            },
            "isVisible": true,
            "customProperties": {},
            "isDangling": false
        }
        """

        let data = Data(legacyJson.utf8)
        let decoded = try JSONDecoder().decode(DrawingAnnotation.self, from: data)

        #expect(decoded.name == "General Note")
        #expect(decoded.kind == .note)
        #expect(decoded.isDangling == false)
    }

    @Test func testBalloonAnnotationCodableRoundTrip() throws {
        let compId = UUID()
        let balloonData = BalloonAnnotationData(
            anchorPointMM: SIMD2(25.0, 35.0),
            balloonCenterMM: SIMD2(50.0, 60.0),
            sizeMM: 11.0,
            shape: .splitCircular,
            itemNumber: "7",
            quantity: 2,
            showQuantity: true,
            textOverride: "7A",
            componentInstanceId: compId,
            componentName: "Motor Mount"
        )
        let annotation = DrawingAnnotation(
            name: "Balloon Callout 1",
            data: .balloon(balloonData)
        )

        let encoded = try JSONEncoder().encode(annotation)
        let decoded = try JSONDecoder().decode(DrawingAnnotation.self, from: encoded)

        #expect(decoded.name == "Balloon Callout 1")
        #expect(decoded.kind == .balloon)

        if case .balloon(let d) = decoded.data {
            #expect(d.anchorPointMM == SIMD2(25.0, 35.0))
            #expect(d.balloonCenterMM == SIMD2(50.0, 60.0))
            #expect(d.sizeMM == 11.0)
            #expect(d.shape == .splitCircular)
            #expect(d.itemNumber == "7")
            #expect(d.quantity == 2)
            #expect(d.showQuantity == true)
            #expect(d.textOverride == "7A")
            #expect(d.componentInstanceId == compId)
            #expect(d.componentName == "Motor Mount")
        } else {
            Issue.record("Expected .balloon data")
        }
    }

    @Test func testBalloonResolvesItemNumberWithoutPlacedTable() {
        let comp1 = ComponentInstance(
            name: "Baseplate",
            reference: .internalPart(name: "Baseplate", bodyId: nil),
            metadata: [CustomPropertyKey.partNumber: "BP-001"]
        )
        let comp2 = ComponentInstance(
            name: "Shaft",
            reference: .internalPart(name: "Shaft", bodyId: nil),
            metadata: [CustomPropertyKey.partNumber: "SH-002"]
        )

        let doc = DocumentModel(documentType: .assembly, componentInstances: [comp1, comp2], sheets: [DrawingSheet()])
        #expect(doc.sheets.first?.bomTables.isEmpty == true)

        let bom = BillOfMaterials.generate(from: doc, structure: .flat)
        #expect(bom.items.count == 2)

        let baseplateItem = bom.items.first(where: { $0.partNumber == "BP-001" })
        #expect(baseplateItem?.itemNumber == "1")

        let shaftItem = bom.items.first(where: { $0.partNumber == "SH-002" })
        #expect(shaftItem?.itemNumber == "2")
    }

    @Test func testBalloonAssociativityDanglingStateOnComponentRemoval() {
        let compId = UUID()
        let comp = ComponentInstance(
            id: compId,
            name: "Gear",
            reference: .internalPart(name: "Gear", bodyId: nil),
            metadata: [CustomPropertyKey.partNumber: "GR-001"]
        )

        var sheet = DrawingSheet(name: "Sheet 1")
        let balloonData = BalloonAnnotationData(
            anchorPointMM: SIMD2(10.0, 10.0),
            balloonCenterMM: SIMD2(30.0, 30.0),
            itemNumber: "1",
            componentInstanceId: compId,
            componentName: "Gear"
        )
        let annotation = DrawingAnnotation(
            name: "Gear Balloon",
            data: .balloon(balloonData),
            isDangling: false
        )
        sheet.annotations = [annotation]

        let doc = DocumentModel(documentType: .assembly, componentInstances: [comp], sheets: [sheet])
        #expect(doc.sheets.first?.annotations.first?.isDangling == false)

        // 1. Remove component instance -> triggers associativity update
        _ = doc.removeComponentInstance(id: compId)
        #expect(doc.sheets.first?.annotations.first?.isDangling == true)

        // 2. Undo removal -> component restored, recovers dangling state
        doc.undoManager?.undo()
        #expect(doc.sheets.first?.annotations.first?.isDangling == false)
    }
}
