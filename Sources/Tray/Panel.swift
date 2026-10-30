import AppKit
import SwiftUI

/// SPEC §4 setting: `defaults write dev.illia.tray panelMaxWidth <points>` (200–800, default 360).
private var maxPanelWidth: CGFloat {
    let width = UserDefaults.standard.double(forKey: "panelMaxWidth")
    return width > 0 ? min(max(width, 200), 800) : 360
}

/// SPEC §3 setting, chosen in the chevron menu (0.5–3 s, default 1 s).
var refreshInterval: TimeInterval {
    let interval = UserDefaults.standard.double(forKey: "refreshInterval")
    return interval > 0 ? min(max(interval, 0.5), 3) : 1
}

/// Origins for items of `sizes`, left to right, wrapping before `maxWidth`, plus the total size.
/// An item wider than `maxWidth` gets a row of its own.
func flow(_ sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> (origins: [CGPoint], size: CGSize) {
    var origins: [CGPoint] = []
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
    for size in sizes {
        if x > 0 && x + size.width > maxWidth {
            x = 0
            y += rowHeight + spacing
            rowHeight = 0
        }
        origins.append(CGPoint(x: x, y: y))
        x += size.width + spacing
        width = max(width, x - spacing)
        rowHeight = max(rowHeight, size.height)
    }
    return (origins, CGSize(width: width, height: y + rowHeight))
}

/// Wrapping flow (SPEC §4): each cell keeps its own width, so square icons line up like a grid and wide
/// items (Stats sensors) take their real width. Wraps at `maxWidth` whatever the proposal.
struct FlowLayout: Layout {
    let maxWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        flow(subviews.map { $0.sizeThatFits(.unspecified) }, maxWidth: maxWidth, spacing: spacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = flow(subviews.map { $0.sizeThatFits(.unspecified) }, maxWidth: maxWidth, spacing: spacing).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }
}

struct PanelCell: Identifiable {
    let id: CGWindowID
    let name: String
    let image: NSImage
}

struct PanelView: View {
    let cells: [PanelCell]
    let needsScreenRecording: Bool
    let onClick: (CGWindowID, CGMouseButton) -> Void
    /// A cell dropped: on another cell (`target`, before or after it) or elsewhere (nil).
    let onDragEnd: (CGWindowID, (id: CGWindowID, side: Side)?) -> Void
    @State private var cellFrames: [CGWindowID: CGRect] = [:]
    /// The cell being dragged, how far, and where the cursor is (grid coordinates).
    @State private var drag: (id: CGWindowID, offset: CGSize, location: CGPoint)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if needsScreenRecording {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To show items live, Tray needs Screen Recording access.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings", action: openScreenRecordingSettings)
                }
                .frame(width: 260, alignment: .leading)
            }
            if cells.isEmpty {
                Text("The tray is empty").foregroundStyle(.secondary)
            }
            FlowLayout(maxWidth: maxPanelWidth - 16, spacing: 4) {
                ForEach(cells) { cell in
                    let dragged = drag?.id == cell.id
                    CellView(cell: cell, dragged: dragged, insertion: insertion(at: cell.id),
                             action: { onClick(cell.id, $0) },
                             dragChanged: { drag = (cell.id, $0, $1) },
                             dragEnded: { location in
                                 drag = nil
                                 onDragEnd(cell.id, dropTarget(at: location, excluding: cell.id))
                             })
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: CellFrames.self, value: [cell.id: geometry.frame(in: .named("grid"))])
                        })
                        .offset(dragged ? drag?.offset ?? .zero : .zero)
                        .zIndex(dragged ? 1 : 0)
                }
            }
            .coordinateSpace(name: "grid")
            .onPreferenceChange(CellFrames.self) { cellFrames = $0 }
        }
        .padding(8)
    }

    /// Where the insertion marker goes on this cell while another cell is dragged over it.
    private func insertion(at id: CGWindowID) -> Side? {
        guard let drag, let target = dropTarget(at: drag.location, excluding: drag.id), target.id == id else { return nil }
        return target.side
    }

    /// The cell under `point` (grid coordinates) other than the dragged one, and which half it was dropped on.
    private func dropTarget(at point: CGPoint, excluding id: CGWindowID) -> (id: CGWindowID, side: Side)? {
        cellFrames.first { $0.key != id && $0.value.contains(point) }
            .map { ($0.key, point.x < $0.value.midX ? Side.left : .right) }
    }
}

private struct CellFrames: PreferenceKey {
    static let defaultValue: [CGWindowID: CGRect] = [:]
    static func reduce(value: inout [CGWindowID: CGRect], nextValue: () -> [CGWindowID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct CellView: View {
    let cell: PanelCell
    let dragged: Bool
    /// Side of this cell where a dragged cell would be inserted, if it is dropped now.
    let insertion: Side?
    let action: (CGMouseButton) -> Void
    let dragChanged: (CGSize, CGPoint) -> Void
    let dragEnded: (CGPoint) -> Void
    @State private var hovering = false

    var body: some View {
        Image(nsImage: cell.image)
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(hovering || dragged ? 0.15 : 0)))
            .overlay(alignment: insertion == .right ? .trailing : .leading) {
                if let insertion {
                    Capsule().fill(Color.accentColor).frame(width: 3).offset(x: insertion == .left ? -3.5 : 3.5)
                }
            }
            .scaleEffect(dragged ? 1.1 : 1)
            .shadow(radius: dragged ? 6 : 0)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { action(.left) }
            .overlay(RightClickCatcher { action(.right) })
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("grid"))
                .onChanged { dragChanged($0.translation, $0.location) }
                .onEnded { dragEnded($0.location) })
            .help(cell.name)
    }
}

/// Catches right clicks only; every other event passes through to the SwiftUI cell beneath (SwiftUI on macOS
/// has no right-click gesture).
private struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView(action: action) }
    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { action() }
    }
}

/// True when `point` (AppKit screen coordinates) is in a menu bar: above its screen's visible frame.
private func isInMenuBar(_ point: NSPoint) -> Bool {
    NSScreen.screens.contains { $0.frame.contains(point) && point.y >= $0.visibleFrame.maxY }
}

private func openScreenRecordingSettings() {
    CGRequestScreenCaptureAccess()  // lists Tray in System Settings → Screen Recording
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
    }
}

/// Borderless panels refuse key status by default; key status is what delivers Esc to us.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The floating tray panel (SPEC §4) under the chevron. While open, it rediscovers the tray items and
/// recaptures their images every `refreshInterval`; the last image per window is kept, so it opens instantly.
final class Panel {
    private let window = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: true)
    private let hosting = NSHostingView(rootView: PanelView(cells: [], needsScreenRecording: false,
                                                            onClick: { _, _ in }, onDragEnd: { _, _ in }))
    private let discover: () -> [StatusWindow]
    private let onClick: (StatusWindow, CGMouseButton) -> Void
    private let onDropOnMenuBar: (StatusWindow) -> Void
    private let onReorder: (StatusWindow, StatusWindow, Side) -> Void
    private var anchor: NSStatusBarButton?
    private var items: [StatusWindow] = []
    /// After a reorder, the panel keeps its own order for a moment instead of rediscovering, so the dropped
    /// cell does not flicker while the real item is still being moved.
    private var keepOrderUntil = Date.distantPast
    private var images: [CGWindowID: NSImage] = [:]
    private var capturing = false
    /// Until a capture has returned real pixels, only the first item is captured; after a refresh that
    /// returns none (e.g. while macOS waits for the owner to allow screen capture), nothing is captured
    /// until the next opening. At most one consent alert per opening (docs/FINDINGS.md).
    private var captureWorked = false
    private var captureFailed = false
    private var timer: Timer?
    private var monitors: [Any] = []

    var isOpen: Bool { window.isVisible }

    init(discover: @escaping () -> [StatusWindow], onClick: @escaping (StatusWindow, CGMouseButton) -> Void,
         onDropOnMenuBar: @escaping (StatusWindow) -> Void, onReorder: @escaping (StatusWindow, StatusWindow, Side) -> Void) {
        self.discover = discover
        self.onClick = onClick
        self.onDropOnMenuBar = onDropOnMenuBar
        self.onReorder = onReorder
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        // A layer corner radius leaves square corners on NSVisualEffectView; a stretchable mask does not.
        let mask = NSImage(size: NSSize(width: 21, height: 21), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        mask.resizingMode = .stretch
        effect.maskImage = mask
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        window.contentView = effect
    }

    func open(below button: NSStatusBarButton) {
        anchor = button
        captureFailed = false
        // Captured glyphs are drawn for the menu bar's appearance; match it so they stay readable.
        window.appearance = button.effectiveAppearance
        refresh()
        window.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in self?.refresh() }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                // Tray's own synthetic events (reordering) carry user data; the owner's clicks do not.
                guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) == 0 else { return }
                self?.close()
            },
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }  // Esc
                self?.close()
                return nil
            },
        ].compactMap { $0 }
        log.info("panel opened: \(self.items.count, privacy: .public) items")
    }

    func close() {
        timer?.invalidate()
        timer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        window.orderOut(nil)
    }

    private func refresh() {
        if Date() >= keepOrderUntil { items = discover() }
        render()
        guard CGPreflightScreenCaptureAccess(), !capturing, !captureFailed, !items.isEmpty else { return }
        capturing = true
        let items = captureWorked ? self.items : Array(self.items.prefix(1))
        DispatchQueue.global(qos: .userInitiated).async {
            let captured = captureImages(of: items).filter { !isBlank($0.value) }
            DispatchQueue.main.async {
                for item in items {
                    if let image = captured[item.windowID] {
                        self.images[item.windowID] = NSImage(cgImage: image, size: item.frame.size)
                    }
                }
                self.captureWorked = !captured.isEmpty
                if captured.isEmpty {
                    self.captureFailed = true
                    log.error("capture returned no pixels for \(items.count, privacy: .public) items; retry on next opening")
                }
                self.capturing = false
                if self.isOpen { self.render() }
            }
        }
    }

    private func render() {
        let cells = items.map { item in
            PanelCell(id: item.windowID,
                      name: NSRunningApplication(processIdentifier: item.pid)?.localizedName ?? "",
                      image: images[item.windowID] ?? appIcon(for: item))
        }
        hosting.rootView = PanelView(
            cells: cells, needsScreenRecording: !CGPreflightScreenCaptureAccess(),
            onClick: { [weak self] id, button in
                guard let self, let item = self.items.first(where: { $0.windowID == id }) else { return }
                self.close()
                self.onClick(item, button)
            },
            onDragEnd: { [weak self] id, target in
                guard let self, let item = self.items.first(where: { $0.windowID == id }) else { return }
                if let target, let other = self.items.first(where: { $0.windowID == target.id }) {
                    // Show the new order at once; the panel stays open while the real item moves.
                    self.items.removeAll { $0.windowID == id }
                    let index = self.items.firstIndex { $0.windowID == target.id } ?? self.items.endIndex
                    self.items.insert(item, at: target.side == .left ? index : min(index + 1, self.items.endIndex))
                    self.keepOrderUntil = Date().addingTimeInterval(1.5)
                    self.render()
                    self.onReorder(item, other, target.side)
                } else if isInMenuBar(NSEvent.mouseLocation) {
                    self.close()
                    self.onDropOnMenuBar(item)
                }
            })
        guard let anchorWindow = anchor?.window, let screen = anchorWindow.screen ?? NSScreen.main else { return }
        let size = hosting.fittingSize
        let x = min(max(anchorWindow.frame.midX - size.width / 2, screen.frame.minX + 4), screen.frame.maxX - size.width - 4)
        window.setFrame(NSRect(x: x, y: anchorWindow.frame.minY - size.height - 4, width: size.width, height: size.height),
                        display: true)
        window.invalidateShadow()  // the shadow follows the rounded mask only once recomputed
    }

    /// Without Screen Recording: the owning app's icon, centered in the item's real size.
    private func appIcon(for item: StatusWindow) -> NSImage {
        let icon = NSRunningApplication(processIdentifier: item.pid)?.icon ?? NSImage()
        return NSImage(size: item.frame.size, flipped: false) { rect in
            let side = min(rect.width, rect.height) * 0.6
            icon.draw(in: NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
            return true
        }
    }
}
