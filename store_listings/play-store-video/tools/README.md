# Promo video tools

Build `../cosmo-strike-promo-landscape.mp4` (1920x1080, for the Google Play
listing via YouTube) and `../youtube-thumbnail-1280x720.png`. Adapted from
Snake Classic's `store_listings/play-store-video/tools/`. Raw recordings and
render scratch files are gitignored; record new ones into this folder.

## 1. Record

- Device: the Galaxy A24 (`RR8W901JDRL`, landscape 2340x1080). It's shared
  with other sessions: ask before using it, and never restart adb/tcpip.
- Install the demo build from the `demo/autopilot` branch (local only, never
  merge): `flutter build apk --release --dart-define=DEMO_AUTOPILOT=true`,
  then `adb install -r` (same signing key, keeps the signed-in data). The
  ship is invulnerable, steers itself onto targets, weaves through fire to
  graze, fires Overdrive when full and missiles at bosses, and **runs are
  never uploaded** (no leaderboard pollution). Reinstall the normal release
  build afterwards.
- Record: `adb shell screenrecord --bit-rate 8000000 --time-limit 178 /sdcard/recN.mp4`
  in the background, drive menus with `adb shell input tap x y`, stop with
  `adb shell pkill -INT screenrecord` (or the mp4 won't play), then
  `adb pull`.

## 2. Pick the cuts

`scenes.json`: `src` clip, `a`/`b` trim (seconds), and the caption
`chip` / `color` (cyan, violet, pink, gold, mint) / `title` / `sub`. Keep
titles short (~26 characters at 78 px across the 1600 px band). Copy uses the
3.2 vocabulary (`docs/rebrand/REBRAND_SPEC.md`); no price, ranking or
"download now" claims.

## 3. Render

```
FF=<python>/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe   # pip install imageio-ffmpeg
python -I render_landscape.py $FF scenes.json ../cosmo-strike-promo-landscape.mp4
python -I thumb.py
```

- Pillow draws the Prism Noir background, prism-framed footage stage, mask,
  caption band, intro and outro cards (app fonts: Syne, IBM Plex Mono).
- One ffmpeg graph trims/concats the clips (`fps=30` first: screenrecord is
  variable frame rate), masks the footage, fades captions in/out, draws the
  progress bar, adds intro/outro and the music. H.264 crf 19, 30 fps, AAC 192k.
- `thumb.py` only resizes the Play feature graphic
  (`play-store-screenshots/feature-graphic-1024x500.png`, untouched) onto a
  blurred fill of itself; it never edits or replaces the original.

## Music

`../music/Cyborg Ninja.mp3` — "Cyborg Ninja" Kevin MacLeod (incompetech.com),
Licensed under Creative Commons: By Attribution 4.0,
https://creativecommons.org/licenses/by/4.0/. The licence requires credit:
the outro card shows it, and the YouTube description must include:

```
Music: "Cyborg Ninja" Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 4.0
https://creativecommons.org/licenses/by/4.0/
```

## 4. Publish

- Upload the landscape video to YouTube (public or unlisted, ads off, not
  age-restricted), with the credit above in the description and the
  thumbnail.
- Paste the `youtube.com/watch?v=` URL (not `/shorts/`) into Play Console →
  Main store listing → Video. Play shows it in a 16:9 slot.
