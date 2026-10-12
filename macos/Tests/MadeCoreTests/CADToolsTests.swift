import Testing
import Foundation
@testable import MadeCore

@Suite struct CADToolsTests {
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
        
        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            #expect(p.width == 90.0) // Clamped to 90
        } else {
            Issue.record("Expected box params")
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
}
