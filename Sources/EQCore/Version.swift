/// Semantic versions for update checks ("1.2.3", "v1.2", "1.3.0-beta.2").
public struct SemVer: Comparable, CustomStringConvertible, Sendable {
    public var major: Int, minor: Int, patch: Int
    public var prerelease: [String]

    public init?(_ text: String) {
        var t = text.trimmed
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        let mainAndPre = t.split(separator: "-", maxSplits: 1).map(String.init)
        let core = (mainAndPre.first ?? "").split(separator: "+").first.map(String.init) ?? ""
        let nums = core.split(separator: ".").map { Int($0) }
        guard !nums.isEmpty, nums.count <= 3, nums.allSatisfy({ $0 != nil }) else { return nil }
        major = nums[0]!
        minor = nums.count > 1 ? nums[1]! : 0
        patch = nums.count > 2 ? nums[2]! : 0
        prerelease = mainAndPre.count > 1 ? mainAndPre[1].split(separator: ".").map(String.init) : []
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    public static func < (a: SemVer, b: SemVer) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        // A pre-release sorts before the release.
        if a.prerelease.isEmpty != b.prerelease.isEmpty { return !a.prerelease.isEmpty }
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            if let xi = Int(x), let yi = Int(y) { return xi < yi }
            return x < y
        }
        return a.prerelease.count < b.prerelease.count
    }

    public static func == (a: SemVer, b: SemVer) -> Bool { !(a < b) && !(b < a) }
}

public struct UpdateInfo: Equatable, Sendable {
    public var version: SemVer
    public var url: String
    public var notes: String
    public init(version: SemVer, url: String, notes: String) { self.version = version; self.url = url; self.notes = notes }

    public static func == (a: UpdateInfo, b: UpdateInfo) -> Bool { a.version == b.version && a.url == b.url && a.notes == b.notes }

    /// Newer than `current`? (Skips pre-releases unless the user runs one.)
    public func isNewer(than current: SemVer) -> Bool {
        if !version.prerelease.isEmpty && current.prerelease.isEmpty { return false }
        return current < version
    }
}
