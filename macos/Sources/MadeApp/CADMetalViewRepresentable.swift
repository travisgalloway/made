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
    
    var tool: ViewportTool = .select {
        didSet {
            if oldValue != tool { window?.invalidateCursorRects(for: self) }
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    static func cursor(for tool: ViewportTool) -> NSCursor {
        switch tool {
        case .select: return .arrow
        case .orbit: return .crosshair
        case .pan: return .openHand
        case .zoom: return .resizeUpDown
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
}

public struct CADMetalViewRepresentable: NSViewRepresentable {
    @Bindable var document: DocumentModel
    var renderer: MetalRenderer
    var tool: ViewportTool
    var coordinatorBinding: Binding<Coordinator?>?
    var onInvalidate: (() -> Void)?
    var onSnapChanged: ((SnapResult?) -> Void)?
    var onToolShortcut: ((ViewportTool) -> Void)?
    var onResetView: (() -> Void)?
    var onCommitParam: ((ObjectId, String, Float) -> Void)?
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer,
        tool: ViewportTool = .select,
        coordinator: Binding<Coordinator?>? = nil,
        onInvalidate: (() -> Void)? = nil,
        onSnapChanged: ((SnapResult?) -> Void)? = nil,
        onToolShortcut: ((ViewportTool) -> Void)? = nil,
        onResetView: (() -> Void)? = nil,
        onCommitParam: ((ObjectId, String, Float) -> Void)? = nil
    ) {
        self.document = document
        self.renderer = renderer
        self.tool = tool
        self.coordinatorBinding = coordinator
        self.onInvalidate = onInvalidate
        self.onSnapChanged = onSnapChanged
        self.onToolShortcut = onToolShortcut
        self.onResetView = onResetView
        self.onCommitParam = onCommitParam
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
        renderer.selectedId = document.selectedId
        return view
    }
    
    public func updateNSView(_ nsView: MTKView, context: Context) {
        // The coordinator outlives this struct, so refresh its copy to pick up the current tool and callbacks.
        context.coordinator.parent = self
        (nsView as? CADMTKView)?.tool = tool
        
        // Abort gizmo drag if the selected object was removed from the document
        if let drag = context.coordinator.dragState {
            if !document.objects.contains(where: { $0.id == drag.selectedId }) {
                context.coordinator.abortGizmoDrag()
            }
        }
        
        if renderer.selectedId != document.selectedId {
            renderer.selectedId = document.selectedId
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
        public let pointerRouter = PointerRouter()
        public var dragState: GizmoDragState? = nil
        
        private var lastMousePoint: CGPoint = .zero
        private var activeMouseButton: MouseButton? = nil
        private var activeDragAction: ViewportDragAction? = nil
        private var isShiftDown: Bool = false
        private var activeSnapResult: SnapResult? = nil
        
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
            guard let view = mtkView else { return }
            let loc = view.convert(event.locationInWindow, from: nil)
            lastMousePoint = loc
            activeMouseButton = button
            isShiftDown = event.modifierFlags.contains(.shift)
            
            let pointer = ArbiterPointer(pointerId: button.pointerId, x: Float(loc.x), y: Float(loc.y))
            let pType = pointerType(for: event)
            
            // Gizmo handle hit-test on primary/left button under select tool or pen
            if button == .left && (parent.tool == .select || pType == .pen),
               let selectedId = parent.document.selectedId,
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
            
            let action = ViewportTool.dragAction(
                tool: parent.tool,
                button: button.pointerButton,
                option: event.modifierFlags.contains(.option),
                shift: isShiftDown
            )
            activeDragAction = action
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
            guard let view = mtkView, let action = activeDragAction else { return }
            let loc = view.convert(event.locationInWindow, from: nil)
            let pointer = ArbiterPointer(pointerId: button.pointerId, x: Float(loc.x), y: Float(loc.y))
            let pType = pointerType(for: event)
            let decision = pointerRouter.handle(.move(pointerType: pType, pointer: pointer))
            
            let deltaX = Float(loc.x - lastMousePoint.x)
            let deltaY = Float(loc.y - lastMousePoint.y)
            lastMousePoint = loc
            
            if let _ = dragState {
                handleGizmoDrag(at: loc, in: view, isTouch: pType == .touch)
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
                        deltaElevation: deltaY * sensitivity
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
                    parent.renderer.camera = Camera.zoom(
                        camera: parent.renderer.camera,
                        factor: ViewportTool.zoomFactor(forDragDeltaY: deltaY)
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
            
            let candidateMeshes = parent.renderer.candidateMeshes()
            let pointer = SIMD2<Float>(Float(loc.x), Float(loc.y))
            
            let result = resolveSnapAtPointer(
                meshes: candidateMeshes,
                pointer: pointer,
                viewportSize: view.bounds.size,
                viewMatrix: matrices.view,
                projectionMatrix: matrices.projection,
                gridSpacing: defaultGridSpacing,
                tolerancePx: defaultSnapTolerancePx
            )
            
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
            
            if activeSnapResult != nil {
                activeSnapResult = nil
                parent.renderer.activeSnap = nil
                parent.onSnapChanged?(nil)
                invalidate(reason: .interaction)
            }
            
            if button == .left && decision.mode == .manipulate {
                if parent.tool == .select || pType == .pen {
                    guard let view = mtkView else { return }
                    let loc = view.convert(event.locationInWindow, from: nil)
                    let aspect = Float(max(1.0, view.bounds.width) / max(1.0, view.bounds.height))
                    let matrices = parent.renderer.viewAndProjectionMatrices(aspect: aspect)
                    let pointer = SIMD2<Float>(Float(loc.x), Float(loc.y))
                    let hitId = pickSolidAtPointer(
                        pointer: pointer,
                        viewportSize: view.bounds.size,
                        viewMatrix: matrices.view,
                        projectionMatrix: matrices.projection,
                        candidateMeshes: parent.renderer.candidateMeshes()
                    )
                    parent.document.selectedId = hitId
                    if parent.renderer.selectedId != hitId {
                        parent.renderer.selectedId = hitId
                        invalidate(reason: .interaction)
                    }
                }
            }
        }
        
        func handleCancel(button: MouseButton) {
            _ = pointerRouter.handle(.cancel(pointerType: .mouse, pointerId: button.pointerId))
            activeMouseButton = nil
            activeDragAction = nil
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
            guard let view = mtkView else { return }
            if event.hasPreciseScrollingDeltas {
                let dx = Float(event.scrollingDeltaX)
                let dy = Float(event.scrollingDeltaY)
                guard dx != 0 || dy != 0 else { return }
                
                let decision = pointerRouter.handle(.scroll(deltaX: dx, deltaY: dy))
                guard decision.mode == .navigate else { return }
                
                if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
                    let factor = 1.0 + dy * 0.01
                    parent.renderer.camera = Camera.zoom(camera: parent.renderer.camera, factor: factor)
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
                parent.renderer.camera = Camera.zoom(camera: parent.renderer.camera, factor: factor)
                invalidate(reason: .camera)
            }
        }
        
        func handleMagnify(with event: NSEvent) {
            let mag = Float(event.magnification)
            guard mag != 0 else { return }
            
            let factor = 1.0 + mag
            let decision = pointerRouter.handle(.magnify(factor: factor))
            guard decision.mode == .navigate else { return }
            
            parent.renderer.camera = Camera.zoom(camera: parent.renderer.camera, factor: factor)
            invalidate(reason: .camera)
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
        return view
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        if renderer.selectedId != document.selectedId {
            renderer.selectedId = document.selectedId
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
