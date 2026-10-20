import Testing
import SwiftUI
import simd
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct RadialMenuViewTests {

    @Test @MainActor func testEmptySpaceItems() {
        let items = RadialMenuView.items(targetSolid: nil)
        #expect(items.count == 2)

        let addBox = items[0]
        #expect(addBox.id == .addBox)
        #expect(addBox.title == "Add Box")
        #expect(addBox.iconName == "cube")
        #expect(!addBox.isDestructive)

        let addCyl = items[1]
        #expect(addCyl.id == .addCylinder)
        #expect(addCyl.title == "Add Cylinder")
        #expect(addCyl.iconName == "cylinder")
        #expect(!addCyl.isDestructive)
    }

    @Test @MainActor func testSolidItems() {
        let unlockedVisible = SceneObject(
            id: ObjectId("test-1"),
            name: "Test Part",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            isVisible: true,
            isLocked: false
        )
        let items1 = RadialMenuView.items(targetSolid: unlockedVisible)
        #expect(items1.count == 4)
        #expect(items1[0].id == .delete)
        #expect(items1[0].isDestructive)
        #expect(items1[1].id == .duplicate)
        #expect(!items1[1].isDestructive)
        #expect(items1[2].id == .lock)
        #expect(items1[2].title == "Lock")
        #expect(items1[2].iconName == "lock")
        #expect(items1[3].id == .hide)
        #expect(items1[3].title == "Hide")
        #expect(items1[3].iconName == "eye.slash")

        let lockedHidden = SceneObject(
            id: ObjectId("test-2"),
            name: "Test Part 2",
            def: .box(BoxParams(width: 10, depth: 10, height: 10)),
            isVisible: false,
            isLocked: true
        )
        let items2 = RadialMenuView.items(targetSolid: lockedHidden)
        #expect(items2[2].id == .lock)
        #expect(items2[2].title == "Unlock")
        #expect(items2[2].iconName == "lock.open")
        #expect(items2[3].id == .hide)
        #expect(items2[3].title == "Show")
        #expect(items2[3].iconName == "eye")
    }

    @Test @MainActor func testExecuteAddBoxDismissesMenu() {
        let model = WorkspaceModel()
        let countBefore = model.document.objects.count
        model.openRadialMenu(at: CGPoint(x: 100, y: 100), targetSolidId: nil)
        #expect(model.radialMenuState != nil)

        RadialMenuView.execute(command: .addBox, targetSolidId: nil, workspace: model)

        #expect(model.document.objects.count == countBefore + 1)
        #expect(model.radialMenuState == nil)
    }

    @Test @MainActor func testExecuteAddCylinderDismissesMenu() {
        let model = WorkspaceModel()
        let countBefore = model.document.objects.count
        model.openRadialMenu(at: CGPoint(x: 100, y: 100), targetSolidId: nil)
        #expect(model.radialMenuState != nil)

        RadialMenuView.execute(command: .addCylinder, targetSolidId: nil, workspace: model)

        #expect(model.document.objects.count == countBefore + 1)
        #expect(model.radialMenuState == nil)
    }

    @Test @MainActor func testExecuteDuplicateDismissesMenuAndOffsetsObject() {
        let model = WorkspaceModel()
        guard let box = model.document.objects.first else {
            Issue.record("Expected initial box object")
            return
        }
        let initialPos = box.transform.position

        model.openRadialMenu(at: CGPoint(x: 100, y: 100), targetSolidId: box.id)
        #expect(model.radialMenuState != nil)

        RadialMenuView.execute(command: .duplicate, targetSolidId: box.id, workspace: model)

        #expect(model.radialMenuState == nil)
        guard let duplicated = model.selectedObject else {
            Issue.record("Expected newly duplicated object to be selected")
            return
        }
        #expect(duplicated.id != box.id)
        #expect(duplicated.name == "\(box.name) Copy")
        #expect(duplicated.transform.position == initialPos + SIMD3<Float>(10, 10, 0))

        // Verify undo removes duplicated object
        #expect(model.canUndo)
        model.undo()
        #expect(!model.document.objects.contains(where: { $0.id == duplicated.id }))
    }

    @Test @MainActor func testExecuteToggleLockAndHideDismissesMenu() {
        let model = WorkspaceModel()
        guard let box = model.document.objects.first else {
            Issue.record("Expected initial box object")
            return
        }

        model.openRadialMenu(at: CGPoint(x: 100, y: 100), targetSolidId: box.id)
        RadialMenuView.execute(command: .lock, targetSolidId: box.id, workspace: model)
        #expect(model.radialMenuState == nil)
        #expect(model.document.objects.first(where: { $0.id == box.id })?.isLocked == true)

        model.openRadialMenu(at: CGPoint(x: 100, y: 100), targetSolidId: box.id)
        RadialMenuView.execute(command: .hide, targetSolidId: box.id, workspace: model)
        #expect(model.radialMenuState == nil)
        #expect(model.document.objects.first(where: { $0.id == box.id })?.isVisible == false)
    }

    @Test @MainActor func testExecuteDeleteDismissesMenu() {
        let model = WorkspaceModel()
        guard let box = model.document.objects.first else {
            Issue.record("Expected initial box object")
            return
        }

        model.openRadialMenu(at: CGPoint(x: 100, y: 100), targetSolidId: box.id)
        RadialMenuView.execute(command: .delete, targetSolidId: box.id, workspace: model)
        #expect(model.radialMenuState == nil)
        #expect(!model.document.objects.contains(where: { $0.id == box.id }))
    }

    @Test @MainActor func testDismissRadialMenuPreservesSceneAndSelection() {
        let model = WorkspaceModel()
        guard let box = model.document.objects.first else {
            Issue.record("Expected initial box object")
            return
        }
        model.selectedId = box.id
        let initialObjectsCount = model.document.objects.count

        model.openRadialMenu(at: CGPoint(x: 150, y: 150), targetSolidId: box.id)
        #expect(model.radialMenuState != nil)

        model.dismissRadialMenu()

        #expect(model.radialMenuState == nil)
        #expect(model.selectedId == box.id)
        #expect(model.document.objects.count == initialObjectsCount)
    }

    @Test @MainActor func testAutoDismissalOnSelectionChanges() {
        let model = WorkspaceModel()
        let secondId = model.document.addObject(def: .box(BoxParams(width: 20, depth: 20, height: 20)))

        // 1. Changing selectedId dismisses menu
        model.openRadialMenu(at: CGPoint(x: 100, y: 100), targetSolidId: nil)
        #expect(model.radialMenuState != nil)
        model.selectedId = secondId
        #expect(model.radialMenuState == nil)

        // 2. Changing selectedIds dismisses menu
        model.openRadialMenu(at: CGPoint(x: 100, y: 100), targetSolidId: nil)
        #expect(model.radialMenuState != nil)
        model.selectedIds = [secondId]
        #expect(model.radialMenuState == nil)

        // 3. Clearing selection dismisses menu
        model.openRadialMenu(at: CGPoint(x: 100, y: 100), targetSolidId: nil)
        #expect(model.radialMenuState != nil)
        model.clearSelection()
        #expect(model.radialMenuState == nil)
    }
}
