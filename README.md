# Tray

A Windows-style overflow tray for the macOS menu bar.

Tray keeps the menu bar down to the icons you actually look at. Everything else goes behind one
chevron (`<`). Click it, and a small panel opens with the hidden icons drawn live, exactly as they
look in the menu bar: CPU and network numbers from Stats keep moving, the battery keeps its
percentage. Click an icon in the panel and its own menu opens, as if you had clicked it in the menu bar.

Made for MacBooks with a notch, where there is never enough room to the right of it.

## Features

- **One chevron instead of a crowded menu bar.** Third-party icons go into the tray. Apple's own icons
  (Wi-Fi, Battery, Control Center…) stay visible, and so does anything you pin.
- **Live previews.** The panel shows every hidden icon as it looks right now, refreshed every second.
- **Real menus.** Click or right-click an icon in the panel and its own menu opens next to the chevron.
  When the menu closes, the icon goes back into the tray.
- **Drag and drop.** Rearrange the panel, pin icons to the menu bar, or put them back into the tray.
- **Works with a notch and with external displays.** The panel opens under the chevron of the display
  you are using.

## Requirements

- macOS 14 Sonoma or macOS 15 Sequoia, on Apple Silicon. Tested on macOS 15.7.
- Xcode to build it. Tray is built and tested with Xcode 26.

## Install

There is no signed download yet, so for now Tray is built from source. It takes a minute. In a clone
of this repository, run:

```sh
scripts/build.sh
```

The script prints the path of the app it built, `build/Tray.app`. Move it to Applications and open it:

```sh
mv build/Tray.app /Applications/
open /Applications/Tray.app
```

`build.sh` signs the app with your "Apple Development" certificate if Xcode has one. Without it, the app
is signed ad hoc and the script prints a warning. Ad-hoc builds work, but macOS forgets their
permissions after every rebuild.

### If someone sent you Tray.app

macOS blocks apps that are not notarized by Apple. On macOS 15, right-click → Open no longer works
around it. Try to open Tray once, then go to **System Settings → Privacy & Security** and click
**Open Anyway** next to the message about Tray.

## First launch

Tray asks for two permissions in a small window. Each has a button that opens the right page in System
Settings:

| Permission | Why Tray needs it |
| --- | --- |
| **Accessibility** | To click hidden icons for you and to move icons between the menu bar and the tray. |
| **Screen & System Audio Recording** | To draw the hidden icons live in the panel. |

After you allow Screen Recording, click **Restart Tray** in that window. macOS only applies this
permission to a freshly started app.

On first use of the panel, macOS may also ask whether Tray may *bypass the system private window
picker*. Click **Allow**. macOS can ask again from time to time; that is a macOS rule for every app that
captures the screen.

On the very first launch, Tray moves Apple's icons to the right of the chevron, once. After that, the
layout is yours.

## Using Tray

| To | Do this |
| --- | --- |
| Open the tray | Click the chevron `<` |
| Open an icon's menu | Click the icon in the panel |
| Open an icon's right-click menu | Right-click the icon in the panel |
| Reorder the tray | Drag an icon in the panel onto another one (a line shows where it lands) |
| Pin an icon to the menu bar | Drag it from the panel onto the menu bar |
| Put a menu bar icon into the tray | Hold ⌘ and drag the icon onto the left half of the chevron |
| See everything at once | Right-click the chevron → **Arrange Icons**; ⌘-drag icons left or right of the `│` line |
| Close the panel | Click anywhere else, press Esc, or click the chevron |

> Don't ⌘-drag an icon out of the menu bar and let go there: macOS removes Apple's icons (Wi-Fi,
> Battery, Bluetooth) when you do. Drop onto the chevron instead.

Right-click the chevron for the menu:

- **Arrange Icons**: shows all icons with a `│` divider, so you can rearrange them by hand.
- **Refresh**: re-applies the hiding.
- **Refresh Interval**: how often the panel redraws the icons: 0.5, 1, 2 or 3 seconds.
- **Launch at Login**
- **Quit Tray**: every hidden icon comes back to the menu bar.

The panel is at most 360 points wide. To change that:

```sh
defaults write dev.illia.tray panelMaxWidth 480   # 200–800
```

## Good to know

- **The purple icon in the menu bar** appears while the panel is open. It is macOS telling you that an
  app (Tray) is capturing the screen, and it goes away a few seconds after the panel closes. macOS
  does not let apps hide it.
- **If the menu bar ever looks wrong,** quit Tray: all icons come back to their places. Start it again
  afterwards.
- **If the chevron shows a hint** about the `│` separator, it is to the right of the chevron. Hold ⌘ and
  drag it back to the left. Tray will not hide anything until it is.

## Uninstall

1. Right-click the chevron → **Quit Tray**.
2. Delete Tray from Applications.
3. Optional: run `defaults delete dev.illia.tray`, and remove Tray from Accessibility and from Screen &
   System Audio Recording in System Settings → Privacy & Security.

## For developers

- `swift test` runs the tests; `scripts/build.sh` builds the app.
- `Tray --dump`, `--capture <dir>`, `--move <windowID> <right|tray>` and `--onboarding` help with
  debugging; [AGENTS.md](AGENTS.md) explains them and has the code map.
- What Tray was designed to do is in [docs/SPEC.md](docs/SPEC.md). What macOS actually does, as
  measured while building it, is in [docs/FINDINGS.md](docs/FINDINGS.md).
- Logs: `/usr/bin/log stream --level debug --predicate 'subsystem == "dev.illia.tray"'`.

## Credits

Moving menu bar icons with synthetic ⌘-drags, and capturing hidden icons with CoreGraphics, follow the
approach of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird (GPL-3.0).
