import AppKit
import SwiftUI

private let maxPanelWidth: CGFloat = 360
private let refreshInterval: TimeInterval = 1

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
    let onClick: (CGWindowID) -> Void
    let onDragEnd: (CGWindowID) -> Void

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
                    CellView(cell: cell, action: { onClick(cell.id) }, dragEnded: { onDragEnd(cell.id) })
                }
            }
        }
        .padding(8)
    }
}

private struct CellView: View {
    let cell: PanelCell
    let action: () -> Void
    let dragEnded: () -> Void
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        Image(nsImage: cell.image)
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(hovering ? 0.15 : 0)))
            .opacity(dragging ? 0.4 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .gesture(DragGesture(minimumDistance: 6)
                .onChanged { _ in dragging = true }
                .onEnded { _ in
                    dragging = false
                    dragEnded()
                })
            .help(cell.name)
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
                                                            onClick: { _ in }, onDragEnd: { _ in }))
    private let discover: () -> [StatusWindow]
    private let onClick: (StatusWindow) -> Void
    private let onDropOnMenuBar: (StatusWindow) -> Void
    private var anchor: NSStatusBarButton?
    private var items: [StatusWindow] = []
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

    init(discover: @escaping () -> [StatusWindow], onClick: @escaping (StatusWindow) -> Void,
         onDropOnMenuBar: @escaping (StatusWindow) -> Void) {
        self.discover = discover
        self.onClick = onClick
        self.onDropOnMenuBar = onDropOnMenuBar
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
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
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
        items = discover()
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
            onClick: { [weak self] id in
                guard let self, let item = self.items.first(where: { $0.windowID == id }) else { return }
                self.close()
                self.onClick(item)
            },
            onDragEnd: { [weak self] id in
                guard let self, let item = self.items.first(where: { $0.windowID == id }),
                      isInMenuBar(NSEvent.mouseLocation)
                else { return }
                self.close()
                self.onDropOnMenuBar(item)
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
