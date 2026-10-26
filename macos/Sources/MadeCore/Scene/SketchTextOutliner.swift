import Foundation
import CoreGraphics
import CoreText
import simd

/// Extracts 2D polygonal contour loops and closed `SketchRegion`s from text entities using CoreText.
public enum SketchTextOutliner {

    /// Extracts sampled 2D polygonal contour loops (in millimeters/units) from a text entity.
    public static func extractContours(for entity: SketchEntity) -> [[SIMD2<Double>]] {
        guard entity.kind == "text", let text = entity.text, !text.isEmpty else {
            return []
        }
        let fontName = entity.fontName ?? "Helvetica"
        let fontSize = max(1e-5, entity.fontSize ?? 12.0)
        let origin = entity.origin ?? .zero

        return extractContours(text: text, fontName: fontName, fontSize: fontSize, origin: origin)
    }

    /// Extracts sampled 2D polygonal contour loops for raw text parameters.
    public static func extractContours(
        text: String,
        fontName: String = "Helvetica",
        fontSize: Double = 12.0,
        origin: SIMD2<Double> = .zero
    ) -> [[SIMD2<Double>]] {
        let trimmedFont = fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cgFontName = (trimmedFont.isEmpty ? "Helvetica" : trimmedFont) as CFString
        let font = CTFontCreateWithName(cgFontName, CGFloat(fontSize), nil)

        let lines = text.components(separatedBy: .newlines)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let totalLineHeight = Double(ascent + descent + leading)
        let lineHeight = totalLineHeight > 1e-4 ? totalLineHeight : fontSize * 1.2

        var allContours: [[SIMD2<Double>]] = []

        for (lineIdx, lineText) in lines.enumerated() {
            guard !lineText.isEmpty else { continue }
            let lineOriginY = origin.y - Double(lineIdx) * lineHeight

            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font
            ]
            let attrString = NSAttributedString(string: lineText, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attrString as CFAttributedString)

            let runs = (CTLineGetGlyphRuns(ctLine) as? [CTRun]) ?? []
            for run in runs {
                let runFont = font
                let glyphCount = CTRunGetGlyphCount(run)
                guard glyphCount > 0 else { continue }

                var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                CTRunGetGlyphs(run, CFRangeMake(0, glyphCount), &glyphs)
                CTRunGetPositions(run, CFRangeMake(0, glyphCount), &positions)

                for i in 0..<glyphCount {
                    let glyph = glyphs[i]
                    let pos = positions[i]
                    var transform = CGAffineTransform(
                        translationX: CGFloat(origin.x) + pos.x,
                        y: CGFloat(lineOriginY) + pos.y
                    )

                    guard let path = CTFontCreatePathForGlyph(runFont, glyph, &transform) else {
                        continue
                    }

                    let glyphContours = decomposePath(path)
                    allContours.append(contentsOf: glyphContours)
                }
            }
        }

        return allContours
    }

    /// Decomposes a CGPath into sampled polygonal vertex loops.
    private static func decomposePath(_ path: CGPath) -> [[SIMD2<Double>]] {
        var contours: [[SIMD2<Double>]] = []
        var currentLoop: [SIMD2<Double>] = []

        path.applyWithBlock { elementPtr in
            let element = elementPtr.pointee
            switch element.type {
            case .moveToPoint:
                if currentLoop.count >= 3 {
                    if let first = currentLoop.first, let last = currentLoop.last,
                       hypot(first.x - last.x, first.y - last.y) < 1e-5 {
                        currentLoop.removeLast()
                    }
                    if currentLoop.count >= 3 {
                        contours.append(currentLoop)
                    }
                }
                currentLoop = []
                let pt = element.points[0]
                currentLoop.append(SIMD2<Double>(Double(pt.x), Double(pt.y)))

            case .addLineToPoint:
                let pt = element.points[0]
                let p = SIMD2<Double>(Double(pt.x), Double(pt.y))
                if let last = currentLoop.last, hypot(p.x - last.x, p.y - last.y) < 1e-5 {
                    // skip coincident duplicate
                } else {
                    currentLoop.append(p)
                }

            case .addQuadCurveToPoint:
                guard let p0 = currentLoop.last else { break }
                let p1 = SIMD2<Double>(Double(element.points[0].x), Double(element.points[0].y))
                let p2 = SIMD2<Double>(Double(element.points[1].x), Double(element.points[1].y))
                let steps = 8
                for s in 1...steps {
                    let t = Double(s) / Double(steps)
                    let oneMinusT = 1.0 - t
                    let pt = oneMinusT * oneMinusT * p0 + 2.0 * oneMinusT * t * p1 + t * t * p2
                    if let last = currentLoop.last, hypot(pt.x - last.x, pt.y - last.y) < 1e-5 {
                        continue
                    }
                    currentLoop.append(pt)
                }

            case .addCurveToPoint:
                guard let p0 = currentLoop.last else { break }
                let p1 = SIMD2<Double>(Double(element.points[0].x), Double(element.points[0].y))
                let p2 = SIMD2<Double>(Double(element.points[1].x), Double(element.points[1].y))
                let p3 = SIMD2<Double>(Double(element.points[2].x), Double(element.points[2].y))
                let steps = 12
                for s in 1...steps {
                    let t = Double(s) / Double(steps)
                    let oneMinusT = 1.0 - t
                    let pt = oneMinusT * oneMinusT * oneMinusT * p0 +
                             3.0 * oneMinusT * oneMinusT * t * p1 +
                             3.0 * oneMinusT * t * t * p2 +
                             t * t * t * p3
                    if let last = currentLoop.last, hypot(pt.x - last.x, pt.y - last.y) < 1e-5 {
                        continue
                    }
                    currentLoop.append(pt)
                }

            case .closeSubpath:
                if currentLoop.count >= 3 {
                    if let first = currentLoop.first, let last = currentLoop.last,
                       hypot(first.x - last.x, first.y - last.y) < 1e-5 {
                        currentLoop.removeLast()
                    }
                    if currentLoop.count >= 3 {
                        contours.append(currentLoop)
                    }
                }
                currentLoop = []

            @unknown default:
                break
            }
        }

        if currentLoop.count >= 3 {
            if let first = currentLoop.first, let last = currentLoop.last,
               hypot(first.x - last.x, first.y - last.y) < 1e-5 {
                currentLoop.removeLast()
            }
            if currentLoop.count >= 3 {
                contours.append(currentLoop)
            }
        }

        return contours
    }

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
