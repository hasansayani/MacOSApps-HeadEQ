import XCTest
@testable import EQCore

/// Runs only when AUTOEQ_INDEX points at a downloaded AutoEQ INDEX.md.
final class RealIndexTests: XCTestCase {
    func testRealIndex() throws {
        guard let path = ProcessInfo.processInfo.environment["AUTOEQ_INDEX"] else { throw XCTSkip("AUTOEQ_INDEX not set") }
        let entries = AutoEQ.parseIndex(try String(contentsOfFile: path, encoding: .utf8))
        print("parsed \(entries.count) entries")
        XCTAssertGreaterThan(entries.count, 5000)
        for q in ["sony xm3", "Sony WH-1000XM3", "bose soundsport", "hd 650", "airpods pro 2", "momentum 4"] {
            let r = AutoEQ.search(q, in: entries)
            print(q, "→", r.prefix(3).map { "\($0.name) [\($0.source)]" })
        }
        XCTAssertEqual(AutoEQ.search("Sony WH-1000XM3", in: entries).first?.source, "oratory1990")
    }
}
