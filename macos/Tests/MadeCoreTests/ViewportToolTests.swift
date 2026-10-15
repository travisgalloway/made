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

    // MARK: - Navigation Presets Tests

    @Test func testNavigationPresetsMiddleButton() {
        // Default (Made): Middle = pan
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: false, preset: .defaultPreset) == .pan)

        // SolidWorks: Middle = orbit, Ctrl+Middle = pan, Shift+Middle = zoom
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: false, control: false, preset: .solidWorks) == .orbit)
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: false, control: true, preset: .solidWorks) == .pan)
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: true, control: false, preset: .solidWorks) == .zoom)

        // Fusion 360: Middle = pan, Ctrl+Middle = zoom, Shift+Middle = orbit
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: false, control: false, preset: .fusion360) == .pan)
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: false, control: true, preset: .fusion360) == .zoom)
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: true, control: false, preset: .fusion360) == .orbit)

        // Blender: Middle = orbit, Ctrl+Middle = zoom, Shift+Middle = pan
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: false, control: false, preset: .blender) == .orbit)
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: false, control: true, preset: .blender) == .zoom)
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: true, control: false, preset: .blender) == .pan)

        // Onshape: Middle = pan
        #expect(ViewportTool.dragAction(tool: .select, button: .middle, option: false, shift: false, preset: .onshape) == .pan)
    }

    @Test func testNavigationPresetsSecondaryButton() {
        for preset in NavigationPreset.allCases {
            // Secondary drag orbits, Shift+Secondary drag pans
            #expect(ViewportTool.dragAction(tool: .select, button: .secondary, option: false, shift: false, preset: preset) == .orbit)
            #expect(ViewportTool.dragAction(tool: .select, button: .secondary, option: false, shift: true, preset: preset) == .pan)
        }
    }

    @Test func testInvariant8PreservationAcrossAllPresets() {
        // Invariant 8: Under tool == .select with primary button and no option navigation, dragAction is ALWAYS .manipulate
        for preset in NavigationPreset.allCases {
            #expect(ViewportTool.dragAction(tool: .select, button: .primary, option: false, shift: false, preset: preset) == .manipulate)
            #expect(ViewportTool.dragAction(tool: .select, button: .primary, option: false, shift: true, preset: preset) == .manipulate)
            #expect(ViewportTool.dragAction(tool: .select, button: .primary, option: false, shift: false, control: true, preset: preset) == .manipulate)
            #expect(ViewportTool.dragAction(tool: .select, button: .primary, option: false, shift: false, command: true, preset: preset) == .manipulate)
        }
    }

    @Test func testNavigationPresetDescriptionsAndIdentifiable() {
        for preset in NavigationPreset.allCases {
            #expect(!preset.displayName.isEmpty)
            #expect(!preset.description.isEmpty)
            #expect(preset.id == preset.rawValue)
        }
    }
}
