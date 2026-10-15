import SwiftUI
import MadeCore

struct CommandPanelView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Bindable var session: CommandSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if !session.selectionSlots.isEmpty {
                selectionSlotsSection
                Divider()
            }

            inputsSection

            Divider()

            Toggle("Preview", isOn: $session.isPreviewEnabled)
                .controlSize(.small)

            Divider()

            footerButtons
        }
        .padding(8)
    }

    private var header: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.tint)
            Text(session.title)
                .font(.headline)
            Spacer()
        }
    }

    private var selectionSlotsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selection")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(session.selectionSlots) { slot in
                HStack {
                    Text(slot.label)
                        .font(.callout)
                    if slot.isRequired {
                        Text("*")
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    if let name = slot.selectedObjectName {
                        Text(name)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    } else {
                        Text("Click solid to select")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(slot.isActive ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .onTapGesture {
                    session.selectSlot(id: slot.id)
                }
            }
        }
    }

    private var inputsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.inputs) { input in
                inputRow(input)
            }
        }
    }

    @ViewBuilder
    private func inputRow(_ input: CommandInput) -> some View {
        switch input.value {
        case .number(let val, let range, let step, let unit):
            HStack(spacing: 4) {
                Text(input.label)
                    .font(.callout)
                Spacer()
                CommitNumberField(label: input.label, value: Double(val), width: 64) { newVal in
                    session.setNumberValue(Float(newVal), for: input.id)
                }
                .accessibilityLabel(input.label)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let range {
                    let binding = Binding<Double>(
                        get: { Double(session.numberValue(for: input.id) ?? val) },
                        set: { session.setNumberValue(Float($0), for: input.id) }
                    )
                    Stepper(
                        input.label,
                        value: binding,
                        in: Double(range.lowerBound)...Double(range.upperBound),
                        step: Double(step)
                    )
                    .labelsHidden()
                }
            }
        case .text(let val):
            HStack {
                Text(input.label)
                    .font(.callout)
                Spacer()
                TextField(
                    input.label,
                    text: Binding(
                        get: { session.textValue(for: input.id) ?? val },
                        set: { session.setTextValue($0, for: input.id) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            }
        case .toggle(let val):
            Toggle(
                input.label,
                isOn: Binding(
                    get: { session.toggleValue(for: input.id) ?? val },
                    set: { session.setToggleValue($0, for: input.id) }
                )
            )
            .font(.callout)
        case .choice(let val, let options):
            HStack {
                Text(input.label)
                    .font(.callout)
                Spacer()
                Picker(
                    input.label,
                    selection: Binding(
                        get: { session.choiceValue(for: input.id) ?? val },
                        set: { session.setChoiceValue($0, for: input.id) }
                    )
                ) {
                    ForEach(options, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
        }
    }

    private var footerButtons: some View {
        HStack {
            Button("Cancel") {
                workspace.cancelActiveCommand()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("OK") {
                workspace.commitActiveCommand()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!session.canCommit)
        }
        .controlSize(.small)
    }
}
