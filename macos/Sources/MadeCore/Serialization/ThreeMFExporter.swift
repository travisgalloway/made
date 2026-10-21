import Foundation
import simd
import OCCTSwift

/// Errors that can occur during 3MF export.
public enum ThreeMFExportError: LocalizedError, Sendable, Equatable {
    case invalidTolerance(Double)
    case noVisibleObjects
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTolerance(let tol):
            return "Invalid tessellation tolerance: \(tol). Tolerance must be positive."
        case .noVisibleObjects:
            return "No visible objects to export"
        case .writeFailed(let message):
            return "Failed to write 3MF file: \(message)"
        }
    }
}

/// Metadata and validation summary resulting from a 3MF export.
public struct ThreeMFExportResult: Sendable, Codable, Equatable {
    public let objectCount: Int
    public let triangleCount: Int
    public let openEdgeCount: Int
    public let warnings: [String]

    public init(objectCount: Int, triangleCount: Int, openEdgeCount: Int = 0, warnings: [String] = []) {
        self.objectCount = objectCount
        self.triangleCount = triangleCount
        self.openEdgeCount = openEdgeCount
        self.warnings = warnings
    }
}

/// Payload representing a body to package into a 3MF container.
public struct ThreeMFBody: Sendable {
    public let name: String
    public let mesh: MeshPayload
    public let transform: Transform
    public let color: SIMD4<Float>

    public init(
        name: String,
        mesh: MeshPayload,
        transform: Transform = .identity,
        color: SIMD4<Float> = SIMD4<Float>(0.35, 0.65, 0.95, 1.0)
    ) {
        self.name = name
        self.mesh = mesh
        self.transform = transform
        self.color = color
    }
}

extension LengthUnit {
    /// The unit identifier string specified in the 3MF Core Specification.
    public var threeMFUnitString: String {
        switch self {
        case .millimeters: return "millimeter"
        case .centimeters: return "centimeter"
        case .meters: return "meter"
        case .inches: return "inch"
        case .feet: return "foot"
        }
    }
}

/// Serializes CAD scene bodies into standard 3MF Open Packaging Conventions (OPC) archives.
public struct ThreeMFExporter: Sendable {
    /// Validates that tessellation tolerance is positive, finite, and not NaN.
    public static func validateTolerance(_ tolerance: Double) -> Bool {
        tolerance > 0 && !tolerance.isNaN && !tolerance.isInfinite
    }

    /// Escapes XML attribute special characters (&, <, >, ", ').
    public static func escapeXMLAttribute(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for char in string {
            switch char {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            case "\"": result.append("&quot;")
            case "'": result.append("&apos;")
            default: result.append(char)
            }
        }
        return result
    }

    /// Formats a SIMD4<Float> color as a 3MF hex color string (#RRGGBBAA).
    public static func hexColor(from color: SIMD4<Float>) -> String {
        let r = Int(round(max(0, min(1, color.x)) * 255.0))
        let g = Int(round(max(0, min(1, color.y)) * 255.0))
        let b = Int(round(max(0, min(1, color.z)) * 255.0))
        let a = Int(round(max(0, min(1, color.w)) * 255.0))
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    /// Formats a float coordinate for XML attribute output.
    private static func formatCoord(_ value: Float) -> String {
        let s = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        if s.contains(".") {
            var trimmed = s
            while trimmed.hasSuffix("0") {
                trimmed.removeLast()
            }
            if trimmed.hasSuffix(".") {
                trimmed.removeLast()
            }
            return trimmed == "-0" ? "0" : trimmed
        }
        return s
    }

    /// Exports an array of bodies to a 3MF file at the specified destination URL.
    @discardableResult
    public static func export(
        bodies: [ThreeMFBody],
        unit: LengthUnit = .millimeters,
        to destinationURL: URL
    ) throws -> ThreeMFExportResult {
        guard !bodies.isEmpty else {
            throw ThreeMFExportError.noVisibleObjects
        }

        let totalTriangles = bodies.reduce(0) { $0 + $1.mesh.triangleCount }
        guard totalTriangles > 0 else {
            throw ThreeMFExportError.writeFailed("No geometry to export")
        }

        var totalOpenEdges = 0
        var warnings: [String] = []

        // Topological analysis for open boundary edges on each body
        for body in bodies {
            let analysis = SolidVerifier.analyzeMesh(body.mesh, transform: body.transform)
            if analysis.openEdgeCount > 0 {
                totalOpenEdges += analysis.openEdgeCount
                warnings.append("Body '\(body.name)' has \(analysis.openEdgeCount) open boundary edges.")
            }
        }

        let destinationDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: destinationDir.path) {
            do {
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            } catch {
                throw ThreeMFExportError.writeFailed("Cannot create directory \(destinationDir.path): \(error.localizedDescription)")
            }
        }

        let tempURL = destinationDir.appendingPathComponent(".tmp.\(UUID().uuidString).3mf")
        defer {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        // 1. [Content_Types].xml
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
        </Types>
        """

        // 2. _rels/.rels
        let relsXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
        </Relationships>
        """

        // 3. 3D/3dmodel.model
        let scaleFactor = Float(unit.fromMillimeters(1.0))
        var modelXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="\(unit.threeMFUnitString)" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources>
            <basematerials id="1">

        """

        for body in bodies {
            let escapedName = escapeXMLAttribute(body.name)
            let colorHex = hexColor(from: body.color)
            modelXML.append("      <base name=\"\(escapedName)\" displaycolor=\"\(colorHex)\" />\n")
        }

        modelXML.append("    </basematerials>\n")

        for (idx, body) in bodies.enumerated() {
            let objectId = idx + 2
            let escapedName = escapeXMLAttribute(body.name)
            modelXML.append("    <object id=\"\(objectId)\" type=\"model\" name=\"\(escapedName)\" pid=\"1\" pindex=\"\(idx)\">\n")
            modelXML.append("      <mesh>\n")
            modelXML.append("        <vertices>\n")

            let positions = body.mesh.positions
            let vertexCount = positions.count / 3
            for v in 0..<vertexCount {
                let p = SIMD3<Float>(positions[v * 3], positions[v * 3 + 1], positions[v * 3 + 2])
                let pt = body.transform.transformPoint(p) * scaleFactor
                modelXML.append("          <vertex x=\"\(formatCoord(pt.x))\" y=\"\(formatCoord(pt.y))\" z=\"\(formatCoord(pt.z))\" />\n")
            }

            modelXML.append("        </vertices>\n")
            modelXML.append("        <triangles>\n")

            let indices = body.mesh.indices
            let triCount = body.mesh.triangleCount
            for t in 0..<triCount {
                let i0 = indices[t * 3]
                let i1 = indices[t * 3 + 1]
                let i2 = indices[t * 3 + 2]
                modelXML.append("          <triangle v1=\"\(i0)\" v2=\"\(i1)\" v3=\"\(i2)\" />\n")
            }

            modelXML.append("        </triangles>\n")
            modelXML.append("      </mesh>\n")
            modelXML.append("    </object>\n")
        }

        modelXML.append("  </resources>\n")
        modelXML.append("  <build>\n")

        for (idx, _) in bodies.enumerated() {
            let objectId = idx + 2
            modelXML.append("    <item objectid=\"\(objectId)\" />\n")
        }

        modelXML.append("  </build>\n")
        modelXML.append("</model>\n")

        guard let contentTypesData = contentTypesXML.data(using: .utf8),
              let relsData = relsXML.data(using: .utf8),
              let modelData = modelXML.data(using: .utf8) else {
            throw ThreeMFExportError.writeFailed("Could not encode 3MF XML payloads")
        }

        let entries = [
            ZipEntry(path: "[Content_Types].xml", data: contentTypesData),
            ZipEntry(path: "_rels/.rels", data: relsData),
            ZipEntry(path: "3D/3dmodel.model", data: modelData)
        ]

        do {
            try ZipArchive.write(entries: entries, to: tempURL)
        } catch {
            throw ThreeMFExportError.writeFailed("Could not write 3MF archive: \(error.localizedDescription)")
        }

        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL, backupItemName: nil, options: .withoutDeletingBackupItem)
            } else {
                try fileManager.moveItem(at: tempURL, to: destinationURL)
            }
        } catch {
            throw ThreeMFExportError.writeFailed("Failed to atomically replace destination file: \(error.localizedDescription)")
        }

        return ThreeMFExportResult(
            objectCount: bodies.count,
            triangleCount: totalTriangles,
            openEdgeCount: totalOpenEdges,
            warnings: warnings
        )
    }

    /// Tessellates visible scene objects and packages them to 3MF at destinationURL.
    @discardableResult
    public static func export(
        objects: [SceneObject],
        tolerance: Double,
        unit: LengthUnit = .millimeters,
        to destinationURL: URL,
        cachedShapes: [SolidId: Shape] = [:],
        cachedMeshes: [SolidId: MeshPayload] = [:]
    ) throws -> ThreeMFExportResult {
        let visibleObjects = objects.filter { $0.isVisible }
        guard !visibleObjects.isEmpty else {
            throw ThreeMFExportError.noVisibleObjects
        }
        guard validateTolerance(tolerance) else {
            throw ThreeMFExportError.invalidTolerance(tolerance)
        }

        var bodies: [ThreeMFBody] = []
        for obj in visibleObjects {
            var meshPayload: MeshPayload?
            if let shape = cachedShapes[obj.id] ?? (try? OCCTEngine.buildShape(for: obj.def, cachedShape: cachedShapes[obj.id])) {
                meshPayload = OCCTEngine.toMeshPayload(shape, deflection: tolerance)
            }
            if meshPayload == nil, let cached = cachedMeshes[obj.id] {
                meshPayload = cached
            }
            if let meshPayload, meshPayload.triangleCount > 0 {
                bodies.append(ThreeMFBody(
                    name: obj.name,
                    mesh: meshPayload,
                    transform: obj.transform,
                    color: obj.material.color
                ))
            }
        }

        guard !bodies.isEmpty else {
            throw ThreeMFExportError.writeFailed("No geometry to export")
        }

        return try export(bodies: bodies, unit: unit, to: destinationURL)
    }
}
