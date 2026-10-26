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
    
    @Test func testGetScenePaginationAcrossMultiplePages() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        for obj in doc.objects {
            _ = doc.removeObject(id: obj.id)
        }
        for i in 1...120 {
            _ = doc.addObject(def: .box(BoxParams(width: 10 + Float(i), depth: 10, height: 10)))
        }
        #expect(doc.objects.count == 120)
        
        let p1 = await registry.callTool(name: "cad_get_scene", arguments: ["limit": .int(50)])
        #expect(p1.isError == false)
        guard let d1 = p1.content.first?.text?.data(using: .utf8),
              let json1 = try? JSONSerialization.jsonObject(with: d1) as? [String: Any],
              let objs1 = json1["objects"] as? [[String: Any]],
              let total1 = json1["total"] as? Int,
              let cursor1 = json1["nextCursor"] as? String else {
            Issue.record("Failed to parse page 1")
            return
        }
        #expect(objs1.count == 50)
        #expect(total1 == 120)
        #expect(!cursor1.isEmpty)
        
        let p2 = await registry.callTool(name: "cad_get_scene", arguments: ["limit": .int(50), "cursor": .string(cursor1)])
        #expect(p2.isError == false)
        guard let d2 = p2.content.first?.text?.data(using: .utf8),
              let json2 = try? JSONSerialization.jsonObject(with: d2) as? [String: Any],
              let objs2 = json2["objects"] as? [[String: Any]],
              let total2 = json2["total"] as? Int,
              let cursor2 = json2["nextCursor"] as? String else {
            Issue.record("Failed to parse page 2")
            return
        }
        #expect(objs2.count == 50)
        #expect(total2 == 120)
        #expect(!cursor2.isEmpty)
        
        let p3 = await registry.callTool(name: "cad_get_scene", arguments: ["limit": .int(50), "cursor": .string(cursor2)])
        #expect(p3.isError == false)
        guard let d3 = p3.content.first?.text?.data(using: .utf8),
              let json3 = try? JSONSerialization.jsonObject(with: d3) as? [String: Any],
              let objs3 = json3["objects"] as? [[String: Any]],
              let total3 = json3["total"] as? Int else {
            Issue.record("Failed to parse page 3")
            return
        }
        #expect(objs3.count == 20)
        #expect(total3 == 120)
        #expect(json3["nextCursor"] == nil)
        
        let allIds = (objs1 + objs2 + objs3).compactMap { $0["id"] as? String }
        #expect(allIds.count == 120)
        #expect(Set(allIds).count == 120)
    }

    @Test func testGetSceneRejectsNonPositiveLimit() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let res0 = await registry.callTool(name: "cad_get_scene", arguments: ["limit": .int(0)])
        #expect(res0.isError == true)
        #expect(res0.content.first?.text?.contains("limit") == true)
        
        let resNeg = await registry.callTool(name: "cad_get_scene", arguments: ["limit": .int(-5)])
        #expect(resNeg.isError == true)
        #expect(resNeg.content.first?.text?.contains("limit") == true)
    }

    @Test func testGetSceneClampsLimitAboveMax() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        for obj in doc.objects {
            _ = doc.removeObject(id: obj.id)
        }
        for i in 1...550 {
            _ = doc.addObject(def: .box(BoxParams(width: Float(i), depth: 10, height: 10)))
        }
        #expect(doc.objects.count == 550)
        
        let res = await registry.callTool(name: "cad_get_scene", arguments: ["limit": .int(600)])
        #expect(res.isError == false)
        guard let data = res.content.first?.text?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objs = json["objects"] as? [[String: Any]] else {
            Issue.record("Failed to parse response")
            return
        }
        #expect(objs.count == 500)
        #expect(json["total"] as? Int == 550)
        #expect(json["nextCursor"] != nil)
    }

    @Test func testGetSceneEmptyDocumentOmitsCursor() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        for obj in doc.objects {
            _ = doc.removeObject(id: obj.id)
        }
        #expect(doc.objects.isEmpty)
        
        let res = await registry.callTool(name: "cad_get_scene", arguments: [:])
        #expect(res.isError == false)
        guard let data = res.content.first?.text?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objs = json["objects"] as? [[String: Any]],
              let total = json["total"] as? Int else {
            Issue.record("Failed to parse response")
            return
        }
        #expect(objs.isEmpty)
        #expect(total == 0)
        #expect(json["nextCursor"] == nil)
    }

    @Test func testGetSceneCursorPastEndReturnsEmptyList() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let total = doc.objects.count
        let res = await registry.callTool(name: "cad_get_scene", arguments: ["cursor": .string("past-the-end")])
        #expect(res.isError == false)
        guard let data = res.content.first?.text?.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objs = json["objects"] as? [[String: Any]] else {
            Issue.record("Failed to parse response")
            return
        }
        #expect(objs.isEmpty)
        #expect(json["total"] as? Int == total)
        #expect(json["nextCursor"] == nil)
    }

    @Test func testGetSceneCursorResumesAfterObjectRemoval() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        for obj in doc.objects {
            _ = doc.removeObject(id: obj.id)
        }
        let idA = doc.addObject(def: .box(BoxParams(width: 10, depth: 10, height: 10)))
        let idB = doc.addObject(def: .box(BoxParams(width: 20, depth: 20, height: 20)))
        let idC = doc.addObject(def: .box(BoxParams(width: 30, depth: 30, height: 30)))
        let idD = doc.addObject(def: .box(BoxParams(width: 40, depth: 40, height: 40)))
        let idE = doc.addObject(def: .box(BoxParams(width: 50, depth: 50, height: 50)))
        
        let p1 = await registry.callTool(name: "cad_get_scene", arguments: ["limit": .int(2)])
        #expect(p1.isError == false)
        guard let d1 = p1.content.first?.text?.data(using: .utf8),
              let json1 = try? JSONSerialization.jsonObject(with: d1) as? [String: Any],
              let objs1 = json1["objects"] as? [[String: Any]],
              let cursor1 = json1["nextCursor"] as? String else {
            Issue.record("Failed to parse page 1")
            return
        }
        #expect(objs1.compactMap { $0["id"] as? String } == [idA.rawValue, idB.rawValue])
        
        _ = doc.removeObject(id: idB)
        
        let p2 = await registry.callTool(name: "cad_get_scene", arguments: ["limit": .int(2), "cursor": .string(cursor1)])
        #expect(p2.isError == false)
        guard let d2 = p2.content.first?.text?.data(using: .utf8),
              let json2 = try? JSONSerialization.jsonObject(with: d2) as? [String: Any],
              let objs2 = json2["objects"] as? [[String: Any]] else {
            Issue.record("Failed to parse page 2")
            return
        }
        let ids2 = objs2.compactMap { $0["id"] as? String }
        #expect(ids2 == [idC.rawValue, idD.rawValue])
        #expect(!ids2.contains(idA.rawValue))
        #expect(!ids2.contains(idB.rawValue))
        #expect(idE.rawValue != "")
    }

    @Test func testGetSceneRejectsMalformedCursor() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        
        let resBadType = await registry.callTool(name: "cad_get_scene", arguments: ["cursor": .int(42)])
        #expect(resBadType.isError == true)
        #expect(resBadType.content.first?.text?.contains("cursor") == true)
        
        let resGarbage = await registry.callTool(name: "cad_get_scene", arguments: ["cursor": .string("!!!not-a-valid-cursor???")])
        #expect(resGarbage.isError == true)
        #expect(resGarbage.content.first?.text?.contains("cursor") == true)
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

    @Test func testAddSolidSphereConeTorusWedge() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // Sphere
        let sphRes = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("sphere"),
            "radius": .double(18)
        ])
        #expect(sphRes.isError == false)
        if case .sphere(let p) = doc.objects.last?.def {
            #expect(p.radius == 18)
        } else {
            Issue.record("Expected sphere solid")
        }

        // Cone
        let coneRes = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("cone"),
            "bottomRadius": .double(12),
            "topRadius": .double(4),
            "height": .double(28)
        ])
        #expect(coneRes.isError == false)
        if case .cone(let p) = doc.objects.last?.def {
            #expect(p.bottomRadius == 12)
            #expect(p.topRadius == 4)
            #expect(p.height == 28)
        } else {
            Issue.record("Expected cone solid")
        }

        // Torus
        let torRes = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("torus"),
            "majorRadius": .double(22),
            "minorRadius": .double(6)
        ])
        #expect(torRes.isError == false)
        if case .torus(let p) = doc.objects.last?.def {
            #expect(p.majorRadius == 22)
            #expect(p.minorRadius == 6)
        } else {
            Issue.record("Expected torus solid")
        }

        // Wedge
        let wdgRes = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("wedge"),
            "width": .double(25),
            "depth": .double(15),
            "height": .double(35),
            "topWidth": .double(5)
        ])
        #expect(wdgRes.isError == false)
        if case .wedge(let p) = doc.objects.last?.def {
            #expect(p.width == 25)
            #expect(p.depth == 15)
            #expect(p.height == 35)
            #expect(p.topWidth == 5)
        } else {
            Issue.record("Expected wedge solid")
        }
    }

    @Test func testSetParamSphereConeTorusWedge() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let sphId = doc.addObject(def: .sphere(SphereParams(radius: 10)))
        let sphSet = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string(sphId.rawValue),
            "param": .string("radius"),
            "value": .double(25)
        ])
        #expect(sphSet.isError == false)
        if case .sphere(let p) = doc.paramsFor(id: sphId) {
            #expect(p.radius == 25)
        } else {
            Issue.record("Expected sphere params")
        }

        let coneId = doc.addObject(def: .cone(ConeParams(bottomRadius: 10, topRadius: 2, height: 20)))
        let coneSet = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string(coneId.rawValue),
            "param": .string("bottomRadius"),
            "value": .double(15)
        ])
        #expect(coneSet.isError == false)
        if case .cone(let p) = doc.paramsFor(id: coneId) {
            #expect(p.bottomRadius == 15)
        } else {
            Issue.record("Expected cone params")
        }

        let torId = doc.addObject(def: .torus(TorusParams(majorRadius: 20, minorRadius: 5)))
        let torSet = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string(torId.rawValue),
            "param": .string("minorRadius"),
            "value": .double(8)
        ])
        #expect(torSet.isError == false)
        if case .torus(let p) = doc.paramsFor(id: torId) {
            #expect(p.minorRadius == 8)
        } else {
            Issue.record("Expected torus params")
        }

        let wdgId = doc.addObject(def: .wedge(WedgeParams(width: 20, depth: 20, height: 20, topWidth: 0)))
        let wdgSet = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string(wdgId.rawValue),
            "param": .string("topWidth"),
            "value": .double(8)
        ])
        #expect(wdgSet.isError == false)
        if case .wedge(let p) = doc.paramsFor(id: wdgId) {
            #expect(p.topWidth == 8)
        } else {
            Issue.record("Expected wedge params")
        }
    }

    @Test func testMeasureSphereConeTorusWedge() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let sphId = doc.addObject(def: .sphere(SphereParams(radius: 15)))
        let sphRes = await registry.callTool(name: "cad_measure", arguments: ["id": .string(sphId.rawValue)])
        #expect(sphRes.isError == false)
        #expect(sphRes.content.first?.text?.contains("sphere") == true)

        let coneId = doc.addObject(def: .cone(ConeParams(bottomRadius: 10, topRadius: 0, height: 30)))
        let coneRes = await registry.callTool(name: "cad_measure", arguments: ["id": .string(coneId.rawValue)])
        #expect(coneRes.isError == false)
        #expect(coneRes.content.first?.text?.contains("cone") == true)

        let torId = doc.addObject(def: .torus(TorusParams(majorRadius: 20, minorRadius: 5)))
        let torRes = await registry.callTool(name: "cad_measure", arguments: ["id": .string(torId.rawValue)])
        #expect(torRes.isError == false)
        #expect(torRes.content.first?.text?.contains("torus") == true)

        let wdgId = doc.addObject(def: .wedge(WedgeParams(width: 20, depth: 10, height: 30, topWidth: 0)))
        let wdgRes = await registry.callTool(name: "cad_measure", arguments: ["id": .string(wdgId.rawValue)])
        #expect(wdgRes.isError == false)
        #expect(wdgRes.content.first?.text?.contains("wedge") == true)
        #expect(wdgRes.content.first?.text?.contains("3000") == true)
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
              let rawJson = try? JSONSerialization.jsonObject(with: data),
              let items = (rawJson as? [String: Any])?["objects"] as? [[String: Any]] ?? (rawJson as? [[String: Any]]),
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

    @Test func testCADRollbackToIndexAndToEnd() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)

        // Roll back to index 1
        let rollMsg = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"cad_rollback","arguments":{"index":1}}}"#
        let rollResp = await server.processMessage(rollMsg)
        #expect(rollResp?.contains("rolled back at index 1") == true)
        #expect(doc.rollbackIndex == 1)
        #expect(doc.objects.count == 1)

        // Roll forward to end
        let endMsg = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cad_rollback","arguments":{}}}"#
        let endResp = await server.processMessage(endMsg)
        #expect(endResp?.contains("fully rolled forward") == true)
        #expect(doc.rollbackIndex == nil)
        #expect(doc.objects.count == 2)
    }

    @Test func testCADRollbackToSolidId() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)

        // Roll back to solid_id box-1
        let rollMsg = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cad_rollback","arguments":{"solid_id":"box-1"}}}"#
        let rollResp = await server.processMessage(rollMsg)
        #expect(rollResp?.contains("rolled back at index 1") == true)
        #expect(doc.rollbackIndex == 1)
        #expect(doc.objects.count == 1)

        // Non-existent solid returns error
        let badMsg = #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"cad_rollback","arguments":{"solid_id":"nonexistent"}}}"#
        let badResp = await server.processMessage(badMsg)
        #expect(badResp?.contains("not found in timeline") == true)
    }

    @Test func testCADRollbackRejectsOutOfRangeAndNonIntegerIndices() async {
        // Direct AnyCodableValue intValue validation
        #expect(AnyCodableValue.double(1.5).intValue == nil)
        #expect(AnyCodableValue.double(1e30).intValue == nil)
        #expect(AnyCodableValue.double(-1e30).intValue == nil)
        #expect(AnyCodableValue.double(.nan).intValue == nil)
        #expect(AnyCodableValue.double(.infinity).intValue == nil)
        #expect(AnyCodableValue.double(-.infinity).intValue == nil)
        #expect(AnyCodableValue.double(42.0).intValue == 42)
        #expect(AnyCodableValue.int(42).intValue == 42)
        #expect(AnyCodableValue.string("42").intValue == nil)

        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        let server = MCPServer(toolRegistry: registry)

        let initialCount = doc.objects.count
        #expect(doc.rollbackIndex == nil)

        // 1. Non-integer index (1.5) via JSON-RPC
        let nonIntMsg = #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"cad_rollback","arguments":{"index":1.5}}}"#
        let nonIntResp = await server.processMessage(nonIntMsg)
        #expect(nonIntResp?.contains("\"isError\":true") == true)
        #expect(doc.rollbackIndex == nil)
        #expect(doc.objects.count == initialCount)

        // 2. Positive out-of-Int-range index (1e30) via JSON-RPC
        let posOverflowMsg = #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"cad_rollback","arguments":{"index":1e30}}}"#
        let posOverflowResp = await server.processMessage(posOverflowMsg)
        #expect(posOverflowResp?.contains("\"isError\":true") == true)
        #expect(doc.rollbackIndex == nil)
        #expect(doc.objects.count == initialCount)

        // 3. Negative out-of-Int-range index (-1e30) via JSON-RPC
        let negOverflowMsg = #"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"cad_rollback","arguments":{"index":-1e30}}}"#
        let negOverflowResp = await server.processMessage(negOverflowMsg)
        #expect(negOverflowResp?.contains("\"isError\":true") == true)
        #expect(doc.rollbackIndex == nil)
        #expect(doc.objects.count == initialCount)

        // 4. Direct registry call validation
        let directNonInt = await registry.callTool(name: "cad_rollback", arguments: ["index": .double(1.5)])
        #expect(directNonInt.isError == true)

        let directPosOverflow = await registry.callTool(name: "cad_rollback", arguments: ["index": .double(1e30)])
        #expect(directPosOverflow.isError == true)

        let directNegOverflow = await registry.callTool(name: "cad_rollback", arguments: ["index": .double(-1e30)])
        #expect(directNegOverflow.isError == true)

        #expect(doc.rollbackIndex == nil)
        #expect(doc.objects.count == initialCount)

        // 5. Timeline preservation when already rolled back
        _ = doc.setRollbackIndex(1)
        #expect(doc.rollbackIndex == 1)
        let rolledCount = doc.objects.count

        let badWhileRolled = await registry.callTool(name: "cad_rollback", arguments: ["index": .double(1e30)])
        #expect(badWhileRolled.isError == true)
        #expect(doc.rollbackIndex == 1)
        #expect(doc.objects.count == rolledCount)
    }

    @Test func testChangingChordalToleranceRetessellatesCylinderInMeshSink() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
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
        registry.scheduleRecompute(id: boxSolidId)
        registry.scheduleRecompute(id: cylinderSolidId)
        await registry.settleRecomputes(for: [boxSolidId, cylinderSolidId])

        // 1. Set coarse chordal tolerance (0.1)
        registry.scheduleRetessellateAll(tolerances: KernelTolerances(chordalTolerance: 0.1))
        await registry.settleRecomputes(for: [boxSolidId, cylinderSolidId])

        let coarsePayload = try #require(sink.meshes[cylinderSolidId]?.payload)
        let coarseTriangleCount = coarsePayload.triangleCount
        #expect(sink.meshes[boxSolidId] != nil, "Box mesh must still exist")

        // 2. Set fine chordal tolerance (0.01)
        registry.scheduleRetessellateAll(tolerances: KernelTolerances(chordalTolerance: 0.01))
        await registry.settleRecomputes(for: [boxSolidId, cylinderSolidId])

        let finePayload = try #require(sink.meshes[cylinderSolidId]?.payload)
        let fineTriangleCount = finePayload.triangleCount
        #expect(fineTriangleCount > coarseTriangleCount, "Fine tolerance must increase cylinder triangle count")
        #expect(sink.meshes[boxSolidId] != nil, "Box mesh must still exist")

        // 3. Set even finer chordal tolerance (0.005)
        registry.scheduleRetessellateAll(tolerances: KernelTolerances(chordalTolerance: 0.005))
        await registry.settleRecomputes(for: [boxSolidId, cylinderSolidId])

        let finerPayload = try #require(sink.meshes[cylinderSolidId]?.payload)
        let finerTriangleCount = finerPayload.triangleCount
        #expect(finerTriangleCount > fineTriangleCount, "Finer tolerance must further increase cylinder triangle count")
        #expect(sink.meshes[boxSolidId] != nil, "Multiple solids remain installed without dropping meshes")
    }

    // MARK: - Feature-Level Tools Tests (BL-AGT-04, #151)

    @Test func testCreateSketchAndAddEntities() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // 1. Create sketch on default XY plane with initial entities
        let initialEntities: [AnyCodableValue] = [
            .dictionary([
                "type": .string("line"),
                "startX": .double(0),
                "startY": .double(0),
                "endX": .double(10),
                "endY": .double(0)
            ]),
            .dictionary([
                "type": .string("circle"),
                "centerX": .double(5),
                "centerY": .double(5),
                "radius": .double(2.5)
            ])
        ]
        let createResult = await registry.callTool(name: "cad_create_sketch", arguments: [
            "plane": .string("XY"),
            "entities": .array(initialEntities)
        ])
        #expect(createResult.isError == false)
        let text = try #require(createResult.content.first?.text)
        let createData = try #require(text.data(using: .utf8))
        let createJson = try #require(try JSONSerialization.jsonObject(with: createData) as? [String: Any])
        let sketchIdStr = try #require(createJson["id"] as? String)
        let sketchUUID = try #require(UUID(uuidString: sketchIdStr))
        #expect(createJson["plane"] as? String == "XY")
        #expect(createJson["entityCount"] as? Int == 2)

        // Verify in document
        let sketchFeat = try #require(doc.feature(for: sketchUUID))
        if case .sketch(let data) = sketchFeat.operation {
            #expect(data.entities.count == 2)
            #expect(data.planeName == "XY")
        } else {
            Issue.record("Expected sketch operation")
        }

        // 2. Add an arc entity to the existing sketch
        let addArcRes = await registry.callTool(name: "cad_add_sketch_entity", arguments: [
            "sketchId": .string(sketchIdStr),
            "type": .string("arc"),
            "startX": .double(10),
            "startY": .double(0),
            "endX": .double(10),
            "endY": .double(10),
            "centerX": .double(10),
            "centerY": .double(5),
            "clockwise": .bool(false)
        ])
        #expect(addArcRes.isError == false)

        // 3. Add a construction line
        let addConstLineRes = await registry.callTool(name: "cad_add_sketch_entity", arguments: [
            "sketchId": .string(sketchIdStr),
            "type": .string("line"),
            "startX": .double(0),
            "startY": .double(0),
            "endX": .double(10),
            "endY": .double(10),
            "isConstruction": .bool(true)
        ])
        #expect(addConstLineRes.isError == false)

        let updatedFeat = try #require(doc.feature(for: sketchUUID))
        if case .sketch(let data) = updatedFeat.operation {
            #expect(data.entities.count == 4)
            #expect(data.entities.last?.isConstruction == true)
        }

        // 4. Create sketch on XZ and YZ planes
        let xzRes = await registry.callTool(name: "cad_create_sketch", arguments: ["plane": .string("XZ")])
        #expect(xzRes.isError == false)
        let yzRes = await registry.callTool(name: "cad_create_sketch", arguments: ["plane": .string("YZ")])
        #expect(yzRes.isError == false)

        // 5. Create sketch on a datum plane
        _ = doc.addDatumPlaneFeature(name: "OffsetPlane1")
        let datumSketchRes = await registry.callTool(name: "cad_create_sketch", arguments: ["plane": .string("OffsetPlane1")])
        #expect(datumSketchRes.isError == false)
    }

    @Test func testAddSketchConstraints() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // Create empty sketch
        let createRes = await registry.callTool(name: "cad_create_sketch", arguments: ["plane": .string("XY")])
        #expect(createRes.isError == false)
        let text = try #require(createRes.content.first?.text)
        let json = try #require(try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any])
        let sketchIdStr = try #require(json["id"] as? String)
        let sketchUUID = try #require(UUID(uuidString: sketchIdStr))

        // Add 2 lines
        let addL1 = await registry.callTool(name: "cad_add_sketch_entity", arguments: [
            "sketchId": .string(sketchIdStr),
            "type": .string("line"),
            "startX": .double(0),
            "startY": .double(0),
            "endX": .double(20),
            "endY": .double(0)
        ])
        #expect(addL1.isError == false)

        let addL2 = await registry.callTool(name: "cad_add_sketch_entity", arguments: [
            "sketchId": .string(sketchIdStr),
            "type": .string("line"),
            "startX": .double(20),
            "startY": .double(0),
            "endX": .double(20),
            "endY": .double(20)
        ])
        #expect(addL2.isError == false)

        let feat = try #require(doc.feature(for: sketchUUID))
        guard case .sketch(let sketchData) = feat.operation, sketchData.entities.count == 2 else {
            Issue.record("Expected 2 entities in sketch")
            return
        }
        let e1Id = sketchData.entities[0].id.uuidString
        let e2Id = sketchData.entities[1].id.uuidString

        // 1. Add horizontal constraint to line 1
        let hRes = await registry.callTool(name: "cad_add_constraint", arguments: [
            "sketchId": .string(sketchIdStr),
            "type": .string("horizontal"),
            "entityIds": .array([.string(e1Id)])
        ])
        #expect(hRes.isError == false)

        // 2. Add vertical constraint to line 2
        let vRes = await registry.callTool(name: "cad_add_constraint", arguments: [
            "sketchId": .string(sketchIdStr),
            "type": .string("vertical"),
            "entityIds": .array([.string(e2Id)])
        ])
        #expect(vRes.isError == false)

        // 3. Add coincident constraint between line 1 and line 2
        let cRes = await registry.callTool(name: "cad_add_constraint", arguments: [
            "sketchId": .string(sketchIdStr),
            "type": .string("coincident"),
            "entityIds": .array([.string(e1Id), .string(e2Id)])
        ])
        #expect(cRes.isError == false)

        // Verify constraints recorded in document
        let featWithConstraints = try #require(doc.feature(for: sketchUUID))
        if case .sketch(let data) = featWithConstraints.operation {
            #expect(data.constraints.count == 3)
            #expect(data.constraints.contains(where: { $0.kind == .horizontal }))
            #expect(data.constraints.contains(where: { $0.kind == .vertical }))
            #expect(data.constraints.contains(where: { $0.kind == .coincident }))
        }
    }

    @Test func testCADAddConstraintDriven() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let sink = RecordingMeshSink()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, meshSink: sink)

        let createRes = await registry.callTool(name: "cad_create_sketch", arguments: [
            "plane": .string("XY"),
            "entities": .array([
                .dictionary([
                    "type": .string("line"),
                    "startX": .double(0),
                    "startY": .double(0),
                    "endX": .double(20),
                    "endY": .double(0)
                ])
            ])
        ])
        #expect(createRes.isError == false)
        let json = try #require(try JSONSerialization.jsonObject(with: createRes.content.first!.text!.data(using: .utf8)!) as? [String: Any])
        let sketchIdStr = try #require(json["id"] as? String)
        let sketchUUID = try #require(UUID(uuidString: sketchIdStr))

        let feat = try #require(doc.feature(for: sketchUUID))
        guard case .sketch(let sketchData) = feat.operation else {
            Issue.record("Expected sketch feature")
            return
        }
        let e1Id = sketchData.entities[0].id.uuidString

        let hRes = await registry.callTool(name: "cad_add_constraint", arguments: [
            "sketchId": .string(sketchIdStr),
            "type": .string("horizontal"),
            "entityIds": .array([.string(e1Id)]),
            "isDriven": .bool(true)
        ])
        #expect(hRes.isError == false)
        let resText = try #require(hRes.content.first?.text)
        #expect(resText.contains("(driven reference)"))

        let featWithConstraints = try #require(doc.feature(for: sketchUUID))
        if case .sketch(let data) = featWithConstraints.operation {
            #expect(data.constraints.count == 1)
            let c = data.constraints[0]
            #expect(c.kind == .horizontal)
            #expect(c.isDriven == true)
        }
    }

    @Test func testExtrudeSketchCreatesSolidAndMesh() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let sink = RecordingMeshSink()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, meshSink: sink)

        // Create a sketch with a closed circular profile
        let createRes = await registry.callTool(name: "cad_create_sketch", arguments: [
            "plane": .string("XY"),
            "entities": .array([
                .dictionary([
                    "type": .string("circle"),
                    "centerX": .double(0),
                    "centerY": .double(0),
                    "radius": .double(15)
                ])
            ])
        ])
        #expect(createRes.isError == false)
        let json = try #require(try JSONSerialization.jsonObject(with: createRes.content.first!.text!.data(using: .utf8)!) as? [String: Any])
        let sketchIdStr = try #require(json["id"] as? String)

        // Extrude 30mm
        let extrudeRes = await registry.callTool(name: "cad_extrude", arguments: [
            "sketchId": .string(sketchIdStr),
            "distance": .double(30),
            "isSymmetric": .bool(false)
        ])
        #expect(extrudeRes.isError == false)
        let extrudeText = try #require(extrudeRes.content.first?.text)
        #expect(extrudeText.contains("extrude-"))
        #expect(extrudeText.contains("30.0 mm"))

        // Find the created extrude solid
        let extrudeObj = try #require(doc.objects.first(where: { $0.id.rawValue.hasPrefix("extrude-") }))
        let solidId = extrudeObj.id

        // Settle kernel recompute
        await registry.settleRecomputes(for: [solidId])

        // Verify mesh installed in sink
        let meshEntry = try #require(sink.meshes[solidId])
        #expect(meshEntry.payload.triangleCount > 0)
    }

    @Test func testFilletSolidEdgeByTopologicalReference() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let sink = RecordingMeshSink()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, meshSink: sink)

        // Settle initial document box recompute
        registry.scheduleRecompute(id: boxSolidId)
        await registry.settleRecomputes(for: [boxSolidId])

        // Apply fillet on edge:top-front
        let filletRes = await registry.callTool(name: "cad_fillet", arguments: [
            "solidId": .string("box-1"),
            "edge": .string("edge:top-front"),
            "radius": .double(2.0)
        ])
        #expect(filletRes.isError == false)
        let text = try #require(filletRes.content.first?.text)
        #expect(text.contains("Successfully applied fillet of radius 2.0 mm to edge 'edge:top-front' on solid 'box-1'"))

        // Verify updated mesh installed in sink
        let mesh = try #require(sink.meshes[boxSolidId]?.payload)
        #expect(mesh.triangleCount > 0)
    }

    @Test func testFilletErrorCases() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        registry.scheduleRecompute(id: boxSolidId)
        await registry.settleRecomputes(for: [boxSolidId])

        // 1. Unknown solid
        let unknownSolidRes = await registry.callTool(name: "cad_fillet", arguments: [
            "solidId": .string("nonexistent-solid"),
            "edge": .string("edge:top-front"),
            "radius": .double(2.0)
        ])
        #expect(unknownSolidRes.isError == true)
        #expect(unknownSolidRes.content.first?.text?.contains("not found in scene") == true)

        // 2. Negative or zero radius
        let negRadiusRes = await registry.callTool(name: "cad_fillet", arguments: [
            "solidId": .string("box-1"),
            "edge": .string("edge:top-front"),
            "radius": .double(-1.0)
        ])
        #expect(negRadiusRes.isError == true)
        #expect(negRadiusRes.content.first?.text?.contains("positive number") == true)

        let zeroRadiusRes = await registry.callTool(name: "cad_fillet", arguments: [
            "solidId": .string("box-1"),
            "edge": .string("edge:top-front"),
            "radius": .double(0.0)
        ])
        #expect(zeroRadiusRes.isError == true)

        // 3. Missing / nonexistent edge label
        let missingEdgeRes = await registry.callTool(name: "cad_fillet", arguments: [
            "solidId": .string("box-1"),
            "edge": .string("edge:nonexistent-label"),
            "radius": .double(2.0)
        ])
        #expect(missingEdgeRes.isError == true)
        #expect(missingEdgeRes.content.first?.text?.contains("Available edges:") == true)

        // 4. Excessive radius geometry failure
        let excessiveRes = await registry.callTool(name: "cad_fillet", arguments: [
            "solidId": .string("box-1"),
            "edge": .string("edge:top-front"),
            "radius": .double(500.0)
        ])
        #expect(excessiveRes.isError == true)
        #expect(excessiveRes.content.first?.text?.contains("Fillet failed") == true)
    }

    @Test func testQueryTreeReturnsFullHistory() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // Query entire tree
        let allRes = await registry.callTool(name: "cad_query_tree", arguments: [:])
        #expect(allRes.isError == false)
        let allText = try #require(allRes.content.first?.text)
        let allData = try #require(allText.data(using: .utf8))
        let allJson = try #require(try JSONSerialization.jsonObject(with: allData) as? [String: Any])
        let features = try #require(allJson["features"] as? [[String: Any]])
        #expect(features.count >= 2) // default box and cylinder

        let firstFeat = try #require(features.first)
        #expect(firstFeat["type"] as? String == "primitive")
        #expect(firstFeat["primitiveKind"] as? String == "box")
        let topology = try #require(firstFeat["generatedTopology"] as? [String: String])
        #expect(topology["edge:top-front"] != nil)
        let featIdStr = try #require(firstFeat["id"] as? String)

        // Query single feature by ID
        let singleRes = await registry.callTool(name: "cad_query_tree", arguments: [
            "featureId": .string(featIdStr)
        ])
        #expect(singleRes.isError == false)
        let singleText = try #require(singleRes.content.first?.text)
        let singleJson = try #require(try JSONSerialization.jsonObject(with: singleText.data(using: .utf8)!) as? [String: Any])
        #expect(singleJson["id"] as? String == featIdStr)
        #expect(singleJson["name"] as? String == firstFeat["name"] as? String)
    }

    @Test func testSetParamExtrudeDistance() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // Create sketch and extrude
        let createRes = await registry.callTool(name: "cad_create_sketch", arguments: [
            "plane": .string("XY"),
            "entities": .array([
                .dictionary([
                    "type": .string("circle"),
                    "centerX": .double(0),
                    "centerY": .double(0),
                    "radius": .double(10)
                ])
            ])
        ])
        #expect(createRes.isError == false)
        let json = try #require(try JSONSerialization.jsonObject(with: createRes.content.first!.text!.data(using: .utf8)!) as? [String: Any])
        let sketchIdStr = try #require(json["id"] as? String)

        let extrudeRes = await registry.callTool(name: "cad_extrude", arguments: [
            "sketchId": .string(sketchIdStr),
            "distance": .double(25)
        ])
        #expect(extrudeRes.isError == false)

        let extrudeObj = try #require(doc.objects.first(where: { $0.id.rawValue.hasPrefix("extrude-") }))
        let solidId = extrudeObj.id

        // Modify distance via solidId
        let setParamRes = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string(solidId.rawValue),
            "param": .string("distance"),
            "value": .double(45)
        ])
        #expect(setParamRes.isError == false)
        #expect(setParamRes.content.first?.text?.contains("45.0") == true)

        if case .extrude(let p) = doc.paramsFor(id: solidId) {
            #expect(p.distance == 45.0)
        } else {
            Issue.record("Expected extrude params")
        }

        // Modify distance via feature UUID
        let extrudeFeat = try #require(doc.features.first(where: { $0.outputSolidId == solidId }))
        let setParamByFeatRes = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string(extrudeFeat.id.uuidString),
            "param": .string("distance"),
            "value": .double(60)
        ])
        #expect(setParamByFeatRes.isError == false)
        #expect(setParamByFeatRes.content.first?.text?.contains("60.0") == true)

        if case .extrude(let p) = doc.paramsFor(id: solidId) {
            #expect(p.distance == 60.0)
        } else {
            Issue.record("Expected extrude params")
        }
    }

    @Test func testFeatureToolsArgumentValidationErrors() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // cad_create_sketch: invalid plane
        let badPlaneRes = await registry.callTool(name: "cad_create_sketch", arguments: [
            "plane": .string("INVALID_PLANE")
        ])
        #expect(badPlaneRes.isError == true)

        // cad_add_sketch_entity: missing sketchId
        let noSketchIdRes = await registry.callTool(name: "cad_add_sketch_entity", arguments: [
            "type": .string("line"),
            "startX": .double(0),
            "startY": .double(0),
            "endX": .double(10),
            "endY": .double(0)
        ])
        #expect(noSketchIdRes.isError == true)

        // cad_add_sketch_entity: unknown sketchId
        let fakeUUID = UUID().uuidString
        let unknownSketchRes = await registry.callTool(name: "cad_add_sketch_entity", arguments: [
            "sketchId": .string(fakeUUID),
            "type": .string("line"),
            "startX": .double(0),
            "startY": .double(0),
            "endX": .double(10),
            "endY": .double(0)
        ])
        #expect(unknownSketchRes.isError == true)

        // cad_add_sketch_entity: missing type
        let noTypeRes = await registry.callTool(name: "cad_add_sketch_entity", arguments: [
            "sketchId": .string(fakeUUID)
        ])
        #expect(noTypeRes.isError == true)

        // cad_add_sketch_entity: non-finite coordinates
        let nonFiniteRes = await registry.callTool(name: "cad_add_sketch_entity", arguments: [
            "sketchId": .string(fakeUUID),
            "type": .string("line"),
            "startX": .double(.nan),
            "startY": .double(0),
            "endX": .double(10),
            "endY": .double(0)
        ])
        #expect(nonFiniteRes.isError == true)

        // cad_add_constraint: missing entityIds
        let noEntitiesRes = await registry.callTool(name: "cad_add_constraint", arguments: [
            "sketchId": .string(fakeUUID),
            "type": .string("horizontal")
        ])
        #expect(noEntitiesRes.isError == true)

        // cad_add_constraint: unknown constraint kind
        let badKindRes = await registry.callTool(name: "cad_add_constraint", arguments: [
            "sketchId": .string(fakeUUID),
            "type": .string("skew"),
            "entityIds": .array([.string(UUID().uuidString)])
        ])
        #expect(badKindRes.isError == true)

        // cad_extrude: missing distance
        let noDistRes = await registry.callTool(name: "cad_extrude", arguments: [
            "sketchId": .string(fakeUUID)
        ])
        #expect(noDistRes.isError == true)

        // cad_fillet: missing arguments
        let noEdgeRes = await registry.callTool(name: "cad_fillet", arguments: [
            "solidId": .string("box-1"),
            "radius": .double(2.0)
        ])
        #expect(noEdgeRes.isError == true)

        // cad_query_tree: invalid featureId
        let badFeatIdRes = await registry.callTool(name: "cad_query_tree", arguments: [
            "featureId": .string("not-a-uuid")
        ])
        #expect(badFeatIdRes.isError == true)

        let unknownFeatIdRes = await registry.callTool(name: "cad_query_tree", arguments: [
            "featureId": .string(UUID().uuidString)
        ])
        #expect(unknownFeatIdRes.isError == true)
    }

    @Test func testQueryTopologyForSolid() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let res = await registry.callTool(name: "cad_query_topology", arguments: [
            "solidId": .string("box-1")
        ])
        #expect(res.isError == false)
        let text = try #require(res.content.first?.text)
        let data = try #require(text.data(using: .utf8))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["solidId"] as? String == "box-1")
        #expect(json["count"] as? Int == 26)

        let faces = try #require(json["faces"] as? [[String: Any]])
        #expect(faces.count == 6)
        let topFace = try #require(faces.first(where: { $0["label"] as? String == "face:top" }))
        #expect(topFace["elementType"] as? String == "face")
        #expect(topFace["type"] as? String == "plane")
        #expect(topFace["area"] as? Double == 1200.0)
        #expect(topFace["areaOrLength"] as? Double == 1200.0)
        let normal = try #require(topFace["normal"] as? [Double])
        #expect(normal.count == 3)
        #expect(normal[0] == 0.0 && normal[1] == 0.0 && normal[2] == 1.0)
        let centroid = try #require(topFace["centroid"] as? [Double])
        #expect(centroid.count == 3)
        #expect(centroid[0] == 0.0 && centroid[1] == 0.0 && centroid[2] == 10.0)

        let edges = try #require(json["edges"] as? [[String: Any]])
        #expect(edges.count == 12)
        let topFrontEdge = try #require(edges.first(where: { $0["label"] as? String == "edge:top-front" }))
        #expect(topFrontEdge["elementType"] as? String == "edge")
        #expect(topFrontEdge["type"] as? String == "line")
        #expect(topFrontEdge["length"] as? Double == 40.0)
        #expect(topFrontEdge["areaOrLength"] as? Double == 40.0)
        let edgeCentroid = try #require(topFrontEdge["centroid"] as? [Double])
        #expect(edgeCentroid.count == 3)

        let vertices = try #require(json["vertices"] as? [[String: Any]])
        #expect(vertices.count == 8)
        let vert = try #require(vertices.first(where: { $0["label"] as? String == "vertex:top-front-left" }))
        #expect(vert["elementType"] as? String == "vertex")
        let vertCentroid = try #require(vert["centroid"] as? [Double])
        #expect(vertCentroid.count == 3)
    }

    @Test func testQueryTopologyFilteredByElementType() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // Filter: face
        let faceRes = await registry.callTool(name: "cad_query_topology", arguments: [
            "solidId": .string("box-1"),
            "elementType": .string("face")
        ])
        #expect(faceRes.isError == false)
        let faceText = try #require(faceRes.content.first?.text)
        let faceJson = try #require(try JSONSerialization.jsonObject(with: faceText.data(using: .utf8)!) as? [String: Any])
        #expect(faceJson["count"] as? Int == 6)
        let faces = try #require(faceJson["faces"] as? [[String: Any]])
        #expect(faces.count == 6)
        #expect(faceJson["edges"] == nil)
        #expect(faceJson["vertices"] == nil)

        // Filter: edge
        let edgeRes = await registry.callTool(name: "cad_query_topology", arguments: [
            "solidId": .string("box-1"),
            "elementType": .string("edge")
        ])
        #expect(edgeRes.isError == false)
        let edgeText = try #require(edgeRes.content.first?.text)
        let edgeJson = try #require(try JSONSerialization.jsonObject(with: edgeText.data(using: .utf8)!) as? [String: Any])
        #expect(edgeJson["count"] as? Int == 12)
        let edges = try #require(edgeJson["edges"] as? [[String: Any]])
        #expect(edges.count == 12)
        #expect(edgeJson["faces"] == nil)
        #expect(edgeJson["vertices"] == nil)

        // Filter: vertex
        let vertRes = await registry.callTool(name: "cad_query_topology", arguments: [
            "solidId": .string("box-1"),
            "elementType": .string("vertex")
        ])
        #expect(vertRes.isError == false)
        let vertText = try #require(vertRes.content.first?.text)
        let vertJson = try #require(try JSONSerialization.jsonObject(with: vertText.data(using: .utf8)!) as? [String: Any])
        #expect(vertJson["count"] as? Int == 8)
        let vertices = try #require(vertJson["vertices"] as? [[String: Any]])
        #expect(vertices.count == 8)
        #expect(vertJson["faces"] == nil)
        #expect(vertJson["edges"] == nil)
    }

    @Test func testQueryTopologyByFeatureId() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let boxFeat = try #require(doc.feature(for: SolidId("box-1")))
        let featIdStr = boxFeat.id.uuidString

        let res = await registry.callTool(name: "cad_query_topology", arguments: [
            "featureId": .string(featIdStr)
        ])
        #expect(res.isError == false)
        let text = try #require(res.content.first?.text)
        let json = try #require(try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any])
        #expect(json["featureId"] as? String == featIdStr)
        #expect(json["solidId"] as? String == "box-1")
        #expect(json["count"] as? Int == 26)

        // Empty topology feature check
        let emptyFeat = Feature(
            id: UUID(),
            name: "Empty Feature",
            operation: .primitive(.box(BoxParams(width: 40, depth: 30, height: 20))),
            inputExpressions: [:],
            references: [],
            isSuppressed: false,
            errorState: nil,
            generatedTopology: [:]
        )
        doc.addFeature(emptyFeat)
        let emptyRes = await registry.callTool(name: "cad_query_topology", arguments: [
            "featureId": .string(emptyFeat.id.uuidString)
        ])
        #expect(emptyRes.isError == false)
        let emptyText = try #require(emptyRes.content.first?.text)
        let emptyData = try #require(emptyText.data(using: .utf8))
        let emptyObj = try JSONSerialization.jsonObject(with: emptyData)
        let emptyJson = try #require(emptyObj as? [String: Any])
        #expect(emptyJson["count"] as? Int == 0)
        let emptyFaces = try #require(emptyJson["faces"] as? [[String: Any]])
        let emptyEdges = try #require(emptyJson["edges"] as? [[String: Any]])
        let emptyVertices = try #require(emptyJson["vertices"] as? [[String: Any]])
        #expect(emptyFaces.isEmpty)
        #expect(emptyEdges.isEmpty)
        #expect(emptyVertices.isEmpty)
    }

    @Test func testQueryTopologyAllSolids() async throws {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let res = await registry.callTool(name: "cad_query_topology", arguments: [:])
        #expect(res.isError == false)
        let text = try #require(res.content.first?.text)
        let json = try #require(try JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as? [String: Any])
        let solids = try #require(json["solids"] as? [[String: Any]])
        #expect(solids.count >= 2)

        let boxSummary = try #require(solids.first(where: { $0["solidId"] as? String == "box-1" }))
        #expect(boxSummary["count"] as? Int == 26)

        let cylSummary = try #require(solids.first(where: { $0["solidId"] as? String == "cylinder-1" }))
        let cylFaces = try #require(cylSummary["faces"] as? [[String: Any]])
        #expect(cylFaces.count == 3)
        let sideFace = try #require(cylFaces.first(where: { $0["label"] as? String == "face:side" }))
        #expect(sideFace["type"] as? String == "cylinder")
        let topFace = try #require(cylFaces.first(where: { $0["label"] as? String == "face:top" }))
        #expect(topFace["type"] as? String == "plane")
        let bottomFace = try #require(cylFaces.first(where: { $0["label"] as? String == "face:bottom" }))
        #expect(bottomFace["type"] as? String == "plane")

        let cylEdges = try #require(cylSummary["edges"] as? [[String: Any]])
        #expect(cylEdges.count == 3)
        #expect(cylEdges.contains(where: { $0["type"] as? String == "circle" }))
        #expect(cylEdges.contains(where: { $0["type"] as? String == "line" }))

        let totalCount = try #require(json["count"] as? Int)
        #expect(totalCount >= 26 + 8)
    }

    @Test func testQueryTopologyErrorCases() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // Nonexistent solid
        let badSolidRes = await registry.callTool(name: "cad_query_topology", arguments: [
            "solidId": .string("missing-solid")
        ])
        #expect(badSolidRes.isError == true)
        #expect(badSolidRes.content.first?.text?.contains("not found in scene") == true)

        // Malformed feature ID
        let badFeatIdRes = await registry.callTool(name: "cad_query_topology", arguments: [
            "featureId": .string("not-a-uuid")
        ])
        #expect(badFeatIdRes.isError == true)
        #expect(badFeatIdRes.content.first?.text?.contains("Invalid UUID") == true)

        // Nonexistent feature ID
        let unknownFeatIdRes = await registry.callTool(name: "cad_query_topology", arguments: [
            "featureId": .string(UUID().uuidString)
        ])
        #expect(unknownFeatIdRes.isError == true)
        #expect(unknownFeatIdRes.content.first?.text?.contains("not found in document") == true)

        // Invalid element type
        let badTypeRes = await registry.callTool(name: "cad_query_topology", arguments: [
            "elementType": .string("polygon")
        ])
        #expect(badTypeRes.isError == true)
        #expect(badTypeRes.content.first?.text?.contains("Invalid elementType") == true)
    }

    // MARK: - BL-AGT-06: Agent Undo/Redo Attribution Tests (#154)

    @Test func testAgentAddSolidUndoRedo() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let args: [String: AnyCodableValue] = [
            "type": .string("box"),
            "width": .double(50),
            "depth": .double(30),
            "height": .double(20)
        ]
        let result = await registry.callTool(name: "cad_add_solid", arguments: args)
        #expect(result.isError == false)
        #expect(doc.objects.count == 3)
        guard let addedId = doc.objects.last?.id else {
            Issue.record("Expected added object")
            return
        }

        #expect(doc.undoManager?.undoActionName == "Agent: cad_add_solid")
        #expect(doc.undoActionTitle == "Undo Agent: cad_add_solid")
        #expect(doc.canUndo == true)

        doc.undo()

        #expect(doc.objects.count == 2)
        #expect(doc.objects.contains(where: { $0.id == addedId }) == false)
        #expect(doc.canRedo == true)
        #expect(doc.redoActionTitle == "Redo Agent: cad_add_solid")

        doc.redo()

        #expect(doc.objects.count == 3)
        #expect(doc.objects.contains(where: { $0.id == addedId }) == true)
        #expect(doc.undoActionTitle == "Undo Agent: cad_add_solid")
    }

    @Test func testAgentSetParamUndoRedo() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let initialDef = doc.paramsFor(id: boxSolidId)
        if case .box(let p) = initialDef {
            #expect(p.width == 40)
        }

        let args: [String: AnyCodableValue] = [
            "id": .string("box-1"),
            "param": .string("width"),
            "value": .double(65)
        ]
        let result = await registry.callTool(name: "cad_set_param", arguments: args)
        #expect(result.isError == false)
        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            #expect(p.width == 65)
        }

        #expect(doc.undoManager?.undoActionName == "Agent: cad_set_param")
        #expect(doc.undoActionTitle == "Undo Agent: cad_set_param")
        #expect(doc.canUndo == true)

        doc.undo()

        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            #expect(p.width == 40)
        }
        #expect(doc.canRedo == true)
        #expect(doc.redoActionTitle == "Redo Agent: cad_set_param")

        doc.redo()

        if case .box(let p) = doc.paramsFor(id: boxSolidId) {
            #expect(p.width == 65)
        }
        #expect(doc.undoActionTitle == "Undo Agent: cad_set_param")
    }

    @Test func testAgentSetTransformUndoRedo() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let initialPos = doc.objects.first(where: { $0.id == boxSolidId })?.transform.position
        #expect(initialPos?.x == -25)

        let args: [String: AnyCodableValue] = [
            "id": .string("box-1"),
            "posX": .double(100),
            "posY": .double(50),
            "posZ": .double(10)
        ]
        let result = await registry.callTool(name: "cad_set_transform", arguments: args)
        #expect(result.isError == false)
        let updatedPos = doc.objects.first(where: { $0.id == boxSolidId })?.transform.position
        #expect(updatedPos?.x == 100)

        #expect(doc.undoManager?.undoActionName == "Agent: cad_set_transform")
        #expect(doc.undoActionTitle == "Undo Agent: cad_set_transform")
        #expect(doc.canUndo == true)

        doc.undo()

        let revertedPos = doc.objects.first(where: { $0.id == boxSolidId })?.transform.position
        #expect(revertedPos?.x == -25)
        #expect(doc.canRedo == true)
        #expect(doc.redoActionTitle == "Redo Agent: cad_set_transform")

        doc.redo()

        let redonePos = doc.objects.first(where: { $0.id == boxSolidId })?.transform.position
        #expect(redonePos?.x == 100)
        #expect(doc.undoActionTitle == "Undo Agent: cad_set_transform")
    }

    @Test func testAgentRemoveSolidUndoRedo() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        let args: [String: AnyCodableValue] = [
            "id": .string("cylinder-1")
        ]
        let result = await registry.callTool(name: "cad_remove_solid", arguments: args)
        #expect(result.isError == false)
        #expect(doc.objects.count == 1)
        #expect(doc.objects.contains(where: { $0.id == cylinderSolidId }) == false)

        #expect(doc.undoManager?.undoActionName == "Agent: cad_remove_solid")
        #expect(doc.undoActionTitle == "Undo Agent: cad_remove_solid")
        #expect(doc.canUndo == true)

        doc.undo()

        #expect(doc.objects.count == 2)
        #expect(doc.objects.contains(where: { $0.id == cylinderSolidId }) == true)
        #expect(doc.canRedo == true)
        #expect(doc.redoActionTitle == "Redo Agent: cad_remove_solid")

        doc.redo()

        #expect(doc.objects.count == 1)
        #expect(doc.objects.contains(where: { $0.id == cylinderSolidId }) == false)
        #expect(doc.undoActionTitle == "Undo Agent: cad_remove_solid")
    }

    @Test func testAgentBooleanOperationUndoRedoWithKeepTool() async {
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
        #expect(doc.objects.count == 3)
        let booleanObj = doc.objects.last
        #expect(booleanObj?.id.rawValue.hasPrefix("boolean-") == true)
        let boxObj = doc.objects.first(where: { $0.id == boxSolidId })
        let cylObj = doc.objects.first(where: { $0.id == cylinderSolidId })
        #expect(boxObj?.isVisible == false)
        #expect(cylObj?.isVisible == false)

        #expect(doc.undoManager?.undoActionName == "Agent: cad_boolean_operation")
        #expect(doc.undoActionTitle == "Undo Agent: cad_boolean_operation")
        #expect(doc.canUndo == true)

        doc.undo()

        #expect(doc.objects.count == 2)
        #expect(doc.objects.contains(where: { $0.id == booleanObj?.id }) == false)
        let boxAfterUndo = doc.objects.first(where: { $0.id == boxSolidId })
        let cylAfterUndo = doc.objects.first(where: { $0.id == cylinderSolidId })
        #expect(boxAfterUndo?.isVisible == true)
        #expect(cylAfterUndo?.isVisible == true)

        #expect(doc.canRedo == true)
        #expect(doc.redoActionTitle == "Redo Agent: cad_boolean_operation")

        doc.redo()

        #expect(doc.objects.count == 3)
        #expect(doc.objects.contains(where: { $0.id == booleanObj?.id }) == true)
        let boxAfterRedo = doc.objects.first(where: { $0.id == boxSolidId })
        let cylAfterRedo = doc.objects.first(where: { $0.id == cylinderSolidId })
        #expect(boxAfterRedo?.isVisible == false)
        #expect(cylAfterRedo?.isVisible == false)
        #expect(doc.undoActionTitle == "Undo Agent: cad_boolean_operation")
    }

    @Test func testAgentFailedToolCallRegistersNoUndo() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        #expect(doc.canUndo == false)

        // 1. Invalid solid type
        let addBad = await registry.callTool(name: "cad_add_solid", arguments: ["type": .string("invalid_shape")])
        #expect(addBad.isError == true)
        #expect(doc.canUndo == false)

        // 2. Set param on missing solid
        let setMissing = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string("nonexistent"),
            "param": .string("width"),
            "value": .double(10)
        ])
        #expect(setMissing.isError == true)
        #expect(doc.canUndo == false)

        // 3. Set transform with missing id
        let transMissing = await registry.callTool(name: "cad_set_transform", arguments: ["posX": .double(10)])
        #expect(transMissing.isError == true)
        #expect(doc.canUndo == false)

        // 4. Remove missing solid
        let removeMissing = await registry.callTool(name: "cad_remove_solid", arguments: ["id": .string("nonexistent")])
        #expect(removeMissing.isError == true)
        #expect(doc.canUndo == false)

        // 5. Boolean with missing operand
        let boolMissing = await registry.callTool(name: "cad_boolean_operation", arguments: [
            "solidA": .string("box-1"),
            "solidB": .string("nonexistent"),
            "operation": .string("subtract")
        ])
        #expect(boolMissing.isError == true)
        #expect(doc.canUndo == false)
    }

    @Test func testAgentThreeSequentialToolCallsUndoneInReverseOrder() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // Step 1: Add solid
        let addRes = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("sphere"),
            "radius": .double(15)
        ])
        #expect(addRes.isError == false)
        guard let sphereId = doc.objects.last?.id else {
            Issue.record("Expected sphere")
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)

        // Step 2: Set param
        let paramRes = await registry.callTool(name: "cad_set_param", arguments: [
            "id": .string(sphereId.rawValue),
            "param": .string("radius"),
            "value": .double(25)
        ])
        #expect(paramRes.isError == false)
        try? await Task.sleep(nanoseconds: 5_000_000)

        // Step 3: Set transform
        let transRes = await registry.callTool(name: "cad_set_transform", arguments: [
            "id": .string(sphereId.rawValue),
            "posX": .double(50)
        ])
        #expect(transRes.isError == false)
        try? await Task.sleep(nanoseconds: 5_000_000)

        // 3 steps in reverse order:
        // Undo 1: Reverts transform
        #expect(doc.undoActionTitle == "Undo Agent: cad_set_transform")
        doc.undo()
        try? await Task.sleep(nanoseconds: 5_000_000)
        let posAfterUndo1 = doc.objects.first(where: { $0.id == sphereId })?.transform.position.x
        #expect(posAfterUndo1 == 0)

        // Undo 2: Reverts param
        #expect(doc.undoActionTitle == "Undo Agent: cad_set_param")
        doc.undo()
        try? await Task.sleep(nanoseconds: 5_000_000)
        if case .sphere(let p) = doc.paramsFor(id: sphereId) {
            #expect(p.radius == 15)
        }

        // Undo 3: Reverts add solid
        #expect(doc.undoActionTitle == "Undo Agent: cad_add_solid")
        doc.undo()
        try? await Task.sleep(nanoseconds: 5_000_000)
        #expect(doc.objects.contains(where: { $0.id == sphereId }) == false)
        #expect(doc.canUndo == false)
    }

    @Test func testGUIEditBetweenAgentCallsKeepsSeparateStep() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)

        // Agent Call 1: cad_add_solid
        let addRes = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("wedge"),
            "width": .double(30),
            "depth": .double(30),
            "height": .double(30)
        ])
        #expect(addRes.isError == false)
        guard let wedgeId = doc.objects.last?.id else {
            Issue.record("Expected wedge")
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)

        // GUI Mutation: Unattributed setParam
        let guiRes = doc.setParam(id: wedgeId, key: "width", value: 50)
        #expect(guiRes == .success(()))
        try? await Task.sleep(nanoseconds: 5_000_000)

        // Agent Call 2: cad_set_transform
        let transRes = await registry.callTool(name: "cad_set_transform", arguments: [
            "id": .string(wedgeId.rawValue),
            "posX": .double(30)
        ])
        #expect(transRes.isError == false)
        try? await Task.sleep(nanoseconds: 5_000_000)

        // Verify sequence of undo titles:
        // 1. Agent transform
        #expect(doc.undoActionTitle == "Undo Agent: cad_set_transform")
        doc.undo()
        try? await Task.sleep(nanoseconds: 5_000_000)

        // 2. GUI param change ("Change Width")
        #expect(doc.undoActionTitle == "Undo Change Width")
        doc.undo()
        try? await Task.sleep(nanoseconds: 5_000_000)

        // 3. Agent add solid
        #expect(doc.undoActionTitle == "Undo Agent: cad_add_solid")
        doc.undo()
        try? await Task.sleep(nanoseconds: 5_000_000)

        #expect(doc.canUndo == false)
    }

    @Test func testMCPStdioDocumentUndoIsolation() async {
        let hostDoc = DocumentModel()
        let stdioDoc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: stdioDoc, kernelClient: kernel)

        #expect(hostDoc.canUndo == false)
        #expect(stdioDoc.canUndo == false)

        let addRes = await registry.callTool(name: "cad_add_solid", arguments: [
            "type": .string("sphere"),
            "radius": .double(12)
        ])
        #expect(addRes.isError == false)

        #expect(stdioDoc.canUndo == true)
        #expect(stdioDoc.undoActionTitle == "Undo Agent: cad_add_solid")

        // Host doc remains untouched
        #expect(hostDoc.canUndo == false)
        #expect(hostDoc.undoActionTitle == "Undo")
    }

    @Test func testKernelRestartBetweenCallAndUndoRegeneratesConsistently() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let registry = CADToolRegistry(document: doc, kernelClient: kernel)
        await seedKernel(kernel)

        let args: [String: AnyCodableValue] = [
            "type": .string("box"),
            "width": .double(50),
            "depth": .double(40),
            "height": .double(30)
        ]
        let addRes = await registry.callTool(name: "cad_add_solid", arguments: args)
        #expect(addRes.isError == false)
        #expect(doc.objects.count == 3)
        guard let addedId = doc.objects.last?.id else { return }

        // Simulate kernel restart and regeneration before undo
        await KernelRegeneration.regenerate(document: doc, client: kernel, excluding: nil)

        // Undo the agent call
        doc.undo()
        #expect(doc.objects.count == 2)
        #expect(doc.objects.contains(where: { $0.id == addedId }) == false)

        // Regenerate again after undo
        await KernelRegeneration.regenerate(document: doc, client: kernel, excluding: nil)
        #expect(doc.objects.count == 2)
    }

    @Test func testMeasureImportedSolidReturnsBounds() async {
        let doc = DocumentModel()
        let kernel = KernelClient(debounceDuration: .milliseconds(5))
        let sink = RecordingMeshSink()
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, meshSink: sink)

        let importedId = doc.addObject(def: .imported(name: "bracket.step"))
        let payload = NativeGeometryGenerator.generateBox(width: 10, depth: 20, height: 30)
        _ = sink.installMesh(payload, for: importedId, transform: .identity, color: SIMD4<Float>(0.5, 0.5, 0.5, 1.0), isHidden: false)

        let result = await registry.callTool(name: "cad_measure", arguments: ["id": .string(importedId.rawValue)])
        #expect(result.isError == false)

        guard let text = result.content.first?.text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Expected valid JSON response from cad_measure")
            return
        }

        #expect(json["type"] as? String == "imported")
        #expect(json["name"] as? String == "bracket.step")

        guard let aabb = json["axisAlignedBox"] as? [String: Any],
              let obb = json["orientedBox"] as? [String: Any],
              let bounds = json["bounds"] as? [String: Any] else {
            Issue.record("Expected bounding box and bounds keys in measure result")
            return
        }

        #expect(aabb["volume"] as? Double == 6000.0)
        #expect(obb["volume"] as? Double == 6000.0)
        if let aabbSize = aabb["size"] as? [Double] {
            #expect(aabbSize.count == 3)
            #expect(abs(aabbSize[0] - 10.0) < 0.01)
            #expect(abs(aabbSize[1] - 20.0) < 0.01)
            #expect(abs(aabbSize[2] - 30.0) < 0.01)
        }
        _ = bounds
    }

    @Test func testCADReorderFeaturesTool() async throws {
        let (doc, kernel, _, registry) = makeWindowBoundFixture()
        await seedKernel(kernel)

        #expect(doc.features.count == 2)
        let f0 = doc.features[0].id.uuidString
        let f1 = doc.features[1].id.uuidString

        // Valid reorder
        let validRes = await registry.callTool(name: "reorder_features", arguments: [
            "feature_ids": .array([.string(f1), .string(f0)])
        ])
        #expect(validRes.isError == false)
        #expect(doc.features.map(\.id.uuidString) == [f1, f0])

        // Invalid reorder (missing/corrupt IDs)
        let invalidRes = await registry.callTool(name: "reorder_features", arguments: [
            "feature_ids": .array([.string(f1)])
        ])
        #expect(invalidRes.isError == true)
        #expect(invalidRes.content.first?.text?.contains("Reorder failed") == true)
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

    func candidateMesh(for id: SolidId) -> CandidateMesh? {
        guard let entry = meshes[id] else { return nil }
        return CandidateMesh(id: id, payload: entry.payload, transform: entry.transform)
    }
}

private final class FailingSnapshotProvider: SnapshotProvider {
    func captureSnapshotPngBase64() async -> String? { nil }
}
