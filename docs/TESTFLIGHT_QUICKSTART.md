# TestFlight — fastest path from this commit to a build divers can test

Picks up where `APP_STORE_SUBMISSION.md` left off, focused on the
narrow goal of getting build 1 onto TestFlight. The full submission
flow (screenshots, marketing copy, privacy policy URL, etc.) is **not
required** for TestFlight — only for the public App Store release.

## Status as of this commit — ✓ already in place

| Item | Value |
|---|---|
| Bundle ID | `nl.despaankamer.ccrlogger` |
| Team ID | `U8945M3R9X` (auto-signing on) |
| Display name | **CCRLog** (fixed from "Ccrlogger") |
| Version | `1.0.0+1` (pubspec.yaml) |
| Privacy manifest | `ios/Runner/PrivacyInfo.xcprivacy` (wired into target) |
| Privacy strings | Bluetooth, Location, Camera, Photos all set in Info.plist |
| Encryption form | `ITSAppUsesNonExemptEncryption = false` |
| Icons | All 22 sizes + 1024×1024 RGB (no alpha) |
| Launch screen | dark background matching the app's wreck palette |
| Release IPA | Verified buildable: 30 MB at `build/ios/ipa/ccrlogger.ipa` |

## 1. App Store Connect — create the app record

Required before you can upload. You only do this once per app.

1. Sign in at https://appstoreconnect.apple.com
2. **My Apps → +** → New App
3. Fill in:
   - **Platform**: iOS
   - **Name**: `CCRLog` (this is the App Store listing name; if taken,
     try `CCRLog – Tech Dive Log` or similar — the home-screen display
     name stays `CCRLog` regardless)
   - **Primary language**: English (UK or US — your call)
   - **Bundle ID**: pick `nl.despaankamer.ccrlogger` from the dropdown.
     If it's not there:
     - Go to https://developer.apple.com/account/resources/identifiers/list
     - **+** → App IDs → App → Continue
     - Description: "CCRLog", Bundle ID: explicit `nl.despaankamer.ccrlogger`
     - Capabilities: none required for TestFlight
     - Register → back to App Store Connect, the ID will appear
   - **SKU**: anything unique. Convention: `ccrlog-ios-001`
   - **User access**: Full Access
4. The app record now exists. You don't need to fill App Privacy /
   App Information / Pricing / etc. for TestFlight — those gates only
   trigger on the App Store submission.

## 2. Rebuild the IPA (one-liner)

The IPA already in `build/ios/ipa/` is current as of HEAD. If you
want a fresh one:

```bash
flutter build ipa --release
```

Build artefact: `build/ios/ipa/ccrlogger.ipa` (~30 MB).

If `pod install` complains about the Profile config xcconfig, ignore
it — it's a Flutter idiosyncrasy that doesn't affect Release builds.

## 3. Upload — pick one

### Option A: Transporter (recommended for first build)

The simplest path. Apple's free Mac app.

1. Install **Transporter** from the Mac App Store
   (https://apps.apple.com/app/transporter/id1450874784)
2. Sign in with the same Apple ID that owns the developer account
3. Drag `build/ios/ipa/ccrlogger.ipa` into the Transporter window
4. Click **Deliver**
5. The upload + Apple's automated checks take 2–5 min

### Option B: Xcode Organizer

1. Open `ios/Runner.xcworkspace` in Xcode
2. **Product → Archive** (use the same release config that already
   built successfully — Xcode will rebuild from scratch)
3. When the archive completes, Xcode opens the Organizer
4. Click your archive → **Distribute App → App Store Connect → Upload**
5. Xcode walks through signing + uploading

### Option C: altool (scriptable; needs an API key)

For when you want to automate this. Create an App Store Connect API
key first at https://appstoreconnect.apple.com/access/api , then:

```bash
xcrun altool --upload-app \
  --type ios \
  -f build/ios/ipa/ccrlogger.ipa \
  --apiKey "<KEY_ID>" \
  --apiIssuer "<ISSUER_ID>"
```

(`--apiKey` is the key ID, not the file. Apple's tool reads the
private key from `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`.)

## 4. Wait for processing (App Store Connect → TestFlight)

The uploaded build appears under your app → **TestFlight → iOS**
within a few minutes. State progresses:

- **Processing** (Apple validates signing, manifests, etc.) — 5–30 min
- **Missing Compliance** — only if you didn't set
  `ITSAppUsesNonExemptEncryption` in Info.plist. We did, so this
  shouldn't appear.
- **Ready to Submit** — done. Now you can hand the build to testers.

## 5. Internal testing — add yourself + buddies

1. App Store Connect → CCRLog → **TestFlight → Internal Testing → +**
2. Add yourself by Apple ID. You can add up to **100 internal
   testers** (must be users of your dev team — invite them to your
   team first under "Users and Access" if they're not).
3. Each tester gets an email → install **TestFlight** app on iPhone →
   redeem the invite → install CCRLog. Internal builds are available
   instantly (no Apple review).

## 6. External testing — optional but recommended before App Store

For non-team-member testers (your CCR-diving friends):

1. App Store Connect → **TestFlight → External Testing → +** → create
   a group like "Beta divers"
2. Add testers by email (up to 10,000)
3. Pick the build → submit it for **Beta App Review** (Apple does a
   light review, takes ~24 h on a first build)
4. Once approved, testers get invite emails

## 7. Iterate

Each subsequent upload **must bump the build number**:

```yaml
# pubspec.yaml
version: 1.0.0+2  # then +3, +4, ...
```

The marketing version (`1.0.0`) only bumps when you're cutting a new
release line. Within a release, `+N` keeps incrementing.

## When you're ready for the public App Store

Pick up `APP_STORE_SUBMISSION.md` sections §9 (screenshots), §10
(privacy policy URL), §11 (TestFlight you're already on), §13
(marketing copy). Submit the same build TestFlight has been chewing
on so testers' feedback is on the build that ships.

## Common gotchas at upload time

| Symptom | Fix |
|---|---|
| Transporter: "ITMS-90683: Missing purpose string in info.plist" | A new dependency added a permission. Add the matching `NS…UsageDescription` to Info.plist. |
| Transporter: "ITMS-90809: Deprecated API Usage" | The privacy manifest is missing a required-reason API entry. Open `ios/Runner/PrivacyInfo.xcprivacy` and add it. |
| "Invalid signature" | Open Xcode → Runner → Signing & Capabilities → toggle "Automatically manage signing" off then on. Re-archive. |
| "Bundle ID is invalid or has already been taken" | Either the bundle ID isn't registered (do step 1.4 above) or you typed it wrong in App Store Connect. |
| 1024×1024 icon has alpha channel | Re-export from your source as RGB (we already verified ours is RGB). |
