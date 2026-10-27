import SwiftUI
import AppKit
import MadeCore

/// User-configurable options for vector file import into a sketch (BL-SKT-14, #362).
@Observable
@MainActor
public final class SketchImportOptions {
    public var unitOverride: LengthUnit?
    public var scale: Double
    public var weldEndpoints: Bool
    public var markAllConstruction: Bool

    public init(
        unitOverride: LengthUnit? = nil,
        scale: Double = 1.0,
        weldEndpoints: Bool = true,
        markAllConstruction: Bool = false
    ) {
        self.unitOverride = unitOverride
        self.scale = scale
        self.weldEndpoints = weldEndpoints
        self.markAllConstruction = markAllConstruction
    }
}

/// SwiftUI accessory view presenting unit override, scale, endpoint welding, and construction selection for NSOpenPanel.
public struct SketchImportAccessoryView: View {
    @Bindable var options: SketchImportOptions

    public init(options: SketchImportOptions) {
        self.options = options
    }

    public var body: some View {
        Form {
            Section("Import Options") {
                Picker("Units", selection: $options.unitOverride) {
                    Text("Automatic (from file)").tag(LengthUnit?.none)
                    ForEach(LengthUnit.allCases) { unit in
                        Text(unit.displayName).tag(Optional(unit))
                    }
                }

                TextField("Scale Factor", value: $options.scale, format: .number)
                    .textFieldStyle(.roundedBorder)

                Toggle("Weld Endpoints", isOn: $options.weldEndpoints)
                Toggle("Import as Construction", isOn: $options.markAllConstruction)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

/// AppKit hosting view wrapping SketchImportAccessoryView for NSOpenPanel.accessoryView.
@MainActor
public final class SketchImportAccessoryHostingView: NSHostingView<SketchImportAccessoryView> {
    public let options: SketchImportOptions

    public init(options: SketchImportOptions = SketchImportOptions()) {
        self.options = options
        super.init(rootView: SketchImportAccessoryView(options: options))
        self.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(rootView: SketchImportAccessoryView) {
        self.options = rootView.options
        super.init(rootView: rootView)
        self.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
    }
}
