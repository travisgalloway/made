import Foundation

/// Represents a single file entry in an uncompressed (STORED) ZIP archive.
public struct ZipEntry: Sendable, Equatable {
    public let path: String
    public let data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

/// Errors that can occur during ZIP archive creation or reading.
public enum ZipError: LocalizedError, Sendable, Equatable {
    case invalidArchive
    case unsupportedCompression(UInt16)
    case checksumMismatch(expected: UInt32, actual: UInt32)
    case writeFailed(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "The archive is corrupted or not a valid ZIP file."
        case .unsupportedCompression(let method):
            return "Unsupported ZIP compression method: \(method). Only STORED (0) is supported."
        case .checksumMismatch(let expected, let actual):
            return "CRC-32 checksum mismatch: expected \(String(format: "0x%08X", expected)), got \(String(format: "0x%08X", actual))."
        case .writeFailed(let message):
            return "Failed to write ZIP archive: \(message)"
        case .fileNotFound(let path):
            return "Entry '\(path)' was not found in the ZIP archive."
        }
    }
}

/// IEEE 802.3 32-bit Cyclic Redundancy Check (CRC-32).
public enum CRC32: Sendable {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c >>= 1
                }
            }
            return c
        }
    }()

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

/// Pure Swift uncompressed (STORED) ZIP archive reader and writer.
public struct ZipArchive: Sendable {
    public var entries: [ZipEntry]

    public init(entries: [ZipEntry] = []) {
        self.entries = entries
    }

    public func entry(for path: String) -> ZipEntry? {
        entries.first { $0.path == path }
    }

    public func string(for path: String) -> String? {
        entry(for: path).flatMap { String(data: $0.data, encoding: .utf8) }
    }

    public static func entry(named path: String, in entries: [ZipEntry]) -> ZipEntry? {
        entries.first { $0.path == path }
    }

    public static func string(named path: String, in entries: [ZipEntry]) -> String? {
        entry(named: path, in: entries).flatMap { String(data: $0.data, encoding: .utf8) }
    }

    /// Converts date to MS-DOS date and time bitfields.
    public static func dosDateTime(from date: Date = Date()) -> (date: UInt16, time: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, components.year ?? 1980) - 1980
        let month = max(1, min(12, components.month ?? 1))
        let day = max(1, min(31, components.day ?? 1))
        let hour = max(0, min(23, components.hour ?? 0))
        let minute = max(0, min(59, components.minute ?? 0))
        let second = max(0, min(59, components.second ?? 0)) / 2

        let dosDate = UInt16(((year & 0x7F) << 9) | ((month & 0x0F) << 5) | (day & 0x1F))
        let dosTime = UInt16(((hour & 0x1F) << 11) | ((minute & 0x3F) << 5) | (second & 0x1F))
        return (dosDate, dosTime)
    }

    /// Creates an uncompressed ZIP archive payload from the provided entries.
    public static func create(entries: [ZipEntry], timestamp: Date = Date()) -> Data {
        var localData = Data()
        var centralDirectoryData = Data()
        let (dosDate, dosTime) = dosDateTime(from: timestamp)

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let localHeaderOffset = UInt32(localData.count)

            // 1. Local File Header
            localData.appendUInt32LE(0x04034b50) // Local file header signature
            localData.appendUInt16LE(20)         // Version needed to extract (2.0)
            localData.appendUInt16LE(0x0800)     // UTF-8 filename flag
            localData.appendUInt16LE(0)          // Compression method (0 = STORED)
            localData.appendUInt16LE(dosTime)
            localData.appendUInt16LE(dosDate)
            localData.appendUInt32LE(crc)
            localData.appendUInt32LE(size)       // Compressed size
            localData.appendUInt32LE(size)       // Uncompressed size
            localData.appendUInt16LE(UInt16(nameData.count))
            localData.appendUInt16LE(0)          // Extra field length
            localData.append(nameData)
            localData.append(entry.data)

            // 2. Central Directory Header
            centralDirectoryData.appendUInt32LE(0x02014b50) // Central directory signature
            centralDirectoryData.appendUInt16LE(20)         // Version made by (2.0)
            centralDirectoryData.appendUInt16LE(20)         // Version needed to extract (2.0)
            centralDirectoryData.appendUInt16LE(0x0800)     // UTF-8 filename flag
            centralDirectoryData.appendUInt16LE(0)          // Compression method (0 = STORED)
            centralDirectoryData.appendUInt16LE(dosTime)
            centralDirectoryData.appendUInt16LE(dosDate)
            centralDirectoryData.appendUInt32LE(crc)
            centralDirectoryData.appendUInt32LE(size)
            centralDirectoryData.appendUInt32LE(size)
            centralDirectoryData.appendUInt16LE(UInt16(nameData.count))
            centralDirectoryData.appendUInt16LE(0)          // Extra field length
            centralDirectoryData.appendUInt16LE(0)          // File comment length
            centralDirectoryData.appendUInt16LE(0)          // Disk number start
            centralDirectoryData.appendUInt16LE(0)          // Internal attributes
            centralDirectoryData.appendUInt32LE(0)          // External attributes
            centralDirectoryData.appendUInt32LE(localHeaderOffset)
            centralDirectoryData.append(nameData)
        }

        let centralDirectoryOffset = UInt32(localData.count)
        let centralDirectorySize = UInt32(centralDirectoryData.count)
        let entryCount = UInt16(entries.count)

        // 3. End of Central Directory Record (EOCD)
        var eocd = Data()
        eocd.appendUInt32LE(0x06054b50) // EOCD signature
        eocd.appendUInt16LE(0)          // Disk number
        eocd.appendUInt16LE(0)          // Start disk
        eocd.appendUInt16LE(entryCount) // Total entries on disk
        eocd.appendUInt16LE(entryCount) // Total entries in central directory
        eocd.appendUInt32LE(centralDirectorySize)
        eocd.appendUInt32LE(centralDirectoryOffset)
        eocd.appendUInt16LE(0)          // Comment length

        var archiveData = Data()
        archiveData.append(localData)
        archiveData.append(centralDirectoryData)
        archiveData.append(eocd)
        return archiveData
    }

    /// Reads and unpacks entries from an uncompressed (STORED) ZIP archive payload.
    public static func read(from data: Data) throws -> [ZipEntry] {
        guard data.count >= 22 else {
            throw ZipError.invalidArchive
        }

        var eocdOffset: Int?
        let minEocdOffset = max(0, data.count - 65535 - 22)
        for offset in stride(from: data.count - 22, through: minEocdOffset, by: -1) {
            if data[offset] == 0x50 && data[offset + 1] == 0x4b && data[offset + 2] == 0x05 && data[offset + 3] == 0x06 {
                eocdOffset = offset
                break
            }
        }

        guard let eocdPos = eocdOffset else {
            throw ZipError.invalidArchive
        }

        let entryCount = Int(data.readUInt16LE(at: eocdPos + 10))
        let centralDirectorySize = Int(data.readUInt32LE(at: eocdPos + 12))
        let centralDirectoryOffset = Int(data.readUInt32LE(at: eocdPos + 16))

        guard centralDirectoryOffset + centralDirectorySize <= data.count else {
            throw ZipError.invalidArchive
        }

        var entries: [ZipEntry] = []
        entries.reserveCapacity(entryCount)
        var cdCursor = centralDirectoryOffset

        for _ in 0..<entryCount {
            guard cdCursor + 46 <= data.count else { throw ZipError.invalidArchive }
            let sig = data.readUInt32LE(at: cdCursor)
            guard sig == 0x02014b50 else { throw ZipError.invalidArchive }

            let compression = data.readUInt16LE(at: cdCursor + 10)
            let expectedCRC = data.readUInt32LE(at: cdCursor + 16)
            let compressedSize = Int(data.readUInt32LE(at: cdCursor + 20))
            let nameLen = Int(data.readUInt16LE(at: cdCursor + 28))
            let extraLen = Int(data.readUInt16LE(at: cdCursor + 30))
            let commentLen = Int(data.readUInt16LE(at: cdCursor + 32))
            let localOffset = Int(data.readUInt32LE(at: cdCursor + 42))

            guard cdCursor + 46 + nameLen <= data.count else { throw ZipError.invalidArchive }
            let nameData = data.subdata(in: (cdCursor + 46)..<(cdCursor + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)

            cdCursor += 46 + nameLen + extraLen + commentLen

            guard compression == 0 else {
                throw ZipError.unsupportedCompression(compression)
            }

            guard localOffset + 30 <= data.count else { throw ZipError.invalidArchive }
            let localSig = data.readUInt32LE(at: localOffset)
            guard localSig == 0x04034b50 else { throw ZipError.invalidArchive }

            let localNameLen = Int(data.readUInt16LE(at: localOffset + 26))
            let localExtraLen = Int(data.readUInt16LE(at: localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            let dataEnd = dataStart + compressedSize

            guard dataEnd <= data.count else { throw ZipError.invalidArchive }
            let entryData = data.subdata(in: dataStart..<dataEnd)

            let actualCRC = CRC32.checksum(entryData)
            guard actualCRC == expectedCRC else {
                throw ZipError.checksumMismatch(expected: expectedCRC, actual: actualCRC)
            }

            entries.append(ZipEntry(path: name, data: entryData))
        }

        return entries
    }

    /// Writes entries as a ZIP file to the destination URL.
    public static func write(entries: [ZipEntry], to url: URL) throws {
        let data = create(entries: entries)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ZipError.writeFailed(error.localizedDescription)
        }
    }

    /// Reads and unpacks entries from a ZIP file at the provided URL.
    public static func read(from url: URL) throws -> [ZipEntry] {
        let data = try Data(contentsOf: url)
        return try read(from: data)
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1])
        return b0 | (b1 << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }
}
