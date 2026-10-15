import Testing
import Foundation
import Metal
@testable import MadeCore

@MainActor
@Suite(.serialized) final class ViewportStateTests {
    
    deinit {
        MetalDeviceProvider.forceNoDeviceSeam = false
    }
    
    @Test func testInitialStateIsInitializing() {
        let manager = ViewportStateManager()
        #expect(manager.state == .initializing)
        #expect(!manager.state.isAvailable)
        #expect(!manager.state.isUnavailable)
        #expect(manager.state.unavailableReason == nil)
        #expect(manager.state.statusText == "Initializing Metal 4...")
    }
    
    @Test func testStateResolverLogic() {
        #expect(ViewportStateResolver.resolve(deviceAvailable: false, rendererCreated: false) == .unavailable(reason: .noDevice))
        #expect(ViewportStateResolver.resolve(deviceAvailable: false, rendererCreated: true) == .unavailable(reason: .noDevice))
        #expect(ViewportStateResolver.resolve(deviceAvailable: true, rendererCreated: false) == .unavailable(reason: .pipelineCreationFailed))
        #expect(ViewportStateResolver.resolve(deviceAvailable: true, rendererCreated: true) == .ready)
    }
    
    @Test func testNoDevicePathProducesUnavailableNoDevice() {
        let provider = CustomMetalDeviceProvider(device: nil)
        let manager = ViewportStateManager(deviceProvider: provider)
        
        let state = manager.setup()
        
        #expect(state == .unavailable(reason: .noDevice))
        #expect(manager.state == .unavailable(reason: .noDevice))
        #expect(manager.state.isUnavailable)
        #expect(!manager.state.isAvailable)
        #expect(manager.state.unavailableReason == .noDevice)
        #expect(manager.state.statusText == "Metal unavailable")
        #expect(manager.renderer == nil)
    }
    
    @Test func testForceNoGPUSeam() {
        #expect(!MetalDeviceProvider.forceNoDeviceSeam)
        
        MetalDeviceProvider.forceNoDeviceSeam = true
        #expect(MetalDeviceProvider.isForceNoGPUEnabled)
        
        let provider = DefaultMetalDeviceProvider()
        #expect(provider.makeDevice() == nil, "Seam must force makeDevice to return nil")
        
        let manager = ViewportStateManager(deviceProvider: provider)
        let state = manager.setup()
        
        #expect(state == .unavailable(reason: .noDevice))
        #expect(manager.renderer == nil)
        
        MetalDeviceProvider.forceNoDeviceSeam = false
        #expect(!MetalDeviceProvider.isForceNoGPUEnabled)
    }
    
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Metal unavailable")) func testPipelineCreationFailedProducesUnavailable() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        
        let provider = CustomMetalDeviceProvider(device: device)
        // Simulate pipeline creation failure by returning nil from renderer factory
        let manager = ViewportStateManager(
            deviceProvider: provider,
            rendererFactory: { _ in nil }
        )
        
        let state = manager.setup()
        
        #expect(state == .unavailable(reason: .pipelineCreationFailed))
        #expect(manager.state == .unavailable(reason: .pipelineCreationFailed))
        #expect(manager.state.isUnavailable)
        #expect(manager.state.unavailableReason == .pipelineCreationFailed)
        #expect(manager.state.statusText == "Metal unavailable")
        #expect(manager.renderer == nil)
    }
    
    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testDeviceLostAfterLaunchTransition() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        
        let provider = CustomMetalDeviceProvider(device: device)
        let manager = ViewportStateManager(
            deviceProvider: provider,
            rendererFactory: { _ in renderer }
        )
        
        let state = manager.setup()
        #expect(state == .ready)
        #expect(manager.state.isAvailable)
        #expect(manager.renderer != nil)
        
        // Simulate device loss
        manager.handleDeviceLost()
        
        #expect(manager.state == .unavailable(reason: .deviceLost))
        #expect(manager.state.isUnavailable)
        #expect(!manager.state.isAvailable)
        #expect(manager.state.unavailableReason == .deviceLost)
        #expect(manager.state.statusText == "Metal unavailable")
        #expect(manager.renderer == nil)
    }
    
    @Test(.enabled(if: MetalTestSupport.isMetal4Available, "Metal 4 unavailable")) func testDeviceLostViaNotification() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try #require(MetalRenderer(device: device))
        
        let provider = CustomMetalDeviceProvider(device: device)
        let manager = ViewportStateManager(
            deviceProvider: provider,
            rendererFactory: { _ in renderer }
        )
        
        manager.setup()
        #expect(manager.state == .ready)
        
        // Post device removal notification
        NotificationCenter.default.post(
            name: NSNotification.Name(MTLDeviceNotificationName.wasRemoved.rawValue),
            object: nil
        )
        
        #expect(manager.state == .unavailable(reason: .deviceLost))
        #expect(manager.renderer == nil)
    }
    
    @Test func testKernelRunsWithoutRenderer() async {
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
        #expect(result.isSuccess)
        guard let payload = result.value else {
            Issue.record("Kernel makeBox failed to return mesh payload")
            return
        }
        #expect(!payload.positions.isEmpty)
        #expect(!payload.indices.isEmpty)
        
        // Cylinder geometry computation
        let cylParams = CylinderParams(radius: 15, height: 40)
        let cylRequest = KernelRequest.makeCylinder(
            jobId: JobId("test-job-cyl"),
            solidId: cylinderSolidId,
            params: cylParams
        )
        let cylResult = await kernel.request(cylRequest)
        #expect(cylResult.isSuccess)
        guard let cylPayload = cylResult.value else {
            Issue.record("Kernel makeCylinder failed to return mesh payload")
            return
        }
        #expect(!cylPayload.positions.isEmpty)
        #expect(!cylPayload.indices.isEmpty)
        
        // Document manipulation without renderer
        doc.setParam(id: boxSolidId, key: "width", value: 65)
        if case .box(let updatedParams) = doc.paramsFor(id: boxSolidId) {
            #expect(updatedParams.width == 65.0)
        } else {
            Issue.record("Expected box params to update")
        }
        
        // CADToolRegistry with nil snapshotProvider operates cleanly
        let registry = CADToolRegistry(document: doc, kernelClient: kernel, snapshotProvider: nil)
        #expect(!registry.tools.isEmpty)
        
        let sceneResult = await registry.callTool(name: "cad_get_scene", arguments: [:])
        #expect(sceneResult.isError == false)
    }
    
    @Test func testViewportStateDescriptions() {
        #expect(ViewportUnavailableReason.noDevice.description == "No Metal device found")
        #expect(ViewportUnavailableReason.pipelineCreationFailed.description == "Failed to create Metal render pipeline")
        #expect(ViewportUnavailableReason.deviceLost.description == "Metal device was lost or disconnected")
    }
}
