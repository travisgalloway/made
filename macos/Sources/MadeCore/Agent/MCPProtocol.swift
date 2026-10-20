import Foundation

// MARK: - JSON-RPC 2.0 Types

public struct JSONRPCID: Codable, Hashable, Sendable, CustomStringConvertible {
    private let stringValue: String?
    private let intValue: Int?
    
    public init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }
    
    public init(_ int: Int) {
        self.stringValue = nil
        self.intValue = int
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self.intValue = intVal
            self.stringValue = nil
        } else if let strVal = try? container.decode(String.self) {
            self.stringValue = strVal
            self.intValue = nil
        } else {
            throw DecodingError.typeMismatch(JSONRPCID.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "A JSON-RPC id must be a string, an integer, or null"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = self.intValue {
            try container.encode(intValue)
        } else if let stringValue = self.stringValue {
            try container.encode(stringValue)
        } else {
            try container.encodeNil()
        }
    }
    
    public var description: String {
        if let s = stringValue { return s }
        if let i = intValue { return String(i) }
        return "null"
    }
}

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let method: String
    public let params: [String: AnyCodableValue]?
    
    public init(method: String, id: JSONRPCID? = nil, params: [String: AnyCodableValue]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCErrorPayload: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodableValue?
    
    public init(code: Int, message: String, data: AnyCodableValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
    
    public static let parseError = JSONRPCErrorPayload(code: -32700, message: "Parse error")
    public static let invalidRequest = JSONRPCErrorPayload(code: -32600, message: "Invalid Request")
    public static let methodNotFound = JSONRPCErrorPayload(code: -32601, message: "Method not found")
    public static let invalidParams = JSONRPCErrorPayload(code: -32602, message: "Invalid params")
    public static let internalError = JSONRPCErrorPayload(code: -32603, message: "Internal error")
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let result: AnyCodableValue?
    public let error: JSONRPCErrorPayload?
    
    public init(id: JSONRPCID?, result: AnyCodableValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }
    
    public init(id: JSONRPCID?, error: JSONRPCErrorPayload) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
    
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }
    
    // JSON-RPC 2.0 requires the id member on every response, null when unknown.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

// MARK: - AnyCodableValue Helper

public enum AnyCodableValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            self = .array(arr)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported AnyCodableValue type"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .dictionary(let dict): try container.encode(dict)
        case .array(let arr): try container.encode(arr)
        case .null: try container.encodeNil()
        }
    }
    
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    
    public var doubleValue: Double? {
        if case .double(let d) = self { return d }
        if case .int(let i) = self { return Double(i) }
        return nil
    }
    
    public var floatValue: Float? {
        guard let d = doubleValue else { return nil }
        return Float(d)
    }
    
    public var intValue: Int? {
        if case .int(let i) = self { return i }
        if case .double(let d) = self {
            guard d.isFinite else { return nil }
            return Int(exactly: d)
        }
        return nil
    }
    
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    
    public var dictionaryValue: [String: AnyCodableValue]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }
    
    public var arrayValue: [AnyCodableValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

// MARK: - Model Context Protocol (MCP) Types

public struct MCPProperty: Codable, Sendable {
    public let type: String
    public let description: String?
    public let `enum`: [String]?
    
    public init(type: String, description: String? = nil, enum: [String]? = nil) {
        self.type = type
        self.description = description
        self.enum = `enum`
    }
}

public struct MCPInputSchema: Codable, Sendable {
    public let type: String
    public let properties: [String: MCPProperty]
    public let required: [String]?
    
    public init(type: String = "object", properties: [String: MCPProperty], required: [String]? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

public struct MCPToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: MCPInputSchema
    
    public init(name: String, description: String, inputSchema: MCPInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPContent: Codable, Sendable {
    public let type: String // "text" or "image"
    public let text: String?
    public let data: String? // base64 for images
    public let mimeType: String?
    
    public static func text(_ text: String) -> MCPContent {
        MCPContent(type: "text", text: text, data: nil, mimeType: nil)
    }
    
    public static func image(base64: String, mimeType: String = "image/png") -> MCPContent {
        MCPContent(type: "image", text: nil, data: base64, mimeType: mimeType)
    }
    
    public init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.mimeType = mimeType
    }
}

public struct MCPToolCallResult: Codable, Sendable {
    public let content: [MCPContent]
    public let isError: Bool?
    
    public init(content: [MCPContent], isError: Bool? = nil) {
        self.content = content
        self.isError = isError
    }
    
    public static func text(_ text: String) -> MCPToolCallResult {
        MCPToolCallResult(content: [.text(text)], isError: false)
    }
    
    public static func error(_ message: String) -> MCPToolCallResult {
        MCPToolCallResult(content: [.text("Error: \(message)")], isError: true)
    }
}
