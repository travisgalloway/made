import Testing
import Foundation
import simd
@testable import MadeCore

@Suite @MainActor struct CADToolsTests {
    @Test func testGetSceneReturnsDefaultSolids() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let result = await registry.callTool(name: "cad_get_scene", arguments: [:])
        
        #expect(result.isError == false)
        guard let text = result.content.first?.text else {
            Issue.record("Expected text content")
            return
        }
        
        #expect(text.contains("box-1"))
        #expect(text.contains("cylinder-1"))
    }
    
    @Test func testAddSolidCreatesNewBox() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let args: [String: AnyCodableValue] = [
            "type": .string("box"),
            "width": .double(55),
            "depth": .double(35),
            "height": .double(25)
        ]
        
        let result = await registry.callTool(name: "cad_add_solid", arguments: args)
        
        #expect(result.isError == false)
        #expect(doc.objects.count == 3)
        let added = doc.objects.last
        #expect(added != nil)
        if case .box(let p) = added?.def {
            #expect(p.width == 55)
            #expect(p.depth == 35)
            #expect(p.height == 25)
        } else {
            Issue.record("Expected box solid")
        }
    }
    
    @Test func testAddSolidClampsOutOfRangeBox() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let args: [String: AnyCodableValue] = [
            "type": .string("box"),
            "width": .double(500),
            "depth": .double(-3),
            "height": .double(20)
        ]
        let result = await registry.callTool(name: "cad_add_solid", arguments: args)
        #expect(result.isError == false)
        if case .box(let p) = doc.objects.last?.def {
            #expect(p.width == 90)
            #expect(p.depth == 5)
            #expect(p.height == 20)
        } else {
            Issue.record("Expected box solid")
        }
    }

    @Test func testAddSolidCreatesClampedCylinder() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let args: [String: AnyCodableValue] = [
            "type": .string("cylinder"),
            "radius": .double(0),
            "height": .double(200)
        ]
        let result = await registry.callTool(name: "cad_add_solid", arguments: args)
        #expect(result.isError == false)
        if case .cylinder(let p) = doc.objects.last?.def {
            #expect(p.radius == 5)
            #expect(p.height == 90)
        } else {
            Issue.record("Expected cylinder solid")
        }
    }

    @Test func testSetParamClampsAndUpdates() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let args: [String: AnyCodableValue] = [
            "id": .string("box-1"),
            "param": .string("width"),
            "value": .double(500) // Exceeds max 90
        ]
        
        let result = await registry.callTool(name: "cad_set_param", arguments: args)
        #expect(result.isError == false)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("to 90.0"))
        #expect(!text.contains("500"))
        
        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            #expect(p.width == 90.0) // Clamped to 90
        } else {
            Issue.record("Expected box params")
        }
    }
    
    private func setParam(_ doc: DocumentModel, _ args: [String: AnyCodableValue]) async -> MCPToolCallResult {
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        return await CADToolRegistry(document: doc, kernelClient: kernel).callTool(name: "cad_set_param", arguments: args)
    }
    
    @Test func testSetParamRejectsUnknownName() async {
        let doc = DocumentModel()
        let before = doc.paramsFor(id: boxSolidId)
        let result = await setParam(doc, ["id": .string("box-1"), "param": .string("color"), "value": .double(5)])
        #expect(result.isError == true)
        let text = result.content.first?.text ?? ""
        #expect(text.contains("'width', 'depth', 'height'"))
        #expect(doc.paramsFor(id: boxSolidId) == before)
    }
    
    @Test func testSetParamRejectsCylinderNameOnBox() async {
        let doc = DocumentModel()
        let before = doc.paramsFor(id: boxSolidId)
        let result = await setParam(doc, ["id": .string("box-1"), "param": .string("radius"), "value": .double(10)])
        #expect(result.isError == true)
        #expect(doc.paramsFor(id: boxSolidId) == before)
    }
    
    @Test func testSetParamRejectsBoxNameOnCylinder() async {
        let doc = DocumentModel()
        let cyl = SolidId("cylinder-1")
        let before = doc.paramsFor(id: cyl)
        let result = await setParam(doc, ["id": .string("cylinder-1"), "param": .string("width"), "value": .double(10)])
        #expect(result.isError == true)
        #expect(doc.paramsFor(id: cyl) == before)
    }
    
    @Test func testSetParamRejectsImportedSolid() async {
        let doc = DocumentModel()
        let id = doc.addObject(def: .imported(name: "part"))
        let result = await setParam(doc, ["id": .string(id.rawValue), "param": .string("height"), "value": .double(10)])
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains("imported") == true)
        #expect(doc.paramsFor(id: id) == .imported(name: "part"))
    }
    
    @Test func testSetParamRejectsUnknownSolid() async {
        let result = await setParam(DocumentModel(), ["id": .string("nope"), "param": .string("width"), "value": .double(10)])
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains("not found") == true)
    }
    
    @Test func testSetParamRejectsMissingParam() async {
        let result = await setParam(DocumentModel(), ["id": .string("box-1"), "value": .double(10)])
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains("param") == true)
    }
    
    @Test func testSetParamRejectsNaN() async {
        let doc = DocumentModel()
        let before = doc.paramsFor(id: boxSolidId)
        let result = await setParam(doc, ["id": .string("box-1"), "param": .string("width"), "value": .double(.nan)])
        #expect(result.isError == true)
        #expect(doc.paramsFor(id: boxSolidId) == before)
    }
    
    @Test func testSetParamClampsBelowMinimum() async {
        let doc = DocumentModel()
        let result = await setParam(doc, ["id": .string("cylinder-1"), "param": .string("radius"), "value": .double(1)])
        #expect(result.isError == false)
        #expect(result.content.first?.text?.contains("to 5.0") == true)
        if case .cylinder(let p) = doc.paramsFor(id: SolidId("cylinder-1")) {
            #expect(p.radius == 5.0)
        } else {
            Issue.record("Expected cylinder params")
        }
    }
    
    @Test func testMeasureReturnsCorrectVolume() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        // Default box: 40 x 30 x 20 = 24,000 mm3
        let result = await registry.callTool(name: "cad_measure", arguments: ["id": .string("box-1")])
        #expect(result.isError == false)
        
        guard let text = result.content.first?.text else {
            Issue.record("Expected text content")
            return
        }
        
        #expect(text.contains("24000"))
    }
    
    @Test func testRemoveSolidDeletesFromDocument() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let result = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string("box-1")])
        #expect(result.isError == false)
        #expect(doc.objects.count == 1)
        #expect(!doc.objects.contains(where: { $0.id == boxSolidId }))
    }
    
    @Test func testRemoveSolidReleasesKernelCache() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let box = await kernel.request(.makeBox(jobId: JobId("jb"), solidId: boxSolidId, params: BoxParams(width: 40, depth: 30, height: 20)))
        let cyl = await kernel.request(.makeCylinder(jobId: JobId("jc"), solidId: cylinderSolidId, params: CylinderParams(radius: 15, height: 40)))
        #expect(box.isSuccess && cyl.isSuccess)
        
        _ = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string("box-1")])
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: [
            "solidA": .string("box-1"), "solidB": .string("cylinder-1"), "operation": .string("union")
        ])
        
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains("not found") == true)
    }
    
    @Test func testRemoveUnknownSolidReturnsError() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let result = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string("nope")])
        
        #expect(result.isError == true)
        #expect(doc.objects.count == 2)
    }

    @Test func testToolsListCaptureSnapshot() {
        let registry = CADToolRegistry(document: DocumentModel(), kernelClient: KernelClient(debounceDuration: .milliseconds(5)))
        #expect(registry.tools.contains { $0.name == "cad_capture_snapshot" })
    }

    @Test func testCaptureSnapshotWithoutProviderReportsNoDevice() async {
        let registry = CADToolRegistry(document: DocumentModel(), kernelClient: KernelClient(debounceDuration: .milliseconds(5)))

        let result = await registry.callTool(name: "cad_capture_snapshot", arguments: [:])

        #expect(result.isError == true)
        #expect(result.content.first?.text == "Error: Snapshot unavailable: no Metal 4 device is available to render the viewport")
    }

    @Test func testCaptureSnapshotFailureIsDistinctFromNoProvider() async {
        let provider = FailingSnapshotProvider()
        let registry = CADToolRegistry(document: DocumentModel(), kernelClient: KernelClient(debounceDuration: .milliseconds(5)), snapshotProvider: provider)

        let result = await registry.callTool(name: "cad_capture_snapshot", arguments: [:])
        withExtendedLifetime(provider) {}

        #expect(result.isError == true)
        #expect(result.content.first?.text == "Error: Snapshot capture failed: the viewport frame could not be rendered or encoded")
    }
    // MARK: - cad_add_solid and cad_set_transform argument validation (#98)
    
    private func addSolid(_ doc: DocumentModel, _ args: [String: AnyCodableValue]) async -> MCPToolCallResult {
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        return await CADToolRegistry(document: doc, kernelClient: kernel).callTool(name: "cad_add_solid", arguments: args)
    }
    
    private func setTransform(_ doc: DocumentModel, _ args: [String: AnyCodableValue]) async -> MCPToolCallResult {
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        return await CADToolRegistry(document: doc, kernelClient: kernel).callTool(name: "cad_set_transform", arguments: args)
    }
    
    private func expectAddRejected(_ args: [String: AnyCodableValue], mentioning key: String) async {
        let doc = DocumentModel()
        let count = doc.objects.count
        let result = await addSolid(doc, args)
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains(key) == true)
        #expect(doc.objects.count == count)
    }
    
    private func expectSetRejected(_ args: [String: AnyCodableValue], mentioning key: String) async {
        let doc = DocumentModel()
        let before = doc.objects.first(where: { $0.id == boxSolidId })?.transform
        var full = args
        full["id"] = .string("box-1")
        let result = await setTransform(doc, full)
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains(key) == true)
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.transform == before)
    }
    
    private func boxPosition(_ doc: DocumentModel) -> SIMD3<Float>? {
        doc.objects.first(where: { $0.id == boxSolidId })?.transform.position
    }
    
    @Test func testAddSolidRejectsStringPosition() async {
        await expectAddRejected(["type": .string("box"), "posX": .string("10")], mentioning: "posX")
    }
    
    @Test func testAddSolidRejectsPositionAboveFloatMax() async {
        await expectAddRejected(["type": .string("box"), "posY": .double(1e39)], mentioning: "10000")
    }
    
    @Test func testAddSolidRejectsInfinitePosition() async {
        await expectAddRejected(["type": .string("box"), "posZ": .double(.infinity)], mentioning: "finite")
    }
    
    @Test func testAddSolidRejectsNullPosition() async {
        await expectAddRejected(["type": .string("box"), "posX": .null], mentioning: "must be a number")
    }
    
    @Test func testAddSolidRejectsStringSize() async {
        await expectAddRejected(["type": .string("box"), "width": .string("55")], mentioning: "width")
    }
    
    @Test func testAddSolidRejectsInfiniteSize() async {
        await expectAddRejected(["type": .string("cylinder"), "radius": .double(.infinity)], mentioning: "radius")
    }
    
    @Test func testAddSolidRejectsNonNumericStringSize() async {
        await expectAddRejected(["type": .string("box"), "width": .string("abc")], mentioning: "width")
        await expectAddRejected(["type": .string("box"), "depth": .string("def")], mentioning: "depth")
        await expectAddRejected(["type": .string("box"), "height": .string("ghi")], mentioning: "height")
        await expectAddRejected(["type": .string("cylinder"), "radius": .string("jkl")], mentioning: "radius")
        await expectAddRejected(["type": .string("cylinder"), "height": .string("mno")], mentioning: "height")
    }

    @Test func testAddSolidRejectsStringHoldingNumber() async {
        await expectAddRejected(["type": .string("box"), "width": .string("40")], mentioning: "width")
        await expectAddRejected(["type": .string("cylinder"), "radius": .string("15")], mentioning: "radius")
    }

    @Test func testAddSolidRejectsDimensionOverflowingFloat() async {
        await expectAddRejected(["type": .string("box"), "width": .double(1e39)], mentioning: "finite")
        await expectAddRejected(["type": .string("box"), "depth": .double(1e39)], mentioning: "finite")
        await expectAddRejected(["type": .string("box"), "height": .double(1e39)], mentioning: "finite")
        await expectAddRejected(["type": .string("cylinder"), "radius": .double(1e39)], mentioning: "finite")
        await expectAddRejected(["type": .string("cylinder"), "height": .double(1e39)], mentioning: "finite")
    }

    @Test func testAddSolidRejectsNullDimension() async {
        await expectAddRejected(["type": .string("box"), "width": .null], mentioning: "width")
        await expectAddRejected(["type": .string("cylinder"), "radius": .null], mentioning: "radius")
    }

    @Test func testAddSolidRejectsBooleanDimension() async {
        await expectAddRejected(["type": .string("box"), "height": .bool(true)], mentioning: "height")
        await expectAddRejected(["type": .string("cylinder"), "radius": .bool(false)], mentioning: "radius")
    }

    @Test func testAddSolidClampsNegativeDimension() async {
        let doc = DocumentModel()
        let result = await addSolid(doc, [
            "type": .string("box"),
            "width": .double(-10),
            "depth": .double(-5),
            "height": .double(-2)
        ])
        #expect(result.isError == false)
        #expect(result.content.first?.text == "Successfully added solid with ID: box-2 with dimensions (width: 5.0, depth: 5.0, height: 5.0) at position (0.0, 0.0, 0.0)")
        if case .box(let p) = doc.objects.last?.def {
            #expect(p.width == 5.0)
            #expect(p.depth == 5.0)
            #expect(p.height == 5.0)
        } else {
            Issue.record("Expected box solid")
        }
    }

    @Test func testAddSolidSuccessMessageReportsClampedDimensionsAndPosition() async {
        let docBox = DocumentModel()
        let boxResult = await addSolid(docBox, [
            "type": .string("box"),
            "width": .double(120),
            "depth": .double(2),
            "height": .double(25),
            "posX": .double(10),
            "posY": .double(-20),
            "posZ": .double(30)
        ])
        #expect(boxResult.isError == false)
        #expect(boxResult.content.first?.text == "Successfully added solid with ID: box-2 with dimensions (width: 90.0, depth: 5.0, height: 25.0) at position (10.0, -20.0, 30.0)")

        let docCyl = DocumentModel()
        let cylResult = await addSolid(docCyl, [
            "type": .string("cylinder"),
            "radius": .double(80),
            "height": .double(2),
            "posX": .double(5),
            "posY": .double(0),
            "posZ": .double(-10)
        ])
        #expect(cylResult.isError == false)
        #expect(cylResult.content.first?.text == "Successfully added solid with ID: cylinder-2 with dimensions (radius: 50.0, height: 5.0) at position (5.0, 0.0, -10.0)")
    }

    @Test func testAddSolidDefaultsMissingDimensions() async {
        let docBox = DocumentModel()
        let boxResult = await addSolid(docBox, ["type": .string("box")])
        #expect(boxResult.isError == false)
        #expect(boxResult.content.first?.text == "Successfully added solid with ID: box-2 with dimensions (width: 40.0, depth: 30.0, height: 20.0) at position (0.0, 0.0, 0.0)")
        if case .box(let p) = docBox.objects.last?.def {
            #expect(p.width == 40.0)
            #expect(p.depth == 30.0)
            #expect(p.height == 20.0)
        } else {
            Issue.record("Expected box solid")
        }
        #expect(docBox.objects.last?.transform.position == SIMD3<Float>(0, 0, 0))

        let docCyl = DocumentModel()
        let cylResult = await addSolid(docCyl, ["type": .string("cylinder")])
        #expect(cylResult.isError == false)
        #expect(cylResult.content.first?.text == "Successfully added solid with ID: cylinder-2 with dimensions (radius: 15.0, height: 40.0) at position (0.0, 0.0, 0.0)")
        if case .cylinder(let p) = docCyl.objects.last?.def {
            #expect(p.radius == 15.0)
            #expect(p.height == 40.0)
        } else {
            Issue.record("Expected cylinder solid")
        }
        #expect(docCyl.objects.last?.transform.position == SIMD3<Float>(0, 0, 0))
    }
    
    @Test func testAddSolidAcceptsIntegerPosition() async {
        let doc = DocumentModel()
        let result = await addSolid(doc, ["type": .string("box"), "posX": .int(12)])
        #expect(result.isError == false)
        #expect(doc.objects.last?.transform.position.x == 12)
    }
    
    @Test func testAddSolidDefaultsMissingPosition() async {
        let doc = DocumentModel()
        let result = await addSolid(doc, ["type": .string("box"), "posX": .double(5)])
        #expect(result.isError == false)
        #expect(doc.objects.last?.transform.position == SIMD3<Float>(5, 0, 0))
    }
    
    @Test func testAddSolidAcceptsPositionAtBound() async {
        let doc = DocumentModel()
        let result = await addSolid(doc, ["type": .string("box"), "posX": .double(10_000), "posY": .double(-10_000)])
        #expect(result.isError == false)
        #expect(doc.objects.last?.transform.position == SIMD3<Float>(10_000, -10_000, 0))
    }
    
    @Test func testAddSolidRejectsPositionPastBound() async {
        await expectAddRejected(["type": .string("box"), "posX": .double(10_000.5)], mentioning: "10000")
    }
    
    @Test func testSetTransformMovesSolid() async {
        let doc = DocumentModel()
        let result = await setTransform(doc, ["id": .string("box-1"), "posX": .double(1), "posY": .double(2), "posZ": .double(3)])
        #expect(result.isError == false)
        #expect(result.content.first?.text?.contains("(1.0, 2.0, 3.0)") == true)
        #expect(boxPosition(doc) == SIMD3<Float>(1, 2, 3))
    }
    
    @Test func testSetTransformRejectsStringPosition() async {
        await expectSetRejected(["posX": .string("10")], mentioning: "posX")
    }
    
    @Test func testSetTransformRejectsPositionAboveFloatMax() async {
        await expectSetRejected(["posX": .double(1e39)], mentioning: "10000")
    }
    
    @Test func testSetTransformRejectsInfinity() async {
        await expectSetRejected(["posY": .double(.infinity)], mentioning: "finite")
    }
    
    @Test func testSetTransformRejectsNaN() async {
        await expectSetRejected(["posZ": .double(.nan)], mentioning: "finite")
    }
    
    @Test func testSetTransformAcceptsInteger() async {
        let doc = DocumentModel()
        let result = await setTransform(doc, ["id": .string("box-1"), "posX": .int(-7)])
        #expect(result.isError == false)
        #expect(boxPosition(doc)?.x == -7)
    }
    
    @Test func testSetTransformAcceptsNegativeZero() async {
        let doc = DocumentModel()
        let result = await setTransform(doc, ["id": .string("box-1"), "posX": .double(-0.0)])
        #expect(result.isError == false)
        #expect(boxPosition(doc)?.x == 0)
    }
    
    @Test func testSetTransformAcceptsPositionAtBound() async {
        let doc = DocumentModel()
        let result = await setTransform(doc, ["id": .string("box-1"), "posX": .double(10_000), "posZ": .double(-10_000)])
        #expect(result.isError == false)
        #expect(boxPosition(doc)?.x == 10_000)
        #expect(boxPosition(doc)?.z == -10_000)
    }
    
    @Test func testSetTransformRejectsPositionPastBound() async {
        await expectSetRejected(["posX": .double(-10_000.5)], mentioning: "10000")
    }
    
    @Test func testSetTransformRejectsMixedValidAndInvalid() async {
        await expectSetRejected(["posX": .double(50), "posY": .string("20")], mentioning: "posY")
    }
    
    @Test func testSetTransformOmittedCoordinatesUnchanged() async {
        let doc = DocumentModel()
        let before = boxPosition(doc)
        let result = await setTransform(doc, ["id": .string("box-1"), "posZ": .double(42)])
        #expect(result.isError == false)
        #expect(boxPosition(doc)?.x == before?.x)
        #expect(boxPosition(doc)?.y == before?.y)
        #expect(boxPosition(doc)?.z == 42)
    }
    
    @Test func testSetTransformRejectsUnknownSolid() async {
        let result = await setTransform(DocumentModel(), ["id": .string("nope"), "posX": .double(1)])
        #expect(result.isError == true)
        #expect(result.content.first?.text == "Error: Solid 'nope' not found in scene")
    }
    
    @Test func testSetTransformRotation() async {
        let doc = DocumentModel()
        let result = await setTransform(doc, [
            "id": .string("box-1"),
            "rotX": .double(90),
            "rotY": .double(0),
            "rotZ": .double(45)
        ])
        #expect(result.isError == false)
        #expect(result.content.first?.text?.contains("rotation (90.0, 0.0, 45.0)") == true)
        
        let degToRad = Float.pi / 180.0
        let qx = simd_quatf(angle: 90 * degToRad, axis: SIMD3<Float>(1, 0, 0))
        let qy = simd_quatf(angle: 0 * degToRad, axis: SIMD3<Float>(0, 1, 0))
        let qz = simd_quatf(angle: 45 * degToRad, axis: SIMD3<Float>(0, 0, 1))
        let expectedQuat = qz * qy * qx
        
        let actualRot = doc.objects.first(where: { $0.id == boxSolidId })?.transform.rotation
        #expect(actualRot != nil)
        if let actualRot {
            #expect(simd_distance(actualRot.vector, expectedQuat.vector) < 1e-5)
        }
    }
    
    @Test func testSetTransformRotationOmittedAnglesDefaultToZero() async {
        let doc = DocumentModel()
        let result = await setTransform(doc, [
            "id": .string("box-1"),
            "rotZ": .double(30)
        ])
        #expect(result.isError == false)
        let degToRad = Float.pi / 180.0
        let expectedQuat = simd_quatf(angle: 30 * degToRad, axis: SIMD3<Float>(0, 0, 1))
        let actualRot = doc.objects.first(where: { $0.id == boxSolidId })?.transform.rotation
        if let actualRot {
            #expect(simd_distance(actualRot.vector, expectedQuat.vector) < 1e-5)
        }
    }
    
    @Test func testSetTransformRejectsInvalidRotation() async {
        await expectSetRejected(["rotX": .string("invalid")], mentioning: "rotX")
        await expectSetRejected(["rotY": .double(.nan)], mentioning: "finite")
        await expectSetRejected(["rotZ": .double(.infinity)], mentioning: "finite")
        await expectSetRejected(["rotX": .double(1e39)], mentioning: "finite")
        await expectSetRejected(["rotY": .null], mentioning: "must be a number")
        await expectSetRejected(["rotZ": .bool(true)], mentioning: "must be a number")
    }
    
    // MARK: - cad_boolean_operation operand validation (#99)
    
    private func booleanArgs(_ a: String, _ b: String, _ op: String = "union") -> [String: AnyCodableValue] {
        ["solidA": .string(a), "solidB": .string(b), "operation": .string(op)]
    }
    
    private func seedKernel(_ kernel: KernelClient) async {
        let box = await kernel.request(.makeBox(jobId: JobId("jb"), solidId: boxSolidId, params: BoxParams(width: 40, depth: 30, height: 20)))
        let cyl = await kernel.request(.makeCylinder(jobId: JobId("jc"), solidId: cylinderSolidId, params: CylinderParams(radius: 15, height: 40)))
        #expect(box.isSuccess && cyl.isSuccess)
    }
    
    private func expectBooleanRejected(_ a: String, _ b: String, operation: String = "union", mentioning key: String) async {
        let doc = DocumentModel()
        let ids = doc.objects.map(\.id)
        let registry = CADToolRegistry(document: doc, kernelClient: KernelClient(debounceDuration: .milliseconds(5)))
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs(a, b, operation))
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains(key) == true)
        #expect(doc.objects.map(\.id) == ids)
    }
    
    @Test func testBooleanRejectsMissingFirstOperand() async {
        await expectBooleanRejected("nope", "cylinder-1", mentioning: "'nope' not found")
    }
    
    @Test func testBooleanRejectsMissingSecondOperand() async {
        await expectBooleanRejected("box-1", "nope", mentioning: "'nope' not found")
    }
    
    @Test func testBooleanRejectsIdenticalOperands() async {
        await expectBooleanRejected("box-1", "box-1", mentioning: "must be different")
    }
    
    @Test func testBooleanRejectsUnknownOperation() async {
        await expectBooleanRejected("box-1", "cylinder-1", operation: "xor", mentioning: "operation")
    }
    
    @Test func testBooleanOnImportedOperandWithoutMeshLeavesDocumentUnchanged() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)
        doc.addObject(def: .imported(name: "step"))
        guard let imported = doc.objects.last?.id else { return }
        let count = doc.objects.count
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs("box-1", imported.rawValue))
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains("failed") == true)
        #expect(doc.objects.count == count)
    }
    
    @Test func testBooleanOnDisjointOperandsMatchesKernelOutcome() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let box = await kernel.request(.evaluateShape(
            jobId: JobId("jb"), solidId: boxSolidId,
            shape: .box(BoxParams(width: 40, depth: 30, height: 20))
        ))
        let far = await kernel.request(.evaluateShape(
            jobId: JobId("jc"), solidId: cylinderSolidId,
            shape: .translate(.cylinder(CylinderParams(radius: 15, height: 40), slices: 32), offset: SIMD3(500, 0, 0))
        ))
        #expect(box.isSuccess && far.isSuccess)
        
        let count = doc.objects.count
        let union = await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs("box-1", "cylinder-1"))
        #expect(union.isError == false)
        #expect(doc.objects.count == count + 1)
        
        let intersect = await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs("box-1", "cylinder-1", "intersect"))
        #expect(doc.objects.count == count + (intersect.isError == true ? 1 : 2))
    }

    @Test func testBooleanOperationWithKeepToolTruePreservesToolVisibility() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)

        let args: [String: AnyCodableValue] = [
            "solidA": .string("box-1"),
            "solidB": .string("cylinder-1"),
            "operation": .string("subtract"),
            "keepTool": .bool(true)
        ]
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: args)
        #expect(result.isError == false)

        let boxObj = doc.objects.first(where: { $0.id == boxSolidId })
        let cylObj = doc.objects.first(where: { $0.id == cylinderSolidId })
        #expect(boxObj?.isVisible == false)
        #expect(cylObj?.isVisible == true)
    }

    @Test func testBooleanOperationWithKeepToolFalseHidesBothOperands() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)

        let args: [String: AnyCodableValue] = [
            "solidA": .string("box-1"),
            "solidB": .string("cylinder-1"),
            "operation": .string("subtract"),
            "keepTool": .bool(false)
        ]
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: args)
        #expect(result.isError == false)

        let boxObj = doc.objects.first(where: { $0.id == boxSolidId })
        let cylObj = doc.objects.first(where: { $0.id == cylinderSolidId })
        #expect(boxObj?.isVisible == false)
        #expect(cylObj?.isVisible == false)
    }

    @Test func testBooleanOperationWithoutKeepToolPreservesVisibility() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)

        let args: [String: AnyCodableValue] = [
            "solidA": .string("box-1"),
            "solidB": .string("cylinder-1"),
            "operation": .string("subtract")
        ]
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: args)
        #expect(result.isError == false)

        let boxObj = doc.objects.first(where: { $0.id == boxSolidId })
        let cylObj = doc.objects.first(where: { $0.id == cylinderSolidId })
        #expect(boxObj?.isVisible == true)
        #expect(cylObj?.isVisible == true)
    }

    @Test func testBooleanOperationRejectsNonBooleanKeepTool() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)

        let args: [String: AnyCodableValue] = [
            "solidA": .string("box-1"),
            "solidB": .string("cylinder-1"),
            "operation": .string("subtract"),
            "keepTool": .string("notABool")
        ]
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: args)
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains("'keepTool' must be a boolean") == true)
    }
    
    @Test func testBooleanSucceedsWithValidOperands() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)
        let count = doc.objects.count
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs("box-1", "cylinder-1", "subtract"))
        #expect(result.isError == false)
        #expect(doc.objects.count == count + 1)
    }
    
    @Test func testBooleanOperandRemovedDuringKernelRequestAddsNothing() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(200))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)
        let task = Task { await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs("box-1", "cylinder-1")) }
        await Task.yield()
        _ = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string("box-1")])
        let result = await task.value
        #expect(result.isError == true)
        // remove_solid also disposes the kernel mesh, so the kernel may fail first; either message leaves the document unchanged.
        let text = result.content.first?.text ?? ""
        #expect(text.contains("removed") || text.contains("failed"))
        #expect(!doc.objects.contains(where: { if case .boolean = $0.def { return true } else { return false } }))
    }
    
    // MARK: - cad_boolean_operation result ID (#100)
    
    /// Runs a boolean and returns the ID parsed from "Output registered as '…'", or nil on failure.
    private func runBoolean(_ registry: CADToolRegistry, _ a: String = "box-1", _ b: String = "cylinder-1", op: String = "subtract") async -> ObjectId? {
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs(a, b, op))
        guard result.isError == false, let text = result.content.first?.text,
              let range = text.range(of: "Output registered as '") else {
            Issue.record("Expected a successful boolean, got \(result.content.first?.text ?? "nothing")")
            return nil
        }
        return ObjectId(String(text[range.upperBound...].dropLast()))
    }
    
    private func isBoolean(_ object: SceneObject) -> Bool {
        if case .boolean = object.def { return true } else { return false }
    }
    
    @Test func testBooleanResultIdChainsIntoMeasureTransformAndRemove() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)
        guard let id = await runBoolean(registry) else { return }
        #expect(id == doc.objects.last?.id)
        #expect(id.rawValue.hasPrefix("boolean-"))
        #expect(doc.paramsFor(id: id) == .boolean(op: .subtract, solidA: boxSolidId, solidB: cylinderSolidId))
        
        let measure = await registry.callTool(name: "cad_measure", arguments: ["id": .string(id.rawValue)])
        #expect(measure.isError == false)
        let measured = measure.content.first?.text ?? ""
        #expect(measured.contains("boolean") && measured.contains("box-1") && measured.contains("cylinder-1"))
        
        let move = await registry.callTool(name: "cad_set_transform", arguments: ["id": .string(id.rawValue), "posX": .double(12)])
        #expect(move.isError == false)
        #expect(doc.objects.first(where: { $0.id == id })?.transform.position.x == 12)
        
        let remove = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string(id.rawValue)])
        #expect(remove.isError == false)
        #expect(!doc.objects.contains(where: { $0.id == id }))
    }
    
    @Test func testBooleanResultRemovalReleasesKernelCache() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)
        guard let id = await runBoolean(registry) else { return }
        let before = await kernel.request(.booleanOperation(jobId: JobId("probe-1"), solidId: SolidId("probe"), op: .union, solidA: id, solidB: cylinderSolidId))
        #expect(before.isSuccess)
        
        _ = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string(id.rawValue)])
        let after = await kernel.request(.booleanOperation(jobId: JobId("probe-2"), solidId: SolidId("probe"), op: .union, solidA: id, solidB: cylinderSolidId))
        #expect(after.error?.code == .unknownSolid)
    }
    
    @Test func testTwoBooleanOperationsProduceDistinctIds() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)
        guard let first = await runBoolean(registry), let second = await runBoolean(registry, op: "union") else { return }
        #expect(first != second)
        for id in [first, second] {
            #expect(await registry.callTool(name: "cad_measure", arguments: ["id": .string(id.rawValue)]).isError == false)
        }
    }
    
    @Test func testRemovedBooleanIdIsNotReused() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)
        guard let removed = await runBoolean(registry) else { return }
        _ = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string(removed.rawValue)])
        let measure = await registry.callTool(name: "cad_measure", arguments: ["id": .string(removed.rawValue)])
        #expect(measure.isError == true)
        #expect(measure.content.first?.text?.contains("not found") == true)
        guard let next = await runBoolean(registry) else { return }
        #expect(next != removed)
    }
    
    @Test func testBooleanKernelFailureReportsNoId() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        await seedKernel(kernel)
        let faulty = FaultInjectingKernelClient(wrapping: kernel)
        let registry = CADToolRegistry(document: doc, kernelClient: faulty)
        await faulty.failNextRequest(with: .geometryFailed)
        let count = doc.objects.count
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs("box-1", "cylinder-1"))
        #expect(result.isError == true)
        #expect(doc.objects.count == count)
        #expect(!doc.objects.contains(where: isBoolean))
        #expect(result.content.first?.text?.contains("boolean-") == false)
    }
    
    @Test func testGetSceneReportsBooleanOperationAndOperands() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)
        guard let id = await runBoolean(registry, op: "intersect") else { return }
        let scene = await registry.callTool(name: "cad_get_scene", arguments: [:])
        guard let data = scene.content.first?.text?.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let item = items.first(where: { $0["id"] as? String == id.rawValue }) else {
            Issue.record("Expected the boolean result in cad_get_scene")
            return
        }
        #expect(item["kind"] as? String == "boolean")
        #expect(item["operation"] as? String == "intersect")
        #expect(item["operands"] as? [String] == ["box-1", "cylinder-1"])
    }
    
    @Test func testSetParamRejectsBooleanSolid() async {
        let doc = DocumentModel()
        let def = ObjectDef.boolean(op: .union, solidA: boxSolidId, solidB: cylinderSolidId)
        let id = doc.addObject(def: def)
        let result = await setParam(doc, ["id": .string(id.rawValue), "param": .string("height"), "value": .double(10)])
        #expect(result.isError == true)
        #expect(result.content.first?.text?.contains("is a boolean solid and has no editable parameters") == true)
        #expect(doc.paramsFor(id: id) == def)
    }
    
    @Test func testSetTransformSchemaOmitsScale() {
        let registry = CADToolRegistry(document: DocumentModel(), kernelClient: KernelClient(debounceDuration: .milliseconds(5)))
        guard let tool = registry.tools.first(where: { $0.name == "cad_set_transform" }) else {
            Issue.record("Expected cad_set_transform definition")
            return
        }
        #expect(!tool.description.lowercased().contains("scale"))
        for key in ["posX", "posY", "posZ"] {
            #expect(tool.inputSchema.properties[key]?.description?.contains("10000") == true)
        }
        for key in ["rotX", "rotY", "rotZ"] {
            #expect(tool.inputSchema.properties[key]?.description?.contains("degrees") == true)
        }
    }
    
    // MARK: - Window-bound viewport recompute (#132)
    
    private func makeWindowBoundFixture(debounceDuration: Duration = .milliseconds(5)) -> (
        DocumentModel,
        KernelClient,
        RecordingMeshSink,
        CADToolRegistry
    ) {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: debounceDuration)
        let sink = RecordingMeshSink()
        let registry = CADToolRegistry(
            document: doc,
            kernelClient: kernel,
            meshSink: sink,
            onViewportInvalidated: { sink.invalidations += 1 },
            onRecomputeResult: { result, id in
                _ = sink.failures.record(result, for: id)
            }
        )
        return (doc, kernel, sink, registry)
    }
    
    private func extentX(_ payload: MeshPayload) -> Float {
        let xs = stride(from: 0, to: payload.positions.count, by: 3).map { payload.positions[$0] }
        return (xs.max() ?? 0) - (xs.min() ?? 0)
    }
    
    @Test func testWindowBoundAddSolidInstallsMeshAndRegistersWithKernel() async throws {
        let (doc, kernel, sink, registry) = makeWindowBoundFixture()
        await seedKernel(kernel)
        
        let result = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("box"),
            "width": .double(50),
            "depth": .double(30),
            "height": .double(20),
            "posX": .double(15)
        ])
        #expect(result.isError == false)
        let newId = try #require(doc.objects.last?.id)
        await registry.settleRecomputes(for: [newId])
        
        #expect(sink.meshes[newId] != nil)
        #expect(sink.meshes[newId]?.transform.position.x == 15)
        #expect(sink.invalidations == 1)
        
        let boolean = await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs(newId.rawValue, "cylinder-1", "union"))
        #expect(boolean.isError == false)
    }
    
    @Test func testWindowBoundSetParamAndSetTransformRedrawSolid() async throws {
        let (doc, _, sink, registry) = makeWindowBoundFixture()
        registry.scheduleRecompute(id: boxSolidId)
        await registry.settleRecomputes(for: [boxSolidId])
        #expect(sink.invalidations == 1)
        
        let paramResult = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string("box-1"),
            "param": .string("width"),
            "value": .double(70)
        ])
        #expect(paramResult.isError == false)
        await registry.settleRecomputes(for: [boxSolidId])
        
        let payload = try #require(sink.meshes[boxSolidId]?.payload)
        #expect(abs(extentX(payload) - 70) <= 1e-3)
        #expect(sink.invalidations == 2)
        
        let moveResult = await registry.callTool(name: "cad_set_transform", arguments: [
            "id": .string("box-1"),
            "posX": .double(33),
            "posY": .double(-12)
        ])
        #expect(moveResult.isError == false)
        #expect(sink.meshes[boxSolidId]?.transform.position == SIMD3<Float>(33, -12, 0))
        #expect(sink.invalidations == 3)
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.transform.position == SIMD3<Float>(33, -12, 0))
    }

    @Test func testWindowBoundSetTransformUpdatesMeshRotation() async throws {
        let (_, _, sink, registry) = makeWindowBoundFixture()
        registry.scheduleRecompute(id: boxSolidId)
        await registry.settleRecomputes(for: [boxSolidId])
        
        let result = await registry.callTool(name: "cad_set_transform", arguments: [
            "id": .string("box-1"),
            "rotZ": .double(90)
        ])
        #expect(result.isError == false)
        let degToRad = Float.pi / 180.0
        let expectedQuat = simd_quatf(angle: 90 * degToRad, axis: SIMD3<Float>(0, 0, 1))
        let installedRot = try #require(sink.meshes[boxSolidId]?.transform.rotation)
        #expect(simd_distance(installedRot.vector, expectedQuat.vector) < 1e-5)
        #expect(sink.invalidations >= 2)
    }

    @Test func testScaleAndRotationEditsIssueZeroKernelDispatches() async throws {
        let (doc, kernel, sink, registry) = makeWindowBoundFixture()
        registry.scheduleRecompute(id: boxSolidId)
        await registry.settleRecomputes(for: [boxSolidId])
        
        let dispatchedBefore = await kernel.getStats().dispatched
        
        // 1. Scale edit via document & SolidMeshApplier
        var t = try #require(doc.objects.first(where: { $0.id == boxSolidId })?.transform)
        t.scale = SIMD3<Float>(2.0, 1.5, 0.5)
        doc.setTransform(id: boxSolidId, transform: t)
        _ = SolidMeshApplier.applyTransform(to: boxSolidId, document: doc, sink: sink)
        
        // 2. Rotation edit via cad_set_transform tool
        let rotResult = await registry.callTool(name: "cad_set_transform", arguments: [
            "id": .string("box-1"),
            "rotX": .double(45),
            "rotY": .double(30),
            "rotZ": .double(15)
        ])
        #expect(rotResult.isError == false)
        
        let dispatchedAfter = await kernel.getStats().dispatched
        #expect(dispatchedAfter == dispatchedBefore, "Scale and rotation edits must not dispatch kernel recomputes")
    }
    
    @Test func testWindowBoundBooleanInstallsResultMesh() async throws {
        let (_, kernel, sink, registry) = makeWindowBoundFixture()
        await seedKernel(kernel)
        
        let booleanId = try #require(await runBoolean(registry, "box-1", "cylinder-1", op: "subtract"))
        #expect(sink.meshes[booleanId] != nil)
        #expect((sink.meshes[booleanId]?.payload.triangleCount ?? 0) > 0)
        #expect(sink.invalidations == 1)
    }
    
    @Test func testBooleanImmediatelyAfterAddSolidAwaitsFirstTessellation() async throws {
        let (doc, kernel, sink, registry) = makeWindowBoundFixture(debounceDuration: .milliseconds(30))
        await seedKernel(kernel)
        
        let added = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("cylinder"),
            "radius": .double(10),
            "height": .double(30)
        ])
        #expect(added.isError == false)
        let addedId = try #require(doc.objects.last?.id)
        // Before debounce expires, the mesh is not yet installed in the sink.
        #expect(sink.meshes[addedId] == nil)
        
        let booleanId = try #require(await runBoolean(registry, "box-1", addedId.rawValue, op: "subtract"))
        #expect(sink.meshes[addedId] != nil)
        #expect(sink.meshes[booleanId] != nil)
    }

    @Test func testOperandRemovalCausesBooleanToFailWithUnknownSolid() async throws {
        let (_, kernel, sink, registry) = makeWindowBoundFixture()
        await seedKernel(kernel)

        let booleanId = try #require(await runBoolean(registry, "box-1", "cylinder-1", op: "subtract"))
        #expect(sink.meshes[booleanId] != nil)
        #expect(sink.failures.message(for: booleanId) == nil)

        // Remove cylinder-1
        let removeResult = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string("cylinder-1")])
        #expect(removeResult.isError == false)

        await registry.settleRecomputes(for: [booleanId])

        // Verify the boolean solid has a recorded unknownSolid failure in RecomputeFailures
        let failureMsg = sink.failures.message(for: booleanId)
        #expect(failureMsg != nil)
        #expect(failureMsg?.contains("unknown-solid") == true)
        #expect(failureMsg?.contains("Solid B 'cylinder-1' not found") == true)
    }
    
    @Test func testAddAndRemoveBeforeRecomputeFinishesInstallsNothingAndDisposesKernel() async throws {
        let (doc, kernel, sink, registry) = makeWindowBoundFixture(debounceDuration: .milliseconds(200))
        
        // Case 1: removed immediately on the next tool call before the recompute task starts.
        let added1 = await registry.callTool(name: "cad_add_solid", arguments: ["type": .string("box")])
        #expect(added1.isError == false)
        let addedId1 = try #require(doc.objects.last?.id)
        let removed1 = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string(addedId1.rawValue)])
        #expect(removed1.isError == false)
        #expect(sink.meshes[addedId1] == nil)
        let probe1 = await kernel.request(.tessellate(jobId: JobId("probe-1"), solidId: addedId1))
        #expect(probe1.error?.code == .unknownSolid)
        
        // Case 2: removed while the recompute request is waiting inside the kernel debounce window.
        let added2 = await registry.callTool(name: "cad_add_solid", arguments: ["type": .string("cylinder")])
        #expect(added2.isError == false)
        let addedId2 = try #require(doc.objects.last?.id)
        try await Task.sleep(for: .milliseconds(5))
        let removed2 = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string(addedId2.rawValue)])
        #expect(removed2.isError == false)
        #expect(sink.meshes[addedId2] == nil)
        let probe2 = await kernel.request(.tessellate(jobId: JobId("probe-2"), solidId: addedId2))
        #expect(probe2.error?.code == .unknownSolid)
    }
    
    @Test func testImportedObjectRequestsNoMesh() async {
        let (doc, kernel, sink, registry) = makeWindowBoundFixture()
        let before = await kernel.getStats().dispatched
        let id = doc.addObject(def: .imported(name: "fixture.step"))
        
        #expect(registry.scheduleRecompute(id: id) == nil)
        #expect(sink.meshes[id] == nil)
        #expect(await kernel.getStats().dispatched == before)
    }

    @Test func testRemoveThenReaddSolidCreatesNewIdAndFreshMesh() async throws {
        let (doc, _, sink, registry) = makeWindowBoundFixture()
        let add1 = await registry.callTool(name: "cad_add_solid", arguments: ["type": .string("box")])
        #expect(add1.isError == false)
        let id1 = SolidId("box-2")
        await registry.settleRecomputes(for: [id1])
        #expect(sink.meshes[id1] != nil)

        let rem = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string(id1.rawValue)])
        #expect(rem.isError == false)
        #expect(sink.meshes[id1] == nil)
        #expect(!doc.objects.contains(where: { $0.id == id1 }))

        let add2 = await registry.callTool(name: "cad_add_solid", arguments: ["type": .string("box")])
        #expect(add2.isError == false)
        let id2 = SolidId("box-3")
        #expect(id1 != id2)
        await registry.settleRecomputes(for: [id2])
        #expect(sink.meshes[id1] == nil)
        #expect(sink.meshes[id2] != nil)
    }
    
    @Test func testRecomputeFailureKeepsPreviousMeshAndRecordsError() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let faulty = FaultInjectingKernelClient(wrapping: kernel)
        let sink = RecordingMeshSink()
        let registry = CADToolRegistry(
            document: doc,
            kernelClient: faulty,
            meshSink: sink,
            onViewportInvalidated: { sink.invalidations += 1 },
            onRecomputeResult: { result, id in
                _ = sink.failures.record(result, for: id)
            }
        )
        registry.scheduleRecompute(id: boxSolidId)
        await registry.settleRecomputes(for: [boxSolidId])
        let initialPayload = try #require(sink.meshes[boxSolidId]?.payload)
        #expect(abs(extentX(initialPayload) - 40) <= 1e-3)
        let invalidationsBefore = sink.invalidations
        
        await faulty.failNextRequest(with: .invalidParams)
        let edit = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string("box-1"),
            "param": .string("width"),
            "value": .double(80)
        ])
        #expect(edit.isError == false)
        await registry.settleRecomputes(for: [boxSolidId])
        
        let preserved = try #require(sink.meshes[boxSolidId]?.payload)
        #expect(abs(extentX(preserved) - 40) <= 1e-3)
        #expect(sink.invalidations == invalidationsBefore)
        #expect(sink.failures.message(for: boxSolidId)?.contains("invalid-params") == true)
    }
    
    @Test func testTwoEditsInDebounceWindowConflateToOneResult() async throws {
        let (_, kernel, sink, registry) = makeWindowBoundFixture(debounceDuration: .milliseconds(120))
        
        _ = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string("box-1"),
            "param": .string("width"),
            "value": .double(55)
        ])
        _ = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string("box-1"),
            "param": .string("width"),
            "value": .double(85)
        ])
        await registry.settleRecomputes(for: [boxSolidId])
        
        let stats = await kernel.getStats()
        #expect(stats.conflated == 1)
        #expect(stats.dispatched == 1)
        let payload = try #require(sink.meshes[boxSolidId]?.payload)
        #expect(abs(extentX(payload) - 85) <= 1e-3)
        #expect(sink.invalidations == 1)
        #expect(sink.failures.message(for: boxSolidId) == nil)
    }

    @Test func testAddSolidDispatchesOnlyNewSolidWithoutRerequestingExisting() async throws {
        let (doc, kernel, sink, registry) = makeWindowBoundFixture()
        await seedKernel(kernel)
        let dispatchedBefore = await kernel.getStats().dispatched
        
        let result = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("cylinder"),
            "radius": .double(10),
            "height": .double(25)
        ])
        #expect(result.isError == false)
        let newId = try #require(doc.objects.last?.id)
        await registry.settleRecomputes(for: [newId])
        
        let statsAfter = await kernel.getStats()
        #expect(statsAfter.dispatched == dispatchedBefore + 1)
        #expect(sink.meshes[newId] != nil)
    }

    @Test func testFiftyAddAndRemoveCyclesLeavesKernelAndMeshSinkAtStartingCounts() async throws {
        let (doc, kernel, sink, registry) = makeWindowBoundFixture()
        let initialStoreCounts = await kernel.storeCounts()
        let initialMeshCount = sink.meshes.count

        for _ in 0..<50 {
            let addResult = await registry.callTool(name: "cad_add_solid", arguments: [
                "type": .string("box"),
                "width": .double(20),
                "depth": .double(20),
                "height": .double(20)
            ])
            #expect(addResult.isError == false)
            let addedId = try #require(doc.objects.last?.id)
            await registry.settleRecomputes(for: [addedId])
            #expect(sink.meshes[addedId] != nil)

            let removeResult = await registry.callTool(name: "cad_remove_solid", arguments: [
                "id": .string(addedId.rawValue)
            ])
            #expect(removeResult.isError == false)
            #expect(sink.meshes[addedId] == nil)
        }

        let finalStoreCounts = await kernel.storeCounts()
        #expect(finalStoreCounts == initialStoreCounts)
        #expect(sink.meshes.count == initialMeshCount)
    }

    @Test func testLockedObjectRejectsCADToolsSetParamSetTransformRemoveSolid() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        doc.setLocked(id: boxSolidId, isLocked: true)

        let initialBox = doc.paramsFor(id: boxSolidId)
        let initialTransform = doc.objects.first(where: { $0.id == boxSolidId })?.transform
        let initialCount = doc.objects.count

        // cad_set_param
        let paramResult = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string("box-1"),
            "param": .string("width"),
            "value": .double(60)
        ])
        #expect(paramResult.isError == true)
        #expect(paramResult.content.first?.text?.contains("box-1") == true)
        #expect(paramResult.content.first?.text?.contains("locked") == true)
        #expect(doc.paramsFor(id: boxSolidId) == initialBox)

        // cad_set_transform
        let transformResult = await registry.callTool(name: "cad_set_transform", arguments: [
            "id": .string("box-1"),
            "posX": .double(100)
        ])
        #expect(transformResult.isError == true)
        #expect(transformResult.content.first?.text?.contains("box-1") == true)
        #expect(transformResult.content.first?.text?.contains("locked") == true)
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.transform == initialTransform)

        // cad_remove_solid
        let removeResult = await registry.callTool(name: "cad_remove_solid", arguments: [
            "id": .string("box-1")
        ])
        #expect(removeResult.isError == true)
        #expect(removeResult.content.first?.text?.contains("box-1") == true)
        #expect(removeResult.content.first?.text?.contains("locked") == true)
        #expect(doc.objects.count == initialCount)
        #expect(doc.objects.contains(where: { $0.id == boxSolidId }))
    }

    @Test func testLockedObjectCanBeUsedAsBooleanOperand() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)
        doc.setLocked(id: boxSolidId, isLocked: true)

        let count = doc.objects.count
        let result = await registry.callTool(name: "cad_boolean_operation", arguments: booleanArgs("box-1", "cylinder-1", "subtract"))
        #expect(result.isError == false)
        #expect(doc.objects.count == count + 1)
        #expect(doc.objects.first(where: { $0.id == boxSolidId })?.isLocked == true)
    }

    @Test func testLockWhileRecomputeInFlightAppliesLastAcceptedValue() async throws {
        let (doc, _, sink, registry) = makeWindowBoundFixture()
        // Accept a parameter edit while unlocked
        let editResult = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string("box-1"),
            "param": .string("width"),
            "value": .double(75)
        ])
        #expect(editResult.isError == false)

        // Lock solid while recompute is pending or in flight
        doc.setLocked(id: boxSolidId, isLocked: true)

        // Wait for recomputes to settle
        await registry.settleRecomputes(for: [boxSolidId])

        // Verify the last accepted value was applied and mesh installed
        #expect(sink.meshes[boxSolidId] != nil)
        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            #expect(p.width == 75)
        } else {
            Issue.record("Expected box definition")
        }
    }
}

@MainActor
private final class RecordingMeshSink: SolidMeshSink {
    struct Entry {
        var payload: MeshPayload
        var transform: Transform
        var color: SIMD4<Float>
        var isHidden: Bool
    }
    var meshes: [SolidId: Entry] = [:]
    var invalidations = 0
    var failures = RecomputeFailures()

    func installMesh(_ payload: MeshPayload, for id: SolidId, transform: Transform, color: SIMD4<Float>, isHidden: Bool) -> Bool {
        meshes[id] = Entry(payload: payload, transform: transform, color: color, isHidden: isHidden)
        return true
    }

    func updateTransform(_ transform: Transform, for id: SolidId) -> Bool {
        guard var entry = meshes[id] else { return false }
        entry.transform = transform
        meshes[id] = entry
        return true
    }

    func removeMesh(for id: SolidId) -> Bool {
        meshes.removeValue(forKey: id) != nil
    }
}

private final class FailingSnapshotProvider: SnapshotProvider {
    func captureSnapshotPngBase64() async -> String? { nil }
}
