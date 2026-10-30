import XCTest
@testable import Tray

final class DiscoveryTests: XCTestCase {
    // Frames observed on a notch MacBook, macOS 15 (docs/FINDINGS.md).
    func testMatchIndex() {
        let ax = [CGRect(x: 1011, y: 6, width: 42, height: 24),  // Telegram: 1pt wider than its window
                  CGRect(x: 1051, y: 6, width: 34, height: 24),  // Maccy
                  CGRect(x: 608, y: 6, width: 33, height: 24)]   // Stats: 7pt narrower than its window
        XCTAssertEqual(matchIndex(for: CGRect(x: 1012, y: 0, width: 40, height: 36), in: ax), 0)
        XCTAssertEqual(matchIndex(for: CGRect(x: 1052, y: 0, width: 32, height: 36), in: ax), 1)
        XCTAssertEqual(matchIndex(for: CGRect(x: 601, y: 0, width: 47, height: 36), in: ax), 2)
        XCTAssertNil(matchIndex(for: CGRect(x: 2930, y: -62, width: 40, height: 24), in: ax), "other display's copy")
        XCTAssertNil(matchIndex(for: .zero, in: []))
    }
}
