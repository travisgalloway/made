import Foundation
import simd

/// Individual entity within a 2D sketch (line, arc, circle, constraint).
public struct SketchEntity: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: String
    public var data: [String: Double]
    public var isConstruction: Bool
    public var reference: Reference?
    public var text: String?
    public var fontName: String?

    public var isProjected: Bool {
        reference != nil
    }

    public init(
        id: UUID = UUID(),
        kind: String,
        data: [String: Double] = [:],
        isConstruction: Bool = false,
        reference: Reference? = nil,
        text: String? = nil,
        fontName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.data = data
        self.isConstruction = isConstruction
        self.reference = reference
        self.text = text
        self.fontName = fontName
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, data, isConstruction, reference, text, fontName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.data = try container.decode([String: Double].self, forKey: .data)
        self.isConstruction = try container.decodeIfPresent(Bool.self, forKey: .isConstruction) ?? false
        self.reference = try container.decodeIfPresent(Reference.self, forKey: .reference)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.fontName = try container.decodeIfPresent(String.self, forKey: .fontName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(data, forKey: .data)
        if isConstruction {
            try container.encode(isConstruction, forKey: .isConstruction)
        }
        if let reference {
            try container.encode(reference, forKey: .reference)
        }
        if let text {
            try container.encode(text, forKey: .text)
        }
        if let fontName {
            try container.encode(fontName, forKey: .fontName)
        }
    }

    public static func line(
        id: UUID = UUID(),
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        isConstruction: Bool = false,
        reference: Reference? = nil
    ) -> SketchEntity {
        SketchEntity(
            id: id,
            kind: "line",
            data: [
                "startX": start.x,
                "startY": start.y,
                "endX": end.x,
                "endY": end.y
            ],
            isConstruction: isConstruction,
            reference: reference
        )
    }

    public static func arc(
        id: UUID = UUID(),
        start: SIMD2<Double>,
        end: SIMD2<Double>,
        center: SIMD2<Double>,
        clockwise: Bool = false,
        isConstruction: Bool = false,
        reference: Reference? = nil
    ) -> SketchEntity {
        SketchEntity(
            id: id,
            kind: "arc",
            data: [
                "startX": start.x,
                "startY": start.y,
                "endX": end.x,
                "endY": end.y,
                "centerX": center.x,
                "centerY": center.y,
                "clockwise": clockwise ? 1.0 : 0.0
            ],
            isConstruction: isConstruction,
            reference: reference
        )
    }

    public static func circle(
        id: UUID = UUID(),
        center: SIMD2<Double>,
        radius: Double,
        isConstruction: Bool = false,
        reference: Reference? = nil
    ) -> SketchEntity {
        SketchEntity(
            id: id,
            kind: "circle",
            data: [
                "centerX": center.x,
                "centerY": center.y,
                "radius": radius
            ],
            isConstruction: isConstruction,
            reference: reference
        )
    }

    public static func point(
        id: UUID = UUID(),
        position: SIMD2<Double>,
        isConstruction: Bool = false,
        reference: Reference? = nil
    ) -> SketchEntity {
        SketchEntity(
            id: id,
            kind: "point",
            data: [
                "x": position.x,
                "y": position.y
            ],
            isConstruction: isConstruction,
            reference: reference
        )
    }

    public static func text(
        id: UUID = UUID(),
        text: String,
        origin: SIMD2<Double> = .zero,
        fontSize: Double = 12.0,
        fontName: String = "Helvetica",
        isConstruction: Bool = false
    ) -> SketchEntity {
        SketchEntity(
            id: id,
            kind: "text",
            data: [
                "originX": origin.x,
                "originY": origin.y,
                "fontSize": fontSize
            ],
            isConstruction: isConstruction,
            reference: nil,
            text: text,
            fontName: fontName
        )
    }

    public var pointPosition: SIMD2<Double>? {
        get {
            guard let x = data["x"], let y = data["y"] else { return nil }
            return SIMD2<Double>(x, y)
        }
        set {
            if let newValue {
                data["x"] = newValue.x
                data["y"] = newValue.y
            } else {
                data.removeValue(forKey: "x")
                data.removeValue(forKey: "y")
            }
        }
    }

    public var startPoint: SIMD2<Double>? {
        get {
            guard let sx = data["startX"], let sy = data["startY"] else { return nil }
            return SIMD2<Double>(sx, sy)
        }
        set {
            if let newValue {
                data["startX"] = newValue.x
                data["startY"] = newValue.y
            } else {
                data.removeValue(forKey: "startX")
                data.removeValue(forKey: "startY")
            }
        }
    }

    public var endPoint: SIMD2<Double>? {
        get {
            guard let ex = data["endX"], let ey = data["endY"] else { return nil }
            return SIMD2<Double>(ex, ey)
        }
        set {
            if let newValue {
                data["endX"] = newValue.x
                data["endY"] = newValue.y
            } else {
                data.removeValue(forKey: "endX")
                data.removeValue(forKey: "endY")
            }
        }
    }

    public var centerPoint: SIMD2<Double>? {
        get {
            guard let cx = data["centerX"], let cy = data["centerY"] else { return nil }
            return SIMD2<Double>(cx, cy)
        }
        set {
            if let newValue {
                data["centerX"] = newValue.x
                data["centerY"] = newValue.y
            } else {
                data.removeValue(forKey: "centerX")
                data.removeValue(forKey: "centerY")
            }
        }
    }

    public var radius: Double? {
        get {
            if let r = data["radius"] { return r }
            if let cp = centerPoint, let sp = startPoint {
                return hypot(sp.x - cp.x, sp.y - cp.y)
            }
            return nil
        }
        set {
            if let newValue {
                data["radius"] = newValue
            } else {
                data.removeValue(forKey: "radius")
            }
        }
    }

    public var isClockwise: Bool {
        get {
            data["clockwise"] == 1.0
        }
        set {
            data["clockwise"] = newValue ? 1.0 : 0.0
        }
    }

    public var textString: String? {
        get { text }
        set { text = newValue }
    }

    public var origin: SIMD2<Double>? {
        get {
            guard let ox = data["originX"], let oy = data["originY"] else { return nil }
            return SIMD2<Double>(ox, oy)
        }
        set {
            if let newValue {
                data["originX"] = newValue.x
                data["originY"] = newValue.y
            } else {
                data.removeValue(forKey: "originX")
                data.removeValue(forKey: "originY")
            }
        }
    }

    public var fontSize: Double? {
        get {
            data["fontSize"]
        }
        set {
            if let newValue {
                data["fontSize"] = newValue
            } else {
                data.removeValue(forKey: "fontSize")
            }
        }
    }

    public var length: Double? {
        guard kind == "line", let start = startPoint, let end = endPoint else { return nil }
        return hypot(end.x - start.x, end.y - start.y)
    }

    public func updatingLength(_ newLength: Double, anchor: SIMD2<Double>? = nil) -> SketchEntity {
        guard kind == "line", let start = startPoint, let end = endPoint, newLength > 0, newLength.isFinite else { return self }
        let curLen = hypot(end.x - start.x, end.y - start.y)
        guard curLen > 1e-9 else { return self }
        let fixedStart = anchor ?? start
        let dir = SIMD2<Double>((end.x - start.x) / curLen, (end.y - start.y) / curLen)
        let newEnd = SIMD2<Double>(fixedStart.x + dir.x * newLength, fixedStart.y + dir.y * newLength)
        return updatingEndpoints(start: fixedStart, end: newEnd)
    }

    public func updatingEndpoints(start: SIMD2<Double>? = nil, end: SIMD2<Double>? = nil) -> SketchEntity {
        var copy = self
        if let start {
            copy.data["startX"] = start.x
            copy.data["startY"] = start.y
        }
        if let end {
            copy.data["endX"] = end.x
            copy.data["endY"] = end.y
        }
        return copy
    }

    public func withEndpoints(start: SIMD2<Double>? = nil, end: SIMD2<Double>? = nil) -> SketchEntity {
        updatingEndpoints(start: start, end: end)
    }

    public func updatingConstruction(_ isConstruction: Bool) -> SketchEntity {
        var copy = self
        copy.isConstruction = isConstruction
        return copy
    }
}
