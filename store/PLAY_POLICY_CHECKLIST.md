# InkTide: Territory Dash — Play Policy Checklist

Package `com.agmiex.inktide` · AGMIEX Technologies · Check every box before applying for production.

## Technical requirements
- [ ] **Target SDK 36+** (Android 16). Required for new apps/updates from 31 Aug 2026 ([source](https://developer.android.com/google/play/requirements/target-sdk)). Verify with `aapt2 dump badging ... | findstr targetSdkVersion`.
- [ ] **64-bit support**: Flutter release builds include `arm64-v8a` (plus `armeabi-v7a`, `x86_64`). No custom 32-bit-only native libs added.
- [ ] **Android App Bundle** (`.aab`) uploaded, not APK.
- [ ] **Play App Signing** enrolled (Google-generated app signing key); upload key backed up.
- [ ] versionCode higher than any previous upload.
- [ ] Release build is signed with upload key, not debug key.
- [ ] App runs on a real device in release mode; no crashes on launch (pre-launch report reviewed).

## Permissions
- [ ] **No restricted or sensitive permissions** (no SMS, Call Log, location, storage/MANAGE_EXTERNAL_STORAGE, QUERY_ALL_PACKAGES, accessibility, background location, exact alarms, etc.).
- [ ] `INTERNET` is now **required** (online play + Play Games sign-in). Declare it honestly in Data safety and keep the privacy policy in sync. The app talks only to its own game server (use wss://) and Google Play Games.
- [ ] `POST_NOTIFICATIONS` (runtime prompt shown after the first match) and `RECEIVE_BOOT_COMPLETED` (re-arms reminders after a reboot) come from the local-reminders feature. Reminders use inexact alarms, so no `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` is needed - keep it that way.
- [ ] `VIBRATE` is acceptable if a haptics plugin adds it (normal permission, no declaration needed).

## App content (Play Console > Policy > App content)
- [ ] **Privacy policy URL**: public, non-PDF, working HTML page (GitHub Pages) matching `PRIVACY_POLICY.md`; contact placeholder replaced.
- [ ] **App access**: "All functionality is available without special access" (no login).
- [ ] **Ads**: **No**, the app does not contain ads.
- [ ] **Content rating**: IARC questionnaire completed (Game category; mild cartoon/fantasy elimination of abstract cubes; no gambling, UGC, purchases, location sharing).
- [ ] **Target audience**: 13+ age groups only (13–15, 16–17, 18+) for initial release, so the Families policy does not apply.
- [ ] **Data safety**: "No data collected or shared." Re-verify that no dependency adds analytics/crash reporting/networking.
- [ ] **Government apps**: No / not applicable.
- [ ] **Financial features**: None / not applicable.
- [ ] **Health apps**: None / not applicable.
- [ ] **News app**: No.
- [ ] **Advertising ID**: declare that the app does not use the advertising ID (and confirm no plugin adds `com.google.android.gms.permission.AD_ID`).

## Families policy note
- [ ] Not targeting under-13 users at launch. If you later add any under-13 age group, the [Families policy](https://support.google.com/googleplay/android-developer/answer/9893335) applies: only Families-self-certified ad SDKs, no transmission of device identifiers from children, child-appropriate metadata, and potential Teacher Approved/Families review. Re-audit all packages before switching.
- [ ] If Google flags "unintended appeal to children", respond honestly or adjust listing art/copy.

## Intellectual property
- [ ] All game art, cube mascot, logo, icon, feature graphic and screenshots are **original** and owned by AGMIEX Technologies / Agam Singh.
- [ ] Fonts are licensed for app bundling (e.g. **SIL Open Font License** fonts such as Google Fonts); OFL license text included in the app's licenses page or assets.
- [ ] Sound effects and music are original or licensed for commercial redistribution (keep license records/receipts).
- [ ] Open-source package licenses shown (Flutter's `showLicensePage` / `LicensePage` recommended in Settings).
- [ ] No references to other games' names or trademarks in app, listing, keywords or screenshots (e.g. do not say "like paper.io").
- [ ] No impersonation: developer name "AGMIEX Technologies" matches the Play developer account.

## Store listing metadata policy
- [ ] App name 30 chars max, no emoji, no ALL CAPS, no "best/#1/free/new" style promotional words or price claims in the title.
- [ ] Short description 80 chars max; full description 4000 chars max.
- [ ] No keyword stuffing, no fake testimonials, no unattributed user quotes, no ranking claims.
- [ ] Screenshots show real in-app gameplay; no misleading content; captions accurate.
- [ ] Icon 512x512 PNG, feature graphic 1024x500 (no alpha), 2–8 phone screenshots (16:9 or 9:16, 320–3840 px).
- [ ] Contact email is real and monitored (set to `agamcoder@gmail.com`).
- [ ] Category: Game > Casual (or Arcade). Tags relevant only.

## Testing requirement (personal account)
- [ ] If the developer account is a **personal account created after 13 Nov 2023**: closed test with **12+ testers opted in for 14 consecutive days** completed before applying for production ([source](https://support.google.com/googleplay/android-developer/answer/14151465)). Organization accounts are exempt.

## Developer account
- [ ] Identity verification completed; developer contact details current.
- [ ] Account-level Android developer verification requirements checked in Play Console (Google has been rolling out additional developer verification; follow any prompts shown on the dashboard).


## Online play (added with the multiplayer server)

- [ ] **Data safety form**: collects *User IDs* (Play Games ID or random guest ID) and *Name/nickname* (user-chosen), **sent off-device** to our server for app functionality; **not shared** with third parties; **not stored** after the player leaves; encrypted in transit (wss). IP address is processed by the hosting provider. Update the form to match [PRIVACY_POLICY.md](PRIVACY_POLICY.md).
- [ ] **User interaction / UGC**: players see each other's nicknames. There is no chat. Nicknames are filtered with a basic word list ([server/lib/lobby.dart](../server/lib/lobby.dart)); add reporting/moderation before a large launch. Under Google Play's UGC policy this needs a way to report/block abusive content if you expand beyond nicknames.
- [ ] **Play Games Services**: create the game in Play Console > Play Games Services, set the numeric Application ID in `android/app/src/main/res/values/games_ids.xml`, and add your upload/app-signing SHA-1 certificates to the Play Games OAuth credentials, or sign-in will fail (guest play still works).
- [ ] **Server**: deploy `server/` behind TLS, build the app with `--dart-define=INKTIDE_SERVER=wss://your.host`, and load-test your host. See [server/README.md](../server/README.md).
- [ ] Re-check **Families / target audience** answers: online interaction with strangers matters if the app targets children.
