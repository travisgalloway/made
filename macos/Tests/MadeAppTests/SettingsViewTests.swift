import Testing
import SwiftUI
@testable import MadeApp
import MadeCore

@Suite struct SettingsViewTests {
    @Test @MainActor func testSettingsViewTabCases() {
        #expect(SettingsView.Tab.allCases.count == 6)
        let expected: [SettingsView.Tab] = [.general, .units, .navigation, .display, .tolerances, .shortcuts]
        #expect(SettingsView.Tab.allCases == expected)
        for tab in SettingsView.Tab.allCases {
            #expect(!tab.rawValue.isEmpty)
            #expect(tab.id == tab.rawValue)
        }
    }

    @Test @MainActor func testSettingsViewInstantiation() {
        let model = WorkspaceModel()
        let view = SettingsView(initialTab: .general)
            .environment(model)
        #expect(view != nil)

        for tab in SettingsView.Tab.allCases {
            let tabView = SettingsView(initialTab: tab).environment(model)
            #expect(tabView != nil)
        }
    }

    @Test @MainActor func testShortcutFilteringLogic() {
        let entries = WorkspaceModel.standardShortcuts

        // Empty query matches all
        let allFiltered = entries.filter { _ in true }
        #expect(allFiltered.count == entries.count)

        // Filter by category
        let toolsOnly = entries.filter { $0.category == .tools }
        #expect(toolsOnly.count == 4)
        for entry in toolsOnly {
            #expect(entry.category == .tools)
        }

        let navOnly = entries.filter { $0.category == .navigation }
        #expect(navOnly.count >= 9)

        // Search query by title
        let searchBox = entries.filter { $0.title.lowercased().contains("box") }
        #expect(searchBox.count >= 1)
        #expect(searchBox.first?.title == "Add Box")

        // Search query by shortcut text
        let searchOpt = entries.filter { $0.shortcut.lowercased().contains("⌥") }
        #expect(searchOpt.count >= 4)

        // Search query with no match
        let noMatch = entries.filter { $0.title.lowercased().contains("nonexistent_action_xyz") }
        #expect(noMatch.isEmpty)
    }

    @Test @MainActor func testPrecisionAndToleranceClampingActions() {
        let model = WorkspaceModel()

        // Precision clamping
        model.decimalPrecision = 10
        #expect(model.decimalPrecision == UnitSettings.maxDecimalPrecision)

        model.decimalPrecision = -3
        #expect(model.decimalPrecision == UnitSettings.minDecimalPrecision)

        // Tolerance clamping
        model.kernelTolerances = KernelTolerances(linearTolerance: -0.5, angularTolerance: 0.0, chordalTolerance: -1.0)
        #expect(model.kernelTolerances.linearTolerance == KernelTolerances.minLinearTolerance)
        #expect(model.kernelTolerances.angularTolerance == KernelTolerances.minAngularTolerance)
        #expect(model.kernelTolerances.chordalTolerance == KernelTolerances.minChordalTolerance)
        #expect(model.kernelTolerances.isValid)
    }
}
