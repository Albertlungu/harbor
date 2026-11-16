# Harbor

Multiple custom docks for macOS. Put a dock on any edge of any screen, give each
one its own look and behavior, and fill it with apps, folders and widgets.

Harbor is a working name; the final brand comes later.

## Status

Early development. Working today: multiple docks pinned to any edge or floating, per-screen
assignment, auto-hide, magnification, glass/blur/solid backgrounds, effects, themes, collapse,
Edit Mode, folder browsing, Live Dock and Running Apps, clock/label/spacer/divider widgets,
global shortcuts, the Manager, Settings, backups and onboarding.

Not done yet: most other widgets, window previews, the notch layout's shape, badges and
keeping windows off docks. See `replica/build-log.md` and `replica/features.csv`.

## Building

Requires macOS 26 or later and Swift 6.2.

```bash
make test   # core tests
make app    # builds dist/Harbor.app
make run    # builds and opens it
```

Set `HARBOR_HOME=/some/folder` to run against a separate config instead of
`~/Library/Application Support/Harbor`.
