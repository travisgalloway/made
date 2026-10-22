import Foundation

/// Structural organization mode for Bill of Materials (BL-ASM-10, #173).
public enum BOMStructure: String, Sendable, Codable, CaseIterable {
    case flat
    case hierarchical

    public var displayName: String {
        switch self {
        case .flat: return "Flat"
        case .hierarchical: return "Hierarchical"
        }
    }
}

/// A line item in a Bill of Materials.
public struct BOMItem: Identifiable, Sendable, Codable, Equatable {
    public var id: String { "\(itemNumber):\(name):\(partNumber)" }
    public var itemNumber: String
    public var level: Int
    public var name: String
    public var partNumber: String
    public var description: String
    public var revision: String
    public var vendor: String
    public var material: String
    public var quantity: Int
    public var isSubassembly: Bool
    public var customProperties: [String: String]

    public init(
        itemNumber: String,
        level: Int = 1,
        name: String,
        partNumber: String = "",
        description: String = "",
        revision: String = "",
        vendor: String = "",
        material: String = "",
        quantity: Int = 1,
        isSubassembly: Bool = false,
        customProperties: [String: String] = [:]
    ) {
        self.itemNumber = itemNumber
        self.level = level
        self.name = name
        self.partNumber = partNumber
        self.description = description
        self.revision = revision
        self.vendor = vendor
        self.material = material
        self.quantity = quantity
        self.isSubassembly = isSubassembly
        self.customProperties = customProperties
    }
}

/// Errors occurring during Bill of Materials CSV export.
public enum BOMExportError: LocalizedError, Sendable {
    case encodingFailed
    case emptyDocument

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode Bill of Materials to UTF-8."
        case .emptyDocument:
            return "Cannot export Bill of Materials from an empty assembly."
        }
    }
}

/// A complete Bill of Materials generated from an assembly document or component hierarchy.
public struct BillOfMaterials: Sendable, Codable, Equatable {
    public var structure: BOMStructure
    public var items: [BOMItem]
    public var customPropertyKeys: [String]

    public init(
        structure: BOMStructure,
        items: [BOMItem],
        customPropertyKeys: [String] = []
    ) {
        self.structure = structure
        self.items = items
        self.customPropertyKeys = customPropertyKeys
    }

    /// Generates a Bill of Materials from an assembly or part document model.
    @MainActor
    public static func generate(from document: DocumentModel, structure: BOMStructure) -> BillOfMaterials {
        if !document.componentInstances.isEmpty {
            return generate(from: document.componentInstances, structure: structure)
        }

        // Multi-body part drawings: synthesize BOM items from document objects
        let visibleObjects = document.objects.filter { $0.isVisible }
        let objectsToInclude = visibleObjects.isEmpty ? document.objects : visibleObjects
        guard !objectsToInclude.isEmpty else {
            return BillOfMaterials(structure: structure, items: [], customPropertyKeys: [])
        }

        var items: [BOMItem] = []
        for (index, obj) in objectsToInclude.enumerated() {
            let partNumber = obj.metadata.property(forKey: CustomPropertyKey.partNumber)
                ?? obj.metadata.property(forKey: "partNumber")
                ?? ""
            let description = obj.metadata.property(forKey: CustomPropertyKey.description)
                ?? obj.metadata.property(forKey: "description")
                ?? ""
            let revision = obj.metadata.property(forKey: CustomPropertyKey.revision)
                ?? obj.metadata.property(forKey: "revision")
                ?? ""
            let vendor = obj.metadata.property(forKey: CustomPropertyKey.vendor)
                ?? obj.metadata.property(forKey: "vendor")
                ?? ""
            let material = obj.metadata.property(forKey: "material")
                ?? obj.metadata.property(forKey: "Material")
                ?? ""

            var custom: [String: String] = [:]
            for (k, v) in obj.metadata {
                let trimmedKey = k.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedKey.isEmpty else { continue }
                if !standardPropertyNames.contains(trimmedKey.lowercased()) {
                    custom[trimmedKey] = v
                }
            }

            items.append(BOMItem(
                itemNumber: "\(index + 1)",
                level: 1,
                name: obj.name,
                partNumber: partNumber,
                description: description,
                revision: revision,
                vendor: vendor,
                material: material,
                quantity: 1,
                isSubassembly: false,
                customProperties: custom
            ))
        }

        let customKeys = Array(Set(items.flatMap { $0.customProperties.keys })).sorted()
        return BillOfMaterials(structure: structure, items: items, customPropertyKeys: customKeys)
    }

    /// Generates a Bill of Materials from an array of root component instances.
    public static func generate(from instances: [ComponentInstance], structure: BOMStructure) -> BillOfMaterials {
        switch structure {
        case .flat:
            return generateFlat(from: instances)
        case .hierarchical:
            return generateHierarchical(from: instances)
        }
    }

    // MARK: - Flat BOM Generation

    private static func generateFlat(from instances: [ComponentInstance]) -> BillOfMaterials {
        struct AggregatedEntry {
            var name: String
            var partNumber: String
            var description: String
            var revision: String
            var vendor: String
            var material: String
            var quantity: Int
            var customProperties: [String: String]
            var referenceKey: String
        }

        var aggregated: [String: AggregatedEntry] = [:]

        func walk(instance: ComponentInstance, multiplier: Int) {
            if instance.isSubassembly {
                for child in instance.childInstances {
                    walk(instance: child, multiplier: multiplier)
                }
            } else {
                let props = extractProperties(from: instance)
                let pn = props.partNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                let refKey = referenceKey(for: instance.reference)

                let groupKey: String
                if !pn.isEmpty {
                    groupKey = "pn:\(pn)"
                } else {
                    groupKey = "ref:\(props.name):\(refKey)"
                }

                if var existing = aggregated[groupKey] {
                    existing.quantity += multiplier
                    if existing.description.isEmpty && !props.description.isEmpty {
                        existing.description = props.description
                    }
                    if existing.revision.isEmpty && !props.revision.isEmpty {
                        existing.revision = props.revision
                    }
                    if existing.vendor.isEmpty && !props.vendor.isEmpty {
                        existing.vendor = props.vendor
                    }
                    if existing.material.isEmpty && !props.material.isEmpty {
                        existing.material = props.material
                    }
                    for (k, v) in props.customProperties where existing.customProperties[k] == nil {
                        existing.customProperties[k] = v
                    }
                    aggregated[groupKey] = existing
                } else {
                    aggregated[groupKey] = AggregatedEntry(
                        name: props.name,
                        partNumber: pn,
                        description: props.description,
                        revision: props.revision,
                        vendor: props.vendor,
                        material: props.material,
                        quantity: multiplier,
                        customProperties: props.customProperties,
                        referenceKey: refKey
                    )
                }
            }
        }

        for instance in instances {
            walk(instance: instance, multiplier: 1)
        }

        // Deterministic sorting: Part Number ascending, then Name ascending, then referenceKey
        let sortedEntries = aggregated.values.sorted { a, b in
            if a.partNumber != b.partNumber {
                return a.partNumber < b.partNumber
            }
            if a.name != b.name {
                return a.name < b.name
            }
            return a.referenceKey < b.referenceKey
        }

        var items: [BOMItem] = []
        for (index, entry) in sortedEntries.enumerated() {
            items.append(BOMItem(
                itemNumber: "\(index + 1)",
                level: 1,
                name: entry.name,
                partNumber: entry.partNumber,
                description: entry.description,
                revision: entry.revision,
                vendor: entry.vendor,
                material: entry.material,
                quantity: entry.quantity,
                isSubassembly: false,
                customProperties: entry.customProperties
            ))
        }

        let customKeys = Array(Set(items.flatMap { $0.customProperties.keys })).sorted()
        return BillOfMaterials(structure: .flat, items: items, customPropertyKeys: customKeys)
    }

    // MARK: - Hierarchical BOM Generation

    private static func generateHierarchical(from instances: [ComponentInstance]) -> BillOfMaterials {
        var items: [BOMItem] = []

        func traverse(instance: ComponentInstance, prefix: String, index: Int, level: Int) {
            let itemNumber = "\(prefix)\(index + 1)"
            let props = extractProperties(from: instance)

            let item = BOMItem(
                itemNumber: itemNumber,
                level: level,
                name: props.name,
                partNumber: props.partNumber,
                description: props.description,
                revision: props.revision,
                vendor: props.vendor,
                material: props.material,
                quantity: 1,
                isSubassembly: instance.isSubassembly,
                customProperties: props.customProperties
            )
            items.append(item)

            if instance.isSubassembly {
                for (childIndex, child) in instance.childInstances.enumerated() {
                    traverse(instance: child, prefix: "\(itemNumber).", index: childIndex, level: level + 1)
                }
            }
        }

        for (index, instance) in instances.enumerated() {
            traverse(instance: instance, prefix: "", index: index, level: 1)
        }

        let customKeys = Array(Set(items.flatMap { $0.customProperties.keys })).sorted()
        return BillOfMaterials(structure: .hierarchical, items: items, customPropertyKeys: customKeys)
    }

    // MARK: - Property Extraction and Reference Helpers

    private static let standardPropertyNames: Set<String> = [
        "partnumber",
        "part_number",
        "description",
        "itemdescription",
        "revision",
        "vendor",
        "material"
    ]

    private static func extractProperties(from instance: ComponentInstance) -> (
        name: String,
        partNumber: String,
        description: String,
        revision: String,
        vendor: String,
        material: String,
        customProperties: [String: String]
    ) {
        let name = instance.name
        let partNumber = instance.partNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? instance.metadata.property(forKey: CustomPropertyKey.partNumber)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let description = instance.itemDescription
            ?? instance.metadata.property(forKey: CustomPropertyKey.description)
            ?? instance.metadata.property(forKey: "Description")
            ?? ""
        let revision = instance.revision
            ?? instance.metadata.property(forKey: CustomPropertyKey.revision)
            ?? instance.metadata.property(forKey: "Revision")
            ?? ""
        let vendor = instance.vendor
            ?? instance.metadata.property(forKey: CustomPropertyKey.vendor)
            ?? instance.metadata.property(forKey: "Vendor")
            ?? ""
        let material = instance.metadata.property(forKey: "material")
            ?? instance.metadata.property(forKey: "Material")
            ?? ""

        var custom: [String: String] = [:]
        for (k, v) in instance.metadata {
            let trimmedKey = k.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { continue }
            let lower = trimmedKey.lowercased()
            if !standardPropertyNames.contains(lower) {
                custom[trimmedKey] = v
            }
        }

        return (name, partNumber, description, revision, vendor, material, custom)
    }

    private static func referenceKey(for ref: ComponentReference) -> String {
        switch ref {
        case .internalPart(let name, let bodyId):
            return "internalPart:\(name):\(bodyId?.rawValue ?? "")"
        case .externalDocument(let url, let partName):
            return "externalDocument:\(url.standardizedFileURL.path):\(partName ?? "")"
        case .subassembly(let name):
            return "subassembly:\(name)"
        }
    }

    // MARK: - RFC 4180 CSV Serialization

    /// Escapes a field according to RFC 4180.
    ///
    /// If the field contains a comma, quotation mark, newline, or carriage return,
    /// it is enclosed in double quotes and existing double quotes are doubled (`""`).
    public static func escapeCSVField(_ field: String) -> String {
        let needsQuoting = field.unicodeScalars.contains { scalar in
            scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r"
        }
        if needsQuoting {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        } else {
            return field
        }
    }

    /// Serializes the Bill of Materials to an RFC 4180 compliant CSV string.
    public func toCSV() -> String {
        var lines: [String] = []

        switch structure {
        case .flat:
            var headers = ["Item", "Name", "Part Number", "Description", "Revision", "Vendor", "Material", "Quantity"]
            headers.append(contentsOf: customPropertyKeys)
            lines.append(headers.map { Self.escapeCSVField($0) }.joined(separator: ","))

            for item in items {
                var row: [String] = [
                    Self.escapeCSVField(item.itemNumber),
                    Self.escapeCSVField(item.name),
                    Self.escapeCSVField(item.partNumber),
                    Self.escapeCSVField(item.description),
                    Self.escapeCSVField(item.revision),
                    Self.escapeCSVField(item.vendor),
                    Self.escapeCSVField(item.material),
                    String(item.quantity)
                ]
                for key in customPropertyKeys {
                    row.append(Self.escapeCSVField(item.customProperties[key] ?? ""))
                }
                lines.append(row.joined(separator: ","))
            }

        case .hierarchical:
            var headers = ["Item", "Level", "Name", "Part Number", "Description", "Revision", "Vendor", "Material", "Quantity", "Type"]
            headers.append(contentsOf: customPropertyKeys)
            lines.append(headers.map { Self.escapeCSVField($0) }.joined(separator: ","))

            for item in items {
                var row: [String] = [
                    Self.escapeCSVField(item.itemNumber),
                    String(item.level),
                    Self.escapeCSVField(item.name),
                    Self.escapeCSVField(item.partNumber),
                    Self.escapeCSVField(item.description),
                    Self.escapeCSVField(item.revision),
                    Self.escapeCSVField(item.vendor),
                    Self.escapeCSVField(item.material),
                    String(item.quantity),
                    Self.escapeCSVField(item.isSubassembly ? "Subassembly" : "Part")
                ]
                for key in customPropertyKeys {
                    row.append(Self.escapeCSVField(item.customProperties[key] ?? ""))
                }
                lines.append(row.joined(separator: ","))
            }
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Exports the Bill of Materials to a destination CSV file atomically.
    public func exportCSV(to destinationURL: URL) throws {
        let parentDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        let csvContent = toCSV()
        guard let data = csvContent.data(using: .utf8) else {
            throw BOMExportError.encodingFailed
        }
        try data.write(to: destinationURL, options: .atomic)
    }
}
