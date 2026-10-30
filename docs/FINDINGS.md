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
- **Duplicate windows in the active row.** The active display's row holds two windows per item with
  identical frames (an old low windowID and a newer copy); both match the same AX element. `trayItems`
  keeps the lower windowID. Which one renders for capture: open (phase 3). Evidence: `--dump`, 2026-10-30.
- **Quitting restores the menu bar.** After `pkill -x Tray`, all 19 items were back at their exact
  pre-launch x positions. Evidence: `--dump` before launch vs after quit, 2026-10-30.
- **Rebuilding over a running Tray.** `scripts/build.sh` now copies then renames, so the running process
  keeps its inode; Tray survived a rebuild while running. Evidence: same pid before/after, 2026-10-30.
- **Signing.** Apple Development signing gives a certificate-based designated requirement
  (`identifier "dev.illia.tray" and anchor apple generic and certificate leaf[subject.CN] = …`), so
  grants should survive rebuilds. Evidence: `codesign -d -r-`, 2026-10-30. Survival across a rebuild
  is not yet observed.

## Open
- Does AX follow the display with the active menu bar, together with the "original" windows?
- Which of an item's duplicate windows renders correctly for ScreenCaptureKit (phase 3)?
- Do Stats items keep redrawing while pushed off-screen (phase 3)?
