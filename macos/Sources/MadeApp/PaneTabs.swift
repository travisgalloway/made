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
    case construction
    case simulation

    var title: String {
        switch self {
        case .scene: return "Scene"
        case .construction: return "Construction"
        case .simulation: return "Simulation"
        }
    }

    var systemImage: String {
        switch self {
        case .scene: return "cube"
        case .construction: return "ruler"
        case .simulation: return "waveform.path.ecg"
        }
    }
}

enum InspectorTab: String, PaneTab {
    case properties
    case metadata
    case physical
    case document

    var title: String {
        switch self {
        case .properties: return "Attributes"
        case .metadata: return "Metadata"
        case .physical: return "Physical"
        case .document: return "Document"
        }
    }

    var systemImage: String {
        switch self {
        case .properties: return "slider.horizontal.3"
        case .metadata: return "tag"
        case .physical: return "scalemass"
        case .document: return "doc.text"
        }
    }
}

/// Icon tab selector at the top of a side pane. Xcode-style segmented icon bar that stretches evenly when `fillsWidth` is true.
struct PaneTabBar<Tab: PaneTab>: View {
    let label: String
    @Binding var selection: Tab
    var fillsWidth = false

    private var tabs: [Tab] { Array(Tab.allCases) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let isSelected = selection == tab
                Button {
                    selection = tab
                } label: {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 22)
                        .padding(.horizontal, fillsWidth ? 0 : 10)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .frame(maxWidth: .infinity, alignment: fillsWidth ? .center : .leading)
        .padding(.horizontal, 10)
        .frame(height: BarMetrics.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
