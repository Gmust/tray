import AppKit
import ServiceManagement
import os

let log = Logger(subsystem: "dev.illia.tray", category: "app")

/// Our two status items (SPEC §1). `separator` sits left of `chevron`; collapsed, it is 10_000pt wide and
/// pushes every status item left of it (the tray) off-screen. Expanded, it is a thin "│" and the tray
/// items are visible, so they can be rearranged with ⌘-drag.
final class MenuBar: NSObject {
    private let chevron: NSStatusItem
    private let separator: NSStatusItem
    private var expanded = false
    private var observers: [NSObjectProtocol] = []
    /// Set while Tray moves items itself, so its own moves are not taken for the owner's drops.
    private var busy = false
    private lazy var panel = Panel(discover: { [unowned self] in self.currentTrayItems() },
                                   onClick: { [unowned self] item, button in
                                       Task { @MainActor in await self.forwardClick(to: item, button: button) }
                                   },
                                   onDropOnMenuBar: { [unowned self] item in Task { @MainActor in await self.pin(item) } },
                                   onReorder: { [unowned self] item, target, side in
                                       Task { @MainActor in await self.reorder(item, nextTo: target, side: side) }
                                   })

    override init() {
        Self.seedPositions()
        chevron = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        chevron.autosaveName = "chevron"
        separator = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separator.autosaveName = "separator"
        super.init()

        // `--dump` finds our items in another process by these AX identifiers.
        chevron.button?.setAccessibilityIdentifier("chevron")
        separator.button?.setAccessibilityIdentifier("separator")
        chevron.button?.target = self
        chevron.button?.action = #selector(chevronClicked)
        chevron.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        chevron.button?.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Tray")
        separator.button?.title = "│"

        // Re-check whenever our items move: a deferred collapse can proceed once they are placed,
        // ⌘-dragging the separator right of the chevron while collapsed must expand at once, and an item
        // ⌘-dropped onto the chevron lands between separator and chevron (it shifts the separator).
        for window in [chevron.button?.window, separator.button?.window].compactMap({ $0 }) {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { [weak self] _ in
                guard let self, !self.expanded else { return }
                self.apply()
                Task { @MainActor in await self.absorbDroppedItems() }
            })
        }
        DispatchQueue.main.async { self.apply() }
    }

    /// First launch only: chevron rightmost, separator directly left of it. The value is the distance from the
    /// screen's right edge to the item's right edge (docs/FINDINGS.md); 0 and 1 clamp to "as far right as
    /// macOS allows", left of the clock and Control Center. Afterwards AppKit keeps these keys itself.
    private static func seedPositions() {
        for (name, position) in [("chevron", 0.0), ("separator", 1.0)] {
            let key = "NSStatusItem Preferred Position \(name)"
            let existing = UserDefaults.standard.object(forKey: key)
            log.info("\(key, privacy: .public) = \(String(describing: existing), privacy: .public)")
            if existing == nil { UserDefaults.standard.set(position, forKey: key) }
        }
    }

    /// nil until the status bar has placed the chevron: new items start outside every screen (below it,
    /// or past its right edge), with frames that say nothing about their order (docs/FINDINGS.md).
    private var separatorIsLeftOfChevron: Bool? {
        guard let s = separator.button?.window?.frame, let c = chevron.button?.window?.frame,
              NSScreen.screens.contains(where: { $0.frame.contains(c) })
        else { return nil }
        return s.midX < c.midX
    }

    /// Shows the current state. Never collapses unless the separator is known to be left of the chevron:
    /// 10_000pt would otherwise push the chevron itself off-screen. While the status bar relayouts, frames
    /// pass through wrong orders (e.g. the separator already 5016pt wide at its old origin), so a wrong
    /// order only counts if it is still there half a second later.
    private func apply(confirmed: Bool = false) {
        if !expanded {
            switch separatorIsLeftOfChevron {
            case nil:
                return log.info("collapse deferred: chevron not placed yet")
            case false? where !confirmed:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.apply(confirmed: true) }
                return
            case false?:
                log.error("separator is not left of the chevron; expanding")
                expanded = true
                showOrderHint()
            case true?:
                // Collapsed with a known order: the first time, give Apple's items their default place.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    Task { @MainActor in await self.pinSystemItemsOnce() }
                }
            }
        }
        separator.length = expanded ? NSStatusItem.variableLength : 10_000
        separator.button?.title = expanded ? "│" : ""
        chevron.button?.image = NSImage(systemSymbolName: expanded ? "chevron.right" : "chevron.left",
                                        accessibilityDescription: "Tray")
        let frames = "separator \(separator.button?.window?.frame ?? .zero), chevron \(chevron.button?.window?.frame ?? .zero)"
        log.info("expanded=\(self.expanded, privacy: .public) \(frames, privacy: .public)")
    }

    private func showOrderHint() {
        guard let button = chevron.button else { return }
        let label = NSTextField(wrappingLabelWithString:
            "The “│” separator must be left of the chevron.\nHold ⌘ and drag it to the left.")
        let height = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 260, height: 1_000)).height ?? 40
        label.frame = NSRect(x: 12, y: 12, width: 260, height: height)
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 284, height: height + 24))
        controller.view.addSubview(label)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = controller.view.frame.size
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // Left click: the panel, or back to collapsed when the tray is revealed. Right click: menu.
    @objc private func chevronClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            if expanded { return toggleArrange() }
            if panel.isOpen { return panel.close() }
            if let button = chevron.button { panel.open(below: button) }
            return
        }
        panel.close()
        chevron.menu = makeMenu()
        chevron.button?.performClick(nil)  // tracks the menu synchronously
        chevron.menu = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, checked: Bool = false, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.state = checked ? .on : .off
            menu.addItem(item)
        }
        add("Arrange Icons", #selector(toggleArrange), checked: expanded)
        add("Refresh", #selector(refresh))
        let intervals = NSMenu()
        for seconds in [0.5, 1, 2, 3] {
            let item = NSMenuItem(title: seconds == 0.5 ? "0.5 s" : "\(Int(seconds)) s", action: #selector(setRefreshInterval(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = refreshInterval == seconds ? .on : .off
            intervals.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervals
        menu.addItem(intervalItem)
        add("Launch at Login", #selector(toggleLaunchAtLogin), checked: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add("Quit Tray", #selector(NSApplication.terminate(_:)), key: "q")
        menu.items.last?.target = NSApp
        return menu
    }

    @objc private func setRefreshInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        UserDefaults.standard.set(seconds, forKey: "refreshInterval")  // used from the panel's next opening
    }

    @objc private func toggleArrange() {
        expanded.toggle()
        apply()
    }

    /// Re-applies the state and logs what discovery sees as the tray.
    @objc private func refresh() {
        apply()
        let tray = currentTrayItems()
        let names = tray.map { NSRunningApplication(processIdentifier: $0.pid)?.localizedName ?? "pid \($0.pid)" }
        log.info("tray: \(tray.count, privacy: .public) items: \(names.joined(separator: ", "), privacy: .public)")
    }

    /// The tray as discovery sees it now (SPEC §2), located through our own windows' CG frames.
    private func currentTrayItems() -> [StatusWindow] {
        let windows = statusWindows()
        func frame(of item: NSStatusItem) -> CGRect? { windows.first { $0.windowID == windowID(of: item) }?.frame }
        guard let c = frame(of: chevron), let s = frame(of: separator) else {
            log.error("own windows not found")
            return []
        }
        return axBacked(trayItems(in: windows, chevron: c, separator: s))
    }

    private func windowID(of item: NSStatusItem) -> CGWindowID {
        CGWindowID(clamping: item.button?.window?.windowNumber ?? 0)  // Int → UInt32 without trapping
    }

    /// Opens a tray item's own menu or popover under the tray (SPEC §5): move it next to the chevron, press
    /// it, wait until its menu closes, move it back left of its old right-hand neighbour (or of the
    /// separator). If it does not move, reveal the whole tray for the click instead.
    @MainActor
    private func forwardClick(to item: StatusWindow, button: CGMouseButton) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let tray = currentTrayItems()
        let index = tray.firstIndex { $0.windowID == item.windowID }
        let neighbour = index.flatMap { tray.indices.contains($0 + 1) ? tray[$0 + 1].windowID : nil }
        let baseline = menuWindows(of: item.pid)
        if await moveStatusItem(item, nextTo: windowID(of: chevron), side: .left) {
            await pressWhenOnScreen(item, button: button, baseline: baseline)
            _ = await moveStatusItem(item, nextTo: neighbour ?? windowID(of: separator), side: .left)
        } else {
            log.error("move failed; revealing the tray for the click")
            expanded = true
            apply()
            await pressWhenOnScreen(item, button: button, baseline: baseline)
            expanded = false
            apply()
        }
    }

    /// Waits (≤ 1 s) for the item to be on screen, clicks it and waits until the menu it opened has closed.
    /// A synthetic click, not SPEC's AXPress first: Telegram (Qt) ignores AXPress, and waiting 1.5 s for its
    /// menu before falling back made the item sit by the chevron for 3 s (docs/FINDINGS.md).
    @MainActor
    private func pressWhenOnScreen(_ item: StatusWindow, button: CGMouseButton, baseline: Set<CGWindowID>) async {
        var polls = 0
        while polls < 50, !(frame(of: item.windowID).map(isOnScreen) ?? false) {
            try? await Task.sleep(nanoseconds: 20_000_000)
            polls += 1
        }
        let current = StatusWindow(windowID: item.windowID, pid: item.pid, frame: frame(of: item.windowID) ?? item.frame,
                                   onScreen: true)
        await clickStatusItem(current, button: button)
        _ = await waitForMenuToClose(of: current, baseline: baseline)
    }

    /// Once per Mac (owner's change to SPEC §1, see docs/SPEC.md): Apple's own items start pinned right of the
    /// chevron, everything else in the tray. Afterwards the owner moves them freely. Needs Accessibility,
    /// as display copies (not AX-backed) cannot be moved; retried on later launches until all moved.
    @MainActor
    private func pinSystemItemsOnce() async {
        let key = "systemItemsPinned"
        guard !UserDefaults.standard.bool(forKey: key), !busy, !expanded, AXIsProcessTrusted() else { return }
        let system = currentTrayItems().filter {
            NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier?.hasPrefix("com.apple.") == true
        }
        busy = true
        defer { busy = false }
        var moved = 0
        for item in system.reversed() {  // each lands right of the chevron: rightmost first keeps the order
            if await moveStatusItem(item, nextTo: windowID(of: chevron), side: .right) { moved += 1 }
        }
        log.info("pinned \(moved, privacy: .public)/\(system.count, privacy: .public) system items")
        if moved == system.count { UserDefaults.standard.set(true, forKey: key) }
    }

    /// A panel cell dropped on another: move the item before or after it in the tray (the panel's order is the
    /// menu bar's order).
    @MainActor
    private func reorder(_ item: StatusWindow, nextTo target: StatusWindow, side: Side) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        _ = await moveStatusItem(item, nextTo: target.windowID, side: side)
    }

    /// A panel cell dropped on the menu bar: pin the item right of the chevron.
    @MainActor
    private func pin(_ item: StatusWindow) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        _ = await moveStatusItem(item, nextTo: windowID(of: chevron), side: .right)
    }

    /// Items the owner ⌘-dropped onto the chevron sit between separator and chevron: move them into the tray.
    @MainActor
    private func absorbDroppedItems() async {
        guard !busy, !expanded else { return }
        let windows = statusWindows()
        guard let c = windows.first(where: { $0.windowID == windowID(of: chevron) })?.frame,
              let s = windows.first(where: { $0.windowID == windowID(of: separator) })?.frame
        else { return }
        let dropped = axBacked(windows.filter {
            $0.pid != getpid() && abs($0.frame.minY - c.minY) < 1 && $0.frame.height == c.height
                && $0.frame.minX >= s.maxX - 1 && $0.frame.maxX <= c.minX + 1
        })
        guard !dropped.isEmpty else { return }
        busy = true
        defer { busy = false }
        for item in dropped {
            log.info("dropped on the chevron: \(item.windowID, privacy: .public) → tray")
            _ = await moveStatusItem(item, nextTo: windowID(of: separator), side: .left)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            log.error("launch at login: \(error.localizedDescription, privacy: .public)")
        }
        log.info("launch at login status: \(service.status.rawValue, privacy: .public)")
    }
}
