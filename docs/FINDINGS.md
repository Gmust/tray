# Findings on the owner's Mac

Verified platform behavior that the design depends on. Each entry: what, evidence, date.
Machine: MacBook Air (notch), macOS 15.7.9, arm64, plus one external 4K display.

## Verified
- **Displays.** Built-in display: 1470pt wide, menu bar 36pt (notch), at y=0. External display: at x=1470,
  y=-62, menu bar 24pt. Evidence: `--dump` frames, 2026-10-30.
- **One window per display.** Every status item has one layer-25 window per display menu bar. Discovery
  must pick the copy on the target display by menu bar row (y and height), not by layer alone.
  Evidence: `--dump`, 2026-10-30.
- **Window IDs move between displays.** The same windowID (e.g. Claude's) sat on the external menu bar in
  one dump and on the built-in one in the next. A windowID does not identify a display; re-discover on
  every panel open. Evidence: three `--dump` runs, 2026-10-30.
- **Ghost windows.** Off-screen layer-25 windows at (0,0), and sometimes copies with the other display's
  menu bar height (e.g. 48×36 at y=-62), belong to no visible item. Their number varies (66 → 45 windows
  between runs). Evidence: `--dump`, 2026-10-30.
- **Non-status windows at layer 25.** NotchNook overlays (1470×250, 1920×250) and Maccy's popup (450×800)
  share the status layer. Evidence: `--dump`, 2026-10-30.
- **Notch.** Stats items on the built-in display sit under the notch (x 601–862) and report
  `onScreen: false`. Evidence: `--dump`, 2026-10-30.
- **AX frames share the window's center, not its size.** `AXExtrasMenuBar` children are 22–24pt tall,
  vertically centered in the 36pt bar; Stats elements are 7pt narrower per side, most others 1pt wider.
  Centers agree within 0.25pt. Matching by center matched 19/19 items on the built-in menu bar,
  including the ControlCenter items. Evidence: `--dump` + `DiscoveryTests.testMatchIndex`, 2026-10-30.
- **AX reports one copy per item.** At test time it reported the built-in display's copies; the external
  display's copies had no AX element. Evidence: `--dump`, 2026-10-30.
- **AX labels.** Apple items carry a description and an identifier (`com.apple.menuextra.clock`, `.wifi`,
  `.battery`, …). Most third-party items have an empty title and no description, so app names come
  from `NSRunningApplication`. Evidence: `--dump`, 2026-10-30.
- **TCC attribution.** Running `Tray.app/Contents/MacOS/Tray` from Claude Code's shell checks Claude
  Code's grants (tccd: responsible = `com.anthropic.claude-code`, identified by its versioned binary
  path). `open -n -W --stdout <file> build/Tray.app --args --dump` checks Tray.app's own grants. The
  owner's Accessibility grant landed on Claude Code; Tray.app is still denied. Evidence: tccd log +
  `accessibility` field, 2026-10-30.
- **"NSStatusItem Preferred Position <autosaveName>" = distance in points from the screen's right edge to
  the item's right edge (maxX)**, stored in the owning app's defaults domain. Six ControlCenter /
  Spotlight / TextInputMenuAgent values matched the external-display window positions exactly (Spotlight:
  3390 − 3225 = 165). The clock has no key (fixed); Control Center's value (131) equals the clock's width.
  Values update only when an item moves: Maccy's (426) was stale. Evidence: `defaults read` vs `--dump`,
  2026-10-30. Seeding 0 (chevron) / 1 (separator) before creating the items works: on first launch they
  landed rightmost, directly left of Control Center, separator left of chevron, on both displays.
  AppKit leaves the seeded values as they are until the user drags an item. Evidence: `--dump` + `defaults
  read dev.illia.tray`, 2026-10-30.
- **New status item windows start unplaced.** For ~100 ms after creation our windows sit outside every
  screen (below it at y=-36, or past its right edge at x=3390), sometimes already resized. During
  relayout, frames pass through wrong orders (separator 5016pt wide at its old origin). Never act on a
  single reading: wait until the chevron is inside a screen, and re-check a wrong order after 0.5 s.
  Evidence: launch logs (two false "wrong order" expansions before the fix), 2026-10-30.
- **Length 10_000 is clamped to 5016pt.** Still enough: collapsed, every tray item sat 2–4.5k pt off-screen
  on both displays (e.g. x −2535…−1861 on the external one). Evidence: `--dump`, 2026-10-30.
- **Duplicate windows: capture the copy, not the original.** When the built-in display has the active
  menu bar, each item has two windows there with identical frames: the app's original (low windowID,
  follows the active menu bar) over the display's own copy (newer windowID). A capture of the original
  never gets a frame: replayd starts the SkyLight stream and reports "complete", then nothing, and no
  consent alert is raised (0x1300a, Stats, at 14:42 and 15:15). Requests for the copies reached the
  consent stage. With the external display active, its row holds only originals, and those captured
  fine. `trayItems` keeps the higher windowID. Evidence: replayd log + Tray "still pending" log, 2026-10-30.
- **Quitting restores the menu bar.** After `pkill -x Tray`, all 19 items were back at their exact
  pre-launch x positions. Evidence: `--dump` before launch vs after quit, 2026-10-30.
- **Rebuilding over a running Tray.** `scripts/build.sh` now copies then renames, so the running process
  keeps its inode; Tray survived a rebuild while running. Evidence: same pid before/after, 2026-10-30.
- **ScreenCaptureKit captures off-screen status items.** `SCContentFilter(desktopIndependentWindow:)` +
  `SCScreenshotManager.captureImage` rendered all 17 tray items while they sat thousands of points
  off-screen, including Stats' live values (CPU, RAM, sensor, network), ControlCenter items and the input
  source. Evidence: owner's screenshot of the panel, 2026-10-30. Whether Stats keeps redrawing between
  captures while off-screen is not yet confirmed.
- **"Quit & Reopen" after a Screen Recording grant quit Tray without reopening it** (LSUIElement app
  launched via `open`). Relaunch it by hand. Evidence: owner report, 2026-10-30.
- **macOS 15 "bypass the system private window picker" alert.** Until the owner presses "Allow", every
  `SCScreenshotManager.captureImage` request for a *window* raises its own alert (UserNotificationCenter,
  layer 8) and blocks without returning or throwing; a *display* capture raised none. 17 parallel window
  requests stacked 17 alerts. Alerts outlive Tray; killing UserNotificationCenter makes replayd re-post
  every pending request (15 → 31 alerts). What clears them is answering each one. Fix: until one window
  capture returns an image, one request per panel opening (`Sources/Tray/Capture.swift`). Evidence: replayd + Tray logs, alert window counts, owner
  screenshots, 2026-10-30. Not yet observed: behavior after "Allow", and how long it lasts.
- **Signing.** Apple Development signing gives a certificate-based designated requirement
  (`identifier "dev.illia.tray" and anchor apple generic and certificate leaf[subject.CN] = …`), so
  grants should survive rebuilds. Evidence: `codesign -d -r-`, 2026-10-30. Survival across a rebuild
  is not yet observed.

- **Capture backend switched to CoreGraphics.** Ice (jordanbaird/Ice, `Ice/Utilities/ScreenCapture.swift`)
  captures hidden items with `CGImage(windowListFromArrayScreenBounds:windowArray:imageOption:)`, with the
  comment "ScreenCaptureKit doesn't support capturing composite images of offscreen menu bar items". Tray
  now does the same, one window per call. On the owner's Mac (built-in display active, items ~4.4k pt
  off-screen) all 17 items came back live, with no consent alert. Panel still captures one item until
  real pixels come back. Evidence: Ice source + owner screenshot, 2026-10-30.
- **Stats keeps redrawing while off-screen.** Across the owner's panel screenshots the off-screen Stats
  items changed: CPU 33% → 38% → 28%, sensor 66° → 50°, network rates. Evidence: owner screenshots,
  2026-10-30.

- **Moving items with synthetic ⌘-drags works with Ice's delivery.** `--move 55 right` took Spotlight
  from x −1861 (off-screen, tray) to right of the chevron, `--move 55 tray` put it back. Simpler event
  sequences (no event taps, mouse-down on the item, no lift check) never moved anything. What made it work
  (`Sources/Tray/Move.swift`): ⌘ mouse-down at (20000, 20000) addressed to the item's window, wait for
  the frame to change, mouse-up at the target's edge addressed to the target; each event posted via a null
  event to the app → session tap → back to the app. Evidence: `--move` output + `--dump`, 2026-10-30.
- **Display copies cannot be moved.** The same events on Spotlight's built-in copies (84830, 80253) never
  changed their frames, while its original (55, the window AX reports) moved. Clicks and moves go to the
  original (`movableWindow`), captures to the drawn window. Evidence: `--move`, 2026-10-30.

- **Display copies drift.** While the menu bar relayouts (e.g. the purple screen-capture indicator
  appearing), copies keep stale frames next to the originals: the panel showed 31–34 items, each item
  twice (light and dark glyphs). Only AX-backed windows are tray items now (`axBacked`). Evidence: Tray
  log "panel opened: 31/33 items", owner screenshot, 2026-10-30.
- **Synthetic clicks must land before the cursor is restored.** Telegram (Qt) ignored AXPress; the
  fallback click went nowhere while the cursor was warped back right after posting. Clicks now wait
  for a session tap to see each event (Ice's `postEventAndWaitToReceive`). Fix unverified. Evidence:
  Tray log "AXPress opened nothing for 319; clicking" → item moved back after 1.5 s, 2026-10-30.

- **Click, not AXPress, for Telegram.** AXPress on Telegram's item (Qt) opened nothing; waiting 1.5 s
  for it before the fallback click left the item next to the chevron for ~3 s. A synthetic click delivered
  like Ice's opened Telegram's menu (owner confirmed). Clicks now come first. Evidence: Tray log
  15:56:13 → 15:56:16, owner report, 2026-10-30.
- **The purple indicator is `com.apple.menuextra.audiovideo`** ("Audio and Video Controls", popover "Tray
  is capturing your screen"), shown while Tray captures, at its saved place (here: just left of the
  chevron, preferred position 326). Moving it into the tray does not stick: Tray moved it three times in
  10 s, macOS recreated it at 326 each time. Tray leaves it alone and keeps it out of the panel. Evidence:
  Tray log 16:05:05–16:05:15, `defaults read com.apple.controlcenter`, 2026-10-30.
- **Stats' popover was not seen as "opened"** (layer 0, only layers ≠ 0/25 counted), so its item went
  back after 1.5 s. Normal-layer windows hanging from the menu bar now count. Fix unverified. Evidence:
  Tray log "menu of 77831: nothing opened", 2026-10-30.

## Open
- Does AX follow the display with the active menu bar, together with the "original" windows?
