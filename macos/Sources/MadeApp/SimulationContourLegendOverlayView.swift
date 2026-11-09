import SwiftUI
import MadeCore
import simd

/// Floating viewport overlay rendering CAE color gradient legend and screen-projected min/max markers (BL-RES-02, #193).
public struct SimulationContourLegendOverlayView: View {
    @Environment(WorkspaceModel.self) private var workspace
    public let studyId: UUID
    public let settings: SimulationContourSettings
    public let extrema: SimulationContourExtrema

    public var onRangeChanged: ((Double, Double) -> Void)? = nil
    public var clipOutsideRange: Bool = false
    public var onToggleClipOutsideRange: ((Bool) -> Void)? = nil

    @State private var dragMin: Double? = nil
    @State private var dragMax: Double? = nil

    public init(
        studyId: UUID,
        settings: SimulationContourSettings,
        extrema: SimulationContourExtrema,
        onRangeChanged: ((Double, Double) -> Void)? = nil,
        clipOutsideRange: Bool = false,
        onToggleClipOutsideRange: ((Bool) -> Void)? = nil
    ) {
        self.studyId = studyId
        self.settings = settings
        self.extrema = extrema
        self.onRangeChanged = onRangeChanged
        self.clipOutsideRange = clipOutsideRange
        self.onToggleClipOutsideRange = onToggleClipOutsideRange
    }

    public var body: some View {
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
        .allowsHitTesting(onRangeChanged != nil || onToggleClipOutsideRange != nil)
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
                ZStack(alignment: .topLeading) {
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

                    if onRangeChanged != nil {
                        let curMax = dragMax ?? extrema.effectiveMax
                        let curMin = dragMin ?? extrema.effectiveMin
                        let effectiveRange = max(1e-9, extrema.effectiveMax - extrema.effectiveMin)
                        let maxFrac = max(0.0, min(1.0, (curMax - extrema.effectiveMin) / effectiveRange))
                        let maxY = (1.0 - maxFrac) * 140.0

                        let minFrac = max(0.0, min(1.0, (curMin - extrema.effectiveMin) / effectiveRange))
                        let minY = (1.0 - minFrac) * 140.0

                        // Max threshold handle
                        thresholdHandle(isMax: true, yPos: maxY)
                            .gesture(
                                DragGesture()
                                    .onChanged { val in
                                        let newY = max(0.0, min(minY - 4.0, maxY + val.translation.height))
                                        let newFrac = 1.0 - (newY / 140.0)
                                        let newMax = extrema.effectiveMin + newFrac * effectiveRange
                                        dragMax = newMax
                                        onRangeChanged?(curMin, newMax)
                                    }
                                    .onEnded { _ in
                                        let finalMax = dragMax ?? curMax
                                        onRangeChanged?(curMin, finalMax)
                                        dragMax = nil
                                    }
                            )

                        // Min threshold handle
                        thresholdHandle(isMax: false, yPos: minY)
                            .gesture(
                                DragGesture()
                                    .onChanged { val in
                                        let newY = max(maxY + 4.0, min(140.0, minY + val.translation.height))
                                        let newFrac = 1.0 - (newY / 140.0)
                                        let newMin = extrema.effectiveMin + newFrac * effectiveRange
                                        dragMin = newMin
                                        onRangeChanged?(newMin, curMax)
                                    }
                                    .onEnded { _ in
                                        let finalMin = dragMin ?? curMin
                                        onRangeChanged?(finalMin, curMax)
                                        dragMin = nil
                                    }
                            )
                    }
                }
                .frame(width: onRangeChanged != nil ? 26 : 14, height: 140)

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

            // Iso-Volume Clip Toggle button
            if onToggleClipOutsideRange != nil {
                Divider()
                    .padding(.vertical, 2)
                Button(action: {
                    onToggleClipOutsideRange?(!clipOutsideRange)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: clipOutsideRange ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11))
                            .foregroundStyle(clipOutsideRange ? Color.accentColor : Color.secondary)
                        Text("Iso-Volume Clip")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("simulation-contour-clip-toggle")
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

    @ViewBuilder
    private func thresholdHandle(isMax: Bool, yPos: CGFloat) -> some View {
        HStack(spacing: 1) {
            Rectangle()
                .fill(isMax ? Color.red : Color.blue)
                .frame(width: 14, height: 2)
            Image(systemName: "arrowtriangle.backward.fill")
                .font(.system(size: 7))
                .foregroundStyle(isMax ? Color.red : Color.blue)
        }
        .offset(x: 0, y: max(0, min(138, yPos - 1)))
        .accessibilityIdentifier(isMax ? "simulation-legend-max-handle" : "simulation-legend-min-handle")
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
