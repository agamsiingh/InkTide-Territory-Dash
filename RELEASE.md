# InkTide: Territory Dash — Android Release Guide (Windows)

Package: `com.agmiex.inktide` · First release: `1.0.0+1` (versionName 1.0.0, versionCode 1)

All commands are **Windows cmd** syntax, run from the Flutter project root unless stated.

---

## 0. Requirements verified (as of October 2026)

| Requirement | Value | Source |
|---|---|---|
| Target API level for new apps and updates | **Android 16 (API level 36) or higher**, effective **31 Aug 2026** (extension to 1 Nov 2026 could be requested) | [Android Developers: Meet Google Play's target API level requirement](https://developer.android.com/google/play/requirements/target-sdk) · [Play Console Help: Target API level requirements](https://support.google.com/googleplay/android-developer/answer/11926878) |
| Testing before production (personal accounts) | **At least 12 testers opted in to a closed test continuously for at least 14 consecutive days**, for **personal developer accounts created after 13 Nov 2023** | [Play Console Help: App testing requirements for new personal developer accounts](https://support.google.com/googleplay/android-developer/answer/14151465) |
| Publishing format | Android App Bundle (`.aab`) required for new apps | Play Console Help |

Google changes these requirements periodically; re-check both links before each submission.

### Target SDK check
Flutter's template uses `targetSdk = flutter.targetSdkVersion`. Confirm your Flutter version's default is **36 or higher**:

```cmd
flutter --version
type android\app\build.gradle.kts | findstr /i "targetSdk compileSdk minSdk"
```

After a build, confirm the actual value:

```cmd
%LOCALAPPDATA%\Android\Sdk\build-tools\<version>\aapt2 dump badging build\app\outputs\flutter-apk\app-release.apk | findstr /i "targetSdkVersion"
```

If it prints less than `'36'`, upgrade Flutter (`flutter upgrade`) or set `targetSdk = 36` (and `compileSdk = 36`) explicitly in `android/app/build.gradle(.kts)`, then rebuild and test.

---

## 1. Create the upload keystore (one time)

```cmd
mkdir %USERPROFILE%\keys
keytool -genkey -v -keystore %USERPROFILE%\keys\inktide-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- If `keytool` is not found, use the JDK bundled with Android Studio:
  `"C:\Program Files\Android\Android Studio\jbr\bin\keytool" -genkey -v -keystore %USERPROFILE%\keys\inktide-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
  (or run `flutter doctor -v` and look for the "Java binary at" path).
- Choose a strong password. For PKCS12 keystores (the default), the key password equals the store password.
- **Back up** `inktide-upload.jks` and its password somewhere safe (password manager + offline copy). If you lose the upload key, you can request an upload-key reset from Play support, but it costs time.
- Never commit the `.jks` file.

## 2. Create `android\key.properties` (keep it out of git)

Create the file `android\key.properties` with this content (Notepad is fine):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=C:/Users/YOUR_WINDOWS_USERNAME/keys/inktide-upload.jks
```

- Use **forward slashes** (or doubled backslashes `C:\\Users\\...`) in `storeFile`; single backslashes are escape characters in `.properties` files.
- Add the lines from `android_snippets/gitignore_additions.txt` to `android\.gitignore` (or the root `.gitignore`), then verify:

```cmd
git check-ignore -v android\key.properties
git status
```

`key.properties` must not appear in `git status`.

## 3. Wire up signing in Gradle

Already done: `android\app\build.gradle.kts` loads `android\key.properties` when it exists. Without `key.properties` it falls back to debug signing so `flutter run --release` still works locally, but **Play Console will reject debug-signed uploads**.

Do not remove these (each fixes a real failure found on the emulator):

- `android\app\proguard-rules.pro`: R8 keep rules for `shared_preferences_android` 2.5.x. Its Dart side calls Kotlin over JNI, which R8 can't see; without the rules the release build hangs on the splash screen (`NoSuchMethodError` / `ClassNotFoundException` in logcat).
- `android\gradle.properties`: `kotlin.incremental=false` (the pub cache on C: and the project on D: break Kotlin's incremental caches) and `kotlin.compiler.execution.strategy=in-process` (the separate Kotlin daemon deadlocked builds on this machine).

## 4. Build

```cmd
flutter clean
flutter pub get
flutter build appbundle --release
flutter build apk --release
```

Outputs:

| Artifact | Path |
|---|---|
| App Bundle (upload this to Play) | `build\app\outputs\bundle\release\app-release.aab` |
| APK (sideload / device testing only) | `build\app\outputs\flutter-apk\app-release.apk` |

Optional: smaller per-ABI APKs for testing: `flutter build apk --release --split-per-abi`.
Flutter release builds include `arm64-v8a`, `armeabi-v7a` and `x86_64`, which satisfies Play's 64-bit requirement.

### Verify the release build

```cmd
adb install -r build\app\outputs\flutter-apk\app-release.apk
"%JAVA_HOME%\bin\jarsigner" -verify -verbose -certs build\app\outputs\bundle\release\app-release.aab | findstr /i "CN="
%LOCALAPPDATA%\Android\Sdk\build-tools\<version>\aapt2 dump permissions build\app\outputs\flutter-apk\app-release.apk
```

- The signer should be your upload certificate, **not** `CN=Android Debug`.
- Permissions output should **not** include `android.permission.INTERNET` (Flutter adds it only in the debug/profile manifests). If it appears, check `android\app\src\main\AndroidManifest.xml` and plugin manifests.

## 5. Play Console: create the app and enroll in Play App Signing

1. [Play Console](https://play.google.com/console) > **Create app**: name "InkTide: Territory Dash", default language, **Game**, **Free**, accept declarations.
2. **Play App Signing** is mandatory for new apps and is set up automatically on first upload: choose **"Use Google-generated key"** (recommended). Google holds the app signing key; you keep the upload key from step 1.
3. After the first upload, go to **Test and release > Setup > App signing** (menu names vary slightly) and note both SHA-1/SHA-256 fingerprints (upload key and app signing key) for later use.

## 6. Complete "App content" (Policy) before any rollout

Privacy policy URL, App access (all functionality available without login), Ads (No), Content rating (IARC questionnaire), Target audience, Data safety, Government apps (No), Financial features (None), Health (None). Answers are in `store/STORE_LISTING.md` and `store/PLAY_POLICY_CHECKLIST.md`.

## 7. Internal testing (fast sanity check, up to 100 testers)

1. **Test and release > Testing > Internal testing > Create new release**.
2. Upload `app-release.aab`. Release name: `1.0.0 (1)`. Add release notes.
3. **Testers** tab: create an email list (your own Gmail accounts), save.
4. Review and roll out. Copy the **opt-in link**, open it on your phone with a tester account, accept, then install from Play.
5. Internal testing does **not** count toward the 12-tester/14-day requirement.

## 8. Closed testing (required for personal accounts created after 13 Nov 2023)

1. **Testing > Closed testing** > use the default track (e.g. "Alpha") or create one > **Create new release** (you can promote the internal build).
2. Select countries, add a tester email list (or a Google Group) with **at least 12 testers** (recruit a few extra; people drop out).
3. Roll out; send testers the opt-in link. They must **opt in** and should install and actually play.
4. Keep at least 12 testers opted in **continuously for 14 consecutive days**. Push 1–2 updates during this period based on feedback (helps the production-access review).
5. After 14 days, the **Apply for production** option appears in the Dashboard. Answer the questions about your test (who tested, feedback received, changes made, readiness). Google reviews this application; allow several days (see the Play Console Help link above for current timing).
6. Once approved, create a **Production** release (consider a staged rollout, e.g. 20% then 100%).

## 9. Version bump for the next release

Every upload to Play needs a **higher versionCode**. In `pubspec.yaml`:

```yaml
version: 1.0.1+2   # versionName 1.0.1, versionCode 2
```

Then rebuild:

```cmd
flutter build appbundle --release
```

Or override without editing pubspec: `flutter build appbundle --release --build-name=1.0.1 --build-number=2`.
Rule: `+N` must always increase (2, 3, 4, ...); the name before `+` is user-facing.

## 10. Release checklist (quick)

- [ ] `targetSdkVersion` 36+ confirmed in built APK
- [ ] Signed with upload key (not debug)
- [ ] No `INTERNET` permission in release manifest
- [ ] `key.properties` and `*.jks` not in git; keystore backed up
- [ ] Version bumped (`+N` increased)
- [ ] App content forms complete; privacy policy URL live
- [ ] Store listing, icon 512x512, feature graphic 1024x500, 2–8 screenshots uploaded
- [ ] Contact email placeholder `support@agmiex.example` replaced everywhere
