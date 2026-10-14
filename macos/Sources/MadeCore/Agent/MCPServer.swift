import Foundation
import Network

/// Recovers a request's id before the full decode, so an invalid request can echo it.
private struct IDProbe: Decodable {
    let id: JSONRPCID?
}

public final class MCPServer: @unchecked Sendable {
    public let toolRegistry: CADToolRegistry
    private let encoder: JSONEncoder
    private let maximumLineLength: Int
    private let decoder = JSONDecoder()
    
    // In-app TCP server state
    internal private(set) var listener: NWListener?
    private let queue = DispatchQueue(label: "com.made.mcp.server", qos: .userInitiated)
    public private(set) var isRunning: Bool = false
    public private(set) var port: UInt16 = 9820
    public var onStateChange: (@Sendable (Bool) -> Void)? = nil
    
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
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: nwPort)
        self.port = port
        self.listener = listener
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                self?.onStateChange?(true)
            case .failed, .cancelled:
                self?.isRunning = false
                self?.onStateChange?(false)
            default:
                break
            }
        }
        
        listener.start(queue: queue)
        self.isRunning = true
        self.onStateChange?(true)
    }
    
    /// Stops the in-app MCP TCP listener and terminates active connections.
    public func stop() {
        guard let oldListener = self.listener else {
            isRunning = false
            onStateChange?(false)
            return
        }
        self.listener = nil
        if case .cancelled = oldListener.state {
            isRunning = false
            onStateChange?(false)
            return
        }
        let semaphore = DispatchSemaphore(value: 0)
        oldListener.stateUpdateHandler = { state in
            if case .cancelled = state {
                semaphore.signal()
            }
        }
        oldListener.cancel()
        _ = semaphore.wait(timeout: .now() + .milliseconds(500))
        isRunning = false
        onStateChange?(false)
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let (frames, continuation) = AsyncStream.makeStream(of: MCPLineFramer.Frame.self)
        // One consumer per connection answers lines in arrival order.
        Task {
            for await frame in frames {
                if let response = await self.processFrame(frame) {
                    connection.send(content: Data((response + "\n").utf8), completion: .contentProcessed({ _ in }))
                }
                // An oversized line ends the connection after its -32700, so the peer cannot keep streaming.
                if frame == .oversized { break }
            }
            // Sends complete in order, so the final message flushes every response before the cancel.
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
        connection.start(queue: queue)
        receiveMessages(on: connection, framer: MCPLineFramer(maximumLineLength: maximumLineLength), continuation: continuation)
    }
    
    /// Threads the framer through each receive by value; callbacks run serially on `queue`.
    private func receiveMessages(on connection: NWConnection, framer: MCPLineFramer, continuation: AsyncStream<MCPLineFramer.Frame>.Continuation) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
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
            } else if let self, error == nil {
                self.receiveMessages(on: connection, framer: framer, continuation: continuation)
            } else {
                continuation.finish()
            }
        }
    }
    
    /// Returns the response to one frame. An oversized line and bytes that are not UTF-8 both get -32700.
    private func processFrame(_ frame: MCPLineFramer.Frame) async -> String? {
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
