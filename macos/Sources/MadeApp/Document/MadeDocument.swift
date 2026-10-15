import SwiftUI
import UniformTypeIdentifiers
import MadeCore

public struct MadeDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.madeDocument] }
    public static var writableContentTypes: [UTType] { [.madeDocument] }

    public var package: MadePackage

    public init(package: MadePackage = MadePackage(documentData: DocumentData(objects: []))) {
        self.package = package
    }

    public init(configuration: ReadConfiguration) throws {
        self.package = try MadePackage(fileWrapper: configuration.file)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try package.makeFileWrapper()
    }
}
