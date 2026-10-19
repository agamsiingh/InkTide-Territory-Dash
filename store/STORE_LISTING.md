# InkTide: Territory Dash — Google Play Store Listing

> Developer: **AGMIEX Technologies** (Agam Singh)
> Package: `com.agmiex.inktide` · Version 1.0.0 (versionCode 1)
> Contact email: **agamcoder@gmail.com** (monitored inbox).

---

## 1. App name (max 30 chars)

```
InkTide: Territory Dash
```
Length: **23 / 30** characters.

## 2. Short description (max 80 chars)

```
Paint your trail, close the loop and claim the map. Outsmart bots, fight friends online!
```
Length: **78 / 80** characters (count includes spaces and punctuation).

Alternative (if you prefer no exclamation mark):
```
Paint a trail, loop back and capture land. Territory battles vs bots or live players.
```
Length: **77 / 80** characters.

## 3. Full description (max 4000 chars)

```
Grab the map, one loop at a time.

InkTide: Territory Dash is a fast, colorful territory-capture game starring a glossy yellow cube with big ambitions. Leave your home zone, paint a trail across the board, and swing back to your territory to claim everything you enclosed. Simple to learn, hard to put down.

HOW TO PLAY
• Swipe to steer your cube across the arena.
• Outside your territory you leave a paint trail behind you.
• Return to your own land to close the loop and capture the whole enclosed area.
• Careful: if a rival crosses your trail before you get home, you are out. Crossing your own line is harmless; you only claim land by getting back home. Cut across a rival's trail and they are out instead, and their land becomes yours.
• Reach the level's target percentage of the map to win.

PLAY ANYWHERE, OR FIGHT ONLINE
Solo play is fully offline: play on a flight, on the metro or anywhere with no signal. No accounts, no sign-up, no waiting.

PLAY ONLINE WITH OTHERS
Tap Play Online to drop into a live arena with other real players (bots fill the empty seats), or make a friend room and share the 4-letter code. Sign in with Google Play Games or just pick a nickname.

NO ADS. NO IN-APP PURCHASES.
Just the game. Nothing to buy, no ad breaks between rounds.

LEVELS THAT GROW WITH YOU
Each level raises the target percentage and brings smarter AI bots that chase trails, defend their land and take risks of their own. Learn when to make a big greedy loop and when to play it safe.

UNLOCK SKINS
Earn coins in every match and spend them on fresh skins for your cube. Show off your style while you paint the board.

MADE FOR SHORT SESSIONS
Rounds are quick, so you can jump in for a minute or play level after level.

YOUR SETTINGS, YOUR WAY
Toggle sound effects, music and haptic feedback, and adjust game speed to match how you like to play.

PRIVACY FRIENDLY
InkTide does not collect or share personal data. Your settings and progress are saved only on your device.

Ready to dash? Paint your trail, close the loop and take over the map.
```
Approximate length: ~1,750 / 4,000 characters (well within limit; room to add a "What's new" or feature lines later).

Listing-copy rules followed: no other games' or brands' names/trademarks, no "#1"/"best"/ranking claims, no emoji spam, no ALL-CAPS beyond short section headers, no claims about features that do not exist (no multiplayer, no leaderboards, no cloud save).

## 4. Category and tags

- **App type:** Game
- **Category:** **Casual** (primary recommendation). **Arcade** is also a fair fit; pick one.
- **Tags** (choose up to 5 in Play Console > Store settings, from Google's list): Casual, Arcade, Offline, Single player, Stylized / Colorful (use the exact tag names Play Console offers; available tags change).

## 5. Content rating (IARC questionnaire guidance)

Category to select: **Game**. Suggested answers (answer truthfully for your final build):

| Question area | Answer | Note |
|---|---|---|
| Violence | Fantasy/cartoon only, very mild | Abstract cubes are "eliminated" (disappear/pop). No blood, gore, humans or weapons. If the questionnaire asks whether violence is against realistic human characters: **No**. |
| Fear / horror | No | |
| Sexuality / nudity | No | |
| Language (profanity, crude humor) | No | |
| Controlled substances (drugs, alcohol, tobacco) | No | |
| Gambling / simulated gambling | No | Coins are earned in matches and spent on cosmetic skins; no real money, no randomized paid rewards. |
| User-generated content / user interaction / chat | **Yes (limited)** | Online arenas show other players' nicknames (basic word filter). There is NO chat or messaging. Declare "users can interact" and describe it as nickname display only. |
| Shares user location | No | |
| Digital purchases | No | No IAP. |
| Miscellaneous (unrestricted internet, etc.) | No | The app connects only to its own game server. |

Expected outcome: lowest or near-lowest rating band in most regions (e.g. ESRB Everyone, PEGI 3 or 7). The final rating is assigned by IARC, not by you.

## 6. Target audience and content

**Recommendation: select age groups 13–15, 16–17 and 18+ only (do not select any under-13 group) for the initial release.**

Why:
- Selecting any age group under 13 puts the app under Google Play's **Families policy**, which adds requirements: Families-specific ads/SDK rules, stricter data handling (e.g. no transmission of identifiers from children), stricter metadata review, and possible extra review time.
- The game is not designed specifically for children, and keeping the initial target 13+ keeps compliance simple.
- The game content itself is suitable for all ages; the IARC rating may still come back as "Everyone". That is fine: the content rating and the target audience are separate settings.
- When asked "Could your store listing unintentionally appeal to children?" answer honestly. The bright cube mascot may lead Google to flag it; if so, you may need to explain that the game is a general-audience casual game, or consider opting into Families later.
- If you later want to target under-13 users: review the Families policy in full, ensure no SDK collects identifiers, and re-submit the Target audience form.

## 7. Data safety form answers

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | Not applicable (no data collected; form skips this when "No" above) |
| Do you provide a way for users to request that their data is deleted? | Not applicable; data stays on device. Uninstalling the app or clearing app storage deletes it. |

Notes:
- Data processed only on-device and never sent off the device is **not "collected"** under Play's Data safety definitions. SharedPreferences storage of settings/progress qualifies.
- Re-check before each release that no plugin or package adds analytics, crash reporting or network calls. If you ever add Firebase, Crashlytics, ads, etc., this form MUST be updated.
- The release manifest must not request `INTERNET` (Flutter only adds it in `debug`/`profile` manifests). Verify with `aapt dump permissions` or the Play Console bundle explorer.

## 8. Graphics assets

### App icon
- **512 x 512 px**, 32-bit PNG (with alpha), max **1024 KB**.
- Google applies the rounded mask and shadow; supply a full-bleed square, do not pre-round corners or add your own drop shadow.
- Use the yellow cube mascot centered, high contrast, no text.

### Feature graphic
- **1024 x 500 px**, JPEG or 24-bit PNG (**no alpha**), max **15 MB**.
- Keep key content (logo, mascot) in the center; edges may be cropped on some surfaces. Avoid small text; no device frames needed.

### Phone screenshots
- Formats: JPEG or 24-bit PNG (no alpha).
- Aspect ratio: **16:9 or 9:16**.
- Each side: **min 320 px, max 3840 px**; the longer side cannot be more than twice the shorter side.
- Count: **2 to 8** screenshots (minimum 2 to publish).
- For games, Google recommends at least 4 screenshots at 1080 px+ for better promotion eligibility.
- **Recommended: 1080 x 1920 px portrait (9:16), 6 screenshots:**
  1. Mid-match: cube leaving territory with a long paint trail curving back (caption: "Paint your trail").
  2. The moment of capture: big enclosed area filling with color (caption: "Close the loop, claim the land").
  3. Eliminating a bot by crossing its trail (caption: "Cut off rival trails").
  4. Level-complete screen showing target % reached and coins earned (caption: "Beat the target, earn coins").
  5. Skins shop with several unlocked cube skins (caption: "Unlock fresh skins").
  6. Level select / progression or settings (caption: "Smarter bots every level. Play offline or online").
- Screenshots must show real gameplay from the actual build; captions are optional overlays and must not make claims the game cannot back up.

### Optional
- Promo video: YouTube URL, public or unlisted, ads off, not age-restricted.
- Tablet screenshots (7" and 10") only if you declare tablet support and want tablet featuring.

## 9. Contact details (Store settings)
- Email: **agamcoder@gmail.com** (required)
- Website: https://github.com/agamsiingh/InkTide-Territory-Dash (source repo; optional)
- Privacy policy URL: required (see `PRIVACY_POLICY.md`; host it on GitHub Pages)
