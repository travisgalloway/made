import SwiftUI
import MetalKit
import MadeCore

#if os(macOS)
import AppKit

extension MTKView: ViewportInvalidationTarget {
    public var isMinimized: Bool {
        return window?.isMiniaturized ?? false
    }
    
    public func requestRedraw() {
        self.setNeedsDisplay(self.bounds)
    }
}

enum MouseButton: Int {
    case left = 0
    case right = 1
    case other = 2
    
    var pointerId: Int {
        rawValue
    }
    
    var pointerButton: ViewportPointerButton {
        switch self {
        case .left: return .primary
        case .right: return .secondary
        case .other: return .middle
        }
    }
}

final class CADMTKView: MTKView {
    weak var coordinator: CADMetalViewRepresentable.Coordinator?
    private var trackingArea: NSTrackingArea?
    
    var tool: ViewportTool = .select {
        didSet {
            if oldValue != tool { window?.invalidateCursorRects(for: self) }
        }
    }
    
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    static func cursor(for tool: ViewportTool) -> NSCursor {
        switch tool {
        case .select: return .arrow
        case .orbit: return .crosshair
        case .pan: return .openHand
        case .zoom: return .resizeUpDown
        case .trim: return .crosshair
        case .rectangle: return .crosshair
        }
    }
    
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.cursor(for: tool))
    }
    
    // AppKit does not re-evaluate cursor rects mid-drag, so the drag cursor is set directly.
    func beginDragCursor(for action: ViewportDragAction) {
        if action == .pan { NSCursor.closedHand.set() }
    }
    
    func endDragCursor() {
        Self.cursor(for: tool).set()
    }
    
    override func keyDown(with event: NSEvent) {
        if coordinator?.handleKeyDown(with: event) != true {
            super.keyDown(with: event)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        coordinator?.handleMouseDown(with: event, button: .left)
    }
    
    override func mouseDragged(with event: NSEvent) {
        coordinator?.handleMouseDragged(with: event, button: .left)
    }
    
    override func mouseUp(with event: NSEvent) {
        coordinator?.handleMouseUp(with: event, button: .left)
    }
    
    override func rightMouseDown(with event: NSEvent) {
        coordinator?.handleMouseDown(with: event, button: .right)
    }
    
    override func rightMouseDragged(with event: NSEvent) {
        coordinator?.handleMouseDragged(with: event, button: .right)
    }
    
    override func rightMouseUp(with event: NSEvent) {
        coordinator?.handleMouseUp(with: event, button: .right)
    }
    
    override func otherMouseDown(with event: NSEvent) {
        coordinator?.handleMouseDown(with: event, button: .other)
    }
    
    override func otherMouseDragged(with event: NSEvent) {
        coordinator?.handleMouseDragged(with: event, button: .other)
    }
    
    override func otherMouseUp(with event: NSEvent) {
        coordinator?.handleMouseUp(with: event, button: .other)
    }
    
    override func scrollWheel(with event: NSEvent) {
        coordinator?.handleScrollWheel(with: event)
    }
    
    override func magnify(with event: NSEvent) {
        coordinator?.handleMagnify(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        coordinator?.handleMouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        coordinator?.handleMouseExited(with: event)
    }
}

public struct CADMetalViewRepresentable: NSViewRepresentable {
    @Bindable var document: DocumentModel
    var renderer: MetalRenderer
    var selectedId: ObjectId?
    var selectedSubElement: SelectedSubElement?
    var tool: ViewportTool
    var showsGrid: Bool
    var showsAxes: Bool
    var showsGizmo: Bool
    var showsEdges: Bool
    var displayMode: DisplayMode
    var selectionFilter: SelectionFilter
    var navigationPreset: NavigationPreset
    var coordinatorBinding: Binding<Coordinator?>?
    var isCommandActive: Bool
    var onCancelCommand: (() -> Void)?
    var onCommitCommand: (() -> Void)?
    var onSelectObjectForCommand: ((ObjectId) -> Void)?
    var onInvalidate: (() -> Void)?
    var onSnapChanged: ((SnapResult?) -> Void)?
    var onToolShortcut: ((ViewportTool) -> Void)?
    var onResetView: (() -> Void)?
    var onCommitParam: ((ObjectId, String, Float) -> Void)?
    var onDoubleTapFace: ((SolidId, Int) -> Void)?
    var onCancelAnimation: (() -> Void)?
    var activeSketchPlane: SketchPlane?
    var sketchEntities: [SketchEntity]
    var sketchRegions: [SketchRegion]
    var onHoverSketchRegion: ((UUID?) -> Void)?
    var onSelectSketchRegion: ((UUID) -> Void)?
    var onTrimClick: ((SIMD2<Double>) -> Void)?
    var onTrimDrag: (([SIMD2<Double>]) -> Void)?
    var activeSketchFeatureId: UUID?
    var onSketchDragStart: ((UUID, UUID) -> Void)?
    var onSketchDragUpdate: ((UUID, DragTarget) -> Void)?
    var onSketchDragEnd: ((UUID) -> Void)?
    var activeRectangleKind: SketchRectangleKind
    var onRectangleCompleted: ((SIMD2<Double>, SIMD2<Double>) -> Void)?
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer,
        selectedId: ObjectId? = nil,
        selectedSubElement: SelectedSubElement? = nil,
        tool: ViewportTool = .select,
        selectionFilter: SelectionFilter = .all,
        showsGrid: Bool = true,
        showsAxes: Bool = true,
        showsGizmo: Bool = true,
        showsEdges: Bool = true,
        displayMode: DisplayMode = .shadedWithEdges,
        navigationPreset: NavigationPreset = .defaultPreset,
        coordinator: Binding<Coordinator?>? = nil,
        isCommandActive: Bool = false,
        onCancelCommand: (() -> Void)? = nil,
        onCommitCommand: (() -> Void)? = nil,
        onSelectObjectForCommand: ((ObjectId) -> Void)? = nil,
        onInvalidate: (() -> Void)? = nil,
        onSnapChanged: ((SnapResult?) -> Void)? = nil,
        onToolShortcut: ((ViewportTool) -> Void)? = nil,
        onResetView: (() -> Void)? = nil,
        onCommitParam: ((ObjectId, String, Float) -> Void)? = nil,
        onDoubleTapFace: ((SolidId, Int) -> Void)? = nil,
        onCancelAnimation: (() -> Void)? = nil,
        activeSketchPlane: SketchPlane? = nil,
        sketchEntities: [SketchEntity] = [],
        sketchRegions: [SketchRegion] = [],
        onHoverSketchRegion: ((UUID?) -> Void)? = nil,
        onSelectSketchRegion: ((UUID) -> Void)? = nil,
        onTrimClick: ((SIMD2<Double>) -> Void)? = nil,
        onTrimDrag: (([SIMD2<Double>]) -> Void)? = nil,
        activeSketchFeatureId: UUID? = nil,
        onSketchDragStart: ((UUID, UUID) -> Void)? = nil,
        onSketchDragUpdate: ((UUID, DragTarget) -> Void)? = nil,
        onSketchDragEnd: ((UUID) -> Void)? = nil,
        activeRectangleKind: SketchRectangleKind = .corner,
        onRectangleCompleted: ((SIMD2<Double>, SIMD2<Double>) -> Void)? = nil
    ) {
        self.document = document
        self.renderer = renderer
        self.selectedId = selectedId
        self.selectedSubElement = selectedSubElement
        self.tool = tool
        self.selectionFilter = selectionFilter
        self.showsGrid = showsGrid
        self.showsAxes = showsAxes
        self.showsGizmo = showsGizmo
        self.showsEdges = showsEdges
        self.displayMode = displayMode
        self.navigationPreset = navigationPreset
        self.coordinatorBinding = coordinator
        self.isCommandActive = isCommandActive
        self.onCancelCommand = onCancelCommand
        self.onCommitCommand = onCommitCommand
        self.onSelectObjectForCommand = onSelectObjectForCommand
        self.onInvalidate = onInvalidate
        self.onSnapChanged = onSnapChanged
        self.onToolShortcut = onToolShortcut
        self.onResetView = onResetView
        self.onCommitParam = onCommitParam
        self.onDoubleTapFace = onDoubleTapFace
        self.onCancelAnimation = onCancelAnimation
        self.activeSketchPlane = activeSketchPlane
        self.sketchEntities = sketchEntities
        self.sketchRegions = sketchRegions
        self.onHoverSketchRegion = onHoverSketchRegion
        self.onSelectSketchRegion = onSelectSketchRegion
        self.onTrimClick = onTrimClick
        self.onTrimDrag = onTrimDrag
        self.activeSketchFeatureId = activeSketchFeatureId
        self.onSketchDragStart = onSketchDragStart
        self.onSketchDragUpdate = onSketchDragUpdate
        self.onSketchDragEnd = onSketchDragEnd
        self.activeRectangleKind = activeRectangleKind
        self.onRectangleCompleted = onRectangleCompleted
    }
    
    public func makeCoordinator() -> Coordinator {
        let coord = Coordinator(self)
        coordinatorBinding?.wrappedValue = coord
        return coord
    }
    
    public func makeNSView(context: Context) -> MTKView {
        let view = CADMTKView()
        view.coordinator = context.coordinator
        view.tool = tool
        view.device = renderer.device
        view.delegate = renderer
        
        // Invariant 2: On-demand rendering (no continuous rAF loop)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        
        context.coordinator.mtkView = view
        coordinatorBinding?.wrappedValue = context.coordinator
        
        renderer.onFrameRendered = { [weak coordinator = context.coordinator] in
            Task { @MainActor in
                coordinator?.handleFrameRendered()
            }
        }
        let activeSelectedId = selectedId ?? document.selectedId
        let activeSelectedIds = selectedId.map { [$0] } ?? document.selectedIds
        let activeSubElement = selectedSubElement ?? document.selectedSubElement
        renderer.selectedId = activeSelectedId
        renderer.selectedIds = activeSelectedIds
        renderer.selectedSubElement = activeSubElement
        renderer.preselectedSubElement = context.coordinator.preselectedSubElement
        let isLocked = document.objects.first(where: { $0.id == activeSelectedId })?.isLocked ?? false
        renderer.showsGrid = showsGrid
        renderer.showsAxes = showsAxes
        renderer.showsEdges = showsEdges
        renderer.displayMode = displayMode
        renderer.showsGizmo = showsGizmo && !isLocked && activeSelectedIds.count <= 1
        if activeSketchPlane != nil || !sketchEntities.isEmpty {
            renderer.updateSketch(plane: activeSketchPlane, entities: sketchEntities)
        }
        return view
    }
    
    public func update(view: MTKView?, coordinator: Coordinator) {
        // The coordinator outlives this struct, so refresh its copy to pick up the current tool and callbacks.
        coordinator.parent = self
        (view as? CADMTKView)?.tool = tool
        
        // Tool transition, filter restriction, or object deletion/hiding clears preselection highlight
        if !(tool == .select || isCommandActive) {
            coordinator.clearPreselection()
        } else if let pre = coordinator.preselectedSubElement {
            let filterAllows: Bool
            switch pre.elementType {
            case .face: filterAllows = selectionFilter.allowsFaces
            case .edge: filterAllows = selectionFilter.allowsEdges
            case .vertex: filterAllows = selectionFilter.allowsVertices
            }
            if !filterAllows || !document.objects.contains(where: { $0.id == pre.solidId }) || renderer.hiddenSolidIds.contains(pre.solidId) {
                coordinator.clearPreselection()
            }
        }
        
        if !selectionFilter.allowsSketchEntities && coordinator.activeSnapResult != nil {
            coordinator.clearPreselection()
        }
        
        // Abort gizmo drag if the selected object was removed from the document or locked
        if let drag = coordinator.dragState {
            if let obj = document.objects.first(where: { $0.id == drag.selectedId }), obj.isLocked {
                coordinator.abortGizmoDrag()
            } else if !document.objects.contains(where: { $0.id == drag.selectedId }) {
                coordinator.abortGizmoDrag()
            }
        }
        
        let isLocked = document.objects.first(where: { $0.id == selectedId })?.isLocked ?? false
        let targetSelectedIds = selectedId.map { [$0] } ?? document.selectedIds
        let effectiveGizmo = showsGizmo && !isLocked && targetSelectedIds.count <= 1
        var needsInvalidate = false
        if renderer.selectedId != selectedId || renderer.selectedIds != targetSelectedIds || renderer.selectedSubElement != selectedSubElement {
            renderer.selectedId = selectedId
            renderer.selectedIds = targetSelectedIds
            renderer.selectedSubElement = selectedSubElement
            needsInvalidate = true
        }
        if renderer.showsGrid != showsGrid {
            renderer.showsGrid = showsGrid
            needsInvalidate = true
        }
        if renderer.activeSketchPlane != activeSketchPlane || renderer.activeSketchEntities != sketchEntities {
            renderer.updateSketch(plane: activeSketchPlane, entities: sketchEntities)
            needsInvalidate = true
        }
        if renderer.showsAxes != showsAxes {
            renderer.showsAxes = showsAxes
            needsInvalidate = true
        }
        if renderer.showsEdges != showsEdges {
            renderer.showsEdges = showsEdges
            needsInvalidate = true
        }
        if renderer.displayMode != displayMode {
            renderer.displayMode = displayMode
            needsInvalidate = true
        }
        if renderer.showsGizmo != effectiveGizmo {
            renderer.showsGizmo = effectiveGizmo
            needsInvalidate = true
        }
        if needsInvalidate {
            coordinator.invalidate(reason: .interaction)
        }
        if coordinatorBinding?.wrappedValue !== coordinator {
            DispatchQueue.main.async {
                coordinatorBinding?.wrappedValue = coordinator
            }
        }
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        update(view: nsView, coordinator: context.coordinator)
    }
    
    @MainActor
    public class Coordinator: NSObject, @unchecked Sendable {
        var parent: CADMetalViewRepresentable
        weak var mtkView: MTKView? {
            didSet {
                viewportCoordinator.target = mtkView
            }
        }
        public let viewportCoordinator = ViewportCoordinator()
        public let pointerRouter = PointerRouter()
        public var dragState: GizmoDragState? = nil
        public var activeOrbitPivot: SIMD3<Float>? = nil
        public private(set) var preselectedSubElement: SelectedSubElement? = nil
        private var lastHoverLocation: CGPoint? = nil
        
        private var lastMousePoint: CGPoint = .zero
        private var activeMouseButton: MouseButton? = nil
        private var activeDragAction: ViewportDragAction? = nil
        private var isShiftDown: Bool = false
        public private(set) var activeSnapResult: SnapResult? = nil
        private var trimStrokePoints: [SIMD2<Double>] = []
        private var trimMouseDownLocation: CGPoint = .zero
        private var rectangleMouseDownLocation: CGPoint = .zero
        private var rectangleStartUV: SIMD2<Double>?

        public struct SketchDragState {
            public var featureId: UUID
            public var entityId: UUID
            public var endpoint: DragTarget.EndpointTarget?
            public var initialEntity: SketchEntity
            public var startUV: SIMD2<Double>
            public var hasMoved: Bool = false
        }
        public private(set) var sketchDragState: SketchDragState?

        public func unprojectToSketchPlane(loc: CGPoint, in view: MTKView) -> SIMD2<Double>? {
            guard let plane = parent.activeSketchPlane,
                  let ray = unprojectCursorRay(at: loc, in: view) else { return nil }
            let normal = SIMD3<Double>(Double(plane.normal.x), Double(plane.normal.y), Double(plane.normal.z))
            let rayDir = SIMD3<Double>(Double(ray.direction.x), Double(ray.direction.y), Double(ray.direction.z))
            let rayOrig = SIMD3<Double>(Double(ray.origin.x), Double(ray.origin.y), Double(ray.origin.z))
            let planeOrig = SIMD3<Double>(Double(plane.origin.x), Double(plane.origin.y), Double(plane.origin.z))
            let denom = simd_dot(rayDir, normal)
            guard abs(denom) > 1e-6 else { return nil }
            let t = simd_dot(planeOrig - rayOrig, normal) / denom
            guard t > 0 else { return nil }
            let p3D = rayOrig + t * rayDir
            let delta = p3D - planeOrig
            let xAxis = SIMD3<Double>(Double(plane.xAxis.x), Double(plane.xAxis.y), Double(plane.xAxis.z))
            let u = simd_dot(delta, xAxis)
            let yAxis = simd_normalize(simd_cross(normal, xAxis))
            let v = simd_dot(delta, yAxis)
            return SIMD2<Double>(u, v)
        }
        
        init(_ parent: CADMetalViewRepresentable) {
            self.parent = parent
            super.init()
            viewportCoordinator.onInvalidate = { [weak self] in
                self?.parent.onInvalidate?()
            }
        }
        
        public func invalidate(reason: InvalidateReason) {
            viewportCoordinator.invalidate(reason: reason)
        }
        
        func handleFrameRendered() {
            parent.onInvalidate?()
        }
        
        func handleMouseDown(with event: NSEvent, button: MouseButton) {
            clearPreselection()
            parent.onCancelAnimation?()
            guard let view = mtkView else { return }
            let loc = view.convert(event.locationInWindow, from: nil)
            lastMousePoint = loc
            activeMouseButton = button
            isShiftDown = event.modifierFlags.contains(.shift)
            
            if button == .left && parent.tool == .trim {
                trimMouseDownLocation = loc
                trimStrokePoints.removeAll()
                if let uv = unprojectToSketchPlane(loc: loc, in: view) {
                    trimStrokePoints.append(uv)
                }
            }

            if button == .left && parent.tool == .rectangle {
                rectangleMouseDownLocation = loc
                rectangleStartUV = unprojectToSketchPlane(loc: loc, in: view)
            }
            
            let pointer = ArbiterPointer(pointerId: button.pointerId, x: Float(loc.x), y: Float(loc.y))
            let pType = pointerType(for: event)
            
            // Gizmo handle hit-test on primary/left button under select tool or pen
            if parent.showsGizmo && button == .left && (parent.tool == .select || pType == .pen),
               let selectedId = parent.document.selectedId,
               let selectedObj = parent.document.objects.first(where: { $0.id == selectedId }),
               !selectedObj.isLocked,
               let mesh = parent.renderer.meshes[selectedId],
               !parent.renderer.hiddenSolidIds.contains(selectedId) {
                let aspect = Float(max(1.0, view.bounds.width) / max(1.0, view.bounds.height))
                let matrices = parent.renderer.viewAndProjectionMatrices(aspect: aspect)
                let pointerPt = SIMD2<Float>(Float(loc.x), Float(loc.y))
                let isTouch = (pType == .touch)
                
                if let hit = gizmoHitTestAtPointer(
                    pointer: pointerPt,
                    isTouch: isTouch,
                    gizmoCenter: mesh.transform.position,
                    arrowLength: defaultGizmoArrowLength,
                    ringRadius: defaultGizmoRingRadius,
                    tolerancePx: defaultGizmoTolerancePx,
                    viewportSize: view.bounds.size,
                    viewMatrix: matrices.view,
                    projectionMatrix: matrices.projection
                ) {
                    let testPointer = isTouch ? SIMD2<Float>(pointerPt.x, pointerPt.y + touchPickOffsetPt) : pointerPt
                    if let startRay = screenPointToRay(
                        screenPoint: testPointer,
                        viewportSize: view.bounds.size,
                        viewMatrix: matrices.view,
                        projectionMatrix: matrices.projection
                    ) {
                        let startParam: Float
                        let startRadial: SIMD3<Float>
                        if hit.handle.isTranslation {
                            startParam = closestPointParamOnAxis(
                                axisOrigin: mesh.transform.position,
                                axisDirection: hit.handle.axis,
                                rayOrigin: startRay.origin,
                                rayDirection: startRay.direction
                            ) ?? 0.0
                            startRadial = .zero
                        } else if hit.handle.isScale {
                            startParam = closestPointParamOnAxis(
                                axisOrigin: mesh.transform.position,
                                axisDirection: hit.handle.axis,
                                rayOrigin: startRay.origin,
                                rayDirection: startRay.direction
                            ) ?? defaultGizmoScaleLength
                            startRadial = .zero
                        } else {
                            startParam = 0.0
                            if let hitPlane = intersectRayPlane(
                                ray: startRay,
                                planeCenter: mesh.transform.position,
                                planeNormal: hit.handle.axis
                            ) {
                                startRadial = hitPlane - mesh.transform.position
                            } else {
                                startRadial = SIMD3<Float>(1, 0, 0)
                            }
                        }
                        
                        dragState = GizmoDragState(
                            selectedId: selectedId,
                            handle: hit.handle,
                            initialTransform: mesh.transform,
                            startPointer: pointerPt,
                            startRay: startRay,
                            startAxisParam: startParam,
                            startRadialVector: startRadial,
                            hasMoved: false
                        )
                        
                        pointerRouter.arbiter.lock(to: .manipulate)
                        parent.renderer.activeGizmoHandle = hit.handle
                        activeDragAction = .manipulate
                        _ = pointerRouter.handle(.down(pointerType: pType, pointer: pointer))
                        invalidate(reason: .interaction)
                        return
                    }
                }
            }

            // Sketch entity drag on primary/left button under select tool or pen
            if (parent.tool == .select || pType == .pen) && button == .left,
               parent.selectionFilter.allowsSketchEntities,
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control),
               let featureId = parent.activeSketchFeatureId,
               parent.activeSketchPlane != nil,
               let uv = unprojectToSketchPlane(loc: loc, in: view) {
                if let hit = SketchOperations.hitTestSketchDragTarget(
                    at: uv,
                    in: parent.sketchEntities,
                    vertexTolerance: 1.0,
                    curveTolerance: 1.0
                ) {
                    sketchDragState = SketchDragState(
                        featureId: featureId,
                        entityId: hit.entity.id,
                        endpoint: hit.endpoint,
                        initialEntity: hit.entity,
                        startUV: uv,
                        hasMoved: false
                    )
                    pointerRouter.arbiter.lock(to: .manipulate)
                    activeDragAction = .manipulate
                    parent.onSketchDragStart?(featureId, hit.entity.id)
                    _ = pointerRouter.handle(.down(pointerType: pType, pointer: pointer))
                    invalidate(reason: .interaction)
                    return
                }
            }
            
            let action = ViewportTool.dragAction(
                tool: parent.tool,
                button: button.pointerButton,
                option: event.modifierFlags.contains(.option),
                shift: isShiftDown,
                control: event.modifierFlags.contains(.control),
                command: event.modifierFlags.contains(.command),
                preset: parent.navigationPreset
            )
            activeDragAction = action
            if action == .orbit {
                activeOrbitPivot = resolveOrbitPivot(at: loc, in: view)
            }
            (view as? CADMTKView)?.beginDragCursor(for: action)
            _ = pointerRouter.handle(.down(pointerType: pType, pointer: pointer))
        }
        
        private func pointerType(for event: NSEvent) -> PointerType {
            if event.subtype == .tabletPoint || event.subtype == .tabletProximity {
                return .pen
            }
            return .mouse
        }
        
        func handleMouseDragged(with event: NSEvent, button: MouseButton) {
            clearPreselection()
            guard let view = mtkView, let action = activeDragAction else { return }
            let loc = view.convert(event.locationInWindow, from: nil)
            let pointer = ArbiterPointer(pointerId: button.pointerId, x: Float(loc.x), y: Float(loc.y))
            let pType = pointerType(for: event)
            let decision = pointerRouter.handle(.move(pointerType: pType, pointer: pointer))
            
            let deltaX = Float(loc.x - lastMousePoint.x)
            let deltaY = Float(loc.y - lastMousePoint.y)
            lastMousePoint = loc
            
            if button == .left && parent.tool == .trim {
                if let uv = unprojectToSketchPlane(loc: loc, in: view) {
                    if let last = trimStrokePoints.last {
                        if hypot(uv.x - last.x, uv.y - last.y) > 0.001 {
                            trimStrokePoints.append(uv)
                            if trimStrokePoints.count >= 2 {
                                parent.onTrimDrag?(trimStrokePoints)
                            }
                        }
                    } else {
                        trimStrokePoints.append(uv)
                    }
                }
                invalidate(reason: .interaction)
                return
            }
            
            if let _ = dragState {
                handleGizmoDrag(at: loc, in: view, isTouch: pType == .touch)
                return
            }

            if var drag = sketchDragState {
                if let uv = unprojectToSketchPlane(loc: loc, in: view) {
                    let target = DragTarget(entityId: drag.entityId, endpoint: drag.endpoint, targetPosition: uv)
                    drag.hasMoved = true
                    sketchDragState = drag
                    parent.onSketchDragUpdate?(drag.featureId, target)
                }
                invalidate(reason: .interaction)
                return
            }
            
            if decision.mode == .navigate {
                guard deltaX != 0 || deltaY != 0 else { return }
                let sensitivity: Float = 0.008
                switch action {
                case .orbit:
                    parent.renderer.camera = Camera.orbit(
                        camera: parent.renderer.camera,
                        deltaAzimuth: -deltaX * sensitivity,
                        deltaElevation: deltaY * sensitivity,
                        pivot: activeOrbitPivot ?? parent.renderer.camera.target
                    )
                case .pan:
                    parent.renderer.camera = Camera.pan(
                        camera: parent.renderer.camera,
                        deltaX: deltaX,
                        deltaY: deltaY,
                        viewportSize: view.bounds.size
                    )
                case .zoom:
                    guard deltaY != 0 else { return }
                    let ray = unprojectCursorRay(at: loc, in: view)
                    parent.renderer.camera = Camera.zoom(
                        camera: parent.renderer.camera,
                        factor: ViewportTool.zoomFactor(forDragDeltaY: deltaY),
                        cursorRay: ray
                    )
                case .manipulate:
                    return
                }
                invalidate(reason: .camera)
            } else if decision.mode == .manipulate {
                resolveSnap(at: loc, in: view)
            }
        }
        
        func handleKeyDown(with event: NSEvent) -> Bool {
            if parent.isCommandActive {
                if event.keyCode == 53 { // Esc
                    parent.onCancelCommand?()
                    return true
                }
                if event.keyCode == 36 { // Return
                    parent.onCommitCommand?()
                    return true
                }
            }

            let blocking: NSEvent.ModifierFlags = [.command, .control, .option]
            guard event.modifierFlags.intersection(blocking).isEmpty,
                  let key = event.charactersIgnoringModifiers?.lowercased().first else { return false }
            if let tool = ViewportTool.forShortcutKey(key) {
                parent.onToolShortcut?(tool)
                return true
            }
            switch key {
            case "f": fitToScene()
            case "h": parent.onResetView?()
            case "=", "+": zoomStep(zoomIn: true)
            case "-": zoomStep(zoomIn: false)
            default: return false
            }
            return true
        }
        
        /// Frames every visible solid without changing the view direction.
        public func fitToScene() {
            guard let view = mtkView,
                  let bounds = SceneBounds.of(parent.renderer.candidateMeshes()) else { return }
            let aspect = Float(max(1.0, view.bounds.width) / max(1.0, view.bounds.height))
            parent.renderer.camera = Camera.framing(camera: parent.renderer.camera, bounds: bounds, aspect: aspect)
            invalidate(reason: .camera)
        }
        
        public func zoomStep(zoomIn: Bool) {
            let factor = zoomIn ? Camera.zoomStepFactor : 1.0 / Camera.zoomStepFactor
            parent.renderer.camera = Camera.zoom(camera: parent.renderer.camera, factor: factor)
            invalidate(reason: .camera)
        }
        
        private func resolveSnap(at loc: CGPoint, in view: MTKView) {
            let aspect = Float(max(1.0, view.bounds.width) / max(1.0, view.bounds.height))
            let matrices = parent.renderer.viewAndProjectionMatrices(aspect: aspect)
            let vp = matrices.projection * matrices.view
            let candidateMeshes = parent.renderer.candidateMeshes()
            let pointer = SIMD2<Float>(Float(loc.x), Float(loc.y))
            
            var result = resolveSnapAtPointer(
                meshes: candidateMeshes,
                sketchEntities: parent.selectionFilter.allowsSketchEntities ? parent.sketchEntities : [],
                sketchPlane: parent.activeSketchPlane,
                pointer: pointer,
                viewportSize: view.bounds.size,
                viewMatrix: matrices.view,
                projectionMatrix: matrices.projection,
                gridSpacing: defaultGridSpacing,
                tolerancePx: defaultSnapTolerancePx
            )
            
            if let r = result, r.screenPoint == nil {
                let scr = projectToScreen(point: r.point, viewProjectionMatrix: vp, viewportSize: view.bounds.size)
                result = SnapResult(kind: r.kind, point: r.point, screenPoint: scr, planePoint: r.planePoint)
            }
            
            if result != activeSnapResult {
                activeSnapResult = result
                parent.renderer.activeSnap = result
                parent.onSnapChanged?(result)
                invalidate(reason: .interaction)
            }
        }
        
        private func handleGizmoDrag(at loc: CGPoint, in view: MTKView, isTouch: Bool) {
            guard var drag = dragState else { return }
            let pointerPt = SIMD2<Float>(Float(loc.x), Float(loc.y))
            let testPointer = isTouch ? SIMD2<Float>(pointerPt.x, pointerPt.y + touchPickOffsetPt) : pointerPt
            let aspect = Float(max(1.0, view.bounds.width) / max(1.0, view.bounds.height))
            let matrices = parent.renderer.viewAndProjectionMatrices(aspect: aspect)
            
            guard let currentRay = screenPointToRay(
                screenPoint: testPointer,
                viewportSize: view.bounds.size,
                viewMatrix: matrices.view,
                projectionMatrix: matrices.projection
            ) else { return }
            
            var previewTransform = drag.initialTransform
            
            if drag.handle.isTranslation {
                let axis = drag.handle.axis
                if let currentParam = closestPointParamOnAxis(
                    axisOrigin: drag.initialTransform.position,
                    axisDirection: axis,
                    rayOrigin: currentRay.origin,
                    rayDirection: currentRay.direction
                ) {
                    var deltaS = currentParam - drag.startAxisParam
                    
                    // Snapping: exclude currently dragged solid
                    let candidates = parent.renderer.candidateMeshes().filter { $0.id != drag.selectedId }
                    let snap = resolveSnapAtPointer(
                        meshes: candidates,
                        pointer: testPointer,
                        viewportSize: view.bounds.size,
                        viewMatrix: matrices.view,
                        projectionMatrix: matrices.projection,
                        gridSpacing: defaultGridSpacing,
                        tolerancePx: defaultSnapTolerancePx
                    )
                    if let snap {
                        deltaS = simd_dot(snap.point - drag.initialTransform.position, axis)
                        if snap != activeSnapResult {
                            activeSnapResult = snap
                            parent.renderer.activeSnap = snap
                            parent.onSnapChanged?(snap)
                        }
                    } else if activeSnapResult != nil {
                        activeSnapResult = nil
                        parent.renderer.activeSnap = nil
                        parent.onSnapChanged?(nil)
                    }
                    
                    let deltaT = deltaS * axis
                    previewTransform.position = drag.initialTransform.position + deltaT
                }
            } else if drag.handle.isScale {
                let axis = drag.handle.axis
                var currentParam = closestPointParamOnAxis(
                    axisOrigin: drag.initialTransform.position,
                    axisDirection: axis,
                    rayOrigin: currentRay.origin,
                    rayDirection: currentRay.direction
                ) ?? drag.startAxisParam
                
                // Snapping: exclude currently dragged solid
                let candidates = parent.renderer.candidateMeshes().filter { $0.id != drag.selectedId }
                let snap = resolveSnapAtPointer(
                    meshes: candidates,
                    pointer: testPointer,
                    viewportSize: view.bounds.size,
                    viewMatrix: matrices.view,
                    projectionMatrix: matrices.projection,
                    gridSpacing: defaultGridSpacing,
                    tolerancePx: defaultSnapTolerancePx
                )
                if let snap {
                    currentParam = simd_dot(snap.point - drag.initialTransform.position, axis)
                    if snap != activeSnapResult {
                        activeSnapResult = snap
                        parent.renderer.activeSnap = snap
                        parent.onSnapChanged?(snap)
                    }
                } else if activeSnapResult != nil {
                    activeSnapResult = nil
                    parent.renderer.activeSnap = nil
                    parent.onSnapChanged?(nil)
                }
                
                let scaleRatio = computeGizmoScale(
                    startParam: drag.startAxisParam,
                    currentParam: currentParam,
                    baseParam: defaultGizmoScaleLength
                )
                
                switch drag.handle {
                case .scaleX:
                    previewTransform.scale.x = drag.initialTransform.scale.x * scaleRatio
                case .scaleY:
                    previewTransform.scale.y = drag.initialTransform.scale.y * scaleRatio
                case .scaleZ:
                    previewTransform.scale.z = drag.initialTransform.scale.z * scaleRatio
                default:
                    break
                }
            } else {
                // Rotation handle
                let axis = drag.handle.axis
                let center = drag.initialTransform.position
                
                var currentRadial: SIMD3<Float>? = nil
                let candidates = parent.renderer.candidateMeshes().filter { $0.id != drag.selectedId }
                let snap = resolveSnapAtPointer(
                    meshes: candidates,
                    pointer: testPointer,
                    viewportSize: view.bounds.size,
                    viewMatrix: matrices.view,
                    projectionMatrix: matrices.projection,
                    gridSpacing: defaultGridSpacing,
                    tolerancePx: defaultSnapTolerancePx
                )
                if let snap {
                    currentRadial = snap.point - center
                    if snap != activeSnapResult {
                        activeSnapResult = snap
                        parent.renderer.activeSnap = snap
                        parent.onSnapChanged?(snap)
                    }
                } else {
                    if activeSnapResult != nil {
                        activeSnapResult = nil
                        parent.renderer.activeSnap = nil
                        parent.onSnapChanged?(nil)
                    }
                    if let p1 = intersectRayPlane(ray: currentRay, planeCenter: center, planeNormal: axis) {
                        currentRadial = p1 - center
                    }
                }
                
                if let rad1 = currentRadial {
                    let rad0 = drag.startRadialVector
                    let len0 = simd_length(rad0)
                    let len1 = simd_length(rad1)
                    if len0 > 1e-4 && len1 > 1e-4 {
                        let n0 = rad0 / len0
                        let n1 = rad1 / len1
                        let sinTheta = simd_dot(simd_cross(n0, n1), axis)
                        let cosTheta = simd_dot(n0, n1)
                        let theta = atan2(sinTheta, cosTheta)
                        let deltaQ = simd_quatf(angle: theta, axis: axis)
                        previewTransform.rotation = deltaQ * drag.initialTransform.rotation
                    }
                }
            }
            
            if previewTransform.position != drag.initialTransform.position ||
               previewTransform.rotation != drag.initialTransform.rotation ||
               previewTransform.scale != drag.initialTransform.scale {
                drag.hasMoved = true
            }
            self.dragState = drag
            
            _ = parent.renderer.updateTransform(previewTransform, for: drag.selectedId)
            invalidate(reason: .interaction)
        }
        
        func handleMouseUp(with event: NSEvent, button: MouseButton) {
            let pType = pointerType(for: event)
            let decision = pointerRouter.handle(.up(pointerType: pType, pointerId: button.pointerId))
            activeMouseButton = nil
            activeDragAction = nil
            activeOrbitPivot = nil
            (mtkView as? CADMTKView)?.endDragCursor()
            
            if let drag = dragState {
                if drag.hasMoved, let currentMesh = parent.renderer.meshes[drag.selectedId] {
                    if drag.handle.isScale {
                        if let obj = parent.document.objects.first(where: { $0.id == drag.selectedId }) {
                            let initScale = drag.initialTransform.scale
                            let currScale = currentMesh.transform.scale
                            let relativeScale = SIMD3<Float>(
                                abs(initScale.x) > 1e-5 ? currScale.x / initScale.x : currScale.x,
                                abs(initScale.y) > 1e-5 ? currScale.y / initScale.y : currScale.y,
                                abs(initScale.z) > 1e-5 ? currScale.z / initScale.z : currScale.z
                            )
                            let paramsToCommit = computeResizedParameters(for: obj.def, scale: relativeScale)
                            if !paramsToCommit.isEmpty {
                                var resetTransform = currentMesh.transform
                                resetTransform.scale = SIMD3<Float>(1, 1, 1)
                                _ = parent.renderer.updateTransform(resetTransform, for: drag.selectedId)
                                
                                if let onCommit = parent.onCommitParam {
                                    for (key, val) in paramsToCommit {
                                        onCommit(drag.selectedId, key, val)
                                    }
                                } else {
                                    for (key, val) in paramsToCommit {
                                        parent.document.setParam(id: drag.selectedId, key: key, value: val)
                                    }
                                }
                            } else {
                                parent.document.setTransform(id: drag.selectedId, transform: currentMesh.transform)
                            }
                        }
                    } else {
                        parent.document.setTransform(id: drag.selectedId, transform: currentMesh.transform)
                    }
                } else {
                    _ = parent.renderer.updateTransform(drag.initialTransform, for: drag.selectedId)
                }
                dragState = nil
                parent.renderer.activeGizmoHandle = nil
                if activeSnapResult != nil {
                    activeSnapResult = nil
                    parent.renderer.activeSnap = nil
                    parent.onSnapChanged?(nil)
                }
                pointerRouter.arbiter.reset()
                invalidate(reason: .interaction)
                return
            }

            if let drag = sketchDragState {
                parent.onSketchDragEnd?(drag.featureId)
                sketchDragState = nil
                pointerRouter.arbiter.reset()
                invalidate(reason: .interaction)
                return
            }
            
            if activeSnapResult != nil {
                activeSnapResult = nil
                parent.renderer.activeSnap = nil
                parent.onSnapChanged?(nil)
                invalidate(reason: .interaction)
            }
            
            if button == .left && parent.tool == .trim {
                guard let view = mtkView else { return }
                let loc = view.convert(event.locationInWindow, from: nil)
                let movement = hypot(loc.x - trimMouseDownLocation.x, loc.y - trimMouseDownLocation.y)
                if movement < 6.0 {
                    if let uv = unprojectToSketchPlane(loc: loc, in: view) {
                        parent.onTrimClick?(uv)
                    }
                }
                trimStrokePoints.removeAll()
                pointerRouter.arbiter.reset()
                invalidate(reason: .interaction)
                return
            }

            if button == .left && parent.tool == .rectangle {
                guard let view = mtkView else { return }
                let loc = view.convert(event.locationInWindow, from: nil)
                let movement = hypot(loc.x - rectangleMouseDownLocation.x, loc.y - rectangleMouseDownLocation.y)
                if movement > 2.0, let start = rectangleStartUV, let end = unprojectToSketchPlane(loc: loc, in: view) {
                    parent.onRectangleCompleted?(start, end)
                }
                rectangleStartUV = nil
                pointerRouter.arbiter.reset()
                invalidate(reason: .interaction)
                return
            }

            if button == .left && decision.mode == .manipulate {
                if parent.tool == .select || pType == .pen {
                    guard let view = mtkView else { return }
                    let loc = view.convert(event.locationInWindow, from: nil)
                    let pointer = SIMD2<Float>(Float(loc.x), Float(loc.y))

                    var hitId: SolidId? = nil
                    var selectedSub: SelectedSubElement? = nil
                    var pickedFace: (SolidId, Int)? = nil

                    if parent.selectionFilter.allowsSubElements {
                        let pickResult = parent.renderer.pickSubElement(
                            at: pointer,
                            viewportSize: view.bounds.size,
                            filter: parent.selectionFilter
                        )
                        if let pick = pickResult {
                            hitId = pick.solidId
                            selectedSub = SelectedSubElement(
                                solidId: pick.solidId,
                                elementType: pick.elementType,
                                elementId: pick.elementId,
                                deterministicId: pick.deterministicId,
                                hitPoint: pick.hitPoint
                            )
                            if pick.elementType == .face {
                                pickedFace = (pick.solidId, pick.elementId)
                            }
                        }
                    }

                    if hitId == nil && parent.selectionFilter.allowsBodies {
                        let aspect = Float(max(1.0, view.bounds.width) / max(1.0, view.bounds.height))
                        let matrices = parent.renderer.viewAndProjectionMatrices(aspect: aspect)
                        hitId = pickSolidAtPointer(
                            pointer: pointer,
                            viewportSize: view.bounds.size,
                            viewMatrix: matrices.view,
                            projectionMatrix: matrices.projection,
                            candidateMeshes: parent.renderer.candidateMeshes()
                        )
                        selectedSub = nil
                    }

                    if let plane = parent.activeSketchPlane, !parent.sketchRegions.isEmpty,
                       let ray = unprojectCursorRay(at: loc, in: view) {
                        let normal = plane.normal
                        let denom = simd_dot(ray.direction, normal)
                        if abs(denom) > 1e-6 {
                            let t = simd_dot(plane.origin - ray.origin, normal) / denom
                            if t > 0 {
                                let p3D = ray.origin + t * ray.direction
                                let delta = p3D - plane.origin
                                let u = simd_dot(delta, plane.xAxis)
                                let yAxis = simd_normalize(simd_cross(normal, plane.xAxis))
                                let v = simd_dot(delta, yAxis)
                                let uv = SIMD2<Float>(u, v)
                                if let hitRegion = parent.sketchRegions.first(where: { $0.contains(point: uv) }) {
                                    parent.onSelectSketchRegion?(hitRegion.id)
                                }
                            }
                        }
                    }

                    let isExtend = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)

                    if let hitId {
                        if isExtend {
                            parent.document.toggleSelection(solidId: hitId)
                            if parent.document.selection.count > 1 {
                                parent.document.selectedSubElement = nil
                            } else if parent.document.isSelected(solidId: hitId) {
                                parent.document.selectedSubElement = selectedSub
                            }
                        } else {
                            parent.document.selectedId = hitId
                            parent.document.selectedSubElement = selectedSub
                        }
                        if parent.isCommandActive {
                            parent.onSelectObjectForCommand?(hitId)
                        }
                    } else {
                        // Empty space click clears selection
                        parent.document.clearSelection()
                    }

                    let targetSelectedIds = parent.document.selectedIds
                    let targetSelectedId = parent.document.selectedId
                    let targetSubElement = parent.document.selectedSubElement
                    let isLocked = parent.document.objects.first(where: { $0.id == targetSelectedId })?.isLocked ?? false
                    let effectiveGizmo = parent.showsGizmo && !isLocked && targetSelectedIds.count <= 1

                    var needsInvalidate = false
                    if parent.renderer.selectedIds != targetSelectedIds || parent.renderer.selectedId != targetSelectedId || parent.renderer.selectedSubElement != targetSubElement {
                        parent.renderer.selectedIds = targetSelectedIds
                        parent.renderer.selectedId = targetSelectedId
                        parent.renderer.selectedSubElement = targetSubElement
                        needsInvalidate = true
                    }
                    if parent.renderer.showsGizmo != effectiveGizmo {
                        parent.renderer.showsGizmo = effectiveGizmo
                        needsInvalidate = true
                    }
                    if needsInvalidate {
                        invalidate(reason: .interaction)
                    }
                    if event.clickCount == 2, let (faceSolidId, faceId) = pickedFace {
                        parent.onDoubleTapFace?(faceSolidId, faceId)
                    }
                }
            }
        }

        func handleMouseMoved(with event: NSEvent) {
            guard activeMouseButton == nil, dragState == nil, activeDragAction == nil else {
                clearPreselection()
                return
            }
            guard parent.tool == .select || parent.isCommandActive else {
                clearPreselection()
                return
            }
            guard let view = mtkView else { return }
            let loc = view.convert(event.locationInWindow, from: nil)
            if let lastHover = lastHoverLocation {
                let dx = loc.x - lastHover.x
                let dy = loc.y - lastHover.y
                if hypot(dx, dy) < 1.0 {
                    return
                }
            }
            lastHoverLocation = loc

            if parent.activeSketchPlane != nil {
                resolveSnap(at: loc, in: view)
            }

            // Hit-test sketch regions on active sketch plane if present
            if let plane = parent.activeSketchPlane, !parent.sketchRegions.isEmpty {
                if let ray = unprojectCursorRay(at: loc, in: view) {
                    let normal = plane.normal
                    let denom = simd_dot(ray.direction, normal)
                    if abs(denom) > 1e-6 {
                        let t = simd_dot(plane.origin - ray.origin, normal) / denom
                        if t > 0 {
                            let p3D = ray.origin + t * ray.direction
                            let delta = p3D - plane.origin
                            let u = simd_dot(delta, plane.xAxis)
                            let yAxis = simd_normalize(simd_cross(normal, plane.xAxis))
                            let v = simd_dot(delta, yAxis)
                            let uv = SIMD2<Float>(u, v)
                            let hitRegion = parent.sketchRegions.first(where: { $0.contains(point: uv) })
                            parent.onHoverSketchRegion?(hitRegion?.id)
                        } else {
                            parent.onHoverSketchRegion?(nil)
                        }
                    } else {
                        parent.onHoverSketchRegion?(nil)
                    }
                }
            } else {
                parent.onHoverSketchRegion?(nil)
            }

            guard parent.selectionFilter.allowsSubElements else {
                if preselectedSubElement != nil || parent.renderer.preselectedSubElement != nil {
                    preselectedSubElement = nil
                    parent.renderer.preselectedSubElement = nil
                    invalidate(reason: .interaction)
                }
                return
            }

            let pointer = SIMD2<Float>(Float(loc.x), Float(loc.y))
            let pickResult = parent.renderer.pickSubElement(at: pointer, viewportSize: view.bounds.size, filter: parent.selectionFilter)
            let newPreselection = pickResult.map {
                SelectedSubElement(
                    solidId: $0.solidId,
                    elementType: $0.elementType,
                    elementId: $0.elementId,
                    deterministicId: $0.deterministicId
                )
            }
            if preselectedSubElement != newPreselection {
                preselectedSubElement = newPreselection
                parent.renderer.preselectedSubElement = newPreselection
                invalidate(reason: .interaction)
            }
        }

        func handleMouseExited(with event: NSEvent) {
            clearPreselection()
        }

        public func clearPreselection() {
            lastHoverLocation = nil
            parent.onHoverSketchRegion?(nil)
            if activeSnapResult != nil {
                activeSnapResult = nil
                parent.renderer.activeSnap = nil
                parent.onSnapChanged?(nil)
                invalidate(reason: .interaction)
            }
            if preselectedSubElement != nil || parent.renderer.preselectedSubElement != nil {
                preselectedSubElement = nil
                parent.renderer.preselectedSubElement = nil
                invalidate(reason: .interaction)
            }
        }
        
        func handleCancel(button: MouseButton) {
            _ = pointerRouter.handle(.cancel(pointerType: .mouse, pointerId: button.pointerId))
            activeMouseButton = nil
            activeDragAction = nil
            activeOrbitPivot = nil
            (mtkView as? CADMTKView)?.endDragCursor()
            
            if let drag = dragState {
                _ = parent.renderer.updateTransform(drag.initialTransform, for: drag.selectedId)
                dragState = nil
                parent.renderer.activeGizmoHandle = nil
                if activeSnapResult != nil {
                    activeSnapResult = nil
                    parent.renderer.activeSnap = nil
                    parent.onSnapChanged?(nil)
                }
                pointerRouter.arbiter.reset()
                invalidate(reason: .interaction)
                return
            }
            
            if activeSnapResult != nil {
                activeSnapResult = nil
                parent.renderer.activeSnap = nil
                parent.onSnapChanged?(nil)
                invalidate(reason: .interaction)
            }
        }
        
        public func abortGizmoDrag() {
            guard let drag = dragState else { return }
            _ = parent.renderer.removeMesh(for: drag.selectedId)
            dragState = nil
            activeOrbitPivot = nil
            parent.renderer.activeGizmoHandle = nil
            if activeSnapResult != nil {
                activeSnapResult = nil
                parent.renderer.activeSnap = nil
                parent.onSnapChanged?(nil)
            }
            pointerRouter.arbiter.reset()
            invalidate(reason: .interaction)
        }
        
        func handleScrollWheel(with event: NSEvent) {
            parent.onCancelAnimation?()
            guard let view = mtkView else { return }
            let loc = view.convert(event.locationInWindow, from: nil)
            let ray = unprojectCursorRay(at: loc, in: view)
            if event.hasPreciseScrollingDeltas {
                let dx = Float(event.scrollingDeltaX)
                let dy = Float(event.scrollingDeltaY)
                guard dx != 0 || dy != 0 else { return }
                
                let decision = pointerRouter.handle(.scroll(deltaX: dx, deltaY: dy))
                guard decision.mode == .navigate else { return }
                
                if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
                    let factor = 1.0 + dy * 0.01
                    parent.renderer.camera = Camera.zoom(camera: parent.renderer.camera, factor: factor, cursorRay: ray)
                } else {
                    // 2-finger trackpad pan
                    parent.renderer.camera = Camera.pan(
                        camera: parent.renderer.camera,
                        deltaX: dx,
                        deltaY: dy,
                        viewportSize: view.bounds.size
                    )
                }
                invalidate(reason: .camera)
            } else {
                // Mouse wheel zoom
                let dy = Float(event.deltaY)
                guard dy != 0 else { return }
                
                let decision = pointerRouter.handle(.scroll(deltaX: 0, deltaY: dy))
                guard decision.mode == .navigate else { return }
                
                let factor = 1.0 + dy * 0.05
                parent.renderer.camera = Camera.zoom(camera: parent.renderer.camera, factor: factor, cursorRay: ray)
                invalidate(reason: .camera)
            }
        }
        
        func handleMagnify(with event: NSEvent) {
            parent.onCancelAnimation?()
            let mag = Float(event.magnification)
            guard mag != 0 else { return }
            
            let factor = 1.0 + mag
            let decision = pointerRouter.handle(.magnify(factor: factor))
            guard decision.mode == .navigate else { return }
            
            guard let view = mtkView else { return }
            let loc = view.convert(event.locationInWindow, from: nil)
            let ray = unprojectCursorRay(at: loc, in: view)
            parent.renderer.camera = Camera.zoom(camera: parent.renderer.camera, factor: factor, cursorRay: ray)
            invalidate(reason: .camera)
        }
        
        public func unprojectCursorRay(at loc: CGPoint, in view: MTKView) -> Ray3D? {
            let aspect = Float(max(1.0, view.bounds.width) / max(1.0, view.bounds.height))
            let matrices = parent.renderer.viewAndProjectionMatrices(aspect: aspect)
            let pointer = SIMD2<Float>(Float(loc.x), Float(loc.y))
            return screenPointToRay(
                screenPoint: pointer,
                viewportSize: view.bounds.size,
                viewMatrix: matrices.view,
                projectionMatrix: matrices.projection
            )
        }
        
        public func resolveOrbitPivot(at loc: CGPoint, in view: MTKView) -> SIMD3<Float> {
            let ray = unprojectCursorRay(at: loc, in: view)
            let candidateMeshes = parent.renderer.candidateMeshes()
            var selectedCenter: SIMD3<Float>? = nil
            if let selectedId = parent.document.selectedId,
               let mesh = parent.renderer.meshes[selectedId],
               !parent.renderer.hiddenSolidIds.contains(selectedId) {
                let positions = mesh.candidateMesh.positions
                if !positions.isEmpty {
                    var localMin = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
                    var localMax = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
                    for pos in positions {
                        localMin = simd_min(localMin, pos)
                        localMax = simd_max(localMax, pos)
                    }
                    let localCenter = (localMin + localMax) * 0.5
                    let center4 = mesh.transform.matrix * SIMD4<Float>(localCenter, 1.0)
                    if abs(center4.w) > 1e-8 {
                        selectedCenter = SIMD3<Float>(center4.x, center4.y, center4.z) / center4.w
                    } else {
                        selectedCenter = mesh.transform.position
                    }
                } else {
                    selectedCenter = mesh.transform.position
                }
            }
            return MadeCore.resolveOrbitPivot(
                ray: ray,
                candidateMeshes: candidateMeshes,
                selectedSolidCenter: selectedCenter,
                fallbackTarget: parent.renderer.camera.target
            )
        }
    }
}

#elseif os(iOS)
import UIKit

extension MTKView: ViewportInvalidationTarget {
    public var isMinimized: Bool { false }
    
    public func requestRedraw() {
        self.setNeedsDisplay()
    }
}

public struct CADMetalViewRepresentable: UIViewRepresentable {
    @Bindable var document: DocumentModel
    var renderer: MetalRenderer
    var coordinatorBinding: Binding<Coordinator?>?
    var onInvalidate: (() -> Void)?
    var onSnapChanged: ((SnapResult?) -> Void)?
    var onCommitParam: ((ObjectId, String, Float) -> Void)?
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer,
        coordinator: Binding<Coordinator?>? = nil,
        onInvalidate: (() -> Void)? = nil,
        onSnapChanged: ((SnapResult?) -> Void)? = nil,
        onCommitParam: ((ObjectId, String, Float) -> Void)? = nil
    ) {
        self.document = document
        self.renderer = renderer
        self.coordinatorBinding = coordinator
        self.onInvalidate = onInvalidate
        self.onSnapChanged = onSnapChanged
        self.onCommitParam = onCommitParam
    }
    
    public func makeCoordinator() -> Coordinator {
        let coord = Coordinator(self)
        coordinatorBinding?.wrappedValue = coord
        return coord
    }
    
    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = renderer.device
        view.delegate = renderer
        
        // Invariant 2: On-demand rendering
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        
        // iPad Apple Pencil & Touch
        view.isMultipleTouchEnabled = true
        
        context.coordinator.mtkView = view
        coordinatorBinding?.wrappedValue = context.coordinator
        
        renderer.onFrameRendered = { [weak coordinator = context.coordinator] in
            Task { @MainActor in
                coordinator?.handleFrameRendered()
            }
        }
        renderer.selectedId = document.selectedId
        renderer.selectedIds = document.selectedIds
        return view
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        if renderer.selectedId != document.selectedId || renderer.selectedIds != document.selectedIds {
            renderer.selectedId = document.selectedId
            renderer.selectedIds = document.selectedIds
            context.coordinator.invalidate(reason: .interaction)
        }
        if coordinatorBinding?.wrappedValue !== context.coordinator {
            DispatchQueue.main.async {
                coordinatorBinding?.wrappedValue = context.coordinator
            }
        }
    }
    
    @MainActor
    public class Coordinator: NSObject, @unchecked Sendable {
        var parent: CADMetalViewRepresentable
        weak var mtkView: MTKView? {
            didSet {
                viewportCoordinator.target = mtkView
            }
        }
        public let viewportCoordinator = ViewportCoordinator()
        private let pointerRouter = PointerRouter()
        
        init(_ parent: CADMetalViewRepresentable) {
            self.parent = parent
            super.init()
            viewportCoordinator.onInvalidate = { [weak self] in
                self?.parent.onInvalidate?()
            }
        }
        
        public func invalidate(reason: InvalidateReason) {
            viewportCoordinator.invalidate(reason: reason)
        }
        
        func handleFrameRendered() {
            parent.onInvalidate?()
        }
    }
}
#endif
