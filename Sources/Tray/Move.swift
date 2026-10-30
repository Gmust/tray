import AppKit
import ApplicationServices

/// A CFArray of raw window ids, as the CGWindowList "FromArray" functions take them (no CFNumbers).
func windowArray(_ ids: [CGWindowID]) -> CFArray? {
    var pointers = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
    return CFArrayCreate(kCFAllocatorDefault, &pointers, pointers.count, nil)
}

/// Current frame of one window (CG, top-left origin), or nil once it is gone.
func frame(of windowID: CGWindowID) -> CGRect? {
    guard let array = windowArray([windowID]),
          let info = (CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]])?.first,
          let bounds = info[kCGWindowBounds as String] as? NSDictionary
    else { return nil }
    return CGRect(dictionaryRepresentation: bounds)
}

/// Bounds of the active displays (CG, top-left origin).
func displayBounds() -> [CGRect] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &displays, &count)
    return displays.map(CGDisplayBounds)
}

/// True when `frame` (CG, top-left origin) lies inside one display.
func isOnScreen(_ frame: CGRect) -> Bool {
    displayBounds().contains { $0.contains(frame) }
}

enum Side { case left, right }

/// Moves a status item next to `target`, the way a ⌘-drag does (SPEC §5), ported from Ice
/// (`MenuBarItemManager.moveItemWithoutRestoringMouseLocation`): a ⌘ mouse-down far off-screen addressed
/// to the item's window lifts the item; a mouse-up at the target's edge addressed to the target's window
/// drops it. Each event goes through `deliver`. Addressing by window id is what moves off-screen items.
/// If a step does not change the item's frame, a mouse-up on the item cancels and the move is retried
/// (3 tries). The cursor is hidden and put back. Needs Accessibility.
@MainActor
func moveStatusItem(_ item: StatusWindow, nextTo target: CGWindowID, side: Side) async -> Bool {
    guard let start = frame(of: item.windowID), let targetFrame = frame(of: target),
          let source = CGEventSource(stateID: .hidSystemState)
    else { return false }
    permitLocalEvents()
    let end = CGPoint(x: side == .left ? targetFrame.minX : targetFrame.maxX, y: targetFrame.midY)
    let cursor = CGEvent(source: nil)?.location
    CGDisplayHideCursor(CGMainDisplayID())
    defer {
        if let cursor { CGWarpMouseCursorPosition(cursor) }
        CGDisplayShowCursor(CGMainDisplayID())
    }
    for attempt in 1...3 {
        guard let down = menuBarEvent(.leftMouseDown, at: CGPoint(x: 20_000, y: 20_000), window: item.windowID,
                                      pid: item.pid, source: source, command: true),
              let up = menuBarEvent(.leftMouseUp, at: end, window: target, pid: item.pid, source: source),
              let cancel = menuBarEvent(.leftMouseUp, at: CGPoint(x: start.midX, y: start.midY), window: item.windowID,
                                        pid: item.pid, source: source)
        else { return false }
        let before = frame(of: item.windowID) ?? start
        if await deliver(down, to: item.pid), await frameChanges(of: item.windowID, from: before) {
            let lifted = frame(of: item.windowID) ?? before
            if await deliver(up, to: item.pid), await frameChanges(of: item.windowID, from: lifted),
               let now = frame(of: item.windowID), now != start {
                log.info("moved \(item.windowID, privacy: .public) \(start.debugDescription, privacy: .public) → \(now.debugDescription, privacy: .public)")
                return true
            }
        }
        _ = await deliver(cancel, to: item.pid)
        log.error("move \(item.windowID, privacy: .public): try \(attempt, privacy: .public) failed")
    }
    return false
}

/// A synthetic click at the item's center, addressed to its window (SPEC §5 fallback for AXPress). Each
/// event is awaited at the session before the next, and the cursor is put back only after both: putting
/// it back earlier sent the click to wherever the cursor had been (Telegram never opened its menu).
@MainActor
func clickStatusItem(_ item: StatusWindow, button: CGMouseButton) async {
    guard let frame = frame(of: item.windowID), let source = CGEventSource(stateID: .hidSystemState) else { return }
    permitLocalEvents()
    let center = CGPoint(x: frame.midX, y: frame.midY)
    let (down, up): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
    let cursor = CGEvent(source: nil)?.location
    CGDisplayHideCursor(CGMainDisplayID())
    defer {
        if let cursor { CGWarpMouseCursorPosition(cursor) }
        CGDisplayShowCursor(CGMainDisplayID())
    }
    for type in [down, up] {
        guard let event = menuBarEvent(type, at: center, window: item.windowID, pid: item.pid, source: source, button: button)
        else { return }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        await postAndWait(event)
    }
}

/// Posts to the session and waits (≤ 50 ms) until a session tap has seen the event (Ice's
/// `postEventAndWaitToReceive`).
@MainActor
private func postAndWait(_ event: CGEvent) async {
    let tag = event.getIntegerValueField(.eventSourceUserData)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        var tap: EventTap?
        var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            tap = nil
            continuation.resume()
        }
        tap = EventTap(pid: nil, listenOnly: true, type: event.type) { seen in
            if seen.getIntegerValueField(.eventSourceUserData) == tag { finish() }
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { finish() }
        event.post(tap: .cgSessionEventTap)
        _ = tap  // kept alive until finish
    }
}

/// Undocumented window id field that Ice also sets on menu bar item events.
private let windowIDField = CGEventField(rawValue: 0x33)

/// A mouse event addressed to a status item window (Ice's `CGEvent.menuBarItemEvent`).
private func menuBarEvent(_ type: CGEventType, at location: CGPoint, window: CGWindowID, pid: pid_t,
                          source: CGEventSource, command: Bool = false, button: CGMouseButton = .left) -> CGEvent? {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button)
    else { return nil }
    event.flags = command ? .maskCommand : []
    event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
    event.setIntegerValueField(.eventSourceUserData, value: Int64(truncatingIfNeeded: Int(bitPattern: ObjectIdentifier(event))))
    event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
    event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
    if let windowIDField { event.setIntegerValueField(windowIDField, value: Int64(window)) }
    return event
}

/// The owner's own mouse and keyboard keep working while synthetic events are posted.
private func permitLocalEvents() {
    guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
    for state in [CGEventSuppressionState.eventSuppressionStateRemoteMouseDrag, .eventSuppressionStateSuppressionInterval] {
        source.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitLocalKeyboardEvents,
                                                           .permitSystemDefinedEvents], state: state)
    }
    source.localEventsSuppressionInterval = 0
}

/// Ice's delivery for menu bar item events (`scrombleEvent`): a null event is posted to the app, where a
/// tap swallows it and posts the real event to the session; once a session tap sees the real event, it
/// is posted to the app as well. False if the session tap did not see it within 50 ms.
@MainActor
private func deliver(_ event: CGEvent, to pid: pid_t) async -> Bool {
    guard let null = CGEvent(source: nil) else { return false }
    let nullTag = Int64(truncatingIfNeeded: Int(bitPattern: ObjectIdentifier(null)))
    null.setIntegerValueField(.eventSourceUserData, value: nullTag)
    let tag = event.getIntegerValueField(.eventSourceUserData)
    return await withCheckedContinuation { continuation in
        var appTap: EventTap?, sessionTap: EventTap?
        var finished = false
        func finish(_ delivered: Bool) {
            guard !finished else { return }
            finished = true
            appTap = nil
            sessionTap = nil
            continuation.resume(returning: delivered)
        }
        appTap = EventTap(pid: pid, listenOnly: false, type: null.type) { seen in
            guard seen.getIntegerValueField(.eventSourceUserData) == nullTag else { return false }
            event.post(tap: .cgSessionEventTap)
            return true
        }
        sessionTap = EventTap(pid: nil, listenOnly: true, type: event.type) { seen in
            guard seen.getIntegerValueField(.eventSourceUserData) == tag else { return false }
            event.postToPid(pid)
            finish(true)
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { finish(false) }
        null.postToPid(pid)
        _ = (appTap, sessionTap)  // kept alive until finish
    }
}

/// Polls (≤ 100 ms) until the window's frame differs from `initial`.
@MainActor
private func frameChanges(of windowID: CGWindowID, from initial: CGRect) async -> Bool {
    for _ in 0..<20 {
        if let now = frame(of: windowID), now != initial { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return false
}

/// A CGEventTap on the main run loop, session-wide (`pid` nil) or on one app. `handler` returns true to
/// swallow the event. Removed when released.
private final class EventTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate let handler: (CGEvent) -> Bool

    init(pid: pid_t?, listenOnly: Bool, type: CGEventType, handler: @escaping (CGEvent) -> Bool) {
        self.handler = handler
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handler(event) ? nil : Unmanaged.passUnretained(event)
        }
        let mask = CGEventMask(1) << type.rawValue
        let options: CGEventTapOptions = listenOnly ? .listenOnly : .defaultTap
        let me = Unmanaged.passUnretained(self).toOpaque()
        if let pid {
            port = CGEvent.tapCreateForPid(pid: pid, place: .tailAppendEventTap, options: options,
                                           eventsOfInterest: mask, callback: callback, userInfo: me)
        } else {
            port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: options,
                                     eventsOfInterest: mask, callback: callback, userInfo: me)
        }
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            log.error("event tap not created (Accessibility?)")
            return
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
    }
}

/// Visible windows of `pid` that can be what its status item opened: menus and popovers. Not status windows
/// (layer 25); normal-layer windows only when they hang from the menu bar (top edge ≤ 60 pt below a
/// display's top), as some popovers do (Stats' was missed otherwise). A closed menu may stay "on screen"
/// fully transparent, so alpha 0 does not count.
func menuWindows(of pid: pid_t) -> Set<CGWindowID> {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let displays = displayBounds()
    return Set(list.compactMap { info in
        guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
              let layer = info[kCGWindowLayer as String] as? Int, layer != 25,
              info[kCGWindowAlpha as String] as? Double ?? 1 > 0,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds)
        else { return nil }
        let top = CGPoint(x: frame.midX, y: frame.minY)
        guard layer != 0 || displays.contains(where: { $0.contains(top) && frame.minY - $0.minY <= 60 }) else { return nil }
        return info[kCGWindowNumber as String] as? CGWindowID
    })
}

/// Waits until the menu or popover `item`'s app opened (beyond `baseline`) has closed: none for two polls
/// in a row. Returns false when nothing opened within 1.5 s (SPEC §5), or after 60 s regardless.
@MainActor
func waitForMenuToClose(of item: StatusWindow, baseline: Set<CGWindowID>) async -> Bool {
    var opened = false, emptyPolls = 0, waited: TimeInterval = 0
    while waited < 60 {
        try? await Task.sleep(nanoseconds: 250_000_000)
        waited += 0.25
        if menuWindows(of: item.pid).subtracting(baseline).isEmpty {
            emptyPolls += 1
            if !opened && waited >= 1.5 {
                log.info("menu of \(item.windowID, privacy: .public): nothing opened")
                return false
            }
            if opened && emptyPolls >= 2 {
                log.info("menu of \(item.windowID, privacy: .public): closed after \(waited, privacy: .public) s")
                return true
            }
        } else {
            if !opened { log.info("menu of \(item.windowID, privacy: .public): opened") }
            opened = true
            emptyPolls = 0
        }
    }
    log.error("menu of \(item.windowID, privacy: .public): still open after 60 s")
    return false
}

/// `--move <windowID> <right|tray>`: moves one item right of the running Tray's chevron (pinned) or into the
/// tray (left of the separator), to test moving in isolation. Needs Accessibility for the posting process.
@MainActor
func moveCommand(windowID: CGWindowID, to destination: String) async -> Int32 {
    let windows = statusWindows()
    guard let item = windows.first(where: { $0.windowID == windowID }) else {
        FileHandle.standardError.write(Data("no status window \(windowID)\n".utf8))
        return 1
    }
    guard let layout = runningTrayLayout(in: windows) else {
        FileHandle.standardError.write(Data("Tray is not running\n".utf8))
        return 1
    }
    let moved: Bool
    switch destination {
    case "right": moved = await moveStatusItem(item, nextTo: layout.chevron.windowID, side: .right)
    case "tray": moved = await moveStatusItem(item, nextTo: layout.separator.windowID, side: .left)
    default:
        FileHandle.standardError.write(Data("destination must be right or tray\n".utf8))
        return 64
    }
    print("\(windowID): \(item.frame.debugDescription) → \(frame(of: windowID)?.debugDescription ?? "gone") moved=\(moved)")
    return moved ? 0 : 1
}
