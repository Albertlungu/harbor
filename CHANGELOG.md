# Changelog

## 1.1.0

### Shelf, Pinned Files and Trash

- The Shelf, Pinned Files and Trash open in the same Finder-style browser as folders, with Icons, List,
  Columns and Gallery views, sorting, search, Quick Look and Finder's shortcuts.
- The Shelf opens the moment a dragged file comes near it, or only when it's right over it; the distance is
  set in its settings. A shelf opened that way closes once the pointer moves away, unless you click in it.
- Command-V pastes files onto the Shelf, and a copied screenshot or text is saved there as a file.
- Clear All on the Shelf no longer asks first.
- Dropping files on the Trash browser moves them to the Trash, items in it can be deleted immediately, and
  Command-click on Empty Trash skips the confirmation.
- Pinned Files can be added by dropping or pasting, removed without touching the files, and stay pinned when
  renamed.

### Performance

- The clock, timer and system gauges stop redrawing while their dock is hidden, and a finished timer stops
  ticking, which cuts Harbor's idle CPU use to under 1%.
- Switching apps, including leaving Mission Control, no longer stalls Harbor while it reads the running apps.
- With Replace the macOS Dock on, the guard that keeps the Dock from sliding up no longer makes pointer
  movement wait on Harbor.

## 1.0.0

The first public release.

### Docks

- Any number of docks, pinned to any of 12 edge positions, floating, or shown as a notch-style pill.
- Per-screen placement that survives sleep and unplugging, and mirroring onto every display.
- Glass, blur, solid or no background, borders, corner styles, tinted icons, magnification, labels and themes.
- Auto-hide, fullscreen hiding, fade under windows, keep windows off docks, a hotkey per dock and Keep Dock Shown.
- Window previews, notification badges, click and scroll gestures, and Edit Dock on the dock itself.
- Optional ambient dock effects: snow, rays, fireworks and more.
- Replace the macOS Dock: hides it while Harbor runs and restores it on quit, on toggle-off, after a crash
  (at the next launch) and when Harbor is stopped with `kill` or `killall`.

### Widgets

- 24 widgets, including clock, folder and app stacks, shelves, Trash, Live Dock, running apps, Space indicator,
  CPU, memory, GPU, battery, Bluetooth battery, timer, metronome and a pet.
- Folders open in a small Finder window with List and Icons views, file operations and drag and drop.
- The pet comes in nine species with colours, markings and accessories, can roam the desktop and windows,
  and can be picked up and thrown.

### Desktop

- Desktop weather that follows the seasons and piles up on windows. Off by default for new installs.
- A wallpaper browser with search, favourites and optional seasonal changes.
- Rounded screen corners.

### Setup and reliability

- A guided tour on first launch, reopened any time with Show Tour in the menu bar or the Help menu.
- A Permissions window that explains each permission and asks only when a feature needs it.
- Daily config backups, restore, settings export and an icon library.
- A damaged config falls back to the newest good backup and is kept as `config.damaged-<time>.json`;
  a config written by a newer Harbor is kept the same way instead of being overwritten.
- Harbor keeps running, and reports the problem in the Manager, when its settings folder can't be written.

### Automation

- `harbor://` URLs to show, hide, toggle and create docks from Shortcuts and scripts.
- A bundled `harbor-mcp` server so AI assistants can list and change docks after you approve.
