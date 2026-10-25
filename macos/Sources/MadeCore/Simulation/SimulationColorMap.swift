import Foundation
import simd
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Available color palettes for CAE contour visualization (BL-RES-02, #193).
public enum SimulationColorMapKind: String, Sendable, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case turbo
    case rainbow
    case viridis
    case coolWarm
    case magma
    case grayscale

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .turbo:
            return "Turbo"
        case .rainbow:
            return "Rainbow (Jet)"
        case .viridis:
            return "Viridis"
        case .coolWarm:
            return "Cool to Warm"
        case .magma:
            return "Magma"
        case .grayscale:
            return "Grayscale"
        }
    }
}

/// Pure Swift color evaluation engine mapping normalized values to GPU colors and SwiftUI gradients (BL-RES-02, #193).
public enum SimulationColorMap: Sendable {

    /// Evaluates a normalized scalar parameter $t \in [0, 1]$ against the requested colormap,
    /// returning RGBA floating-point color components clamped to $[0, 1]$ with alpha 1.0.
    public static func evaluate(t: Double, map: SimulationColorMapKind) -> SIMD4<Float> {
        let x = max(0.0, min(1.0, t.isNaN ? 0.5 : t))

        switch map {
        case .turbo:
            return evaluateTurbo(x)
        case .rainbow:
            return evaluateRainbow(x)
        case .viridis:
            return evaluateViridis(x)
        case .coolWarm:
            return evaluateCoolWarm(x)
        case .magma:
            return evaluateMagma(x)
        case .grayscale:
            return evaluateGrayscale(x)
        }
    }

    #if canImport(SwiftUI)
    /// Converts a normalized scalar value $t \in [0, 1]$ into a SwiftUI Color.
    public static func color(t: Double, map: SimulationColorMapKind) -> Color {
        let rgba = evaluate(t: t, map: map)
        return Color(red: Double(rgba.x), green: Double(rgba.y), blue: Double(rgba.z), opacity: Double(rgba.w))
    }

    /// Generates evenly spaced SwiftUI gradient color stops across the palette for legend bars.
    public static func gradientColors(map: SimulationColorMapKind, sampleCount: Int = 32) -> [Color] {
        let count = max(2, sampleCount)
        return (0..<count).map { i in
            let t = Double(i) / Double(count - 1)
            return color(t: t, map: map)
        }
    }
    #endif

    // MARK: - Palette Evaluators

    /// Google Turbo colormap 7th-order polynomial approximation.
    private static func evaluateTurbo(_ x: Double) -> SIMD4<Float> {
        let kRedVec4 = SIMD4<Double>(0.13572138, 4.61539260, -42.66032258, 132.13108234)
        let kGreenVec4 = SIMD4<Double>(0.09140261, 2.19418839, 4.84296658, -14.18503333)
        let kBlueVec4 = SIMD4<Double>(0.10667330, 12.64194608, -60.58204836, 110.36276771)
        let kRedVec2 = SIMD2<Double>(-152.94239396, 59.28637943)
        let kGreenVec2 = SIMD2<Double>(4.27729857, 2.82956604)
        let kBlueVec2 = SIMD2<Double>(-89.90310912, 27.34824973)

        let x2 = x * x
        let x3 = x2 * x
        let x4 = x3 * x
        let x5 = x4 * x

        let v4 = SIMD4<Double>(1.0, x, x2, x3)
        let v2 = SIMD2<Double>(x4, x5)

        let r = dot4(v4, kRedVec4) + dot2(v2, kRedVec2)
        let g = dot4(v4, kGreenVec4) + dot2(v2, kGreenVec2)
        let b = dot4(v4, kBlueVec4) + dot2(v2, kBlueVec2)

        return SIMD4<Float>(
            Float(max(0.0, min(1.0, r))),
            Float(max(0.0, min(1.0, g))),
            Float(max(0.0, min(1.0, b))),
            1.0
        )
    }

    /// Piecewise linear Jet / Rainbow colormap: Blue -> Cyan -> Green -> Yellow -> Red.
    private static func evaluateRainbow(_ x: Double) -> SIMD4<Float> {
        if x <= 0.25 {
            let f = x / 0.25
            return SIMD4<Float>(0.0, Float(f), 1.0, 1.0)
        } else if x <= 0.50 {
            let f = (x - 0.25) / 0.25
            return SIMD4<Float>(0.0, 1.0, Float(1.0 - f), 1.0)
        } else if x <= 0.75 {
            let f = (x - 0.50) / 0.25
            return SIMD4<Float>(Float(f), 1.0, 0.0, 1.0)
        } else {
            let f = (x - 0.75) / 0.25
            return SIMD4<Float>(1.0, Float(1.0 - f), 0.0, 1.0)
        }
    }

    /// Standard Viridis colormap evaluated with 9 control stops.
    private static func evaluateViridis(_ x: Double) -> SIMD4<Float> {
        let stops: [(Double, SIMD3<Double>)] = [
            (0.000, SIMD3<Double>(0.267, 0.005, 0.329)),
            (0.125, SIMD3<Double>(0.282, 0.170, 0.463)),
            (0.250, SIMD3<Double>(0.216, 0.316, 0.545)),
            (0.375, SIMD3<Double>(0.165, 0.443, 0.557)),
            (0.500, SIMD3<Double>(0.128, 0.567, 0.551)),
            (0.625, SIMD3<Double>(0.180, 0.690, 0.488)),
            (0.750, SIMD3<Double>(0.439, 0.811, 0.278)),
            (0.875, SIMD3<Double>(0.753, 0.892, 0.157)),
            (1.000, SIMD3<Double>(0.993, 0.906, 0.144))
        ]
        return interpolateStops(x, stops: stops)
    }

    /// Diverging Cool-to-Warm colormap with neutral gray center.
    private static func evaluateCoolWarm(_ x: Double) -> SIMD4<Float> {
        let stops: [(Double, SIMD3<Double>)] = [
            (0.0, SIMD3<Double>(0.230, 0.299, 0.754)),
            (0.5, SIMD3<Double>(0.865, 0.865, 0.865)),
            (1.0, SIMD3<Double>(0.706, 0.016, 0.150))
        ]
        return interpolateStops(x, stops: stops)
    }

    /// Perceptually uniform Magma colormap evaluated with 5 control stops.
    private static func evaluateMagma(_ x: Double) -> SIMD4<Float> {
        let stops: [(Double, SIMD3<Double>)] = [
            (0.00, SIMD3<Double>(0.001, 0.000, 0.014)),
            (0.25, SIMD3<Double>(0.317, 0.071, 0.485)),
            (0.50, SIMD3<Double>(0.716, 0.215, 0.475)),
            (0.75, SIMD3<Double>(0.987, 0.578, 0.380)),
            (1.00, SIMD3<Double>(0.987, 0.991, 0.750))
        ]
        return interpolateStops(x, stops: stops)
    }

    /// Linear Grayscale luminance ramp from dark gray to off-white.
    private static func evaluateGrayscale(_ x: Double) -> SIMD4<Float> {
        let val = Float(0.1 + 0.85 * x)
        return SIMD4<Float>(val, val, val, 1.0)
    }

    // MARK: - Utilities

    private static func interpolateStops(_ x: Double, stops: [(Double, SIMD3<Double>)]) -> SIMD4<Float> {
        guard let first = stops.first else {
            return SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
        }
        if x <= first.0 {
            return SIMD4<Float>(Float(first.1.x), Float(first.1.y), Float(first.1.z), 1.0)
        }
        guard let last = stops.last else {
            return SIMD4<Float>(Float(first.1.x), Float(first.1.y), Float(first.1.z), 1.0)
        }
        if x >= last.0 {
            return SIMD4<Float>(Float(last.1.x), Float(last.1.y), Float(last.1.z), 1.0)
        }

        for i in 0..<(stops.count - 1) {
            let t0 = stops[i].0
            let t1 = stops[i + 1].0
            if x >= t0 && x <= t1 {
                let segmentRange = t1 - t0
                let fraction = segmentRange > 1e-12 ? (x - t0) / segmentRange : 0.0
                let c0 = stops[i].1
                let c1 = stops[i + 1].1
                let interpolated = c0 + (c1 - c0) * fraction
                return SIMD4<Float>(
                    Float(max(0.0, min(1.0, interpolated.x))),
                    Float(max(0.0, min(1.0, interpolated.y))),
                    Float(max(0.0, min(1.0, interpolated.z))),
                    1.0
                )
            }
        }

        return SIMD4<Float>(Float(last.1.x), Float(last.1.y), Float(last.1.z), 1.0)
    }

    private static func dot4(_ a: SIMD4<Double>, _ b: SIMD4<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
    }

    private static func dot2(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        a.x * b.x + a.y * b.y
    }
}
