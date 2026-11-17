# Seasonal desktop weather: what the snow apps do

Researched 2026-11-17. Claims come from each project's own page or README, not from running the apps.

## The apps

**Snowfall for Mac** (paid, $7.99, macOS 26, Apple silicon) - https://snowfallmac.com/
The polished one that went around online.
- Snow settles on windows, icons, the Dock, widgets and the menu bar. It slides off when a window or icon moves; closing a window dumps its snow.
- Hold and drag through snow: slow drags crumble it, sideways sweeps bank it, fast flicks throw it. Plain clicks pass through to the desktop.
- Snowballs roll onto the Dock and stack. A snowman builds itself on the Dock, puts on a scarf and waves; he throws snowballs at windows. Clicking him bursts one ball at a time; hitting the bottom drops him a level, hitting the middle tumbles his head. He melts (the carrot falls off) and another shows up later.
- Icicles grow under windows that stay still and snap off when the window moves.
- A snowplow periodically clears the Dock; "Send the snowplow" on demand.
- Settings: toggles for snowballs, snowplow, snowman, icicles, mouse pushing, snow on any surface; intensity Light/Normal/Blizzard. "Rests when idle", "easy on the battery".

**Snowpile** (free, MIT) - https://github.com/SergeiNikolenko/Snowpile
The most complete feature list, and the only one with other seasons.
- Settles on window tops, text fields, widgets, the Dock and the bottom of the screen; each Space keeps its own snow.
- The pointer brushes snow aside. Moving a window carries its snow; jerking it shakes it loose.
- Option-drag along a drift rolls a growing ball; click a drift to scoop one. Flick to throw; balls arc under gravity and splat on window sides and the Dock.
- Stack two or three balls for a snowman with carrot, coal eyes and buttons, twig arms. A thrown ball knocks a snowman over. Snowmen melt when the snow stops.
- Other effects: rain with lightning, sakura petals, autumn leaves (both settle on surfaces), fireflies, shooting stars. "Like Outside" follows a city's live weather.
- Settings: effect picker, custom snow intensity and wind, per-display choice, where snow settles, pointer brushing.

**WinterIsComing** (free, MIT) - https://github.com/yike-shi/WINTER_IS_COMING
- Three depth layers of flakes in gentle wind; snow on window tops, the Dock and the screen bottom.
- Dragging a window throws its snow off, farther the faster you drag.
- Moving the mouse sideways over snow rolls a growing ball; balls push each other and fall off edges; hold the button to carry one. Three stacked balls become a snowman with carrot and scarf.

**Snow on Mac by KoiArt** ($9) - https://koiart.app/snow-on-mac
- Windows, Dock, widgets; builds up over time. Sweeping the pointer rolls balls that can be thrown; stack three for a snowman. A plow clears deep snow.
- Clicks pass through. Snow stops while a full-screen app is open. GPU-drawn, can pause on battery.

Also seen in search results only: Snow-Home, SnowHush (snow, leaves, rain, cherry blossom), SnowDesk (Metal, icicles, frost), Warm Mittens.

## What Harbor takes from them

Shared by all of them: flakes fall in wind over everything, settle on window tops and the Dock and the screen bottom, slide off when a window moves or closes, clicks pass through except on snow, roll a ball through a drift, throw it, stack three into a snowman with carrot, coal and twig arms, melt, intensity setting, stop in full screen, cheap on the CPU.

Harbor adds the other seasons on the same surfaces (autumn leaf litter you scatter and rake, spring petals with rain showers, puddles and flowers, summer fireflies, dandelion seeds and bubbles) and lets the roaming pet play in all of it.
