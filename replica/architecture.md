# Architecture: Harbor (a rebuild of ExtraDock's core features)

Harbor is a single-user native macOS app. There is no server, no account, no
payments and no email, so the web-oriented rows of the default stack do not
apply. The equivalents are below.

## Stack

| layer | choice | why |
| --- | --- | --- |
| language | Swift 6.2, strict concurrency | installed toolchain; first-class AppKit access |
| build | Swift Package Manager, executable target + `make app` bundling script | no Xcode project needed; builds from the command line |
| dock windows | AppKit `NSPanel` (non-activating, borderless, all Spaces) hosting SwiftUI | docks must float above apps without stealing focus |
| Manager / Settings UI | SwiftUI `Window` / `Settings` scenes | fast to build forms; native look |
| menu bar | SwiftUI `MenuBarExtra` | one scene, no NSStatusItem plumbing |
| persistence | Codable JSON in `~/Library/Application Support/Harbor/config.json`, atomic writes | one user, one small document; trivially diffable and exportable as a backup |
| backups | copies of `config.json` in `Backups/` with a reason tag | same format as the live config; restore is a file swap |
| window control | Accessibility API (`AXUIElement`) | only public way to raise, cycle and minimize other apps' windows |
| previews | ScreenCaptureKit | public API for window thumbnails |
| system stats | `host_statistics64`, `IOKit` power sources, `getifaddrs` | public, no extra permissions |
| hotkeys | Carbon `RegisterEventHotKey` | still the only public global hotkey API |
| login item | `SMAppService.mainApp` | modern public API |
| tests | Swift Testing (`swift test`) on the model, layout and persistence layers | logic is where regressions hide; UI checked by hand and screenshots |
| distribution | GitHub Releases, zipped `.app`, ad-hoc signed | no paid developer account required to start |

Not used: no database server, no network service. The only network calls are
the public-IP lookup in the IP widget (opt-in) and favicon fetch in the Link
widget.

## Schema

Entities: 11. Access rules: single local user; the config file is in the
user's own Library with default permissions.

The schema is Swift `Codable` types rather than SQL; see
`Sources/HarborCore/Model/`. Rules carried over from the SQL checklist:

- every entity has a stable `id: UUID`; duplicates get fresh IDs
- enums for every status-like field (layout, mode, edge, background kind...)
- a top-level `schemaVersion: Int`; loading a newer version is refused,
  loading an older one runs a migration
- times stored as `Date` (UTC); delays as `Double` seconds
- unknown widget types decode into an inert `.unknown(raw)` case and are
  written back unchanged

```
Config        schemaVersion, docks [Dock], settings AppSettings,
              knownScreens [KnownScreen], themes [Theme], icons [IconAsset],
              shelf [ShelfItem]
Dock          id, name, enabled, layout, style, position, screens, behavior,
              items [DockItem], perScreenPositions [screenID: Position]
DockItem      id, kind (app|file|folder|widget), path, customName,
              alwaysShowLabel, hideExtension, hidden, customIconID,
              folderOptions?, widget?
WidgetConfig  type (enum), settings (typed per widget), state
KnownScreen   id (vendor+model+serial, fallback to name+frame), name,
              customName, lastSeen
```

Deletion rules: deleting a dock deletes its items; forgetting a screen
removes it from every dock's assignments; deleting an icon clears every
item's `customIconID` that points at it (after confirmation).

## API (internal commands)

No HTTP routes. The equivalent is the set of commands the UI, menu bar,
shortcuts and (later) App Intents and MCP all call on one `DockStore`:

| command | does | callers | flow |
| --- | --- | --- | --- |
| createDock() | new floating centered dock from New Dock Defaults | Manager, menu bar | F01 |
| updateDock(id, change) | mutate a dock and persist | Manager sections | F02, F05 |
| duplicate/delete/rename/setEnabled(id) | dock lifecycle | sidebar, menu bar | F01 |
| addItems(dockID, urls, at) | pin apps/files/folders | Items, Edit Mode drop | F01, F04 |
| addWidget(dockID, type, at) | insert widget | Library | F03 |
| move/remove/hideItem | item lifecycle | Items, Edit Mode | F04 |
| setRuntimeHidden(id, source) | runtime hide/show, not persisted | menu bar, hotkey, intents | F09 |
| enterEditMode / exitEditMode(id) | Edit Mode | dock menu, menu bar | F04 |
| exportBackup / importBackup / restore(snapshot) | backups | Settings, Manager | F08 |
| copySettings / pasteSettings | style + behavior transfer | sidebar | |

Events in: workspace notifications (app launch/quit/activate, Space change,
sleep/wake), screen parameter changes, AX observers.
Jobs: daily snapshot on first change of the day; system stats sampler
(shared timer per refresh rate); IP refresh 30 s local / 5 min public.

## The parts that bite

- screen identity: `NSScreen` order and frames change; key screens by
  `CGDisplayVendorNumber`/`ModelNumber`/`SerialNumber`, fall back to name.
- coordinate systems: AppKit is bottom-left origin per global space, AX is
  top-left; convert in one place.
- Spaces and fullscreen: panels need `.canJoinAllSpaces` or
  `.moveToActiveSpace`; fullscreen detection by comparing the frontmost
  window's frame to the screen frame via AX.
- races: apps launching and quitting quickly; always look up
  `NSRunningApplication` fresh, never hold stale PIDs.
- persistence: write atomically, debounce saves, never write on every slider
  tick.
- permissions: every AX call can fail; degrade to plain activation.
- Swift 6 concurrency: AppKit is main-actor; samplers run off-main and hop.
- Reduce Motion and Reduce Transparency must be honored.
- native Dock: deep-hide via `com.apple.dock` defaults (autohide-delay) and
  restore exactly what was saved.

## Build order

1. Vertical slice: Config model + store + persistence; one floating dock
   panel showing pinned apps that launch on click; Manager with dock list and
   Items. Screens S02, S03, S11.
2. Must-haves: Style core (orientation, size, thickness, spacing,
   background), Position (pinned 12 spots, floating drag), Screens
   (all/assigned), Behavior (auto-hide, fullscreen), running indicators,
   item context menu, Edit Mode, menu bar, Settings General, launch at login,
   Running Apps, Clock, Spacer/Divider, Widget Library, permissions page,
   light/dark.
3. Should-haves: magnification, border, collapse, full width, gaps, Spaces
   visibility, reserve space, hotkeys, Native Dock Copy, deep-hide, folder
   browser, stacks, shelf, trash, system monitors, IP, link, finder, label,
   live dock, previews, backups, icon library, new dock defaults, onboarding.
4. Could-haves: notch layout, effects, themes, tint, gestures, badges,
   productivity widgets, pet, Space Awareness, Bluetooth, intents, MCP.
5. Fixes from replica-entrepreneur.
