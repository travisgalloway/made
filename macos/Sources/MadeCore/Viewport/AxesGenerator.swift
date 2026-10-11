import Foundation
import simd
import Metal
import CoreGraphics
import CoreText

public struct AxisLine: Sendable, Equatable {
    public let name: String
    public let start: SIMD3<Float>
    public let end: SIMD3<Float>
    public let color: SIMD4<Float>
    public let labelPosition: SIMD3<Float>
    
    public init(
        name: String,
        start: SIMD3<Float>,
        end: SIMD3<Float>,
        color: SIMD4<Float>,
        labelPosition: SIMD3<Float>
    ) {
        self.name = name
        self.start = start
        self.end = end
        self.color = color
        self.labelPosition = labelPosition
    }
}

public struct AxesGeometry: Sendable, Equatable {
    public let length: Float
    public let labelSize: Float
    public let axes: [AxisLine]
    public let linePositions: [Float] // 3 floats per vertex (x, y, z)
    public let lineColors: [Float]    // 4 floats per vertex (r, g, b, a)
    public let labelCenters: [Float]   // 3 floats per vertex (x, y, z)
    public let labelOffsets: [Float]   // 2 floats per vertex (u_offset, v_offset)
    public let labelTexCoords: [Float] // 2 floats per vertex (u, v)
    public let labelColors: [Float]    // 4 floats per vertex (r, g, b, a)
    
    public var lineVertexCount: Int { linePositions.count / 3 }
    public var labelVertexCount: Int { labelCenters.count / 3 }
    
    public init(
        length: Float,
        labelSize: Float,
        axes: [AxisLine],
        linePositions: [Float],
        lineColors: [Float],
        labelCenters: [Float],
        labelOffsets: [Float],
        labelTexCoords: [Float],
        labelColors: [Float]
    ) {
        self.length = length
        self.labelSize = labelSize
        self.axes = axes
        self.linePositions = linePositions
        self.lineColors = lineColors
        self.labelCenters = labelCenters
        self.labelOffsets = labelOffsets
        self.labelTexCoords = labelTexCoords
        self.labelColors = labelColors
    }
}

public enum AxesGenerator {
    public static let defaultLength: Float = 50.0
    public static let defaultLabelSize: Float = 10.0
    
    /// Red for +X
    public static let defaultXColor = SIMD4<Float>(1.0, 0.21, 0.33, 1.0)
    /// Green for +Y
    public static let defaultYColor = SIMD4<Float>(0.22, 1.0, 0.08, 1.0)
    /// Blue for +Z (matches Orientation.worldUp)
    public static let defaultZColor = SIMD4<Float>(0.17, 0.56, 1.0, 1.0)
    
    /// Generates axes indicator geometry centered at (0,0,0) with three distinct lines and billboard labels.
    public static func generateAxes(
        length: Float = defaultLength,
        labelSize: Float = defaultLabelSize,
        xColor: SIMD4<Float> = defaultXColor,
        yColor: SIMD4<Float> = defaultYColor,
        zColor: SIMD4<Float> = defaultZColor
    ) -> AxesGeometry {
        guard length > 0, labelSize > 0 else {
            return AxesGeometry(
                length: length,
                labelSize: labelSize,
                axes: [],
                linePositions: [],
                lineColors: [],
                labelCenters: [],
                labelOffsets: [],
                labelTexCoords: [],
                labelColors: []
            )
        }
        
        let labelOffsetDistance = length + labelSize * 0.6
        
        let axisX = AxisLine(
            name: "X",
            start: SIMD3<Float>(0, 0, 0),
            end: SIMD3<Float>(length, 0, 0),
            color: xColor,
            labelPosition: SIMD3<Float>(labelOffsetDistance, 0, 0)
        )
        let axisY = AxisLine(
            name: "Y",
            start: SIMD3<Float>(0, 0, 0),
            end: SIMD3<Float>(0, length, 0),
            color: yColor,
            labelPosition: SIMD3<Float>(0, labelOffsetDistance, 0)
        )
        let axisZ = AxisLine(
            name: "Z",
            start: SIMD3<Float>(0, 0, 0),
            end: SIMD3<Float>(0, 0, length),
            color: zColor,
            labelPosition: SIMD3<Float>(0, 0, labelOffsetDistance)
        )
        
        let axes = [axisX, axisY, axisZ]
        
        var linePositions: [Float] = []
        var lineColors: [Float] = []
        
        for axis in axes {
            linePositions.append(contentsOf: [axis.start.x, axis.start.y, axis.start.z])
            linePositions.append(contentsOf: [axis.end.x, axis.end.y, axis.end.z])
            lineColors.append(contentsOf: [axis.color.x, axis.color.y, axis.color.z, axis.color.w])
            lineColors.append(contentsOf: [axis.color.x, axis.color.y, axis.color.z, axis.color.w])
        }
        
        var labelCenters: [Float] = []
        var labelOffsets: [Float] = []
        var labelTexCoords: [Float] = []
        var labelColors: [Float] = []
        
        // Quad corner offsets: local 2D square in [-0.5, 0.5]
        let pTL = SIMD2<Float>(-0.5, 0.5)
        let pBL = SIMD2<Float>(-0.5, -0.5)
        let pBR = SIMD2<Float>(0.5, -0.5)
        let pTR = SIMD2<Float>(0.5, 0.5)
        
        for (i, axis) in axes.enumerated() {
            let uMin = Float(i) / 3.0
            let uMax = Float(i + 1) / 3.0
            let vMin: Float = 0.0
            let vMax: Float = 1.0
            
            let uvTL = SIMD2<Float>(uMin, vMin)
            let uvBL = SIMD2<Float>(uMin, vMax)
            let uvBR = SIMD2<Float>(uMax, vMax)
            let uvTR = SIMD2<Float>(uMax, vMin)
            
            let center = axis.labelPosition
            let color = axis.color
            
            func addVertex(offset: SIMD2<Float>, uv: SIMD2<Float>) {
                labelCenters.append(contentsOf: [center.x, center.y, center.z])
                labelOffsets.append(contentsOf: [offset.x, offset.y])
                labelTexCoords.append(contentsOf: [uv.x, uv.y])
                labelColors.append(contentsOf: [color.x, color.y, color.z, color.w])
            }
            
            // Triangle 1: TL, BL, BR
            addVertex(offset: pTL, uv: uvTL)
            addVertex(offset: pBL, uv: uvBL)
            addVertex(offset: pBR, uv: uvBR)
            
            // Triangle 2: TL, BR, TR
            addVertex(offset: pTL, uv: uvTL)
            addVertex(offset: pBR, uv: uvBR)
            addVertex(offset: pTR, uv: uvTR)
        }
        
        return AxesGeometry(
            length: length,
            labelSize: labelSize,
            axes: axes,
            linePositions: linePositions,
            lineColors: lineColors,
            labelCenters: labelCenters,
            labelOffsets: labelOffsets,
            labelTexCoords: labelTexCoords,
            labelColors: labelColors
        )
    }
    
    /// Creates an offscreen texture atlas containing bold "X", "Y", "Z" label glyphs.
    public static func createAxesLabelAtlas(device: MTLDevice) -> MTLTexture? {
        let tileWidth = 128
        let tileHeight = 128
        let totalWidth = tileWidth * 3
        let totalHeight = tileHeight
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: totalWidth,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: totalWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        context.clear(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
        
        let labels = ["X", "Y", "Z"]
        for (i, label) in labels.enumerated() {
            let xOffset = CGFloat(i * tileWidth)
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 80.0, nil)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: CGColor(gray: 1.0, alpha: 1.0)
            ]
            let attrString = CFAttributedStringCreate(kCFAllocatorDefault, label as CFString, attributes as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attrString)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            
            let textX = xOffset + (CGFloat(tileWidth) - bounds.width) / 2.0 - bounds.origin.x
            let textY = (CGFloat(tileHeight) - bounds.height) / 2.0 - bounds.origin.y
            
            context.textPosition = CGPoint(x: textX, y: textY)
            CTLineDraw(line, context)
        }
        
        guard let data = context.data else { return nil }
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: totalWidth,
            height: totalHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        
        texture.replace(
            region: MTLRegionMake2D(0, 0, totalWidth, totalHeight),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: totalWidth * 4
        )
        return texture
    }
}
