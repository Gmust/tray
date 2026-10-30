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

    func testTrayItems() {
        func window(_ id: CGWindowID, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> StatusWindow {
            StatusWindow(windowID: id, pid: 1, frame: CGRect(x: x, y: y, width: w, height: h), onScreen: false)
        }
        let chevron = CGRect(x: 1300, y: 0, width: 36, height: 36)
        let separator = CGRect(x: 1300 - 10_000, y: 0, width: 10_000, height: 36)  // collapsed
        let windows = [
            window(1, -8800, 0, 40, 36),     // tray: the app's original window → kept
            window(8, -8800, 0, 40, 36),     // a display's copy of 1: same pid and frame, newer id
            window(2, -8760, 0, 47, 36),     // tray
            window(3, -8700, -62, 40, 24),   // left of the separator, but the other display's row
            window(4, 0, 0, 16, 36),         // ghost at the origin: right of a collapsed separator
            window(5, separator.minX, 0, separator.width, 36),  // the separator itself
            window(6, 1300, 0, 36, 36),      // the chevron
            window(7, 1336, 0, 32, 36),      // pinned
        ]
        XCTAssertEqual(trayItems(in: windows, chevron: chevron, separator: separator).map(\.windowID), [1, 2])
    }
}
