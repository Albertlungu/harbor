# Harbor components

Native controls (Form, Toggle, Picker, Slider, ColorPicker, List) are used
as-is in the Manager and Settings and inherit macOS focus rings, keyboard
handling and VoiceOver. The specs below cover the custom pieces. Colors refer
to roles in `tokens.json` / `tokens.dark.json`; Swift mirrors them in
`Sources/Harbor/Design/Tokens.swift`.

```
DockBar
  variants  horizontal, vertical, notch (later)
  states    normal, edit (dashed 1.5pt accent outline, minus badges), collapsed,
            auto-hidden (offscreen; reveal strip stays), magnified
  tokens    background glass | blur | solid(dock-solid) | none, radius by preset,
            optional border, shadow dock
  a11y      panel never takes key focus; each item is an accessibility button

DockIcon
  variants  app, file, folder, widget (1-3 cells)
  states    default, hover (magnify + label pill), pressed (dim 0.7),
            running (indicator dot), badge, launching (bounce), hidden-in-edit (dim 0.4)
  tokens    indicator, label-bg/on-label, badge/on-badge, type label/badge
  a11y      label = item name, value = "running" when running, actions: open, menu

LabelPill
  tokens    label-bg, on-label, type label, radius 6, padding 4x8
  shows     on hover, or always when "always show label"; above icon on bottom edge,
            beside icon on side edges, below on top edge

Badge
  tokens    badge, on-badge, type badge, min 16pt circle, "99+" cap unless full number

SpotPicker (12 positions)
  layout    screen-shaped rectangle 160x100, three spots per edge
  states    default, hover, selected (accent fill), used-by-other (dot), disabled
  a11y      a radio group; each spot labeled "Bottom, center" etc.

PresetPicker (segmented + custom)
  used for  icon size, thickness, spacing, gap, delays
  states    preset selected, custom selected (reveals slider/stepper with range)

SidebarDockRow
  shows     name, placement summary or "Hidden by <source>", item count, eye toggle
  states    selected, disabled (secondary text), dragging
  menu      Rename, Enabled, Duplicate, Delete, Copy Settings, Paste Settings

ItemRow
  shows     icon, name, kind subtitle, drag handle, options button, eye, minus
  states    hidden (dim, "Hidden" tag), dragging

Banner
  variants  info (accent), warning (warning), error (danger)
  shows     icon, message, one action button
  used on   Manager sections

WidgetCard
  shows     live preview, name, one-line description
  states    default, hover, already-in-dock (tag), locked (badge + reason popover)

Popover panels (folder browser, stack, shelf, trash)
  tokens    radius popover, shadow popover, system material background
  states    empty (centered message + hint), filled, no-access (button to grant)
  keys      arrows move, Space Quick Look, Return opens, Esc closes
```

Motion: reveal/hide slides along the edge axis over `motion.reveal`;
magnification follows the pointer without animation lag; under Reduce Motion
slides become crossfades and bounce is disabled.

Icons: SF Symbols (system-provided, licensed for use in macOS apps) for all
chrome. No artwork from the original app is used.
