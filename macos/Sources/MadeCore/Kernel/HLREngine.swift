import Foundation
import simd
import OCCTSwift

/// B-rep exact Hidden Line Removal (HLR) engine.
///
/// Computes exact visible, hidden, silhouette, and tangent edges for 2D drawing views
/// from single solids or multi-body assembly compounds under arbitrary view directions.
public enum HLREngine {

    /// Computes HLR edges for a single OCCT `Shape`.
    ///
    /// - Parameters:
    ///   - shape: The 3D B-rep shape to project.
    ///   - direction: The camera viewing direction vector.
    ///   - options: Configuration for edge inclusion, deflection, and 3D curve generation.
    /// - Returns: Categorized 2D drawing edges and view metadata.
    public static func computeHLR(
        shape: Shape,
        direction: SIMD3<Double>,
        options: HLROptions = .default
    ) -> HLRResult {
        guard simd_length(direction) >= 1e-9 else {
            return HLRResult(edges: [], viewDirection: direction)
        }
        let dir = simd_normalize(direction)

        guard shape.isValid && !shape.isEmpty else {
            return HLRResult(edges: [], viewDirection: dir)
        }

        let deflection = options.deflection > 0 ? options.deflection : 0.1

        var activeCategories: [HLREdgeCategory] = [.visibleSharp, .visibleSewn]
        if options.includeSilhouette {
            activeCategories.append(.visibleOutline)
        }
        if options.includeTangent {
            activeCategories.append(.visibleSmooth)
        }
        if options.includeHidden {
            activeCategories.append(contentsOf: [.hiddenSharp, .hiddenSewn])
            if options.includeSilhouette {
                activeCategories.append(.hiddenOutline)
            }
            if options.includeTangent {
                activeCategories.append(.hiddenSmooth)
            }
        }

        var collectedEdges: [HLREdge] = []

        for category in activeCategories {
            guard let categoryShape = shape.hlrEdges(direction: dir, category: category.occtCategory) else {
                continue
            }
            let polylines = categoryShape.allEdgePolylines(deflection: deflection)
            guard !polylines.isEmpty else { continue }

            var polylines3D: [[SIMD3<Double>]] = []
            if options.compute3D {
                if let shape3D = shape.hlrCompoundOfEdges(
                    direction: dir,
                    edgeType: category.occtEdgeType,
                    visible: category.isVisible,
                    in3d: true
                ) {
                    polylines3D = shape3D.allEdgePolylines(deflection: deflection)
                }
            }

            for (index, polyline) in polylines.enumerated() {
                guard polyline.count >= 2 else { continue }
                let points2D = polyline.map { SIMD2<Double>($0.x, $0.y) }
                let points3D = (options.compute3D && index < polylines3D.count && polylines3D[index].count >= 2)
                    ? polylines3D[index]
                    : []

                let edge = HLREdge(
                    category: category,
                    points2D: points2D,
                    points3D: points3D
                )
                collectedEdges.append(edge)
            }
        }

        return HLRResult(edges: collectedEdges, viewDirection: dir)
    }

    /// Computes HLR edges for multiple scene objects, compounding transformed geometry to resolve inter-body occlusions.
    ///
    /// - Parameters:
    ///   - objects: Multi-body scene objects to project.
    ///   - cachedShapes: Optional pre-evaluated shapes indexed by solid identifier.
    ///   - direction: The camera viewing direction vector.
    ///   - options: Configuration for edge inclusion, deflection, and 3D curve generation.
    /// - Returns: Categorized 2D drawing edges with multi-body occlusions resolved.
    public static func computeHLR(
        objects: [SceneObject],
        cachedShapes: [SolidId: Shape] = [:],
        direction: SIMD3<Double>,
        options: HLROptions = .default
    ) -> HLRResult {
        guard !objects.isEmpty else {
            return HLRResult(edges: [], viewDirection: direction)
        }

        var transformedShapes: [Shape] = []
        for obj in objects {
            guard let baseShape = (try? OCCTEngine.buildShape(for: obj.def, cachedShape: cachedShapes[obj.id])) ?? cachedShapes[obj.id] else {
                continue
            }
            if let transformed = OCCTEngine.transformed(baseShape, by: obj.transform) {
                transformedShapes.append(transformed)
            } else {
                transformedShapes.append(baseShape)
            }
        }

        guard !transformedShapes.isEmpty else {
            return HLRResult(edges: [], viewDirection: direction)
        }

        let finalShape: Shape
        if transformedShapes.count == 1 {
            finalShape = transformedShapes[0]
        } else {
            guard let compound = Shape.compound(transformedShapes) else {
                return HLRResult(edges: [], viewDirection: direction)
            }
            finalShape = compound
        }

        return computeHLR(shape: finalShape, direction: direction, options: options)
    }
}

private extension HLREdgeCategory {
    var occtCategory: Shape.HLREdgeCategory {
        switch self {
        case .visibleSharp: return .visibleSharp
        case .visibleSmooth: return .visibleSmooth
        case .visibleSewn: return .visibleSewn
        case .visibleOutline: return .visibleOutline
        case .hiddenSharp: return .hiddenSharp
        case .hiddenSmooth: return .hiddenSmooth
        case .hiddenSewn: return .hiddenSewn
        case .hiddenOutline: return .hiddenOutline
        }
    }

    var occtEdgeType: Shape.HLREdgeType {
        switch self {
        case .visibleSharp, .hiddenSharp: return .sharp
        case .visibleSmooth, .hiddenSmooth: return .rg1Line
        case .visibleSewn, .hiddenSewn: return .rgNLine
        case .visibleOutline, .hiddenOutline: return .outLine
        }
    }
}
