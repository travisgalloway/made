import Testing
import Foundation
@testable import MadeCore

@Suite struct ViewportToolTests {
    @Test func testPlainPrimaryDragFollowsTheTool() {
        let expected: [ViewportTool: ViewportDragAction] = [.select: .manipulate, .orbit: .orbit, .pan: .pan, .zoom: .zoom]
        for (tool, action) in expected {
            #expect(ViewportTool.dragAction(tool: tool, button: .primary, option: false, shift: false) == action, "\(tool)")
        }
    }

    @Test func testModifierNavigationWorksUnderEveryTool() {
        for tool in ViewportTool.allCases {
            #expect(ViewportTool.dragAction(tool: tool, button: .primary, option: true, shift: false) == .orbit)
            #expect(ViewportTool.dragAction(tool: tool, button: .primary, option: true, shift: true) == .pan)
            #expect(ViewportTool.dragAction(tool: tool, button: .secondary, option: false, shift: false) == .orbit)
            #expect(ViewportTool.dragAction(tool: tool, button: .secondary, option: false, shift: true) == .pan)
            #expect(ViewportTool.dragAction(tool: tool, button: .middle, option: false, shift: false) == .pan)
        }
    }

    @Test func testShiftPrimaryDragUnderSelectStillManipulates() {
        #expect(ViewportTool.dragAction(tool: .select, button: .primary, option: false, shift: true) == .manipulate)
    }

    @Test func testOnlyManipulateIsNotNavigation() {
        #expect(!ViewportDragAction.manipulate.isNavigation)
        #expect(ViewportDragAction.orbit.isNavigation)
        #expect(ViewportDragAction.pan.isNavigation)
        #expect(ViewportDragAction.zoom.isNavigation)
    }

    @Test func testShortcutKeysAreUniqueAndCaseInsensitive() {
        #expect(Set(ViewportTool.allCases.map(\.shortcutKey)).count == ViewportTool.allCases.count)
        for tool in ViewportTool.allCases {
            #expect(ViewportTool.forShortcutKey(tool.shortcutKey) == tool)
            #expect(ViewportTool.forShortcutKey(Character(tool.shortcutKey.uppercased())) == tool)
        }
        #expect(ViewportTool.forShortcutKey("f") == nil)
    }

    @Test func testZoomDragUpMovesCloser() {
        #expect(ViewportTool.zoomFactor(forDragDeltaY: 10) < 1)
        #expect(ViewportTool.zoomFactor(forDragDeltaY: -10) > 1)
        #expect(ViewportTool.zoomFactor(forDragDeltaY: 0) == 1)
    }
}
