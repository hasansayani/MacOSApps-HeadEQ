import AppKit
import EQCore
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message, or nil on success.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Couldn't change the login item: \(error.localizedDescription). Move HeadEQ to /Applications and try again."
        }
    }
}

/// Daily update check against a release feed. The feed URL comes from the
/// app's Info.plist (`HEQUpdateFeedURL`, set at build time). Two formats are
/// understood: a GitHub "releases/latest" API response, or a simple JSON
/// `{"version": "1.2.0", "url": "https://…", "notes": "…"}`.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var available: UpdateInfo?
    @Published private(set) var status = ""
    @Published private(set) var lastChecked: Date?
    private var timer: Timer?

    static var feedURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "HEQUpdateFeedURL") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    func start() {
        guard timer == nil else { return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.check() } }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func check() async {
        guard let url = Self.feedURL else {
            status = "No update feed configured for this build."
            return
        }
        guard let current = SemVer(AppInfo.version) else { status = "Development build — updates not checked."; return }
        status = "Checking…"
        do {
            var req = URLRequest(url: url)
            req.setValue("HeadEQ/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let info = Self.parse(data) else { status = "Couldn't read the update feed."; return }
            lastChecked = Date()
            if info.isNewer(than: current) {
                available = info
                status = "HeadEQ \(info.version) is available."
            } else {
                available = nil
                status = "You're up to date (\(current))."
            }
        } catch {
            status = "Update check failed: \(error.localizedDescription)"
        }
    }

    static func parse(_ data: Data) -> UpdateInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let tag = obj["tag_name"] as? String, let v = SemVer(tag) {   // GitHub releases API
            let asset = (obj["assets"] as? [[String: Any]])?.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
            let url = asset?["browser_download_url"] as? String ?? obj["html_url"] as? String ?? ""
            return UpdateInfo(version: v, url: url, notes: obj["body"] as? String ?? "")
        }
        if let vs = obj["version"] as? String, let v = SemVer(vs) {
            return UpdateInfo(version: v, url: obj["url"] as? String ?? "", notes: obj["notes"] as? String ?? "")
        }
        return nil
    }

    func openDownload() {
        if let s = available?.url, let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}
