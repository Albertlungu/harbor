# Recon map: ExtraDock 5 (macOS 26+)

Scope: every publicly documented ExtraDock 5 feature that does not depend on
Appit Studio's own services, sister apps, or licensed data.
For: Harbor (working name), an open-source multi-dock app for macOS.
Date: 2026-11-16

Clean-room rules applied: public pages only. No binary decompilation, no
reading of app bundles, no network capture. Everything below is paraphrased
from the public docs and changelog. Detailed per-page notes are in
`research/docs-v5-notes.md`.

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | docs (v5, 42 pages) | https://extradock.app/docs/v5 | the spec; see research notes |
| 2 | changelog | https://extradock.app/updates | v1.36 to v5.2.4; shows what got bug reports |
| 3 | marketing site | https://extradock.app/ | feature groups, positioning |
| 4 | pricing | https://extradock.app/pricing | one-time licenses, EUR 14.99 to 99.99 |
| 5 | use cases | https://extradock.app/uses | nine jobs-to-be-done |
| 6 | terms | https://extradock.app/terms-and-conditions | code and design protected; reinforces clean-room |
| 7 | roadmap | https://extradock.app/roadmap | empty |

No App Store listing (direct download). No user account was used.

## Core loop

Create a second (or third) dock, put it on the edge or screen you want, and
fill it with apps, folders and widgets that stay visible everywhere.

## Screens

| ID | screen | route / how to reach | purpose | key components | states seen |
| --- | --- | --- | --- | --- | --- |
| S01 | Menu bar menu | status item | global actions, per-dock submenus | menu, submenus, toggles | no docks, permission needed, previews auto-disabled |
| S02 | Manager, empty | menu bar > Open Manager, no docks | first dock creation | sidebar, empty-state button | empty |
| S03 | Manager > Items | select dock | list, reorder, add, hide, remove items | sidebar rows, item rows, add menu, cards | empty dock (cards), filled, item hidden, a11y banner, dock-hidden banner, save-failed banner |
| S04 | Manager > Style | section tab | layout, bar, size, icons, background, border, effects, magnification, themes, collapse, notch | segmented pickers, sliders, color wells, toggles | dock layout, notch layout (reduced sections) |
| S05 | Manager > Position | section tab | pinned vs floating, 12-spot picker, gaps, padding, drag handle, desktop mode | spot picker, steppers | pinned, floating, notch (spots used marked) |
| S06 | Manager > Screens | section tab | show on all screens, assigned screens, known screens | screen list, status pills | connected, not connected, needs attention, possible duplicate |
| S07 | Manager > Behavior | section tab | auto-hide, visibility, window hover, reserve space, active-app click, badges, shortcut | toggles, pickers, shortcut recorder | notch (no auto-hide), floating (no reserve), app-wide reserve off notice |
| S08 | Widgets Library | Items > Add > Widgets | browse and add widgets | category sidebar, search, preview cards | already in dock, locked, search no results |
| S09 | Widget settings sheet | item row gear, dock menu | per-instance widget settings | form per widget type | setup-on-add, normal |
| S10 | Item options / custom icon | item row button | label, extension, folder click, browser layout, icon | form, icon menu | app, file, folder |
| S11 | Dock (on screen) | always | the product | bar, items, labels, indicators, badges, handle, collapse button, effects | normal, edit mode, collapsed, auto-hidden, notch open/pill/hidden, desktop-widget, magnified |
| S12 | Dock item context menu | right-click item | item actions | menu | app running/not, folder, file, Chromium browser, widget |
| S13 | Folder browser | click folder | browse folder beside dock | grid, list, fan, Quick Look | empty folder, no access |
| S14 | App Stack / Folder Stack popover | click stack | open grouped items | grid, list | empty stack opens settings |
| S15 | Shelf panel / File Shelf gallery | click shelf | staged files | tiles, search | empty, missing file |
| S16 | Trash window | click Trash widget | browse and empty Trash | list, search, sort | empty, no Finder access |
| S17 | Window previews | hover running app | window thumbnails | cards, compact list | no Screen Recording (list fallback) |
| S18 | Settings > General | Cmd-, | startup, presentation, native Dock, updates, appearance | form | restart prompt |
| S19 | Settings > Behavior | Settings sidebar | app-wide folders, dragging, reserve space, running apps, gestures, privacy | form | no Accessibility |
| S20 | Settings > New Docks | Settings sidebar | defaults for new docks | form | customize off |
| S21 | Settings > Icon Library | Settings sidebar | imported icons | grid, search, import | empty, in use, delete confirm |
| S22 | Settings > Previews | Settings sidebar | window preview options | form | master off (disabled) |
| S23 | Settings > Permissions | Settings sidebar | permission status | rows with status and actions | granted, not granted, not determined |
| S24 | Settings > Backup | Settings sidebar | export, import, daily snapshots | buttons, list | no snapshots |
| S25 | Settings > Integrations | Settings sidebar | AI assistant (MCP) access | rows | not connected |
| S26 | Settings > Diagnostics | Settings sidebar | export logs and diagnostics | buttons | |
| S27 | Onboarding | first launch | permissions, starting point | pages | |
| S28 | Restore backup sheet | Manager footer | choose snapshot | list, confirm | none |
| S29 | Themes sheet | Style > Themes | save, apply, import, export | list | none saved |

## Flows

```
F01 Create a second dock with my apps
    S01 -> S02 (Create Dock) -> S03 (Add > Items, pick apps) -> S11
    happy path clicks: 5
    edge: no license gate in Harbor; picking a non-app file; empty name rejected

F02 Pin a dock to the right edge of the external display
    S03 -> S05 (Pinned, right-center spot) -> S06 (enable display) -> S11
    happy path clicks: 4
    edge: display disconnected (hide, return on reconnect), identical monitors

F03 Add a widget
    S03 -> Add > Widgets -> S08 (search "clock", Return) -> S11
    happy path clicks: 3
    edge: one-per-dock widget already present; setup-panel widgets

F04 Edit dock in place
    S11 right-click -> Edit Dock -> drag/reorder/drop from Finder/minus -> Save
    happy path clicks: 3
    edge: widget removal confirms; Live Dock apps not draggable; Esc exits

F05 Auto-hide a pinned dock
    S07 -> Hide automatically -> reveal at edge
    happy path clicks: 2
    edge: fullscreen app, reveal delay, top edge under menu bar

F06 Replace the native Dock
    S18 -> Deep-hide native Dock -> restart; S03 -> Native Dock Copy
    happy path clicks: 4
    edge: native Dock still appears in Mission Control; restore on disable

F07 Drop a file into a docked folder / shelf / trash / app
    Finder drag -> S11 item
    happy path clicks: 1 drag
    edge: name conflict (copy, never overwrite), no folder access

F08 Back up and restore
    S24 Export -> file; S28 pick snapshot -> confirm
    edge: newer-version backup rejected, damaged config at launch

F09 Toggle a dock with a hotkey
    S07 Record Shortcut -> press combo -> S11 appears/hides
    edge: shared shortcut toggles all, macOS rejects combo, hide-again timer

F10 Notch dock
    S04 Layout = Notch -> S05 Notch Position -> S11 pill/open
    edge: bottom requires deep-hide; switching clears effects and border
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Dock bar | horizontal, vertical, notch | normal, edit, collapsed, hidden, magnified | S11 |
| Dock icon | app, file, folder, widget cell(s) | hover, pressed, running dot, badge, bouncing, dimmed | S11 |
| Spot picker (12 positions) | pinned, notch | selected, used-by-other | S05 |
| Segmented preset picker + custom value | size, thickness, spacing, gap, delays | preset, custom | S04, S05, S07, S20, S22 |
| Sidebar dock row | | selected, disabled, hidden-by-source, dragging | S02-S07 |
| Item row | app, file, folder, widget | hidden, dragging | S03 |
| Banner | info, warning, error | with action button | S03-S07 |
| Widget card | normal, already added, locked | hover | S08 |
| Popover panel | folder grid/list/fan, stack, shelf, trash | empty, filled | S13-S16 |
| Shortcut recorder | | idle, recording, conflict | S07 |
| Color well, toggle, slider, stepper | | enabled, disabled | settings |
| Confirmation dialog | destructive, normal | | delete widget, empty trash, restore |

## Inferred data model

```
Dock       id, name, enabled, sortIndex, layout (dock|notch), style (Style),
           position (Position), screens (ScreenRules), behavior (Behavior),
           items [DockItem], perScreenPositions {screenID: Position}
           evidence: S03-S07 docs, duplicate/copy-settings rules
           confidence: high

Style      orientation, iconSize, barThickness, spacing, alwaysShowNames,
           cornerRadius, sidePadding, tint, background (glass|blur|solid|none,
           color, opacity, intensity), border (width, color), effects
           (snow, rays, fireworks, intensity), magnification (on, maxScale,
           falloff), collapse (on, buttonPosition, buttonStyle, color,
           expandUsing, delays), notch (idleMode, delays)
           evidence: Style page; confidence: high

Position   mode (pinned|floating), edge, alignment (start|center|end),
           fullWidth, edgeGap, offsetAlongEdge, padding, floatingOrigin,
           dragHandle (alwaysVisible, side), locked, desktopWidgetMode
           evidence: Position page; confidence: high

ScreenRules showOnAllScreens, assignedScreenIDs
KnownScreen id (stable hardware identity), displayName, customName, lastSeen
           evidence: Screens page; confidence: high (identity scheme: guess)

Behavior   autoHide (on, trigger, distance, hideAfter, revealAfter),
           showOn (allSpaces|activeSpace|pinnedSpace), hideInFullscreen,
           hideOnWindowHover, showAtEdgeWhileHidden, reserveSpace,
           activeAppClick (none|minimize|hide|cycle), badges (on, fullNumber,
           perAppRules), shortcut (keyCode, modifiers, hideAgainAfter)
           evidence: Behavior page; confidence: high

DockItem   id, kind (app|file|folder|widget), url/bookmark, customName,
           alwaysShowLabel, hideExtension, hidden, customIconID,
           folderOptions, gestureOverrides, widget (WidgetConfig?)
WidgetConfig type, settings (per-type JSON), state (counter, pet stats)
           evidence: Items + widget pages; confidence: high

Theme      id, name, style (Style)
IconAsset  id, filename, sourceURL?
ShelfItem  id, storedFileURL (Shelf copies) / bookmark (File Shelf refs)
AppSettings  general, behavior, newDockDefaults, previews, gestures, privacy
Snapshot   id, date, reason (daily|before-upgrade|before-import|replaced)
           evidence: Backup page; confidence: high (storage format: guess)
```

Relationships: AppSettings 1-n Dock, Dock 1-n DockItem, DockItem 0-1
WidgetConfig, Dock n-n KnownScreen, DockItem n-1 IconAsset, Theme 1-1 Style.

## Feature matrix

See `features.csv`. Must: 32, should: 40, could: 34, skip: 10.

## Out of scope (cannot or should not be cloned)

- Licensing, activation, device limits, Appit Services accounts.
- Talk Integrations with DockFlow / ExtraBar (their proprietary apps and IPC).
- Import from ExtraDock 4 (reading another product's data format).
- DockShare.io community gallery (their network).
- Stripe Balance widget (needs a paid third-party account; could later).
- World Cup widget (licensed live sports data; v4 only).
- Their artwork, icon library, TamaDocky character art, names and copy.
- Update channel infrastructure (we ship via GitHub releases instead).

## Size

Screens 29, flows 10, entities 11. Hard parts:

1. Window management through the Accessibility API: raising, cycling,
   minimizing windows across Spaces; Reserve Dock Space; fullscreen detection.
2. Stable multi-display identity and per-screen placement across sleep,
   reconnect and identical monitors.
3. Panel behavior: non-activating always-on-top panels that join all Spaces,
   auto-hide with edge tracking, magnification, notch shape over the menu bar.

Others: window previews (ScreenCaptureKit), native Dock mirroring (reading
Dock preferences), badges (no public API; Accessibility on the native Dock),
global hotkeys, MCP server.

Size: XL. Rescoped into phases:
- Phase 1: docks, Manager, Style/Position/Screens/Behavior core, apps/files/
  folders, persistence, menu bar, Edit Mode.
- Phase 2: widgets (clock, spacer, divider, label, link, finder, system
  monitors, IP, shelf, trash, stacks, running apps, live dock, productivity,
  pet), effects.
- Phase 3: notch layout, previews, badges, reserve space, backups, icon
  library, themes, gestures, App Intents, MCP.
