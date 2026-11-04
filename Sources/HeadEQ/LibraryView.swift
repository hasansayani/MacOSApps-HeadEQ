import AppKit
import EQCore
import SwiftUI
import UniformTypeIdentifiers

/// Folder-based sync of the user library (iCloud Drive by default). Only
/// exists while the Preset sync feature is on.
@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var lastSync: Date?
    @Published private(set) var message = ""
    private weak var model: EQModel?
    private var timer: Timer?
    private var lastSeenModified: Date?
    private var writing = false

    static let folderKey = "syncFolderPath"
    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/HeadEQ", isDirectory: true)
    }
    static var iCloudDriveAvailable: Bool {
        FileManager.default.fileExists(atPath: defaultFolder.deletingLastPathComponent().path)
    }
    var folder: URL {
        UserDefaults.standard.string(forKey: Self.folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultFolder
    }
    var fileURL: URL { folder.appendingPathComponent("HeadEQ Library.headeq") }

    func start(model: EQModel) {
        self.model = model
        model.onLibraryChanged = { [weak self] in self?.writeLocal() }
        syncNow()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullIfChanged() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        model?.onLibraryChanged = nil
        message = "Sync is off"
    }

    func setFolder(_ url: URL?) {
        UserDefaults.standard.set(url?.path, forKey: Self.folderKey)
        lastSeenModified = nil
        syncNow()
    }

    func syncNow() {
        pull(force: true)
        writeLocal()
    }

    private func pullIfChanged() { pull(force: false) }

    private func pull(force: Bool) {
        guard let model else { return }
        let mod = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
        guard force || mod != lastSeenModified, let data = try? Data(contentsOf: fileURL),
              let remote = try? JSONDecoder().decode(PresetLibrary.self, from: data) else { return }
        lastSeenModified = mod
        let added = model.importLibrary(remote)
        lastSync = Date()
        message = added > 0 ? "Received \(added) item\(added == 1 ? "" : "s")" : "Up to date"
    }

    private func writeLocal() {
        guard let model, !writing else { return }
        writing = true
        defer { writing = false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Merge with what's there first so another Mac's additions aren't lost.
            var lib = model.userLibrary
            if let data = try? Data(contentsOf: fileURL), let remote = try? JSONDecoder().decode(PresetLibrary.self, from: data) {
                lib = lib.merged(with: remote).library
            }
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(lib).write(to: fileURL, options: .atomic)
            lastSeenModified = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
            lastSync = Date()
            message = "Saved \(lib.presets.count) presets, \(lib.headphones.count) headphones"
        } catch {
            message = "Couldn't write sync file: \(error.localizedDescription)"
        }
    }
}

struct LibraryPage: View {
    @EnvironmentObject var model: EQModel
    @EnvironmentObject var sync: SyncService
    @State private var status = ""

    var body: some View {
        TwoColumns {
            Section2(title: "Export", icon: "square.and.arrow.up") {
                Button("Export my presets & headphones (.headeq)…") { exportLibrary() }
                Button("Export current EQ as ParametricEQ.txt…") {
                    save(AutoEQ.exportParametricEQ(filters: model.filters, preamp: model.effectivePreamp), name: "HeadEQ ParametricEQ.txt")
                }
                Button("Export current EQ as GraphicEQ (Wavelet)…") {
                    save(PresetFormats.exportGraphicEQ(filters: model.filters, preamp: model.effectivePreamp), name: "HeadEQ GraphicEQ.txt")
                }
                Text("\(model.customPresets.count) presets · \(model.customHeadphones.count) headphone profiles of your own")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section2(title: "Import", icon: "square.and.arrow.down") {
                Button("Import file…") { importFile() }.buttonStyle(.borderedProminent)
                Text("Accepts HeadEQ libraries (.headeq), AutoEQ / Equalizer APO ParametricEQ.txt (becomes a headphone profile) and Wavelet / APO GraphicEQ files (becomes a preset).")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !status.isEmpty { Text(status).font(.callout) }
            }
        } right: {
            Section2(title: "Sync across Macs", icon: "arrow.triangle.2.circlepath.icloud") {
                Toggle("Sync presets & headphones", isOn: $model.settings.features.sync).toggleStyle(.switch)
                Text("Folder: \(sync.folder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                if !SyncService.iCloudDriveAvailable && UserDefaults.standard.string(forKey: SyncService.folderKey) == nil {
                    Label("iCloud Drive isn't turned on. Choose another synced folder.", systemImage: "exclamationmark.icloud")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Choose folder…") { chooseFolder() }
                    Button("Use iCloud Drive") { sync.setFolder(nil) }
                    Button("Sync now") { sync.syncNow() }.disabled(!model.settings.features.sync)
                }
                .controlSize(.small)
                if model.settings.features.sync {
                    Text(sync.message + (sync.lastSync.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Sync only adds, never deletes: deleting a preset on one Mac leaves other Macs' copies alone.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func exportLibrary() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(model.userLibrary), let text = String(data: data, encoding: .utf8) else { return }
        save(text, name: "My HeadEQ Library.headeq")
    }

    private func save(_ text: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8); status = "Saved \(url.lastPathComponent)" }
        catch { status = "Couldn't save: \(error.localizedDescription)" }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .json, UTType(filenameExtension: "headeq") ?? .data]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let item = PresetFormats.parse(text: text, fileName: url.lastPathComponent, id: "user-\(UUID().uuidString)") { json in
            try? JSONDecoder().decode(PresetLibrary.self, from: Data(json.utf8))
        }
        status = item.map { model.importItem($0) } ?? "Couldn't recognise “\(url.lastPathComponent)”."
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { sync.setFolder(url) }
    }
}
