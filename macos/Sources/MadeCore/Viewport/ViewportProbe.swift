import Foundation
import simd

public struct ViewportProbeHit: Equatable, Sendable {
    public let id: SolidId
    public let normalizedOffset: SIMD2<Double>

    public var x: Double { normalizedOffset.x }
    public var y: Double { normalizedOffset.y }

    public init(id: SolidId, normalizedOffset: SIMD2<Double>) {
        self.id = id
        self.normalizedOffset = normalizedOffset
    }
}

public struct ViewportProbeSnapshot: Equatable, Sendable {
    public var state: String
    public var renders: Int
    public var draws: Int
    public var reason: String
    public var selection: String
    public var hits: [ViewportProbeHit]

    public init(
        state: String = "ready",
        renders: Int = 0,
        draws: Int = 0,
        reason: String = "",
        selection: String = "",
        hits: [ViewportProbeHit] = []
    ) {
        self.state = state
        self.renders = renders
        self.draws = draws
        self.reason = reason
        self.selection = selection
        self.hits = hits
    }

    public func formatted() -> String {
        let sortedHits = hits.sorted { $0.id.rawValue < $1.id.rawValue }
        let hitsString = sortedHits.map { hit in
            let x = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), hit.normalizedOffset.x)
            let y = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), hit.normalizedOffset.y)
            return "\(hit.id.rawValue):\(x),\(y)"
        }.joined(separator: "|")
        return "state=\(state);renders=\(renders);draws=\(draws);reason=\(reason);selection=\(selection);hits=\(hitsString)"
    }

    public static func parse(_ string: String) -> ViewportProbeSnapshot {
        var state = ""
        var renders = 0
        var draws = 0
        var reason = ""
        var selection = ""
        var hits: [ViewportProbeHit] = []

        let components = string.components(separatedBy: ";")
        for component in components {
            guard let eqIndex = component.firstIndex(of: "=") else { continue }
            let key = String(component[..<eqIndex])
            let value = String(component[component.index(after: eqIndex)...])
            switch key {
            case "state":
                state = value
            case "renders":
                renders = Int(value) ?? 0
            case "draws":
                draws = Int(value) ?? 0
            case "reason":
                reason = value
            case "selection":
                selection = value
            case "hits":
                if !value.isEmpty {
                    let hitItems = value.components(separatedBy: "|")
                    for item in hitItems {
                        guard let colonIndex = item.firstIndex(of: ":") else { continue }
                        let idStr = String(item[..<colonIndex])
                        let coordsStr = String(item[item.index(after: colonIndex)...])
                        let coords = coordsStr.components(separatedBy: ",")
                        if coords.count == 2,
                           let x = Double(coords[0]),
                           let y = Double(coords[1]) {
                            hits.append(ViewportProbeHit(id: SolidId(idStr), normalizedOffset: SIMD2<Double>(x, y)))
                        }
                    }
                }
            default:
                break
            }
        }

        return ViewportProbeSnapshot(
            state: state,
            renders: renders,
            draws: draws,
            reason: reason,
            selection: selection,
            hits: hits
        )
    }
}

public enum ViewportProbe {
    public static func projectHits(
        candidateMeshes: [CandidateMesh],
        viewMatrix: simd_float4x4,
        projectionMatrix: simd_float4x4
    ) -> [ViewportProbeHit] {
        var hits: [ViewportProbeHit] = []
        for mesh in candidateMeshes {
            guard !mesh.positions.isEmpty else { continue }
            let aabb = AABB(points: mesh.positions)
            let localCenter = aabb.center
            let worldCenter = mesh.transform.transformPoint(localCenter)
            let clip = projectionMatrix * viewMatrix * SIMD4<Float>(worldCenter.x, worldCenter.y, worldCenter.z, 1.0)
            guard clip.w > 0.001 else { continue }
            let ndcZ = clip.z / clip.w
            guard ndcZ >= 0.0 && ndcZ <= 1.0 else { continue }
            let ndcX = clip.x / clip.w
            let ndcY = clip.y / clip.w
            let dx = Double(ndcX * 0.5 + 0.5)
            let dy = Double(1.0 - (ndcY * 0.5 + 0.5))
            guard dx >= 0.0 && dx <= 1.0 && dy >= 0.0 && dy <= 1.0 else { continue }
            hits.append(ViewportProbeHit(id: mesh.id, normalizedOffset: SIMD2<Double>(dx, dy)))
        }
        return hits.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public static func parse(_ string: String) -> ViewportProbeSnapshot {
        ViewportProbeSnapshot.parse(string)
    }
}
