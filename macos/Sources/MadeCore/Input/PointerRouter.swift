import Foundation

public enum PointerType: String, Sendable, Equatable {
    case mouse
    case pen
    case touch
}

public enum RouterEvent: Sendable {
    case down(pointerType: PointerType, pointer: ArbiterPointer)
    case move(pointerType: PointerType, pointer: ArbiterPointer)
    case up(pointerType: PointerType, pointerId: Int)
    case cancel(pointerType: PointerType, pointerId: Int)
    case scroll(deltaX: Float, deltaY: Float)
    case magnify(factor: Float)
}

public let mouseClickThresholdPx: Float = 6.0

public final class PointerRouter: @unchecked Sendable {
    public let arbiter = GestureArbiter()
    private var mouseGestures: [Int: (start: (x: Float, y: Float), draggedPastThreshold: Bool)] = [:]
    
    public init() {}
    
    public func handle(_ event: RouterEvent) -> GestureDecision {
        switch event {
        case .down(let pType, let pointer):
            switch pType {
            case .pen:
                return GestureDecision(mode: .manipulate, locked: true)
            case .touch:
                return arbiter.handle(.down(pointer: pointer))
            case .mouse:
                mouseGestures[pointer.pointerId] = (start: (pointer.x, pointer.y), draggedPastThreshold: false)
                return .undecided
            }
            
        case .move(let pType, let pointer):
            switch pType {
            case .pen:
                return GestureDecision(mode: .manipulate, locked: true)
            case .touch:
                return arbiter.handle(.move(pointer: pointer))
            case .mouse:
                guard var state = mouseGestures[pointer.pointerId] else { return .undecided }
                let dx = pointer.x - state.start.x
                let dy = pointer.y - state.start.y
                if hypot(dx, dy) > mouseClickThresholdPx {
                    state.draggedPastThreshold = true
                    mouseGestures[pointer.pointerId] = state
                }
                let mode: GestureMode = state.draggedPastThreshold ? .navigate : .manipulate
                return GestureDecision(mode: mode, locked: state.draggedPastThreshold)
            }
            
        case .up(let pType, let pointerId):
            switch pType {
            case .pen:
                return GestureDecision(mode: .manipulate, locked: true)
            case .touch:
                return arbiter.handle(.up(pointerId: pointerId))
            case .mouse:
                guard let state = mouseGestures.removeValue(forKey: pointerId) else { return .undecided }
                let mode: GestureMode = state.draggedPastThreshold ? .navigate : .manipulate
                return GestureDecision(mode: mode, locked: true)
            }
            
        case .cancel(let pType, let pointerId):
            switch pType {
            case .pen:
                return GestureDecision(mode: .manipulate, locked: true)
            case .touch:
                return arbiter.handle(.cancel(pointerId: pointerId))
            case .mouse:
                guard let state = mouseGestures.removeValue(forKey: pointerId) else { return .undecided }
                let mode: GestureMode = state.draggedPastThreshold ? .navigate : .manipulate
                return GestureDecision(mode: mode, locked: true)
            }
            
        case .scroll(let dx, let dy):
            if dx == 0 && dy == 0 {
                return .undecided
            }
            return GestureDecision(mode: .navigate, locked: true)
            
        case .magnify(let factor):
            if factor == 1.0 {
                return .undecided
            }
            return GestureDecision(mode: .navigate, locked: true)
        }
    }
}
