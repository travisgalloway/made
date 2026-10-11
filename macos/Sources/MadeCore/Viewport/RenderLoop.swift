import Foundation

public enum InvalidateReason: String, Sendable {
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
