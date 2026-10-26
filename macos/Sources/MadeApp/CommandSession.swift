import SwiftUI
import MadeCore
import simd

enum CommandPanelPlacement: String, CaseIterable, Identifiable, Sendable {
    case inspector = "Inspector"
    case floatingHUD = "Floating HUD"

    var id: String { rawValue }
}

struct CommandSelectionSlot: Identifiable, Sendable, Equatable {
    let id: String
    var label: String
    var isRequired: Bool
    var selectedObjectId: ObjectId?
    var selectedObjectName: String?
    var selectedSubElement: SelectedSubElement?
    var isActive: Bool

    init(
        id: String,
        label: String,
        isRequired: Bool = true,
        selectedObjectId: ObjectId? = nil,
        selectedObjectName: String? = nil,
        selectedSubElement: SelectedSubElement? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.label = label
        self.isRequired = isRequired
        self.selectedObjectId = selectedObjectId
        self.selectedObjectName = selectedObjectName
        self.selectedSubElement = selectedSubElement
        self.isActive = isActive
    }
}

enum CommandInputValue: Sendable, Equatable {
    case number(Float, range: ClosedRange<Float>?, step: Float = 1.0, unit: String = "mm")
    case text(String)
    case toggle(Bool)
    case choice(String, options: [String])
    case readOnlyText(String, unit: String = "")
}

struct CommandInput: Identifiable, Sendable, Equatable {
    let id: String
    var label: String
    var value: CommandInputValue

    init(id: String, label: String, value: CommandInputValue) {
        self.id = id
        self.label = label
        self.value = value
    }
}

@Observable
@MainActor
final class CommandSession: Identifiable {
    static let previewSolidId = SolidId("__preview__")

    let id: String
    let title: String
    var selectionSlots: [CommandSelectionSlot]
    var inputs: [CommandInput]
    var errorMessage: String?
    var isPreviewEnabled: Bool {
        didSet {
            if oldValue != isPreviewEnabled {
                onPreviewUpdate?()
            }
        }
    }
    var customValidation: (@MainActor () -> Bool)?
    var onParamChanged: (@MainActor (String, CommandInputValue) -> Void)?
    var onPreviewUpdate: (@MainActor () -> Void)?
    var onCommit: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?
    var dimensionAnchorsProvider: (@MainActor () -> [String: SIMD3<Float>])?
    var inputVisibilityPredicate: (@MainActor (CommandSession, CommandInput) -> Bool)?

    var visibleInputs: [CommandInput] {
        guard let predicate = inputVisibilityPredicate else { return inputs }
        return inputs.filter { predicate(self, $0) }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        selectionSlots: [CommandSelectionSlot] = [],
        inputs: [CommandInput] = [],
        isPreviewEnabled: Bool = true,
        errorMessage: String? = nil,
        customValidation: (@MainActor () -> Bool)? = nil,
        onParamChanged: (@MainActor (String, CommandInputValue) -> Void)? = nil,
        onPreviewUpdate: (@MainActor () -> Void)? = nil,
        onCommit: (@MainActor () -> Void)? = nil,
        onCancel: (@MainActor () -> Void)? = nil,
        dimensionAnchorsProvider: (@MainActor () -> [String: SIMD3<Float>])? = nil,
        inputVisibilityPredicate: (@MainActor (CommandSession, CommandInput) -> Bool)? = nil
    ) {
        self.id = id
        self.title = title
        self.selectionSlots = selectionSlots
        self.inputs = inputs
        self.isPreviewEnabled = isPreviewEnabled
        self.errorMessage = errorMessage
        self.customValidation = customValidation
        self.onParamChanged = onParamChanged
        self.onPreviewUpdate = onPreviewUpdate
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.dimensionAnchorsProvider = dimensionAnchorsProvider
        self.inputVisibilityPredicate = inputVisibilityPredicate
    }

    var canCommit: Bool {
        for slot in selectionSlots where slot.isRequired {
            if slot.selectedObjectId == nil && slot.selectedSubElement == nil { return false }
        }
        for input in inputs {
            switch input.value {
            case .number(let val, let range, _, _):
                if val.isNaN || val.isInfinite { return false }
                if let range, !range.contains(val) { return false }
            case .choice(let val, let options):
                if !options.isEmpty && !options.contains(val) { return false }
            default:
                break
            }
        }
        if let customValidation, !customValidation() {
            return false
        }
        return true
    }

    func numberValue(for id: String) -> Float? {
        guard let input = inputs.first(where: { $0.id == id }) else { return nil }
        if case .number(let val, _, _, _) = input.value {
            return val
        }
        return nil
    }

    func setNumberValue(_ val: Float, for id: String) {
        guard let idx = inputs.firstIndex(where: { $0.id == id }) else { return }
        switch inputs[idx].value {
        case .number(_, let range, let step, let unit):
            inputs[idx].value = .number(val, range: range, step: step, unit: unit)
            onParamChanged?(id, inputs[idx].value)
            if isPreviewEnabled {
                onPreviewUpdate?()
            }
        default:
            break
        }
    }

    /// Resolves the 3D world-space anchor for a given dimension input, using the explicit
    /// dimensionAnchorsProvider when set, or falling back to the center of the active preview
    /// or selected geometry bounds.
    func dimensionAnchor(for inputId: String, workspace: WorkspaceModel) -> SIMD3<Float>? {
        if let provider = dimensionAnchorsProvider {
            let anchors = provider()
            if let pt = anchors[inputId] {
                return pt
            }
        }
        guard let renderer = workspace.viewportManager.renderer else { return nil }
        var targetCandidate: CandidateMesh? = nil
        let meshes = renderer.candidateMeshes()

        if let previewMesh = renderer.meshes[CommandSession.previewSolidId] {
            var cand = previewMesh.candidateMesh
            cand.transform = previewMesh.transform
            targetCandidate = cand
        } else if let slotObjId = selectionSlots.first(where: { $0.selectedObjectId != nil })?.selectedObjectId,
                  let match = meshes.first(where: { $0.id == slotObjId }) {
            targetCandidate = match
        } else if let selId = workspace.selectedId,
                  let match = meshes.first(where: { $0.id == selId }) {
            targetCandidate = match
        }

        guard let target = targetCandidate,
              let bounds = SceneBounds.of([target]) else {
            return nil
        }
        return (bounds.min + bounds.max) * 0.5
    }

    func textValue(for id: String) -> String? {
        guard let input = inputs.first(where: { $0.id == id }) else { return nil }
        if case .text(let val) = input.value {
            return val
        }
        return nil
    }

    func setTextValue(_ val: String, for id: String) {
        guard let idx = inputs.firstIndex(where: { $0.id == id }) else { return }
        if case .text = inputs[idx].value {
            inputs[idx].value = .text(val)
            onParamChanged?(id, inputs[idx].value)
            if isPreviewEnabled {
                onPreviewUpdate?()
            }
        }
    }

    func toggleValue(for id: String) -> Bool? {
        guard let input = inputs.first(where: { $0.id == id }) else { return nil }
        if case .toggle(let val) = input.value {
            return val
        }
        return nil
    }

    func booleanValue(for id: String) -> Bool? {
        toggleValue(for: id)
    }

    func setToggleValue(_ val: Bool, for id: String) {
        guard let idx = inputs.firstIndex(where: { $0.id == id }) else { return }
        if case .toggle = inputs[idx].value {
            inputs[idx].value = .toggle(val)
            onParamChanged?(id, inputs[idx].value)
            if isPreviewEnabled {
                onPreviewUpdate?()
            }
        }
    }

    func choiceValue(for id: String) -> String? {
        guard let input = inputs.first(where: { $0.id == id }) else { return nil }
        if case .choice(let val, _) = input.value {
            return val
        }
        return nil
    }

    func setChoiceValue(_ val: String, for id: String) {
        guard let idx = inputs.firstIndex(where: { $0.id == id }) else { return }
        if case .choice(_, let options) = inputs[idx].value {
            inputs[idx].value = .choice(val, options: options)
            onParamChanged?(id, inputs[idx].value)
            if isPreviewEnabled {
                onPreviewUpdate?()
            }
        }
    }

    func selectSlot(id: String) {
        for i in selectionSlots.indices {
            selectionSlots[i].isActive = (selectionSlots[i].id == id)
        }
    }

    func setSlotSelection(slotId: String, objectId: ObjectId?, objectName: String?, subElement: SelectedSubElement? = nil) {
        guard let idx = selectionSlots.firstIndex(where: { $0.id == slotId }) else { return }
        selectionSlots[idx].selectedObjectId = objectId
        selectionSlots[idx].selectedObjectName = objectName
        selectionSlots[idx].selectedSubElement = subElement
        onPreviewUpdate?()
    }

    func commit() {
        guard canCommit else { return }
        onCommit?()
    }

    func cancel() {
        onCancel?()
    }
}

extension CommandSession {
    static func makeAddBox(workspace: WorkspaceModel) -> CommandSession {
        let session = CommandSession(
            title: "Add Box",
            inputs: [
                CommandInput(id: "width", label: "Width (X)", value: .number(30.0, range: DocumentLimits.boxWidth.min...DocumentLimits.boxWidth.max, step: 1.0, unit: "mm")),
                CommandInput(id: "depth", label: "Depth (Y)", value: .number(30.0, range: DocumentLimits.boxDepth.min...DocumentLimits.boxDepth.max, step: 1.0, unit: "mm")),
                CommandInput(id: "height", label: "Height (Z)", value: .number(30.0, range: DocumentLimits.boxHeight.min...DocumentLimits.boxHeight.max, step: 1.0, unit: "mm"))
            ],
            isPreviewEnabled: true
        )

        session.dimensionAnchorsProvider = { [weak session] in
            guard let session else { return [:] }
            let w = session.numberValue(for: "width") ?? 30.0
            let d = session.numberValue(for: "depth") ?? 30.0
            let h = session.numberValue(for: "height") ?? 30.0
            return [
                "width": SIMD3<Float>(0, -d / 2.0, -h / 2.0),
                "depth": SIMD3<Float>(w / 2.0, 0, -h / 2.0),
                "height": SIMD3<Float>(w / 2.0, -d / 2.0, 0)
            ]
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            if session.isPreviewEnabled {
                let w = session.numberValue(for: "width") ?? 30.0
                let d = session.numberValue(for: "depth") ?? 30.0
                let h = session.numberValue(for: "height") ?? 30.0
                guard w >= DocumentLimits.boxWidth.min && w <= DocumentLimits.boxWidth.max,
                      d >= DocumentLimits.boxDepth.min && d <= DocumentLimits.boxDepth.max,
                      h >= DocumentLimits.boxHeight.min && h <= DocumentLimits.boxHeight.max else {
                    _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                    workspace.invalidateViewport(.interaction)
                    return
                }
                let payload = NativeGeometryGenerator.generateBox(width: w, depth: d, height: h)
                let previewColor = SIMD4<Float>(0.2, 0.6, 1.0, 0.75)
                _ = workspace.viewportManager.renderer?.installMesh(
                    payload,
                    for: Self.previewSolidId,
                    transform: .identity,
                    color: previewColor,
                    isHidden: false
                )
                workspace.invalidateViewport(.interaction)
            } else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
            }
        }

        session.onPreviewUpdate = updatePreview

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            let w = session.numberValue(for: "width") ?? 30.0
            let d = session.numberValue(for: "depth") ?? 30.0
            let h = session.numberValue(for: "height") ?? 30.0
            workspace.addObject(.box(BoxParams(width: w, depth: d, height: h)))
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    static func makeAddCylinder(workspace: WorkspaceModel) -> CommandSession {
        let session = CommandSession(
            title: "Add Cylinder",
            inputs: [
                CommandInput(id: "radius", label: "Radius", value: .number(12.0, range: DocumentLimits.cylinderRadius.min...DocumentLimits.cylinderRadius.max, step: 1.0, unit: "mm")),
                CommandInput(id: "height", label: "Height (Z)", value: .number(35.0, range: DocumentLimits.cylinderHeight.min...DocumentLimits.cylinderHeight.max, step: 1.0, unit: "mm"))
            ],
            isPreviewEnabled: true
        )

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            if session.isPreviewEnabled {
                let r = session.numberValue(for: "radius") ?? 12.0
                let h = session.numberValue(for: "height") ?? 35.0
                guard r >= DocumentLimits.cylinderRadius.min && r <= DocumentLimits.cylinderRadius.max,
                      h >= DocumentLimits.cylinderHeight.min && h <= DocumentLimits.cylinderHeight.max else {
                    _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                    workspace.invalidateViewport(.interaction)
                    return
                }
                let payload = NativeGeometryGenerator.generateCylinder(radius: r, height: h)
                let previewColor = SIMD4<Float>(0.2, 0.6, 1.0, 0.75)
                _ = workspace.viewportManager.renderer?.installMesh(
                    payload,
                    for: Self.previewSolidId,
                    transform: .identity,
                    color: previewColor,
                    isHidden: false
                )
                workspace.invalidateViewport(.interaction)
            } else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
            }
        }

        session.onPreviewUpdate = updatePreview

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            let r = session.numberValue(for: "radius") ?? 12.0
            let h = session.numberValue(for: "height") ?? 35.0
            workspace.addObject(.cylinder(CylinderParams(radius: r, height: h)))
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    static func makeAddSphere(workspace: WorkspaceModel) -> CommandSession {
        let session = CommandSession(
            title: "Add Sphere",
            inputs: [
                CommandInput(id: "radius", label: "Radius", value: .number(15.0, range: DocumentLimits.sphereRadius.min...DocumentLimits.sphereRadius.max, step: 1.0, unit: "mm"))
            ],
            isPreviewEnabled: true
        )

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            if session.isPreviewEnabled {
                let r = session.numberValue(for: "radius") ?? 15.0
                guard r >= DocumentLimits.sphereRadius.min && r <= DocumentLimits.sphereRadius.max else {
                    _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                    workspace.invalidateViewport(.interaction)
                    return
                }
                let payload = NativeGeometryGenerator.generateSphere(radius: r)
                let previewColor = SIMD4<Float>(0.2, 0.6, 1.0, 0.75)
                _ = workspace.viewportManager.renderer?.installMesh(
                    payload,
                    for: Self.previewSolidId,
                    transform: .identity,
                    color: previewColor,
                    isHidden: false
                )
                workspace.invalidateViewport(.interaction)
            } else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
            }
        }

        session.onPreviewUpdate = updatePreview

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            let r = session.numberValue(for: "radius") ?? 15.0
            workspace.addObject(.sphere(SphereParams(radius: r)))
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    static func makeAddCone(workspace: WorkspaceModel) -> CommandSession {
        let session = CommandSession(
            title: "Add Cone",
            inputs: [
                CommandInput(id: "bottomRadius", label: "Bottom Radius", value: .number(15.0, range: DocumentLimits.coneBottomRadius.min...DocumentLimits.coneBottomRadius.max, step: 1.0, unit: "mm")),
                CommandInput(id: "topRadius", label: "Top Radius", value: .number(0.0, range: DocumentLimits.coneTopRadius.min...DocumentLimits.coneTopRadius.max, step: 1.0, unit: "mm")),
                CommandInput(id: "height", label: "Height (Z)", value: .number(30.0, range: DocumentLimits.coneHeight.min...DocumentLimits.coneHeight.max, step: 1.0, unit: "mm"))
            ],
            isPreviewEnabled: true
        )

        session.customValidation = { [weak session] in
            guard let session else { return false }
            let br = session.numberValue(for: "bottomRadius") ?? 15.0
            let tr = session.numberValue(for: "topRadius") ?? 0.0
            return br > 0 || tr > 0
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            if session.isPreviewEnabled {
                let br = session.numberValue(for: "bottomRadius") ?? 15.0
                let tr = session.numberValue(for: "topRadius") ?? 0.0
                let h = session.numberValue(for: "height") ?? 30.0
                guard br >= DocumentLimits.coneBottomRadius.min && br <= DocumentLimits.coneBottomRadius.max,
                      tr >= DocumentLimits.coneTopRadius.min && tr <= DocumentLimits.coneTopRadius.max,
                      h >= DocumentLimits.coneHeight.min && h <= DocumentLimits.coneHeight.max,
                      br > 0 || tr > 0 else {
                    _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                    workspace.invalidateViewport(.interaction)
                    return
                }
                let payload = NativeGeometryGenerator.generateCone(bottomRadius: br, topRadius: tr, height: h)
                let previewColor = SIMD4<Float>(0.2, 0.6, 1.0, 0.75)
                _ = workspace.viewportManager.renderer?.installMesh(
                    payload,
                    for: Self.previewSolidId,
                    transform: .identity,
                    color: previewColor,
                    isHidden: false
                )
                workspace.invalidateViewport(.interaction)
            } else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
            }
        }

        session.onPreviewUpdate = updatePreview

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            let br = session.numberValue(for: "bottomRadius") ?? 15.0
            let tr = session.numberValue(for: "topRadius") ?? 0.0
            let h = session.numberValue(for: "height") ?? 30.0
            workspace.addObject(.cone(ConeParams(bottomRadius: br, topRadius: tr, height: h)))
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    static func makeAddTorus(workspace: WorkspaceModel) -> CommandSession {
        let session = CommandSession(
            title: "Add Torus",
            inputs: [
                CommandInput(id: "majorRadius", label: "Major Radius", value: .number(20.0, range: DocumentLimits.torusMajorRadius.min...DocumentLimits.torusMajorRadius.max, step: 1.0, unit: "mm")),
                CommandInput(id: "minorRadius", label: "Minor Radius", value: .number(5.0, range: DocumentLimits.torusMinorRadius.min...DocumentLimits.torusMinorRadius.max, step: 1.0, unit: "mm"))
            ],
            isPreviewEnabled: true
        )

        session.customValidation = { [weak session] in
            guard let session else { return false }
            let maj = session.numberValue(for: "majorRadius") ?? 20.0
            let minR = session.numberValue(for: "minorRadius") ?? 5.0
            return maj > minR
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            if session.isPreviewEnabled {
                let maj = session.numberValue(for: "majorRadius") ?? 20.0
                let minR = session.numberValue(for: "minorRadius") ?? 5.0
                guard maj >= DocumentLimits.torusMajorRadius.min && maj <= DocumentLimits.torusMajorRadius.max,
                      minR >= DocumentLimits.torusMinorRadius.min && minR <= DocumentLimits.torusMinorRadius.max,
                      maj > minR else {
                    _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                    workspace.invalidateViewport(.interaction)
                    return
                }
                let payload = NativeGeometryGenerator.generateTorus(majorRadius: maj, minorRadius: minR)
                let previewColor = SIMD4<Float>(0.2, 0.6, 1.0, 0.75)
                _ = workspace.viewportManager.renderer?.installMesh(
                    payload,
                    for: Self.previewSolidId,
                    transform: .identity,
                    color: previewColor,
                    isHidden: false
                )
                workspace.invalidateViewport(.interaction)
            } else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
            }
        }

        session.onPreviewUpdate = updatePreview

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            let maj = session.numberValue(for: "majorRadius") ?? 20.0
            let minR = session.numberValue(for: "minorRadius") ?? 5.0
            workspace.addObject(.torus(TorusParams(majorRadius: maj, minorRadius: minR)))
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    static func makeAddWedge(workspace: WorkspaceModel) -> CommandSession {
        let session = CommandSession(
            title: "Add Wedge",
            inputs: [
                CommandInput(id: "width", label: "Width (X)", value: .number(30.0, range: DocumentLimits.wedgeWidth.min...DocumentLimits.wedgeWidth.max, step: 1.0, unit: "mm")),
                CommandInput(id: "depth", label: "Depth (Y)", value: .number(30.0, range: DocumentLimits.wedgeDepth.min...DocumentLimits.wedgeDepth.max, step: 1.0, unit: "mm")),
                CommandInput(id: "height", label: "Height (Z)", value: .number(30.0, range: DocumentLimits.wedgeHeight.min...DocumentLimits.wedgeHeight.max, step: 1.0, unit: "mm")),
                CommandInput(id: "topWidth", label: "Top Width (X)", value: .number(0.0, range: DocumentLimits.wedgeTopWidth.min...DocumentLimits.wedgeTopWidth.max, step: 1.0, unit: "mm"))
            ],
            isPreviewEnabled: true
        )

        session.customValidation = { [weak session] in
            guard let session else { return false }
            let w = session.numberValue(for: "width") ?? 30.0
            let tw = session.numberValue(for: "topWidth") ?? 0.0
            return tw <= w
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            if session.isPreviewEnabled {
                let w = session.numberValue(for: "width") ?? 30.0
                let d = session.numberValue(for: "depth") ?? 30.0
                let h = session.numberValue(for: "height") ?? 30.0
                let tw = session.numberValue(for: "topWidth") ?? 0.0
                guard w >= DocumentLimits.wedgeWidth.min && w <= DocumentLimits.wedgeWidth.max,
                      d >= DocumentLimits.wedgeDepth.min && d <= DocumentLimits.wedgeDepth.max,
                      h >= DocumentLimits.wedgeHeight.min && h <= DocumentLimits.wedgeHeight.max,
                      tw >= DocumentLimits.wedgeTopWidth.min && tw <= DocumentLimits.wedgeTopWidth.max,
                      tw <= w else {
                    _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                    workspace.invalidateViewport(.interaction)
                    return
                }
                let payload = NativeGeometryGenerator.generateWedge(width: w, depth: d, height: h, topWidth: tw)
                let previewColor = SIMD4<Float>(0.2, 0.6, 1.0, 0.75)
                _ = workspace.viewportManager.renderer?.installMesh(
                    payload,
                    for: Self.previewSolidId,
                    transform: .identity,
                    color: previewColor,
                    isHidden: false
                )
                workspace.invalidateViewport(.interaction)
            } else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
            }
        }

        session.onPreviewUpdate = updatePreview

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            let w = session.numberValue(for: "width") ?? 30.0
            let d = session.numberValue(for: "depth") ?? 30.0
            let h = session.numberValue(for: "height") ?? 30.0
            let tw = session.numberValue(for: "topWidth") ?? 0.0
            workspace.addObject(.wedge(WedgeParams(width: w, depth: d, height: h, topWidth: tw)))
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    static func makeTransform(workspace: WorkspaceModel, targetId: ObjectId? = nil) -> CommandSession {
        let initialId = targetId ?? workspace.selectedId
        let initialName = initialId.flatMap { id in workspace.document.objects.first(where: { $0.id == id })?.name }
        let initialTransform = initialId.flatMap { id in workspace.document.objects.first(where: { $0.id == id })?.transform } ?? Transform.identity

        let session = CommandSession(
            title: "Transform Solid",
            selectionSlots: [
                CommandSelectionSlot(
                    id: "target",
                    label: "Target Solid",
                    isRequired: true,
                    selectedObjectId: initialId,
                    selectedObjectName: initialName,
                    isActive: initialId == nil
                )
            ],
            inputs: [
                CommandInput(id: "posX", label: "Position X", value: .number(initialTransform.position.x, range: DocumentLimits.position.min...DocumentLimits.position.max, step: 1.0, unit: "mm")),
                CommandInput(id: "posY", label: "Position Y", value: .number(initialTransform.position.y, range: DocumentLimits.position.min...DocumentLimits.position.max, step: 1.0, unit: "mm")),
                CommandInput(id: "posZ", label: "Position Z", value: .number(initialTransform.position.z, range: DocumentLimits.position.min...DocumentLimits.position.max, step: 1.0, unit: "mm"))
            ],
            isPreviewEnabled: true
        )

        var originalTransform = initialTransform

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard let slot = session.selectionSlots.first(where: { $0.id == "target" }),
                  let solidId = slot.selectedObjectId else { return }

            if let currentObj = workspace.document.objects.first(where: { $0.id == solidId }) {
                if slot.selectedObjectId != initialId && originalTransform == initialTransform {
                    originalTransform = currentObj.transform
                }
            }

            let px = session.numberValue(for: "posX") ?? originalTransform.position.x
            let py = session.numberValue(for: "posY") ?? originalTransform.position.y
            let pz = session.numberValue(for: "posZ") ?? originalTransform.position.z

            var candidateTransform = originalTransform
            candidateTransform.position = SIMD3<Float>(px, py, pz)

            if session.isPreviewEnabled {
                _ = workspace.viewportManager.renderer?.updateTransform(candidateTransform, for: solidId)
            } else {
                _ = workspace.viewportManager.renderer?.updateTransform(originalTransform, for: solidId)
            }
            workspace.invalidateViewport(.interaction)
        }

        session.onPreviewUpdate = updatePreview

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard let slot = session.selectionSlots.first(where: { $0.id == "target" }),
                  let solidId = slot.selectedObjectId else { return }

            let px = session.numberValue(for: "posX") ?? originalTransform.position.x
            let py = session.numberValue(for: "posY") ?? originalTransform.position.y
            let pz = session.numberValue(for: "posZ") ?? originalTransform.position.z

            var finalTransform = originalTransform
            finalTransform.position = SIMD3<Float>(px, py, pz)
            workspace.setTransform(solidId, finalTransform)
        }

        session.onCancel = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard let slot = session.selectionSlots.first(where: { $0.id == "target" }),
                  let solidId = slot.selectedObjectId else { return }
            _ = workspace.viewportManager.renderer?.updateTransform(originalTransform, for: solidId)
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    static func makeBoolean(workspace: WorkspaceModel, selectedId: ObjectId? = nil) -> CommandSession {
        let initialA = selectedId ?? workspace.selectedId
        let initialAName = initialA.flatMap { id in workspace.document.objects.first(where: { $0.id == id })?.name }

        let session = CommandSession(
            title: "Boolean Operation",
            selectionSlots: [
                CommandSelectionSlot(
                    id: "solidA",
                    label: "Target Solid (A)",
                    isRequired: true,
                    selectedObjectId: initialA,
                    selectedObjectName: initialAName,
                    isActive: initialA == nil
                ),
                CommandSelectionSlot(
                    id: "solidB",
                    label: "Tool Solid (B)",
                    isRequired: true,
                    selectedObjectId: nil,
                    selectedObjectName: nil,
                    isActive: initialA != nil
                )
            ],
            inputs: [
                CommandInput(
                    id: "operation",
                    label: "Operation",
                    value: .choice("Subtract", options: ["Subtract", "Union", "Intersect"])
                ),
                CommandInput(
                    id: "keepTool",
                    label: "Keep Tool",
                    value: .toggle(false)
                )
            ],
            isPreviewEnabled: true
        )

        session.customValidation = { [weak workspace, weak session] in
            guard let workspace, let session else { return false }
            guard let a = session.selectionSlots.first(where: { $0.id == "solidA" })?.selectedObjectId,
                  let b = session.selectionSlots.first(where: { $0.id == "solidB" })?.selectedObjectId else { return false }
            guard a != b else { return false }
            return workspace.document.objects.contains(where: { $0.id == a }) &&
                   workspace.document.objects.contains(where: { $0.id == b })
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard session.isPreviewEnabled,
                  let a = session.selectionSlots.first(where: { $0.id == "solidA" })?.selectedObjectId,
                  let b = session.selectionSlots.first(where: { $0.id == "solidB" })?.selectedObjectId,
                  a != b else {
                if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                    workspace.invalidateViewport(.interaction)
                }
                return
            }

            let opStr = session.choiceValue(for: "operation") ?? "Subtract"
            let op: BooleanOp = switch opStr.lowercased() {
            case "union": .union
            case "intersect": .intersect
            default: .subtract
            }

            Task { @MainActor in
                let req = KernelRequest.booleanOperation(
                    jobId: JobId("preview-\(UUID().uuidString)"),
                    solidId: Self.previewSolidId,
                    op: op,
                    solidA: a,
                    solidB: b
                )
                let result = await workspace.kernelClient.request(req)
                if case .success(_, let payload) = result, !payload.isEmpty {
                    let previewColor = SIMD4<Float>(0.2, 0.6, 1.0, 0.75)
                    _ = workspace.viewportManager.renderer?.installMesh(
                        payload,
                        for: Self.previewSolidId,
                        transform: .identity,
                        color: previewColor,
                        isHidden: false
                    )
                    workspace.invalidateViewport(.interaction)
                } else {
                    if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                        workspace.invalidateViewport(.interaction)
                    }
                }
            }
        }

        session.onPreviewUpdate = updatePreview
        session.onParamChanged = { _, _ in
            updatePreview()
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            guard let a = session.selectionSlots.first(where: { $0.id == "solidA" })?.selectedObjectId,
                  let b = session.selectionSlots.first(where: { $0.id == "solidB" })?.selectedObjectId else { return }

            let opStr = session.choiceValue(for: "operation") ?? "Subtract"
            let op: BooleanOp = switch opStr.lowercased() {
            case "union": .union
            case "intersect": .intersect
            default: .subtract
            }

            let keepTool = session.toggleValue(for: "keepTool") ?? false
            workspace.setVisibility(a, isVisible: false)
            workspace.setVisibility(b, isVisible: keepTool)

            do {
                let feature = try workspace.document.combineBodies(
                    targetBodyId: a,
                    toolBodyId: b,
                    operation: op,
                    keepTool: keepTool
                )
                if let newId = feature.outputSolidId {
                    workspace.selectedId = newId
                    workspace.recomputeSolid(id: newId)
                }
            } catch {
                let def = ObjectDef.boolean(op: op, solidA: a, solidB: b)
                let newId = workspace.document.reserveId(for: def)
                workspace.document.addObject(newId, def: def)
                workspace.selectedId = newId
                workspace.recomputeSolid(id: newId)
            }
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                workspace.invalidateViewport(.interaction)
            }
        }

        return session
    }

    static func makePushPull(workspace: WorkspaceModel, solidId: SolidId, faceId: Int) -> CommandSession {
        let inputs: [CommandInput] = [
            CommandInput(
                id: "distance",
                label: "Distance (Z)",
                value: .number(20.0, range: DocumentLimits.extrudeDistance.min...DocumentLimits.extrudeDistance.max, step: 1.0, unit: "mm")
            )
        ]
        return CommandSession(
            title: "Push-Pull",
            selectionSlots: [],
            inputs: inputs,
            onCommit: {
            },
            onCancel: {
            }
        )
    }

    static func makeExtrude(workspace: WorkspaceModel, sketchFeatureId: UUID? = nil) -> CommandSession {
        let sketches = workspace.document.activeFeatures.filter {
            if case .sketch = $0.operation { return true }
            return false
        }
        let initialSketchId = sketchFeatureId ?? sketches.first?.id
        let sketchOptions = sketches.map { $0.name }
        let initialChoice = sketches.first(where: { $0.id == initialSketchId })?.name ?? (sketchOptions.first ?? "None")

        var inputs: [CommandInput] = [
            CommandInput(
                id: "distance",
                label: "Distance (Z)",
                value: .number(20.0, range: DocumentLimits.extrudeDistance.min...DocumentLimits.extrudeDistance.max, step: 1.0, unit: "mm")
            ),
            CommandInput(
                id: "symmetric",
                label: "Symmetric",
                value: .toggle(false)
            )
        ]
        if !sketchOptions.isEmpty {
            inputs.insert(CommandInput(id: "sketch", label: "Sketch", value: .choice(initialChoice, options: sketchOptions)), at: 0)
        }

        var initialRegions: [SketchRegion] = []
        if let initialSketchId,
           let feat = workspace.document.feature(for: initialSketchId),
           case .sketch(let data) = feat.operation {
            let plane = workspace.document.resolveSketchPlane(for: data)
            initialRegions = (try? SketchProfileBuilder.detectRegions(from: data.entities, plane: plane)) ?? []
        }
        if initialRegions.count > 1 {
            let regionOptions = initialRegions.indices.map { "Region \($0 + 1)" }
            var initialRegionChoice = regionOptions.first ?? "Region 1"
            if let selRegId = workspace.selectedSketchRegionId,
               let idx = initialRegions.firstIndex(where: { $0.id == selRegId }) {
                initialRegionChoice = regionOptions[idx]
            }
            inputs.append(CommandInput(id: "region", label: "Region", value: .choice(initialRegionChoice, options: regionOptions)))
        }

        let session = CommandSession(
            title: "Extrude",
            inputs: inputs,
            isPreviewEnabled: true
        )

        session.customValidation = { [weak workspace, weak session] in
            guard let workspace, let session else { return false }
            let sketchName = session.choiceValue(for: "sketch")
            let targetSketch = workspace.document.activeFeatures.first {
                if case .sketch = $0.operation {
                    if let sketchName { return $0.name == sketchName }
                    return true
                }
                return false
            }
            guard let targetSketch, case .sketch(let sketchData) = targetSketch.operation else { return false }
            guard !sketchData.entities.isEmpty else { return false }
            let plane = workspace.document.resolveSketchPlane(for: sketchData)
            if let regions = try? SketchProfileBuilder.detectRegions(from: sketchData.entities, plane: plane), !regions.isEmpty {
                return true
            }
            do {
                _ = try SketchProfileBuilder.build(from: sketchData.entities, plane: plane)
                return true
            } catch {
                return false
            }
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard session.isPreviewEnabled else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let sketchName = session.choiceValue(for: "sketch")
            let targetSketch = workspace.document.activeFeatures.first {
                if case .sketch = $0.operation {
                    if let sketchName { return $0.name == sketchName }
                    return true
                }
                return false
            }
            guard let targetSketch, case .sketch(let sketchData) = targetSketch.operation else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let dist = session.numberValue(for: "distance") ?? 20.0
            let isSym = session.toggleValue(for: "symmetric") ?? false
            guard dist >= DocumentLimits.extrudeDistance.min && dist <= DocumentLimits.extrudeDistance.max else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let plane = workspace.document.resolveSketchPlane(for: sketchData)
            let regions = (try? SketchProfileBuilder.detectRegions(from: sketchData.entities, plane: plane)) ?? []
            let profile: SketchProfile?
            if let regionChoice = session.choiceValue(for: "region"),
               let num = Int(regionChoice.replacingOccurrences(of: "Region ", with: "")),
               num >= 1, num <= regions.count {
                profile = regions[num - 1].toProfile(plane: plane)
            } else if let selectedRegionId = workspace.selectedSketchRegionId,
                      let matched = regions.first(where: { $0.id == selectedRegionId }) {
                profile = matched.toProfile(plane: plane)
            } else if let primary = regions.first {
                profile = primary.toProfile(plane: plane)
            } else {
                profile = try? SketchProfileBuilder.build(from: sketchData.entities, plane: plane)
            }

            if let profile {
                Task { @MainActor in
                    let req = KernelRequest.evaluateShape(
                        jobId: JobId("preview-\(UUID().uuidString)"),
                        solidId: Self.previewSolidId,
                        shape: .extrude(profile: profile, distance: dist, centered: isSym)
                    )
                    let result = await workspace.kernelClient.request(req)
                    if case .success(_, let payload) = result, !payload.isEmpty {
                        let previewColor = SIMD4<Float>(0.6, 0.3, 0.9, 0.75)
                        _ = workspace.viewportManager.renderer?.installMesh(
                            payload,
                            for: Self.previewSolidId,
                            transform: .identity,
                            color: previewColor,
                            isHidden: false
                        )
                        workspace.invalidateViewport(.interaction)
                    }
                }
            } else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
            }
        }

        session.onPreviewUpdate = updatePreview

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)

            let sketchName = session.choiceValue(for: "sketch")
            let targetSketch = workspace.document.activeFeatures.first {
                if case .sketch = $0.operation {
                    if let sketchName { return $0.name == sketchName }
                    return true
                }
                return false
            }
            guard let targetSketch, case .sketch(let sketchData) = targetSketch.operation else { return }
            let dist = session.numberValue(for: "distance") ?? 20.0
            let isSym = session.toggleValue(for: "symmetric") ?? false

            let plane = workspace.document.resolveSketchPlane(for: sketchData)
            let regions = (try? SketchProfileBuilder.detectRegions(from: sketchData.entities, plane: plane)) ?? []
            var chosenRegionId: UUID? = nil
            if let regionChoice = session.choiceValue(for: "region"),
               let num = Int(regionChoice.replacingOccurrences(of: "Region ", with: "")),
               num >= 1, num <= regions.count {
                chosenRegionId = regions[num - 1].id
            } else if let selectedRegionId = workspace.selectedSketchRegionId,
                      regions.contains(where: { $0.id == selectedRegionId }) {
                chosenRegionId = selectedRegionId
            }

            Task { @MainActor in
                _ = await workspace.extrudeSketch(
                    sketchFeatureId: targetSketch.id,
                    distance: Double(dist),
                    isSymmetric: isSym,
                    regionId: chosenRegionId
                )
            }
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    static func makeRevolve(workspace: WorkspaceModel, sketchFeatureId: UUID? = nil) -> CommandSession {
        let sketches = workspace.document.activeFeatures.filter {
            if case .sketch = $0.operation { return true }
            return false
        }
        let initialSketchId = sketchFeatureId ?? sketches.first?.id
        let sketchOptions = sketches.map { $0.name }
        let initialChoice = sketches.first(where: { $0.id == initialSketchId })?.name ?? (sketchOptions.first ?? "None")

        var axisOptions: [String] = []
        if let initialSketchId,
           let feat = workspace.document.feature(for: initialSketchId),
           case .sketch(let data) = feat.operation {
            let lineEntities = data.entities.filter { $0.kind == "line" && !$0.isConstruction }
            for (idx, _) in lineEntities.enumerated() {
                axisOptions.append("Sketch Line \(idx + 1)")
            }
        }
        let datumAxes = workspace.document.activeFeatures.filter {
            if case .datumAxis = $0.operation { return true }
            return false
        }
        for axisFeat in datumAxes {
            axisOptions.append(axisFeat.name)
        }
        if axisOptions.isEmpty {
            axisOptions.append("None")
        }
        let initialAxisChoice = axisOptions.first ?? "None"

        var inputs: [CommandInput] = [
            CommandInput(
                id: "mode",
                label: "Mode",
                value: .choice("Full", options: ["Full", "Angle", "Symmetric", "Two-Direction"])
            ),
            CommandInput(
                id: "angle",
                label: "Angle",
                value: .number(360.0, range: 0.1...360.0, step: 5.0, unit: "°")
            ),
            CommandInput(
                id: "angle2",
                label: "Angle 2",
                value: .number(0.0, range: 0.0...360.0, step: 5.0, unit: "°")
            ),
            CommandInput(
                id: "axis",
                label: "Axis",
                value: .choice(initialAxisChoice, options: axisOptions)
            )
        ]
        if !sketchOptions.isEmpty {
            inputs.insert(CommandInput(id: "sketch", label: "Sketch", value: .choice(initialChoice, options: sketchOptions)), at: 0)
        }

        var initialRegions: [SketchRegion] = []
        if let initialSketchId,
           let feat = workspace.document.feature(for: initialSketchId),
           case .sketch(let data) = feat.operation {
            let plane = workspace.document.resolveSketchPlane(for: data)
            initialRegions = (try? SketchProfileBuilder.detectRegions(from: data.entities, plane: plane)) ?? []
        }
        if initialRegions.count > 1 {
            let regionOptions = initialRegions.indices.map { "Region \($0 + 1)" }
            var initialRegionChoice = regionOptions.first ?? "Region 1"
            if let selRegId = workspace.selectedSketchRegionId,
               let idx = initialRegions.firstIndex(where: { $0.id == selRegId }) {
                initialRegionChoice = regionOptions[idx]
            }
            inputs.insert(CommandInput(id: "region", label: "Region", value: .choice(initialRegionChoice, options: regionOptions)), at: 1)
        }

        let axisSlot = CommandSelectionSlot(
            id: "axis",
            label: "Revolve Axis",
            isRequired: false,
            selectedObjectId: nil,
            selectedObjectName: nil,
            selectedSubElement: nil,
            isActive: true
        )

        let session = CommandSession(
            title: "Revolve",
            selectionSlots: [axisSlot],
            inputs: inputs,
            isPreviewEnabled: true,
            inputVisibilityPredicate: { session, input in
                let mode = session.choiceValue(for: "mode") ?? "Full"
                switch input.id {
                case "angle":
                    return mode != "Full"
                case "angle2":
                    return mode == "Two-Direction"
                default:
                    return true
                }
            }
        )

        func parseMode(_ str: String?) -> RevolveMode {
            switch str?.lowercased() {
            case "angle": return .angle
            case "symmetric": return .symmetric
            case "two-direction", "twodirection": return .twoDirection
            default: return .full
            }
        }

        func resolveAxisRef(session: CommandSession, targetSketch: Feature, sketchData: SketchFeatureData) -> Reference? {
            if let slot = session.selectionSlots.first(where: { $0.id == "axis" }) {
                if let subEl = slot.selectedSubElement, subEl.elementType == .edge {
                    if let feat = workspace.document.feature(for: subEl.solidId) {
                        let topRef: TopologicalReference
                        if let detId = subEl.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                            topRef = existing
                        } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "edge:\(subEl.elementId)" }) {
                            topRef = named
                        } else {
                            topRef = TopologicalReference(
                                sourceFeatureId: feat.id,
                                elementType: .edge,
                                historyPath: [HistoryStep(kind: .generated, label: "edge:\(subEl.elementId)")]
                            )
                        }
                        return .edge(topRef)
                    }
                }
                if let objId = slot.selectedObjectId,
                   let feat = workspace.document.feature(for: objId),
                   case .datumAxis = feat.operation {
                    return .feature(feat.id)
                }
            }

            let axisChoice = session.choiceValue(for: "axis")
            if let axisChoice {
                if let datumAxis = workspace.document.activeFeatures.first(where: {
                    if case .datumAxis = $0.operation { return $0.name == axisChoice }
                    return false
                }) {
                    return .feature(datumAxis.id)
                }

                let lineEntities = sketchData.entities.filter { $0.kind == "line" && !$0.isConstruction }
                for (idx, line) in lineEntities.enumerated() {
                    if axisChoice == "Sketch Line \(idx + 1)" || axisChoice == "Line \(idx + 1)" {
                        return .sketchEntity(featureId: targetSketch.id, entityId: line.id)
                    }
                }
            }

            let lineEntities = sketchData.entities.filter { $0.kind == "line" && !$0.isConstruction }
            if let firstLine = lineEntities.first {
                return .sketchEntity(featureId: targetSketch.id, entityId: firstLine.id)
            }

            return nil
        }

        session.customValidation = { [weak workspace, weak session] in
            guard let workspace, let session else { return false }
            let sketchName = session.choiceValue(for: "sketch")
            let targetSketch = workspace.document.activeFeatures.first {
                if case .sketch = $0.operation {
                    if let sketchName { return $0.name == sketchName }
                    return true
                }
                return false
            }
            guard let targetSketch, case .sketch(let sketchData) = targetSketch.operation else { return false }
            guard !sketchData.entities.isEmpty else { return false }

            let plane = workspace.document.resolveSketchPlane(for: sketchData)
            let profile: SketchProfile
            let regions = (try? SketchProfileBuilder.detectRegions(from: sketchData.entities, plane: plane)) ?? []
            if let regionChoice = session.choiceValue(for: "region"),
               let num = Int(regionChoice.replacingOccurrences(of: "Region ", with: "")),
               num >= 1, num <= regions.count {
                profile = regions[num - 1].toProfile(plane: plane)
            } else if let selectedRegionId = workspace.selectedSketchRegionId,
                      let matched = regions.first(where: { $0.id == selectedRegionId }) {
                profile = matched.toProfile(plane: plane)
            } else if let primary = regions.first {
                profile = primary.toProfile(plane: plane)
            } else {
                do {
                    profile = try SketchProfileBuilder.build(from: sketchData.entities, plane: plane)
                } catch {
                    return false
                }
            }
            guard profile.points.count >= 3 else { return false }

            guard let axisRef = resolveAxisRef(session: session, targetSketch: targetSketch, sketchData: sketchData) else {
                return false
            }
            guard case .success(let axisGeom) = workspace.document.resolveAxis(from: axisRef) else {
                return false
            }

            if DocumentModel.validateRevolveAxis(profile: profile, axisOrigin: axisGeom.origin, axisDirection: axisGeom.direction) != nil {
                return false
            }

            let mode = parseMode(session.choiceValue(for: "mode"))
            let angle = session.numberValue(for: "angle") ?? 360.0
            guard angle > 0 && angle <= 360.0 else { return false }

            if mode == .twoDirection {
                let angle2 = session.numberValue(for: "angle2") ?? 0.0
                guard angle2 > 0 && angle2 <= 360.0 else { return false }
            }

            return true
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard session.isPreviewEnabled else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let sketchName = session.choiceValue(for: "sketch")
            let targetSketch = workspace.document.activeFeatures.first {
                if case .sketch = $0.operation {
                    if let sketchName { return $0.name == sketchName }
                    return true
                }
                return false
            }
            guard let targetSketch, case .sketch(let sketchData) = targetSketch.operation else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let plane = workspace.document.resolveSketchPlane(for: sketchData)
            let regions = (try? SketchProfileBuilder.detectRegions(from: sketchData.entities, plane: plane)) ?? []
            let profile: SketchProfile?
            if let regionChoice = session.choiceValue(for: "region"),
               let num = Int(regionChoice.replacingOccurrences(of: "Region ", with: "")),
               num >= 1, num <= regions.count {
                profile = regions[num - 1].toProfile(plane: plane)
            } else if let selectedRegionId = workspace.selectedSketchRegionId,
                      let matched = regions.first(where: { $0.id == selectedRegionId }) {
                profile = matched.toProfile(plane: plane)
            } else if let primary = regions.first {
                profile = primary.toProfile(plane: plane)
            } else {
                profile = try? SketchProfileBuilder.build(from: sketchData.entities, plane: plane)
            }

            guard let profile, profile.points.count >= 3 else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            guard let axisRef = resolveAxisRef(session: session, targetSketch: targetSketch, sketchData: sketchData),
                  case .success(let axisGeom) = workspace.document.resolveAxis(from: axisRef) else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            if DocumentModel.validateRevolveAxis(profile: profile, axisOrigin: axisGeom.origin, axisDirection: axisGeom.direction) != nil {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let mode = parseMode(session.choiceValue(for: "mode"))
            let angle = session.numberValue(for: "angle") ?? 360.0
            let angle2 = session.numberValue(for: "angle2") ?? 0.0

            let params = RevolveParams(
                profile: profile,
                mode: mode,
                angle: Double(angle),
                angle2: Double(angle2),
                axisOrigin: axisGeom.origin,
                axisDirection: axisGeom.direction,
                sketchFeatureId: targetSketch.id,
                axisReference: axisRef
            )

            Task { @MainActor in
                let req = KernelRequest.evaluateShape(
                    jobId: JobId("preview-\(UUID().uuidString)"),
                    solidId: Self.previewSolidId,
                    shape: .revolveSolid(params, slices: 64)
                )
                let result = await workspace.kernelClient.request(req)
                if case .success(_, let payload) = result, !payload.isEmpty {
                    let previewColor = SIMD4<Float>(0.6, 0.3, 0.9, 0.75)
                    _ = workspace.viewportManager.renderer?.installMesh(
                        payload,
                        for: Self.previewSolidId,
                        transform: .identity,
                        color: previewColor,
                        isHidden: false
                    )
                    workspace.invalidateViewport(.interaction)
                }
            }
        }

        session.onPreviewUpdate = updatePreview

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)

            let sketchName = session.choiceValue(for: "sketch")
            let targetSketch = workspace.document.activeFeatures.first {
                if case .sketch = $0.operation {
                    if let sketchName { return $0.name == sketchName }
                    return true
                }
                return false
            }
            guard let targetSketch, case .sketch(let sketchData) = targetSketch.operation else { return }

            let plane = workspace.document.resolveSketchPlane(for: sketchData)
            let regions = (try? SketchProfileBuilder.detectRegions(from: sketchData.entities, plane: plane)) ?? []
            var chosenRegionId: UUID? = nil
            if let regionChoice = session.choiceValue(for: "region"),
               let num = Int(regionChoice.replacingOccurrences(of: "Region ", with: "")),
               num >= 1, num <= regions.count {
                chosenRegionId = regions[num - 1].id
            } else if let selectedRegionId = workspace.selectedSketchRegionId,
                      regions.contains(where: { $0.id == selectedRegionId }) {
                chosenRegionId = selectedRegionId
            }

            guard let axisRef = resolveAxisRef(session: session, targetSketch: targetSketch, sketchData: sketchData) else {
                return
            }

            let mode = parseMode(session.choiceValue(for: "mode"))
            let angle = session.numberValue(for: "angle") ?? 360.0
            let angle2 = session.numberValue(for: "angle2") ?? 0.0

            Task { @MainActor in
                _ = await workspace.revolveSketch(
                    sketchFeatureId: targetSketch.id,
                    regionId: chosenRegionId,
                    mode: mode,
                    angle: Double(angle),
                    angle2: Double(angle2),
                    axisReference: axisRef
                )
            }
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    static func makeChamfer(
        workspace: WorkspaceModel,
        targetSolidId: SolidId? = nil,
        edgeReferences: [TopologicalReference] = []
    ) -> CommandSession {
        let initialSub = workspace.document.selectedSubElement
        let hasInitialEdge = initialSub?.elementType == .edge
        let slotName: String?
        if let initialSub, hasInitialEdge {
            let baseName = workspace.document.objects.first(where: { $0.id == initialSub.solidId })?.name ?? initialSub.solidId.rawValue
            slotName = "Edge \(initialSub.elementId) (\(baseName))"
        } else if !edgeReferences.isEmpty {
            slotName = "\(edgeReferences.count) edge\(edgeReferences.count == 1 ? "" : "s")"
        } else {
            slotName = nil
        }

        let edgeSlot = CommandSelectionSlot(
            id: "edges",
            label: "Edges",
            isRequired: edgeReferences.isEmpty && !hasInitialEdge,
            selectedObjectId: targetSolidId,
            selectedObjectName: slotName,
            selectedSubElement: hasInitialEdge ? initialSub : nil,
            isActive: !hasInitialEdge && edgeReferences.isEmpty
        )

        let inputs: [CommandInput] = [
            CommandInput(
                id: "mode",
                label: "Mode",
                value: .choice("Equal Distance", options: ["Equal Distance", "Two Distances", "Distance-Angle"])
            ),
            CommandInput(
                id: "distance",
                label: "Distance",
                value: .number(1.0, range: DocumentLimits.chamferDistance.min...DocumentLimits.chamferDistance.max, step: 0.5, unit: "mm")
            ),
            CommandInput(
                id: "distance2",
                label: "Distance 2",
                value: .number(1.0, range: DocumentLimits.chamferDistance.min...DocumentLimits.chamferDistance.max, step: 0.5, unit: "mm")
            ),
            CommandInput(
                id: "angle",
                label: "Angle",
                value: .number(45.0, range: DocumentLimits.chamferAngle.min...DocumentLimits.chamferAngle.max, step: 1.0, unit: "deg")
            )
        ]

        let session = CommandSession(
            title: "Chamfer",
            selectionSlots: [edgeSlot],
            inputs: inputs,
            isPreviewEnabled: true,
            inputVisibilityPredicate: { session, input in
                let mode = session.choiceValue(for: "mode") ?? "Equal Distance"
                switch input.id {
                case "distance2":
                    return mode == "Two Distances"
                case "angle":
                    return mode == "Distance-Angle"
                default:
                    return true
                }
            }
        )

        func resolveEdges(session: CommandSession) -> [TopologicalReference] {
            if let slot = session.selectionSlots.first(where: { $0.id == "edges" }),
               let subEl = slot.selectedSubElement, subEl.elementType == .edge {
                if let feat = workspace.document.feature(for: subEl.solidId) {
                    let topRef: TopologicalReference
                    if let detId = subEl.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                        topRef = existing
                    } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "edge:\(subEl.elementId)" }) {
                        topRef = named
                    } else {
                        topRef = TopologicalReference(
                            sourceFeatureId: feat.id,
                            elementType: .edge,
                            historyPath: [HistoryStep(kind: .generated, label: "edge:\(subEl.elementId)")]
                        )
                    }
                    return [topRef]
                }
            }
            return edgeReferences
        }

        func resolveTargetId(session: CommandSession) -> SolidId? {
            if let slot = session.selectionSlots.first(where: { $0.id == "edges" }) {
                if let subEl = slot.selectedSubElement {
                    return subEl.solidId
                }
                if let objId = slot.selectedObjectId {
                    return objId
                }
            }
            return targetSolidId ?? workspace.selectedId ?? workspace.document.objects.first?.id
        }

        session.customValidation = { [weak session] in
            guard let session else { return false }
            let d1 = session.numberValue(for: "distance") ?? 1.0
            guard d1 > 0 else { return false }
            let modeStr = session.choiceValue(for: "mode") ?? "Equal Distance"
            if modeStr == "Two Distances" {
                let d2 = session.numberValue(for: "distance2") ?? 1.0
                guard d2 > 0 else { return false }
            } else if modeStr == "Distance-Angle" {
                let ang = session.numberValue(for: "angle") ?? 45.0
                guard ang > 0 && ang < 90 else { return false }
            }
            let refs = resolveEdges(session: session)
            return !refs.isEmpty
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard session.isPreviewEnabled else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let modeStr = session.choiceValue(for: "mode") ?? "Equal Distance"
            let mode: ChamferMode
            switch modeStr {
            case "Two Distances": mode = .twoDistances
            case "Distance-Angle": mode = .distanceAngle
            default: mode = .equalDistance
            }

            let dist = session.numberValue(for: "distance") ?? 1.0
            let dist2 = session.numberValue(for: "distance2") ?? 1.0
            let angle = session.numberValue(for: "angle") ?? 45.0

            let refs = resolveEdges(session: session)
            guard !refs.isEmpty, let targetId = resolveTargetId(session: session) else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            Task { @MainActor in
                let req = KernelRequest.chamfer(
                    jobId: JobId("preview-\(UUID().uuidString)"),
                    solidId: Self.previewSolidId,
                    targetSolidId: targetId,
                    edgeReferences: refs,
                    mode: mode,
                    distance: Double(dist),
                    distance2: Double(dist2),
                    angle: Double(angle)
                )
                let result = await workspace.kernelClient.request(req)
                if case .success(_, let payload) = result, !payload.isEmpty {
                    let previewColor = SIMD4<Float>(0.9, 0.5, 0.2, 0.75)
                    _ = workspace.viewportManager.renderer?.installMesh(
                        payload,
                        for: Self.previewSolidId,
                        transform: .identity,
                        color: previewColor,
                        isHidden: false
                    )
                    workspace.invalidateViewport(.interaction)
                } else {
                    if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                        workspace.invalidateViewport(.interaction)
                    }
                }
            }
        }

        session.onPreviewUpdate = updatePreview
        session.onParamChanged = { _, _ in
            updatePreview()
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)

            let refs = resolveEdges(session: session)
            guard !refs.isEmpty, let targetId = resolveTargetId(session: session) else { return }

            let modeStr = session.choiceValue(for: "mode") ?? "Equal Distance"
            let mode: ChamferMode
            switch modeStr {
            case "Two Distances": mode = .twoDistances
            case "Distance-Angle": mode = .distanceAngle
            default: mode = .equalDistance
            }

            let dist = session.numberValue(for: "distance") ?? 1.0
            let dist2 = session.numberValue(for: "distance2") ?? 1.0
            let angle = session.numberValue(for: "angle") ?? 45.0

            Task { @MainActor in
                _ = await workspace.chamferEdges(
                    targetSolidId: targetId,
                    edgeReferences: refs,
                    mode: mode,
                    distance: Double(dist),
                    distance2: Double(dist2),
                    angle: Double(angle)
                )
            }
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                workspace.invalidateViewport(.interaction)
            }
        }

        return session
    }

    public static func makeHole(
        workspace: WorkspaceModel,
        targetSolidId: SolidId? = nil,
        faceReference: TopologicalReference? = nil,
        sketchFeatureId: UUID? = nil
    ) -> CommandSession {
        let initialSub = workspace.document.selectedSubElement
        let hasInitialFace = initialSub?.elementType == .face
        let slotName: String?
        if let initialSub, hasInitialFace {
            let baseName = workspace.document.objects.first(where: { $0.id == initialSub.solidId })?.name ?? initialSub.solidId.rawValue
            slotName = "Face \(initialSub.elementId) (\(baseName))"
        } else if let faceReference {
            slotName = faceReference.historyPath.last?.label ?? "Face"
        } else {
            slotName = nil
        }

        let faceSlot = CommandSelectionSlot(
            id: "face",
            label: "Face",
            isRequired: faceReference == nil && !hasInitialFace,
            selectedObjectId: targetSolidId,
            selectedObjectName: slotName,
            selectedSubElement: hasInitialFace ? initialSub : nil,
            isActive: !hasInitialFace && faceReference == nil
        )

        let sketchSlot = CommandSelectionSlot(
            id: "sketch",
            label: "Sketch Points",
            isRequired: false,
            selectedObjectId: sketchFeatureId.map { ObjectId($0.uuidString) },
            selectedObjectName: sketchFeatureId != nil ? "Sketch" : nil,
            isActive: false
        )

        let isoSizes = HoleStandards.isoMetricSizes.map(\.designation)
        let uncSizes = HoleStandards.uncSizes.map(\.designation)
        let unfSizes = HoleStandards.unfSizes.map(\.designation)
        let allSizeOptions = ["M5"] + isoSizes.filter { $0 != "M5" } + uncSizes + unfSizes

        let inputs: [CommandInput] = [
            CommandInput(
                id: "type",
                label: "Type",
                value: .choice("Simple", options: ["Simple", "Counterbore", "Countersink", "Tapped"])
            ),
            CommandInput(
                id: "standard",
                label: "Standard",
                value: .choice("ISO Metric", options: ["ISO Metric", "UNC", "UNF", "Custom"])
            ),
            CommandInput(
                id: "size",
                label: "Size",
                value: .choice("M5", options: allSizeOptions)
            ),
            CommandInput(
                id: "termination",
                label: "Termination",
                value: .choice("Through All", options: ["Through All", "Blind"])
            ),
            CommandInput(
                id: "diameter",
                label: "Diameter",
                value: .number(5.0, range: DocumentLimits.holeDiameter.min...DocumentLimits.holeDiameter.max, step: 0.5, unit: "mm")
            ),
            CommandInput(
                id: "depth",
                label: "Depth",
                value: .number(10.0, range: DocumentLimits.holeDepth.min...DocumentLimits.holeDepth.max, step: 0.5, unit: "mm")
            ),
            CommandInput(
                id: "cbDiameter",
                label: "CB Diameter",
                value: .number(8.5, range: DocumentLimits.holeDiameter.min...DocumentLimits.holeDiameter.max, step: 0.5, unit: "mm")
            ),
            CommandInput(
                id: "cbDepth",
                label: "CB Depth",
                value: .number(5.0, range: DocumentLimits.holeDepth.min...DocumentLimits.holeDepth.max, step: 0.5, unit: "mm")
            ),
            CommandInput(
                id: "csDiameter",
                label: "CS Diameter",
                value: .number(10.4, range: DocumentLimits.holeDiameter.min...DocumentLimits.holeDiameter.max, step: 0.5, unit: "mm")
            ),
            CommandInput(
                id: "csAngle",
                label: "CS Angle",
                value: .number(90.0, range: DocumentLimits.countersinkAngle.min...DocumentLimits.countersinkAngle.max, step: 1.0, unit: "deg")
            ),
            CommandInput(
                id: "threadClass",
                label: "Thread Class",
                value: .choice("6H", options: ["6H", "4H", "2B", "3B"])
            )
        ]

        let session = CommandSession(
            title: "Hole",
            selectionSlots: [faceSlot, sketchSlot],
            inputs: inputs,
            isPreviewEnabled: true,
            inputVisibilityPredicate: { session, input in
                let type = session.choiceValue(for: "type") ?? "Simple"
                let standard = session.choiceValue(for: "standard") ?? "ISO Metric"
                let termination = session.choiceValue(for: "termination") ?? "Through All"
                switch input.id {
                case "size":
                    return standard != "Custom"
                case "depth":
                    return termination == "Blind"
                case "cbDiameter", "cbDepth":
                    return type == "Counterbore"
                case "csDiameter", "csAngle":
                    return type == "Countersink"
                case "threadClass":
                    return type == "Tapped"
                default:
                    return true
                }
            }
        )

        func resolveFaceRef(session: CommandSession) -> TopologicalReference? {
            if let slot = session.selectionSlots.first(where: { $0.id == "face" }),
               let subEl = slot.selectedSubElement, subEl.elementType == .face {
                if let feat = workspace.document.feature(for: subEl.solidId) {
                    if let detId = subEl.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                        return existing
                    } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "face:\(subEl.elementId)" }) {
                        return named
                    } else {
                        return TopologicalReference(
                            sourceFeatureId: feat.id,
                            elementType: .face,
                            historyPath: [HistoryStep(kind: .generated, label: "face:\(subEl.elementId)")]
                        )
                    }
                }
            }
            return faceReference
        }

        func resolveTargetId(session: CommandSession) -> SolidId? {
            if let slot = session.selectionSlots.first(where: { $0.id == "face" }) {
                if let subEl = slot.selectedSubElement {
                    return subEl.solidId
                }
                if let objId = slot.selectedObjectId {
                    return objId
                }
            }
            return targetSolidId ?? workspace.selectedId ?? workspace.document.objects.first?.id
        }

        func resolveSketchPoints(session: CommandSession) -> [SIMD2<Double>] {
            var points: [SIMD2<Double>] = []
            if let slot = session.selectionSlots.first(where: { $0.id == "sketch" }),
               let objId = slot.selectedObjectId,
               let feat = workspace.document.features.first(where: { $0.outputSolidId == objId || $0.id.uuidString == objId.rawValue }),
               case .sketch(let sketchData) = feat.operation {
                for entity in sketchData.entities where entity.kind == "point" {
                    if let pos = entity.pointPosition {
                        points.append(pos)
                    }
                }
            }
            return points
        }

        session.customValidation = { [weak session] in
            guard let session else { return false }
            guard resolveFaceRef(session: session) != nil else { return false }
            let dia = session.numberValue(for: "diameter") ?? 5.0
            guard dia > 0 else { return false }
            let term = session.choiceValue(for: "termination") ?? "Through All"
            if term == "Blind" {
                let dep = session.numberValue(for: "depth") ?? 10.0
                guard dep > 0 else { return false }
            }
            let typeStr = session.choiceValue(for: "type") ?? "Simple"
            if typeStr == "Counterbore" {
                let cbD = session.numberValue(for: "cbDiameter") ?? 8.5
                let cbH = session.numberValue(for: "cbDepth") ?? 5.0
                guard cbD > dia, cbH > 0 else { return false }
            } else if typeStr == "Countersink" {
                let csD = session.numberValue(for: "csDiameter") ?? 10.4
                let csA = session.numberValue(for: "csAngle") ?? 90.0
                guard csD > dia, csA > 0, csA < 180 else { return false }
            }
            let stdStr = session.choiceValue(for: "standard") ?? "ISO Metric"
            if stdStr != "Custom" {
                let sizeStr = session.choiceValue(for: "size") ?? "M5"
                let std: HoleStandard = stdStr == "UNC" ? .unc : (stdStr == "UNF" ? .unf : .isoMetric)
                guard HoleStandards.lookup(standard: std, designation: sizeStr) != nil else { return false }
            }
            return true
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard session.isPreviewEnabled else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            guard let faceRef = resolveFaceRef(session: session),
                  let targetId = resolveTargetId(session: session) else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let typeStr = session.choiceValue(for: "type") ?? "Simple"
            let holeType: HoleType
            switch typeStr {
            case "Counterbore": holeType = .counterbore
            case "Countersink": holeType = .countersink
            case "Tapped": holeType = .tapped
            default: holeType = .simple
            }

            let stdStr = session.choiceValue(for: "standard") ?? "ISO Metric"
            let standard: HoleStandard
            switch stdStr {
            case "UNC": standard = .unc
            case "UNF": standard = .unf
            case "Custom": standard = .custom
            default: standard = .isoMetric
            }

            let sizeDesignation = standard == .custom ? nil : (session.choiceValue(for: "size") ?? "M5")
            let isThrough = (session.choiceValue(for: "termination") ?? "Through All") == "Through All"
            let dia = Double(session.numberValue(for: "diameter") ?? 5.0)
            let dep = Double(session.numberValue(for: "depth") ?? 10.0)
            let cbD = Double(session.numberValue(for: "cbDiameter") ?? 8.5)
            let cbH = Double(session.numberValue(for: "cbDepth") ?? 5.0)
            let csD = Double(session.numberValue(for: "csDiameter") ?? 10.4)
            let csA = Double(session.numberValue(for: "csAngle") ?? 90.0)
            let threadClass = session.choiceValue(for: "threadClass") ?? "6H"

            let threadMeta: ThreadMetadata?
            if holeType == .tapped {
                let pitch: Double
                if let sizeDesignation, let stdSize = HoleStandards.lookup(standard: standard, designation: sizeDesignation) {
                    pitch = stdSize.pitch
                } else {
                    pitch = 1.0
                }
                threadMeta = ThreadMetadata(
                    designation: sizeDesignation ?? "M\(dia)",
                    pitch: pitch,
                    threadDepth: dep,
                    threadClass: threadClass,
                    isRightHand: true
                )
            } else {
                threadMeta = nil
            }

            let points = resolveSketchPoints(session: session)
            let holeData = HoleFeatureData(
                targetSolidId: targetId,
                faceReference: faceRef,
                sketchFeatureId: sketchFeatureId,
                points: points,
                holeType: holeType,
                standard: standard,
                sizeDesignation: sizeDesignation,
                diameter: dia,
                depth: dep,
                isThrough: isThrough,
                counterboreDiameter: cbD,
                counterboreDepth: cbH,
                countersinkDiameter: csD,
                countersinkAngle: csA,
                drillTipAngle: nil,
                threadMetadata: threadMeta
            )

            Task { @MainActor in
                let req = KernelRequest.hole(
                    jobId: JobId("preview-\(UUID().uuidString)"),
                    solidId: Self.previewSolidId,
                    targetSolidId: targetId,
                    faceReference: faceRef,
                    holeData: holeData
                )
                let result = await workspace.kernelClient.request(req)
                if case .success(_, let payload) = result, !payload.isEmpty {
                    let previewColor = SIMD4<Float>(0.9, 0.5, 0.2, 0.75)
                    _ = workspace.viewportManager.renderer?.installMesh(
                        payload,
                        for: Self.previewSolidId,
                        transform: .identity,
                        color: previewColor,
                        isHidden: false
                    )
                    workspace.invalidateViewport(.interaction)
                } else {
                    if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                        workspace.invalidateViewport(.interaction)
                    }
                }
            }
        }

        session.onPreviewUpdate = updatePreview
        session.onParamChanged = { [weak session] inputId, _ in
            guard let session else { return }
            if inputId == "size" || inputId == "standard" {
                let stdStr = session.choiceValue(for: "standard") ?? "ISO Metric"
                let sizeStr = session.choiceValue(for: "size") ?? "M5"
                let std: HoleStandard = stdStr == "UNC" ? .unc : (stdStr == "UNF" ? .unf : (stdStr == "Custom" ? .custom : .isoMetric))
                if let size = HoleStandards.lookup(standard: std, designation: sizeStr) {
                    session.setNumberValue(Float(size.normalClearanceDiameter), for: "diameter")
                    session.setNumberValue(Float(size.counterboreDiameter), for: "cbDiameter")
                    session.setNumberValue(Float(size.counterboreDepth), for: "cbDepth")
                    session.setNumberValue(Float(size.countersinkDiameter), for: "csDiameter")
                    session.setNumberValue(Float(size.countersinkAngle), for: "csAngle")
                }
            }
            updatePreview()
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)

            guard let faceRef = resolveFaceRef(session: session),
                  let targetId = resolveTargetId(session: session) else { return }

            let typeStr = session.choiceValue(for: "type") ?? "Simple"
            let holeType: HoleType
            switch typeStr {
            case "Counterbore": holeType = .counterbore
            case "Countersink": holeType = .countersink
            case "Tapped": holeType = .tapped
            default: holeType = .simple
            }

            let stdStr = session.choiceValue(for: "standard") ?? "ISO Metric"
            let standard: HoleStandard
            switch stdStr {
            case "UNC": standard = .unc
            case "UNF": standard = .unf
            case "Custom": standard = .custom
            default: standard = .isoMetric
            }

            let sizeDesignation = standard == .custom ? nil : (session.choiceValue(for: "size") ?? "M5")
            let isThrough = (session.choiceValue(for: "termination") ?? "Through All") == "Through All"
            let dia = Double(session.numberValue(for: "diameter") ?? 5.0)
            let dep = Double(session.numberValue(for: "depth") ?? 10.0)
            let cbD = Double(session.numberValue(for: "cbDiameter") ?? 8.5)
            let cbH = Double(session.numberValue(for: "cbDepth") ?? 5.0)
            let csD = Double(session.numberValue(for: "csDiameter") ?? 10.4)
            let csA = Double(session.numberValue(for: "csAngle") ?? 90.0)
            let threadClass = session.choiceValue(for: "threadClass") ?? "6H"

            let threadMeta: ThreadMetadata?
            if holeType == .tapped {
                let pitch: Double
                if let sizeDesignation, let stdSize = HoleStandards.lookup(standard: standard, designation: sizeDesignation) {
                    pitch = stdSize.pitch
                } else {
                    pitch = 1.0
                }
                threadMeta = ThreadMetadata(
                    designation: sizeDesignation ?? "M\(dia)",
                    pitch: pitch,
                    threadDepth: dep,
                    threadClass: threadClass,
                    isRightHand: true
                )
            } else {
                threadMeta = nil
            }

            let points = resolveSketchPoints(session: session)

            Task { @MainActor in
                _ = await workspace.holeBody(
                    targetSolidId: targetId,
                    faceReference: faceRef,
                    sketchFeatureId: sketchFeatureId,
                    points: points,
                    holeType: holeType,
                    standard: standard,
                    sizeDesignation: sizeDesignation,
                    diameter: dia,
                    depth: dep,
                    isThrough: isThrough,
                    counterboreDiameter: cbD,
                    counterboreDepth: cbH,
                    countersinkDiameter: csD,
                    countersinkAngle: csA,
                    drillTipAngle: nil,
                    threadMetadata: threadMeta
                )
            }
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                workspace.invalidateViewport(.interaction)
            }
        }

        return session
    }

    public static func makeShell(
        workspace: WorkspaceModel,
        targetSolidId: SolidId? = nil,
        removedFaceReferences: [TopologicalReference] = [],
        initialThickness: Double = 1.0
    ) -> CommandSession {
        let initialSub = workspace.document.selectedSubElement
        let hasInitialFace = initialSub?.elementType == .face
        let slotName: String?
        if let initialSub, hasInitialFace {
            let baseName = workspace.document.objects.first(where: { $0.id == initialSub.solidId })?.name ?? initialSub.solidId.rawValue
            slotName = "Face \(initialSub.elementId) (\(baseName))"
        } else if !removedFaceReferences.isEmpty {
            slotName = "\(removedFaceReferences.count) face\(removedFaceReferences.count == 1 ? "" : "s")"
        } else {
            slotName = nil
        }

        let faceSlot = CommandSelectionSlot(
            id: "faces",
            label: "Open Faces",
            isRequired: false,
            selectedObjectId: targetSolidId,
            selectedObjectName: slotName,
            selectedSubElement: hasInitialFace ? initialSub : nil,
            isActive: false
        )

        let inputs: [CommandInput] = [
            CommandInput(
                id: "thickness",
                label: "Thickness",
                value: .number(
                    Float(initialThickness),
                    range: DocumentLimits.shellThickness.min...DocumentLimits.shellThickness.max,
                    step: 0.5,
                    unit: "mm"
                )
            )
        ]

        let session = CommandSession(
            title: "Shell",
            selectionSlots: [faceSlot],
            inputs: inputs,
            isPreviewEnabled: true
        )

        func resolveFaces(session: CommandSession) -> [TopologicalReference] {
            if let slot = session.selectionSlots.first(where: { $0.id == "faces" }),
               let subEl = slot.selectedSubElement, subEl.elementType == .face {
                if let feat = workspace.document.feature(for: subEl.solidId) {
                    let topRef: TopologicalReference
                    if let detId = subEl.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                        topRef = existing
                    } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "face:\(subEl.elementId)" }) {
                        topRef = named
                    } else {
                        topRef = TopologicalReference(
                            sourceFeatureId: feat.id,
                            elementType: .face,
                            historyPath: [HistoryStep(kind: .generated, label: "face:\(subEl.elementId)")]
                        )
                    }
                    return [topRef]
                }
            }
            return removedFaceReferences
        }

        func resolveTargetId(session: CommandSession) -> SolidId? {
            if let slot = session.selectionSlots.first(where: { $0.id == "faces" }) {
                if let subEl = slot.selectedSubElement {
                    return subEl.solidId
                }
                if let objId = slot.selectedObjectId {
                    return objId
                }
            }
            return targetSolidId
        }

        session.customValidation = { [weak session] in
            guard let session else { return false }
            let t = session.numberValue(for: "thickness") ?? 1.0
            guard t > 0 else { return false }
            guard resolveTargetId(session: session) != nil else { return false }
            return true
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard session.isPreviewEnabled else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let thick = session.numberValue(for: "thickness") ?? 1.0
            guard thick > 0 else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            guard let targetId = resolveTargetId(session: session) else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let refs = resolveFaces(session: session)

            Task { @MainActor in
                let req = KernelRequest.shell(
                    jobId: JobId("preview-\(UUID().uuidString)"),
                    solidId: Self.previewSolidId,
                    targetSolidId: targetId,
                    thickness: Double(thick),
                    removedFaceReferences: refs,
                    perFaceOverrides: []
                )
                let result = await workspace.kernelClient.request(req)
                if case .success(_, let payload) = result, !payload.isEmpty {
                    let previewColor = SIMD4<Float>(0.9, 0.5, 0.2, 0.75)
                    _ = workspace.viewportManager.renderer?.installMesh(
                        payload,
                        for: Self.previewSolidId,
                        transform: .identity,
                        color: previewColor,
                        isHidden: false
                    )
                    workspace.invalidateViewport(.interaction)
                } else {
                    if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                        workspace.invalidateViewport(.interaction)
                    }
                }
            }
        }

        session.onPreviewUpdate = updatePreview
        session.onParamChanged = { _, _ in
            updatePreview()
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)

            guard let targetId = resolveTargetId(session: session) else { return }
            let refs = resolveFaces(session: session)
            let thick = session.numberValue(for: "thickness") ?? 1.0

            Task { @MainActor in
                _ = await workspace.shellBody(
                    targetSolidId: targetId,
                    thickness: Double(thick),
                    removedFaceReferences: refs,
                    perFaceOverrides: []
                )
            }
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                workspace.invalidateViewport(.interaction)
            }
        }

        return session
    }

    static func makeNewSketch(workspace: WorkspaceModel) -> CommandSession {
        let defaultName = "Sketch \(workspace.document.activeFeatures.filter { if case .sketch = $0.operation { return true }; return false }.count + 1)"
        let session = CommandSession(
            title: "New Ground Sketch",
            inputs: [
                CommandInput(id: "name", label: "Name", value: .text(defaultName)),
                CommandInput(id: "preset", label: "Initial Shape", value: .choice("Rectangle", options: ["Rectangle", "Circle", "Empty"]))
            ],
            isPreviewEnabled: false
        )

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            let name = session.textValue(for: "name") ?? defaultName
            let preset = session.choiceValue(for: "preset") ?? "Rectangle"
            var entities: [SketchEntity] = []
            switch preset {
            case "Rectangle":
                entities = [
                    SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(30, 0)),
                    SketchEntity.line(start: SIMD2(30, 0), end: SIMD2(30, 20)),
                    SketchEntity.line(start: SIMD2(30, 20), end: SIMD2(0, 20)),
                    SketchEntity.line(start: SIMD2(0, 20), end: SIMD2(0, 0))
                ]
            case "Circle":
                entities = [
                    SketchEntity.circle(center: SIMD2(0, 0), radius: 15.0)
                ]
            default:
                break
            }

            let feature = Feature(
                name: name.isEmpty ? defaultName : name,
                operation: .sketch(SketchFeatureData(planeName: "XY", entities: entities))
            )
            _ = workspace.document.addFeature(feature)
            workspace.selectFeature(feature.id)
        }

        return session
    }

    static func makeDatumPlane(workspace: WorkspaceModel) -> CommandSession {
        let datumCount = workspace.document.activeFeatures.filter {
            if case .datumPlane = $0.operation { return true }
            return false
        }.count + 1
        let defaultName = "Plane \(datumCount)"

        let session = CommandSession(
            title: "New Datum Plane",
            inputs: [
                CommandInput(id: "name", label: "Name", value: .text(defaultName)),
                CommandInput(id: "mode", label: "Mode", value: .choice("Origin", options: [
                    "Origin", "Offset", "At Angle", "Three Points", "Normal to Curve", "Midplane", "Tangent"
                ])),
                CommandInput(id: "originPreset", label: "Preset", value: .choice("XY", options: ["XY", "XZ", "YZ"])),
                CommandInput(id: "offset", label: "Offset Distance", value: .number(0.0, range: -1000.0...1000.0, step: 1.0, unit: "mm")),
                CommandInput(id: "angle", label: "Angle", value: .number(0.0, range: -360.0...360.0, step: 5.0, unit: "°")),
                CommandInput(id: "curveParameter", label: "Curve Parameter t", value: .number(0.5, range: 0.0...1.0, step: 0.1, unit: "t")),
                CommandInput(id: "point1X", label: "Point 1 X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1Y", label: "Point 1 Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1Z", label: "Point 1 Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2X", label: "Point 2 X", value: .number(10.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2Y", label: "Point 2 Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2Z", label: "Point 2 Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point3X", label: "Point 3 X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point3Y", label: "Point 3 Y", value: .number(10.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point3Z", label: "Point 3 Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "flip", label: "Flip Normal", value: .toggle(false))
            ],
            isPreviewEnabled: false,
            inputVisibilityPredicate: { session, input in
                let mode = session.choiceValue(for: "mode") ?? "Origin"
                switch input.id {
                case "name", "mode", "flip":
                    return true
                case "originPreset":
                    return mode == "Origin" || mode == "Offset" || mode == "At Angle" || mode == "Tangent"
                case "offset":
                    return mode == "Offset"
                case "angle":
                    return mode == "At Angle"
                case "curveParameter":
                    return mode == "Normal to Curve"
                case "point1X", "point1Y", "point1Z", "point2X", "point2Y", "point2Z":
                    return mode == "Three Points" || mode == "Midplane"
                case "point3X", "point3Y", "point3Z":
                    return mode == "Three Points"
                default:
                    return true
                }
            }
        )

        session.customValidation = { [weak session] in
            guard let session else { return false }
            let modeChoice = session.choiceValue(for: "mode") ?? "Origin"
            if modeChoice == "Three Points" {
                let p1 = SIMD3<Float>(
                    session.numberValue(for: "point1X") ?? 0,
                    session.numberValue(for: "point1Y") ?? 0,
                    session.numberValue(for: "point1Z") ?? 0
                )
                let p2 = SIMD3<Float>(
                    session.numberValue(for: "point2X") ?? 0,
                    session.numberValue(for: "point2Y") ?? 0,
                    session.numberValue(for: "point2Z") ?? 0
                )
                let p3 = SIMD3<Float>(
                    session.numberValue(for: "point3X") ?? 0,
                    session.numberValue(for: "point3Y") ?? 0,
                    session.numberValue(for: "point3Z") ?? 0
                )
                let v1 = p2 - p1
                let v2 = p3 - p1
                let v3 = p3 - p2
                if simd_length(v1) < 1e-6 || simd_length(v2) < 1e-6 || simd_length(v3) < 1e-6 {
                    return false
                }
                if simd_length(simd_cross(v1, v2)) < 1e-6 {
                    return false
                }
            } else if modeChoice == "Midplane" {
                let p1 = SIMD3<Float>(
                    session.numberValue(for: "point1X") ?? 0,
                    session.numberValue(for: "point1Y") ?? 0,
                    session.numberValue(for: "point1Z") ?? 0
                )
                let p2 = SIMD3<Float>(
                    session.numberValue(for: "point2X") ?? 0,
                    session.numberValue(for: "point2Y") ?? 0,
                    session.numberValue(for: "point2Z") ?? 0
                )
                if simd_length(p2 - p1) < 1e-6 {
                    return false
                }
            }
            return true
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            let name = session.textValue(for: "name") ?? defaultName
            let modeStr = session.choiceValue(for: "mode") ?? "Origin"
            let mode: DatumPlaneMode
            switch modeStr {
            case "Offset": mode = .offset
            case "At Angle": mode = .atAngle
            case "Three Points": mode = .threePoints
            case "Normal to Curve": mode = .normalToCurve
            case "Midplane": mode = .midplane
            case "Tangent": mode = .tangent
            default: mode = .origin
            }

            let originPreset = session.choiceValue(for: "originPreset") ?? "XY"
            let offsetDistance = Double(session.numberValue(for: "offset") ?? 0.0)
            let angleDegrees = Double(session.numberValue(for: "angle") ?? 0.0)
            let curveParameter = Double(session.numberValue(for: "curveParameter") ?? 0.5)
            let isFlipped = session.toggleValue(for: "flip") ?? false

            let p1 = SIMD3<Float>(
                session.numberValue(for: "point1X") ?? 0,
                session.numberValue(for: "point1Y") ?? 0,
                session.numberValue(for: "point1Z") ?? 0
            )
            let p2 = SIMD3<Float>(
                session.numberValue(for: "point2X") ?? 0,
                session.numberValue(for: "point2Y") ?? 0,
                session.numberValue(for: "point2Z") ?? 0
            )
            let p3 = SIMD3<Float>(
                session.numberValue(for: "point3X") ?? 0,
                session.numberValue(for: "point3Y") ?? 0,
                session.numberValue(for: "point3Z") ?? 0
            )

            var references: [Reference] = []
            if let selectedFeat = workspace.selectedDatumPlaneFeature {
                references.append(.feature(selectedFeat.id))
            }

            let data = DatumPlaneFeatureData(
                mode: mode,
                originPreset: originPreset,
                offsetDistance: offsetDistance,
                angleDegrees: angleDegrees,
                curveParameter: curveParameter,
                point1: p1,
                point2: p2,
                point3: p3,
                isFlipped: isFlipped
            )

            let feature = workspace.document.addDatumPlaneFeature(
                name: name.isEmpty ? defaultName : name,
                data: data,
                references: references
            )
            workspace.selectFeature(feature.id)
        }

        return session
    }

    static func makeDatumAxis(workspace: WorkspaceModel) -> CommandSession {
        let datumCount = workspace.document.activeFeatures.filter {
            if case .datumAxis = $0.operation { return true }
            return false
        }.count + 1
        let defaultName = "Axis \(datumCount)"

        let session = CommandSession(
            title: "New Datum Axis",
            inputs: [
                CommandInput(id: "name", label: "Name", value: .text(defaultName)),
                CommandInput(id: "mode", label: "Mode", value: .choice("Preset", options: [
                    "Preset", "Two Points", "Edge", "Cylinder", "Normal to Plane"
                ])),
                CommandInput(id: "preset", label: "Preset Axis", value: .choice("Z", options: ["X", "Y", "Z"])),
                CommandInput(id: "point1X", label: "Point 1 X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1Y", label: "Point 1 Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1Z", label: "Point 1 Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2X", label: "Point 2 X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2Y", label: "Point 2 Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2Z", label: "Point 2 Z", value: .number(10.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "flip", label: "Flip Direction", value: .toggle(false))
            ],
            isPreviewEnabled: false,
            inputVisibilityPredicate: { session, input in
                let mode = session.choiceValue(for: "mode") ?? "Preset"
                switch input.id {
                case "name", "mode", "flip":
                    return true
                case "preset":
                    return mode == "Preset"
                case "point1X", "point1Y", "point1Z", "point2X", "point2Y", "point2Z":
                    return mode == "Two Points"
                default:
                    return true
                }
            }
        )

        session.customValidation = { [weak session] in
            guard let session else { return false }
            let modeChoice = session.choiceValue(for: "mode") ?? "Preset"
            if modeChoice == "Two Points" {
                let p1 = SIMD3<Float>(
                    session.numberValue(for: "point1X") ?? 0,
                    session.numberValue(for: "point1Y") ?? 0,
                    session.numberValue(for: "point1Z") ?? 0
                )
                let p2 = SIMD3<Float>(
                    session.numberValue(for: "point2X") ?? 0,
                    session.numberValue(for: "point2Y") ?? 0,
                    session.numberValue(for: "point2Z") ?? 0
                )
                if simd_length(p2 - p1) < 1e-6 {
                    return false
                }
            }
            return true
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            let name = session.textValue(for: "name") ?? defaultName
            let modeStr = session.choiceValue(for: "mode") ?? "Preset"
            let mode: DatumAxisMode
            switch modeStr {
            case "Two Points": mode = .twoPoints
            case "Edge": mode = .edge
            case "Cylinder": mode = .cylinder
            case "Normal to Plane": mode = .normalToPlane
            default: mode = .preset
            }

            let presetName = session.choiceValue(for: "preset") ?? "Z"
            let isFlipped = session.toggleValue(for: "flip") ?? false

            let p1 = SIMD3<Float>(
                session.numberValue(for: "point1X") ?? 0,
                session.numberValue(for: "point1Y") ?? 0,
                session.numberValue(for: "point1Z") ?? 0
            )
            let p2 = SIMD3<Float>(
                session.numberValue(for: "point2X") ?? 0,
                session.numberValue(for: "point2Y") ?? 0,
                session.numberValue(for: "point2Z") ?? 0
            )

            var references: [Reference] = []
            if let selectedAxis = workspace.selectedDatumAxisFeature {
                references.append(.feature(selectedAxis.id))
            } else if let selectedPlane = workspace.selectedDatumPlaneFeature {
                references.append(.feature(selectedPlane.id))
            }

            let data = DatumAxisFeatureData(
                mode: mode,
                presetName: presetName,
                point1: p1,
                point2: p2,
                isFlipped: isFlipped
            )

            let feature = workspace.document.addDatumAxisFeature(
                name: name.isEmpty ? defaultName : name,
                data: data,
                references: references
            )
            workspace.selectFeature(feature.id)
        }

        return session
    }

    static func makeDatumPoint(workspace: WorkspaceModel) -> CommandSession {
        let datumCount = workspace.document.activeFeatures.filter {
            if case .datumPoint = $0.operation { return true }
            return false
        }.count + 1
        let defaultName = "Point \(datumCount)"

        let session = CommandSession(
            title: "New Datum Point",
            inputs: [
                CommandInput(id: "name", label: "Name", value: .text(defaultName)),
                CommandInput(id: "mode", label: "Mode", value: .choice("Coordinates", options: [
                    "Coordinates", "On Vertex", "Arc Center", "Along Curve", "Midpoint", "Intersection"
                ])),
                CommandInput(id: "coordX", label: "Position X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "coordY", label: "Position Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "coordZ", label: "Position Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1X", label: "Point 1 X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1Y", label: "Point 1 Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1Z", label: "Point 1 Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2X", label: "Point 2 X", value: .number(10.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2Y", label: "Point 2 Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2Z", label: "Point 2 Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "curveParameter", label: "Curve Parameter t", value: .number(0.5, range: 0.0...1.0, step: 0.1, unit: "t"))
            ],
            isPreviewEnabled: false,
            inputVisibilityPredicate: { session, input in
                let mode = session.choiceValue(for: "mode") ?? "Coordinates"
                switch input.id {
                case "name", "mode":
                    return true
                case "coordX", "coordY", "coordZ":
                    return mode == "Coordinates"
                case "point1X", "point1Y", "point1Z", "point2X", "point2Y", "point2Z":
                    return mode == "Midpoint"
                case "curveParameter":
                    return mode == "Along Curve"
                default:
                    return true
                }
            }
        )

        session.customValidation = { [weak session] in
            guard let session else { return false }
            let modeChoice = session.choiceValue(for: "mode") ?? "Coordinates"
            if modeChoice == "Midpoint" {
                let p1 = SIMD3<Float>(
                    session.numberValue(for: "point1X") ?? 0,
                    session.numberValue(for: "point1Y") ?? 0,
                    session.numberValue(for: "point1Z") ?? 0
                )
                let p2 = SIMD3<Float>(
                    session.numberValue(for: "point2X") ?? 0,
                    session.numberValue(for: "point2Y") ?? 0,
                    session.numberValue(for: "point2Z") ?? 0
                )
                if simd_length(p2 - p1) < 1e-6 {
                    return false
                }
            }
            return true
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            let name = session.textValue(for: "name") ?? defaultName
            let modeStr = session.choiceValue(for: "mode") ?? "Coordinates"
            let mode: DatumPointMode
            switch modeStr {
            case "On Vertex": mode = .onVertex
            case "Arc Center": mode = .arcCenter
            case "Along Curve": mode = .alongCurve
            case "Midpoint": mode = .midpoint
            case "Intersection": mode = .intersection
            default: mode = .coordinates
            }

            let coords = SIMD3<Float>(
                session.numberValue(for: "coordX") ?? 0,
                session.numberValue(for: "coordY") ?? 0,
                session.numberValue(for: "coordZ") ?? 0
            )
            let p1 = SIMD3<Float>(
                session.numberValue(for: "point1X") ?? 0,
                session.numberValue(for: "point1Y") ?? 0,
                session.numberValue(for: "point1Z") ?? 0
            )
            let p2 = SIMD3<Float>(
                session.numberValue(for: "point2X") ?? 0,
                session.numberValue(for: "point2Y") ?? 0,
                session.numberValue(for: "point2Z") ?? 0
            )
            let curveParameter = Double(session.numberValue(for: "curveParameter") ?? 0.5)

            var references: [Reference] = []
            if let selectedPt = workspace.selectedDatumPointFeature {
                references.append(.feature(selectedPt.id))
            }

            let data = DatumPointFeatureData(
                mode: mode,
                coordinates: coords,
                point1: p1,
                point2: p2,
                curveParameter: curveParameter
            )

            let feature = workspace.document.addDatumPointFeature(
                name: name.isEmpty ? defaultName : name,
                data: data,
                references: references
            )
            workspace.selectFeature(feature.id)
        }

        return session
    }

    static func makeDatumCoordinateSystem(workspace: WorkspaceModel) -> CommandSession {
        let datumCount = workspace.document.activeFeatures.filter {
            if case .datumCoordinateSystem = $0.operation { return true }
            return false
        }.count + 1
        let defaultName = "UCS \(datumCount)"

        let session = CommandSession(
            title: "New Coordinate System",
            inputs: [
                CommandInput(id: "name", label: "Name", value: .text(defaultName)),
                CommandInput(id: "mode", label: "Mode", value: .choice("Origin and Axes", options: [
                    "Origin and Axes", "Three Points", "Aligned with Plane", "Offset from Parent"
                ])),
                CommandInput(id: "originX", label: "Origin X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "originY", label: "Origin Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "originZ", label: "Origin Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1X", label: "Point 1 (Origin) X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1Y", label: "Point 1 (Origin) Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point1Z", label: "Point 1 (Origin) Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2X", label: "Point 2 (+X) X", value: .number(10.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2Y", label: "Point 2 (+X) Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point2Z", label: "Point 2 (+X) Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point3X", label: "Point 3 (+XY) X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point3Y", label: "Point 3 (+XY) Y", value: .number(10.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "point3Z", label: "Point 3 (+XY) Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "offsetX", label: "Offset X", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "offsetY", label: "Offset Y", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "offsetZ", label: "Offset Z", value: .number(0.0, range: nil, step: 1.0, unit: "mm")),
                CommandInput(id: "rotX", label: "Rotation X", value: .number(0.0, range: -360.0...360.0, step: 5.0, unit: "°")),
                CommandInput(id: "rotY", label: "Rotation Y", value: .number(0.0, range: -360.0...360.0, step: 5.0, unit: "°")),
                CommandInput(id: "rotZ", label: "Rotation Z", value: .number(0.0, range: -360.0...360.0, step: 5.0, unit: "°"))
            ],
            isPreviewEnabled: false,
            inputVisibilityPredicate: { session, input in
                let mode = session.choiceValue(for: "mode") ?? "Origin and Axes"
                switch input.id {
                case "name", "mode":
                    return true
                case "originX", "originY", "originZ":
                    return mode == "Origin and Axes" || mode == "Aligned with Plane"
                case "point1X", "point1Y", "point1Z", "point2X", "point2Y", "point2Z", "point3X", "point3Y", "point3Z":
                    return mode == "Three Points"
                case "offsetX", "offsetY", "offsetZ":
                    return mode == "Offset from Parent"
                case "rotX", "rotY", "rotZ":
                    return mode == "Origin and Axes" || mode == "Offset from Parent"
                default:
                    return true
                }
            }
        )

        session.customValidation = { [weak session] in
            guard let session else { return false }
            let modeChoice = session.choiceValue(for: "mode") ?? "Origin and Axes"
            if modeChoice == "Three Points" {
                let p1 = SIMD3<Float>(
                    session.numberValue(for: "point1X") ?? 0,
                    session.numberValue(for: "point1Y") ?? 0,
                    session.numberValue(for: "point1Z") ?? 0
                )
                let p2 = SIMD3<Float>(
                    session.numberValue(for: "point2X") ?? 0,
                    session.numberValue(for: "point2Y") ?? 0,
                    session.numberValue(for: "point2Z") ?? 0
                )
                let p3 = SIMD3<Float>(
                    session.numberValue(for: "point3X") ?? 0,
                    session.numberValue(for: "point3Y") ?? 0,
                    session.numberValue(for: "point3Z") ?? 0
                )
                let v1 = p2 - p1
                let v2 = p3 - p1
                let v3 = p3 - p2
                if simd_length(v1) < 1e-6 || simd_length(v2) < 1e-6 || simd_length(v3) < 1e-6 {
                    return false
                }
                if simd_length(simd_cross(v1, v2)) < 1e-6 {
                    return false
                }
            }
            return true
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            let name = session.textValue(for: "name") ?? defaultName
            let modeStr = session.choiceValue(for: "mode") ?? "Origin and Axes"
            let mode: DatumCoordinateSystemMode
            switch modeStr {
            case "Three Points": mode = .threePoints
            case "Aligned with Plane": mode = .alignedWithPlane
            case "Offset from Parent": mode = .offsetFromParent
            default: mode = .originAndAxes
            }

            let origin = SIMD3<Float>(
                session.numberValue(for: "originX") ?? 0,
                session.numberValue(for: "originY") ?? 0,
                session.numberValue(for: "originZ") ?? 0
            )
            let p1 = SIMD3<Float>(
                session.numberValue(for: "point1X") ?? 0,
                session.numberValue(for: "point1Y") ?? 0,
                session.numberValue(for: "point1Z") ?? 0
            )
            let p2 = SIMD3<Float>(
                session.numberValue(for: "point2X") ?? 0,
                session.numberValue(for: "point2Y") ?? 0,
                session.numberValue(for: "point2Z") ?? 0
            )
            let p3 = SIMD3<Float>(
                session.numberValue(for: "point3X") ?? 0,
                session.numberValue(for: "point3Y") ?? 0,
                session.numberValue(for: "point3Z") ?? 0
            )
            let offset = SIMD3<Float>(
                session.numberValue(for: "offsetX") ?? 0,
                session.numberValue(for: "offsetY") ?? 0,
                session.numberValue(for: "offsetZ") ?? 0
            )
            let rot = SIMD3<Float>(
                session.numberValue(for: "rotX") ?? 0,
                session.numberValue(for: "rotY") ?? 0,
                session.numberValue(for: "rotZ") ?? 0
            )

            var references: [Reference] = []
            if let selectedUCS = workspace.selectedDatumCoordinateSystemFeature {
                references.append(.feature(selectedUCS.id))
            } else if let selectedPlane = workspace.selectedDatumPlaneFeature {
                references.append(.feature(selectedPlane.id))
            }

            let data = DatumCoordinateSystemFeatureData(
                mode: mode,
                origin: origin,
                xAxis: SIMD3<Float>(1, 0, 0),
                yAxis: SIMD3<Float>(0, 1, 0),
                zAxis: SIMD3<Float>(0, 0, 1),
                point1: p1,
                point2: p2,
                point3: p3,
                offsetDistance: offset,
                rotationAngles: rot
            )

            let feature = workspace.document.addDatumCoordinateSystemFeature(
                name: name.isEmpty ? defaultName : name,
                data: data,
                references: references
            )
            workspace.selectFeature(feature.id)
        }

        return session
    }

    static func makeDimension(
        workspace: WorkspaceModel,
        sketchFeatureId: UUID? = nil,
        entityId: UUID? = nil
    ) -> CommandSession {
        let targetFeatureId = sketchFeatureId ?? workspace.selectedSketchLineEntity?.featureId ?? workspace.selectedSketchFeature?.id
        var initialLength: Double = 10.0
        if let targetFeatureId,
           let feat = workspace.document.feature(for: targetFeatureId),
           case .sketch(let sketchData) = feat.operation {
            let targetEntityId = entityId ?? workspace.selectedSketchLineEntity?.entity.id ?? sketchData.entities.first(where: { $0.kind == "line" })?.id
            if let targetEntityId,
               let entity = sketchData.entities.first(where: { $0.id == targetEntityId }),
               let len = entity.length, len > 0 {
                initialLength = len
            }
        }

        let session = CommandSession(
            title: "Dimension Line",
            inputs: [
                CommandInput(
                    id: "length",
                    label: "Length",
                    value: .number(Float(initialLength), range: 0.01...10000.0, step: 1.0, unit: "mm")
                ),
                CommandInput(
                    id: "isDriven",
                    label: "Driven (Reference)",
                    value: .toggle(false)
                )
            ],
            isPreviewEnabled: false
        )

        session.customValidation = { [weak workspace, weak session] in
            guard let workspace, let session else { return false }
            let len = session.numberValue(for: "length") ?? 0
            guard len > 0, len.isFinite, len >= 0.01, len <= 10000.0 else { return false }

            let resolvedFeatureId = sketchFeatureId ?? workspace.selectedSketchLineEntity?.featureId ?? workspace.selectedSketchFeature?.id
            guard let resolvedFeatureId,
                  let feat = workspace.document.feature(for: resolvedFeatureId),
                  case .sketch(let sketchData) = feat.operation else {
                return false
            }

            let resolvedEntityId = entityId ?? workspace.selectedSketchLineEntity?.entity.id ?? sketchData.entities.first(where: { $0.kind == "line" })?.id
            guard let resolvedEntityId,
                  let entity = sketchData.entities.first(where: { $0.id == resolvedEntityId }),
                  entity.kind == "line" else {
                return false
            }

            let isDriven = session.booleanValue(for: "isDriven") ?? false
            if !isDriven {
                let system = ConstraintSystem(entities: sketchData.entities, constraints: sketchData.constraints)
                if case .overConstrained = ConstraintSolver.computeDOFStatus(system: system) {
                    return false
                }
            }

            return true
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            let len = session.numberValue(for: "length") ?? 0
            guard len > 0, len.isFinite else { return }

            let resolvedFeatureId = sketchFeatureId ?? workspace.selectedSketchLineEntity?.featureId ?? workspace.selectedSketchFeature?.id
            guard let resolvedFeatureId,
                  let feat = workspace.document.feature(for: resolvedFeatureId),
                  case .sketch(let sketchData) = feat.operation else {
                return
            }

            let resolvedEntityId = entityId ?? workspace.selectedSketchLineEntity?.entity.id ?? sketchData.entities.first(where: { $0.kind == "line" })?.id
            guard let resolvedEntityId else { return }

            let isDriven = session.booleanValue(for: "isDriven") ?? false
            if isDriven {
                let kind: SketchConstraint.Kind
                if let entity = sketchData.entities.first(where: { $0.id == resolvedEntityId }),
                   let s = entity.startPoint, let end = entity.endPoint {
                    kind = abs(end.x - s.x) >= abs(end.y - s.y) ? .horizontal : .vertical
                } else {
                    kind = .horizontal
                }
                let constraint = SketchConstraint(kind: kind, entityIds: [resolvedEntityId], isDriven: true)
                workspace.addSketchConstraint(to: resolvedFeatureId, constraint: constraint)
            } else {
                do {
                    _ = try workspace.dimensionSketchLine(
                        featureId: resolvedFeatureId,
                        entityId: resolvedEntityId,
                        length: Double(len)
                    )
                } catch {
                    // If over-constrained or error, captured by workspace
                }
            }
        }

        return session
    }

    static func makeMeasure(workspace: WorkspaceModel) -> CommandSession {
        let session = CommandSession(
            title: "Measure",
            selectionSlots: [
                CommandSelectionSlot(
                    id: "element1",
                    label: "Element 1",
                    isRequired: false,
                    selectedObjectId: nil,
                    selectedObjectName: nil,
                    selectedSubElement: nil,
                    isActive: true
                ),
                CommandSelectionSlot(
                    id: "element2",
                    label: "Element 2",
                    isRequired: false,
                    selectedObjectId: nil,
                    selectedObjectName: nil,
                    selectedSubElement: nil,
                    isActive: false
                )
            ],
            inputs: [],
            isPreviewEnabled: false
        )

        let recalculate: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            let slot1 = session.selectionSlots.first(where: { $0.id == "element1" })
            let slot2 = session.selectionSlots.first(where: { $0.id == "element2" })

            let elem1: MeasuredElement?
            if let sub = slot1?.selectedSubElement {
                elem1 = MeasuredElement(selectedSubElement: sub)
            } else if let objId = slot1?.selectedObjectId {
                elem1 = .body(objId)
            } else {
                elem1 = nil
            }

            let elem2: MeasuredElement?
            if let sub = slot2?.selectedSubElement {
                elem2 = MeasuredElement(selectedSubElement: sub)
            } else if let objId = slot2?.selectedObjectId {
                elem2 = .body(objId)
            } else {
                elem2 = nil
            }

            guard let elem1 else {
                session.inputs = []
                return
            }

            let candidateMeshes = workspace.viewportManager.renderer?.candidateMeshes() ?? []
            let hiddenIds = workspace.viewportManager.renderer?.hiddenSolidIds ?? []
            let unitSettings = workspace.document.settings.unitSettings

            guard let result = MeasureTool.measure(
                elementA: elem1,
                elementB: elem2,
                in: workspace.document,
                candidateMeshes: candidateMeshes,
                hiddenSolidIds: hiddenIds
            ) else {
                session.inputs = []
                return
            }

            var newInputs: [CommandInput] = []

            if elem2 != nil {
                let minValStr = unitSettings.formatLength(result.minDistance, includeSymbol: false)
                newInputs.append(CommandInput(
                    id: "minDistance",
                    label: "Minimum Distance",
                    value: .readOnlyText(minValStr, unit: unitSettings.lengthUnit.symbol)
                ))

                let centerValStr = unitSettings.formatLength(result.centerDistance, includeSymbol: false)
                newInputs.append(CommandInput(
                    id: "centerDistance",
                    label: "Center Distance",
                    value: .readOnlyText(centerValStr, unit: unitSettings.lengthUnit.symbol)
                ))

                if let normDist = result.normalDistance {
                    let normValStr = unitSettings.formatLength(normDist, includeSymbol: false)
                    newInputs.append(CommandInput(
                        id: "normalDistance",
                        label: "Normal Distance",
                        value: .readOnlyText(normValStr, unit: unitSettings.lengthUnit.symbol)
                    ))
                }

                if let angle = result.angleDegrees {
                    let angleValStr = unitSettings.formatAngle(angle, includeSymbol: false)
                    newInputs.append(CommandInput(
                        id: "angle",
                        label: "Angle",
                        value: .readOnlyText(angleValStr, unit: unitSettings.angleUnit.symbol)
                    ))
                }
            }

            let geomA = result.geometryA
            let geomB = result.geometryB

            if let area = geomA.area ?? geomB?.area {
                let factor = unitSettings.lengthUnit.fromMillimeters(1.0)
                let convertedArea = area * (factor * factor)
                let areaValStr = UnitSettings.format(value: convertedArea, precision: unitSettings.decimalPrecision)
                let areaUnitStr = "\(unitSettings.lengthUnit.symbol)²"
                newInputs.append(CommandInput(
                    id: "area",
                    label: "Area",
                    value: .readOnlyText(areaValStr, unit: areaUnitStr)
                ))
            }

            if let length = geomA.length ?? geomB?.length {
                let lenValStr = unitSettings.formatLength(length, includeSymbol: false)
                newInputs.append(CommandInput(
                    id: "length",
                    label: "Length",
                    value: .readOnlyText(lenValStr, unit: unitSettings.lengthUnit.symbol)
                ))
            }

            if let radius = geomA.radius ?? geomB?.radius {
                let radValStr = unitSettings.formatLength(radius, includeSymbol: false)
                newInputs.append(CommandInput(
                    id: "radius",
                    label: "Radius",
                    value: .readOnlyText(radValStr, unit: unitSettings.lengthUnit.symbol)
                ))
            }

            if let diameter = geomA.diameter ?? geomB?.diameter {
                let diamValStr = unitSettings.formatLength(diameter, includeSymbol: false)
                newInputs.append(CommandInput(
                    id: "diameter",
                    label: "Diameter",
                    value: .readOnlyText(diamValStr, unit: unitSettings.lengthUnit.symbol)
                ))
            }

            session.inputs = newInputs
        }

        session.onPreviewUpdate = recalculate
        session.onCommit = { [weak workspace] in
            workspace?.cancelActiveCommand()
        }
        session.onCancel = { [weak workspace] in
            workspace?.cancelActiveCommand()
        }

        return session
    }

    public static func makeLinearPattern(
        workspace: WorkspaceModel,
        targetSolidId: SolidId? = nil,
        initialCount: Int = 3,
        initialSpacing: Double = 20.0,
        direction: [Double] = [1.0, 0.0, 0.0],
        isSymmetric: Bool = false,
        skippedIndices: [Int] = []
    ) -> CommandSession {
        let initialId = targetSolidId ?? workspace.selectedId ?? workspace.document.selectedSubElement?.solidId ?? workspace.document.objects.first?.id
        let initialName = initialId.flatMap { id in workspace.document.objects.first(where: { $0.id == id })?.name }

        let targetSlot = CommandSelectionSlot(
            id: "target",
            label: "Target Solid",
            isRequired: true,
            selectedObjectId: initialId,
            selectedObjectName: initialName,
            isActive: initialId == nil
        )

        let initialAxisChoice: String
        if direction == [0.0, 1.0, 0.0] {
            initialAxisChoice = "Y Axis"
        } else if direction == [0.0, 0.0, 1.0] {
            initialAxisChoice = "Z Axis"
        } else {
            initialAxisChoice = "X Axis"
        }

        let skippedString = skippedIndices.map(String.init).joined(separator: ", ")

        let inputs: [CommandInput] = [
            CommandInput(
                id: "count",
                label: "Count",
                value: .number(Float(initialCount), range: Float(DocumentLimits.patternCount.min)...Float(DocumentLimits.patternCount.max), step: 1.0, unit: "")
            ),
            CommandInput(
                id: "spacing",
                label: "Spacing",
                value: .number(Float(initialSpacing), range: Float(DocumentLimits.patternSpacing.min)...Float(DocumentLimits.patternSpacing.max), step: 1.0, unit: "mm")
            ),
            CommandInput(
                id: "axis",
                label: "Direction",
                value: .choice(initialAxisChoice, options: ["X Axis", "Y Axis", "Z Axis"])
            ),
            CommandInput(
                id: "isSymmetric",
                label: "Symmetric",
                value: .toggle(isSymmetric)
            ),
            CommandInput(
                id: "skippedIndices",
                label: "Skip Indices",
                value: .text(skippedString)
            )
        ]

        let session = CommandSession(
            title: "Linear Pattern",
            selectionSlots: [targetSlot],
            inputs: inputs,
            isPreviewEnabled: true
        )

        func resolveTargetId(session: CommandSession) -> SolidId? {
            session.selectionSlots.first(where: { $0.id == "target" })?.selectedObjectId
        }

        func parseSkipped(session: CommandSession) -> [Int] {
            guard let text = session.textValue(for: "skippedIndices") else { return [] }
            return text.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }

        func resolveDirection(session: CommandSession) -> [Double] {
            let choice = session.choiceValue(for: "axis") ?? "X Axis"
            switch choice {
            case "Y Axis": return [0.0, 1.0, 0.0]
            case "Z Axis": return [0.0, 0.0, 1.0]
            default: return [1.0, 0.0, 0.0]
            }
        }

        session.customValidation = { [weak session] in
            guard let session else { return false }
            guard resolveTargetId(session: session) != nil else { return false }
            let countVal = session.numberValue(for: "count") ?? 0
            guard !countVal.isNaN, countVal >= 1.0 else { return false }
            let spacingVal = session.numberValue(for: "spacing") ?? 0
            guard !spacingVal.isNaN, spacingVal > 0 else { return false }
            return true
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard session.isPreviewEnabled else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            guard let targetId = resolveTargetId(session: session) else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let count = Int(session.numberValue(for: "count") ?? 3)
            let spacing = Double(session.numberValue(for: "spacing") ?? 20.0)
            let dir = resolveDirection(session: session)
            let isSym = session.toggleValue(for: "isSymmetric") ?? false
            let skipped = parseSkipped(session: session)

            guard count >= 1, spacing > 0 else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let params = PatternParams(
                targetSolidId: targetId,
                targetType: .body,
                patternType: .linear,
                direction: dir,
                linearSpacing: spacing,
                count: count,
                isSymmetric: isSym,
                axisOrigin: [0.0, 0.0, 0.0],
                axisDirection: [0.0, 0.0, 1.0],
                totalAngle: 360.0,
                isFullCircle: true,
                skippedIndices: skipped
            )

            Task { @MainActor in
                let req = KernelRequest.pattern(
                    jobId: JobId("preview-\(UUID().uuidString)"),
                    solidId: Self.previewSolidId,
                    params: params
                )
                let result = await workspace.kernelClient.request(req)
                if case .success(_, let payload) = result, !payload.isEmpty {
                    let previewColor = SIMD4<Float>(0.9, 0.5, 0.2, 0.75)
                    _ = workspace.viewportManager.renderer?.installMesh(
                        payload,
                        for: Self.previewSolidId,
                        transform: .identity,
                        color: previewColor,
                        isHidden: false
                    )
                    workspace.invalidateViewport(.interaction)
                } else {
                    if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                        workspace.invalidateViewport(.interaction)
                    }
                }
            }
        }

        session.onPreviewUpdate = updatePreview
        session.onParamChanged = { _, _ in
            updatePreview()
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)

            guard let targetId = resolveTargetId(session: session) else { return }
            let count = Int(session.numberValue(for: "count") ?? 3)
            let spacing = Double(session.numberValue(for: "spacing") ?? 20.0)
            let dir = resolveDirection(session: session)
            let isSym = session.toggleValue(for: "isSymmetric") ?? false
            let skipped = parseSkipped(session: session)

            let params = PatternParams(
                targetSolidId: targetId,
                targetType: .body,
                patternType: .linear,
                direction: dir,
                linearSpacing: spacing,
                count: count,
                isSymmetric: isSym,
                axisOrigin: [0.0, 0.0, 0.0],
                axisDirection: [0.0, 0.0, 1.0],
                totalAngle: 360.0,
                isFullCircle: true,
                skippedIndices: skipped
            )

            Task { @MainActor in
                _ = await workspace.patternBody(params: params)
            }
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                workspace.invalidateViewport(.interaction)
            }
        }

        return session
    }

    public static func makeCircularPattern(
        workspace: WorkspaceModel,
        targetSolidId: SolidId? = nil,
        initialCount: Int = 4,
        initialTotalAngle: Double = 360.0,
        isFullCircle: Bool = true,
        axisOrigin: [Double] = [0.0, 0.0, 0.0],
        axisDirection: [Double] = [0.0, 0.0, 1.0],
        skippedIndices: [Int] = []
    ) -> CommandSession {
        let initialId = targetSolidId ?? workspace.selectedId ?? workspace.document.selectedSubElement?.solidId ?? workspace.document.objects.first?.id
        let initialName = initialId.flatMap { id in workspace.document.objects.first(where: { $0.id == id })?.name }

        let targetSlot = CommandSelectionSlot(
            id: "target",
            label: "Target Solid",
            isRequired: true,
            selectedObjectId: initialId,
            selectedObjectName: initialName,
            isActive: initialId == nil
        )

        let initialAxisChoice: String
        if axisDirection == [1.0, 0.0, 0.0] {
            initialAxisChoice = "X Axis"
        } else if axisDirection == [0.0, 1.0, 0.0] {
            initialAxisChoice = "Y Axis"
        } else {
            initialAxisChoice = "Z Axis"
        }

        let skippedString = skippedIndices.map(String.init).joined(separator: ", ")

        let inputs: [CommandInput] = [
            CommandInput(
                id: "count",
                label: "Count",
                value: .number(Float(initialCount), range: Float(DocumentLimits.patternCount.min)...Float(DocumentLimits.patternCount.max), step: 1.0, unit: "")
            ),
            CommandInput(
                id: "totalAngle",
                label: "Angle",
                value: .number(Float(initialTotalAngle), range: Float(DocumentLimits.patternAngle.min)...Float(DocumentLimits.patternAngle.max), step: 1.0, unit: "°")
            ),
            CommandInput(
                id: "axis",
                label: "Axis",
                value: .choice(initialAxisChoice, options: ["X Axis", "Y Axis", "Z Axis"])
            ),
            CommandInput(
                id: "isFullCircle",
                label: "Full Circle",
                value: .toggle(isFullCircle)
            ),
            CommandInput(
                id: "skippedIndices",
                label: "Skip Indices",
                value: .text(skippedString)
            )
        ]

        let session = CommandSession(
            title: "Circular Pattern",
            selectionSlots: [targetSlot],
            inputs: inputs,
            isPreviewEnabled: true,
            inputVisibilityPredicate: { session, input in
                if input.id == "totalAngle" {
                    return !(session.toggleValue(for: "isFullCircle") ?? true)
                }
                return true
            }
        )

        func resolveTargetId(session: CommandSession) -> SolidId? {
            session.selectionSlots.first(where: { $0.id == "target" })?.selectedObjectId
        }

        func parseSkipped(session: CommandSession) -> [Int] {
            guard let text = session.textValue(for: "skippedIndices") else { return [] }
            return text.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }

        func resolveAxisDirection(session: CommandSession) -> [Double] {
            let choice = session.choiceValue(for: "axis") ?? "Z Axis"
            switch choice {
            case "X Axis": return [1.0, 0.0, 0.0]
            case "Y Axis": return [0.0, 1.0, 0.0]
            default: return [0.0, 0.0, 1.0]
            }
        }

        session.customValidation = { [weak session] in
            guard let session else { return false }
            guard resolveTargetId(session: session) != nil else { return false }
            let countVal = session.numberValue(for: "count") ?? 0
            guard !countVal.isNaN, countVal >= 1.0 else { return false }
            let angleVal = session.numberValue(for: "totalAngle") ?? 0
            guard !angleVal.isNaN, angleVal > 0 else { return false }
            return true
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard session.isPreviewEnabled else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            guard let targetId = resolveTargetId(session: session) else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let count = Int(session.numberValue(for: "count") ?? 4)
            let totalAngle = Double(session.numberValue(for: "totalAngle") ?? 360.0)
            let axisDir = resolveAxisDirection(session: session)
            let isFull = session.toggleValue(for: "isFullCircle") ?? true
            let skipped = parseSkipped(session: session)

            guard count >= 1, totalAngle > 0 else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let params = PatternParams(
                targetSolidId: targetId,
                targetType: .body,
                patternType: .circular,
                direction: [1.0, 0.0, 0.0],
                linearSpacing: 20.0,
                count: count,
                isSymmetric: false,
                axisOrigin: axisOrigin,
                axisDirection: axisDir,
                totalAngle: totalAngle,
                isFullCircle: isFull,
                skippedIndices: skipped
            )

            Task { @MainActor in
                let req = KernelRequest.pattern(
                    jobId: JobId("preview-\(UUID().uuidString)"),
                    solidId: Self.previewSolidId,
                    params: params
                )
                let result = await workspace.kernelClient.request(req)
                if case .success(_, let payload) = result, !payload.isEmpty {
                    let previewColor = SIMD4<Float>(0.9, 0.5, 0.2, 0.75)
                    _ = workspace.viewportManager.renderer?.installMesh(
                        payload,
                        for: Self.previewSolidId,
                        transform: .identity,
                        color: previewColor,
                        isHidden: false
                    )
                    workspace.invalidateViewport(.interaction)
                } else {
                    if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                        workspace.invalidateViewport(.interaction)
                    }
                }
            }
        }

        session.onPreviewUpdate = updatePreview
        session.onParamChanged = { _, _ in
            updatePreview()
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)

            guard let targetId = resolveTargetId(session: session) else { return }
            let count = Int(session.numberValue(for: "count") ?? 4)
            let totalAngle = Double(session.numberValue(for: "totalAngle") ?? 360.0)
            let axisDir = resolveAxisDirection(session: session)
            let isFull = session.toggleValue(for: "isFullCircle") ?? true
            let skipped = parseSkipped(session: session)

            let params = PatternParams(
                targetSolidId: targetId,
                targetType: .body,
                patternType: .circular,
                direction: [1.0, 0.0, 0.0],
                linearSpacing: 20.0,
                count: count,
                isSymmetric: false,
                axisOrigin: axisOrigin,
                axisDirection: axisDir,
                totalAngle: totalAngle,
                isFullCircle: isFull,
                skippedIndices: skipped
            )

            Task { @MainActor in
                _ = await workspace.patternBody(params: params)
            }
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                workspace.invalidateViewport(.interaction)
            }
        }

        return session
    }

    public static func makeMirror(
        workspace: WorkspaceModel,
        targetSolidId: SolidId? = nil,
        planeReference: Reference? = nil,
        presetPlane: String = "XY Plane",
        keepOriginal: Bool = true
    ) -> CommandSession {
        let initialId = targetSolidId ?? workspace.selectedId ?? workspace.document.selectedSubElement?.solidId ?? workspace.document.objects.first?.id
        let initialName = initialId.flatMap { id in workspace.document.objects.first(where: { $0.id == id })?.name }

        let targetSlot = CommandSelectionSlot(
            id: "target",
            label: "Target Solid",
            isRequired: true,
            selectedObjectId: initialId,
            selectedObjectName: initialName,
            isActive: initialId == nil
        )

        var initialPlaneSlotName: String? = nil
        var initialPlaneObjId: ObjectId? = nil
        if let planeReference {
            switch planeReference.target {
            case .feature(let featId):
                initialPlaneObjId = ObjectId(featId.uuidString)
                initialPlaneSlotName = workspace.document.feature(for: featId)?.name ?? "Datum Plane"
            case .face(let topRef):
                initialPlaneSlotName = topRef.historyPath.last?.label ?? "Planar Face"
            default:
                break
            }
        }

        let isFromSelection = presetPlane == "From Selection" || planeReference != nil
        let actualPreset = isFromSelection ? "From Selection" : presetPlane

        let planeSlot = CommandSelectionSlot(
            id: "mirrorPlane",
            label: "Mirror Plane",
            isRequired: actualPreset == "From Selection",
            selectedObjectId: initialPlaneObjId,
            selectedObjectName: initialPlaneSlotName,
            isActive: actualPreset == "From Selection" && initialPlaneSlotName == nil
        )

        let inputs: [CommandInput] = [
            CommandInput(
                id: "presetPlane",
                label: "Plane Preset",
                value: .choice(actualPreset, options: ["XY Plane", "XZ Plane", "YZ Plane", "From Selection"])
            ),
            CommandInput(
                id: "keepOriginal",
                label: "Keep Original",
                value: .toggle(keepOriginal)
            )
        ]

        let session = CommandSession(
            title: "Mirror",
            selectionSlots: [targetSlot, planeSlot],
            inputs: inputs,
            isPreviewEnabled: true
        )

        func resolveTargetId(session: CommandSession) -> SolidId? {
            session.selectionSlots.first(where: { $0.id == "target" })?.selectedObjectId
        }

        func resolvePlane(session: CommandSession) -> (normal: SIMD3<Double>, origin: SIMD3<Double>, ref: Reference?)? {
            let choice = session.choiceValue(for: "presetPlane") ?? "XY Plane"
            switch choice {
            case "XY Plane":
                return (normal: SIMD3<Double>(0, 0, 1), origin: SIMD3<Double>(0, 0, 0), ref: nil)
            case "XZ Plane":
                return (normal: SIMD3<Double>(0, 1, 0), origin: SIMD3<Double>(0, 0, 0), ref: nil)
            case "YZ Plane":
                return (normal: SIMD3<Double>(1, 0, 0), origin: SIMD3<Double>(0, 0, 0), ref: nil)
            case "From Selection":
                let planeSlot = session.selectionSlots.first(where: { $0.id == "mirrorPlane" })
                if let subEl = planeSlot?.selectedSubElement, subEl.elementType == .face {
                    if let feat = workspace.document.feature(for: subEl.solidId) {
                        let topRef: TopologicalReference
                        if let detId = subEl.deterministicId, let existing = feat.generatedTopology.values.first(where: { $0.id == detId }) {
                            topRef = existing
                        } else if let named = feat.generatedTopology.values.first(where: { $0.historyPath.last?.label == "face:\(subEl.elementId)" }) {
                            topRef = named
                        } else {
                            topRef = TopologicalReference(
                                sourceFeatureId: feat.id,
                                elementType: .face,
                                historyPath: [HistoryStep(kind: .generated, label: "face:\(subEl.elementId)")]
                            )
                        }
                        let ref = Reference.face(topRef)
                        if let sketchPlane = try? DatumPlaneEvaluator.resolveBasePlane(from: ref, in: workspace.document) {
                            return (normal: SIMD3<Double>(sketchPlane.normal), origin: SIMD3<Double>(sketchPlane.origin), ref: ref)
                        }
                    }
                } else if let objId = planeSlot?.selectedObjectId {
                    let feat = (UUID(uuidString: objId.rawValue).flatMap { workspace.document.feature(for: $0) }) ?? workspace.document.feature(for: objId)
                    if let feat {
                        let ref = Reference.feature(feat.id)
                        if let sketchPlane = try? DatumPlaneEvaluator.resolveBasePlane(from: ref, in: workspace.document) {
                            return (normal: SIMD3<Double>(sketchPlane.normal), origin: SIMD3<Double>(sketchPlane.origin), ref: ref)
                        }
                    }
                }
                if let planeReference {
                    if let sketchPlane = try? DatumPlaneEvaluator.resolveBasePlane(from: planeReference, in: workspace.document) {
                        return (normal: SIMD3<Double>(sketchPlane.normal), origin: SIMD3<Double>(sketchPlane.origin), ref: planeReference)
                    }
                }
                return nil
            default:
                return (normal: SIMD3<Double>(0, 0, 1), origin: SIMD3<Double>(0, 0, 0), ref: nil)
            }
        }

        session.customValidation = { [weak session] in
            guard let session else { return false }
            guard resolveTargetId(session: session) != nil else { return false }
            let choice = session.choiceValue(for: "presetPlane") ?? "XY Plane"
            if choice == "From Selection" {
                let planeSlot = session.selectionSlots.first(where: { $0.id == "mirrorPlane" })
                let hasSelection = planeSlot?.selectedObjectId != nil || planeSlot?.selectedSubElement != nil || planeReference != nil
                guard hasSelection else { return false }
            }
            guard let plane = resolvePlane(session: session) else { return false }
            let len = simd_length(plane.normal)
            guard !len.isNaN, len > 1e-6 else { return false }
            return true
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard session.isPreviewEnabled else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            guard let targetId = resolveTargetId(session: session),
                  let plane = resolvePlane(session: session) else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                workspace.invalidateViewport(.interaction)
                return
            }

            let keepOrig = session.toggleValue(for: "keepOriginal") ?? true

            let params = MirrorParams(
                targetSolidId: targetId,
                targetType: .body,
                planeNormal: plane.normal,
                planeOrigin: plane.origin,
                keepOriginal: keepOrig,
                planeReference: plane.ref
            )

            Task { @MainActor in
                let req = KernelRequest.mirror(
                    jobId: JobId("preview-\(UUID().uuidString)"),
                    solidId: Self.previewSolidId,
                    params: params
                )
                let result = await workspace.kernelClient.request(req)
                if case .success(_, let payload) = result, !payload.isEmpty {
                    let previewColor = SIMD4<Float>(0.2, 0.7, 0.9, 0.75)
                    _ = workspace.viewportManager.renderer?.installMesh(
                        payload,
                        for: Self.previewSolidId,
                        transform: .identity,
                        color: previewColor,
                        isHidden: false
                    )
                    workspace.invalidateViewport(.interaction)
                } else {
                    if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                        workspace.invalidateViewport(.interaction)
                    }
                }
            }
        }

        session.onPreviewUpdate = updatePreview
        session.onParamChanged = { id, _ in
            if id == "presetPlane" {
                let isFromSel = session.choiceValue(for: "presetPlane") == "From Selection"
                if let idx = session.selectionSlots.firstIndex(where: { $0.id == "mirrorPlane" }) {
                    session.selectionSlots[idx].isRequired = isFromSel
                    session.selectionSlots[idx].isActive = isFromSel && session.selectionSlots[idx].selectedObjectId == nil && session.selectionSlots[idx].selectedSubElement == nil
                }
            }
            updatePreview()
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            workspace.invalidateViewport(.interaction)

            guard let targetId = resolveTargetId(session: session),
                  let plane = resolvePlane(session: session) else { return }

            let keepOrig = session.toggleValue(for: "keepOriginal") ?? true

            let params = MirrorParams(
                targetSolidId: targetId,
                targetType: .body,
                planeNormal: plane.normal,
                planeOrigin: plane.origin,
                keepOriginal: keepOrig,
                planeReference: plane.ref
            )

            Task { @MainActor in
                _ = await workspace.mirrorBody(params: params)
            }
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                workspace.invalidateViewport(.interaction)
            }
        }

        return session
    }

    // MARK: - Edit Feature (BL-PRT-25)

    static func makeEditFeature(workspace: WorkspaceModel, featureId: UUID) -> CommandSession? {
        guard let feature = workspace.document.feature(for: featureId), !feature.isLocked else {
            return nil
        }
        guard case .primitive(let prim) = feature.operation else {
            return nil
        }

        let solidId = feature.outputSolidId ?? SolidId(feature.id.uuidString)
        let wasOriginallyHidden = workspace.viewportManager.renderer?.hiddenSolidIds.contains(solidId) ?? false

        let inputs: [CommandInput]
        let title: String
        let customValidation: (@MainActor (CommandSession) -> Bool)?

        switch prim {
        case .box(let params):
            title = "Edit Box"
            inputs = [
                CommandInput(id: "width", label: "Width (X)", value: .number(params.width, range: DocumentLimits.boxWidth.min...DocumentLimits.boxWidth.max, step: 1.0, unit: "mm")),
                CommandInput(id: "depth", label: "Depth (Y)", value: .number(params.depth, range: DocumentLimits.boxDepth.min...DocumentLimits.boxDepth.max, step: 1.0, unit: "mm")),
                CommandInput(id: "height", label: "Height (Z)", value: .number(params.height, range: DocumentLimits.boxHeight.min...DocumentLimits.boxHeight.max, step: 1.0, unit: "mm"))
            ]
            customValidation = nil

        case .cylinder(let params):
            title = "Edit Cylinder"
            inputs = [
                CommandInput(id: "radius", label: "Radius", value: .number(params.radius, range: DocumentLimits.cylinderRadius.min...DocumentLimits.cylinderRadius.max, step: 1.0, unit: "mm")),
                CommandInput(id: "height", label: "Height (Z)", value: .number(params.height, range: DocumentLimits.cylinderHeight.min...DocumentLimits.cylinderHeight.max, step: 1.0, unit: "mm"))
            ]
            customValidation = nil

        case .sphere(let params):
            title = "Edit Sphere"
            inputs = [
                CommandInput(id: "radius", label: "Radius", value: .number(params.radius, range: DocumentLimits.sphereRadius.min...DocumentLimits.sphereRadius.max, step: 1.0, unit: "mm"))
            ]
            customValidation = nil

        case .cone(let params):
            title = "Edit Cone"
            inputs = [
                CommandInput(id: "bottomRadius", label: "Bottom Radius", value: .number(params.bottomRadius, range: DocumentLimits.coneBottomRadius.min...DocumentLimits.coneBottomRadius.max, step: 1.0, unit: "mm")),
                CommandInput(id: "topRadius", label: "Top Radius", value: .number(params.topRadius, range: DocumentLimits.coneTopRadius.min...DocumentLimits.coneTopRadius.max, step: 1.0, unit: "mm")),
                CommandInput(id: "height", label: "Height (Z)", value: .number(params.height, range: DocumentLimits.coneHeight.min...DocumentLimits.coneHeight.max, step: 1.0, unit: "mm"))
            ]
            customValidation = { sess in
                let br = sess.numberValue(for: "bottomRadius") ?? params.bottomRadius
                let tr = sess.numberValue(for: "topRadius") ?? params.topRadius
                return br > 0 || tr > 0
            }

        case .torus(let params):
            title = "Edit Torus"
            inputs = [
                CommandInput(id: "majorRadius", label: "Major Radius", value: .number(params.majorRadius, range: DocumentLimits.torusMajorRadius.min...DocumentLimits.torusMajorRadius.max, step: 1.0, unit: "mm")),
                CommandInput(id: "minorRadius", label: "Minor Radius", value: .number(params.minorRadius, range: DocumentLimits.torusMinorRadius.min...DocumentLimits.torusMinorRadius.max, step: 1.0, unit: "mm"))
            ]
            customValidation = { sess in
                let maj = sess.numberValue(for: "majorRadius") ?? params.majorRadius
                let minR = sess.numberValue(for: "minorRadius") ?? params.minorRadius
                return maj > minR
            }

        case .wedge(let params):
            title = "Edit Wedge"
            inputs = [
                CommandInput(id: "width", label: "Width (X)", value: .number(params.width, range: DocumentLimits.wedgeWidth.min...DocumentLimits.wedgeWidth.max, step: 1.0, unit: "mm")),
                CommandInput(id: "depth", label: "Depth (Y)", value: .number(params.depth, range: DocumentLimits.wedgeDepth.min...DocumentLimits.wedgeDepth.max, step: 1.0, unit: "mm")),
                CommandInput(id: "height", label: "Height (Z)", value: .number(params.height, range: DocumentLimits.wedgeHeight.min...DocumentLimits.wedgeHeight.max, step: 1.0, unit: "mm")),
                CommandInput(id: "topWidth", label: "Top Width (X)", value: .number(params.topWidth, range: DocumentLimits.wedgeTopWidth.min...DocumentLimits.wedgeTopWidth.max, step: 1.0, unit: "mm"))
            ]
            customValidation = { sess in
                let w = sess.numberValue(for: "width") ?? params.width
                let tw = sess.numberValue(for: "topWidth") ?? params.topWidth
                return tw <= w
            }
        }

        let session = CommandSession(
            title: title,
            inputs: inputs,
            isPreviewEnabled: true
        )

        if let customValidation {
            session.customValidation = { [weak session] in
                guard let session else { return false }
                return customValidation(session)
            }
        }

        if case .box = prim {
            session.dimensionAnchorsProvider = { [weak session] in
                guard let session else { return [:] }
                let w = session.numberValue(for: "width") ?? 30.0
                let d = session.numberValue(for: "depth") ?? 30.0
                let h = session.numberValue(for: "height") ?? 30.0
                return [
                    "width": SIMD3<Float>(0, -d / 2.0, -h / 2.0),
                    "depth": SIMD3<Float>(w / 2.0, 0, -h / 2.0),
                    "height": SIMD3<Float>(w / 2.0, -d / 2.0, 0)
                ]
            }
        }

        let updatePreview: @MainActor () -> Void = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            guard let currentFeature = workspace.document.feature(for: featureId) else { return }

            if session.isPreviewEnabled {
                let payload: MeshPayload?
                let candidateFeature: Feature?

                switch prim {
                case .box:
                    let w = session.numberValue(for: "width") ?? 30.0
                    let d = session.numberValue(for: "depth") ?? 30.0
                    let h = session.numberValue(for: "height") ?? 30.0
                    guard w >= DocumentLimits.boxWidth.min && w <= DocumentLimits.boxWidth.max,
                          d >= DocumentLimits.boxDepth.min && d <= DocumentLimits.boxDepth.max,
                          h >= DocumentLimits.boxHeight.min && h <= DocumentLimits.boxHeight.max else {
                        payload = nil
                        candidateFeature = nil
                        break
                    }
                    payload = NativeGeometryGenerator.generateBox(width: w, depth: d, height: h)
                    var f = Feature.makeBox(
                        id: currentFeature.id,
                        solidId: solidId,
                        name: currentFeature.name,
                        params: BoxParams(width: w, depth: d, height: h),
                        bodyOperation: currentFeature.bodyOperation,
                        targetBodyId: currentFeature.targetBodyId,
                        transform: currentFeature.transform,
                        isVisible: currentFeature.isVisible,
                        isLocked: currentFeature.isLocked,
                        material: currentFeature.material
                    )
                    f.isSuppressed = currentFeature.isSuppressed
                    candidateFeature = f

                case .cylinder:
                    let r = session.numberValue(for: "radius") ?? 12.0
                    let h = session.numberValue(for: "height") ?? 35.0
                    guard r >= DocumentLimits.cylinderRadius.min && r <= DocumentLimits.cylinderRadius.max,
                          h >= DocumentLimits.cylinderHeight.min && h <= DocumentLimits.cylinderHeight.max else {
                        payload = nil
                        candidateFeature = nil
                        break
                    }
                    payload = NativeGeometryGenerator.generateCylinder(radius: r, height: h)
                    var f = Feature.makeCylinder(
                        id: currentFeature.id,
                        solidId: solidId,
                        name: currentFeature.name,
                        params: CylinderParams(radius: r, height: h),
                        bodyOperation: currentFeature.bodyOperation,
                        targetBodyId: currentFeature.targetBodyId,
                        transform: currentFeature.transform,
                        isVisible: currentFeature.isVisible,
                        isLocked: currentFeature.isLocked,
                        material: currentFeature.material
                    )
                    f.isSuppressed = currentFeature.isSuppressed
                    candidateFeature = f

                case .sphere:
                    let r = session.numberValue(for: "radius") ?? 15.0
                    guard r >= DocumentLimits.sphereRadius.min && r <= DocumentLimits.sphereRadius.max else {
                        payload = nil
                        candidateFeature = nil
                        break
                    }
                    payload = NativeGeometryGenerator.generateSphere(radius: r)
                    var f = Feature.makeSphere(
                        id: currentFeature.id,
                        solidId: solidId,
                        name: currentFeature.name,
                        params: SphereParams(radius: r),
                        bodyOperation: currentFeature.bodyOperation,
                        targetBodyId: currentFeature.targetBodyId,
                        transform: currentFeature.transform,
                        isVisible: currentFeature.isVisible,
                        isLocked: currentFeature.isLocked,
                        material: currentFeature.material
                    )
                    f.isSuppressed = currentFeature.isSuppressed
                    candidateFeature = f

                case .cone:
                    let br = session.numberValue(for: "bottomRadius") ?? 15.0
                    let tr = session.numberValue(for: "topRadius") ?? 0.0
                    let h = session.numberValue(for: "height") ?? 30.0
                    guard br >= DocumentLimits.coneBottomRadius.min && br <= DocumentLimits.coneBottomRadius.max,
                          tr >= DocumentLimits.coneTopRadius.min && tr <= DocumentLimits.coneTopRadius.max,
                          h >= DocumentLimits.coneHeight.min && h <= DocumentLimits.coneHeight.max,
                          br > 0 || tr > 0 else {
                        payload = nil
                        candidateFeature = nil
                        break
                    }
                    payload = NativeGeometryGenerator.generateCone(bottomRadius: br, topRadius: tr, height: h)
                    var f = Feature.makeCone(
                        id: currentFeature.id,
                        solidId: solidId,
                        name: currentFeature.name,
                        params: ConeParams(bottomRadius: br, topRadius: tr, height: h),
                        bodyOperation: currentFeature.bodyOperation,
                        targetBodyId: currentFeature.targetBodyId,
                        transform: currentFeature.transform,
                        isVisible: currentFeature.isVisible,
                        isLocked: currentFeature.isLocked,
                        material: currentFeature.material
                    )
                    f.isSuppressed = currentFeature.isSuppressed
                    candidateFeature = f

                case .torus:
                    let maj = session.numberValue(for: "majorRadius") ?? 20.0
                    let minR = session.numberValue(for: "minorRadius") ?? 5.0
                    guard maj >= DocumentLimits.torusMajorRadius.min && maj <= DocumentLimits.torusMajorRadius.max,
                          minR >= DocumentLimits.torusMinorRadius.min && minR <= DocumentLimits.torusMinorRadius.max,
                          maj > minR else {
                        payload = nil
                        candidateFeature = nil
                        break
                    }
                    payload = NativeGeometryGenerator.generateTorus(majorRadius: maj, minorRadius: minR)
                    var f = Feature.makeTorus(
                        id: currentFeature.id,
                        solidId: solidId,
                        name: currentFeature.name,
                        params: TorusParams(majorRadius: maj, minorRadius: minR),
                        bodyOperation: currentFeature.bodyOperation,
                        targetBodyId: currentFeature.targetBodyId,
                        transform: currentFeature.transform,
                        isVisible: currentFeature.isVisible,
                        isLocked: currentFeature.isLocked,
                        material: currentFeature.material
                    )
                    f.isSuppressed = currentFeature.isSuppressed
                    candidateFeature = f

                case .wedge:
                    let w = session.numberValue(for: "width") ?? 30.0
                    let d = session.numberValue(for: "depth") ?? 30.0
                    let h = session.numberValue(for: "height") ?? 30.0
                    let tw = session.numberValue(for: "topWidth") ?? 0.0
                    guard w >= DocumentLimits.wedgeWidth.min && w <= DocumentLimits.wedgeWidth.max,
                          d >= DocumentLimits.wedgeDepth.min && d <= DocumentLimits.wedgeDepth.max,
                          h >= DocumentLimits.wedgeHeight.min && h <= DocumentLimits.wedgeHeight.max,
                          tw >= DocumentLimits.wedgeTopWidth.min && tw <= DocumentLimits.wedgeTopWidth.max,
                          tw <= w else {
                        payload = nil
                        candidateFeature = nil
                        break
                    }
                    payload = NativeGeometryGenerator.generateWedge(width: w, depth: d, height: h, topWidth: tw)
                    var f = Feature.makeWedge(
                        id: currentFeature.id,
                        solidId: solidId,
                        name: currentFeature.name,
                        params: WedgeParams(width: w, depth: d, height: h, topWidth: tw),
                        bodyOperation: currentFeature.bodyOperation,
                        targetBodyId: currentFeature.targetBodyId,
                        transform: currentFeature.transform,
                        isVisible: currentFeature.isVisible,
                        isLocked: currentFeature.isLocked,
                        material: currentFeature.material
                    )
                    f.isSuppressed = currentFeature.isSuppressed
                    candidateFeature = f
                }

                if let payload, let candidateFeature {
                    workspace.viewportManager.renderer?.hiddenSolidIds.insert(solidId)
                    let previewColor = SIMD4<Float>(0.2, 0.6, 1.0, 0.75)
                    _ = workspace.viewportManager.renderer?.installMesh(
                        payload,
                        for: Self.previewSolidId,
                        transform: currentFeature.transform,
                        color: previewColor,
                        isHidden: false
                    )
                    session.errorMessage = checkDownstreamValidation(feature: currentFeature, candidateFeature: candidateFeature, workspace: workspace)
                } else {
                    _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                    if !wasOriginallyHidden && !currentFeature.isSuppressed {
                        workspace.viewportManager.renderer?.hiddenSolidIds.remove(solidId)
                    }
                    session.errorMessage = nil
                }
                workspace.invalidateViewport(.interaction)
            } else {
                _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
                if !wasOriginallyHidden && !currentFeature.isSuppressed {
                    workspace.viewportManager.renderer?.hiddenSolidIds.remove(solidId)
                }
                session.errorMessage = nil
                workspace.invalidateViewport(.interaction)
            }
        }

        session.onPreviewUpdate = updatePreview

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            let isSuppressed = workspace.document.feature(for: featureId)?.isSuppressed ?? false
            if !wasOriginallyHidden && !isSuppressed {
                workspace.viewportManager.renderer?.hiddenSolidIds.remove(solidId)
            }
            workspace.invalidateViewport(.interaction)
        }

        session.onCommit = { [weak workspace, weak session] in
            guard let workspace, let session else { return }
            _ = workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId)
            let isSuppressed = workspace.document.feature(for: featureId)?.isSuppressed ?? false
            if !wasOriginallyHidden && !isSuppressed {
                workspace.viewportManager.renderer?.hiddenSolidIds.remove(solidId)
            }

            guard let currentFeature = workspace.document.feature(for: featureId) else { return }
            let updatedFeature: Feature?

            switch prim {
            case .box:
                let w = session.numberValue(for: "width") ?? 30.0
                let d = session.numberValue(for: "depth") ?? 30.0
                let h = session.numberValue(for: "height") ?? 30.0
                var f = Feature.makeBox(
                    id: currentFeature.id,
                    solidId: solidId,
                    name: currentFeature.name,
                    params: BoxParams(width: w, depth: d, height: h),
                    bodyOperation: currentFeature.bodyOperation,
                    targetBodyId: currentFeature.targetBodyId,
                    transform: currentFeature.transform,
                    isVisible: currentFeature.isVisible,
                    isLocked: currentFeature.isLocked,
                    material: currentFeature.material
                )
                f.isSuppressed = currentFeature.isSuppressed
                updatedFeature = f

            case .cylinder:
                let r = session.numberValue(for: "radius") ?? 12.0
                let h = session.numberValue(for: "height") ?? 35.0
                var f = Feature.makeCylinder(
                    id: currentFeature.id,
                    solidId: solidId,
                    name: currentFeature.name,
                    params: CylinderParams(radius: r, height: h),
                    bodyOperation: currentFeature.bodyOperation,
                    targetBodyId: currentFeature.targetBodyId,
                    transform: currentFeature.transform,
                    isVisible: currentFeature.isVisible,
                    isLocked: currentFeature.isLocked,
                    material: currentFeature.material
                )
                f.isSuppressed = currentFeature.isSuppressed
                updatedFeature = f

            case .sphere:
                let r = session.numberValue(for: "radius") ?? 15.0
                var f = Feature.makeSphere(
                    id: currentFeature.id,
                    solidId: solidId,
                    name: currentFeature.name,
                    params: SphereParams(radius: r),
                    bodyOperation: currentFeature.bodyOperation,
                    targetBodyId: currentFeature.targetBodyId,
                    transform: currentFeature.transform,
                    isVisible: currentFeature.isVisible,
                    isLocked: currentFeature.isLocked,
                    material: currentFeature.material
                )
                f.isSuppressed = currentFeature.isSuppressed
                updatedFeature = f

            case .cone:
                let br = session.numberValue(for: "bottomRadius") ?? 15.0
                let tr = session.numberValue(for: "topRadius") ?? 0.0
                let h = session.numberValue(for: "height") ?? 30.0
                var f = Feature.makeCone(
                    id: currentFeature.id,
                    solidId: solidId,
                    name: currentFeature.name,
                    params: ConeParams(bottomRadius: br, topRadius: tr, height: h),
                    bodyOperation: currentFeature.bodyOperation,
                    targetBodyId: currentFeature.targetBodyId,
                    transform: currentFeature.transform,
                    isVisible: currentFeature.isVisible,
                    isLocked: currentFeature.isLocked,
                    material: currentFeature.material
                )
                f.isSuppressed = currentFeature.isSuppressed
                updatedFeature = f

            case .torus:
                let maj = session.numberValue(for: "majorRadius") ?? 20.0
                let minR = session.numberValue(for: "minorRadius") ?? 5.0
                var f = Feature.makeTorus(
                    id: currentFeature.id,
                    solidId: solidId,
                    name: currentFeature.name,
                    params: TorusParams(majorRadius: maj, minorRadius: minR),
                    bodyOperation: currentFeature.bodyOperation,
                    targetBodyId: currentFeature.targetBodyId,
                    transform: currentFeature.transform,
                    isVisible: currentFeature.isVisible,
                    isLocked: currentFeature.isLocked,
                    material: currentFeature.material
                )
                f.isSuppressed = currentFeature.isSuppressed
                updatedFeature = f

            case .wedge:
                let w = session.numberValue(for: "width") ?? 30.0
                let d = session.numberValue(for: "depth") ?? 30.0
                let h = session.numberValue(for: "height") ?? 30.0
                let tw = session.numberValue(for: "topWidth") ?? 0.0
                var f = Feature.makeWedge(
                    id: currentFeature.id,
                    solidId: solidId,
                    name: currentFeature.name,
                    params: WedgeParams(width: w, depth: d, height: h, topWidth: tw),
                    bodyOperation: currentFeature.bodyOperation,
                    targetBodyId: currentFeature.targetBodyId,
                    transform: currentFeature.transform,
                    isVisible: currentFeature.isVisible,
                    isLocked: currentFeature.isLocked,
                    material: currentFeature.material
                )
                f.isSuppressed = currentFeature.isSuppressed
                updatedFeature = f
            }

            if let updatedFeature {
                _ = workspace.document.updateFeature(updatedFeature)
                if !updatedFeature.isSuppressed {
                    workspace.recomputeSolid(id: solidId)
                }
            }
            workspace.invalidateViewport(.interaction)
        }

        return session
    }

    private static func checkDownstreamValidation(
        feature: Feature,
        candidateFeature: Feature,
        workspace: WorkspaceModel
    ) -> String? {
        let solidId = feature.outputSolidId ?? SolidId(feature.id.uuidString)
        let downstream = workspace.document.dependentFeatures(referencing: feature.id)

        let directTargetFeatures = workspace.document.features.filter { feat in
            guard feat.id != feature.id else { return false }
            if feat.targetBodyId == solidId { return true }
            if case .chamfer(let ch) = feat.operation, ch.targetSolidId == solidId { return true }
            if case .shell(let sh) = feat.operation, sh.targetSolidId == solidId { return true }
            if case .hole(let h) = feat.operation, h.targetSolidId == solidId { return true }
            if case .boolean(let b) = feat.operation, (b.targetSolidId == solidId || b.toolSolidId == solidId) { return true }
            return false
        }

        var allDownstream = downstream
        for f in directTargetFeatures where !allDownstream.contains(where: { $0.id == f.id }) {
            allDownstream.append(f)
        }

        guard !allDownstream.isEmpty else { return nil }

        for dep in allDownstream {
            if let err = dep.errorState {
                return "Downstream feature “\(dep.name)” has an error: \(err.message)"
            }

            switch (candidateFeature.operation, dep.operation) {
            case (.primitive(.box(let p)), .chamfer(let ch)):
                let limit = Double(min(p.width, min(p.depth, p.height)))
                if ch.distance >= limit || (ch.mode == .twoDistances && ch.distance2 >= limit) {
                    return "Downstream feature “\(dep.name)” would fail: Chamfer distance exceeds solid dimensions."
                }
            case (.primitive(.cylinder(let p)), .chamfer(let ch)):
                let limit = Double(min(p.radius, p.height))
                if ch.distance >= limit {
                    return "Downstream feature “\(dep.name)” would fail: Chamfer distance exceeds solid dimensions."
                }
            case (.primitive(.sphere(let p)), .chamfer(let ch)):
                if ch.distance >= Double(p.radius) {
                    return "Downstream feature “\(dep.name)” would fail: Chamfer distance exceeds solid dimensions."
                }
            case (.primitive(.cone(let p)), .chamfer(let ch)):
                let rMax = Double(max(p.bottomRadius, p.topRadius))
                let limit = min(rMax, Double(p.height))
                if ch.distance >= limit {
                    return "Downstream feature “\(dep.name)” would fail: Chamfer distance exceeds solid dimensions."
                }
            case (.primitive(.torus(let p)), .chamfer(let ch)):
                if ch.distance >= Double(p.minorRadius) {
                    return "Downstream feature “\(dep.name)” would fail: Chamfer distance exceeds solid dimensions."
                }
            case (.primitive(.wedge(let p)), .chamfer(let ch)):
                let limit = Double(min(p.width, min(p.depth, p.height)))
                if ch.distance >= limit {
                    return "Downstream feature “\(dep.name)” would fail: Chamfer distance exceeds solid dimensions."
                }

            case (.primitive(.box(let p)), .shell(let sh)):
                let limit = Double(min(p.width, min(p.depth, p.height)))
                if sh.thickness * 2.0 >= limit {
                    return "Downstream feature “\(dep.name)” would fail: Shell thickness exceeds solid dimensions."
                }
            case (.primitive(.cylinder(let p)), .shell(let sh)):
                if sh.thickness >= Double(p.radius) || sh.thickness * 2.0 >= Double(p.height) {
                    return "Downstream feature “\(dep.name)” would fail: Shell thickness exceeds solid dimensions."
                }
            case (.primitive(.sphere(let p)), .shell(let sh)):
                if sh.thickness >= Double(p.radius) {
                    return "Downstream feature “\(dep.name)” would fail: Shell thickness exceeds solid dimensions."
                }

            case (.primitive(.box(let p)), .hole(let h)):
                if Double(p.height) < h.depth || Double(min(p.width, p.depth)) < h.diameter {
                    return "Downstream feature “\(dep.name)” would fail: Hole exceeds solid bounds."
                }
            case (.primitive(.cylinder(let p)), .hole(let h)):
                if Double(p.height) < h.depth || Double(p.radius * 2.0) < h.diameter {
                    return "Downstream feature “\(dep.name)” would fail: Hole exceeds solid bounds."
                }

            default:
                break
            }
        }

        return nil
    }
}
