# Build log

| ID | date | status | missing | harder than expected |
| --- | --- | --- | --- | --- |
| core | 2026-11-16 | done | | Swift Testing under Command Line Tools needs extra framework flags and has no Foundation overlay; worked around in the Makefile |
| S11 dock | 2026-11-16 | partial | notch shape and folding, badges, window previews, hide on window hover, reserve dock space | making clicks pass through a panel's transparent area: solved by toggling `ignoresMouseEvents` from pointer tracking |
| S01 menu bar | 2026-11-16 | done | Media controls, Export Logs | |
| S02-S07 Manager | 2026-11-16 | done | Choose Display / Merge for identical monitors | the section picker overflowed the toolbar at default width; moved into the body |
| S08 widget library | 2026-11-16 | done | per-widget default settings | |
| S09 widget settings | 2026-11-16 | partial | forms for clock, spacer, divider, label and app-list widgets only | |
| S10 item options | 2026-11-16 | done | per-item gesture overrides | |
| S12 item menu | 2026-11-16 | done | | |
| S13 folder browser | 2026-11-16 | done | Finder-style file actions (rename, compress) | |
| S28 restore | 2026-11-16 | done | | |
| widgets | 2026-11-16 | partial | clock, spacer, divider, label and app lists done; 18 widgets still show a placeholder icon | a delegated attempt stopped when the account hit its weekly usage limit, before committing anything |
| S18-S26 Settings | 2026-11-16 | done | AI assistant integrations (MCP) | |
| S27 onboarding | 2026-11-16 | done | | the first launch on a new config can take a few seconds to show the window |

Must-haves: 32 of 32 done. Parity score 82 / 100 (replica-diff).

Next, in order: the remaining widgets (system monitors, Finder, Link, stacks, shelf, trash, IP, Bluetooth, productivity, pet), window previews, notch drawing, reserve dock space, badges, hide on window hover, gestures on the dock, App Intents and Focus filter, MCP server.
