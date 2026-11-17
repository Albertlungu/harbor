# Wallpapers: source and licence decisions

Research for the wallpaper browser (seasonal collections plus a searchable 4K library).
Checked November 2026 against each service's own docs and terms; endpoints were also
queried live.

## Sources compared

| source | key | limits | search and size filters | licence for an app | verdict |
| --- | --- | --- | --- | --- | --- |
| Wallhaven API v1 | none for safe-for-work | 45 calls/min, 429 past that | free text with +/- tags, minimum size (`atleast`), exact sizes, ratios, a fixed colour palette, sort by relevance, top list, date, random (seeded) | none granted; images stay their owners' property | primary source |
| Unsplash | access key in every request | 50/hour demo, 1,000/hour after approval | text, orientation, colour; no pixel-size filter | Unsplash Licence; must hotlink, credit photographer and Unsplash on every display, and call the download-tracking URL on every download or set | best licence, but a shipped key and per-display credit rules |
| Pexels | key in every request | 200/hour, 20,000/month | text, orientation, colour, megapixel tiers | free use, but the API terms name wallpaper apps as an example of copying Pexels' core function | ruled out |
| Wikimedia Commons featured pictures | none | none published; serial requests and a descriptive User-Agent expected | no size filter in search, only per-file metadata | per file (CC BY, CC BY-SA, public domain); attribution and licence per image | possible secondary, needs per-file licence handling |
| NASA Image and Video Library | none for images-api.nasa.gov | not published | text only | mostly US public domain; insignia and third-party images excluded | possible secondary, space imagery only |
| Bing daily image | unofficial endpoint | unknown | date only | restricted to Microsoft's own wallpaper use | ruled out |

## Decision

Wallhaven is the only source that offers search, a minimum-resolution filter (so "4K and
up" is one parameter), aspect ratios, colours and seeded random paging with no key. That
fits a free app with no account or backend.

- Purity is always `100` (safe for work only). It is hard-coded, not a setting, and
  requests never send an API key, so other levels are impossible anyway.
- The library searches the General and Anime categories; People is left out. Seasonal
  collections search General only, which keeps them to landscapes and scenery.
- No secondary source shipped. Commons and NASA would each need their own licence and
  credit display per image. That is worth adding only if users ask for a "free to reuse"
  filter.

## Obligations we take on

- Wallhaven grants no licence for the images. Uploads stay their creators' property. We
  therefore position the feature as "use as your own wallpaper", show a source link to the
  Wallhaven page (and the uploader's original source when given), and say in the
  detail panel and in Settings that images belong to their creators.
- No redistribution: Harbor never re-hosts or bundles images. It fetches thumbnails from
  Wallhaven's CDN and full images only when the user sets or downloads one.
- Rate limit: about 45 searches a minute is plenty for one user, given a debounced search
  field and a page of 24 per call. A 429 shows a "slow down" message instead of retrying.
- A plain `Harbor/0.1` User-Agent; no user details are sent.

## Efficiency notes

- Thumbnails: the `lg` thumb (about 432 by 243 px, 7 to 30 KB) serves both grid and preview,
  so selecting a tile costs no extra fetch. It is decoded with ImageIO to at most 520 px.
- The fetch limit is four connections per host; queued requests drop when their tile
  scrolls away (SwiftUI cancels the tile's task).
- Disk cache: files in Caches/Harbor/WallpaperThumbnails, trimmed by last use to 150 MB
  when the window closes. The memory cache is an NSCache (300 images) that is emptied on close.
- Closing the window frees the whole browser. "Change with the seasons" runs once a day,
  at launch and on wake, with no timer.

## Seasons

Meteorological, northern hemisphere: Dec to Feb winter, Mar to May spring, Jun to Aug
summer, Sep to Nov autumn. Wallhaven has no OR operator, so each season is a list of
themes (for example "autumn forest", "fall foliage", "misty forest") shown as chips. Each
one returned between about 100 and 1,500 results at 4K and up when checked.
