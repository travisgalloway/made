import Foundation
import simd

extension SketchTextOutliner {

    private struct ClassifiedLoop {
        let points: [SIMD2<Float>]
        let area: Float
        let centroid: SIMD2<Float>
        let bbox: (minX: Float, minY: Float, maxX: Float, maxY: Float)
    }

    /// Extracts closed `SketchRegion`s from a text entity, classifying outer boundaries and interior holes.
    public static func extractRegions(for entity: SketchEntity) -> [SketchRegion] {
        let contours = extractContours(for: entity)
        guard !contours.isEmpty else { return [] }

        var loops: [ClassifiedLoop] = []

        for contour in contours {
            guard contour.count >= 3 else { continue }

            var twiceArea: Double = 0
            let n = contour.count
            for i in 0..<n {
                let a = contour[i]
                let b = contour[(i + 1) % n]
                twiceArea += a.x * b.y - b.x * a.y
            }
            let signedArea = twiceArea / 2.0
            guard abs(signedArea) > 1e-5 else { continue }

            let oriented: [SIMD2<Float>]
            if signedArea > 0 {
                oriented = contour.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
            } else {
                oriented = contour.reversed().map { SIMD2<Float>(Float($0.x), Float($0.y)) }
            }

            let area = Float(abs(signedArea))

            // Compute centroid
            var cx: Double = 0
            var cy: Double = 0
            for i in 0..<n {
                let a = oriented[i]
                let b = oriented[(i + 1) % n]
                let factor = Double(a.x) * Double(b.y) - Double(b.x) * Double(a.y)
                cx += Double(a.x + b.x) * factor
                cy += Double(a.y + b.y) * factor
            }
            let denom = 6.0 * Double(area)
            let centroid: SIMD2<Float>
            if abs(denom) > 1e-6 {
                centroid = SIMD2<Float>(Float(cx / denom), Float(cy / denom))
            } else {
                centroid = oriented.reduce(SIMD2<Float>.zero, +) / Float(max(1, oriented.count))
            }

            var minX = Float.greatestFiniteMagnitude
            var minY = Float.greatestFiniteMagnitude
            var maxX = -Float.greatestFiniteMagnitude
            var maxY = -Float.greatestFiniteMagnitude
            for p in oriented {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
            let bbox = (minX: minX, minY: minY, maxX: maxX, maxY: maxY)

            loops.append(ClassifiedLoop(points: oriented, area: area, centroid: centroid, bbox: bbox))
        }

        guard !loops.isEmpty else { return [] }

        let loopCount = loops.count
        var contains = Array(repeating: Array(repeating: false, count: loopCount), count: loopCount)

        for i in 0..<loopCount {
            for j in 0..<loopCount {
                if i == j { continue }
                let outer = loops[i]
                let inner = loops[j]

                // Fast AABB check
                if inner.bbox.minX < outer.bbox.minX - 1e-3 ||
                   inner.bbox.maxX > outer.bbox.maxX + 1e-3 ||
                   inner.bbox.minY < outer.bbox.minY - 1e-3 ||
                   inner.bbox.maxY > outer.bbox.maxY + 1e-3 {
                    continue
                }

                var insideVotes = 0
                if SketchRegion.pointInPolygon(point: inner.centroid, polygon: outer.points) {
                    insideVotes += 2
                }
                let sampleCount = min(8, inner.points.count)
                let step = max(1, inner.points.count / sampleCount)
                for k in stride(from: 0, to: inner.points.count, by: step) {
                    if SketchRegion.pointInPolygon(point: inner.points[k], polygon: outer.points) {
                        insideVotes += 1
                    }
                }
                if insideVotes >= 3 {
                    contains[i][j] = true
                }
            }
        }

        // Determine ancestor nesting depth for each loop
        var ancestors: [Int: [Int]] = [:]
        for j in 0..<loopCount {
            var anc: [Int] = []
            for i in 0..<loopCount {
                if contains[i][j] {
                    anc.append(i)
                }
            }
            ancestors[j] = anc
        }

        // Outer boundaries: even ancestor depth (0, 2, ...)
        // Holes: odd ancestor depth (1, 3, ...)
        var outerIndices: [Int] = []
        var directHoles: [Int: [Int]] = [:] // outerIndex -> [holeIndices]

        for i in 0..<loopCount {
            let depth = ancestors[i]?.count ?? 0
            if depth % 2 == 0 {
                outerIndices.append(i)
                directHoles[i] = []
            }
        }

        for i in 0..<loopCount {
            let depth = ancestors[i]?.count ?? 0
            if depth % 2 == 1 {
                // Find immediate parent outer loop: the ancestor with smallest area
                if let ancList = ancestors[i], !ancList.isEmpty {
                    let directParent = ancList.min { loops[$0].area < loops[$1].area }
                    if let directParent {
                        directHoles[directParent, default: []].append(i)
                    }
                }
            }
        }

        var regions: [SketchRegion] = []
        for outerIdx in outerIndices {
            let outerLoop = loops[outerIdx]
            let holeIndices = directHoles[outerIdx] ?? []
            let holeLoops = holeIndices.map { loops[$0] }

            let totalHoleArea = holeLoops.reduce(Float(0)) { $0 + $1.area }
            let netArea = max(Float(1e-5), outerLoop.area - totalHoleArea)

            var weightedCentroid = outerLoop.centroid * outerLoop.area
            for h in holeLoops {
                weightedCentroid -= h.centroid * h.area
            }
            let netCentroid = netArea > Float(1e-5) ? (weightedCentroid / netArea) : outerLoop.centroid

            let regionId = UUID()
            let region = SketchRegion(
                id: regionId,
                outerLoop: outerLoop.points,
                innerLoops: holeLoops.map { $0.points },
                area: netArea,
                centroid: netCentroid
            )
            regions.append(region)
        }

        // Sort descending by net area, then by centroid
        regions.sort {
            if abs($0.area - $1.area) > 1e-3 {
                return $0.area > $1.area
            }
            if abs($0.centroid.x - $1.centroid.x) > 1e-3 {
                return $0.centroid.x < $1.centroid.x
            }
            return $0.centroid.y < $1.centroid.y
        }

        return regions
    }
}
