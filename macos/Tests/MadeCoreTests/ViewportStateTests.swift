import XCTest
import Metal
@testable import MadeCore

@MainActor
final class ViewportStateTests: XCTestCase {
    
    override func tearDown() {
        MetalDeviceProvider.forceNoDeviceSeam = false
        super.tearDown()
    }
    
    func testInitialStateIsInitializing() {
        let manager = ViewportStateManager()
        XCTAssertEqual(manager.state, .initializing)
        XCTAssertFalse(manager.state.isAvailable)
        XCTAssertFalse(manager.state.isUnavailable)
        XCTAssertNil(manager.state.unavailableReason)
        XCTAssertEqual(manager.state.statusText, "Initializing Metal 3...")
    }
    
    func testStateResolverLogic() {
        XCTAssertEqual(
            ViewportStateResolver.resolve(deviceAvailable: false, rendererCreated: false),
            .unavailable(reason: .noDevice)
        )
        XCTAssertEqual(
            ViewportStateResolver.resolve(deviceAvailable: false, rendererCreated: true),
            .unavailable(reason: .noDevice)
        )
        XCTAssertEqual(
            ViewportStateResolver.resolve(deviceAvailable: true, rendererCreated: false),
            .unavailable(reason: .pipelineCreationFailed)
        )
        XCTAssertEqual(
            ViewportStateResolver.resolve(deviceAvailable: true, rendererCreated: true),
            .ready
        )
    }
    
    func testNoDevicePathProducesUnavailableNoDevice() {
        let provider = CustomMetalDeviceProvider(device: nil)
        let manager = ViewportStateManager(deviceProvider: provider)
        
        let state = manager.setup()
        
        XCTAssertEqual(state, .unavailable(reason: .noDevice))
        XCTAssertEqual(manager.state, .unavailable(reason: .noDevice))
        XCTAssertTrue(manager.state.isUnavailable)
        XCTAssertFalse(manager.state.isAvailable)
        XCTAssertEqual(manager.state.unavailableReason, .noDevice)
        XCTAssertEqual(manager.state.statusText, "Metal unavailable")
        XCTAssertNil(manager.renderer)
    }
    
    func testForceNoGPUSeam() {
        XCTAssertFalse(MetalDeviceProvider.forceNoDeviceSeam)
        
        MetalDeviceProvider.forceNoDeviceSeam = true
        XCTAssertTrue(MetalDeviceProvider.isForceNoGPUEnabled)
        
        let provider = DefaultMetalDeviceProvider()
        XCTAssertNil(provider.makeDevice(), "Seam must force makeDevice to return nil")
        
        let manager = ViewportStateManager(deviceProvider: provider)
        let state = manager.setup()
        
        XCTAssertEqual(state, .unavailable(reason: .noDevice))
        XCTAssertNil(manager.renderer)
        
        MetalDeviceProvider.forceNoDeviceSeam = false
        XCTAssertFalse(MetalDeviceProvider.isForceNoGPUEnabled)
    }
    
    func testPipelineCreationFailedProducesUnavailable() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal unavailable")
        }
        
        let provider = CustomMetalDeviceProvider(device: device)
        // Simulate pipeline creation failure by returning nil from renderer factory
        let manager = ViewportStateManager(
            deviceProvider: provider,
            rendererFactory: { _ in nil }
        )
        
        let state = manager.setup()
        
        XCTAssertEqual(state, .unavailable(reason: .pipelineCreationFailed))
        XCTAssertEqual(manager.state, .unavailable(reason: .pipelineCreationFailed))
        XCTAssertTrue(manager.state.isUnavailable)
        XCTAssertEqual(manager.state.unavailableReason, .pipelineCreationFailed)
        XCTAssertEqual(manager.state.statusText, "Metal unavailable")
        XCTAssertNil(manager.renderer)
    }
    
    func testDeviceLostAfterLaunchTransition() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            throw XCTSkip("Metal unavailable")
        }
        
        let provider = CustomMetalDeviceProvider(device: device)
        let manager = ViewportStateManager(
            deviceProvider: provider,
            rendererFactory: { _ in renderer }
        )
        
        let state = manager.setup()
        XCTAssertEqual(state, .ready)
        XCTAssertTrue(manager.state.isAvailable)
        XCTAssertNotNil(manager.renderer)
        
        // Simulate device loss
        manager.handleDeviceLost()
        
        XCTAssertEqual(manager.state, .unavailable(reason: .deviceLost))
        XCTAssertTrue(manager.state.isUnavailable)
        XCTAssertFalse(manager.state.isAvailable)
        XCTAssertEqual(manager.state.unavailableReason, .deviceLost)
        XCTAssertEqual(manager.state.statusText, "Metal unavailable")
        XCTAssertNil(manager.renderer)
    }
    
    func testDeviceLostViaNotification() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = MetalRenderer(device: device) else {
            throw XCTSkip("Metal unavailable")
        }
        
        let provider = CustomMetalDeviceProvider(device: device)
        let manager = ViewportStateManager(
            deviceProvider: provider,
            rendererFactory: { _ in renderer }
        )
        
        manager.setup()
        XCTAssertEqual(manager.state, .ready)
        
        // Post device removal notification
        NotificationCenter.default.post(
            name: NSNotification.Name(MTLDeviceNotificationName.wasRemoved.rawValue),
            object: nil
        )
        
        XCTAssertEqual(manager.state, .unavailable(reason: .deviceLost))
        XCTAssertNil(manager.renderer)
    }
    
    func testKernelRunsWithoutRenderer() async {
        let kernel = KernelClient()
        let doc = DocumentModel()
        
        // Ensure kernel can execute geometry requests without a renderer
        let boxParams = BoxParams(width: 40, depth: 30, height: 20)
        let request = KernelRequest.makeBox(
            jobId: JobId("test-job-box"),
            solidId: boxSolidId,
            params: boxParams
        )
        
        let result = await kernel.request(request)
        XCTAssertTrue(result.isSuccess)
        guard let payload = result.value else {
            XCTFail("Kernel makeBox failed to return mesh payload")
            return
        }
        XCTAssertFalse(payload.positions.isEmpty)
        XCTAssertFalse(payload.indices.isEmpty)
        
        // Cylinder geometry computation
        let cylParams = CylinderParams(radius: 15, height: 40)
        let cylRequest = KernelRequest.makeCylinder(
            jobId: JobId("test-job-cyl"),
            solidId: cylinderSolidId,
            params: cylParams
        )
        let cylResult = await kernel.request(cylRequest)
        XCTAssertTrue(cylResult.isSuccess)
        guard let cylPayload = cylResult.value else {
            XCTFail("Kernel makeCylinder failed to return mesh payload")
            return
        }
        XCTAssertFalse(cylPayload.positions.isEmpty)
        XCTAssertFalse(cylPayload.indices.isEmpty)
        
        // Document manipulation without renderer
        doc.setParam(id: boxSolidId, key: "width", value: 65)
        if case .box(let updatedParams) = doc.paramsFor(id: boxSolidId) {
            XCTAssertEqual(updatedParams.width, 65.0)
        } else {
            XCTFail("Expected box params to update")
        }
        
        // CADToolRegistry with nil snapshotProvider operates cleanly
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: nil)
        XCTAssertFalse(registry.tools.isEmpty)
        
        let sceneResult = await registry.callTool(name: "cad_get_scene", arguments: [:])
        XCTAssertEqual(sceneResult.isError, false)
    }
    
    func testViewportStateDescriptions() {
        XCTAssertEqual(ViewportUnavailableReason.noDevice.description, "No Metal device found")
        XCTAssertEqual(ViewportUnavailableReason.pipelineCreationFailed.description, "Failed to create Metal render pipeline")
        XCTAssertEqual(ViewportUnavailableReason.deviceLost.description, "Metal device was lost or disconnected")
    }
}
