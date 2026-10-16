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
    var isActive: Bool

    init(
        id: String,
        label: String,
        isRequired: Bool = true,
        selectedObjectId: ObjectId? = nil,
        selectedObjectName: String? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.label = label
        self.isRequired = isRequired
        self.selectedObjectId = selectedObjectId
        self.selectedObjectName = selectedObjectName
        self.isActive = isActive
    }
}

enum CommandInputValue: Sendable, Equatable {
    case number(Float, range: ClosedRange<Float>?, step: Float = 1.0, unit: String = "mm")
    case text(String)
    case toggle(Bool)
    case choice(String, options: [String])
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

    init(
        id: String = UUID().uuidString,
        title: String,
        selectionSlots: [CommandSelectionSlot] = [],
        inputs: [CommandInput] = [],
        isPreviewEnabled: Bool = true,
        customValidation: (@MainActor () -> Bool)? = nil,
        onParamChanged: (@MainActor (String, CommandInputValue) -> Void)? = nil,
        onPreviewUpdate: (@MainActor () -> Void)? = nil,
        onCommit: (@MainActor () -> Void)? = nil,
        onCancel: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.selectionSlots = selectionSlots
        self.inputs = inputs
        self.isPreviewEnabled = isPreviewEnabled
        self.customValidation = customValidation
        self.onParamChanged = onParamChanged
        self.onPreviewUpdate = onPreviewUpdate
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    var canCommit: Bool {
        for slot in selectionSlots where slot.isRequired {
            if slot.selectedObjectId == nil { return false }
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

    func setSlotSelection(slotId: String, objectId: ObjectId?, objectName: String?) {
        guard let idx = selectionSlots.firstIndex(where: { $0.id == slotId }) else { return }
        selectionSlots[idx].selectedObjectId = objectId
        selectionSlots[idx].selectedObjectName = objectName
        if isPreviewEnabled {
            onPreviewUpdate?()
        }
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

            let def = ObjectDef.boolean(op: op, solidA: a, solidB: b)
            let newId = workspace.document.reserveId(for: def)

            // Hide target solid A; tool solid B visibility depends on keepTool
            workspace.setVisibility(a, isVisible: false)
            let keepTool = session.toggleValue(for: "keepTool") ?? false
            workspace.setVisibility(b, isVisible: keepTool)

            workspace.document.addObject(newId, def: def)
            workspace.selectedId = newId
            workspace.recomputeSolid(id: newId)
        }

        session.onCancel = { [weak workspace] in
            guard let workspace else { return }
            if workspace.viewportManager.renderer?.removeMesh(for: Self.previewSolidId) == true {
                workspace.invalidateViewport(.interaction)
            }
        }

        return session
    }
}
