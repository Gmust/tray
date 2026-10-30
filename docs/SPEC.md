# Tray — product spec

Source: the owner's brief (2026-10-30), kept verbatim below. Design §1–7 is decided:
ask before redesigning. Only the last section, "Delivery plan", is an agent proposal.

# Goal
Build "Tray": a native macOS menu bar utility that works like the Windows system tray overflow.
- One chevron button in the menu bar. By default EVERY status item lives in the tray (pushed off-screen),
  except items the user pins to the right of the chevron (and the clock / Control Center, which macOS keeps fixed).
- Clicking the chevron opens a floating panel under it showing all tray items as a wrapping grid,
  rendered LIVE exactly as they look in the menu bar — including dynamic items like Stats / iStat Menus
  (CPU temp, network speed, battery, graphs).
- Clicking an item in the panel opens that item's real menu/popover right under the tray, like on Windows.

# Target
- macOS 14 Sonoma and 15 Sequoia, Apple Silicon. My machine: MacBook Air with a notch, macOS 15.
- Not sandboxed, not for the App Store (Accessibility + synthetic events don't work in the sandbox).

# Stack
- Swift, SwiftPM (swift-tools-version 5.10, Swift 5 language mode), no .xcodeproj, no third-party deps.
- scripts/build.sh bundles the executable into Tray.app. Info.plist: LSUIElement=true, bundle id dev.illia.tray.
- AppKit: NSStatusItem, NSPanel, NSEvent monitors. SwiftUI only for panel content and onboarding.
- CoreGraphics (CGWindowListCopyWindowInfo, CGEvent), AX (AXUIElement, AXExtrasMenuBar, AXPress),
  ScreenCaptureKit (SCScreenshotManager), ServiceManagement (SMAppService).

# Design (decided; ask before redesigning)
1. Hiding: two status items of our own.
   - `chevron` — always visible.
   - `separator` — directly left of the chevron. Collapsed: length 10_000, pushing every status item to its left
     off-screen. Arrange mode: thin visible "│".
   - Tray = left of the separator. Pinned = right of the chevron. The user can also rearrange with native ⌘-drag.
     Persist with `autosaveName`.
   - First launch: place chevron + separator at the far right of the status area so everything starts in the tray.
     Try seeding the "NSStatusItem Preferred Position <autosaveName>" user-defaults keys before creating the items
     (Ice does this); verify the actual semantics on my machine and report.
   - Safety: never collapse if the separator is not left of the chevron. Expand and show a hint instead.

2. Discovery: CGWindowListCopyWindowInfo(.optionAll), layer == kCGStatusWindowLevel (25), exclude our pid.
   Tray items = windows with maxX <= separator window minX, in menu bar order.
   Apple items (Wi-Fi, battery, Bluetooth…) are owned by ControlCenter on 14/15 — include them.
   CG/AX use top-left-origin global coords; NSScreen/NSWindow use bottom-left. Convert carefully.

3. Live images (core feature, not optional):
   - Capture each tray item window with ScreenCaptureKit
     (SCContentFilter(desktopIndependentWindow:) + SCScreenshotManager.captureImage) at its real size, @2x.
   - While the panel is open, refresh all visible items every 1 s (setting: 0.5–3 s). Stop when the panel closes.
   - Cache the last image per windowID so the panel opens instantly.
   - Verify that dynamic items (Stats) keep updating while off-screen. If they don't, report and propose a fix.
   - Screen Recording is required. Without it: fallback to app icons + a banner in the panel asking for permission.

4. Panel layout: NOT a uniform square grid.
   - Custom SwiftUI `Layout` = wrapping flow. Fixed row height (menu bar height + padding),
     each cell as wide as the item's own image, 4pt spacing, max panel width ~360pt (setting).
     Square icons naturally align into a grid; wide items (Stats sensors/network) take their real width.
   - Hover highlight, tooltip = app name.
   - NSPanel [.borderless, .nonactivatingPanel], level .popUpMenu, all spaces + full-screen auxiliary,
     NSVisualEffectView (.popover), 10pt corner radius, centered under the chevron, clamped to the screen.
   - Panel appearance = the chevron button's effectiveAppearance, so captured white/black glyphs stay readable.
   - Closes on outside click (global mouse monitor), Esc, chevron click, and after an item is clicked.

5. Click forwarding:
   - Primary = temporary move (Ice's "temp show"): close panel → move the clicked item right next to the chevron
     with synthetic ⌘-drag CGEvents targeted at its window → wait until it is on-screen → AXPress
     (fallback: synthetic click) → when its menu/popover closes, move it back to its original position.
   - Fallback = temporary reveal, used only if the move fails or times out: expand separator → click → re-collapse.
   - AX lookup: AXUIElementCreateApplication(pid) → AXExtrasMenuBar → children → match by frame.
   - "Menu closed" detection: poll on-screen windows of that pid with layer not in {0, 25}; none for 2 consecutive
     polls → done. Nothing opened within 1.5 s → done.
   - Right-click on a cell → same flow with a right click.
   - Context menu on a cell: «Закрепить в строке меню» / «Убрать в трей» — uses the same move mechanism
     (this also fixes items stuck under the notch that can't be ⌘-dragged by hand).

6. Chevron right-click menu (Russian UI): «Расставить иконки» (toggle arrange mode), «Обновить»,
   «Запускать при входе» (SMAppService), «Выйти».

7. Onboarding on first launch: Accessibility and Screen Recording, both required, each with live status and an
   "Open System Settings" button (AXIsProcessTrustedWithOptions, CGPreflightScreenCaptureAccess /
   CGRequestScreenCaptureAccess).

# Debuggability (you can't see my screen)
- `Tray.app/Contents/MacOS/Tray --dump` prints JSON: every status item window (pid, app, windowID, frame, inTray)
  plus the matched AX element (title/description, match ok?).
- `--capture <dir>` saves current PNGs of all tray items so I can check them.
- `--move <windowID> <right|tray>` moves an item from the terminal, to test the move mechanism in isolation.
- os.Logger with subsystem = bundle id; give me the exact `log stream` command.

# Build & signing
- scripts/build.sh: `swift build -c release` → assemble Tray.app → codesign → print the path.
- macOS ties Accessibility/Screen Recording grants to the code signature; ad-hoc signing changes every build and
  silently revokes them. Sign with my "Apple Development" identity (`security find-identity -v -p codesigning`);
  fall back to ad-hoc only with a loud warning.

# Delivery plan (agent proposal, not a decision)
Each phase ends with evidence from the Mac (`--dump` / `--capture` / `log stream` / owner confirmation).
1. SwiftPM package, `scripts/build.sh` with signing, `--dump` (status windows + AX match).
2. Hiding (§1) + chevron menu (§6) + os.Logger; `--dump` gains separator and `inTray`.
   Verify the Preferred Position seeding semantics.
3. Onboarding (§7), live capture (§3) + `--capture`; verify Stats keeps updating off-screen.
4. Panel (§4).
5. Click forwarding (§5) + `--move` + pin/unpin context menu.
