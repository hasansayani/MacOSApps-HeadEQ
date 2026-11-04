import XCTest
@testable import EQCore

final class VersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(SemVer("v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(SemVer("0.6")?.description, "0.6.0")
        XCTAssertEqual(SemVer("2.0.0-beta.2")?.prerelease, ["beta", "2"])
        XCTAssertEqual(SemVer("1.0.0+build.5")?.description, "1.0.0")
        XCTAssertNil(SemVer("dev"))
        XCTAssertNil(SemVer("1.x"))
    }

    func testOrdering() {
        let order = ["0.5.0", "0.5.1", "0.6.0-alpha", "0.6.0-alpha.2", "0.6.0-beta", "0.6.0", "0.10.0", "1.0.0"].map { SemVer($0)! }
        for i in 1..<order.count { XCTAssertLessThan(order[i - 1], order[i], "\(order[i - 1]) < \(order[i])") }
        XCTAssertEqual(SemVer("1.0")!, SemVer("1.0.0")!)
    }

    func testUpdateDecision() {
        let current = SemVer("0.6.0")!
        XCTAssertTrue(UpdateInfo(version: SemVer("0.6.1")!, url: "", notes: "").isNewer(than: current))
        XCTAssertFalse(UpdateInfo(version: SemVer("0.6.0")!, url: "", notes: "").isNewer(than: current))
        XCTAssertFalse(UpdateInfo(version: SemVer("0.7.0-beta")!, url: "", notes: "").isNewer(than: current), "stable users skip betas")
        XCTAssertTrue(UpdateInfo(version: SemVer("0.7.0-beta.2")!, url: "", notes: "").isNewer(than: SemVer("0.7.0-beta.1")!))
    }
}
