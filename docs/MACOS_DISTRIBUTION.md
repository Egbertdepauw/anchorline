# Anchorline macOS distribution — Mac App Store + Developer ID

Sibling to `docs/TESTFLIGHT_QUICKSTART.md` (iOS). Covers both
distribution paths the user picked: Mac App Store (with TestFlight
for Mac) AND direct download via Developer ID-signed + notarised
.dmg.

The scaffolding is in place — App Sandbox is on, entitlements
declare BLE / network / location / camera / keychain /
user-selected-files, privacy strings + `ITSAppUsesNonExemptEncryption`
are in `macos/Runner/Info.plist`, two `xcodebuild` export-options
plists live under `macos/`, and the bundle id is shared with iOS
(`nl.despaankamer.ccrlogger`). What's NOT yet in place is the
Mac-side signing certificates — those have to be requested from
Apple Developer Portal one time.

## 1. The certificates you need (one-time setup)

The Apple Developer account already has an **Apple Development**
cert (the one driving iOS dev builds). Mac distribution needs three
more:

| Cert | Used for | Path that needs it |
|---|---|---|
| **Apple Distribution** | signing the `.app` for App Store | both |
| **Mac Installer Distribution** | signing the `.pkg` wrapper that App Store uploads need | Mac App Store only |
| **Developer ID Application** | signing the `.app` for direct (non-App-Store) distribution + notarisation | direct .dmg only |

### Quickest path — Xcode's auto-signing

1. Open Xcode → **Settings → Accounts → your Apple ID → Manage Certificates…**
2. Click `+` in the bottom-left and create each of the three above
3. They land in your login keychain automatically

### Manual path — via developer.apple.com

1. https://developer.apple.com/account/resources/certificates → `+`
2. For each cert above, follow the wizard:
   - Generate a CSR locally via Keychain Access → Certificate Assistant
   - Upload it on the portal
   - Download the `.cer`, double-click to install

Verify they landed:

```bash
security find-identity -v -p codesigning | grep -E "Apple Distribution|Mac Installer|Developer ID"
```

You should see three lines matching the three certs above.

### Mac App Store provisioning profile

For the App Store path you also need a **provisioning profile**
linked to the bundle id:

1. https://developer.apple.com/account/resources/profiles → `+`
2. Distribution → **Mac App Store**
3. App ID: `nl.despaankamer.ccrlogger`
4. Certificate: pick **Apple Distribution**
5. Download → double-click to install (Xcode imports it automatically)

(For the Developer ID path no profile is needed — that cert is
self-sufficient.)

## 2. Build the archive (one archive, both exports)

```bash
flutter clean
flutter pub get
flutter build macos --release \
  --dart-define=BUILD_CHANNEL=release --dart-define=DISTRIBUTION_CHANNEL=app_store --dart-define=APP_VERSION=<V> --dart-define=APP_BUILD=<N>

xcodebuild -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath build/macos/Anchorline.xcarchive \
  -destination "generic/platform=macOS" \
  archive
```

If it complains about provisioning at this stage, open
`macos/Runner.xcworkspace` in Xcode once, select the Runner target
→ Signing & Capabilities → make sure "Automatically manage signing"
is on for both Debug and Release, and your team (`U8945M3R9X`) is
selected. Then close Xcode and re-run the `xcodebuild archive`.

The archive lives at `build/macos/Anchorline.xcarchive` and works as
the source for **both** export paths below.

`<V>+<N>` is the `version:` in `pubspec.yaml`. The four defines label the
build (Settings → Version, Sentry release). `DISTRIBUTION_CHANNEL` is baked
into the build, so the archive you export for the Developer ID .dmg (§4)
has to be built with `DISTRIBUTION_CHANNEL=website` instead of `app_store`.

## 3. Mac App Store path — produce a signed .pkg

```bash
xcodebuild -exportArchive \
  -archivePath build/macos/Anchorline.xcarchive \
  -exportOptionsPlist macos/export_options_mas.plist \
  -exportPath build/macos/export-mas
```

Output: `build/macos/export-mas/Anchorline.pkg`.

### Upload native dSYMs to Sentry (do this right after the archive)

So macOS hangs/crashes (e.g. issue #4) arrive symbolicated instead of
`<redacted> in unknown file`. Runs `sentry_dart_plugin`, which scans the
build output + archive for debug files and uploads them. The slugs aren't
secret; the token is — all three come from env so nothing is committed:

```bash
SENTRY_ORG=<your-org-slug> \
SENTRY_PROJECT=<your-project-slug> \
SENTRY_AUTH_TOKEN=<token-with-project:releases scope> \
  dart run sentry_dart_plugin
```

Get the token at Sentry → Settings → Auth Tokens (scope
`project:releases` / `project:read`). The org + project slugs are in the
Sentry URL: `sentry.io/organizations/<org-slug>/projects/<project-slug>/`.
If you'd rather only pass the token, hardcode `org:`/`project:` under the
`sentry:` block in `pubspec.yaml`. Config knobs live in that block.

> Not yet verified end-to-end (needs your auth token). After the first run,
> confirm the dSYMs show up under Sentry → Settings → Debug Files for the
> project, then trigger/await a macOS event to check frames symbolicate.

### App Store Connect — create a SEPARATE Mac app record

Flutter Mac apps can't share an App Store Connect record with iOS
(that's a Mac Catalyst feature). The Mac listing is its own record,
with the SAME bundle id as iOS:

1. https://appstoreconnect.apple.com → My Apps → `+`
2. Platform: **macOS**
3. Name: Anchorline (or "Anchorline – Dive Log" if "Anchorline" is
   already taken in the macOS namespace)
4. Bundle ID: `nl.despaankamer.ccrlogger` (same as iOS)
5. SKU: `anchorline-macos-001`
6. Save

(You'll see two listings under My Apps once both exist — one for
iOS, one for macOS. They each have their own App Privacy, screenshots,
description, version history. Apple presents them as distinct apps
in the respective Stores.)

### Upload

Same Transporter you used for iOS:

1. Drag `build/macos/export-mas/Anchorline.pkg` into Transporter
2. Click Deliver

After ~30 min of processing it appears under the Mac App Store record's
TestFlight tab as `Ready to Submit`. Add yourself as an internal tester
and the TestFlight app on macOS picks it up.

## 4. Developer ID path — produce a notarised .dmg

```bash
xcodebuild -exportArchive \
  -archivePath build/macos/Anchorline.xcarchive \
  -exportOptionsPlist macos/export_options_devid.plist \
  -exportPath build/macos/export-devid
```

Output: `build/macos/export-devid/Anchorline.app` — signed with
Developer ID Application, NOT yet notarised.

### Notarise

Notarisation needs Apple credentials — easiest is an **App-Specific
Password** generated at https://appleid.apple.com → Sign-In and
Security → App-Specific Passwords → `+`. Label it "notarytool".

Stash the credential once so `notarytool` can re-use it:

```bash
xcrun notarytool store-credentials anchorline-notary \
  --apple-id egbert.de.pauw@gmail.com \
  --team-id U8945M3R9X \
  --password "abcd-efgh-ijkl-mnop"   # the app-specific password
```

Submit + wait for Apple's verdict (usually 1–5 min):

```bash
cd build/macos/export-devid
ditto -c -k --keepParent Anchorline.app Anchorline.zip

xcrun notarytool submit Anchorline.zip \
  --keychain-profile anchorline-notary \
  --wait
```

If the verdict is `Accepted`, staple the ticket onto the .app so
it can run even offline:

```bash
xcrun stapler staple Anchorline.app
```

### Wrap in a .dmg

Quick disk image with `hdiutil` (built-in, ugly default look):

```bash
hdiutil create \
  -volname Anchorline \
  -srcfolder build/macos/export-devid/Anchorline.app \
  -ov \
  -format UDZO \
  build/macos/Anchorline.dmg
```

For a nicer .dmg (background image, drag-to-Applications symlink),
install `create-dmg` via `brew install create-dmg` then:

```bash
create-dmg \
  --volname "Anchorline" \
  --window-size 540 380 \
  --icon-size 96 \
  --app-drop-link 400 180 \
  --icon Anchorline.app 140 180 \
  build/macos/Anchorline.dmg \
  build/macos/export-devid/Anchorline.app
```

Host the .dmg behind a download link on despaankamer.nl. Users who
download it can install without going through the Mac App Store;
Gatekeeper accepts it because of the notarisation.

## 5. iterating (build numbers)

Just like iOS, App Store Connect rejects duplicate `CFBundleVersion`
under the same `CFBundleShortVersionString`. The Mac path shares the
same `pubspec.yaml` version as iOS, so when you bump iOS (e.g.
`1.0.0+2 → 1.0.0+3`) the Mac upload automatically picks the new
build number too. Tag the source state if you want to cleanly
separate iOS-3 from macOS-3 in history.

For Developer ID direct downloads the build number doesn't matter
to Apple — it's just metadata in the .app. Bumping it on every
release still helps your users tell which one they have.

## 6. Architecture notes

The archive produces a Universal Binary (`x86_64 + arm64`) for the
main app binary. **However**: `git2dart_binaries` only ships arm64
dylibs for macOS, so the x86_64 portion can't load `libgit2`. Effect:

- **Apple Silicon Macs (M1+)**: everything works including Subsurface
  Cloud sync.
- **Intel Macs**: app launches, but the Subsurface sync feature
  crashes when it tries to load libgit2.
- **macOS version floor for sync**: `git2dart_binaries` 1.12.1's
  `libgit2.dylib` is built with `minos 26.0` (upstream builds on the
  latest SDK without a deployment target), so on macOS < 26 dyld
  refuses to load it — the app runs, but Subsurface sync errors out.
  Earlier binaries were minos 15.0. Worth reporting upstream: if their
  CI sets a `MACOSX_DEPLOYMENT_TARGET`, a future binaries bump restores
  older-macOS sync support automatically.

For TestFlight + first release this is fine — most Mac buyers in
the last three years are on Apple Silicon. If Intel support becomes
important later, you'd need a universal `libgit2-experimental.dylib`
(probably built from source via `git2dart_binaries`'s upstream).

## 7. Common pitfalls

| Symptom | Fix |
|---|---|
| `No signing certificate "Mac Installer Distribution" found` | Step 1 above — create the Mac Installer Distribution cert. |
| `No profiles for 'nl.despaankamer.ccrlogger' were found` | Step 1 above — create the Mac App Store provisioning profile. |
| `notarytool submit … Status: Invalid` | Run `xcrun notarytool log SUBMISSION_UUID --keychain-profile anchorline-notary` to get the per-file rejection reasons (usually unsigned helper, hardened-runtime missing, etc.). |
| Mac App Store rejected: "App icon contains an alpha channel" | Run the chroma-key tool we used before to regen the iOS-style solid icon for macOS too. The current pipeline already does this — corners of `Anchorline.app/Contents/Resources/AppIcon.icns` should be opaque hullBlack at the largest sizes. |
| Mac App Store rejected: "App requires Sandbox" | Already on (`com.apple.security.app-sandbox` true in Release.entitlements). |
| App launches but blocks at first BLE access | Bluetooth entitlement should already be there; if not, add `com.apple.security.device.bluetooth` to Release.entitlements. |

## 8. What's already on disk after this commit

| Path | Purpose |
|---|---|
| `macos/Runner/Info.plist` | Added `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `ITSAppUsesNonExemptEncryption = false` |
| `macos/Runner/Release.entitlements` | App Sandbox + BLE + network + location + camera + user-selected files + keychain (pre-existing) |
| `macos/Runner/Configs/AppInfo.xcconfig` | PRODUCT_NAME = Anchorline (renames .app bundle), bundle id `nl.despaankamer.ccrlogger`, copyright updated |
| `macos/export_options_mas.plist` | Used by `xcodebuild -exportArchive` to produce the Mac App Store .pkg |
| `macos/export_options_devid.plist` | Used by `xcodebuild -exportArchive` to produce the Developer ID .app |
