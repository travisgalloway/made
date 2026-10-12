import Foundation
import XPC
import os

/// The kernel XPC service bundled inside `Made.app/Contents/XPCServices`.
public enum KernelService {
    public static let identifier = "com.made.app.kernel"
    static let bundleName = "MadeKernelService.xpc"
    
    /// True when the running app bundle carries the service; `swift run` and tests do not.
    static var isBundled: Bool {
        let url = Bundle.main.bundleURL.appending(path: "Contents/XPCServices/\(bundleName)")
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

extension KernelClient {
    /// The app's kernel: the XPC service when bundled, otherwise geometry in this process off the main actor.
    public static func makeDefault() -> KernelClient {
        let logger = Logger(subsystem: "com.made.app", category: "Kernel")
        guard KernelService.isBundled else {
            logger.log("Kernel service not bundled; running geometry in process")
            return KernelClient(engine: LocalKernelEngine())
        }
        logger.log("Kernel running in the \(KernelService.identifier, privacy: .public) XPC service")
        return KernelClient(engine: XPCKernelEngine { cancellationHandler in
            try XPCSession(xpcService: KernelService.identifier, cancellationHandler: cancellationHandler)
        })
    }
}
