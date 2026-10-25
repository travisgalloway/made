import SwiftUI
import MadeCore
import simd

/// Floating viewport overlay rendering CAE color gradient legend and screen-projected min/max markers (BL-RES-02, #193).
struct SimulationContourLegendOverlayView: View {
    @Environment(WorkspaceModel.self) private var workspace
    let studyId: UUID
    let settings: SimulationContourSettings
    let extrema: SimulationContourExtrema

    var body: some View {
        GeometryReader { geo in
            let viewportSize = geo.size

            ZStack(alignment: .bottomLeading) {
                // Min/Max screen-projected markers
                if settings.showMinMaxMarkers,
                   viewportSize.width > 0,
                   viewportSize.height > 0,
                   let renderer = workspace.viewportManager.renderer {
                    let aspect = Float(max(1.0, viewportSize.width) / max(1.0, viewportSize.height))
                    let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
                    let vp = simd_mul(matrices.projection, matrices.view)

                    if let maxPos = extrema.maxPosition {
                        let maxPt = SIMD3<Float>(Float(maxPos.x), Float(maxPos.y), Float(maxPos.z))
                        if let screen = projectToScreen(point: maxPt, viewProjectionMatrix: vp, viewportSize: viewportSize) {
                            let canvasPt = SnapOverlayView.canvasPosition(screenPoint: screen, viewportHeight: viewportSize.height)
                            markerBadge(
                                label: "Max: \(formatValue(extrema.actualMax))",
                                unit: extrema.unitSymbol,
                                point: canvasPt,
                                color: .red,
                                identifier: "simulation-contour-max-marker"
                            )
                        }
                    }

                    if let minPos = extrema.minPosition {
                        let minPt = SIMD3<Float>(Float(minPos.x), Float(minPos.y), Float(minPos.z))
                        if let screen = projectToScreen(point: minPt, viewProjectionMatrix: vp, viewportSize: viewportSize) {
                            let canvasPt = SnapOverlayView.canvasPosition(screenPoint: screen, viewportHeight: viewportSize.height)
                            markerBadge(
                                label: "Min: \(formatValue(extrema.actualMin))",
                                unit: extrema.unitSymbol,
                                point: canvasPt,
                                color: .blue,
                                isBelow: true,
                                identifier: "simulation-contour-min-marker"
                            )
                        }
                    }
                }

                // Probe screen-projected callout badges (BL-RES-04, #325)
                if let study = workspace.document.study(id: studyId),
                   study.probeTable.showProbeBadges,
                   !study.probeTable.probes.isEmpty,
                   viewportSize.width > 0,
                   viewportSize.height > 0,
                   let renderer = workspace.viewportManager.renderer {
                    let aspect = Float(max(1.0, viewportSize.width) / max(1.0, viewportSize.height))
                    let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
                    let vp = simd_mul(matrices.projection, matrices.view)

                    ForEach(study.probeTable.probes) { probe in
                        let pt = SIMD3<Float>(Float(probe.position.x), Float(probe.position.y), Float(probe.position.z))
                        if let screen = projectToScreen(point: pt, viewProjectionMatrix: vp, viewportSize: viewportSize) {
                            let canvasPt = SnapOverlayView.canvasPosition(screenPoint: screen, viewportHeight: viewportSize.height)
                            let val = probe.fieldValues[settings.field] ?? 0.0
                            markerBadge(
                                label: "\(probe.name): \(formatValue(val))",
                                unit: settings.field.defaultUnitSymbol,
                                point: canvasPt,
                                color: .orange,
                                identifier: "simulation-probe-marker-\(probe.id)"
                            )
                        }
                    }
                }

                // Legend Card
                legendCard
                    .padding(.leading, 16)
                    .padding(.bottom, 24)
                    .accessibilityIdentifier("simulation-contour-legend-card")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("simulation-contour-legend-overlay")
    }

    // MARK: - Legend Card

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text(extrema.fieldName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                if !extrema.unitSymbol.isEmpty {
                    Text("(\(extrema.unitSymbol))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Gradient bar + tick mark labels
            HStack(spacing: 8) {
                // Gradient bar: top is high (t=1.0), bottom is low (t=0.0)
                let gradientColors = SimulationColorMap.gradientColors(map: settings.colorMap, sampleCount: 32).reversed()
                LinearGradient(
                    colors: Array(gradientColors),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 14, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )

                // Tick intervals: 5 values from effectiveMax down to effectiveMin
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<5) { step in
                        let fraction = 1.0 - Double(step) / 4.0
                        let val = extrema.effectiveMin + fraction * (extrema.effectiveMax - extrema.effectiveMin)
                        Text(formatValue(val))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if step < 4 {
                            Spacer()
                        }
                    }
                }
                .frame(height: 140)
            }

            // Extrema summary read-out
            HStack(spacing: 6) {
                Text("Range:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("\(formatValue(extrema.actualMin)) … \(formatValue(extrema.actualMax))")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
    }

    // MARK: - Screen-Projected Marker Callout

    @ViewBuilder
    private func markerBadge(
        label: String,
        unit: String,
        point: CGPoint,
        color: Color,
        isBelow: Bool = false,
        identifier: String
    ) -> some View {
        let badgeText = unit.isEmpty ? label : "\(label) \(unit)"
        let yOffset: CGFloat = isBelow ? 14 : -14

        ZStack {
            // Anchor dot
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                .position(x: point.x, y: point.y)

            // Floating pill badge
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(badgeText)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
            .position(x: point.x + 40, y: point.y + yOffset)
        }
        .accessibilityIdentifier(identifier)
    }

    private func formatValue(_ val: Double) -> String {
        if val.isNaN { return "NaN" }
        let absVal = abs(val)
        if absVal >= 10000 || (absVal < 0.001 && absVal > 0) {
            return String(format: "%.2e", val)
        } else if absVal >= 100 {
            return String(format: "%.1f", val)
        } else {
            return String(format: "%.2f", val)
        }
    }
}
