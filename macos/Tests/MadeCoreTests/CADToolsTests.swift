import Testing
import Foundation
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
}

private final class FailingSnapshotProvider: SnapshotProvider {
    func captureSnapshotPngBase64() async -> String? { nil }
}
