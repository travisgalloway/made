import Testing
import Foundation
import SwiftUI
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct BillOfMaterialsAppTests {

    @Test func testWorkspaceCanExportBillOfMaterialsState() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        #expect(ws.canExportBillOfMaterials == false)

        let instance = ws.addComponentInstance(
            name: "Bracket",
            reference: .internalPart(name: "BracketPart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )

        #expect(ws.canExportBillOfMaterials == true)

        _ = ws.removeComponentInstance(id: instance.id)
        #expect(ws.canExportBillOfMaterials == false)
    }

    @Test func testWorkspaceExportBillOfMaterialsFlatCSV() async throws {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        _ = ws.addComponentInstance(
            name: "Sensor Mount",
            reference: .internalPart(name: "MountPart"),
            transform: Transform.identity
        )
        if let id = ws.document.componentInstances.first?.id {
            ws.setComponentProperty(id: id, key: CustomPropertyKey.partNumber, value: "SM-100")
            ws.setComponentProperty(id: id, key: CustomPropertyKey.description, value: "Optical Sensor Mount")
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let exportURL = tempDir.appendingPathComponent("test-bom-flat.csv")

        let success = await ws.exportBillOfMaterials(to: exportURL, structure: .flat)
        #expect(success == true)
        #expect(ws.pendingExportError == nil)
        #expect(ws.isShowingExportErrorAlert == false)

        #expect(FileManager.default.fileExists(atPath: exportURL.path))
        let content = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(content.contains("SM-100"))
        #expect(content.contains("Optical Sensor Mount"))
        #expect(content.contains("Item,Name,Part Number,Description,Revision,Vendor,Material,Quantity\r\n"))
    }

    @Test func testWorkspaceExportBillOfMaterialsHierarchicalCSV() async throws {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let child = ComponentInstance(
            name: "Gear",
            reference: .internalPart(name: "GearPart"),
            metadata: [CustomPropertyKey.partNumber: "GR-01"]
        )
        let sub = ComponentInstance(
            name: "Gearbox Subassembly",
            reference: .subassembly(name: "Gearbox"),
            childInstances: [child]
        )

        _ = ws.document.addComponentInstance(sub)
        #expect(ws.canExportBillOfMaterials == true)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let exportURL = tempDir.appendingPathComponent("test-bom-hierarchical.csv")

        let success = await ws.exportBillOfMaterials(to: exportURL, structure: .hierarchical)
        #expect(success == true)
        #expect(ws.pendingExportError == nil)
        #expect(ws.isShowingExportErrorAlert == false)

        #expect(FileManager.default.fileExists(atPath: exportURL.path))
        let content = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(content.contains("Item,Level,Name,Part Number,Description,Revision,Vendor,Material,Quantity,Type\r\n"))
        #expect(content.contains("1,1,Gearbox Subassembly,,,,,,1,Subassembly\r\n"))
        #expect(content.contains("1.1,2,Gear,GR-01,,,,,1,Part\r\n"))
    }

    @Test func testWorkspaceExportBillOfMaterialsEmptyFailsGracefully() async {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()
        #expect(ws.canExportBillOfMaterials == false)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("empty-test.csv")
        let success = await ws.exportBillOfMaterials(to: tempURL, structure: .flat)

        #expect(success == false)
        #expect(ws.pendingExportError != nil)
        #expect(ws.isShowingExportErrorAlert == true)
        #expect(FileManager.default.fileExists(atPath: tempURL.path) == false)
    }
}
