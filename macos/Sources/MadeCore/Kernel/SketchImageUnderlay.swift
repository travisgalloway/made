import Foundation
import simd
import ImageIO

/// Typed errors encountered during sketch image underlay creation and scale calibration.
public enum SketchUnderlayError: Error, Equatable, Sendable, LocalizedError {
    case degenerateDistance
    case nonFiniteCoordinates
    case coincidentPoints
    case invalidImageData

    public var errorDescription: String? {
        switch self {
        case .degenerateDistance:
            return "Target distance must be a positive finite number."
        case .nonFiniteCoordinates:
            return "Calibration points must have finite coordinates."
        case .coincidentPoints:
            return "Calibration points must not be coincident."
        case .invalidImageData:
            return "The image data is invalid or corrupt."
        }
    }
}

/// A reference raster image underlay placed on a 2D sketch plane.
public struct SketchImageUnderlay: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var imageData: Data?
    public var assetFilename: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var origin: SIMD2<Double>
    public var width: Double
    public var height: Double
    public var rotationAngle: Double // radians
    public var opacity: Double {
        didSet {
            opacity = min(max(opacity, 0.0), 1.0)
        }
    }
    public var isLocked: Bool
    public var isVisible: Bool
    public var preserveAspectRatio: Bool

    /// Alias for `origin` matching geometric property conventions.
    public var position: SIMD2<Double> {
        get { origin }
        set { origin = newValue }
    }

    /// Alias for `rotationAngle` matching rotation property conventions.
    public var rotation: Double {
        get { rotationAngle }
        set { rotationAngle = newValue }
    }

    public init(
        id: UUID = UUID(),
        name: String = "Image Underlay",
        imageData: Data? = nil,
        assetFilename: String? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        origin: SIMD2<Double> = .zero,
        width: Double = 100.0,
        height: Double = 100.0,
        rotationAngle: Double = 0.0,
        opacity: Double = 1.0,
        isLocked: Bool = false,
        isVisible: Bool = true,
        preserveAspectRatio: Bool = true
    ) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.assetFilename = assetFilename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.origin = origin
        self.width = width
        self.height = height
        self.rotationAngle = rotationAngle
        self.opacity = min(max(opacity, 0.0), 1.0)
        self.isLocked = isLocked
        self.isVisible = isVisible
        self.preserveAspectRatio = preserveAspectRatio
    }

    /// Convenience initializer creating an underlay from image data and extracting pixel dimensions via CGImageSource.
    public init(
        id: UUID = UUID(),
        name: String = "Image Underlay",
        imageData: Data,
        assetFilename: String? = nil,
        origin: SIMD2<Double> = .zero,
        width: Double? = nil,
        height: Double? = nil,
        rotationAngle: Double = 0.0,
        opacity: Double = 1.0,
        isLocked: Bool = false,
        isVisible: Bool = true,
        preserveAspectRatio: Bool = true
    ) throws {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw SketchUnderlayError.invalidImageData
        }

        var pWidth: Int?
        var pHeight: Int?
        if let w = properties[kCGImagePropertyPixelWidth] as? NSNumber {
            pWidth = w.intValue
        } else if let w = properties[kCGImagePropertyPixelWidth] as? Int {
            pWidth = w
        }
        if let h = properties[kCGImagePropertyPixelHeight] as? NSNumber {
            pHeight = h.intValue
        } else if let h = properties[kCGImagePropertyPixelHeight] as? Int {
            pHeight = h
        }

        guard let pw = pWidth, let ph = pHeight, pw > 0, ph > 0 else {
            throw SketchUnderlayError.invalidImageData
        }

        let defaultWidth = Double(pw)
        let defaultHeight = Double(ph)

        self.id = id
        self.name = name
        self.imageData = imageData
        self.assetFilename = assetFilename
        self.pixelWidth = pw
        self.pixelHeight = ph
        self.origin = origin
        self.width = width ?? defaultWidth
        self.height = height ?? defaultHeight
        self.rotationAngle = rotationAngle
        self.opacity = min(max(opacity, 0.0), 1.0)
        self.isLocked = isLocked
        self.isVisible = isVisible
        self.preserveAspectRatio = preserveAspectRatio
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case imageData
        case assetFilename
        case pixelWidth
        case pixelHeight
        case origin
        case position
        case width
        case height
        case rotationAngle
        case rotation
        case opacity
        case isLocked
        case isVisible
        case preserveAspectRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Image Underlay"
        self.imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        self.assetFilename = try container.decodeIfPresent(String.self, forKey: .assetFilename)
        self.pixelWidth = try container.decodeIfPresent(Int.self, forKey: .pixelWidth) ?? 0
        self.pixelHeight = try container.decodeIfPresent(Int.self, forKey: .pixelHeight) ?? 0

        if let orig = try container.decodeIfPresent(SIMD2<Double>.self, forKey: .origin) {
            self.origin = orig
        } else if let pos = try container.decodeIfPresent(SIMD2<Double>.self, forKey: .position) {
            self.origin = pos
        } else {
            self.origin = .zero
        }

        self.width = try container.decodeIfPresent(Double.self, forKey: .width) ?? Double(max(self.pixelWidth, 100))
        self.height = try container.decodeIfPresent(Double.self, forKey: .height) ?? Double(max(self.pixelHeight, 100))

        if let rotAngle = try container.decodeIfPresent(Double.self, forKey: .rotationAngle) {
            self.rotationAngle = rotAngle
        } else if let rot = try container.decodeIfPresent(Double.self, forKey: .rotation) {
            self.rotationAngle = rot
        } else {
            self.rotationAngle = 0.0
        }

        let op = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        self.opacity = min(max(op, 0.0), 1.0)
        self.isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        self.isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        self.preserveAspectRatio = try container.decodeIfPresent(Bool.self, forKey: .preserveAspectRatio) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encodeIfPresent(assetFilename, forKey: .assetFilename)
        try container.encode(pixelWidth, forKey: .pixelWidth)
        try container.encode(pixelHeight, forKey: .pixelHeight)
        try container.encode(origin, forKey: .origin)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(rotationAngle, forKey: .rotationAngle)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(preserveAspectRatio, forKey: .preserveAspectRatio)
    }

    /// Sets width, adjusting height proportionally if `preserveAspectRatio` is active.
    public mutating func setWidth(_ newWidth: Double) {
        width = newWidth
        if preserveAspectRatio && pixelWidth > 0 {
            height = newWidth * Double(pixelHeight) / Double(pixelWidth)
        }
    }

    /// Sets height, adjusting width proportionally if `preserveAspectRatio` is active.
    public mutating func setHeight(_ newHeight: Double) {
        height = newHeight
        if preserveAspectRatio && pixelHeight > 0 {
            width = newHeight * Double(pixelWidth) / Double(pixelHeight)
        }
    }

    /// Calibrates the scale of the underlay using two reference points and a known real-world target distance.
    /// Uniformly scales width and height while anchoring origin so that `point1` stays fixed.
    public mutating func calibrate(
        point1: SIMD2<Double>,
        point2: SIMD2<Double>,
        targetDistance: Double
    ) throws {
        guard targetDistance > 0 && targetDistance.isFinite else {
            throw SketchUnderlayError.degenerateDistance
        }
        guard point1.x.isFinite && point1.y.isFinite && point2.x.isFinite && point2.y.isFinite else {
            throw SketchUnderlayError.nonFiniteCoordinates
        }
        let currentDist = hypot(point2.x - point1.x, point2.y - point1.y)
        guard currentDist > 1e-9 else {
            throw SketchUnderlayError.coincidentPoints
        }

        let scaleFactor = targetDistance / currentDist
        width *= scaleFactor
        height *= scaleFactor
        origin = point1 + (origin - point1) * scaleFactor
    }

    /// Calculates 4 unprojected world-space coordinates (bottom-left, bottom-right, top-right, top-left) on the given sketch plane.
    public func corners(on plane: SketchPlane) -> [SIMD3<Float>] {
        let cosR = cos(rotationAngle)
        let sinR = sin(rotationAngle)
        let localCorners: [SIMD2<Double>] = [
            SIMD2<Double>(0, 0),
            SIMD2<Double>(width, 0),
            SIMD2<Double>(width, height),
            SIMD2<Double>(0, height)
        ]
        let planeCorners = localCorners.map { lc in
            let rx = lc.x * cosR - lc.y * sinR
            let ry = lc.x * sinR + lc.y * cosR
            return origin + SIMD2<Double>(rx, ry)
        }
        return planeCorners.map { plane.unprojectPoint($0) }
    }
}
