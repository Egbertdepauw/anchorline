# Anchorline beta distribution

End-to-end recipe for getting builds in front of beta testers across
**iOS, macOS, Android, Windows**. Sibling docs:

- `docs/TESTFLIGHT_QUICKSTART.md` — iOS TestFlight (already in flight).
- `docs/MACOS_DISTRIBUTION.md` — Mac App Store + Developer ID `.dmg`.

This file covers what those two don't: **Android signing + Play Internal +
hosted `.apk`**, **Windows installer via Inno Setup**, **R2 hosting for
the macOS `.dmg` / Android `.apk` / Windows `.exe`**, and the
**landing page** at `staging.despaankamer.nl/anchorline` that lets
testers find the right build for their device.

---

## 1. Android — one-time setup

### 1a. Generate the upload keystore

The keystore is what Google Play uses to verify "this APK comes from
you" across updates. **Lose it = lose the ability to ship updates to
existing installs.** Back up everything in this section to 1Password
when you're done.

```bash
cd android
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

It'll prompt for:
- **Keystore password** — strong, save in 1Password.
- **Key password** — same as keystore password is fine (or different).
- **Name + org + city + country** — these end up baked into the
  certificate. Use real values; testers don't see them, but Play
  Console does.

### 1b. Create `key.properties`

```bash
cp android/key.properties.example android/key.properties
# Edit android/key.properties — fill in storePassword and keyPassword
# with what you just typed at keytool prompts. storeFile stays as
# upload-keystore.jks (relative to android/app/build.gradle.kts).
```

`android/key.properties` and `android/upload-keystore.jks` are both
gitignored. **Do not commit them.** When working on a new machine,
restore both from 1Password.

### 1c. Verify the build is signed correctly

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Verify
signing:

```bash
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

You should see the SHA-256 fingerprint of the certificate you just
created. **Record this fingerprint** — Play Console asks for it the
first time you upload, and any future deployment that doesn't match
will be rejected.

### 1d. Build JDK — no override needed

Flutter runs Gradle on Android Studio's bundled JDK (JBR). Check which
one with `flutter doctor -v` → "Java binary at". The Gradle wrapper
(`android/gradle/wrapper/gradle-wrapper.properties`, currently 9.3.1)
supports JDK 17 through 25. Leave `flutter config --jdk-dir` **unset**.

If an Android Studio update ships a newer JBR, the Gradle build fails
within seconds and the only error text is the JDK version (for example
`What went wrong: 25.0.2`). Fix it by bumping the Gradle wrapper, plus
AGP and Kotlin if their compatibility tables require it, and don't pin
an older JDK. CLAUDE.md → "Known third-party defects" has the version
coupling (issue #80).

---

## 2. Android — Google Play Internal Testing

### 2a. Create the Play Console app (one-time)

1. Pay the **$25 Google Play Developer fee** at
   <https://play.google.com/console/signup> (you only do this once, ever).
2. After approval (instant for individual devs, up to 48 h for org), go
   to <https://play.google.com/console> → "Create app".
3. **App name**: Anchorline
4. **Default language**: English (United States) — easiest for the
   review machinery.
5. **App or game**: App
6. **Free or paid**: Free
7. Tick the policy/declaration checkboxes (real ones: ads = no,
   target audience = adults, etc.).
8. Click **Create app**.

### 2b. App content (one-time)

Under "Policy → App content" the side panel lists ~10 items Google
wants completed before any internal-testing build can roll out:

- **Privacy policy** — must be a public URL. A one-line page on
  `https://egbertdepauw.github.io/ccrlogger-legal/` works for beta; before
  public release we'll need a real one.
- **App access** — "All functionality is available without restrictions"
  is fine (the optional sign-in is gated by a Supabase account, which
  doesn't count as a restriction in Play's eyes).
- **Ads** — None.
- **Content rating** — IARC questionnaire, ~5 minutes. Anchorline is
  Everyone-rated (no violence, no purchases, no UGC).
- **Target audience** — 18+.
- **News app** — No.
- **COVID-19 contact tracing** — No.
- **Data safety** — Declares what data the app collects. Anchorline
  collects: email (for sign-in), location (for dive sites), photos
  (for attachments), crash logs (Sentry). All of it is encrypted in
  transit + at rest. Tick those boxes.
- **Government app** — No.
- **Financial features** — No.

This list is annoying but each item takes <5 min once you have the
text ready. Most can be edited later.

### 2c. Upload the first `.aab`

1. Left rail → **Testing → Internal testing**.
2. **Create new release**.
3. Drag `build/app/outputs/bundle/release/app-release.aab` into the
   bundle uploader.
4. **Release name**: `1.0.0 (5)` — Play auto-suggests this from
   `versionName (versionCode)`.
5. **Release notes**: copy from `docs/TESTFLIGHT_QUICKSTART.md`'s
   "What to Test" copy.
6. **Save** → **Review release** → **Start rollout to Internal testing**.

### 2d. Invite testers

Same screen → **Testers** tab → **Create email list** → paste tester
emails (max 100). Copy the **opt-in URL** Play generates (looks like
`https://play.google.com/apps/internaltest/XXXXXXX`). Paste that URL
into `DOWNLOADS.androidPlay` in
[the landing page component](https://staging.despaankamer.nl/anchorline)
(see Section 5 below).

Testers click the opt-in link on an Android device signed into the same
Gmail you added to the list, then install via Play Store as usual.
**Build appears within 5-10 min of rollout**, sometimes faster.

---

## 3. Android — hosted `.apk` (fallback)

For testers who refuse to use Play (Huawei users, F-Droid types,
people who hate Google), build a signed `.apk` and host it on R2:

```bash
flutter build apk --release --target-platform android-arm64
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Upload to R2 (see Section 6) as `anchorline-1.0.0-beta.4.apk`.

The landing page exposes this as the "…or download .apk" secondary
button on the Android card. Users tap it on their phone → Chrome
warns "this type of file can harm your device" → Tap "Download
anyway" → Open → Android asks for "install unknown apps" permission
for Chrome → grant once → installer runs. Subsequent betas reuse the
permission.

---

## 4. Windows — Inno Setup on a Windows VM

You handle the Windows build host. From the macOS side, the only
pieces of the puzzle that live in this repo are:

- `windows/installer/anchorline.iss` — the Inno Setup script.
- `windows/CMakeLists.txt` + `windows/runner/Runner.rc` — branded with
  "Anchorline" / "De Spaankamer" instead of the Flutter `ccrlogger`
  defaults.

### 4a. On the Windows machine

Prerequisites (one-time):
- Flutter SDK (matching the macOS dev version; see
  `flutter --version` output on the Mac).
- Visual Studio 2022 Community with "Desktop development with C++"
  workload (Flutter's Windows build requires MSVC + Windows 10 SDK).
- Inno Setup 6 from <https://jrsoftware.org/isdl.php> (free).

Build + package:

```cmd
:: From a `cmd` prompt, repo root
flutter pub get
flutter build windows --release

:: Replace <V> and <N> with the version and the build number from
:: pubspec.yaml's version field (<V>+<N>).
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" ^
  /DMyAppVersion=<V> /DMyAppBuild=<N> /DChannel=release ^
  windows\installer\anchorline.iss
```

Output: `windows\installer\Output\Anchorline-<V>-windows-x64.exe`. Upload
to R2 as `anchorline-setup-1.0.0-beta.4.exe` (see Section 6).

### 4b. SmartScreen warning

First-time users see a "Windows protected your PC" dialog because the
.exe isn't signed. Workaround for testers: click **"More info"** →
**"Run anyway"**.

To make this go away, get an **EV Code Signing Certificate** (~€350-700/yr
from Sectigo, DigiCert, or SSL.com). After signing the .exe with
`signtool.exe`, SmartScreen accumulates "reputation" over ~100 installs
and the warning eventually stops appearing. Not worth it for beta.

---

## 5. Hosting on Cloudflare R2

Anchorline already uses R2 for attachments
(`worker/wrangler.toml` → bucket `ccrlogger-attachments`). We add a
**separate** bucket for the public downloads — different access pattern
(public-read instead of presigned-URL-only), different lifecycle, easier
to clean up old beta builds.

### 5a. Create the bucket

```bash
cd worker
npx wrangler r2 bucket create anchorline-downloads
```

In the Cloudflare dashboard → R2 → `anchorline-downloads` → **Settings**:

- **Public access** → click **Allow Access**. Cloudflare gives you a
  hostname like `https://pub-1234abcd.r2.dev`. **Record that** — the
  landing page needs it (see `DOWNLOADS.macDmg` etc. in
  `src/app/anchorline/anchorline-landing.tsx` on SpaankamerWeb).
- **CORS** — not needed for direct file downloads from a browser
  (`<a href>` doesn't go through CORS). Leave default.

### 5b. Upload builds

```bash
# macOS .dmg (notarised, from `docs/MACOS_DISTRIBUTION.md`)
npx wrangler r2 object put \
  anchorline-downloads/anchorline-1.0.0-beta.4.dmg \
  --file=../build/macos/Anchorline.dmg \
  --content-type=application/x-apple-diskimage

# Android .apk
npx wrangler r2 object put \
  anchorline-downloads/anchorline-1.0.0-beta.4.apk \
  --file=../build/app/outputs/flutter-apk/app-release.apk \
  --content-type=application/vnd.android.package-archive

# Windows .exe installer (scp it across from the Windows VM first)
npx wrangler r2 object put \
  anchorline-downloads/anchorline-setup-1.0.0-beta.4.exe \
  --file=./Anchorline-<V>-windows-x64.exe \
  --content-type=application/vnd.microsoft.portable-executable
```

Verify with:

```bash
npx wrangler r2 object list anchorline-downloads
```

Each upload is ~30-70 MB. R2's free tier covers 10 GB storage and
1 million Class A operations / month — plenty.

### 5c. (Optional) Custom domain in front of R2

If you want the pretty URLs the user originally asked for
(`https://staging.despaankamer.nl/anchorline/anchorline_1.0.0.dmg`)
instead of `pub-xxx.r2.dev/...`, add this to
[SpaankamerWeb/next.config.ts](../../nextjs/SpaankamerWeb/next.config.ts):

```ts
async redirects() {
  return [
    {
      source: '/anchorline/downloads/:file*',
      destination: 'https://pub-REPLACE-WITH-R2-PUBLIC-ID.r2.dev/:file*',
      permanent: false,
    },
  ];
}
```

That gives `staging.despaankamer.nl/anchorline/downloads/anchorline-1.0.0-beta.4.dmg`
which redirects to R2. The browser shows the R2 URL after the redirect,
but the **shared link stays pretty**. Update the `DOWNLOADS` const in
`anchorline-landing.tsx` to use the pretty URLs.

(For zero-redirect pretty URLs, attach the staging domain to R2 via
Cloudflare's "Custom Domains" feature in the R2 dashboard — needs the
domain on Cloudflare's nameservers, which it already is for the wider
despaankamer.nl tree.)

---

## 6. Landing page

Lives in the SpaankamerWeb repo at
[`src/app/anchorline/page.tsx`](../../nextjs/SpaankamerWeb/src/app/anchorline/page.tsx)
(plus `anchorline-landing.tsx` and `layout.tsx` in the same dir).

The page is deliberately OUTSIDE the `(site)` route group so it
doesn't get wrapped in De Spaankamer's header/footer — Anchorline is
its own product and should feel like one. The route renders at
**`https://staging.despaankamer.nl/anchorline`**.

After uploading new builds, edit these three constants in
`anchorline-landing.tsx`:

```ts
const VERSION = "1.0.0-beta.4"; // bump per build

const DOWNLOADS = {
  macDmg: `https://pub-REPLACE-WITH-R2-PUBLIC-ID.r2.dev/anchorline-${VERSION}.dmg`,
  // ...
};
```

The OS-detect logic highlights the card matching the visitor's
platform with a "Your device" badge + reel-orange border, but every
card stays clickable — testers on a desktop browser still get all
four options visible.

### Deploy

The SpaankamerWeb project deploys via its existing CI (Vercel / Hetzner
VPS — whichever the team uses for that site). Once the file is committed
+ deployed, `staging.despaankamer.nl/anchorline` is live.

---

## 7. Release checklist

Per beta build:

- [ ] Bump `pubspec.yaml` version (e.g. `1.0.0+4 → 1.0.0+5`).
- [ ] Update `VERSION` in `src/app/anchorline/anchorline-landing.tsx`
      on SpaankamerWeb.
- [ ] **iOS**: `flutter build ipa --release`. Upload to TestFlight via
      Transporter (see `docs/TESTFLIGHT_QUICKSTART.md`).
- [ ] **macOS App Store**: `xcodebuild archive` + `exportArchive` MAS,
      upload `.pkg` via Transporter (see `docs/MACOS_DISTRIBUTION.md`).
- [ ] **macOS Developer ID**: `xcodebuild archive` + `exportArchive`
      Developer ID, `xcrun notarytool submit`, staple, `hdiutil` →
      upload `.dmg` to R2.
- [ ] **Android Play**: `flutter build appbundle --release` → Play
      Console → Internal testing → new release.
- [ ] **Android hosted**: `flutter build apk --release --target-platform
      android-arm64` → upload to R2.
- [ ] **Windows**: build on VM, run ISCC, upload `.exe` to R2.
- [ ] Update R2 URLs in the landing page if filenames changed.
- [ ] Commit + push (Anchorline repo + SpaankamerWeb repo).
- [ ] Email testers with a one-liner pointing to
      `staging.despaankamer.nl/anchorline`.

Five platforms, but no individual step is hard — the bottleneck is
the human review queues at Apple (typically <1 day for TestFlight
updates) and Google (typically <30 min for Internal Testing).
