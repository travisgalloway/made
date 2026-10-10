import Foundation

public final class MCPServer: @unchecked Sendable {
    public let toolRegistry: CADToolRegistry
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init(toolRegistry: CADToolRegistry) {
        self.toolRegistry = toolRegistry
    }
    
    /// Processes a single raw JSON-RPC 2.0 string and returns the response JSON string.
    public func processMessage(_ jsonString: String) async -> String? {
        guard let data = jsonString.data(using: .utf8) else {
            return encodeResponse(JSONRPCResponse(id: nil, error: .parseError))
        }
        
        let request: JSONRPCRequest
        do {
            request = try decoder.decode(JSONRPCRequest.self, from: data)
        } catch {
            return encodeResponse(JSONRPCResponse(id: nil, error: .parseError))
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
            
        case "notifications/initialized":
            // Notification: no response required
            return JSONRPCResponse(id: request.id, result: .null)
            
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
