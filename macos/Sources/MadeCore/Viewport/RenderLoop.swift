import Foundation

public enum InvalidateReason: String, Sendable, CaseIterable {
    case camera
    case resize
    case model
    case interaction
}

/// Tracks render observability, mirroring the made runtime observability contract.
public final class RenderInstrumentation: @unchecked Sendable {
    public private(set) var renderCount: Int = 0
    public private(set) var drawCalls: Int = 0
    public private(set) var lastReason: InvalidateReason? = nil
    
    public static let shared = RenderInstrumentation()
    
    public init() {}
    
    public func recordRender(drawCalls: Int) {
        renderCount += 1
        self.drawCalls = drawCalls
    }
    
    public func recordInvalidation(reason: InvalidateReason) {
        self.lastReason = reason
    }
    
    public func reset() {
        renderCount = 0
        drawCalls = 0
        lastReason = nil
    }
}

/// Protocol for targets that can be invalidated and redrawn (e.g., MTKView or test stub).
@MainActor
public protocol ViewportInvalidationTarget: AnyObject, Sendable {
    var isMinimized: Bool { get }
    func requestRedraw()
}

/// Coordinates viewport invalidations and enforces Invariant 2 (on-demand rendering).
@MainActor
public final class ViewportCoordinator: @unchecked Sendable {
    public weak var target: (any ViewportInvalidationTarget)?
    public var onInvalidate: (@MainActor () -> Void)?
    
    public init(target: (any ViewportInvalidationTarget)? = nil) {
        self.target = target
    }
    
    public func invalidate(reason: InvalidateReason) {
        RenderInstrumentation.shared.recordInvalidation(reason: reason)
        guard let target = target else { return }
        guard !target.isMinimized else { return }
        target.requestRedraw()
        onInvalidate?()
    }
}
