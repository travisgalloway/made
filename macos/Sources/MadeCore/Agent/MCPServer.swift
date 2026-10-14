import Foundation
import Network
import OSLog

/// Recovers a request's id before the full decode, so an invalid request can echo it.
private struct IDProbe: Decodable {
    let id: JSONRPCID?
}

public enum MCPServerError: Error, LocalizedError, Equatable, Sendable {
    case invalidPort(UInt16)

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            return "Invalid port: \(port). Port must be between 1 and 65535."
        }
    }
}

public final class MCPServer: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.made.app", category: "MCP")

    public let toolRegistry: CADToolRegistry
    private let encoder: JSONEncoder
    private let maximumLineLength: Int
    private let decoder = JSONDecoder()
    
    // In-app TCP server state
    private struct TrackedConnection: Sendable {
        let connection: NWConnection
        let task: Task<Void, Never>
        let continuation: AsyncStream<MCPLineFramer.Frame>.Continuation
    }
    
    private let lock = NSLock()
    private var _listener: NWListener?
    private var _isRunning: Bool = false
    private var _port: UInt16 = 9820
    private var _lastError: String? = nil
    private var _onStateChange: (@Sendable (Bool) -> Void)? = nil
    private var _onError: (@Sendable (NWError) -> Void)? = nil
    #if DEBUG
    private var _onSendFailure: (@Sendable (ObjectIdentifier, NWError) -> Void)? = nil
    private var _simulateSendFailure: NWError? = nil
    #endif
    private var activeConnections: [ObjectIdentifier: TrackedConnection] = [:]
    private let queue = DispatchQueue(label: "com.made.mcp.server", qos: .userInitiated)
    
    internal var listener: NWListener? {
        lock.withLock { _listener }
    }
    
    public var isRunning: Bool {
        lock.withLock { _isRunning }
    }
    
    public var port: UInt16 {
        lock.withLock { _port }
    }
    
    public var lastError: String? {
        lock.withLock { _lastError }
    }
    
    public var onStateChange: (@Sendable (Bool) -> Void)? {
        get { lock.withLock { _onStateChange } }
        set { lock.withLock { _onStateChange = newValue } }
    }
    
    public var onError: (@Sendable (NWError) -> Void)? {
        get { lock.withLock { _onError } }
        set { lock.withLock { _onError = newValue } }
    }
    
    #if DEBUG
    public var onSendFailure: (@Sendable (ObjectIdentifier, NWError) -> Void)? {
        get { lock.withLock { _onSendFailure } }
        set { lock.withLock { _onSendFailure = newValue } }
    }
    
    public var simulateSendFailure: NWError? {
        get { lock.withLock { _simulateSendFailure } }
        set { lock.withLock { _simulateSendFailure = newValue } }
    }
    
    internal var activeConnectionIdentifiers: [ObjectIdentifier] {
        lock.withLock { Array(activeConnections.keys) }
    }
    #endif
    
    internal var activeConnectionCount: Int {
        lock.withLock { activeConnections.count }
    }
    
    public convenience init(toolRegistry: CADToolRegistry) {
        self.init(toolRegistry: toolRegistry, encoder: JSONEncoder())
    }
    
    /// Accepts an injected encoder so tests can reach the -32603 path, and a line limit so tests can reach the oversized path.
    init(toolRegistry: CADToolRegistry, encoder: JSONEncoder, maximumLineLength: Int = MCPLineFramer.defaultMaximumLineLength) {
        self.toolRegistry = toolRegistry
        self.encoder = encoder
        self.maximumLineLength = maximumLineLength
    }
    
    /// Starts the in-app MCP TCP listener on the specified local port (default: 9820).
    public func start(port: UInt16 = 9820) throws {
        stop()
        guard port > 0, let nwPort = NWEndpoint.Port(rawValue: port) else {
            let error = MCPServerError.invalidPort(port)
            lock.withLock { self._lastError = error.localizedDescription }
            throw error
        }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: nwPort)
        
        lock.withLock {
            self._port = port
            self._listener = listener
            self._lastError = nil
            self._isRunning = false
        }
        
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            guard let self, let listener else { return }
            let isCurrent = self.lock.withLock { self._listener === listener }
            guard isCurrent else {
                connection.cancel()
                return
            }
            self.handleConnection(connection)
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            let isCurrent = self.lock.withLock { self._listener === listener }
            guard isCurrent else { return }
            
            switch state {
            case .ready:
                let notify = self.lock.withLock { () -> Bool in
                    self._lastError = nil
                    if !self._isRunning {
                        self._isRunning = true
                        return true
                    }
                    return false
                }
                if notify {
                    let cb = self.lock.withLock { self._onStateChange }
                    cb?(true)
                }
                semaphore.signal()
            case .failed(let error):
                let (notify, conns) = self.lock.withLock { () -> (Bool, [TrackedConnection]) in
                    self._lastError = error.localizedDescription
                    let wasRunning = self._isRunning
                    self._isRunning = false
                    let conns = Array(self.activeConnections.values)
                    self.activeConnections.removeAll()
                    return (wasRunning, conns)
                }
                for entry in conns {
                    entry.task.cancel()
                    entry.continuation.finish()
                    entry.connection.cancel()
                }
                let errCb = self.lock.withLock { self._onError }
                errCb?(error)
                if notify {
                    let cb = self.lock.withLock { self._onStateChange }
                    cb?(false)
                }
                semaphore.signal()
            case .cancelled:
                let (notify, conns) = self.lock.withLock { () -> (Bool, [TrackedConnection]) in
                    let wasRunning = self._isRunning
                    self._isRunning = false
                    let conns = Array(self.activeConnections.values)
                    self.activeConnections.removeAll()
                    return (wasRunning, conns)
                }
                for entry in conns {
                    entry.task.cancel()
                    entry.continuation.finish()
                    entry.connection.cancel()
                }
                if notify {
                    let cb = self.lock.withLock { self._onStateChange }
                    cb?(false)
                }
            default:
                break
            }
        }
        
        listener.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + .milliseconds(500))
    }
    
    /// Stops the in-app MCP TCP listener and terminates active connections.
    public func stop() {
        let (oldListener, connectionsToCancel, wasRunning) = lock.withLock { () -> (NWListener?, [TrackedConnection], Bool) in
            self._lastError = nil
            let l = _listener
            _listener = nil
            let conns = Array(activeConnections.values)
            activeConnections.removeAll()
            let was = _isRunning
            _isRunning = false
            return (l, conns, was)
        }
        
        for entry in connectionsToCancel {
            entry.task.cancel()
            entry.continuation.finish()
            entry.connection.cancel()
        }
        
        if let oldListener {
            if case .cancelled = oldListener.state {
                // already cancelled
            } else {
                let semaphore = DispatchSemaphore(value: 0)
                oldListener.stateUpdateHandler = { state in
                    if case .cancelled = state {
                        semaphore.signal()
                    }
                }
                oldListener.cancel()
                _ = semaphore.wait(timeout: .now() + .milliseconds(500))
            }
        }
        
        if wasRunning {
            let callback = lock.withLock { _onStateChange }
            callback?(false)
        }
    }
    
    #if DEBUG
    internal func simulateListenerFailure(_ error: NWError) {
        let (handler, listener) = lock.withLock { (_listener?.stateUpdateHandler, _listener) }
        if let handler, let _ = listener {
            handler(.failed(error))
        }
    }
    #endif
    
    private func handleSendFailure(connection: NWConnection, connectionId: ObjectIdentifier, error: NWError) {
        Self.logger.error("MCP send failed on connection \(String(describing: connectionId), privacy: .public): \(error.localizedDescription, privacy: .public)")
        #if DEBUG
        let callback = lock.withLock { _onSendFailure }
        callback?(connectionId, error)
        #endif
        removeConnection(connection)
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let (frames, continuation) = AsyncStream.makeStream(of: MCPLineFramer.Frame.self)
        let connectionId = ObjectIdentifier(connection)
        
        let task = Task { [weak self] in
            for await frame in frames {
                guard !Task.isCancelled, let self, self.isRunning else { break }
                let isAlive = self.lock.withLock { self.activeConnections[connectionId] != nil }
                guard isAlive else { break }
                if let response = await self.processFrame(frame) {
                    guard !Task.isCancelled, self.isRunning else { break }
                    let stillAlive = self.lock.withLock { self.activeConnections[connectionId] != nil }
                    guard stillAlive else { break }
                    #if DEBUG
                    if let forcedError = self.lock.withLock({ self._simulateSendFailure }) {
                        self.handleSendFailure(connection: connection, connectionId: connectionId, error: forcedError)
                        break
                    }
                    #endif
                    let sendError: NWError? = await withCheckedContinuation { continuation in
                        connection.send(content: Data((response + "\n").utf8), completion: .contentProcessed({ [weak self] error in
                            if let error {
                                self?.handleSendFailure(connection: connection, connectionId: connectionId, error: error)
                            }
                            continuation.resume(returning: error)
                        }))
                    }
                    if sendError != nil { break }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                if frame == .oversized { break }
            }
            if !Task.isCancelled {
                await withCheckedContinuation { continuation in
                    connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ [weak self] error in
                        if let error {
                            self?.handleSendFailure(connection: connection, connectionId: connectionId, error: error)
                        }
                        connection.cancel()
                        self?.removeConnection(connection)
                        continuation.resume()
                    }))
                }
            } else {
                connection.cancel()
                self?.removeConnection(connection)
            }
        }
        
        let entry = TrackedConnection(connection: connection, task: task, continuation: continuation)
        
        let accepted = lock.withLock { () -> Bool in
            guard _isRunning, _listener != nil else { return false }
            activeConnections[connectionId] = entry
            return true
        }
        
        guard accepted else {
            task.cancel()
            continuation.finish()
            connection.cancel()
            return
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        receiveMessages(on: connection, framer: MCPLineFramer(maximumLineLength: maximumLineLength), continuation: continuation)
    }
    
    private func removeConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let entry = lock.withLock {
            activeConnections.removeValue(forKey: id)
        }
        if let entry {
            entry.task.cancel()
            entry.continuation.finish()
            entry.connection.cancel()
        }
    }
    
    /// Threads the framer through each receive by value; callbacks run serially on `queue`.
    private func receiveMessages(on connection: NWConnection, framer: MCPLineFramer, continuation: AsyncStream<MCPLineFramer.Frame>.Continuation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            if error != nil {
                continuation.finish()
                self?.removeConnection(connection)
                return
            }
            var framer = framer
            if let content, !content.isEmpty {
                for frame in framer.append(content) {
                    continuation.yield(frame)
                    if frame == .oversized {
                        continuation.finish()
                        return
                    }
                }
            }
            if isComplete {
                for frame in framer.finish() { continuation.yield(frame) }
                continuation.finish()
            } else if let self, self.isRunning {
                self.receiveMessages(on: connection, framer: framer, continuation: continuation)
            } else {
                continuation.finish()
            }
        }
    }
    
    /// Returns the response to one frame. An oversized line and bytes that are not UTF-8 both get -32700.
    private func processFrame(_ frame: MCPLineFramer.Frame) async -> String? {
        guard !Task.isCancelled else { return nil }
        guard case .line(let line) = frame,
              let string = String(data: line, encoding: .utf8) else {
            return encodeResponse(JSONRPCResponse(id: nil, error: .parseError))
        }
        return await processMessage(string)
    }
    
    /// Processes a single raw JSON-RPC 2.0 string and returns the response JSON string.
    /// Returns nil for a notification (an object with a string `method` and no `id` member).
    public func processMessage(_ jsonString: String) async -> String? {
        guard let data = jsonString.data(using: .utf8) else {
            return encodeResponse(JSONRPCResponse(id: nil, error: .parseError))
        }
        
        // -32700 is reserved for text that is not JSON at all.
        guard let value = try? decoder.decode(AnyCodableValue.self, from: data) else {
            return encodeResponse(JSONRPCResponse(id: nil, error: .parseError))
        }
        guard case .dictionary(let members) = value else {
            return encodeResponse(JSONRPCResponse(id: nil, error: .invalidRequest))
        }
        // A JSON-RPC notification has no id member, and the server must never reply to one.
        if members["id"] == nil, members["method"]?.stringValue != nil {
            return nil
        }
        guard let probe = try? decoder.decode(IDProbe.self, from: data) else {
            return encodeResponse(JSONRPCResponse(id: nil, error: .invalidRequest))
        }
        
        let request: JSONRPCRequest
        do {
            request = try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            return encodeResponse(JSONRPCResponse(id: probe.id, error: .invalidRequest))
        }
        
        let response = await handleRequest(request)
        return encodeResponse(response)
    }
    
    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            let serverInfo: [String: AnyCodableValue] = [
                "protocolVersion": .string("2024-11-05"),
                "serverInfo": .dictionary([
                    "name": .string("made-native-cad"),
                    "version": .string("0.1.0")
                ]),
                "capabilities": .dictionary([
                    "tools": .dictionary([:])
                ])
            ]
            return JSONRPCResponse(id: request.id, result: .dictionary(serverInfo))
            
        case "tools/list":
            let tools = toolRegistry.tools
            if let toolsData = try? encoder.encode(tools),
               let toolsJSON = try? decoder.decode([AnyCodableValue].self, from: toolsData) {
                return JSONRPCResponse(id: request.id, result: .dictionary(["tools": .array(toolsJSON)]))
            }
            return JSONRPCResponse(id: request.id, error: .internalError)
            
        case "tools/call":
            guard let params = request.params,
                  let nameVal = params["name"]?.stringValue else {
                return JSONRPCResponse(id: request.id, error: .invalidParams)
            }
            
            let args = params["arguments"]?.dictionaryValue ?? [:]
            let toolResult = await toolRegistry.callTool(name: nameVal, arguments: args)
            
            if let resultData = try? encoder.encode(toolResult),
               let resultJSON = try? decoder.decode(AnyCodableValue.self, from: resultData) {
                return JSONRPCResponse(id: request.id, result: resultJSON)
            }
            return JSONRPCResponse(id: request.id, error: .internalError)
            
        default:
            return JSONRPCResponse(id: request.id, error: .methodNotFound)
        }
    }
    
    private func encodeResponse(_ response: JSONRPCResponse) -> String? {
        guard let data = try? encoder.encode(response),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    /// Runs the server on standard input/output (for Claude Desktop / Cursor CLI MCP integration).
    public func runStdio() async {
        let inputHandle = FileHandle.standardInput
        let outputHandle = FileHandle.standardOutput
        
        var framer = MCPLineFramer(maximumLineLength: maximumLineLength)
        
        // An oversized line gets -32700 and the rest of it is skipped; stdio has one client, so it keeps serving.
        func respond(to frames: [MCPLineFramer.Frame]) async {
            for frame in frames {
                if let response = await processFrame(frame) {
                    try? outputHandle.write(contentsOf: Data((response + "\n").utf8))
                }
            }
        }
        
        while true {
            guard let data = try? inputHandle.read(upToCount: 65536), !data.isEmpty else {
                break
            }
            await respond(to: framer.append(data))
        }
        await respond(to: framer.finish())
    }
}
