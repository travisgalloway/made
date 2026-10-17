import Foundation
import simd

public struct GridLine: Sendable, Equatable {
    public let start: SIMD3<Float>
    public let end: SIMD3<Float>
    public let isMajor: Bool
    
    public init(start: SIMD3<Float>, end: SIMD3<Float>, isMajor: Bool = false) {
        self.start = start
        self.end = end
        self.isMajor = isMajor
    }
}

public struct GridGeometry: Sendable, Equatable {
    public let size: Float
    public let spacing: Float
    public let lines: [GridLine]
    public let positions: [Float] // 3 floats per vertex (x, y, z)
    public let colors: [Float]    // 4 floats per vertex (r, g, b, a)
    
    public var lineCount: Int { lines.count }
    public var vertexCount: Int { positions.count / 3 }
    
    public init(
        size: Float,
        spacing: Float,
        lines: [GridLine],
        positions: [Float],
        colors: [Float]
    ) {
        self.size = size
        self.spacing = spacing
        self.lines = lines
        self.positions = positions
        self.colors = colors
    }
}

public enum GridGenerator {
    public static let defaultSize: Float = 300.0
    public static let defaultSpacing: Float = defaultGridSpacing
    
    /// Minor grid line color (subtle gray against dark background)
    public static let defaultMinorColor = SIMD4<Float>(0.25, 0.28, 0.32, 1.0)
    /// Major / center line color (slightly highlighted)
    public static let defaultMajorColor = SIMD4<Float>(0.42, 0.45, 0.50, 1.0)
    
    /// Generates grid geometry on `plane` (defaulting to .xy ground plane Z = 0) with lines spaced by `spacing`.
    /// Lines are centered at the plane origin and aligned with its coordinate axes so snap points match grid lines.
    public static func generateGrid(
        plane: SketchPlane = .xy,
        size: Float = defaultSize,
        spacing: Float = defaultSpacing,
        minorColor: SIMD4<Float> = defaultMinorColor,
        majorColor: SIMD4<Float> = defaultMajorColor
    ) -> GridGeometry {
        guard size > 0, spacing > 0 else {
            return GridGeometry(size: size, spacing: spacing, lines: [], positions: [], colors: [])
        }
        
        let halfSize = size / 2.0
        let steps = Int(floor(halfSize / spacing))
        
        var lines: [GridLine] = []
        var positions: [Float] = []
        var colors: [Float] = []
        
        func appendLine(start: SIMD3<Float>, end: SIMD3<Float>, isMajor: Bool) {
            lines.append(GridLine(start: start, end: end, isMajor: isMajor))
            positions.append(contentsOf: [start.x, start.y, start.z])
            positions.append(contentsOf: [end.x, end.y, end.z])
            let color = isMajor ? majorColor : minorColor
            colors.append(contentsOf: [color.x, color.y, color.z, color.w])
            colors.append(contentsOf: [color.x, color.y, color.z, color.w])
        }
        
        // Lines parallel to V (varying U, from -halfSize to +halfSize along V)
        for i in -steps...steps {
            let u = Double(Float(i) * spacing)
            let isMajor = (i == 0)
            let start = plane.unprojectPoint(SIMD2<Double>(u, Double(-halfSize)))
            let end = plane.unprojectPoint(SIMD2<Double>(u, Double(halfSize)))
            appendLine(start: start, end: end, isMajor: isMajor)
        }
        
        // Lines parallel to U (varying V, from -halfSize to +halfSize along U)
        for j in -steps...steps {
            let v = Double(Float(j) * spacing)
            let isMajor = (j == 0)
            let start = plane.unprojectPoint(SIMD2<Double>(Double(-halfSize), v))
            let end = plane.unprojectPoint(SIMD2<Double>(Double(halfSize), v))
            appendLine(start: start, end: end, isMajor: isMajor)
        }
        
        return GridGeometry(
            size: size,
            spacing: spacing,
            lines: lines,
            positions: positions,
            colors: colors
        )
    }
}
