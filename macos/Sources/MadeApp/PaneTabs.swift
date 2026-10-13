import SwiftUI

/// A side-pane tab: a title for VoiceOver and tooltips, and a symbol for the tab bar.
protocol PaneTab: Hashable, CaseIterable, Identifiable where AllCases: RandomAccessCollection {
    var title: String { get }
    var systemImage: String { get }
}

extension PaneTab where Self: RawRepresentable, RawValue == String {
    var id: String { rawValue }
}

enum NavigatorTab: String, PaneTab {
    case scene

    var title: String { "Scene" }
    var systemImage: String { "cube" }
}

enum InspectorTab: String, PaneTab {
    case properties

    var title: String { "Properties" }
    var systemImage: String { "slider.horizontal.3" }
}

/// Icon tab selector at the top of a side pane. Xcode left-aligns navigator tabs and stretches inspector tabs to the pane width.
struct PaneTabBar<Tab: PaneTab>: View {
    let label: String
    @Binding var selection: Tab
    var fillsWidth = false

    var body: some View {
        PaneSegmentedControl(label: label, selection: $selection, fillsWidth: fillsWidth)
            .fixedSize(horizontal: !fillsWidth, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

/// SwiftUI's segmented Picker cannot stretch its segments, so this wraps NSSegmentedControl for `.fillEqually`.
private struct PaneSegmentedControl<Tab: PaneTab>: NSViewRepresentable {
    let label: String
    @Binding var selection: Tab
    let fillsWidth: Bool

    private var tabs: [Tab] { Array(Tab.allCases) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let images = tabs.map { NSImage(systemSymbolName: $0.systemImage, accessibilityDescription: $0.title) ?? NSImage() }
        let control = NSSegmentedControl(images: images, trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = fillsWidth ? .fillEqually : .fit
        control.setAccessibilityLabel(label)
        for (index, tab) in tabs.enumerated() {
            control.setToolTip(tab.title, forSegment: index)
        }
        control.setContentHuggingPriority(fillsWidth ? .defaultLow : .required, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = tabs.firstIndex(of: selection) ?? 0
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PaneSegmentedControl

        init(parent: PaneSegmentedControl) { self.parent = parent }

        @objc func changed(_ sender: NSSegmentedControl) {
            let tabs = parent.tabs
            guard tabs.indices.contains(sender.selectedSegment) else { return }
            parent.selection = tabs[sender.selectedSegment]
        }
    }
}
