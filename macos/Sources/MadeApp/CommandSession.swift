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
            isPreviewEnabled: false
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
            isPreviewEnabled: false
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
            isPreviewEnabled: false
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
            isPreviewEnabled: false
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

            let system = ConstraintSystem(entities: sketchData.entities, constraints: sketchData.constraints)
            if case .overConstrained = ConstraintSolver.computeDOFStatus(system: system) {
                return false
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
}
