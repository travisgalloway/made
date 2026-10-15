import Foundation
import CoreGraphics
import simd

/// Projects 3D scene bounds to 2D screen coordinates in SwiftUI canvas space (top-left origin).
public enum ScreenBoundsCalculator {
    /// Evaluates the 8 world-space corners of `SceneBounds`, projects each to 2D screen coordinates,
    /// and converts from Metal/AppKit Y coordinates (origin bottom-left) to SwiftUI canvas coordinates
    /// (origin top-left): `swiftUIMinY = viewportSize.height - maxMetalY`.
    /// Returns the tight 2D screen bounding rect containing all projected corners.
    /// Returns nil if `bounds` has no valid projected corners or viewport size is non-positive.
    public static func screenBoundingBox(
        for bounds: SceneBounds,
        viewProjectionMatrix: simd_float4x4,
        viewportSize: CGSize
    ) -> CGRect? {
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return nil }

        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(bounds.min.x, bounds.min.y, bounds.min.z),
            SIMD3<Float>(bounds.min.x, bounds.min.y, bounds.max.z),
            SIMD3<Float>(bounds.min.x, bounds.max.y, bounds.min.z),
            SIMD3<Float>(bounds.min.x, bounds.max.y, bounds.max.z),
            SIMD3<Float>(bounds.max.x, bounds.min.y, bounds.min.z),
            SIMD3<Float>(bounds.max.x, bounds.min.y, bounds.max.z),
            SIMD3<Float>(bounds.max.x, bounds.max.y, bounds.min.z),
            SIMD3<Float>(bounds.max.x, bounds.max.y, bounds.max.z)
        ]

        var minX: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var minMetalY: CGFloat = .infinity
        var maxMetalY: CGFloat = -.infinity
        var projectedCount = 0

        for corner in corners {
            if let pt = projectToScreen(point: corner, viewProjectionMatrix: viewProjectionMatrix, viewportSize: viewportSize) {
                let x = CGFloat(pt.x)
                let y = CGFloat(pt.y)
                minX = min(minX, x)
                maxX = max(maxX, x)
                minMetalY = min(minMetalY, y)
                maxMetalY = max(maxMetalY, y)
                projectedCount += 1
            }
        }

        guard projectedCount > 0 else { return nil }

        let swiftUIMinY = viewportSize.height - maxMetalY
        let width = max(0, maxX - minX)
        let height = max(0, maxMetalY - minMetalY)

        return CGRect(x: minX, y: swiftUIMinY, width: width, height: height)
    }
}

/// Geometry placement algorithm that computes non-covering floating HUD coordinates.
public enum CommandHUDPlacement {
    public static let defaultMargin: CGFloat = 16
    public static let defaultPadding: CGFloat = 16

    /// Computes non-covering floating HUD coordinates in SwiftUI canvas space.
    ///
    /// Tests candidate placements around `geometryScreenRect` in order:
    /// 1. Right: `x = geom.maxX + margin`, `y = clamp(geom.midY - hudH / 2)`
    /// 2. Left: `x = geom.minX - margin - hudW`, `y = clamp(geom.midY - hudH / 2)`
    /// 3. Below: `x = clamp(geom.midX - hudW / 2)`, `y = geom.maxY + margin`
    /// 4. Above: `x = clamp(geom.midX - hudW / 2)`, `y = geom.minY - margin - hudH`
    ///
    /// If none of the cardinal candidates fit without intersecting `geometryScreenRect`,
    /// evaluates the four viewport corners (Top-Right, Top-Left, Bottom-Right, Bottom-Left)
    /// and selects the corner that minimizes overlap with `geometryScreenRect`.
    ///
    /// If `geometryScreenRect` is nil or outside the viewport, returns the top-trailing corner:
    /// `(viewportSize.width - hudSize.width - padding, padding)`.
    public static func computePosition(
        geometryScreenRect: CGRect?,
        viewportSize: CGSize,
        hudSize: CGSize,
        margin: CGFloat = defaultMargin,
        padding: CGFloat = defaultPadding
    ) -> CGPoint {
        let viewportRect = CGRect(origin: .zero, size: viewportSize)
        let fallbackTopRight = CGPoint(
            x: max(padding, viewportSize.width - hudSize.width - padding),
            y: padding
        )

        guard let geom = geometryScreenRect,
              !geom.isNull,
              !geom.isEmpty,
              geom.intersects(viewportRect) else {
            return fallbackTopRight
        }

        let hudW = hudSize.width
        let hudH = hudSize.height
        let viewW = viewportSize.width
        let viewH = viewportSize.height

        func clampVal(_ val: CGFloat, minVal: CGFloat, maxVal: CGFloat) -> CGFloat {
            if maxVal < minVal { return minVal }
            return min(max(val, minVal), maxVal)
        }

        // 1. Right candidate
        let rightX = geom.maxX + margin
        let rightY = clampVal(geom.midY - hudH / 2.0, minVal: padding, maxVal: viewH - hudH - padding)
        let rightRect = CGRect(x: rightX, y: rightY, width: hudW, height: hudH)
        if rightX + hudW <= viewW - padding && rightX >= padding && !rightRect.intersects(geom) {
            return CGPoint(x: rightX, y: rightY)
        }

        // 2. Left candidate
        let leftX = geom.minX - margin - hudW
        let leftY = clampVal(geom.midY - hudH / 2.0, minVal: padding, maxVal: viewH - hudH - padding)
        let leftRect = CGRect(x: leftX, y: leftY, width: hudW, height: hudH)
        if leftX >= padding && leftX + hudW <= viewW - padding && !leftRect.intersects(geom) {
            return CGPoint(x: leftX, y: leftY)
        }

        // 3. Below candidate
        let belowX = clampVal(geom.midX - hudW / 2.0, minVal: padding, maxVal: viewW - hudW - padding)
        let belowY = geom.maxY + margin
        let belowRect = CGRect(x: belowX, y: belowY, width: hudW, height: hudH)
        if belowY + hudH <= viewH - padding && belowY >= padding && !belowRect.intersects(geom) {
            return CGPoint(x: belowX, y: belowY)
        }

        // 4. Above candidate
        let aboveX = clampVal(geom.midX - hudW / 2.0, minVal: padding, maxVal: viewW - hudW - padding)
        let aboveY = geom.minY - margin - hudH
        let aboveRect = CGRect(x: aboveX, y: aboveY, width: hudW, height: hudH)
        if aboveY >= padding && aboveY + hudH <= viewH - padding && !aboveRect.intersects(geom) {
            return CGPoint(x: aboveX, y: aboveY)
        }

        // Fallback: evaluate the 4 viewport corners (Top-Right, Top-Left, Bottom-Right, Bottom-Left)
        let cornerCandidates: [CGPoint] = [
            CGPoint(x: max(padding, viewW - hudW - padding), y: padding), // Top-Right
            CGPoint(x: padding, y: padding),                              // Top-Left
            CGPoint(x: max(padding, viewW - hudW - padding), y: max(padding, viewH - hudH - padding)), // Bottom-Right
            CGPoint(x: padding, y: max(padding, viewH - hudH - padding))  // Bottom-Left
        ]

        // First pass: find a corner with zero intersection
        for corner in cornerCandidates {
            let cornerRect = CGRect(origin: corner, size: hudSize)
            if !cornerRect.intersects(geom) {
                return corner
            }
        }

        // Second pass: pick corner with minimal intersection area
        var bestCorner = cornerCandidates[0]
        var minArea: CGFloat = .infinity

        for corner in cornerCandidates {
            let cornerRect = CGRect(origin: corner, size: hudSize)
            let isect = cornerRect.intersection(geom)
            let area: CGFloat = (isect.isNull || isect.isEmpty) ? 0 : (isect.width * isect.height)
            if area < minArea {
                minArea = area
                bestCorner = corner
            }
        }

        return bestCorner
    }
}
