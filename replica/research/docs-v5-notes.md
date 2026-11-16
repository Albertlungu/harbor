# ExtraDock 5 Documentation Notes (clean-room spec)

Notes paraphrased from the public ExtraDock 5 docs, read one page at a time. Facts only, in our own words. Where a page did not state a default or range, that is noted as "not stated". The docs themselves say they may lag the shipping app.

---

## Introduction
Source: https://extradock.app/docs/v5/introduction

- Product: multiple independent, customizable docks for macOS. Only stated requirement: macOS 26.
- Per-dock configurable: items, layout, position, display assignment, behavior, widgets.
- v5 is a separate generation from v4 (new Manager, settings hierarchy, persistence, widgets). v4 docs live at /docs/v4.
- Core concepts:
  - Manager: create docks, edit selected dock. Dock sections: Items, Style, Position, Screens, Behavior.
  - Dock Edit Mode: docks are locked by default; right-click dock -> "Edit Dock" to rearrange/remove/drop items.
  - App Settings: app-wide defaults.
  - Widgets: interactive dock content (clocks, shelves, monitors, running-app views, utilities).
  - Layouts: conventional bar, or a shape attached to a screen edge (Notch layout).
- Privacy: config stays local unless a sharing/connected-service feature is used.
- Docs are AI-generated and team-reviewed; app wins on disagreement. Support email support@appitstudio.com.
- Additional doc pages linked but not in our research list: /installation, /migrate-from-v4, /ai-assistants, /license, /stripe-widget (Stripe Balance widget).
- Doc nav groups: Getting Started; The Manager; App Settings; Workflows; Widgets.

---

## Quick Start
Source: https://extradock.app/docs/v5/quickstart

1. Create a dock: menu bar menu -> Manager; "+" at bottom of sidebar, or "Create Dock" button when no docks exist (empty state). Name it in the toolbar text field. New dock appears floating in the screen center.
2. Add content: Items -> "Add to Dock" (apps, files, folders, widgets). "Native Dock Copy" recreates the macOS Dock contents. Alternative: right-click dock -> Edit Dock, drag from Finder.
3. Arrange: reorder in Items list or drag on dock in Edit Mode. Style = layout (Dock / Notch), orientation, size, spacing, background, border, effects, magnification. Position = pinned or floating. Screens = which displays. Behavior = auto-hide, Spaces/fullscreen visibility, click behavior, badges, per-dock shortcut.
4. Add widget: Items -> Add to Dock -> Widgets; searchable library. Per-instance settings via a settings control on the item's row in the Items list. Suggested starters: Clock, Shelf, Running Apps, CPU Usage, Folder Stack.

---

## Permissions
Source: https://extradock.app/docs/v5/permissions

- Location: Settings -> Permissions. Permissions requested lazily, only when a feature needs them.
- Each row has a status: "Granted", "Not granted", or "Determined when first used". Row actions: "Request Access", "Open System Settings" (where macOS permits).
- Checks are local; status is not stored or transmitted.

| Permission | Used for | When missing |
|---|---|---|
| Accessibility (macOS 27 renames it "Device Control and Data Access"; app labels follow) | Raise existing window across Spaces/displays; cycle and minimize windows from dock; fullscreen detection for auto-hide; messaging-app notification badges; Reserve Dock Space; minimized-window indicators in Space Awareness and Window Previews | Dock clicks fall back to plain app activation; macOS may open a new window instead of raising the existing one |
| Screen Recording ("Screen & System Audio Recording") | Window Preview thumbnails and titles | Previews fall back to a list of icon + title per window |
| Bluetooth | Richer/more accurate Bluetooth Battery widget readings | Widget shows only basic macOS-exposed info; some devices show no percentage |
| Automation (Finder) | Trash widget: show contents, empty Trash via Finder | Older docks: Trash item opens the Trash folder for manual emptying |
| Files and Folders (no row) | Requested by macOS when user picks a folder/file/custom icon/backup location/Shelf location | Access scoped to the chosen resource only |

- Accessibility prompting: offered once in onboarding; Manager shows banner "Accessibility permission is off" with "Enable Accessibility" button until granted. Grant at System Settings -> Privacy & Security -> Accessibility.
- Finder Automation flow: triggered when adding a Trash widget, or when a starting point / Native Dock Copy / v4 import includes Trash. App first shows its own pre-prompt "Allow ExtraDock to Use Finder" -> "Continue" -> macOS prompt. If previously denied (macOS won't re-prompt), app shows "Turn On Finder Access" with "Open System Settings" (Privacy & Security -> Automation).
- Troubleshooting: quit/reopen if a feature stays unavailable after granting; banner persists -> use Enable Accessibility or System Settings.

---

## Manager
Source: https://extradock.app/docs/v5/manager

- Window: sidebar + editor pane.
  - Sidebar lists docks; each row shows name, placement summary (e.g. "Pinned · Bottom", "Floating · Horizontal"), item count. Rows reorderable by drag. Per-row eye button toggles dock on/off.
  - Sidebar footer buttons: open ExtraDock Settings; restore a backup; create new dock ("+").
  - Editor: toolbar has editable dock-name field. Sections: Items, Style, Position, Screens, Behavior.
- Ways to open: menu bar "Open ExtraDock Manager"; menu bar per-dock "Open in Manager"; dock right-click "Open Dock Settings"; Settings -> General "Show Manager on launch" (default not stated here).
- Banners:
  - Accessibility off: "Enable Accessibility" + "Open System Settings".
  - Dock hidden at runtime: "Show Dock" button. Hide sources: menu bar menu, dock menu, dock shortcut, Shortcuts app, Focus filter, DockFlow, AI assistant.
  - Save failure: disk full or ExtraDock5 folder in Application Support not writable; app retries automatically.
- Edits are live (same config the docks render). Some macOS-integration settings may require permission or restart.
- Persistence location: ~/Library/Application Support/ExtraDock5 (folder named "ExtraDock5").
- Empty state: "Create Dock" button when no docks (from Quick Start).

---

## Menu Bar Menu
Source: https://extradock.app/docs/v5/menu-bar

- Status item shown only when Settings -> General "Show ExtraDock as" includes the menu bar.
- Top-level items, in order:
  1. Open ExtraDock Manager
  2. ExtraDock Settings (Cmd-,)
  3. New Dock (uses New Docks defaults)
  4. Window Previews (toggle, without opening Settings)
  5. Media (now-playing transport controls + "Show Full Media Controls")
  6. About ExtraDock (version + build)
  7. Check for Updates (respects update channel)
  8. Export Logs (same file as Settings -> Diagnostics)
  9. Quit ExtraDock
- Per-dock section: one submenu per dock, by name, in sidebar order. Empty state: a disabled "No Docks" row.
- Conditional states:
  - "Accessibility Permission Needed" item inserted above About while missing.
  - License check pending/unconfirmed: menu reduces to license actions + Quit.
- Per-dock submenu, in order:
  1. Status note when the dock is out of view: hidden by auto-hide / hidden while fullscreen / hidden by overlapping window.
  2. Hide Dock / Show Dock (runtime hide; stays enabled; cleared on restart).
  3. Enabled (toggle).
  4. Edit Dock / Done Editing.
  5. Position Mode: Floating (Horizontal | Vertical); Pinned (Bottom | Top | Left | Right). Notch-layout docks instead show 3 notch positions per edge.
  6. Lock Position (floating docks: prevents dragging).
  7. Size: Small (32 px), Medium (48 px), Large (64 px), Match macOS Dock Size.
  8. Open in Manager.

---

## Create and Manage Docks
Source: https://extradock.app/docs/v5/docks

- Create: sidebar "+", empty-state "Create Dock", or menu bar "New Dock". Auto-named sequentially "Dock 1", "Dock 2", ... New docks float centered; initial values from Settings -> New Docks. Requires an active license.
- Rename: toolbar field or sidebar context menu "Rename". Empty names rejected.
- Enable/disable: sidebar eye button, context-menu "Enabled", or menu bar submenu. Disabled dock keeps settings, is hidden and not editable on screen.
- Sidebar right-click menu: Rename, Enabled, Duplicate, Delete, Copy Settings / Paste Settings.
- Duplicate: name = original + " Copy"; copies items, appearance, behavior, shared position; NOT screen assignments or per-screen positions; items get fresh internal IDs.
- Delete: immediate, no confirmation. Recovery via Manager restore-backup button.
- Copy/Paste Settings (also in dock's own menu): transfers appearance + behavior. Target keeps name, identity, items, layout, position, screen assignments, shortcut, enabled state, position lock. Themes (Style) for reusable looks.
- Runtime hidden state (enabled but hidden): sources = Hide Dock (menu bar / dock menu), keyboard shortcut (optional "Hide again after" timer), Shortcuts app, Focus filter, DockFlow preset, AI assistant, Manager. Sidebar row shows "Hidden by <source>" instead of placement; editor shows banner. Ends on Show Dock or app restart, unless a DockFlow preset/Focus filter re-hides it. "Show Dock" reverts to the dock's own visibility rules.

---

## Items
Source: https://extradock.app/docs/v5/items

- Item types: apps, files, folders (picker or Finder drag), widgets (searchable Widgets Library, includes Trash), legacy Trash item in older docks.
- Add to Dock (+) menu:
  - Items: file picker for apps/files/folders.
  - Widgets: opens Widgets Library.
  - Native Dock Copy: adds native Dock's pinned folders/files, spacers, a Live Dock widget, a Trash widget. If Trash needs Finder access, asks first and offers "add without Trash". If dock already has items: choose "Add & Restyle" (also match macOS Dock style) or add items only. Only shown when native Dock preferences are readable.
  - Monitor Dock: adds CPU, Memory, GPU, Battery, IP Address, Bluetooth Battery widgets; skips any already present.
  - Empty dock state: the same options rendered as cards.
- Item Options (apps/files/folders):
  - Name (custom label; empty = item's own name).
  - Always show label (draws name under icon; forced on and locked while dock Style "Always show item names" is on).
  - Files: Hide file extension.
  - Folders: On click = Default (follows global Behavior) | Browse beside dock (popover) | Open in Finder (in chosen app).
  - Folder browser: Layout (Grid | List | Fan); Icon size; Columns + Show file names (Grid only); Sort by (Name | Kind | Date modified); Reverse order; Keep folders first; Show hidden files; Show previews (default ON); Close after dragging a file out (default OFF). Ranges for icon size/columns not stated.
  - Drops into the browser copy files, never overwrite existing.
  - Open folder with: Choose App (per folder) | Use Finder (global default).
- Folder browser keys: Space = Quick Look; arrows = move selection; Esc = close Quick Look; click outside app closes browser. "Move to Trash" always confirms; can be hidden in App-Wide Behavior.
- Legacy Trash options: Ask before emptying (default ON); Show item count (default ON).
- Custom icon menu: Set from File; Import from URL; Choose from Library; Clear Custom Icon.
- Items list row controls: drag handle (reorder); per-type button (Item options / Custom icon / Widget settings / Trash settings); eye (hide without removing; row dims, labeled "Hidden"; not available for widgets); minus (remove immediately, no confirm).
- Dock item right-click menu:
  - Always: Open; Reveal in Finder.
  - Running app: list of windows (minimized ones marked); Hide; Quit.
  - Finder: New Finder Window. Folders: Open in New Window.
  - Chromium browsers (Chrome variants, Brave, Edge, Vivaldi, Chromium): "New Window with Profile" listing named profiles/accounts (no guest/temporary).
  - Common: Change Icon; Revert to Original Icon (if customized); Gestures submenu (per-item modifier and scroll overrides); Edit Dock; Remove from Dock (with confirmation).
  - Apps/files/folders: "New App Stack with"; "Add to App Stack".
  - Live Dock / Running Apps items: Live Dock Settings; Hide from Live Dock.
  - ExtraDock submenu: dock-level commands.
- Removing never deletes the original file. Unknown imported widget types are preserved inert (no crash) until supported.

---

## Style
Source: https://extradock.app/docs/v5/style

- First two attempts failed (connection reset); a later read succeeded.
- Layout: Dock | Notch. Notch hides most sections; keeps Notch, Background, Size & Spacing, Icons.
- Bar: Orientation Horizontal | Vertical (floating only; pinned follows edge). Collapse bar toggle reveals Collapse group.
- Size & Spacing: Icon size Small 32 | Medium 48 | Large 64 | Custom 20-128 pt. Bar thickness Auto | Thin | Standard | Thick | Custom 24-200 pt (Auto fits icons or tallest item; widgets span cells). Space between icons Tight | Default | Roomy | Spacious. Always show item names (default OFF; forces item labels on; widgets keep own). Advanced: Corner radius Default | Soft | Round; Bar side padding.
- Icons: Tint icons (default OFF) + Intensity Subtle..Full; widgets unaffected; live Clock/Calendar icons freeze while tinted; works in Notch.
- Background (Dock layout): Liquid Glass (default; Dark glass toggle, optional Tint color) | Blur (Intensity Lightest..Darkest; Opacity Subtle | Medium | Solid | Opaque) | Solid (Color + same opacity choices) | None (icons only). Global "Always use opaque dock backgrounds" overrides.
- Border: Show border (default OFF); Width Hairline | Thin | Medium | Thick | Custom; Color.
- Effects: Snow, Rays, Fireworks (combinable). Intensity Subtle | Standard | Bold | Custom. Not in Notch.
- Hover Magnification: Magnify icons on hover (default ON); Max scale 1x-4x; Falloff radius.
- Themes: style-only presets, none built in. Apply; Save current style as theme; Import theme file; Manage: Update from This Dock, Rename, Export, Delete.

---

## Position
Source: https://extradock.app/docs/v5/position

- Position mode: "Pinned to Edge" | "Floating". New docks start Floating. Switching to Pinned lands at bottom-center.
- Pinned to Edge:
  - Screen position: 12-spot picker (3 per edge: start/center/end), selecting edge + alignment together.
  - Full width (toggle): bar spans the whole edge; the chosen spot then sets content alignment within the bar.
  - Gap from screen edge: Flush | Small (default) | Medium | Large | Custom (custom max 64 pt).
  - Advanced:
    - Offset along edge: shifts along the edge; positive = inward from corner. Hidden when Full width is on.
    - Top / Right / Bottom / Left padding: insets from pinned edge and both ends. Values for other edges are remembered and reapplied if pinned there later.
- Floating:
  - Drag handle: appears on hover by default; "Show drag handle" toggle keeps it always visible.
  - Drag handle side: Automatic | Screen edge | Inward | a specific end of the dock.
  - Snaps to screen edges and centers (governed by magnetic snapping in Settings -> Behavior).
  - Lock Position: dock right-click menu or menu bar submenu; disables dragging.
  - Drag handle is separate from the collapse control.
- Notch layout docks: always pinned; show "Notch Position" picker using same 12 spots; a dot marks spots taken by another notch dock. Bottom spots require "Deep-hide native macOS Dock" (Settings -> General).
- Desktop widget mode (toggle, default OFF): window level above wallpaper, below all app windows.
- Per-screen positions: a dock can have a screen-specific placement (set by dragging on that screen or via Screens). Editing the general Position applies to all screens and clears conflicting per-screen overrides.

---

## Screens
Source: https://extradock.app/docs/v5/screens

- Screens = where a dock may appear; Position = how it's placed.
- Show on All Screens (toggle): mirrors the dock onto every connected display. Existing assignments kept but ignored. Mirrors share items/settings; editing any copy edits the dock. Default not stated.
- Shows On (when mirroring is off): assign displays by switching them on in Known Screens.
  - No assignments: may appear on any screen.
  - One or more: appears on one matching connected screen at a time; hidden while none connected.
  - Each assignment shows "Connected" / "Not connected" and a Remove button.
  - Stable display identity stored so assignments survive reconnects and rearrangement.
- Known Screens list: every display ever seen. Right-click: Rename; Forget Screen (removes from all docks' assignments).
  - "Needs Attention" section: two identical displays can't be distinguished -> "Choose Display" (highlights each physical display) and "This One" to confirm.
  - "Possible Duplicates" section: one physical display looks like two (new adapter/replaced monitor) -> "Merge".
- Export Screen Diagnostics: saves the screen resolver's recent decisions as JSON.
- Dragging on one display can set a display-specific position; changing general Position sets one shared position.

---

## Behavior (per dock)
Source: https://extradock.app/docs/v5/behavior

- Auto-Hide (section hidden for Notch docks; they use Style idle mode):
  - Hide automatically (toggle; default not stated).
  - Pinned: Reveal trigger = "At screen edge" | "Near screen edge"; Near adds "Distance from edge" (range not stated).
  - Floating: "Use default reveal distance" (toggle); when off, "Reveal distance" value.
  - Hide after: Fast | Standard | Slow | Custom (max 5 s).
  - Reveal after: Fast | Standard | Slow | Custom (max 2 s).
- Visibility:
  - Show on: All Spaces (default) | Active Space (follows you) | Pinned (stays on creation Space).
  - Hide when a fullscreen app is active (toggle, default ON).
- Hide on Window Hover (toggle, default OFF): fades dock when another app's window overlaps; clicks pass through; returns after area clears briefly. Mutually exclusive with "Reserve space for this dock" (enabling one disables the other, for this dock only).
- Show at screen edge while hidden (toggle, default OFF): edge hover reveals a dock hidden by fullscreen or hover-hide; re-hides on leave. Uses Hide after / Reveal after delays (those controls shown here when Auto-Hide is off). Pinned docks only; not for Notch.
- Reserve space for this dock (toggle, default ON): keeps windows off the pinned edge. Requires app-wide "Reserve Dock Space" (Settings -> Behavior); if that's off, notice + "Turn On" button. Floating docks: notice that space can't be reserved.
- Clicking the active app: None (native behavior) | Minimize | Hide | Cycle Windows. New-dock default: Cycle Windows (configurable in New Dock Defaults).
- Notification badges:
  - Show notification badges (default OFF).
  - Show full number (when off, >99 shows "99+"; default not stated).
  - Per-App Rules: list of pinned + running apps with badge toggle each; "Reset All to Default" turns all back on.
  - Messaging-app badges may need Accessibility.
- Shortcuts:
  - Toggle with keyboard shortcut (toggle) + "Record Shortcut" button (global show/hide hotkey).
  - Docks may share a shortcut; one press toggles all; the section lists the others sharing it.
  - Hide again after: Never | 15s | 30s | 1 min | Custom (default not stated).
  - If macOS rejects a conflicting shortcut, app reports it and keeps retrying registration.
- Configured elsewhere: Running Apps widget (show apps without windows), Live Dock widget (indicator dots, spacing), Settings -> Behavior (excluded apps, indicator color, attention style).

---

## App Settings (overview)
Source: https://extradock.app/docs/v5/settings

- Open via Cmd-, ; menu bar "ExtraDock Settings"; gear button at bottom of Manager sidebar.
- Window: sidebar with grouped sections, in order:
  1. App: General (startup, presentation, updates, native Dock, appearance); Behavior (folders, App Stack menus, dragging, Reserve Dock Space, running apps, gestures, screen-share privacy) - app-wide.
  2. Personalization: New Docks (defaults for new docks); Icon Library (imported custom icons).
  3. Features: Previews (Window Previews).
  4. System: Permissions; Backup (export/import, daily backups, v4 migration); Integrations (DockFlow and other Appit apps, AI assistant access, Stripe).
  5. Account: License (activation, update coverage, details).
  6. Support: Diagnostics (exports, logs).
- Per-dock settings live only in the Manager, never in Settings.

---

## General Settings
Source: https://extradock.app/docs/v5/general

- Startup:
  - Launch at login (toggle; default not explicitly stated, appears off). macOS may require login-item approval; a button opens Login Items settings.
  - Show Manager on launch (toggle, default OFF); applies to login launches too.
  - Show ExtraDock as (picker): Menu bar only (default) | Dock app only (no status item/menu; use Manager & Settings) | Menu bar + Dock icon.
- Native Dock:
  - Deep-hide native macOS Dock (toggle, default OFF): suppresses native Dock while app runs. Changing it prompts restart: "Restart Now" | "Later". Link "Open Desktop & Dock Settings" (to move native Dock to an unused edge). Unlocks bottom Notch placement. On failure: "Retry Dock Setting" button. Limitation: macOS can still reveal the native Dock at the physical edge or in Mission Control.
- Updates:
  - Current version (read-only).
  - Check for updates automatically (toggle; default not stated).
  - Update channel: Stable (default) | Beta.
  - Check for Updates button (same as menu bar).
  - Only versions within the license's update coverage are offered.
- Appearance:
  - Always use opaque dock backgrounds (toggle, default OFF): glass/blur/translucency rendered as solid. Forced on automatically while macOS Reduce Transparency is enabled.

---

## App-Wide Behavior Settings
Source: https://extradock.app/docs/v5/app-behavior

Location Settings -> Behavior; applies to all docks. No numeric ranges.
- Folders:
  - Clicking a folder: Browse beside dock (default) | Open in Finder.
  - Open folders with: picker of installed file managers (Finder default). "Show all apps" toggle (lists every app that can open folders; default not stated). "Other app -> Choose App" button.
  - Per-item Item Options override these.
- App Stack Menus: Show Move to Trash in App Stack menus (default ON). Off hides the action and its Cmd-Delete shortcut in App Stack and folder browser menus; when shown it always confirms.
- Dragging: Enable magnetic snapping (default ON) - floating docks snap to edges and centers.
- Reserve Dock Space:
  - Reserve Dock Space (default OFF): keeps expanded/zoomed app windows out of pinned dock areas.
  - Active on Drag (default OFF; enabled only when Reserve is on): also adjusts windows after a user drag or resize.
  - Each pinned dock must also have "Reserve space for this dock" on.
  - Without Accessibility: section shows "Allow Accessibility Access" button; no adjustment occurs.
- Running Apps:
  - Show running indicators (default ON).
  - Indicator color (color override); "Use Default" reverts to each dock's accent or automatic light/dark.
  - Excluded Apps: app list with per-app toggles; excluded apps never show in any running-apps section. "Reset All to Default".
  - Attention style: Bounce (default) | Flash Once | Badge Only | Off.
- Gestures (both groups default OFF):
  - Click gestures (enable toggle). One picker each for Cmd-click, Option-click, Option-Cmd-click, Shift-click, Middle-click. Actions: Do nothing | Reveal in Finder | Hide or show the app | Show only this app | Quit the app | Minimize the front window. Per-combination defaults not stated.
  - Scroll gestures (enable toggle). Scroll over an icon: Cycle the app's windows (default) | Show (up) / hide (down) the app.
  - Control-click always opens the context menu. Only Reveal in Finder works on files/folders. Items can override (Gestures submenu in item context menu).
- Privacy: Hide docks from screen sharing & recordings (default OFF): excludes docks, folder browsers, popovers from shares/recordings/screenshots (still visible locally; open menus still captured).
- Permission: Accessibility needed for Reserve Dock Space.

---

## New Dock Defaults
Source: https://extradock.app/docs/v5/new-docks

Location Settings -> New Docks. Affects only docks created afterwards.
- Default Style, gated by master toggle "Customize style for new docks" (off = built-in style):
  - Icon size: Small (32 pt) | Medium (48 pt, default) | Large (64 pt) | Custom (20-128 pt).
  - Bar thickness: Auto (scales with icon size) | Thin | Standard | Thick | Custom (default not stated; presumably Auto).
  - Spacing between icons: Tight | Default | Roomy | Spacious | Custom (default not stated; presumably Default).
  - Magnify icons on hover: toggle, default ON.
- Behavior, gated by "Customize behavior for new docks":
  - Hide automatically: default OFF.
  - Hide when a fullscreen app is active: default ON.
  - Clicking the active app's icon: Do nothing | Minimize the front window | Hide the app | Cycle the app's windows (default).
- "Reset to Built-in Defaults" button clears both customizations.
- Placement is not configurable here: new docks always start floating, centered; Position/Screens set per dock afterwards.
- No templates/starting points on this page (though Permissions page mentions "starting points" in the context of Trash).

---

## Icon Library
Source: https://extradock.app/docs/v5/icon-library

Location Settings -> Icon Library. App-wide, shared across docks.
- Header shows total icon count. Grid of icons, each tagged "In use" (with usage count) or "Unused". Search field filters grid.
- Import: "Import Files" (multi-select; PNG, JPEG, other common image formats). URL field ("paste an image address") + "Download" button.
- Assign to item: Manager -> Items -> row's custom icon control -> Set from File | Import from URL | Choose from Library | Clear Custom Icon (revert).
- Link, Finder, Folder Stack, App Stack widgets expose their own custom icon option inside widget settings.
- Non-destructive: never modifies the real app/file on disk.
- Delete in-use icon: lists affected items, confirm with "Remove & Delete" (clears references, restores defaults, deletes stored file). Delete unused icon: simple confirmation.
- Not stated: size limits, empty state, import/download error handling.

---

## Window Previews
Source: https://extradock.app/docs/v5/previews

- Settings -> Previews, master "Window Previews" switch (default OFF). Also toggled from menu bar. Other settings visible but disabled while off.
- Crash safeguard: if the app quits unexpectedly while Manager or Settings is open with previews on, previews are disabled at next launch; menu bar reports it and offers "Turn Window Previews Back On".
- Permissions: Screen Recording for thumbnails (Request Access / Open System Settings buttons in the section). Accessibility for some window actions.
- Window sources/filters:
  - Show only current Space's windows (checkbox, default OFF).
  - Include minimized windows (default ON).
  - Advanced -> Include hidden windows (default ON).
  - Excluded App Names (text list; exact name match, case-insensitive).
  - Window Title Filters (text entries; substring match, case-insensitive; hides matching windows).
- Sorting/timing:
  - Sort windows by: Most Recent First (default) | Alphabetical | By Creation Time | By Screen Position.
  - Show delay: Instant | Short (default) | Medium | Long | Custom (max 1 s).
  - Hide delay: Short (default) | Medium | Long | Custom (no max stated).
  - Keep panel open if app quits (default OFF).
  - Advanced -> Fade out: Off | Quick | Smooth | Custom.
  - Advanced -> Distance from dock: 4-32 pt.
- Size/layout:
  - Lock aspect ratio (16:10) (default ON; height derived from width).
  - Card width: Small | Medium (default) | Large | Huge | Custom 100-600 pt.
  - Max rows: 1-8, default 3. Max columns: 1-8, default 3.
- Appearance: Show app name (toggle) + App name style: Plain | Shadowed | Popover. Show window title (toggle) + Window title visibility: While Hovering | Always Visible. Plain window controls (removes capsule behind each card's traffic lights).
- Compact mode: Always use compact list (toggle). Auto-switch at N windows (0 = off, default 0). Compact row label: App Name & Title | Title Only | App Name Only. Compact row size: Extra Small ... Extra Large. Hide traffic lights in compact rows.
- Thumbnails: Capture quality Standard | Best.
- Fallback: no Screen Recording -> plain list of icon + title.
- Not stated: click actions inside cards, keyboard handling, zero-window behavior.

---

## Backup and Restore
Source: https://extradock.app/docs/v5/backup

Location Settings -> Backup.
- Full Backup:
  - Export: single archive, extension `.extradock5backup`; contains all docks, app settings, custom icons.
  - Import: adds backup's docks; a dock with the same identity replaces the existing one. Confirmation states counts of docks added vs replaced and warns app settings will be overwritten. A pre-import snapshot is saved ("Saved before an import"). Backups from a newer app version are rejected.
- Settings Only: "Export Settings" -> plain JSON of app-level settings (no docks). "Import Settings" overwrites app settings, docks untouched.
- Daily Backups: snapshot taken before the first config change each day; roughly one week retained (exact count not stated). List with per-row "Restore".
- Restore flow: Manager sidebar restore button opens full list = daily snapshots + "Saved before an upgrade" + "Saved before an import" + "Replaced by a restore". Confirm "Replace the current configuration?". Replaced state is saved too, so restores are reversible. Snapshots stored in a "Backups" folder (path not stated; presumably under Application Support/ExtraDock5).
- Automatic recovery on damaged config database at launch: latest daily backup -> pre-upgrade snapshots -> empty config.
- "Import from ExtraDock 4": re-runs v4->v5 conversion, replacing current docks; reads only v4 data.
- Implementation hint: config is a database (the docs call it a "configuration database").

---

## Integrations
Source: https://extradock.app/docs/v5/integrations

Location Settings -> Integrations. Three areas.
- Talk Integrations (local app-to-app, no pairing codes; lists connecting apps and access level):
  - DockFlow row status: Available | Not installed | Update needed | Multiple copies | Cannot verify app (signature). "Check Again" button. "Connect" button; approval persisted and restored after restarts.
  - Expandable row permissions: "See docks and whether they're showing" (always required); "Show and hide docks" (optional); "Receive updates when docks change" (optional).
  - Other signed Appit apps requesting access get an "Allow access to your docks?" panel listing requested scopes: "Allow" / "Don't Allow".
  - "Apps with access" list: Permissions (edit scopes), Remove (revoke; app may reconnect).
  - Dock hidden by DockFlow preset -> Manager notice.
- AI Assistants (MCP): local MCP server so assistants can configure the app. Named clients: Codex, Claude Code, Claude Desktop, Cursor, VS Code. Details on /docs/v5/ai-assistants (not in our list).
- Stripe (for Stripe Balance widget): "Open Stripe Dashboard" (create restricted read-only key) -> paste in key field -> "Save Key". Accepted prefixes rk_live_, rk_test_, sk_live_, sk_test_ (restricted recommended). Stored in macOS Keychain; sent only to Stripe. Shows last-updated time; "Delete Key". Widgets show "Connect Stripe" while no key.
- Core dock features need no network/integration.

---

## Dock Edit Mode
Source: https://extradock.app/docs/v5/edit-dock

- Enter: right-click dock or an item -> Edit Dock; or menu bar per-dock "Edit Dock" (enabled docks only; disabled docks can't be edited).
- Visuals: dashed outline around bar; minus badge on removable items; dock forced visible even if auto-hide; floating "Save" button beside the dock; context menu shows "Done Editing".
- Actions: minus badge removes (apps/files/folders immediately; widgets confirm since settings would be lost); drag off dock to remove; drag to reorder; drop from Finder at insertion point to pin. Clicking items does nothing. Apps provided by Live Dock / Running Apps / Space Awareness widgets are not draggable.
- Exit: Save button, Done Editing, Esc, or Return (when no ExtraDock window has key focus). Changes apply live; no undo on exit.
- Locked-mode drop behavior: file on app = open with app; file on folder = move into folder; on Trash / Shelf / App Stack = send there; on gap / plain file / non-accepting item = refused with hint "Right-click › Edit Dock to add items." "Remove from Dock" from item menu confirms.
- Manager Items section works regardless of edit mode.

---

## Replace the Native macOS Dock
Source: https://extradock.app/docs/v5/native-dock

- Enable via Settings -> General -> Deep-hide native macOS Dock. On enable: save the native Dock's current prefs, apply a "deep" auto-hide to the native Dock, prompt restart.
- Native Dock is hidden, not disabled. macOS can still reveal it at its physical screen edge and in Mission Control. Mitigation: move native Dock to an edge ExtraDock doesn't use ("Open Desktop & Dock Settings").
- Prep checklist: Native Dock Copy for apps; Live Dock widget for running apps; ensure dock reachable with auto-hide settings; test window actions and badges; keep a way to reopen Manager/Settings.
- Bottom Notch placement unavailable while native Dock is active.
- Disable -> restore the saved native Dock settings.

---

## Multiple Displays
Source: https://extradock.app/docs/v5/multi-display

- Display choice (Screens) is independent from on-screen placement (Position).
- Steps: select dock -> Screens -> Show on All Screens, or enable displays under Known Screens -> Position -> pinned/floating -> drag a floating dock on a display for a display-specific position.
- Mirroring: on every display; assignments kept but inactive; turning off restores them.
- Multiple assigned displays without mirroring: shows on one matching display at a time.
- Disconnect: identity and assignments retained for reconnection. Hardware/adapter/macOS changes may make a known display look new -> fix with Choose Display, Merge, Rename, Forget Screen.
- Troubleshooting: export screen diagnostics.

---

## Auto-Hide and Collapse
Source: https://extradock.app/docs/v5/auto-hide-and-collapse

- Auto-hide (Behavior): see Behavior page. Pinned = edge reveal; floating = local reveal area.
- Hide on Window Hover (default OFF), exclusive with Reserve space.
- Hide when a fullscreen app is active (default ON); Show at screen edge while hidden (pinned only).
- Collapse (Style section, "Bar" group):
  - Collapse bar (toggle): folds dock to a handle. Toggle by clicking handle, or right-click menu "Collapse" / "Expand".
  - Button position: Auto | Start | Center | End.
  - Button style: Arrow | Symbol (any SF Symbol) | Text (1-5 chars) | None (background-only handle).
  - Button color (color picker).
  - Expand using: Click only | Handle only | Entire dock | Automatic (last three are hover-based).
  - Hover modes add: Expand after, Collapse after (delays; values not stated), Extra hover area (optional).
- Collapsed state persists across relaunch. Collapse is independent of auto-hide reveal area. Floating dock can show drag handle and collapse handle simultaneously.
- Notch layout uses its own idle-mode instead.

---

## Notch Layout
Source: https://extradock.app/docs/v5/notch-layout

- A layout that attaches to an edge, can fold to a small pill and unfold on pointer approach. Always pinned. Multiple notch docks per screen allowed at distinct positions.
- Enable: Manager -> Style -> Layout = Notch; configure Notch, Background, Size & Spacing; then Position -> Notch Position.
- Style -> Layout: Dock | Notch.
- Style -> Notch -> "When idle":
  - Show: always open.
  - Pill: folds to a small tab on the edge. Sub-settings: Expand using (options not listed; likely mirrors collapse "Expand using"), Expand after (delay), Fold after (delay).
  - Hidden: slides off-edge, returns on edge touch. Sub-settings: Hide after, Reveal after.
  - Default idle mode not stated.
- Style -> Background (notch): Black (default; blends with camera housing) | Color (custom fill; icon/text auto-switch light/dark for contrast) | Blur (Intensity: Lightest ... Darkest) | Liquid Glass (open only; black when folded; macOS 27+, labeled "Liquid Glass (Beta)"; folding may stutter). Dock-layout background stored separately and preserved.
- Style -> Size & Spacing: "Bar thickness" relabeled "Notch depth" (range/default not stated).
- Position -> Notch Position: 4 edges x 3 spots. Top center merges with the camera notch and extends over the menu bar. Top corners sit just below the menu bar. Dot marks spots used by other notch docks. Position changes animate fold -> move -> unfold; instant with Reduce Motion.
- Bottom-edge notch requires Deep-hide native macOS Dock.
- While Notch is active: full-width, floating, desktop-widget, ordinary auto-hide hidden/not applicable; magnification disabled.
- Switching to Notch: pins dock, removes full width and edge gap, disables magnification and desktop-widget mode, clears effects and border. These are NOT restored when switching back to Dock.
- States: Open, Pill (folded), Hidden; animated transitions except Reduce Motion.

---

## Shortcuts and Gestures
Source: https://extradock.app/docs/v5/shortcuts-and-gestures

- Per-dock global hotkey (Behavior -> Toggle with keyboard shortcut -> record). Must include at least one modifier. Esc cancels recording; Delete clears. Pressing the shortcut of a disabled dock enables it. Shared shortcuts toggle all sharing docks. Hide again after: 15 s | 30 s | 1 min | Custom, timed from the reveal. macOS rejection -> reported, retried.
- Click on frontmost app: None | Minimize | Hide | Cycle Windows (new-dock default Cycle Windows).
- Modifier-click / scroll gestures: Settings -> Behavior "Enable click gestures" / "Enable scroll gestures" (both OFF by default). Cmd, Option, Option-Cmd, Shift, middle click. Control-click always = context menu.
- Per-item overrides: item right-click -> Gestures submenu. Per combination: "Inherit default" or a specific action. Files/folders: only Do nothing or Reveal in Finder. If global toggle off, submenu offers "Enable Click Gestures" / "Enable Scroll Gestures".
- Edit Mode: Esc exits; Return exits when no ExtraDock window focused.
- Other keys: Cmd-, opens Settings; Cmd-F focuses Widgets Library search; Return in that search adds the widget when exactly one result.
- App Intents (Shortcuts app / Spotlight / Siri): Show Dock, Hide Dock, Toggle Dock, List Docks. Dock parameter = enabled docks (or typed name). Changes are temporary (reset on relaunch); hide persists until something shows. Run in background without opening the app. Fail until license check passes.
- Focus filter "Configure ExtraDock": parameters Docks to Show, Docks to Hide (enabled docks by name). Case-insensitive name match; applies to all enabled docks with that name. On Focus start: shows first, then hides. Current Focus reapplied at launch. On Focus end: nothing restored.
- Accessibility needed for window-control gestures and cycling.
- URL schemes: not documented.

---

## Diagnostics
Source: https://extradock.app/docs/v5/diagnostics

- First attempt hit a connection reset; the single retry succeeded.
- Location: Settings -> Support -> Diagnostics. Exports are saved to a user-chosen location, never auto-sent.
- Export Performance Diagnostics: ~10 s capture of CPU, memory, wakeups + relevant logs; start while the problem is happening.
- Export All Dock Diagnostics: one text file with settings + runtime state for every dock; omits item paths, custom item names, network addresses, window titles; records what last turned off/hid each dock (e.g. DockFlow preset, Focus filter). Single-dock variant: Manager sidebar right-click -> "Export Dock Diagnostics".
- Export Screen Diagnostics: JSON of screen-identity decisions and display layout snapshots (also in each dock's Screens section).
- Export Logs: last day of app logs (incl. widget logs); "Software updates" section with last 3 days of update activity (username/home path scrubbed); app's own crash reports from last 3 days; note on how the previous session ended. Same file from menu bar "Export Logs".
- Reports may contain dock and display names. Support: support@appitstudio.com.
- No verbose-logging toggle documented.

---

## Widgets (overview)
Source: https://extradock.app/docs/v5/widgets

- Widget index: Clock; Link; Finder; IP Address; Spacer and Divider; Label; Folder Stack and App Stack; Shelf and File Shelf; Live Dock and Running Apps; Space Awareness; Trash; Battery / CPU Usage / Memory Usage / GPU Usage; Bluetooth Battery; Clicker / Timer / Metronome; TamaDocky; Stripe Balance.
- Library categories (sidebar): All Widgets, Apps, Folders, Finance, Clocks, Tasks, System.
- "Virtual Trash" widget removed from library; existing instances keep working.
- Adding: Items -> Add to Dock -> "Widgets…". Click a card to add. Link, Folder Stack, App Stack, Stripe Balance, Bluetooth Battery open a setup panel before adding. Library card right-click: "Configure and Add". Cards can be dragged onto a dock (except setup-panel widgets). Monitor Dock bulk-adds CPU, Memory, GPU, Battery, IP Address, Bluetooth Battery (skips present ones).
- Instance limits: most widgets multi-instance; Live Dock and Trash one per dock. Present widgets labeled "Already in this dock". Non-addable card shows a small badge; clicking it explains why.
- Configure: Items row settings control, or dock context menu "Widget Settings…". Settings are per instance.
- Remove: dock context menu "Remove Widget" (confirms).
- Library UI: category sidebar; cards with live previews; "Search widgets" field filters by name or category (Cmd-F focuses; Return adds sole match); hover shows short description.
- Some widgets gated by permission, entitlement, connected service, or rollout; stored widgets stay represented while unavailable.
- Widgets live in a "widget cell" grid system (from Clock page); a widget requests a cell span.

---

## Clock Widget
Source: https://extradock.app/docs/v5/clock-widget

- Shows time and optional date; normally spans 2 cells; its requested size can grow an auto-sized bar.
- Settings:
  - Time format: 12-hour | 24-hour (default not stated; likely system).
  - Show seconds (default OFF).
  - Show date (toggle). Date style: None | Short | Long | Custom. Custom date format (free-form pattern string).
  - Show time zone (toggle). Time zone: System (follows Mac) | fixed GMT offsets | named zones.
  - Font: System | Monospace | Rounded. Type size (range not stated). Time weight: Regular ... Bold. Text color. Background (optional color). Background corner radius (when background set).
  - Click action: None | Open Date & Time Settings | Open Widget Settings.
- Digital only per docs (no analog variant documented).

---

## Link Widget
Source: https://extradock.app/docs/v5/link-widget

- Opens a web URL from the dock (v4 "URL widget").
- Setup panel: URL (scheme omitted -> https:// prepended); Title (optional); Show title (label under icon); Icon source: Website icon (site favicon) | SF Symbol (+ Icon color, Background) | Custom icon (URL) (+ Custom icon URL field) | Custom icon (file) (+ Custom icon file picker).
- Items list subtitle shows destination host.
- With magnification on, Link keeps its size and shifts aside for magnified neighbors.
- Imported links should be treated as untrusted until reviewed.

---

## Finder Widget
Source: https://extradock.app/docs/v5/finder-widget

- Stand-in for the native Dock's Finder icon. Primary click raises Finder / restores minimized windows, following the dock's "Clicking the active app" setting; opens a window at the configured location when needed.
- Settings: Location: Home | Documents | Downloads | Desktop | Applications | Custom path (default not stated); Running indicator (toggle); Custom icon (picker; "Use Default" restores Finder icon).
- Context menu: "New Finder Window" (opens at configured location).
- Does not magnify (keeps size, like Link).

---

## IP Address Widget
Source: https://extradock.app/docs/v5/ip-widget

- Shows public and/or local address with copy action.
- Settings: Mode: Public (internet) (default) | Local network | Both. Local adapters: multi-select (default none = primary active adapter). Show address (toggle). Show icon (toggle). Icon symbol (SF Symbol picker). Font. Text size. Selectable (copy) toggle. Defaults for toggles not stated.
- Refresh fixed: local every 30 s; public every 5 min. Public lookup needs internet (service unnamed). "Copy address" button.
- Adapters (Wi-Fi, Ethernet, virtual) may appear/disappear; VPN/proxy changes public address.
- Not stated: IPv4 vs IPv6, offline/loading states.

---

## Spacer and Divider
Source: https://extradock.app/docs/v5/spacer-and-divider

- Spacer width: Quarter (1/4 icon, default) | Half | Single (1 icon) | Double (2 icons) | Custom (points; range not stated).
- Divider: Line color (default not stated); Space on each side (gap to neighbors); line spans the bar's cross axis in both horizontal and vertical orientation.
- Both reorderable in Items; dimensions count toward cell layout and can change auto bar thickness. Use Label widget for text.

---

## Label Widget
Source: https://extradock.app/docs/v5/label-widget

- Static text between items. Edit via dock right-click -> "Widget Settings…".
- Settings: Title (text); Subtitle (optional smaller 2nd line); Length (24-1200 pt along dock axis; overflow truncated); Vertical text on side docks (reads bottom-to-top on left/right docks; ignored on horizontal and notch); Text size: Small | Medium | Large (scales with dock thickness); Alignment: Left | Center | Right; Text color (system light/dark default, or custom).
- Click does nothing; does not magnify. Defaults otherwise not stated.

---

## Folder Stack and App Stack
Source: https://extradock.app/docs/v5/folder-widgets

- Both open a setup panel on add; both suppress the generic widget context menu on the dock; settings via Items list.
- Folder Stack: one dock icon grouping one or more source folders. Popover lists one entry per folder (not their files); selecting opens that folder. Fields: Folders (1+); Layout: List | Grid; Custom name; Always show name; Icon tint (color); Custom icon file; Open folders with (optional app path). Clicking with no folder configured opens its settings (empty state).
- App Stack: curated list of apps/files/folders behind one item. Fields: Items (add/arrange entries); Stack name; Color; Grid density: Comfortable | Compact; Grid size (unspecified); Icon style: Icon view | Folder view; Show name; Custom icon ("Use Default"). Accepts file drops even when dock is locked.
  - Open stack click: default single-click selects, double-click opens; "Open items with a single click" toggle makes single-click open.
  - Legacy mode (older configs): single Folder + On click action.
- Context menu inside open App Stack: Remove from Stack; Rename Stack…; Move to Trash… (last; always confirms; hideable via Settings -> Behavior).
- Dock item context menu: "New App Stack with" (creates stack in that item's slot); "Add to App Stack" (moves item into an existing stack).
- Folder access may prompt macOS; moved/unavailable folder -> reselect in settings.

---

## Shelf and File Shelf
Source: https://extradock.app/docs/v5/shelf-widget

- Shelf: holds COPIES in one app-wide collection shared by all Shelf widgets (live-synced). Stored locally, restored on launch, no item cap.
  - Drop files on it; click opens panel; drag out from panel. Item right-click: Open; Reveal in Finder; Remove from Shelf. "Clear All" (confirms).
  - Settings: When files are dropped: Copy (default, originals kept) | Move (originals removed). After dragging out: Keep (default) | Remove (only when drop lands outside the Shelf; cancelled drag keeps it). Show item count badge (default not stated). Icon color.
- File Shelf: holds REFERENCES to files and folders; separate list per widget; originals never touched.
  - Drop to stage; drag out of tile; click opens gallery with search field. Item right-click: Open; Reveal in Finder; Copy; Copy Path; Remove from Shelf. "Clear Shelf" (confirms, refs only).
  - After dragging out: Keep after drag out (default) | Remove after drag out | Ask every time.
  - Missing/moved file shown as "Missing file".
- All content stays on the Mac.

---

## Live Dock and Running Apps
Source: https://extradock.app/docs/v5/running-app-widgets

(First attempt connection reset; retry succeeded.)
- Live Dock: shows the native macOS Dock's apps and spacers plus running apps not pinned there; skips uninstalled apps; does not mirror native Dock files/folders (use Native Dock Copy). One per dock. Needs Accessibility to read exact native order; without it, rough order (pinned first) and still shows running apps.
- Running Apps: running apps not pinned elsewhere in the same dock; multi-instance; taskbar-style use.
- Settings sheet from Items list or context menu "Live Dock Settings…" on any app they show:
  - Shared: Space between icons (dock-wide). Badges follow dock badge setting.
  - Live Dock only: Show running indicator dots (dock-wide).
  - Running Apps only: Show apps with no windows (off hides windowless apps).
  - Hidden Items (both): apps removed via context "Hide from Live Dock"; "Show" per row; "Show All Items".
- Related: Settings -> Behavior exclusions/indicator color/attention style; dock Behavior badges; Previews.

---

## Space Awareness Widget
Source: https://extradock.app/docs/v5/space-awareness-widget

- "Display" setting picks one of two modes. Does not control which Space the dock is on.
- Mode 1, Current-Space apps: apps with windows on the current Space of that display.
  - Icon spacing; Left click: Move Window to Front | Minimize / Restore; Dim minimized apps (toggle); Hidden apps list.
  - App right-click: "Hide from this widget"; "Unhide all".
  - Badges follow dock setting. Accessibility may be needed for full window info.
- Mode 2, Space indicator: Indicator style: Dots (one per Space) | Number ("3 / 5"). Dots auto-switch to number when more than 7 Spaces.

---

## Trash Widget
Source: https://extradock.app/docs/v5/trash

- Native Trash widget: one per dock. Auto-added at end of dock by "Replace my Dock", Native Dock Copy, v4 import.
  - Display: Trash Icon (default) | Stack Preview (recent items). No count badge; empty confirmation is always on (not a toggle).
  - Click: opens an in-app Trash window. Drop files: move to Trash (works when locked). Drop a removable volume: eject.
  - Trash window: "Search Trash" field; Sort menu by date | name | size | kind; "Empty Trash" button.
  - Per-file context menu: Open; Show in Finder; Delete Immediately; Empty Trash.
  - Always confirms with "Empty Trash?".
  - Needs Automation (Finder). First add: explanation dialog -> "Continue" (macOS prompt) or "Add Without Trash" (shown as "Not Now" in the library). Previously denied: button opens System Settings. Later: widget context menu "Allow Finder Access".
- Legacy built-in Trash item (pre-5.2.1 docks): click opens Trash in Finder; menu Empty Trash, Open in Finder; Trash Options: Ask before emptying (ON), Show item count (ON). Without Automation, emptying opens the folder for manual emptying.
- Virtual Trash (retired from library): existing instances still store dropped files in the app's own storage, can be opened and emptied.
- v4 migration: native mode -> Trash widget at same position; virtual mode -> Virtual Trash (starts empty). Unsupported v4 options listed in the import report.
- Note: a "Replace my Dock" action is referenced here (probably an onboarding/starting-point flow); not documented elsewhere in our page set.

---

## System Monitor Widgets (Battery, CPU Usage, Memory Usage, GPU Usage)
Source: https://extradock.app/docs/v5/system-monitor-widgets

- Add individually or via Monitor Dock (CPU, Memory, GPU, Battery + IP Address + Bluetooth Battery; skips duplicates).
- Battery: Mac battery state; bolt when charging; tooltip with details such as time to full; desktop Macs show a "No battery" state.
- CPU Usage / Memory Usage: current utilization.
- GPU Usage: utilization when macOS/hardware provide a reading; otherwise an "unavailable" state (never estimated).
- Shared settings:
  - Color: Automatic | Fixed (+ Fixed color). Automatic: CPU/Mem/GPU green -> amber -> red as value rises; Battery reversed (red low -> green high). Thresholds not stated.
  - Show label (toggle). Number size.
  - Refresh rate: Fast | Normal (default) | Relaxed | Power Saver; overall span 1 s to 10 s (per-preset intervals not stated; plausibly 1/2/5/10 s).
- CPU/Mem/GPU only: Text color: Automatic | White | Black | Custom.
- Sampling shared across all visible instances (one sampler, many views).
- Not stated: graph/gauge styles, per-core, click/popover behavior.

---

## Bluetooth Battery Widget
Source: https://extradock.app/docs/v5/bluetooth-widget

- Charge + connection status for Bluetooth accessories reported by macOS (keyboards, mice, headphones).
- Permission flow: on first add may show "Improve Bluetooth Battery Accuracy?" -> enable or "Not Now" (fallback to basic macOS data). Later: settings "Enable Bluetooth Access"; if denied, shortcut to Bluetooth privacy settings.
- Setup panel opens on add:
  - Device visibility: Show: Connected only | Include offline (offline dimmed). Include devices with no battery (toggle). Maximum devices: 1-12. Hidden devices list; hide via dock right-click "Hide from This Widget"; restore with "Show All Devices".
  - Split AirPods into L / R / case (toggle).
  - Appearance: Layout: Icon + percent | Icon + bar | Icon only. Color (background). Text color. Number size. Spacing.
  - Behavior: Low battery below (threshold; default not stated). Click action: Open Bluetooth settings | Refresh now | Do nothing. Refresh rate: Fast | Normal (default, every 1 min) | Relaxed | Power Saver; overall 30 s - 15 min.

---

## Clicker, Timer, Metronome
Source: https://extradock.app/docs/v5/productivity-widgets

- Each instance has independent settings and live state.
- Clicker (tally counter): click adds "Step per click". Context menu: Decrease (only if "Allow decrease" on); Reset to Zero (confirms). Settings: Step per click; Allow decrease; Show caption + Caption; Chip color; Number color; Number size.
- Timer (countdown shown as a ring): click starts; click again stops and resets. Context menu: Start / Restart (state-dependent). Settings: Duration: 5 | 10 | 15 | 25 | 60 min | Custom (Minutes 1-180 integer). Default 5 min. Play a sound when it finishes; Sound (list not stated); Keep chiming until stopped; Show a caption under the time + Caption; Accent color; Time size.
- Metronome: click toggles playback. Context menu: Start; Stop. Settings: Tempo (BPM); Tap Tempo; Beats per measure; Subdivision; Sound; Accent first beat; Volume; Show BPM label; Accent color; Background. Ranges/defaults not stated.

---

## TamaDocky Widget
Source: https://extradock.app/docs/v5/tamadocky-widget

- Animated virtual pet living in a dock.
- Settings: Pet name (text); Size: Regular (1 cell) | Medium (2 cells) | Large (3 cells); Tamagotchi stats (toggle): enables happiness, hunger, energy.
- Click = pet it. Context menu: Feed; Play with; read-only stat readout (happiness, hunger, energy).
- Stats evolve only while the pet is visible; pause when hidden, Mac asleep, or screen locked. Persisted across restarts.
- Animation runs only while visible; slowed under Reduce Motion.
- May clip (especially with magnification); fix with larger size or thicker bar.
- Not stated: decay rates, evolution, death/reset.

---

## Cross-page summary and open gaps

- Pages fetched: 42 of 42 (Style succeeded on a later read).
- Referenced but not in our list: /installation, /migrate-from-v4, /ai-assistants, /license, /stripe-widget.
- Permissions: Accessibility; Screen Recording; Bluetooth; Automation (Finder); per-resource file access (security-scoped). Login item approval for Launch at login. Keychain for the Stripe key.
- Licensing gates: creating docks, Shortcuts actions, and the menu bar menu (reduced while license unconfirmed).
- System integrations to build: App Intents (Show/Hide/Toggle/List Docks), Focus filter, local MCP server, app-to-app "Talk" IPC for DockFlow, update channels (Stable/Beta).
