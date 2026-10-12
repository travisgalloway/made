import Foundation
import XPC
import MadeCore

// The kernel XPC service. Hosts the Euclid engine so a geometry crash ends this process, not the app (invariant 1).
// One app session per process; the service exits when the app goes away.
let handler = KernelServiceHandler(onPeerGone: { exit(EXIT_SUCCESS) })
let listener = try XPCListener(service: KernelService.identifier, incomingSessionHandler: handler.makeListenerHandler())
dispatchMain()
