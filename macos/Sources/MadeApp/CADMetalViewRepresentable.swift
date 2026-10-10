import SwiftUI
import MetalKit
import MadeCore

#if os(macOS)
import AppKit

public struct CADMetalViewRepresentable: NSViewRepresentable {
    @Bindable var document: DocumentModel
    var renderer: MetalRenderer
    var onInvalidate: (() -> Void)?
    
    public init(document: DocumentModel, renderer: MetalRenderer, onInvalidate: (() -> Void)? = nil) {
        self.document = document
        self.renderer = renderer
        self.onInvalidate = onInvalidate
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
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
        return view
    }
    
    public func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.setNeedsDisplay(nsView.bounds)
    }
    
    @MainActor
    public class Coordinator: NSObject {
        var parent: CADMetalViewRepresentable
        weak var mtkView: MTKView?
        private let pointerRouter = PointerRouter()
        
        init(_ parent: CADMetalViewRepresentable) {
            self.parent = parent
        }
        
        func invalidate(reason: InvalidateReason) {
            RenderInstrumentation.shared.recordInvalidation(reason: reason)
            mtkView?.setNeedsDisplay(mtkView?.bounds ?? .zero)
            parent.onInvalidate?()
        }
    }
}

#elseif os(iOS)
import UIKit

public struct CADMetalViewRepresentable: UIViewRepresentable {
    @Bindable var document: DocumentModel
    var renderer: MetalRenderer
    var onInvalidate: (() -> Void)?
    
    public init(document: DocumentModel, renderer: MetalRenderer, onInvalidate: (() -> Void)? = nil) {
        self.document = document
        self.renderer = renderer
        self.onInvalidate = onInvalidate
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
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
        return view
    }
    
    public func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.setNeedsDisplay()
    }
    
    @MainActor
    public class Coordinator: NSObject {
        var parent: CADMetalViewRepresentable
        weak var mtkView: MTKView?
        private let pointerRouter = PointerRouter()
        
        init(_ parent: CADMetalViewRepresentable) {
            self.parent = parent
        }
        
        func invalidate(reason: InvalidateReason) {
            RenderInstrumentation.shared.recordInvalidation(reason: reason)
            mtkView?.setNeedsDisplay()
            parent.onInvalidate?()
        }
    }
}
#endif
