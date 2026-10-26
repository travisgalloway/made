import SwiftUI
import MadeCore
import simd

/// Viewport overlay view that renders heads-up dimension pill badges anchored to 3D geometry features,
/// with click-to-edit inline numeric entry committing values to the active command session.
struct DimensionLabelsOverlayView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Bindable var session: CommandSession
    @State private var editingInputId: String? = nil

    var body: some View {
        GeometryReader { geo in
            let viewportSize = geo.size
            if viewportSize.width > 0 && viewportSize.height > 0,
               let renderer = workspace.viewportManager.renderer {
                let candidates = buildCandidates()
                let aspect = Float(max(1.0, viewportSize.width) / max(1.0, viewportSize.height))
                let matrices = renderer.viewAndProjectionMatrices(aspect: aspect)
                let vp = simd_mul(matrices.projection, matrices.view)
                let placements = DimensionLabelPlacement.computePlacements(
                    candidates: candidates,
                    viewProjectionMatrix: vp,
                    viewportSize: viewportSize
                )

                ZStack(alignment: .topLeading) {
                    ForEach(placements.filter(\.isVisible)) { placement in
                        badgeView(for: placement)
                            .offset(x: placement.screenPosition.x, y: placement.screenPosition.y)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    @MainActor
    static func buildCandidates(session: CommandSession, workspace: WorkspaceModel) -> [DimensionLabelCandidate] {
        let visibleNumericCount = session.visibleInputs.reduce(into: 0) { count, input in
            if case .number = input.value { count += 1 }
        }
        let allowSceneCenterFallback = session.dimensionAnchorsProvider != nil
            || (session.onPreviewUpdate != nil && visibleNumericCount == 1)
        guard allowSceneCenterFallback else { return [] }

        return session.visibleInputs.compactMap { input in
            guard case .number(let val, _, _, let unit) = input.value else {
                return nil
            }
            let anchor: SIMD3<Float>?
            if let provider = session.dimensionAnchorsProvider {
                anchor = provider()[input.id]
            } else {
                anchor = session.dimensionAnchor(for: input.id, workspace: workspace)
            }
            guard let anchor else { return nil }
            return DimensionLabelCandidate(
                id: input.id,
                label: input.label,
                value: val,
                unit: unit.isEmpty ? "mm" : unit,
                worldAnchor: anchor,
                size: CGSize(width: 80, height: 28)
            )
        }
    }

    private func buildCandidates() -> [DimensionLabelCandidate] {
        Self.buildCandidates(session: session, workspace: workspace)
    }


    @ViewBuilder
    private func badgeView(for placement: DimensionLabelPlacementResult) -> some View {
        if editingInputId == placement.id {
            let (minimum, maximum, range, step) = numericRangeAndStep(for: placement.id)
            HStack(spacing: 2) {
                CommitNumberField(
                    label: placement.candidate.label,
                    value: Double(placement.candidate.value),
                    width: 52,
                    minimum: minimum,
                    maximum: maximum,
                    range: range,
                    step: step,
                    onSubmit: {
                        editingInputId = nil
                    },
                    onCancel: {
                        editingInputId = nil
                    },
                    autoFocus: true,
                    commit: { newVal in
                        session.setNumberValue(Float(newVal), for: placement.id)
                    }
                )
                Text(placement.candidate.unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
            .accessibilityIdentifier("dimension-field-\(placement.id)")
        } else {
            Button {
                editingInputId = placement.id
            } label: {
                HStack(spacing: 4) {
                    Text(formatValue(placement.candidate.value))
                        .fontWeight(.medium)
                        .monospacedDigit()
                    Text(placement.candidate.unit)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.separator, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(placement.candidate.label): \(formatValue(placement.candidate.value)) \(placement.candidate.unit)")
            .accessibilityIdentifier("dimension-label-\(placement.id)")
        }
    }

    private func numericRangeAndStep(for inputId: String) -> (min: Double?, max: Double?, range: ClosedRange<Double>?, step: Double) {
        guard let input = session.inputs.first(where: { $0.id == inputId }),
              case .number(_, let range, let step, _) = input.value else {
            return (nil, nil, nil, 1.0)
        }
        if let range {
            return (Double(range.lowerBound), Double(range.upperBound), Double(range.lowerBound)...Double(range.upperBound), Double(step))
        } else {
            return (nil, nil, nil, Double(step))
        }
    }

    private func formatValue(_ value: Float) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}
