# Working agreement

## Mission and scope
Tray is a native macOS menu bar utility that works like the Windows tray overflow. One chevron status
item stays visible. Every other status item lives in a hidden tray, pushed off-screen, unless it is
pinned right of the chevron. The chevron opens a panel that renders the tray items live
(ScreenCaptureKit) and forwards clicks, so an item's real menu opens under the tray.
Full requirements: [docs/SPEC.md](docs/SPEC.md).

In scope: macOS 14 Sonoma and 15 Sequoia on Apple Silicon, including notch MacBooks and multiple displays.
Out of scope: App Store, sandbox, Intel, macOS < 14, `.xcodeproj`, third-party dependencies.

## Source of truth
1. [docs/SPEC.md](docs/SPEC.md): requirements and the decided design (§1–7). Ask before redesigning.
   Its "Delivery plan" section is a proposal, not a decision.
2. This file: working rules and boundaries.
3. [docs/FINDINGS.md](docs/FINDINGS.md): platform behavior verified on the owner's Mac. Add to it when you verify one.
4. [docs/HANDOFF.yaml](docs/HANDOFF.yaml): current state.
5. Code. When code and SPEC disagree, SPEC wins: fix the code or ask.

UI design source: SPEC §4 (panel), §6 (chevron menu), §7 (onboarding). No Figma. Russian UI strings in SPEC are verbatim.

## Code and document map
| Area | Path | Owns | Checks |
| --- | --- | --- | --- |
| Entry / CLI | `Sources/Tray/main.swift` | argument dispatch (`--dump`; app mode not yet) | `swift test` |
| Discovery | `Sources/Tray/Discovery.swift` | status windows (CGWindowList, layer 25), AX `AXExtrasMenuBar` frame match, `--dump` JSON | `swift test`, `--dump` |
| Tests | `Tests/TrayTests/` | pure logic (frame matching) | `swift test` |
| Bundle + signing | [scripts/build.sh](scripts/build.sh) | release build, `build/Tray.app`, Info.plist, codesign | run it |
| CI | [.github/workflows/ci.yml](.github/workflows/ci.yml) | runs the gate on macos-15 | — |
| Requirements + UI design | [docs/SPEC.md](docs/SPEC.md) | what to build | — |
| Platform findings | [docs/FINDINGS.md](docs/FINDINGS.md) | verified macOS behavior, open questions | `--dump` |
| Review rules | [REVIEW.md](REVIEW.md) | `/dual-review` instructions | — |

Not implemented yet (see SPEC delivery plan): hiding (§1), live capture + `--capture` (§3), panel (§4),
click forwarding + `--move` (§5), chevron menu (§6), onboarding (§7), os.Logger.

## Working rules
- Inspect before editing; preserve unrelated and untracked work.
- Confirm before any destructive action.
- State expected evidence before implementing.
- Keep changes focused on the requested scope.
- The agent cannot see the screen. Menu bar or panel behavior counts as verified only with `--dump` JSON,
  `--capture` PNGs, `log stream` output, or the owner's confirmation. Compiling is not verification.
- Coordinates: CGWindowList and AX use global top-left origin; NSScreen/NSWindow use bottom-left, flipped on
  the primary screen's height. Convert in one place, never mix.
- Every status item has one window per display's menu bar, and layer 25 also holds non-status windows
  (overlays, popups). Filter by display and menu bar height, never by layer alone.
- AX calls into other apps: set a messaging timeout and handle failure.
- Logger interpolations need `privacy: .public`, or `log stream` shows `<private>`.
- When review or an incident misses a bug, add what the reviewer lacked: a rule here or in REVIEW.md, or a check.

## Boundaries
Do not edit without asking: `Package.swift` dependencies (none allowed); the bundle id `dev.illia.tray` and
the signing in `scripts/build.sh` (changing either revokes Accessibility / Screen Recording grants and
saved item positions); `.github/workflows/`.
Human review required: `scripts/build.sh`, `.github/workflows/`, code that posts synthetic CGEvents.
An agent's or AI reviewer's approval does not count for these.
Ask before running on the owner's Mac: Tray in app mode or `--move` (they change the live menu bar),
`tccutil reset`, `defaults delete dev.illia.tray`, writing other apps' `NSStatusItem Preferred Position`
keys, quitting other apps. Read-only diagnostics (`--dump`, `--capture`) need no confirmation.
Generated, never edit: `.build/`, `build/`.

## Checks
Gate: `swift test`. It builds all targets and runs the tests; it needs Xcode with the macOS 14+ SDK.
CI runs the same command on macos-15.
Not covered: anything that needs TCC grants, the real menu bar, ScreenCaptureKit, AX, or synthetic events.
Verify those on the Mac with the commands below.

Not part of the gate:
- Bundle: `scripts/build.sh` prints the `Tray.app` path. It signs with the first valid "Apple Development"
  identity (override: `TRAY_SIGN_IDENTITY`). Without one it signs ad-hoc with a loud warning; grants then
  reset on every build.
- Diagnostics, with Tray.app's own TCC grants:
  `open -n -W --stdout /tmp/tray-dump.json build/Tray.app --args --dump`.
  Running `build/Tray.app/Contents/MacOS/Tray --dump` directly works too, but TCC then checks the
  terminal's grants, not Tray's.
- Logs (once app mode exists): `log stream --level debug --predicate 'subsystem == "dev.illia.tray"'`.

## Handoff
`docs/HANDOFF.yaml` is the state that survives a context reset. Update it after every verified step and
before any long or risky one: snapshot, not log; refs not content; under 40 lines; `next` always set.
History is in git.
