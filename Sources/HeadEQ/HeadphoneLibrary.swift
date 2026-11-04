import EQCore
import Foundation

/// Downloads and caches the AutoEQ index (≈5,000 measured headphones) and
/// fetches individual corrections on demand.
@MainActor
final class HeadphoneLibrary: ObservableObject {
    enum State: Equatable { case idle, loading, ready, failed(String) }

    @Published private(set) var entries: [AutoEQ.Entry] = []
    @Published private(set) var state: State = .idle

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HeadEQ", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("autoeq-index.md")
    }()

    func loadIndex() async {
        guard state != .loading, entries.isEmpty else { return }
        state = .loading
        let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)
        let age = (attrs?[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        if age < 7 * 86_400, let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
            entries = AutoEQ.parseIndex(cached)
            state = .ready
            return
        }
        do {
            let text = try await download(AutoEQ.indexURL)
            try? text.write(to: cacheURL, atomically: true, encoding: .utf8)
            entries = AutoEQ.parseIndex(text)
            state = entries.isEmpty ? .failed("The AutoEQ index was empty") : .ready
        } catch {
            // Fall back to a stale cache if we have one.
            if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
                entries = AutoEQ.parseIndex(cached)
                state = .ready
            } else {
                state = .failed("Couldn't reach the AutoEQ database (\(error.localizedDescription))")
            }
        }
    }

    func search(_ query: String) -> [AutoEQ.Entry] {
        AutoEQ.search(query, in: entries, limit: 30)
    }

    func fetchProfile(_ entry: AutoEQ.Entry) async throws -> HeadphoneProfile {
        let text = try await download(entry.parametricEQURL)
        guard let profile = AutoEQ.profile(from: entry, parametricEQ: text, id: "user-hp-\(UUID().uuidString)") else {
            throw URLError(.cannotParseResponse)
        }
        return profile
    }

    private func download(_ string: String) async throws -> String {
        guard let url = URL(string: string) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return text
    }
}
