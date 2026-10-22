import Testing
import Foundation
import SwiftUI
import simd
@testable import MadeApp
@testable import MadeCore

@Suite(.serialized) @MainActor struct AssemblyAppTests {

    @Test func testNewAssemblyShortcutConstants() {
        #expect(WorkspaceModel.newAssemblyShortcutKey == "n")
        #expect(WorkspaceModel.newAssemblyShortcutModifiers == [.option, .command])
    }

    @Test func testNewAssemblyDocumentInWorkspace() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        #expect(ws.document.documentType == .assembly)
        #expect(ws.document.componentInstances.isEmpty)
        #expect(ws.document.objects.isEmpty)
        #expect(!ws.isDocumentModified)
        #expect(ws.currentDocumentURL == nil)
    }

    @Test func testComponentInstanceOperationsInWorkspace() {
        let ws = WorkspaceModel()
        ws.newAssemblyDocument()

        let instance = ws.addComponentInstance(
            name: "Bracket Left",
            reference: .internalPart(name: "BracketPart"),
            transform: Transform(position: SIMD3<Float>(0, 0, 0))
        )

        #expect(ws.document.componentInstances.count == 1)
        #expect(ws.isDocumentModified)
        #expect(ws.selectedId == instance.solidId)
        ws.document.undoManager?.removeAllActions()

        let targetTransform = Transform(
            position: SIMD3<Float>(50, 100, 150),
            rotation: simd_quatf.fromEulerAngles(degrees: SIMD3<Float>(0, 90, 0)),
            scale: SIMD3<Float>(1, 1, 1)
        )
        let updated = ws.updateComponentInstanceTransform(id: instance.id, transform: targetTransform)
        #expect(updated)
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(50, 100, 150))

        ws.undo()
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(0, 0, 0))

        ws.redo()
        #expect(ws.document.componentInstances.first?.transform.position == SIMD3<Float>(50, 100, 150))

        ws.setComponentInstanceName(id: instance.id, name: "Bracket Front")
        #expect(ws.document.componentInstances.first?.name == "Bracket Front")
        ws.document.undoManager?.removeAllActions()

        let removed = ws.removeComponentInstance(id: instance.id)
        #expect(removed)
        #expect(ws.document.componentInstances.isEmpty)
        #expect(ws.selectedId == nil)

        ws.undo()
        #expect(ws.document.componentInstances.count == 1)
        #expect(ws.document.componentInstances.first?.name == "Bracket Front")
    }

    @Test func testSaveAndOpenAssemblyPackageInWorkspace() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AssemblyTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageURL = tempDir.appendingPathComponent("MechanicalAssembly.made")

        let ws1 = WorkspaceModel()
        ws1.newAssemblyDocument()

        _ = ws1.addComponentInstance(
            name: "Pinion",
            reference: .internalPart(name: "PinionPart"),
            transform: Transform(position: SIMD3<Float>(10, 20, 30))
        )
        _ = ws1.addComponentInstance(
            name: "Spur",
            reference: .externalDocument(url: URL(fileURLWithPath: "/models/spur.made")),
            transform: Transform(position: SIMD3<Float>(40, 50, 60))
        )

        let saved = ws1.saveDocument(to: packageURL)
        #expect(saved)
        #expect(!ws1.isDocumentModified)
        #expect(FileManager.default.fileExists(atPath: packageURL.path))

        let ws2 = WorkspaceModel()
        let opened = ws2.openDocument(at: packageURL)
        #expect(opened)
        #expect(ws2.document.documentType == .assembly)
        #expect(ws2.document.componentInstances.count == 2)

        let pinion = ws2.document.componentInstances.first(where: { $0.name == "Pinion" })
        #expect(pinion != nil)
        #expect(pinion?.transform.position == SIMD3<Float>(10, 20, 30))

        let spur = ws2.document.componentInstances.first(where: { $0.name == "Spur" })
        #expect(spur != nil)
        #expect(spur?.transform.position == SIMD3<Float>(40, 50, 60))
    }
}
