import Testing
import Foundation
import CoreGraphics
@testable import MadeCore

@Suite struct RadialMenuLayoutTests {
    private let layout = RadialMenuLayout()

    @Test func testEffectiveRadius() {
        #expect(layout.menuRadius == 54.0)
        #expect(layout.itemRadius == 22.0)
        #expect(layout.margin == 8.0)
        #expect(layout.effectiveRadius == 84.0)
    }

    @Test func testItemAnglesFor4Items() {
        let count = 4
        let a0 = layout.itemAngle(index: 0, count: count)
        let a1 = layout.itemAngle(index: 1, count: count)
        let a2 = layout.itemAngle(index: 2, count: count)
        let a3 = layout.itemAngle(index: 3, count: count)

        #expect(abs(a0 - (-CGFloat.pi / 2.0)) < 1e-5)
        #expect(abs(a1 - 0.0) < 1e-5)
        #expect(abs(a2 - (CGFloat.pi / 2.0)) < 1e-5)
        #expect(abs(a3 - CGFloat.pi) < 1e-5)
    }

    @Test func testItemPositionsFor4Items() {
        let count = 4
        let center = CGPoint(x: 100, y: 100)
        let p0 = layout.itemPosition(center: center, index: 0, count: count)
        let p1 = layout.itemPosition(center: center, index: 1, count: count)
        let p2 = layout.itemPosition(center: center, index: 2, count: count)
        let p3 = layout.itemPosition(center: center, index: 3, count: count)

        // 12 o'clock: (100, 46)
        #expect(abs(p0.x - 100.0) < 1e-4)
        #expect(abs(p0.y - 46.0) < 1e-4)

        // 3 o'clock: (154, 100)
        #expect(abs(p1.x - 154.0) < 1e-4)
        #expect(abs(p1.y - 100.0) < 1e-4)

        // 6 o'clock: (100, 154)
        #expect(abs(p2.x - 100.0) < 1e-4)
        #expect(abs(p2.y - 154.0) < 1e-4)

        // 9 o'clock: (46, 100)
        #expect(abs(p3.x - 46.0) < 1e-4)
        #expect(abs(p3.y - 100.0) < 1e-4)
    }

    @Test func testItemAnglesAndPositionsFor2Items() {
        let count = 2
        let center = CGPoint(x: 200, y: 200)

        let a0 = layout.itemAngle(index: 0, count: count)
        let a1 = layout.itemAngle(index: 1, count: count)
        #expect(abs(a0 - (-CGFloat.pi / 2.0)) < 1e-5)
        #expect(abs(a1 - (CGFloat.pi / 2.0)) < 1e-5)

        let p0 = layout.itemPosition(center: center, index: 0, count: count)
        let p1 = layout.itemPosition(center: center, index: 1, count: count)
        #expect(abs(p0.x - 200.0) < 1e-4)
        #expect(abs(p0.y - 146.0) < 1e-4)
        #expect(abs(p1.x - 200.0) < 1e-4)
        #expect(abs(p1.y - 254.0) < 1e-4)
    }

    @Test func testClampedCenterWithinBounds() {
        let viewport = CGSize(width: 800, height: 600)
        let pointer = CGPoint(x: 250, y: 350)
        let clamped = layout.clampedCenter(pointer: pointer, viewportSize: viewport)

        #expect(clamped.x == 250.0)
        #expect(clamped.y == 350.0)
    }

    @Test func testClampedCenterTopLeft() {
        let viewport = CGSize(width: 800, height: 600)
        let pointer = CGPoint(x: 20, y: 30)
        let clamped = layout.clampedCenter(pointer: pointer, viewportSize: viewport)

        #expect(clamped.x == 84.0)
        #expect(clamped.y == 84.0)
    }

    @Test func testClampedCenterBottomRight() {
        let viewport = CGSize(width: 800, height: 600)
        let pointer = CGPoint(x: 790, y: 580)
        let clamped = layout.clampedCenter(pointer: pointer, viewportSize: viewport)

        #expect(clamped.x == 716.0)
        #expect(clamped.y == 516.0)
    }

    @Test func testClampedCenterUndersizedViewport() {
        let viewport = CGSize(width: 100, height: 120)
        let pointer = CGPoint(x: 10, y: 10)
        let clamped = layout.clampedCenter(pointer: pointer, viewportSize: viewport)

        #expect(clamped.x == 50.0)
        #expect(clamped.y == 60.0)
    }

    @Test func testMenuItemModel() {
        let item = RadialMenuItem(
            id: .delete,
            title: "Delete",
            iconName: "trash",
            isDestructive: true
        )
        #expect(item.id == .delete)
        #expect(item.title == "Delete")
        #expect(item.iconName == "trash")
        #expect(item.isDestructive == true)

        let defaultDestructive = RadialMenuItem(
            id: .duplicate,
            title: "Duplicate",
            iconName: "plus.square.on.square"
        )
        #expect(defaultDestructive.isDestructive == false)
    }
}
