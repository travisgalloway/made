import Foundation
import CoreGraphics
import CoreText
import simd

/// Extracts 2D polygonal contour loops from text entities using CoreText.
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
}
