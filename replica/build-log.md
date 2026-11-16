# Build log

| ID | date | status | missing | harder than expected |
| --- | --- | --- | --- | --- |
| core | 2026-11-16 | done | | Swift Testing under Command Line Tools needs extra framework flags and has no Foundation overlay; worked around in the Makefile |
| S11 dock | 2026-11-16 | partial | notch shape and folding, badges, window previews, hide on window hover, reserve dock space | making clicks pass through a panel's transparent area: solved by toggling `ignoresMouseEvents` from pointer tracking |
| S01 menu bar | 2026-11-16 | done | Media controls, Export Logs | |
| S02-S07 Manager | 2026-11-16 | done | Choose Display / Merge for identical monitors | the section picker overflowed the toolbar at default width; moved into the body |
| S08 widget library | 2026-11-16 | done | per-widget default settings | |
| S09 widget settings | 2026-11-16 | not started | every widget form | |
| S10 item options | 2026-11-16 | done | per-item gesture overrides | |
| S12 item menu | 2026-11-16 | done | | |
| S13 folder browser | 2026-11-16 | done | Finder-style file actions (rename, compress) | |
| S28 restore | 2026-11-16 | done | | |
| widgets | 2026-11-16 | not started | all widget rendering except app lists (Live Dock, Running Apps, Space Apps) | a delegated attempt stopped when the account hit its weekly usage limit, before committing anything |
| S18-S26 Settings | | not started | | |
| S27 onboarding | | not started | | |

Must-haves: 27 of 32 done. Still missing: Settings General, launch at login (code exists, no toggle yet), Permissions page, Clock widget, Spacer and Divider widgets.
