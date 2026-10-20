import Testing
import SwiftUI
import AppKit
@testable import MadeApp
import MadeCore

@Suite(.serialized) struct CommandPanelAccessibilityTests {

    @Test func testDefaultAccessibilityTraitsContainButton() {
        #expect(CommandSelectionSlotRow.defaultAccessibilityTraits.contains(.isButton))
    }

    @Test func testAccessibilityTraitsSelectedAndUnselected() {
        let unselected = CommandSelectionSlotRow.accessibilityTraits(isSelected: false)
        let selected = CommandSelectionSlotRow.accessibilityTraits(isSelected: true)

        #expect(unselected.contains(.isButton))
        #expect(!unselected.contains(.isSelected))
        #expect(selected.contains(.isButton))
        #expect(selected.contains(.isSelected))

        #expect(CommandSelectionSlotRow.accessibilityTraits() == CommandSelectionSlotRow.defaultAccessibilityTraits)
    }

    @Test func testAccessibilityLabelFormattingAcrossSlotStates() {
        // Required slot without selection
        #expect(CommandSelectionSlotRow.accessibilityLabel(
            label: "Target",
            isRequired: true,
            selectedObjectName: nil
        ) == "Target, Required, Click solid to select")

        // Required slot with selection
        #expect(CommandSelectionSlotRow.accessibilityLabel(
            label: "Target",
            isRequired: true,
            selectedObjectName: "Body 1"
        ) == "Target, Required, Body 1")

        // Optional slot without selection
        #expect(CommandSelectionSlotRow.accessibilityLabel(
            label: "Tool",
            isRequired: false,
            selectedObjectName: nil
        ) == "Tool, Click solid to select")

        // Optional slot with selection
        #expect(CommandSelectionSlotRow.accessibilityLabel(
            label: "Tool",
            isRequired: false,
            selectedObjectName: "Body 2"
        ) == "Tool, Body 2")

        // Default parameter checks
        #expect(CommandSelectionSlotRow.accessibilityLabel(label: "Target") == "Target, Click solid to select")

        // Slot struct accessibility label tests
        let slotRequiredEmpty = CommandSelectionSlot(
            id: "target",
            label: "Target",
            isRequired: true,
            selectedObjectName: nil,
            isActive: false
        )
        #expect(CommandSelectionSlotRow.accessibilityLabel(for: slotRequiredEmpty) == "Target, Required, Click solid to select")

        let slotRequiredFilled = CommandSelectionSlot(
            id: "target",
            label: "Target",
            isRequired: true,
            selectedObjectName: "Body 1",
            isActive: true
        )
        #expect(CommandSelectionSlotRow.accessibilityLabel(for: slotRequiredFilled) == "Target, Required, Body 1")

        let slotOptionalEmpty = CommandSelectionSlot(
            id: "tool",
            label: "Tool",
            isRequired: false,
            selectedObjectName: nil,
            isActive: false
        )
        #expect(CommandSelectionSlotRow.accessibilityLabel(for: slotOptionalEmpty) == "Tool, Click solid to select")

        let slotOptionalFilled = CommandSelectionSlot(
            id: "tool",
            label: "Tool",
            isRequired: false,
            selectedObjectName: "Body 2",
            isActive: false
        )
        #expect(CommandSelectionSlotRow.accessibilityLabel(for: slotOptionalFilled) == "Tool, Body 2")
    }

    @Test @MainActor func testSlotRowLayoutAcrossSlotStates() {
        let slots = [
            CommandSelectionSlot(id: "s1", label: "Target", isRequired: true, selectedObjectName: nil, isActive: false),
            CommandSelectionSlot(id: "s2", label: "Target", isRequired: true, selectedObjectName: "Body 1", isActive: true),
            CommandSelectionSlot(id: "s3", label: "Tool", isRequired: false, selectedObjectName: nil, isActive: true),
            CommandSelectionSlot(id: "s4", label: "Tool", isRequired: false, selectedObjectName: "Body 2", isActive: false),
        ]

        for slot in slots {
            var selected = false
            let rowView = CommandSelectionSlotRow(slot: slot) {
                selected = true
            }

            let hostingView = NSHostingView(rootView: AnyView(rowView))
            hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 32)
            hostingView.layoutSubtreeIfNeeded()

            #expect(hostingView.frame.width == 220)
            #expect(hostingView.frame.height == 32)
            #expect(!selected)
        }
    }

    @Test @MainActor func testSlotActivationViaSessionSelectSlot() {
        let session = CommandSession(
            title: "Combine",
            selectionSlots: [
                CommandSelectionSlot(id: "target", label: "Target", isRequired: true, isActive: true),
                CommandSelectionSlot(id: "tool", label: "Tool", isRequired: false, isActive: false),
            ]
        )

        #expect(session.selectionSlots[0].isActive)
        #expect(!session.selectionSlots[1].isActive)

        // Switch to tool slot
        session.selectSlot(id: "tool")
        #expect(!session.selectionSlots[0].isActive)
        #expect(session.selectionSlots[1].isActive)

        // Switch back to target slot
        session.selectSlot(id: "target")
        #expect(session.selectionSlots[0].isActive)
        #expect(!session.selectionSlots[1].isActive)

        // Test activation callback wired to CommandSelectionSlotRow
        var selectedSlotId: String? = nil
        let targetRow = CommandSelectionSlotRow(slot: session.selectionSlots[0]) {
            selectedSlotId = session.selectionSlots[0].id
            session.selectSlot(id: session.selectionSlots[0].id)
        }
        let toolRow = CommandSelectionSlotRow(slot: session.selectionSlots[1]) {
            selectedSlotId = session.selectionSlots[1].id
            session.selectSlot(id: session.selectionSlots[1].id)
        }

        toolRow.onSelect()
        #expect(selectedSlotId == "tool")
        #expect(!session.selectionSlots[0].isActive)
        #expect(session.selectionSlots[1].isActive)

        targetRow.onSelect()
        #expect(selectedSlotId == "target")
        #expect(session.selectionSlots[0].isActive)
        #expect(!session.selectionSlots[1].isActive)
    }
}
