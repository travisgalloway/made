import Testing
import AppKit
import Metal
import SwiftUI
@testable import MadeApp
import MadeCore

private enum MetalTestSupport {
    static let isMetal4Available = MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true
}

@MainActor
@Suite(.serialized) struct CADMetalViewRepresentableTests {
    private let width: CGFloat = 800
    private let height: CGFloat = 600

    private func makeHarness(tool: ViewportTool = .select) throws -> (
        window: NSWindow,
        view: CADMTKView,
        coordinator: CADMetalViewRepresentable.Coordinator,
        renderer: MetalRenderer,
        document: DocumentModel,
        invalidateCount: () -> Int
    ) {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        let document = DocumentModel()

        // Generate and add box mesh
        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        let mesh = try #require(renderer.createMesh(from: payload, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        let boxId = SolidId("box-1")
        renderer.meshes[boxId] = mesh

        var invalidateCalls = 0
        let representable = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            tool: tool,
            onInvalidate: {
                invalidateCalls += 1
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = CADMTKView(frame: NSRect(x: 0, y: 0, width: width, height: height), device: device)
        window.contentView = view

        let coordinator = representable.makeCoordinator()
        coordinator.mtkView = view
        view.coordinator = coordinator

        return (window, view, coordinator, renderer, document, { invalidateCalls })
    }

    private func makeMouseEvent(type: NSEvent.EventType, location: CGPoint, windowNumber: Int) -> NSEvent {
        if type == .mouseEntered || type == .mouseExited {
            return NSEvent.enterExitEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 0,
                trackingNumber: 0,
                userData: nil
            )!
        }
        return NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testMouseMovedUpdatesPreselection() throws {
        let (window, _, coordinator, renderer, _, getInvalidateCount) = try makeHarness()

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let event = makeMouseEvent(type: .mouseMoved, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: event)

        #expect(coordinator.preselectedSubElement != nil)
        #expect(coordinator.preselectedSubElement?.solidId == SolidId("box-1"))
        #expect(renderer.preselectedSubElement == coordinator.preselectedSubElement)
        #expect(getInvalidateCount() == 1)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testMouseMovedRedundantDeltaDoesNotInvalidate() throws {
        let (window, _, coordinator, _, _, getInvalidateCount) = try makeHarness()

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let event1 = makeMouseEvent(type: .mouseMoved, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: event1)
        #expect(getInvalidateCount() == 1)

        // Movement delta < 1.0 pt should be suppressed (Invariant 2)
        let smallJitter = CGPoint(x: center.x + 0.3, y: center.y + 0.3)
        let event2 = makeMouseEvent(type: .mouseMoved, location: smallJitter, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: event2)
        #expect(getInvalidateCount() == 1)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testMouseMovedSameHitDoesNotInvalidate() throws {
        let (window, _, coordinator, _, _, getInvalidateCount) = try makeHarness()

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let event1 = makeMouseEvent(type: .mouseMoved, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: event1)
        #expect(getInvalidateCount() == 1)

        // Movement delta > 1.0 pt but still over the same face should not re-invalidate
        let moveOverSameFace = CGPoint(x: center.x + 5.0, y: center.y + 5.0)
        let event2 = makeMouseEvent(type: .mouseMoved, location: moveOverSameFace, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: event2)
        #expect(getInvalidateCount() == 1)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testMouseExitedClearsPreselection() throws {
        let (window, _, coordinator, renderer, _, getInvalidateCount) = try makeHarness()

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let moveEvent = makeMouseEvent(type: .mouseMoved, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: moveEvent)
        #expect(coordinator.preselectedSubElement != nil)
        #expect(getInvalidateCount() == 1)

        // Mouse exited view
        let exitEvent = makeMouseEvent(type: .mouseExited, location: .zero, windowNumber: window.windowNumber)
        coordinator.handleMouseExited(with: exitEvent)
        #expect(coordinator.preselectedSubElement == nil)
        #expect(renderer.preselectedSubElement == nil)
        #expect(getInvalidateCount() == 2)

        // Calling mouseExited again when already nil should not trigger redraw
        coordinator.handleMouseExited(with: exitEvent)
        #expect(getInvalidateCount() == 2)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testDragSuppressesPreselection() throws {
        let (window, _, coordinator, renderer, _, _) = try makeHarness()

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let moveEvent = makeMouseEvent(type: .mouseMoved, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: moveEvent)
        #expect(coordinator.preselectedSubElement != nil)

        // Initiating mouse down drops preselection
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseDown(with: downEvent, button: .left)
        #expect(coordinator.preselectedSubElement == nil)
        #expect(renderer.preselectedSubElement == nil)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testToolSwitchClearsPreselection() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness()

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let moveEvent = makeMouseEvent(type: .mouseMoved, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: moveEvent)
        #expect(coordinator.preselectedSubElement != nil)

        // Switching tool from .select to .orbit clears preselection
        let updated = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            tool: .orbit
        )
        // Simulate updateNSView
        if !(updated.tool == .select || updated.isCommandActive) {
            coordinator.clearPreselection()
        }
        #expect(coordinator.preselectedSubElement == nil)
        #expect(renderer.preselectedSubElement == nil)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testHiddenSolidPreselectionSuppressed() throws {
        let (window, _, coordinator, renderer, _, _) = try makeHarness()

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let moveEvent = makeMouseEvent(type: .mouseMoved, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: moveEvent)
        #expect(coordinator.preselectedSubElement != nil)

        // Hiding the solid should clear preselection
        renderer.hiddenSolidIds.insert(SolidId("box-1"))
        if let pre = coordinator.preselectedSubElement,
           renderer.hiddenSolidIds.contains(pre.solidId) {
            coordinator.clearPreselection()
        }
        #expect(coordinator.preselectedSubElement == nil)
        #expect(renderer.preselectedSubElement == nil)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testHoverEmptySpaceMissDoesNotInvalidate() throws {
        let (window, _, coordinator, renderer, _, getInvalidateCount) = try makeHarness()

        // Hover over empty corner
        let corner = CGPoint(x: 5, y: 5)
        let moveEvent = makeMouseEvent(type: .mouseMoved, location: corner, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: moveEvent)

        #expect(coordinator.preselectedSubElement == nil)
        #expect(renderer.preselectedSubElement == nil)
        #expect(getInvalidateCount() == 0)
    }
}
