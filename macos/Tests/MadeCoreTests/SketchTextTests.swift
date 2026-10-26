import Testing
import Foundation
import simd
@testable import MadeCore

@Suite struct SketchTextTests {

    @Test func testSketchEntityTextPropertiesAndCodable() throws {
        var entity = SketchEntity.text(
            text: "Hello",
            origin: SIMD2(10.0, 20.0),
            fontSize: 16.0,
            fontName: "Helvetica",
            isConstruction: false
        )

        #expect(entity.kind == "text")
        #expect(entity.text == "Hello")
        #expect(entity.textString == "Hello")
        #expect(entity.fontName == "Helvetica")
        #expect(entity.origin == SIMD2(10.0, 20.0))
        #expect(entity.fontSize == 16.0)
        #expect(entity.isConstruction == false)

        // Mutators
        entity.textString = "World"
        #expect(entity.text == "World")
        entity.origin = SIMD2(5.0, 15.0)
        #expect(entity.origin == SIMD2(5.0, 15.0))
        entity.fontSize = 24.0
        #expect(entity.fontSize == 24.0)

        // Codable round trip
        let encoder = JSONEncoder()
        let data = try encoder.encode(entity)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SketchEntity.self, from: data)

        #expect(decoded.id == entity.id)
        #expect(decoded.kind == "text")
        #expect(decoded.text == "World")
        #expect(decoded.fontName == "Helvetica")
        #expect(decoded.origin == SIMD2(5.0, 15.0))
        #expect(decoded.fontSize == 24.0)

        // Legacy JSON backward compatibility without text and fontName fields
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "kind": "line",
            "data": { "startX": 0, "startY": 0, "endX": 10, "endY": 10 },
            "isConstruction": false
        }
        """.data(using: .utf8)!

        let legacyDecoded = try decoder.decode(SketchEntity.self, from: legacyJSON)
        #expect(legacyDecoded.kind == "line")
        #expect(legacyDecoded.text == nil)
        #expect(legacyDecoded.fontName == nil)
    }

    @Test func testSketchTextOutlinerContours() {
        let entity = SketchEntity.text(
            text: "O",
            origin: SIMD2(0, 0),
            fontSize: 20.0,
            fontName: "Helvetica"
        )

        let contours = SketchTextOutliner.extractContours(for: entity)
        // Letter 'O' has an outer contour and an inner counter contour
        #expect(contours.count == 2)
        for c in contours {
            #expect(c.count >= 3)
        }

        // Fallback font test: unrecognized font name should not crash
        let fallbackContours = SketchTextOutliner.extractContours(
            text: "C",
            fontName: "NonExistentFontName123",
            fontSize: 18.0,
            origin: .zero
        )
        #expect(!fallbackContours.isEmpty)

        // Multi-line text layout test
        let multilineContours = SketchTextOutliner.extractContours(
            text: "A\nB",
            fontName: "Helvetica",
            fontSize: 20.0,
            origin: .zero
        )
        #expect(multilineContours.count >= 4) // At least 2 contours for A and 2 for B
    }

    @Test func testSketchTextNestedHoles() {
        // 'O' should have 1 outer boundary and 1 hole
        let oEntity = SketchEntity.text(text: "O", fontSize: 24.0)
        let oRegions = SketchTextOutliner.extractRegions(for: oEntity)
        #expect(oRegions.count == 1)
        #expect(oRegions[0].innerLoops.count == 1)
        #expect(oRegions[0].area > 0)

        // 'B' should have 1 outer boundary and 2 holes
        let bEntity = SketchEntity.text(text: "B", fontSize: 24.0)
        let bRegions = SketchTextOutliner.extractRegions(for: bEntity)
        #expect(bRegions.count == 1)
        #expect(bRegions[0].innerLoops.count == 2)
        #expect(bRegions[0].area > 0)

        // '8' should have 1 outer boundary and 2 holes
        let eightEntity = SketchEntity.text(text: "8", fontSize: 24.0)
        let eightRegions = SketchTextOutliner.extractRegions(for: eightEntity)
        #expect(eightRegions.count == 1)
        #expect(eightRegions[0].innerLoops.count == 2)
        #expect(eightRegions[0].area > 0)

        // 'A' should have 1 outer boundary and 1 hole
        let aEntity = SketchEntity.text(text: "A", fontSize: 24.0)
        let aRegions = SketchTextOutliner.extractRegions(for: aEntity)
        #expect(aRegions.count == 1)
        #expect(aRegions[0].innerLoops.count == 1)
        #expect(aRegions[0].area > 0)

        // 'i' should have 2 disconnected solid regions (stem and dot)
        let iEntity = SketchEntity.text(text: "i", fontSize: 24.0)
        let iRegions = SketchTextOutliner.extractRegions(for: iEntity)
        #expect(iRegions.count == 2)

        // "AB" should produce 2 solid regions
        let abEntity = SketchEntity.text(text: "AB", fontSize: 24.0)
        let abRegions = SketchTextOutliner.extractRegions(for: abEntity)
        #expect(abRegions.count == 2)
    }

    @Test func testSketchProfileBuilderTextValidation() {
        let valid = SketchEntity.text(text: "Hello", origin: SIMD2(0, 0), fontSize: 12.0)
        #expect(throws: Never.self) {
            try SketchProfileBuilder.validateEntity(valid)
        }

        // Empty text
        let empty = SketchEntity(kind: "text", data: ["originX": 0, "originY": 0, "fontSize": 12], text: "")
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.validateEntity(empty)
        }

        // Whitespace only
        let whitespace = SketchEntity(kind: "text", data: ["originX": 0, "originY": 0, "fontSize": 12], text: "   \n\t")
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.validateEntity(whitespace)
        }

        // Zero font size
        let zeroSize = SketchEntity(kind: "text", data: ["originX": 0, "originY": 0, "fontSize": 0], text: "Valid")
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.validateEntity(zeroSize)
        }

        // Negative font size
        let negSize = SketchEntity(kind: "text", data: ["originX": 0, "originY": 0, "fontSize": -10], text: "Valid")
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.validateEntity(negSize)
        }

        // NaN origin
        let nanOrigin = SketchEntity(kind: "text", data: ["originX": .nan, "originY": 0, "fontSize": 12], text: "Valid")
        #expect(throws: SketchError.self) {
            try SketchProfileBuilder.validateEntity(nanOrigin)
        }
    }

    @Test func testSketchRegionDetectorTextRegions() throws {
        let bEntity = SketchEntity.text(text: "B", fontSize: 30.0)
        let regions = try SketchRegionDetector.detectRegions(from: [bEntity])
        #expect(regions.count == 1)
        #expect(regions[0].innerLoops.count == 2)
        #expect(regions[0].area > 0)

        // Combined geometric circle and text
        let circle = SketchEntity.circle(center: SIMD2(100, 100), radius: 10.0)
        let combined = try SketchRegionDetector.detectRegions(from: [bEntity, circle])
        #expect(combined.count == 2)
    }

    @MainActor
    @Test func testSketchTextExtrusionProfile() throws {
        let textEntity = SketchEntity.text(text: "O", fontSize: 20.0)
        let profile = try SketchProfileBuilder.build(from: [textEntity], plane: .xy)

        #expect(!profile.points.isEmpty)
        #expect(profile.holes.count == 1)

        // Extrude text profile using DocumentModel
        let doc = DocumentModel()
        let sketchFeat = doc.addSketchFeature(planeName: "xy", entities: [textEntity])
        let extrudeFeat = try doc.extrudeSketch(
            sketchFeatureId: sketchFeat.id,
            distance: 5.0
        )

        if case .extrude(let extrudeData) = extrudeFeat.operation {
            #expect(extrudeData.sketchFeatureId == sketchFeat.id)
            #expect(extrudeData.distance == 5.0)
        } else {
            Issue.record("Expected extrude operation")
        }
    }
}
