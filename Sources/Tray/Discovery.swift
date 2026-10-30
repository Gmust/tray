import AppKit
import ApplicationServices

/// A status item window. `frame` is global, top-left origin (CoreGraphics / AX space).
struct StatusWindow {
    let windowID: CGWindowID
    let pid: pid_t
    let frame: CGRect
    let onScreen: Bool
}

/// All status item windows (layer 25), ours included, in menu bar order (left to right).
/// Raw: every display's copy, ghosts and overlays too (docs/FINDINGS.md). Use `trayItems` to select.
func statusWindows() -> [StatusWindow] {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
    return list.compactMap { info -> StatusWindow? in
        guard info[kCGWindowLayer as String] as? Int == statusLayer,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let id = info[kCGWindowNumber as String] as? CGWindowID,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds)
        else { return nil }
        return StatusWindow(windowID: id, pid: pid, frame: frame,
                            onScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }
    .sorted { $0.frame.minX < $1.frame.minX }
}

/// Tray items: windows in the chevron's menu bar row (same y and height, so same display) that end left
/// of the separator. Keeps the input order. Our own windows never qualify: the separator does not end
/// left of itself, and the chevron is right of it. The active row holds two windows per item with the
/// same frame (original + per-display copy); the older one (lower windowID) is kept.
func trayItems(in windows: [StatusWindow], chevron: CGRect, separator: CGRect) -> [StatusWindow] {
    let row = windows.filter {
        abs($0.frame.minY - chevron.minY) < 1 && abs($0.frame.height - chevron.height) < 1
            && $0.frame.maxX <= separator.minX
    }
    return row.filter { w in !row.contains { $0.pid == w.pid && $0.frame == w.frame && $0.windowID < w.windowID } }
}

/// A child of an app's AXExtrasMenuBar. `frame` is global, top-left origin.
struct AXItem: Encodable {
    let title: String?
    let description: String?
    let identifier: String?
    let frame: CGRect
}

func axItems(pid: pid_t) -> [AXItem] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)  // a hung app must not hang us
    guard let bar: AXUIElement = axAttribute(app, "AXExtrasMenuBar"),
          let children: [AXUIElement] = axAttribute(bar, kAXChildrenAttribute)
    else { return [] }
    return children.compactMap { element in
        guard let position: AXValue = axAttribute(element, kAXPositionAttribute),
              let size: AXValue = axAttribute(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &origin)
        AXValueGetValue(size, .cgSize, &extent)
        return AXItem(title: axAttribute(element, kAXTitleAttribute),
                      description: axAttribute(element, kAXDescriptionAttribute),
                      identifier: axAttribute(element, kAXIdentifierAttribute),
                      frame: CGRect(origin: origin, size: extent))
    }
}

func axAttribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

/// Index of the candidate centered on `frame` (within 1pt). AX elements share their window's center but
/// not its size: e.g. Stats insets 7pt per side, Telegram outsets 1pt, both 24pt tall in a 36pt menu bar.
func matchIndex(for frame: CGRect, in candidates: [CGRect]) -> Int? {
    func distance(_ r: CGRect) -> CGFloat { max(abs(r.midX - frame.midX), abs(r.midY - frame.midY)) }
    guard let best = candidates.indices.min(by: { distance(candidates[$0]) < distance(candidates[$1]) }),
          distance(candidates[best]) <= 1
    else { return nil }
    return best
}

/// `--dump`: every status item window plus its matched AX element, as JSON on stdout.
/// `chevron`, `separator` and `inTray` need a running Tray and AX access (to find its items by identifier).
func dump() {
    struct Entry: Encodable {
        let pid: pid_t
        let app: String?
        let bundleID: String?
        let windowID: CGWindowID
        let frame: CGRect
        let onScreen: Bool
        let inTray: Bool?
        let axMatch: Bool
        let ax: AXItem?
    }
    struct Output: Encodable {
        let accessibility: Bool
        let screenRecording: Bool
        let chevron: CGRect?
        let separator: CGRect?
        let items: [Entry]
    }

    let windows = statusWindows()
    var axCache: [pid_t: [AXItem]] = [:]
    func ax(for window: StatusWindow) -> AXItem? {
        let candidates = axCache[window.pid] ?? axItems(pid: window.pid)
        axCache[window.pid] = candidates
        return matchIndex(for: window.frame, in: candidates.map(\.frame)).map { candidates[$0] }
    }

    // The running Tray app's own items, found through the AX identifiers MenuBar sets.
    let trayPID = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.illia.tray")
        .first { $0.processIdentifier != getpid() }?.processIdentifier
    func own(_ identifier: String) -> CGRect? {
        windows.first { $0.pid == trayPID && ax(for: $0)?.identifier == identifier }?.frame
    }
    let chevron = own("chevron"), separator = own("separator")
    let tray = chevron.flatMap { c in separator.map { s in Set(trayItems(in: windows, chevron: c, separator: s).map(\.windowID)) } }

    let items = windows.map { window -> Entry in
        let app = NSRunningApplication(processIdentifier: window.pid)
        let ax = ax(for: window)
        return Entry(pid: window.pid, app: app?.localizedName, bundleID: app?.bundleIdentifier,
                     windowID: window.windowID, frame: window.frame, onScreen: window.onScreen,
                     inTray: tray?.contains(window.windowID), axMatch: ax != nil, ax: ax)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let output = Output(accessibility: AXIsProcessTrusted(), screenRecording: CGPreflightScreenCaptureAccess(),
                        chevron: chevron, separator: separator, items: items)
    // Encoding plain structs of strings and numbers cannot fail.
    FileHandle.standardOutput.write(try! encoder.encode(output))
    FileHandle.standardOutput.write(Data("\n".utf8))
}
