# Asset Licenses - InkTide: Territory Dash

All assets bundled with the game, where each came from, and its license.

## Logo, icons and store graphics

Source artwork: the InkTide logo provided by the project owner, **AGMIEX Technologies**. All rights reserved by AGMIEX Technologies. The files below are derived from it (cropped, masked, resized). The feature graphic's background gradient and paint splashes were drawn procedurally for this project.

| File | Description |
|---|---|
| `assets/images/logo.png` | Full logo, 1024x1024, transparent rounded-square corners |
| `assets/images/logo_wordmark.png` | "InkTide / TERRITORY DASH" wordmark cut-out, 900px wide, transparent background |
| `android_res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` | Legacy launcher icons (48/72/96/144/192 px) |
| `android_res/mipmap-*/ic_launcher_round.png` | Circle-masked launcher icons |
| `android_res/mipmap-*/ic_launcher_foreground.png` | Adaptive-icon foreground layers (108/162/216/324/432 px) |
| `android_res/mipmap-anydpi-v26/ic_launcher.xml`, `ic_launcher_round.xml` | Adaptive icon definitions |
| `android_res/values/ic_launcher_background.xml` | Adaptive icon background color `#FFD21F` |
| `store/play_icon_512.png` | Google Play icon 512x512 |
| `store/feature_graphic_1024x500.png` | Google Play feature graphic 1024x500 |

## Fonts (SIL Open Font License 1.1)

| File | Font | Source | License |
|---|---|---|---|
| `assets/fonts/LilitaOne-Regular.ttf` | Lilita One, (c) 2011 Juan Montoreano | https://raw.githubusercontent.com/google/fonts/main/ofl/lilitaone/LilitaOne-Regular.ttf | OFL 1.1, see `assets/fonts/LICENSE-LilitaOne-OFL.txt` (from https://raw.githubusercontent.com/google/fonts/main/ofl/lilitaone/OFL.txt) |
| `assets/fonts/Fredoka-Variable.ttf` | Fredoka (variable, wdth+wght), (c) 2016 The Fredoka Project Authors | https://raw.githubusercontent.com/google/fonts/main/ofl/fredoka/Fredoka%5Bwdth,wght%5D.ttf | OFL 1.1, see `assets/fonts/LICENSE-Fredoka-OFL.txt` (from https://raw.githubusercontent.com/google/fonts/main/ofl/fredoka/OFL.txt) |

Both fonts come from the Google Fonts repository (https://github.com/google/fonts). The OFL allows bundling them in the app. The fonts may not be sold on their own, and the license text must ship with them.

## Sound effects and music

Every sound and the music loop was **synthesized from scratch for this project** in Python/NumPy (oscillators, filtered noise, envelopes) and encoded to OGG Vorbis with ffmpeg/libvorbis. **No third-party samples, loops or sound libraries were used.** They are original works owned by AGMIEX Technologies.

| File | Description |
|---|---|
| `assets/audio/capture.ogg` | Splash + ascending chime when territory is captured (0.65 s) |
| `assets/audio/trail_tick.ogg` | Soft blip (60 ms) |
| `assets/audio/death.ogg` | Squishy downward splat (0.7 s) |
| `assets/audio/kill.ogg` | Pop + ding (0.5 s) |
| `assets/audio/click.ogg` | UI tap (80 ms) |
| `assets/audio/countdown.ogg` | Countdown beep (150 ms) |
| `assets/audio/go.ogg` | "Go" beep (300 ms) |
| `assets/audio/win.ogg` | 4-note fanfare (1.6 s) |
| `assets/audio/lose.ogg` | Gentle descending tones (1.25 s) |
| `assets/audio/unlock.ogg` | Sparkly arpeggio (0.85 s) |
| `assets/audio/music_loop.ogg` | Background music loop, 120 BPM, 8 bars, 16.0 s, seamless |
| `assets/audio/coin.wav` | Two-step coin ding with chime tail (0.42 s) |
| `assets/audio/levelup.wav` | Rising C-E-G-C arpeggio with sparkle, rank up (0.95 s) |
| `assets/audio/achievement.wav` | Major-chord swell with shimmering bells (1.1 s) |
| `assets/audio/trail_start.wav` | Airy whoosh when leaving your territory (0.28 s) |
| `assets/audio/bump.wav` | Low rubbery thud for wall / head-on collisions (0.32 s) |

The five `.wav` files were added later and were synthesized the same way: NumPy/SciPy oscillators, inharmonic bell partials, band-passed noise and envelopes. They are stored as 16-bit mono 22.05 kHz WAV and are also original works owned by AGMIEX Technologies.

`assets/audio/claim.wav` (reward claim cascade, 0.7 s) and `assets/audio/country_complete.wav` (country-complete fanfare, 1.8 s) were synthesized the same way and are also original works owned by AGMIEX Technologies.

The bonus-game and collection sounds were synthesized the same way and are also original works owned by AGMIEX Technologies:

| File | Description |
|---|---|
| `assets/audio/bonus.wav` | "100% BONUS GAME!" rising fanfare with sparkle tail (2.0 s) |
| `assets/audio/gem.wav` | Two glassy pings when a gem is collected (0.5 s) |
| `assets/audio/power.wav` | Whoosh, splash and thump for the Ink Splash power (0.8 s) |
| `assets/audio/capsule_open.wav` | Rattle, pop and sparkle when a skin capsule opens (1.0 s) |
| `assets/audio/meter_tick.wav` | Tiny tick as the multiplier needle crosses a zone (60 ms) |

The coin stacks, gems, capsules, star-and-crown badge, stopwatch and multiplier meter are drawn procedurally in code; no image files were added for them.

## World map data (public domain)

| File | Source | License |
|---|---|---|
| `assets/data/world.json` | Natural Earth 1:110m Cultural Vectors, Admin 0 – Countries, v5.1.2 (https://www.naturalearthdata.com/, file from https://github.com/nvkelso/natural-earth-vector) | Public domain. Natural Earth asks for no permission or attribution; we credit it anyway. |

The outlines were reprojected (equirectangular), simplified (Douglas-Peucker) and stored as integer coordinates. Antarctica was dropped. Country flags in the game are drawn procedurally in code as simplified designs. No flag image files are bundled.
