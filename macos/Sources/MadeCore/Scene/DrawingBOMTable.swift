import Foundation
import simd

/// Columns available for display in a drawing Bill of Materials table (BL-DRW-08, #215).
public enum DrawingBOMColumn: String, Sendable, Codable, CaseIterable, Identifiable {
    case itemNumber
    case name
    case partNumber
    case description
    case quantity
    case material
    case revision
    case vendor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .itemNumber: return "Item"
        case .name: return "Name"
        case .partNumber: return "Part Number"
        case .description: return "Description"
        case .quantity: return "Qty"
        case .material: return "Material"
        case .revision: return "Rev"
        case .vendor: return "Vendor"
        }
    }

    /// Default width in millimeters for this column.
    public var defaultWidthMM: Double {
        switch self {
        case .itemNumber: return 16.0
        case .name: return 45.0
        case .partNumber: return 40.0
        case .description: return 60.0
        case .quantity: return 16.0
        case .material: return 30.0
        case .revision: return 16.0
        case .vendor: return 30.0
        }
    }

    /// Resolves the display string value for this column from a BOM item.
    public func value(for item: BOMItem) -> String {
        switch self {
        case .itemNumber: return item.itemNumber
        case .name: return item.name
        case .partNumber: return item.partNumber
        case .description: return item.description
        case .quantity: return "\(item.quantity)"
        case .material: return item.material
        case .revision: return item.revision
        case .vendor: return item.vendor
        }
    }
}

/// Represents a tabular Bill of Materials placed on a 2D drawing sheet (BL-DRW-08, #215).
public struct DrawingBOMTable: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var name: String
    /// Position in sheet coordinates (millimeters), anchor corner (top-left).
    public var positionMM: SIMD2<Double>
    public var structure: BOMStructure
    public var columns: [DrawingBOMColumn]
    public var title: String
    public var showTitle: Bool
    public var fontSizePt: Double
    public var rowHeightMM: Double
    /// Optional overrides for individual column widths in millimeters (keyed by column raw value).
    public var customColumnWidths: [String: Double]

    public static let defaultColumns: [DrawingBOMColumn] = [
        .itemNumber,
        .partNumber,
        .name,
        .description,
        .quantity
    ]

    public static let placeholderItem = BOMItem(
        itemNumber: "1",
        name: "No components",
        partNumber: "-",
        description: "Empty parts list",
        quantity: 0
    )

    public init(
        id: UUID = UUID(),
        name: String = "BOM Table 1",
        positionMM: SIMD2<Double> = SIMD2<Double>(20.0, 20.0),
        structure: BOMStructure = .flat,
        columns: [DrawingBOMColumn] = Self.defaultColumns,
        title: String = "BILL OF MATERIALS",
        showTitle: Bool = true,
        fontSizePt: Double = 9.0,
        rowHeightMM: Double = 7.0,
        customColumnWidths: [String: Double] = [:]
    ) {
        self.id = id
        self.name = name
        self.positionMM = positionMM
        self.structure = structure
        self.columns = columns.isEmpty ? Self.defaultColumns : columns
        self.title = title
        self.showTitle = showTitle
        self.fontSizePt = fontSizePt
        self.rowHeightMM = max(4.0, rowHeightMM)
        self.customColumnWidths = customColumnWidths
    }

    /// Resolved width for a specific column in millimeters, incorporating any custom width overrides.
    public func width(for column: DrawingBOMColumn) -> Double {
        if let custom = customColumnWidths[column.rawValue], custom > 0 {
            return custom
        }
        return column.defaultWidthMM
    }

    /// Total table width in millimeters across all enabled columns.
    public var totalWidthMM: Double {
        columns.reduce(0.0) { $0 + width(for: $1) }
    }

    /// Total table height in millimeters including title, header, and data rows.
    public func totalHeightMM(rowCount: Int) -> Double {
        let titleHeight = showTitle ? rowHeightMM : 0.0
        let headerHeight = rowHeightMM
        let dataHeight = Double(max(1, rowCount)) * rowHeightMM
        return titleHeight + headerHeight + dataHeight
    }

    /// Resolves the BOM items to display for this table from the document, falling back to a placeholder row if empty.
    @MainActor
    public func resolvedItems(from document: DocumentModel) -> [BOMItem] {
        let bom = BillOfMaterials.generate(from: document, structure: structure)
        if bom.items.isEmpty {
            return [Self.placeholderItem]
        }
        return bom.items
    }
}
