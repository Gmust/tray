import AppKit

/// Live images of status item windows (SPEC §3), one CoreGraphics capture per window, at the backing
/// scale (@2x on Retina). Synchronous: call it off the main thread. Needs Screen Recording.
///
/// Not ScreenCaptureKit: it gets no frames for status windows pushed off-screen on the notch display, and
/// on macOS 15 each pending request raises its own consent alert (docs/FINDINGS.md). Ice captures hidden
/// items with this same API for the same reason. Deprecated since macOS 14, still working on 15.
func captureImages(of windows: [StatusWindow]) -> [CGWindowID: CGImage] {
    var images: [CGWindowID: CGImage] = [:]
    for window in windows {
        guard let array = windowArray([window.windowID]),
              let image = CGImage(windowListFromArrayScreenBounds: .null, windowArray: array,
                                  imageOption: [.boundsIgnoreFraming, .bestResolution])
        else { continue }
        images[window.windowID] = image
    }
    return images
}

/// True when every pixel is fully transparent. Such an image says nothing about the item: it is treated
/// like a failed capture (e.g. macOS withholding screen capture until the owner allows it).
func isBlank(_ image: CGImage) -> Bool {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return !drawn || !stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] != 0 }
}

/// `--capture <dir>`: PNGs of the running Tray's tray items, named `<index>-<app>-<windowID>.png`.
func captureCommand(to directory: String) -> Int32 {
    guard CGPreflightScreenCaptureAccess() else {
        CGRequestScreenCaptureAccess()  // adds Tray to System Settings → Screen Recording, once
        FileHandle.standardError.write(Data("no Screen Recording access: grant it to Tray and run again\n".utf8))
        return 1
    }
    let windows = statusWindows()
    guard let layout = runningTrayLayout(in: windows) else {
        FileHandle.standardError.write(Data("Tray is not running, or no Accessibility access to find it\n".utf8))
        return 1
    }
    let items = axBacked(trayItems(in: windows, chevron: layout.chevron.frame, separator: layout.separator.frame))
    let images = captureImages(of: items)
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (index, item) in items.enumerated() {
        let app = NSRunningApplication(processIdentifier: item.pid)?.localizedName ?? "pid\(item.pid)"
        guard let image = images[item.windowID],
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            print("\(index) \(app) \(item.windowID): not captured")
            continue
        }
        let file = folder.appendingPathComponent("\(index)-\(app)-\(item.windowID).png")
        do {
            try png.write(to: file)
            print("\(index) \(app) \(item.windowID): \(image.width)x\(image.height) → \(file.path)")
        } catch {
            print("\(index) \(app) \(item.windowID): \(error.localizedDescription)")
        }
    }
    return 0
}
