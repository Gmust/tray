# Review instructions

## What Important means here
- The owner's menu bar left broken: separator collapsed while not left of the chevron, an item not moved
  back after a temporary move, a crash or hang while items are pushed off-screen.
- Coordinate spaces mixed: CG/AX top-left frames used with NSScreen/NSWindow bottom-left frames unconverted.
- Status windows picked by layer alone: wrong display's copy, ghost copies, or overlay/popup windows.
- Acting on a single reading of status item frames (collapse, move, click) without waiting for placement.
- Synthetic CGEvents posted at a position or window that was not verified first.
- Bundle id or signing changes that silently revoke Accessibility / Screen Recording grants.
- Capture timers or AX polling still running after the panel closes.
Style, naming and refactoring are Nit at most.

## Do not report
- Compile errors and test failures: `swift test` catches them.
- Anything under `.build/` or `build/` (generated).

## Always check
- `Package.swift`: no dependencies may be added (SPEC: no third-party deps).
- AX calls into other apps set a messaging timeout and handle failure.
- Claims that UI behavior works cite `--dump` / `--capture` / log evidence, not compilation.
- Changes to `scripts/build.sh`, `.github/workflows/`, or code posting synthetic CGEvents: say in the
  summary that a person must review them.

## Evidence and reporting
- Behavior claims cite `path:line` and a concrete scenario, never a guess from a name.
- Flag the class of a bug: list every instance, not only the first.
- Mark bugs this change did not introduce as Pre-existing.
- At most five Nits; count the rest in the summary.
- After the first review, report Important findings only.
- Open the summary with the count of findings by severity, or with "No blocking issues."
