import Foundation
@preconcurrency import Metal
import Observation
import os

/// The state of the Metal 3D viewport.
public enum ViewportState: Equatable, Sendable {
    case initializing
    case ready
    case unavailable(reason: ViewportUnavailableReason)
    
    public var isAvailable: Bool {
        if case .ready = self { return true }
        return false
    }
    
    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
    
    public var unavailableReason: ViewportUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
    
    public var statusText: String {
        switch self {
        case .initializing:
            return "Initializing Metal 3..."
        case .ready:
            return "Metal 3"
        case .unavailable:
            return "Metal unavailable"
        }
    }
}

/// The specific failure reason when the viewport is unavailable.
public enum ViewportUnavailableReason: String, Equatable, Sendable, CustomStringConvertible {
    case noDevice = "no-device"
    case pipelineCreationFailed = "pipeline-creation-failed"
    case deviceLost = "device-lost"
    
    public var description: String {
        switch self {
        case .noDevice:
            return "No Metal device found"
        case .pipelineCreationFailed:
            return "Failed to create Metal render pipeline"
        case .deviceLost:
            return "Metal device was lost or disconnected"
        }
    }
}

/// Protocol providing an MTLDevice instance or nil.
public protocol MetalDeviceProviding: Sendable {
    func makeDevice() -> (any MTLDevice)?
}

/// Metal device provider utilities and test seam controls.
public enum MetalDeviceProvider {
    private static let _forceNoDeviceSeam = OSAllocatedUnfairLock<Bool>(initialState: false)
    
    /// Programmatic seam for testing: when true, forces makeDevice() to return nil.
    public static var forceNoDeviceSeam: Bool {
        get { _forceNoDeviceSeam.withLock { $0 } }
        set { _forceNoDeviceSeam.withLock { $0 = newValue } }
    }
    
    /// Evaluates whether the no-GPU path is forced via environment variables, CLI arguments, or seam.
    public static var isForceNoGPUEnabled: Bool {
        if forceNoDeviceSeam {
            return true
        }
        let env = ProcessInfo.processInfo.environment
        if let val = env["MADE_FORCE_NO_GPU"], !val.isEmpty && val != "0" {
            return true
        }
        if let val = env["MADE_DISABLE_METAL"], !val.isEmpty && val != "0" {
            return true
        }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--force-no-gpu") || args.contains("--no-gpu") || args.contains("--disable-metal") {
            return true
        }
        return false
    }
}

/// Default system provider that respects the no-device seam.
public struct DefaultMetalDeviceProvider: MetalDeviceProviding {
    public init() {}
    
    public func makeDevice() -> (any MTLDevice)? {
        if MetalDeviceProvider.isForceNoGPUEnabled {
            return nil
        }
        return MTLCreateSystemDefaultDevice()
    }
}

private final class DeviceBox: @unchecked Sendable {
    let device: (any MTLDevice)?
    init(device: (any MTLDevice)?) {
        self.device = device
    }
}

/// Custom device provider for injecting mock or fixed MTLDevice instances.
public struct CustomMetalDeviceProvider: MetalDeviceProviding {
    private let deviceBox: DeviceBox?
    private let deviceClosure: (@Sendable () -> (any MTLDevice)?)?
    
    public init(device: (any MTLDevice)?) {
        self.deviceBox = DeviceBox(device: device)
        self.deviceClosure = nil
    }
    
    public init(deviceClosure: @escaping @Sendable () -> (any MTLDevice)?) {
        self.deviceBox = nil
        self.deviceClosure = deviceClosure
    }
    
    public func makeDevice() -> (any MTLDevice)? {
        if let box = deviceBox {
            return box.device
        }
        return deviceClosure?()
    }
}

/// Pure state selection logic for resolving viewport states.
public enum ViewportStateResolver {
    public static func resolve(deviceAvailable: Bool, rendererCreated: Bool) -> ViewportState {
        guard deviceAvailable else {
            return .unavailable(reason: .noDevice)
        }
        guard rendererCreated else {
            return .unavailable(reason: .pipelineCreationFailed)
        }
        return .ready
    }
}

/// Coordinates viewport state transitions, device resolution, and device-loss lifecycle.
@Observable
@MainActor
public final class ViewportStateManager {
    public var state: ViewportState = .initializing
    public var renderer: MetalRenderer? = nil
    
    private let deviceProvider: any MetalDeviceProviding
    private let rendererFactory: @Sendable (any MTLDevice) -> MetalRenderer?
    
    #if os(macOS)
    private final class ObserverToken: @unchecked Sendable {
        var observer: (any NSObjectProtocol)? = nil
        func set(_ obs: any NSObjectProtocol) {
            self.observer = obs
        }
        func clear() {
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
                observer = nil
            }
        }
        deinit {
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
            }
        }
    }
    
    private let observerToken = ObserverToken()
    #endif
    
    public init(
        deviceProvider: any MetalDeviceProviding = DefaultMetalDeviceProvider(),
        rendererFactory: @escaping @Sendable (any MTLDevice) -> MetalRenderer? = { MetalRenderer(device: $0) }
    ) {
        self.deviceProvider = deviceProvider
        self.rendererFactory = rendererFactory
    }
    
    @discardableResult
    public func setup() -> ViewportState {
        guard let device = deviceProvider.makeDevice() else {
            self.renderer = nil
            self.state = .unavailable(reason: .noDevice)
            return self.state
        }
        
        guard let rend = rendererFactory(device) else {
            self.renderer = nil
            self.state = .unavailable(reason: .pipelineCreationFailed)
            return self.state
        }
        
        self.renderer = rend
        self.state = .ready
        
        #if os(macOS)
        startObservingDeviceLost()
        #endif
        
        return self.state
    }
    
    public func handleDeviceLost() {
        #if os(macOS)
        stopObservingDeviceLost()
        #endif
        self.renderer = nil
        self.state = .unavailable(reason: .deviceLost)
    }
    
    #if os(macOS)
    private func startObservingDeviceLost() {
        stopObservingDeviceLost()
        let obs = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(MTLDeviceNotificationName.wasRemoved.rawValue),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDeviceLost()
            }
        }
        observerToken.set(obs)
    }
    
    private func stopObservingDeviceLost() {
        observerToken.clear()
    }
    #endif
}
