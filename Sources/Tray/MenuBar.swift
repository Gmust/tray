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

        // Re-check whenever our items move: a deferred collapse can proceed once they are placed, and
        // ⌘-dragging the separator right of the chevron while collapsed must expand at once.
        for window in [chevron.button?.window, separator.button?.window].compactMap({ $0 }) {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { [weak self] _ in
                guard let self, !self.expanded else { return }
                self.apply()
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
                break
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
            "Разделитель «│» должен стоять слева от шеврона.\nПеретащите его левее, удерживая ⌘.")
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

    // Left click toggles the tray until the panel exists (SPEC delivery plan, phase 4). Right click: menu.
    @objc private func chevronClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else { return toggleArrange() }
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
        add("Расставить иконки", #selector(toggleArrange), checked: expanded)
        add("Обновить", #selector(refresh))
        add("Запускать при входе", #selector(toggleLaunchAtLogin), checked: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add("Выйти", #selector(NSApplication.terminate(_:)), key: "q")
        menu.items.last?.target = NSApp
        return menu
    }

    @objc private func toggleArrange() {
        expanded.toggle()
        apply()
    }

    /// Re-applies the state and logs what discovery sees as the tray.
    @objc private func refresh() {
        apply()
        let windows = statusWindows()
        func own(_ item: NSStatusItem) -> CGRect? {
            windows.first { $0.windowID == CGWindowID(item.button?.window?.windowNumber ?? 0) }?.frame
        }
        guard let c = own(chevron), let s = own(separator) else { return log.error("own windows not found") }
        let tray = trayItems(in: windows, chevron: c, separator: s)
        let names = tray.map { NSRunningApplication(processIdentifier: $0.pid)?.localizedName ?? "pid \($0.pid)" }
        log.info("tray: \(tray.count, privacy: .public) items: \(names.joined(separator: ", "), privacy: .public)")
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
