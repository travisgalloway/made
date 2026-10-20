import Testing
import AppKit
import Metal
import simd
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

    private func makeHarness(
        tool: ViewportTool = .select,
        showsGizmo: Bool = true,
        boxWidth: Float = 40,
        boxDepth: Float = 30,
        boxHeight: Float = 20,
        selectionFilter: SelectionFilter = .all,
        document: DocumentModel = DocumentModel(),
        activeSketchPlane: SketchPlane? = nil,
        sketchEntities: [SketchEntity] = [],
        activeSketchFeatureId: UUID? = nil,
        onSketchDragStart: ((UUID, UUID) -> Void)? = nil,
        onSketchDragEnd: ((UUID) -> Void)? = nil,
        isRadialMenuOpen: Bool = false,
        onOpenRadialMenu: ((CGPoint, ObjectId?) -> Void)? = nil,
        onDismissRadialMenu: (() -> Void)? = nil
    ) throws -> (
        window: NSWindow,
        view: CADMTKView,
        coordinator: CADMetalViewRepresentable.Coordinator,
        renderer: MetalRenderer,
        document: DocumentModel,
        invalidateCount: () -> Int
    ) {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))

        // Generate and add box mesh
        let payload = NativeGeometryGenerator.generateBox(width: boxWidth, depth: boxDepth, height: boxHeight)
        let boxId = SolidId("box-1")
        let mesh = try #require(renderer.createMesh(from: payload, solidId: boxId, color: SIMD4<Float>(0.4, 0.6, 0.9, 1.0)))
        renderer.meshes[boxId] = mesh
        renderer.selectedId = document.selectedId
        renderer.selectedIds = document.selectedIds

        var invalidateCalls = 0
        let representable = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            tool: tool,
            selectionFilter: selectionFilter,
            showsGizmo: showsGizmo,
            onInvalidate: {
                invalidateCalls += 1
            },
            activeSketchPlane: activeSketchPlane,
            sketchEntities: sketchEntities,
            activeSketchFeatureId: activeSketchFeatureId,
            onSketchDragStart: onSketchDragStart,
            onSketchDragEnd: onSketchDragEnd,
            isRadialMenuOpen: isRadialMenuOpen,
            onOpenRadialMenu: onOpenRadialMenu,
            onDismissRadialMenu: onDismissRadialMenu
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

    private func makeMouseEvent(
        type: NSEvent.EventType,
        location: CGPoint,
        windowNumber: Int,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        if type == .mouseEntered || type == .mouseExited {
            return NSEvent.enterExitEvent(
                with: type,
                location: location,
                modifierFlags: modifierFlags,
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
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: (type == .leftMouseDown || type == .leftMouseUp || type == .rightMouseDown || type == .rightMouseUp) ? 1 : 0,
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

    // MARK: - Selection Filter Tests (BL-SEL-06)

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testMouseMovedWithBodyFilterSuppressesPreselection() throws {
        let (window, _, coordinator, renderer, _, getInvalidateCount) = try makeHarness(selectionFilter: .bodies)

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let event = makeMouseEvent(type: .mouseMoved, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: event)

        #expect(coordinator.preselectedSubElement == nil)
        #expect(renderer.preselectedSubElement == nil)
        #expect(getInvalidateCount() == 0)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testMouseMovedEdgeFilterAllowsPreselection() throws {
        let (window, _, coordinator, renderer, _, _) = try makeHarness(selectionFilter: .edges)

        let payload = NativeGeometryGenerator.generateBox(width: 40, depth: 30, height: 20)
        guard let cornerVertex = payload.vertexPoints.first else {
            Issue.record("No vertex points")
            return
        }
        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = simd_mul(matrices.projection, matrices.view)
        let clip = simd_mul(vp, SIMD4<Float>(cornerVertex.position, 1.0))
        let screenX = (clip.x / clip.w * 0.5 + 0.5) * Float(width)
        let screenY = (1.0 - (clip.y / clip.w * 0.5 + 0.5)) * Float(height)
        let cornerPt = CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))

        let event = makeMouseEvent(type: .mouseMoved, location: cornerPt, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: event)

        #expect(coordinator.preselectedSubElement != nil)
        #expect(coordinator.preselectedSubElement?.elementType == .edge)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testMouseUpWithBodiesFilterSelectsSolidWithoutSubElement() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness(selectionFilter: .bodies)
        document.selectedId = nil
        renderer.selectedId = nil
        #expect(document.selectedId == nil)

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseDown(with: downEvent, button: .left)

        let upEvent = makeMouseEvent(type: .leftMouseUp, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseUp(with: upEvent, button: .left)

        #expect(document.selectedId == ObjectId("box-1"))
        #expect(document.selectedSubElement == nil)
        #expect(renderer.selectedId == SolidId("box-1"))
        #expect(renderer.selectedSubElement == nil)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testFilterChangeClearsInvalidPreselection() throws {
        let (window, _, coordinator, renderer, document, getInvalidateCount) = try makeHarness(selectionFilter: .all)

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let moveEvent = makeMouseEvent(type: .mouseMoved, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: moveEvent)

        #expect(coordinator.preselectedSubElement != nil)
        #expect(coordinator.preselectedSubElement?.elementType == .face)
        let initialInvalidateCount = getInvalidateCount()
        #expect(initialInvalidateCount >= 1)

        // 1. Changing to a filter that STILL allows faces (.faces) does NOT clear preselection or re-invalidate
        let representableWithFaces = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            tool: .select,
            selectionFilter: .faces
        )
        if !(representableWithFaces.tool == .select || representableWithFaces.isCommandActive) {
            coordinator.clearPreselection()
        } else if let pre = coordinator.preselectedSubElement {
            let filterAllows: Bool
            switch pre.elementType {
            case .face: filterAllows = representableWithFaces.selectionFilter.allowsFaces
            case .edge: filterAllows = representableWithFaces.selectionFilter.allowsEdges
            case .vertex: filterAllows = representableWithFaces.selectionFilter.allowsVertices
            }
            if !filterAllows {
                coordinator.clearPreselection()
            }
        }
        #expect(coordinator.preselectedSubElement != nil)
        #expect(getInvalidateCount() == initialInvalidateCount, "Compatible filter change must not invalidate (Invariant 2)")

        // 2. Changing to a filter that EXCLUDES faces (.edges) immediately clears preselection and invalidates once
        let representableWithEdges = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            tool: .select,
            selectionFilter: .edges
        )
        if !(representableWithEdges.tool == .select || representableWithEdges.isCommandActive) {
            coordinator.clearPreselection()
        } else if let pre = coordinator.preselectedSubElement {
            let filterAllows: Bool
            switch pre.elementType {
            case .face: filterAllows = representableWithEdges.selectionFilter.allowsFaces
            case .edge: filterAllows = representableWithEdges.selectionFilter.allowsEdges
            case .vertex: filterAllows = representableWithEdges.selectionFilter.allowsVertices
            }
            if !filterAllows {
                coordinator.clearPreselection()
            }
        }
        #expect(coordinator.preselectedSubElement == nil)
        #expect(renderer.preselectedSubElement == nil)
        #expect(getInvalidateCount() == initialInvalidateCount + 1, "Incompatible filter change must invalidate once (Invariant 2)")
    }

    // MARK: - Representable Selection Sync (BL-SEL-10 / #342)

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testRepresentableSelectionChangeUpdatesRendererAndInvalidates() throws {
        let (_, view, coordinator, renderer, document, getInvalidateCount) = try makeHarness()
        renderer.selectedId = nil
        document.selectedId = nil
        let initialInvalidateCount = getInvalidateCount()

        let cylId = ObjectId("cylinder-1")
        let updatedRepresentable = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            selectedId: cylId,
            selectedSubElement: nil,
            onInvalidate: coordinator.parent.onInvalidate
        )
        updatedRepresentable.update(view: view, coordinator: coordinator)

        #expect(renderer.selectedId == SolidId("cylinder-1"))
        #expect(renderer.selectedSubElement == nil)
        #expect(getInvalidateCount() == initialInvalidateCount + 1)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testRepresentableIdenticalSelectionDoesNotInvalidate() throws {
        let (_, view, coordinator, renderer, document, getInvalidateCount) = try makeHarness()
        let boxId = ObjectId("box-1")
        renderer.selectedId = boxId
        document.selectedId = boxId
        let initialInvalidateCount = getInvalidateCount()

        let sameRepresentable = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            selectedId: boxId,
            selectedSubElement: nil,
            onInvalidate: coordinator.parent.onInvalidate
        )
        sameRepresentable.update(view: view, coordinator: coordinator)

        #expect(renderer.selectedId == SolidId("box-1"))
        #expect(getInvalidateCount() == initialInvalidateCount, "Re-evaluating with identical selection must not invalidate (Invariant 2)")
    }

    // MARK: - Representable Sketch Entity Sync (REQ-f0dd0a1a / #558)

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testRepresentableSketchEntityUpdatesForwardToRendererAndInvalidate() throws {
        let (_, view, coordinator, renderer, document, getInvalidateCount) = try makeHarness(sketchEntities: [])
        let initialInvalidateCount = getInvalidateCount()

        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(30, 30), isConstruction: true)
        let updatedRepresentable = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            onInvalidate: coordinator.parent.onInvalidate,
            activeSketchPlane: .xy,
            sketchEntities: [line]
        )
        updatedRepresentable.update(view: view, coordinator: coordinator)

        #expect(renderer.activeSketchEntities == [line])
        #expect(renderer.sketchRenderItems.count == 1)
        #expect(renderer.sketchRenderItems[0].dashFlag == true)
        #expect(getInvalidateCount() == initialInvalidateCount + 1)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testRepresentableIdenticalSketchEntitiesDoesNotInvalidate() throws {
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(20, 20), isConstruction: false)
        let (_, view, coordinator, renderer, document, getInvalidateCount) = try makeHarness(
            activeSketchPlane: .xy,
            sketchEntities: [line]
        )
        renderer.updateSketch(plane: .xy, entities: [line])
        let initialInvalidateCount = getInvalidateCount()

        let sameRepresentable = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            selectedId: renderer.selectedId,
            selectedSubElement: renderer.selectedSubElement,
            onInvalidate: coordinator.parent.onInvalidate,
            activeSketchPlane: .xy,
            sketchEntities: [line]
        )
        sameRepresentable.update(view: view, coordinator: coordinator)

        #expect(renderer.activeSketchEntities == [line])
        #expect(getInvalidateCount() == initialInvalidateCount, "Re-evaluating with identical sketch entities must not invalidate (Invariant 2)")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testRepresentableSketchPlaneChangeUpdatesRendererAndInvalidates() throws {
        let line = SketchEntity.line(start: SIMD2(0, 0), end: SIMD2(10, 10))
        let (_, view, coordinator, renderer, document, getInvalidateCount) = try makeHarness(
            activeSketchPlane: .xy,
            sketchEntities: [line]
        )
        renderer.updateSketch(plane: .xy, entities: [line])
        let initialInvalidateCount = getInvalidateCount()

        let updatedRepresentable = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            onInvalidate: coordinator.parent.onInvalidate,
            activeSketchPlane: .xz,
            sketchEntities: [line]
        )
        updatedRepresentable.update(view: view, coordinator: coordinator)

        #expect(renderer.activeSketchPlane == .xz)
        #expect(getInvalidateCount() == initialInvalidateCount + 1)
    }

    // MARK: - Multi-Selection Gesture Tests (#552 / DOC-10)

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testShiftClickExtendsSelectionAndSuppressesGizmo() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness()
        let boxId = SolidId("box-1")
        let cylId = SolidId("cylinder-1")

        // Add cylinder mesh at (50, 0, 0)
        let cylPayload = NativeGeometryGenerator.generateCylinder(radius: 15, height: 40)
        let cylTransform = Transform(position: SIMD3<Float>(50, 0, 0))
        let cylMesh = try #require(renderer.createMesh(from: cylPayload, solidId: cylId, transform: cylTransform, color: SIMD4<Float>(0.9, 0.4, 0.4, 1.0)))
        renderer.meshes[cylId] = cylMesh

        // Calculate screen coordinate for cylinder center
        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = simd_mul(matrices.projection, matrices.view)
        let clip = simd_mul(vp, SIMD4<Float>(50, 0, 0, 1.0))
        let screenX = (clip.x / clip.w * 0.5 + 0.5) * Float(width)
        let screenY = (1.0 - (clip.y / clip.w * 0.5 + 0.5)) * Float(height)
        let cylCenter = CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))

        // Initial state: single box selected
        #expect(document.selectedIds == [boxId])
        #expect(renderer.showsGizmo == true)

        // Shift-click cylinder center
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: cylCenter, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDown(with: downEvent, button: .left)
        let upEvent = makeMouseEvent(type: .leftMouseUp, location: cylCenter, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseUp(with: upEvent, button: .left)

        // Verify extended multi-selection
        #expect(document.selection.count == 2)
        #expect(document.selectedIds.count == 2)
        #expect(renderer.selectedIds.count == 2)
        #expect(renderer.selectedIds.contains(boxId))
        #expect(renderer.selectedIds.contains(cylId))
        #expect(renderer.showsGizmo == false, "Gizmo must be suppressed when multiple solids are selected")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testShiftClickTogglesSelectionOff() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness()
        let boxId = SolidId("box-1")
        let cylId = SolidId("cylinder-1")

        // Add cylinder mesh at (50, 0, 0)
        let cylPayload = NativeGeometryGenerator.generateCylinder(radius: 15, height: 40)
        let cylTransform = Transform(position: SIMD3<Float>(50, 0, 0))
        let cylMesh = try #require(renderer.createMesh(from: cylPayload, solidId: cylId, transform: cylTransform, color: SIMD4<Float>(0.9, 0.4, 0.4, 1.0)))
        renderer.meshes[cylId] = cylMesh

        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = simd_mul(matrices.projection, matrices.view)
        let clip = simd_mul(vp, SIMD4<Float>(50, 0, 0, 1.0))
        let screenX = (clip.x / clip.w * 0.5 + 0.5) * Float(width)
        let screenY = (1.0 - (clip.y / clip.w * 0.5 + 0.5)) * Float(height)
        let cylCenter = CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))

        // Pre-select both box and cylinder
        document.selectedIds = [boxId, cylId]
        renderer.selectedIds = [boxId, cylId]
        renderer.showsGizmo = false

        // Shift-click cylinder center to toggle it off
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: cylCenter, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDown(with: downEvent, button: .left)
        let upEvent = makeMouseEvent(type: .leftMouseUp, location: cylCenter, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseUp(with: upEvent, button: .left)

        #expect(document.selection.count == 1)
        #expect(document.isSelected(solidId: boxId))
        #expect(!document.isSelected(solidId: cylId))
        #expect(renderer.selectedIds == [boxId])
        #expect(renderer.showsGizmo == true, "Gizmo must re-enable when selection drops to single solid")
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testCommandClickExtendsSelection() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness()
        let boxId = SolidId("box-1")
        let cylId = SolidId("cylinder-1")

        let cylPayload = NativeGeometryGenerator.generateCylinder(radius: 15, height: 40)
        let cylTransform = Transform(position: SIMD3<Float>(50, 0, 0))
        let cylMesh = try #require(renderer.createMesh(from: cylPayload, solidId: cylId, transform: cylTransform, color: SIMD4<Float>(0.9, 0.4, 0.4, 1.0)))
        renderer.meshes[cylId] = cylMesh

        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = simd_mul(matrices.projection, matrices.view)
        let clip = simd_mul(vp, SIMD4<Float>(50, 0, 0, 1.0))
        let screenX = (clip.x / clip.w * 0.5 + 0.5) * Float(width)
        let screenY = (1.0 - (clip.y / clip.w * 0.5 + 0.5)) * Float(height)
        let cylCenter = CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))

        // Command-click cylinder center
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: cylCenter, windowNumber: window.windowNumber, modifierFlags: .command)
        coordinator.handleMouseDown(with: downEvent, button: .left)
        let upEvent = makeMouseEvent(type: .leftMouseUp, location: cylCenter, windowNumber: window.windowNumber, modifierFlags: .command)
        coordinator.handleMouseUp(with: upEvent, button: .left)

        #expect(document.selection.count == 2)
        #expect(renderer.selectedIds.count == 2)
        #expect(renderer.selectedIds.contains(boxId))
        #expect(renderer.selectedIds.contains(cylId))
        #expect(renderer.showsGizmo == false)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testClickOnEmptySpaceClearsSelection() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness()
        let boxId = SolidId("box-1")
        #expect(document.selectedIds == [boxId])
        #expect(renderer.selectedIds == [boxId])

        // Click on empty space corner (5, 5)
        let corner = CGPoint(x: 5, y: 5)
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: corner, windowNumber: window.windowNumber)
        coordinator.handleMouseDown(with: downEvent, button: .left)
        let upEvent = makeMouseEvent(type: .leftMouseUp, location: corner, windowNumber: window.windowNumber)
        coordinator.handleMouseUp(with: upEvent, button: .left)

        #expect(document.selection.isEmpty)
        #expect(document.selectedIds.isEmpty)
        #expect(document.selectedId == nil)
        #expect(renderer.selectedIds.isEmpty)
        #expect(renderer.selectedId == nil)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testSketchEntitiesFilterGatesDraggingAndSnapping() throws {
        let sketchPlane = SketchPlane(
            origin: SIMD3<Float>(0, 0, 0),
            normal: SIMD3<Float>(0, 0, 1),
            xAxis: SIMD3<Float>(1, 0, 0)
        )
        let featureId = UUID()
        let lineId = UUID()
        let line = SketchEntity(
            id: lineId,
            kind: "line",
            data: ["startX": 0.0, "startY": 0.0, "endX": 25.0, "endY": 25.0]
        )

        var dragStartCalls: [(UUID, UUID)] = []
        var dragEndCalls: [UUID] = []

        let document = DocumentModel()
        let (window, view, coordinator, renderer, _, _) = try makeHarness(
            selectionFilter: [.faces, .edges, .vertices, .bodies],
            document: document,
            activeSketchPlane: sketchPlane,
            sketchEntities: [line],
            activeSketchFeatureId: featureId,
            onSketchDragStart: { featId, entityId in
                dragStartCalls.append((featId, entityId))
                document.selection = [Reference.sketchEntity(featureId: featId, entityId: entityId)]
            },
            onSketchDragEnd: { featId in
                dragEndCalls.append(featId)
            }
        )

        // Clear meshes so only sketch entity candidates can be resolved for snapping
        renderer.meshes.removeAll()
        // Zoom in so grid points (10 mm spacing) exceed the 20 px snap tolerance
        renderer.camera.position = renderer.camera.target + simd_normalize(renderer.camera.position - renderer.camera.target) * 30.0

        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = simd_mul(matrices.projection, matrices.view)
        let worldPos = sketchPlane.unprojectPoint(SIMD2<Double>(25.0, 25.0))
        let screenPos = try #require(projectToScreen(point: worldPos, viewProjectionMatrix: vp, viewportSize: CGSize(width: width, height: height)))
        let endpointLocation = CGPoint(x: CGFloat(screenPos.x), y: CGFloat(screenPos.y))

        // 1. With selectionFilter excluding sketchEntities:
        // Hover over the sketch line endpoint: snap must be suppressed
        let moveEvent1 = makeMouseEvent(type: .mouseMoved, location: endpointLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: moveEvent1)
        #expect(coordinator.activeSnapResult == nil)

        // Mouse down on endpoint: sketch drag must NOT start
        let downEvent1 = makeMouseEvent(type: .leftMouseDown, location: endpointLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseDown(with: downEvent1, button: .left)
        #expect(coordinator.sketchDragState == nil)
        #expect(dragStartCalls.isEmpty)

        let upEvent1 = makeMouseEvent(type: .leftMouseUp, location: endpointLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseUp(with: upEvent1, button: .left)

        // 2. Enable sketchEntities filter (using .all)
        let enabledRepresentable = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            tool: .select,
            selectionFilter: .all,
            onInvalidate: coordinator.parent.onInvalidate,
            activeSketchPlane: sketchPlane,
            sketchEntities: [line],
            activeSketchFeatureId: featureId,
            onSketchDragStart: coordinator.parent.onSketchDragStart,
            onSketchDragEnd: coordinator.parent.onSketchDragEnd
        )
        enabledRepresentable.update(view: view, coordinator: coordinator)

        // Hover over the sketch line endpoint: snap must resolve
        let moveEvent2 = makeMouseEvent(type: .mouseMoved, location: endpointLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseMoved(with: moveEvent2)
        #expect(coordinator.activeSnapResult != nil)
        #expect(coordinator.activeSnapResult?.kind == .endpoint)
        #expect(coordinator.activeSnapResult?.planePoint == SIMD2<Double>(25.0, 25.0))

        // Mouse down on endpoint: sketch drag must start and onSketchDragStart must be called
        let downEvent2 = makeMouseEvent(type: .leftMouseDown, location: endpointLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseDown(with: downEvent2, button: .left)
        #expect(coordinator.sketchDragState != nil)
        #expect(coordinator.sketchDragState?.entityId == lineId)
        #expect(dragStartCalls.count == 1)
        #expect(dragStartCalls.first?.0 == featureId)
        #expect(dragStartCalls.first?.1 == lineId)

        // Mouse up: sketch entity selection must be preserved
        let upEvent2 = makeMouseEvent(type: .leftMouseUp, location: endpointLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseUp(with: upEvent2, button: .left)
        #expect(coordinator.sketchDragState == nil)
        #expect(dragEndCalls.count == 1)
        #expect(dragEndCalls.first == featureId)
        #expect(document.selection == [Reference.sketchEntity(featureId: featureId, entityId: lineId)])

        // Hover again to establish active snap
        coordinator.handleMouseMoved(with: moveEvent2)
        #expect(coordinator.activeSnapResult != nil)

        // 3. Update filter to exclude sketchEntities: active snap must be cleared immediately
        let disabledRepresentable = CADMetalViewRepresentable(
            document: document,
            renderer: renderer,
            tool: .select,
            selectionFilter: [.faces, .edges, .vertices, .bodies],
            onInvalidate: coordinator.parent.onInvalidate,
            activeSketchPlane: sketchPlane,
            sketchEntities: [line],
            activeSketchFeatureId: featureId,
            onSketchDragStart: coordinator.parent.onSketchDragStart,
            onSketchDragEnd: coordinator.parent.onSketchDragEnd
        )
        disabledRepresentable.update(view: view, coordinator: coordinator)
        #expect(coordinator.activeSnapResult == nil)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testSecondaryClickOnSolidOpensRadialMenuAndSelectsSolid() throws {
        var openedAt: CGPoint?
        var openedSolidId: ObjectId?

        let (window, _, coordinator, _, document, _) = try makeHarness(
            onOpenRadialMenu: { loc, solidId in
                openedAt = loc
                openedSolidId = solidId
            }
        )

        let center = CGPoint(x: width / 2.0, y: height / 2.0)
        let downEvent = makeMouseEvent(type: .rightMouseDown, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseDown(with: downEvent, button: .right)

        let upEvent = makeMouseEvent(type: .rightMouseUp, location: center, windowNumber: window.windowNumber)
        coordinator.handleMouseUp(with: upEvent, button: .right)

        #expect(openedAt != nil)
        #expect(openedSolidId == ObjectId("box-1"))
        #expect(document.selectedId == ObjectId("box-1"))
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testSecondaryClickOnEmptySpaceOpensRadialMenuWithNilSolid() throws {
        var openedAt: CGPoint?
        var openedSolidId: ObjectId?

        let (window, _, coordinator, _, document, _) = try makeHarness(
            onOpenRadialMenu: { loc, solidId in
                openedAt = loc
                openedSolidId = solidId
            }
        )

        let initialSelectedId = document.selectedId
        let emptyLocation = CGPoint(x: 50, y: 50)
        let downEvent = makeMouseEvent(type: .rightMouseDown, location: emptyLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseDown(with: downEvent, button: .right)

        let upEvent = makeMouseEvent(type: .rightMouseUp, location: emptyLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseUp(with: upEvent, button: .right)

        #expect(openedAt != nil)
        #expect(openedSolidId == nil)
        #expect(document.selectedId == initialSelectedId)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testSecondaryDragPastThresholdNavigatesAndDoesNotOpenRadialMenu() throws {
        var openMenuCalled = false

        let (window, _, coordinator, renderer, _, _) = try makeHarness(
            onOpenRadialMenu: { _, _ in
                openMenuCalled = true
            }
        )

        let startLocation = CGPoint(x: width / 2.0, y: height / 2.0)
        let initialCamera = renderer.camera

        let downEvent = makeMouseEvent(type: .rightMouseDown, location: startLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseDown(with: downEvent, button: .right)

        let dragLocation = CGPoint(x: startLocation.x + 25.0, y: startLocation.y)
        let dragEvent = makeMouseEvent(type: .rightMouseDragged, location: dragLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseDragged(with: dragEvent, button: .right)

        let upEvent = makeMouseEvent(type: .rightMouseUp, location: dragLocation, windowNumber: window.windowNumber)
        coordinator.handleMouseUp(with: upEvent, button: .right)

        #expect(!openMenuCalled)
        #expect(renderer.camera != initialCamera)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testEscapeKeyDismissesRadialMenu() throws {
        var dismissCalled = false

        let (window, _, coordinator, _, _, _) = try makeHarness(
            isRadialMenuOpen: true,
            onDismissRadialMenu: {
                dismissCalled = true
            }
        )

        let escapeEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53 // Escape
        )!

        let handled = coordinator.handleKeyDown(with: escapeEvent)
        #expect(handled)
        #expect(dismissCalled)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testShiftDragLocksDominantAxisAndCommitsOnceOnRelease() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness(boxWidth: 120, boxDepth: 100, boxHeight: 40)
        let boxId = SolidId("box-1")
        document.setTransform(id: boxId, transform: .identity)

        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = matrices.projection * matrices.view
        let surfacePt = SIMD3<Float>(-40, -30, 10)
        let screenPt = try #require(projectToScreen(point: surfacePt, viewProjectionMatrix: vp, viewportSize: CGSize(width: width, height: height)))
        let startLoc = CGPoint(x: CGFloat(screenPt.x), y: CGFloat(screenPt.y))

        // 1. Mouse down with Shift on solid body away from gizmo
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: startLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDown(with: downEvent, button: .left)

        let drag = try #require(coordinator.widgetlessDragState)
        #expect(drag.selectedId == boxId)
        #expect(coordinator.pointerRouter.arbiter.current().mode == .manipulate)

        // 2. Drag with Shift along screen X by +40 pt
        let dragLoc = CGPoint(x: startLoc.x + 40.0, y: startLoc.y)
        let dragEvent = makeMouseEvent(type: .leftMouseDragged, location: dragLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDragged(with: dragEvent, button: .left)

        let activeDrag = try #require(coordinator.widgetlessDragState)
        #expect(activeDrag.hasMoved == true)
        #expect(activeDrag.latchedAxis == .x)
        #expect(renderer.activeGizmoHandle == .translateX)

        let currentPos = try #require(renderer.meshes[boxId]?.transform.position)
        #expect(currentPos.x != 0.0, "Position X should have translated")
        #expect(abs(currentPos.y) < 1e-4, "Position Y should be strictly constrained")
        #expect(abs(currentPos.z) < 1e-4, "Position Z should be strictly constrained")

        // 3. Mouse up commits exactly once to document
        let upEvent = makeMouseEvent(type: .leftMouseUp, location: dragLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseUp(with: upEvent, button: .left)

        #expect(coordinator.widgetlessDragState == nil)
        #expect(coordinator.pointerRouter.arbiter.current().mode == nil)
        #expect(renderer.activeGizmoHandle == nil)

        let docPos = try #require(document.objects.first(where: { $0.id == boxId })?.transform.position)
        #expect(abs(docPos.x - currentPos.x) < 1e-4)
        #expect(abs(docPos.y) < 1e-4)
        #expect(abs(docPos.z) < 1e-4)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testOptionDragLocksToHorizontalGroundPlaneAndCommits() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness(boxWidth: 120, boxDepth: 100, boxHeight: 40)
        let boxId = SolidId("box-1")
        let elevatedTransform = Transform(position: SIMD3<Float>(0, 0, 15))
        document.setTransform(id: boxId, transform: elevatedTransform)
        _ = renderer.updateTransform(elevatedTransform, for: boxId)

        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = matrices.projection * matrices.view
        let surfacePt = SIMD3<Float>(-40, -30, 25)
        let screenPt = try #require(projectToScreen(point: surfacePt, viewProjectionMatrix: vp, viewportSize: CGSize(width: width, height: height)))
        let startLoc = CGPoint(x: CGFloat(screenPt.x), y: CGFloat(screenPt.y))

        // 1. Mouse down with Option on solid body
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: startLoc, windowNumber: window.windowNumber, modifierFlags: .option)
        coordinator.handleMouseDown(with: downEvent, button: .left)

        #expect(coordinator.widgetlessDragState != nil)

        // 2. Drag with Option (+35, -25)
        let dragLoc = CGPoint(x: startLoc.x + 35.0, y: startLoc.y - 25.0)
        let dragEvent = makeMouseEvent(type: .leftMouseDragged, location: dragLoc, windowNumber: window.windowNumber, modifierFlags: .option)
        coordinator.handleMouseDragged(with: dragEvent, button: .left)

        let activeDrag = try #require(coordinator.widgetlessDragState)
        #expect(activeDrag.hasMoved == true)

        let currentPos = try #require(renderer.meshes[boxId]?.transform.position)
        #expect(abs(currentPos.z - 15.0) < 1e-4, "Z elevation must remain strictly locked to initial elevation")
        #expect(currentPos.x != 0.0 || currentPos.y != 0.0, "XY translation should have occurred")

        // 3. Mouse up commits to document
        let upEvent = makeMouseEvent(type: .leftMouseUp, location: dragLoc, windowNumber: window.windowNumber, modifierFlags: .option)
        coordinator.handleMouseUp(with: upEvent, button: .left)

        #expect(coordinator.widgetlessDragState == nil)
        let docPos = try #require(document.objects.first(where: { $0.id == boxId })?.transform.position)
        #expect(abs(docPos.z - 15.0) < 1e-4)
        #expect(docPos == currentPos)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testEscapeKeyCancelsActiveWidgetlessDrag() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness(boxWidth: 120, boxDepth: 100, boxHeight: 40)
        let boxId = SolidId("box-1")
        document.setTransform(id: boxId, transform: .identity)
        let initialPos = try #require(renderer.meshes[boxId]?.transform.position)

        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = matrices.projection * matrices.view
        let surfacePt = SIMD3<Float>(-40, -30, 10)
        let screenPt = try #require(projectToScreen(point: surfacePt, viewProjectionMatrix: vp, viewportSize: CGSize(width: width, height: height)))
        let startLoc = CGPoint(x: CGFloat(screenPt.x), y: CGFloat(screenPt.y))

        // 1. Start drag
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: startLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDown(with: downEvent, button: .left)

        let dragLoc = CGPoint(x: startLoc.x + 35.0, y: startLoc.y)
        let dragEvent = makeMouseEvent(type: .leftMouseDragged, location: dragLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDragged(with: dragEvent, button: .left)

        #expect(renderer.meshes[boxId]?.transform.position != initialPos)

        // 2. Press Escape key
        let escapeEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )!

        let handled = coordinator.handleKeyDown(with: escapeEvent)
        #expect(handled)
        #expect(coordinator.widgetlessDragState == nil)
        #expect(coordinator.pointerRouter.arbiter.current().mode == nil)
        #expect(renderer.meshes[boxId]?.transform.position == initialPos)
        #expect(document.objects.first(where: { $0.id == boxId })?.transform.position == initialPos)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testZeroMovementDragDoesNotInvokeSetTransform() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness(boxWidth: 120, boxDepth: 100, boxHeight: 40)
        let boxId = SolidId("box-1")
        let initialTransform = try #require(document.objects.first(where: { $0.id == boxId })?.transform)

        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = matrices.projection * matrices.view
        let surfacePt = SIMD3<Float>(-40, -30, 10)
        let screenPt = try #require(projectToScreen(point: surfacePt, viewProjectionMatrix: vp, viewportSize: CGSize(width: width, height: height)))
        let startLoc = CGPoint(x: CGFloat(screenPt.x), y: CGFloat(screenPt.y))

        // Mouse down
        let downEvent = makeMouseEvent(type: .leftMouseDown, location: startLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDown(with: downEvent, button: .left)

        // Sub-threshold drag (2 pt)
        let subThresholdLoc = CGPoint(x: startLoc.x + 2.0, y: startLoc.y)
        let dragEvent = makeMouseEvent(type: .leftMouseDragged, location: subThresholdLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDragged(with: dragEvent, button: .left)

        #expect(coordinator.widgetlessDragState?.hasMoved == false)

        // Mouse up
        let upEvent = makeMouseEvent(type: .leftMouseUp, location: subThresholdLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseUp(with: upEvent, button: .left)

        #expect(coordinator.widgetlessDragState == nil)
        #expect(document.objects.first(where: { $0.id == boxId })?.transform == initialTransform)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testLockedSolidIgnoresWidgetlessDrag() throws {
        let (window, _, coordinator, renderer, document, _) = try makeHarness(boxWidth: 120, boxDepth: 100, boxHeight: 40)
        let boxId = SolidId("box-1")
        document.setLocked(id: boxId, isLocked: true)

        let aspect = Float(width) / Float(height)
        let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = matrices.projection * matrices.view
        let surfacePt = SIMD3<Float>(-40, -30, 10)
        let screenPt = try #require(projectToScreen(point: surfacePt, viewProjectionMatrix: vp, viewportSize: CGSize(width: width, height: height)))
        let startLoc = CGPoint(x: CGFloat(screenPt.x), y: CGFloat(screenPt.y))

        let downEvent = makeMouseEvent(type: .leftMouseDown, location: startLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDown(with: downEvent, button: .left)

        #expect(coordinator.widgetlessDragState == nil, "Locked solid must never start widgetless drag")
        #expect(coordinator.pointerRouter.arbiter.current().locked == false)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testSolidDeletionMidDragAbortsGestureCleanly() throws {
        let (window, view, coordinator, _, document, _) = try makeHarness(boxWidth: 120, boxDepth: 100, boxHeight: 40)
        let boxId = SolidId("box-1")

        let aspect = Float(width) / Float(height)
        let matrices = coordinator.parent.renderer.viewAndProjectionMatrices(aspect: aspect)
        let vp = matrices.projection * matrices.view
        let surfacePt = SIMD3<Float>(-40, -30, 10)
        let screenPt = try #require(projectToScreen(point: surfacePt, viewProjectionMatrix: vp, viewportSize: CGSize(width: width, height: height)))
        let startLoc = CGPoint(x: CGFloat(screenPt.x), y: CGFloat(screenPt.y))

        let downEvent = makeMouseEvent(type: .leftMouseDown, location: startLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDown(with: downEvent, button: .left)

        let dragLoc = CGPoint(x: startLoc.x + 30.0, y: startLoc.y)
        let dragEvent = makeMouseEvent(type: .leftMouseDragged, location: dragLoc, windowNumber: window.windowNumber, modifierFlags: .shift)
        coordinator.handleMouseDragged(with: dragEvent, button: .left)

        #expect(coordinator.widgetlessDragState != nil)

        // Delete the solid feature from document
        let featId = try #require(document.feature(for: boxId)?.id)
        _ = document.removeFeature(id: featId)

        coordinator.parent.update(view: view, coordinator: coordinator)

        #expect(coordinator.widgetlessDragState == nil)
        #expect(coordinator.pointerRouter.arbiter.current().mode == nil)
    }

    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable"))
    func testAccessibilityProbeGatedByUITestingFlag() throws {
        let (_, view, coordinator, _, _, _) = try makeHarness()
        _ = coordinator

        let originalFlag = CADMTKView.isUITestingEnabled
        defer { CADMTKView.isUITestingEnabled = originalFlag }

        CADMTKView.isUITestingEnabled = false
        #expect(view.accessibilityValue() == nil)

        CADMTKView.isUITestingEnabled = true
        let probeValue = try #require(view.accessibilityValue() as? String)
        let snapshot = ViewportProbe.parse(probeValue)
        #expect(snapshot.state == "ready")
        #expect(snapshot.hits.contains { $0.id == SolidId("box-1") })
    }
}
