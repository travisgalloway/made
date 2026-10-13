import Foundation
import Network

/// Recovers a request's id before the full decode, so an invalid request can echo it.
private struct IDProbe: Decodable {
    let id: JSONRPCID?
}

public final class MCPServer: @unchecked Sendable {
    public let toolRegistry: CADToolRegistry
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    
    // In-app TCP server state
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.made.mcp.server", qos: .userInitiated)
    public private(set) var isRunning: Bool = false
    public private(set) var port: UInt16 = 9820
    public var onStateChange: (@Sendable (Bool) -> Void)? = nil
    
    public convenience init(toolRegistry: CADToolRegistry) {
        self.init(toolRegistry: toolRegistry, encoder: JSONEncoder())
    }
    
    /// Accepts an injected encoder so tests can reach the -32603 path.
    init(toolRegistry: CADToolRegistry, encoder: JSONEncoder) {
        self.toolRegistry = toolRegistry
        self.encoder = encoder
    }
    
    /// Starts the in-app MCP TCP listener on the specified local port (default: 9820).
    public func start(port: UInt16 = 9820) throws {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let listener = try NWListener(using: .tcp, on: nwPort)
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
        listener?.cancel()
        listener = nil
        isRunning = false
        onStateChange?(false)
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveMessages(on: connection)
    }
    
    private func receiveMessages(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }
            if let string = String(data: data, encoding: .utf8) {
                let lines = string.split(whereSeparator: \.isNewline)
                Task {
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { continue }
                        if let response = await self.processMessage(trimmed) {
                            let outData = (response + "\n").data(using: .utf8)!
                            connection.send(content: outData, completion: .contentProcessed({ _ in }))
                        }
                    }
                }
            }
            if !isComplete && error == nil {
                self.receiveMessages(on: connection)
            }
        }
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
        
        while true {
            guard let data = try? inputHandle.read(upToCount: 65536), !data.isEmpty else {
                break
            }
            guard let inputString = String(data: data, encoding: .utf8) else { continue }
            
            let lines = inputString.split(whereSeparator: \.isNewline)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                
                if let response = await processMessage(trimmed) {
                    let outData = (response + "\n").data(using: .utf8)!
                    try? outputHandle.write(contentsOf: outData)
                }
            }
        }
    }
}
