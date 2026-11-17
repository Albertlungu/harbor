# Harbor

Multiple custom docks for macOS. Put a dock on any edge of any screen, give each
one its own look and behavior, and fill it with apps, folders and widgets.

Harbor is a working name; the final brand comes later.

## Features

- As many docks as you like: pinned to any edge (12 positions), floating anywhere, or a notch that folds into a pill.
- Per-screen placement that survives unplugging and sleep; mirror a dock on every screen.
- Glass, blur, solid or no background; borders, corner styles, tinted icons, snow/rays/fireworks, magnification, themes.
- Auto-hide, fullscreen hiding, fade under windows, keep windows off docks, a hotkey per dock.
- 24 widgets: clock, link, Finder, IP address, spacer, divider, label, folder and app stacks, two shelves, Trash,
  Live Dock, running apps, desktop apps and indicator, CPU, memory, GPU, battery, Bluetooth battery, counter,
  timer, metronome and a dock pet you can dress up as a seal, cat, dog, fox, bunny, penguin, frog, owl or hamster.
- Window previews, notification badges, click and scroll gestures, Edit Mode on the dock itself.
- Backups with daily snapshots, settings export, icon library.
- Automation: `harbor://toggle?dock=Work` style URLs for Shortcuts, and `harbor-mcp` so AI assistants can
  change docks after you approve.

Clean-room rebuild of the features of a commercial multi-dock app, written from its public documentation.
See `replica/` for the research, plan and build log.

## Building

Requires macOS 26 or later and Swift 6.2.

```bash
make test   # core tests
make app    # builds dist/Harbor.app
make run    # builds and opens it
```

Set `HARBOR_HOME=/some/folder` to run against a separate config instead of
`~/Library/Application Support/Harbor`.
