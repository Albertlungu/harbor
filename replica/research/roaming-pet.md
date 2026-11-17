# Roaming pet: decisions

Research summary for the pet's desktop mode. Sourced lessons are marked with their source;
everything else is a default chosen to test by eye.

## What the sources agree on

- Presence is fine; interruption is not. Clippy was hated for unsolicited pop-ups at the wrong
  moment, not for existing (Mental Floss; CIO). Desktop Goose was liked but crossed the line by
  stealing the cursor and blocking input (PC Gamer, GamesRadar).
- Always provide a floor. Shimeji mascots fall forever when no surface exists below them
  (Shimeji-ee community pages).
- Fast polling ruins battery. RunCat's roughly 4 wakeups a second kept Macs out of deep idle
  (ctrl.blog). Prefer events and slow rates when idle.
- Users expect to pick the pet up and drop it (eSheep), toggle it and resize it from the menu
  bar (ScreenPets), and choose which windows it may climb (Shimeji-ee).

## Decisions

| topic | decision |
| --- | --- |
| size | 32 pt default when roaming, user range 24 to 48 pt; the dock version keeps its cell size |
| walking speed | 45 pt/s default (calm), 70 pt/s lively |
| rest ratio | resting about half the time; walks of 2 to 6 s |
| falling | constant gravity, a small squash on landing, the screen bottom as the floor |
| surfaces | menu bar bottom edge, top edges of normal windows, dock tops, screen bottom |
| window polling | window list off the main thread at 2 Hz while walking, 0.5 Hz while resting, none while asleep |
| frame rate | the display refresh rate while moving (display link), no frames while still except blinks |
| clicks | only the pet's own shape takes clicks; everything else passes through |
| never | steal or block the cursor, cover the focused window's title bar, pop up uninvited, multiply |
| hide | in fullscreen apps, during screen sharing and recording (sharing type none), and while the screen is locked |
| recall | right-click "Bring it home", the menu bar menu, and dragging it back onto a dock |
| quiet | Personality quiet mode limits roaming to hanging out in place |
