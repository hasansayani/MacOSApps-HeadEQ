import EQCore
import SwiftUI

/// Create or edit a custom headphone correction. Changes are auditioned live.
struct HeadphoneEditorView: View {
    @EnvironmentObject var model: EQModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: HeadphoneProfile
    @State private var keywords = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.customHeadphones.contains { $0.id == draft.id } ? "Edit Headphones" : "New Headphones")
                .font(.title3.bold())

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Name")
                    TextField("e.g. Bose SoundSport", text: $draft.name).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Type")
                    Picker("", selection: $draft.kind) {
                        ForEach(HeadphoneKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented)
                }
                GridRow {
                    Text("Auto-detect")
                    TextField("Words in the device name, comma separated (e.g. soundsport, bose)", text: $keywords)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Source")
                    HStack {
                        Badge(text: draft.provenance.title, color: .secondary)
                        Text(draft.provenance.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                GridRow {
                    Text("Notes")
                    TextField("Optional", text: $draft.note).textFieldStyle(.roundedBorder)
                }
            }

            ResponseCurveView(filters: draft.filters, preamp: 0)
                .frame(height: 130)
                .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))

            HStack {
                Text("Correction filters").font(.headline)
                Text("\(draft.filters.count)/\(HeadphoneProfile.maxFilters)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { draft.filters.append(.peak(1000, 0, q: 1)) } label: { Label("Add Filter", systemImage: "plus") }
                    .disabled(draft.filters.count >= HeadphoneProfile.maxFilters)
            }

            ScrollView {
                VStack(spacing: 6) {
                    if draft.filters.isEmpty {
                        Text("No filters yet. Add one, or start from a built-in model with “Customize…”.")
                            .font(.callout).foregroundStyle(.secondary).padding()
                    }
                    ForEach(Array(draft.filters.enumerated()), id: \.offset) { index, _ in
                        FilterRow(filter: filterBinding(index)) { draft.filters.remove(at: index) }
                    }
                }
            }
            .frame(minHeight: 160)

            HStack {
                Text("You're hearing these changes live.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { model.previewHeadphone = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    draft.matchKeywords = keywords.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
                    model.saveHeadphone(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640, height: 640)
        .onAppear {
            keywords = draft.matchKeywords.joined(separator: ", ")
            model.previewHeadphone = draft
        }
        .onChange(of: draft) { _, new in model.previewHeadphone = new }
        .onDisappear { model.previewHeadphone = nil }
    }

    /// Bounds-checked binding so deleting rows can't crash.
    private func filterBinding(_ i: Int) -> Binding<FilterSpec> {
        Binding(get: { i < draft.filters.count ? draft.filters[i] : .peak(1000, 0) },
                set: { if i < draft.filters.count { draft.filters[i] = $0 } })
    }
}

private struct FilterRow: View {
    @Binding var filter: FilterSpec
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("", selection: $filter.type) {
                Text("Peak").tag(FilterType.peak)
                Text("Low shelf").tag(FilterType.lowShelf)
                Text("High shelf").tag(FilterType.highShelf)
            }
            .labelsHidden().frame(width: 105)
            TextField("Hz", value: $filter.frequency, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder).frame(width: 64)
            Text("Hz").font(.caption).foregroundStyle(.secondary)
            Slider(value: $filter.gain, in: -15...15, step: 0.1)
            Text(String(format: "%+.1f dB", filter.gain)).monospacedDigit().font(.caption).frame(width: 56, alignment: .trailing)
            Text("Q").font(.caption).foregroundStyle(.secondary)
            TextField("Q", value: $filter.q, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder).frame(width: 48)
            Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
    }
}
