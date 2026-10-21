import SwiftUI
import AppKit
import MadeCore

/// User-configurable options for 3MF export.
@Observable
@MainActor
public final class ThreeMFExportOptions {
    public var tolerance: Double
    public var unit: LengthUnit

    public init(tolerance: Double = 0.01, unit: LengthUnit = .millimeters) {
        self.tolerance = tolerance
        self.unit = unit
    }
}

/// SwiftUI accessory view presenting tessellation tolerance and unit selection for NSSavePanel.
public struct ThreeMFExportAccessoryView: View {
    @Bindable var options: ThreeMFExportOptions

    public init(options: ThreeMFExportOptions) {
        self.options = options
    }

    public var body: some View {
        Form {
            Section("Export Options") {
                TextField("Tessellation Tolerance", value: $options.tolerance, format: .number)
                    .textFieldStyle(.roundedBorder)

                Picker("Unit", selection: $options.unit) {
                    ForEach(LengthUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            }
        }
        .padding()
        .frame(width: 300)
    }
}

/// AppKit hosting view wrapping ThreeMFExportAccessoryView for NSSavePanel.accessoryView.
@MainActor
public final class ThreeMFExportAccessoryHostingView: NSHostingView<ThreeMFExportAccessoryView> {
    public let options: ThreeMFExportOptions

    public init(options: ThreeMFExportOptions) {
        self.options = options
        super.init(rootView: ThreeMFExportAccessoryView(options: options))
        self.frame = NSRect(x: 0, y: 0, width: 300, height: 110)
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(rootView: ThreeMFExportAccessoryView) {
        self.options = rootView.options
        super.init(rootView: rootView)
        self.frame = NSRect(x: 0, y: 0, width: 300, height: 110)
    }
}
