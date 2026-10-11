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

public struct CADMetalViewRepresentable: NSViewRepresentable {
    @Bindable var document: DocumentModel
    var renderer: MetalRenderer
    var coordinatorBinding: Binding<Coordinator?>?
    var onInvalidate: (() -> Void)?
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer,
        coordinator: Binding<Coordinator?>? = nil,
        onInvalidate: (() -> Void)? = nil
    ) {
        self.document = document
        self.renderer = renderer
        self.coordinatorBinding = coordinator
        self.onInvalidate = onInvalidate
    }
    
    public func makeCoordinator() -> Coordinator {
        let coord = Coordinator(self)
        coordinatorBinding?.wrappedValue = coord
        return coord
    }
    
    public func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
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
    
    public init(
        document: DocumentModel,
        renderer: MetalRenderer,
        coordinator: Binding<Coordinator?>? = nil,
        onInvalidate: (() -> Void)? = nil
    ) {
        self.document = document
        self.renderer = renderer
        self.coordinatorBinding = coordinator
        self.onInvalidate = onInvalidate
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
