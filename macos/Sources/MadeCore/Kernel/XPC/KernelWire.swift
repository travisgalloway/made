import Foundation
import XPC

/// A message from the app to the kernel service.
enum KernelWireMessage: Codable, Sendable, Equatable {
    case execute(KernelRequest)
    case dispose(SolidId)
    /// Ends the service process. Handled on arrival, ahead of any job that is still running.
    case terminate
}

/// The Codable header of a reply. A non-empty mesh travels beside it as an `xpc_shmem` region.
struct KernelWireReply: Codable, Sendable, Equatable {
    var jobId: JobId
    /// Names the engine that answered. A new value means the service relaunched and its cache is empty.
    var instance = ""
    var error: KernelError?
    var positionCount = 0
    var normalCount = 0
    var indexCount = 0
}

/// Encodes the kernel wire contract into XPC dictionaries. The Codable XPC encoder has no shared-memory type,
/// so headers travel as binary property lists and meshes as `xpc_shmem` (invariant 6).
enum KernelWire {
    static let messageKey = "message"
    static let headerKey = "header"
    static let meshKey = "mesh"
    
    static func encode(_ message: KernelWireMessage) throws -> XPCDictionary {
        var dictionary = XPCDictionary()
        dictionary[messageKey] = try dataObject(message)
        return dictionary
    }
    
    static func decodeMessage(_ dictionary: XPCDictionary) throws -> KernelWireMessage {
        try decode(KernelWireMessage.self, from: dictionary, key: messageKey)
    }
    
    static func encodeReply(_ result: KernelResult<MeshPayload>, instance: String = "") -> XPCDictionary {
        var dictionary = XPCDictionary()
        var header = KernelWireReply(jobId: result.jobId, instance: instance, error: result.error)
        if let storage = result.value?.storage {
            header.positionCount = storage.positionCount
            header.normalCount = storage.normalCount
            header.indexCount = storage.indexCount
            if let base = storage.base {
                dictionary[meshKey] = xpc_shmem_create(base, storage.length)
            }
        }
        // A header of Codable value types always encodes.
        dictionary[headerKey] = try! dataObject(header)
        return dictionary
    }
    
    /// Decodes a reply, mapping its shared region. A missing header or a short region is `geometryFailed`.
    static func decodeReply(_ dictionary: XPCDictionary, jobId: JobId) -> KernelResult<MeshPayload> {
        guard let header = try? decode(KernelWireReply.self, from: dictionary, key: headerKey) else {
            return malformed(jobId, "missing or unreadable header")
        }
        if let error = header.error {
            return .failure(jobId: header.jobId, error: error)
        }
        let counts = [header.positionCount, header.normalCount, header.indexCount]
        guard counts.allSatisfy({ $0 >= 0 }) else { return malformed(jobId, "negative component count") }
        let expectedBytes = counts.reduce(0, +) * MeshStorage.elementSize
        guard expectedBytes > 0 else {
            return .success(jobId: header.jobId, value: MeshPayload(positions: [], normals: [], indices: []))
        }
        guard let shmem = dictionary[meshKey, as: XPC_TYPE_SHMEM] else { return malformed(jobId, "mesh region missing") }
        var region: UnsafeMutableRawPointer?
        let mappedLength = xpc_shmem_map(shmem, &region)
        guard let region, mappedLength > 0 else { return malformed(jobId, "mesh region could not be mapped") }
        guard mappedLength >= expectedBytes else {
            munmap(region, mappedLength)
            return malformed(jobId, "mesh region holds \(mappedLength) bytes, header needs \(expectedBytes)")
        }
        let storage = MeshStorage(adopting: region, length: mappedLength, positionCount: header.positionCount,
                                  normalCount: header.normalCount, indexCount: header.indexCount)
        return .success(jobId: header.jobId, value: MeshPayload(storage: storage))
    }
    
    /// The answering engine's instance, or nil when the header is unreadable.
    static func instance(of dictionary: XPCDictionary) -> String? {
        (try? decode(KernelWireReply.self, from: dictionary, key: headerKey))?.instance
    }
    
    static func dataObject<T: Encodable>(_ value: T) throws -> xpc_object_t {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(value)
        return data.withUnsafeBytes { xpc_data_create($0.baseAddress, $0.count) }
    }
    
    private static func decode<T: Decodable>(_ type: T.Type, from dictionary: XPCDictionary, key: String) throws -> T {
        guard let object = dictionary[key, as: XPC_TYPE_DATA], let bytes = xpc_data_get_bytes_ptr(object) else {
            throw CocoaError(.coderValueNotFound)
        }
        let data = Data(bytes: bytes, count: xpc_data_get_length(object))
        return try PropertyListDecoder().decode(type, from: data)
    }
    
    private static func malformed(_ jobId: JobId, _ detail: String) -> KernelResult<MeshPayload> {
        .failure(jobId: jobId, error: KernelError(code: .geometryFailed, message: "Malformed kernel reply: \(detail)"))
    }
}
