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
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer,
        tool: ViewportTool = .select,
        coordinator: Binding<Coordinator?>? = nil,
        onInvalidate: (() -> Void)? = nil,
        onSnapChanged: ((SnapResult?) -> Void)? = nil,
        onToolShortcut: ((ViewportTool) -> Void)? = nil,
        onResetView: (() -> Void)? = nil
    ) {
        self.document = document
        self.renderer = renderer
        self.tool = tool
        self.coordinatorBinding = coordinator
        self.onInvalidate = onInvalidate
        self.onSnapChanged = onSnapChanged
        self.onToolShortcut = onToolShortcut
        self.onResetView = onResetView
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
        
        return view
    }
    
    public func updateNSView(_ nsView: MTKView, context: Context) {
        // The coordinator outlives this struct, so refresh its copy to pick up the current tool and callbacks.
        context.coordinator.parent = self
        (nsView as? CADMTKView)?.tool = tool
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
            
            let action = ViewportTool.dragAction(
                tool: parent.tool,
                button: button.pointerButton,
                option: event.modifierFlags.contains(.option),
                shift: isShiftDown
            )
            activeDragAction = action
            (view as? CADMTKView)?.beginDragCursor(for: action)
            
            let pointer = ArbiterPointer(pointerId: button.pointerId, x: Float(loc.x), y: Float(loc.y))
            let pType = pointerType(for: event)
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
        
        func handleMouseUp(with event: NSEvent, button: MouseButton) {
            let pType = pointerType(for: event)
            let decision = pointerRouter.handle(.up(pointerType: pType, pointerId: button.pointerId))
            activeMouseButton = nil
            activeDragAction = nil
            (mtkView as? CADMTKView)?.endDragCursor()
            
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
                }
            }
        }
        
        func handleCancel(button: MouseButton) {
            _ = pointerRouter.handle(.cancel(pointerType: .mouse, pointerId: button.pointerId))
            activeMouseButton = nil
            activeDragAction = nil
            (mtkView as? CADMTKView)?.endDragCursor()
            
            if activeSnapResult != nil {
                activeSnapResult = nil
                parent.renderer.activeSnap = nil
                parent.onSnapChanged?(nil)
                invalidate(reason: .interaction)
            }
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
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer,
        coordinator: Binding<Coordinator?>? = nil,
        onInvalidate: (() -> Void)? = nil,
        onSnapChanged: ((SnapResult?) -> Void)? = nil
    ) {
        self.document = document
        self.renderer = renderer
        self.coordinatorBinding = coordinator
        self.onInvalidate = onInvalidate
        self.onSnapChanged = onSnapChanged
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
        
        return view
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
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
