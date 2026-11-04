import EQCore
import SwiftUI

/// Type a headphone name → pick a measured correction from AutoEQ, an existing
/// profile, or create a starter profile from the name alone.
struct AddHeadphoneView: View {
    @EnvironmentObject var model: EQModel
    @ObservedObject var library: HeadphoneLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var results: [AutoEQ.Entry] = []
    @State private var adding: AutoEQ.Entry?
    @State private var error: String?

    private var localMatches: [HeadphoneProfile] {
        let tokens = AutoEQ.tokenize(query)
        guard !tokens.isEmpty else { return [] }
        return model.headphoneProfiles.filter { p in
            let name = AutoEQ.tokenize(p.name + " " + p.matchKeywords.joined(separator: " ")).joined()
            return p.id != "none" && tokens.allSatisfy { name.contains($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Headphones by Name").font(.title3.bold())
            TextField("Headphone model — e.g. Sony WH-1000XM3, Sennheiser Momentum 4, Moondrop Aria",
                      text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _, q in results = library.search(q) }

            List {
                if !localMatches.isEmpty {
                    Section("Already in HeadEQ") {
                        ForEach(localMatches) { p in
                            row(title: p.name, subtitle: "\(p.kind.rawValue) · \(p.provenance.title)", button: "Use") {
                                model.settings.headphoneProfileID = p.id
                                dismiss()
                            }
                        }
                    }
                }
                Section {
                    switch library.state {
                    case .loading, .idle:
                        HStack { ProgressView().controlSize(.small); Text("Loading measured database…") }
                    case .failed(let message):
                        Label(message, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                    case .ready:
                        if query.isEmpty {
                            Text("\(library.entries.count) measured profiles available.").foregroundStyle(.secondary)
                        } else if results.isEmpty {
                            Text("No measured profile matches “\(query)”.").foregroundStyle(.secondary)
                        }
                        ForEach(results) { e in
                            row(title: e.name, subtitle: "\(e.kind.rawValue) · measured by \(e.source)",
                                button: adding == e ? nil : "Add") { add(e) }
                        }
                    }
                } header: {
                    Text("AutoEQ measured database")
                }
            }
            .frame(minHeight: 300)

            if let error { Text(error).font(.caption).foregroundStyle(.orange) }

            HStack {
                Button {
                    let p = HeadphoneNaming.starterProfile(named: query, id: "user-hp-\(UUID().uuidString)")
                    model.saveHeadphone(p)
                    dismiss()
                } label: {
                    Label("Create starter profile for “\(query)”", systemImage: "wand.and.stars")
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("No measurement needed: picks a typical curve for the headphone type guessed from the name")
                Spacer()
                Button("Close", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Measured corrections come from the open AutoEQ project (github.com/jaakkopasanen/AutoEq). Each profile records who measured it — see Expert ▸ Tuning sources.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 620, height: 600)
        .task { await library.loadIndex(); results = library.search(query) }
    }

    private func row(title: String, subtitle: String, button: String?, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let button { Button(button, action: action) } else { ProgressView().controlSize(.small) }
        }
    }

    private func add(_ entry: AutoEQ.Entry) {
        adding = entry
        error = nil
        Task {
            do {
                let profile = try await library.fetchProfile(entry)
                model.saveHeadphone(profile)
                dismiss()
            } catch {
                self.error = "Couldn't download \(entry.name): \(error.localizedDescription)"
            }
            adding = nil
        }
    }
}
