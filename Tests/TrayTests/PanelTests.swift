import XCTest
@testable import Tray

final class PanelTests: XCTestCase {
    func testFlowWrapsAtMaxWidth() {
        // Two 40pt icons and a 71pt Stats item fit in 160pt; the next icon wraps; a too-wide item gets its own row.
        let sizes = [CGSize(width: 40, height: 36), CGSize(width: 40, height: 36), CGSize(width: 71, height: 36),
                     CGSize(width: 40, height: 36), CGSize(width: 200, height: 36)]
        let result = flow(sizes, maxWidth: 160, spacing: 4)
        XCTAssertEqual(result.origins, [CGPoint(x: 0, y: 0), CGPoint(x: 44, y: 0), CGPoint(x: 88, y: 0),
                                        CGPoint(x: 0, y: 40), CGPoint(x: 0, y: 80)])
        XCTAssertEqual(result.size, CGSize(width: 200, height: 116))
        XCTAssertEqual(flow([], maxWidth: 160, spacing: 4).size, .zero)
    }

    func testIsBlank() {
        func image(opaquePixel: Bool) -> CGImage {
            let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            if opaquePixel { context.fill(CGRect(x: 2, y: 1, width: 1, height: 1)) }
            return context.makeImage()!
        }
        XCTAssertTrue(isBlank(image(opaquePixel: false)))
        XCTAssertFalse(isBlank(image(opaquePixel: true)))
    }
}
