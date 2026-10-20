import Foundation

public enum GestureMode: String, Sendable, Equatable {
    case navigate
    case manipulate
}

public struct ArbiterPointer: Sendable, Equatable {
    public let pointerId: Int
    public var x: Float
    public var y: Float
    
    public init(pointerId: Int, x: Float, y: Float) {
        self.pointerId = pointerId
        self.x = x
        self.y = y
    }
}

public enum GestureEvent: Sendable {
    case down(pointer: ArbiterPointer)
    case move(pointer: ArbiterPointer)
    case up(pointerId: Int)
    case cancel(pointerId: Int)
}

public struct GestureDecision: Sendable, Equatable {
    public let mode: GestureMode?
    public let locked: Bool
    
    public static let undecided = GestureDecision(mode: nil, locked: false)
    
    public init(mode: GestureMode?, locked: Bool) {
        self.mode = mode
        self.locked = locked
    }
}

/// Pure state machine implementing Invariant 8: Navigation and editing never share a gesture.
/// Multi-finger -> navigate; single pointer -> manipulate. Locked on first movement.
public final class GestureArbiter: @unchecked Sendable {
    private var pointers: [Int: ArbiterPointer] = [:]
    private var peakConcurrent: Int = 0
    private var mode: GestureMode? = nil
    private var locked: Bool = false
    
    public var pointerCount: Int {
        pointers.count
    }
    
    public var peakConcurrentCount: Int {
        peakConcurrent
    }
    
    public init() {}
    
    public func handle(_ event: GestureEvent) -> GestureDecision {
        switch event {
        case .down(let pointer):
            pointers[pointer.pointerId] = pointer
            peakConcurrent = max(peakConcurrent, pointers.count)
            return snapshot()
            
        case .move(let pointer):
            // A stray event for a pointer that is not down must not lock or end a gesture.
            guard pointers[pointer.pointerId] != nil else { return snapshot() }
            pointers[pointer.pointerId] = pointer
            peakConcurrent = max(peakConcurrent, pointers.count)
            if !locked {
                lock()
            }
            return snapshot()
            
        case .up(let pointerId), .cancel(let pointerId):
            guard pointers.removeValue(forKey: pointerId) != nil else { return snapshot() }
            if !pointers.isEmpty {
                return snapshot()
            }
            
            // Last pointer released: if not locked yet (pure tap), lock at peak count
            if !locked {
                lock()
            }
            let decision = snapshot()
            reset()
            return decision
        }
    }
    
    public func current() -> GestureDecision {
        return snapshot()
    }
    
    public func lock(to mode: GestureMode) {
        self.mode = mode
        self.locked = true
    }
    
    private func lock() {
        mode = peakConcurrent > 1 ? .navigate : .manipulate
        locked = true
    }
    
    private func snapshot() -> GestureDecision {
        guard let mode = self.mode else { return .undecided }
        return GestureDecision(mode: mode, locked: self.locked)
    }
    
    @discardableResult
    public func removePointer(_ pointerId: Int) -> Bool {
        guard pointers.removeValue(forKey: pointerId) != nil else { return false }
        if pointers.isEmpty {
            reset()
        }
        return true
    }
    
    public func reset() {
        pointers.removeAll()
        peakConcurrent = 0
        mode = nil
        locked = false
    }
}
