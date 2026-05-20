# App Store submission checklist — CCRLogger / iOS

Single-source-of-truth for everything needed to ship the first iOS
build to TestFlight and then the App Store. Items marked **✓ done**
already exist; **→ action** items are tasks you do (mostly in Xcode or
App Store Connect — I can't drive those screens from this CLI).

## 1. Bundle + signing — ✓ done

- Bundle ID: `nl.despaankamer.ccrlogger`
- Team ID: `U8945M3R9X`
- Code signing: Automatic (Xcode-managed)
- iOS deployment target: 15.0 (Apple's current minimum is 13.0; we're
  ahead of the floor — fine)
- Encryption export compliance: `ITSAppUsesNonExemptEncryption = false`
  in `Info.plist` (no annual export form needed)

## 2. App icons — ✓ done

All 22 sizes generated under `ios/Runner/Assets.xcassets/AppIcon.appiconset/`.
`Icon-App-1024x1024@1x.png` is 8-bit RGB (no alpha channel), which is
what Apple requires for the marketing icon — alpha would auto-reject.

→ **Optional spot-check before upload**: open the 1024×1024 in Preview
and confirm it looks correct as the App Store icon (it'll appear at
that resolution on Apple's web store). Apple adds the rounded-corner
mask, so submit a square icon.

## 3. Privacy descriptions — ✓ done

All four user-facing permission strings are in `Info.plist`:

| Key | Value |
|---|---|
| `NSBluetoothAlwaysUsageDescription` | "CCRLog needs Bluetooth to connect to your Shearwater dive computer and import dive logs." |
| `NSBluetoothPeripheralUsageDescription` | (same) |
| `NSLocationWhenInUseUsageDescription` | "This app uses your location to record where each dive happened." |
| `NSCameraUsageDescription` | "CCRLog uses the camera to attach photos to your dives — for example, snapshots of buddy logbook pages." |
| `NSPhotoLibraryUsageDescription` | "CCRLog reads photos from your library when you attach images to a dive." |

## 4. Privacy manifest — ✓ done (this commit)

`ios/Runner/PrivacyInfo.xcprivacy` is now in place and wired into the
Runner target via `project.pbxproj`. Required-reason API declarations
cover `UserDefaults` (CA92.1), file timestamp (C617.1), disk space
(E174.1), and system boot time (35F9.1). Collected-data declarations
cover crash data, performance data, email, user content, coarse
location, and photos — all marked **not used for tracking**.

→ **Review before submission**: the manifest's collected-data section
makes specific claims about *why* each data type is collected. Read it
through with your privacy policy alongside and tweak if anything
overstates / understates what CCRLog actually does. The values match
Apple's labels on the "App Privacy" section of the App Store listing.

## 5. Display name — → action

Current `CFBundleDisplayName` is **"Ccrlogger"** (mixed case). For the
App Store listing this is what users see under the icon on the home
screen. Common branding choices:

| Option | Rationale |
|---|---|
| **CCRLog** | Matches the project name and how the in-app title bar reads. Reads as an initialism + word, which is typical for tech/diving apps. |
| **CCRLogger** | Matches the bundle ID and pubspec.yaml `name`. |
| Keep "Ccrlogger" | Lowercased middle reads as a typo to most people; recommend changing. |

To change: edit `ios/Runner/Info.plist` →
`<key>CFBundleDisplayName</key><string>CCRLog</string>`. The bundle ID
stays `nl.despaankamer.ccrlogger` — display name and bundle ID are
independent.

## 6. Version + build number — → action

Currently `pubspec.yaml`: `version: 1.0.0+1`. This maps to:
- `CFBundleShortVersionString` = `1.0.0` (marketing version — what
  users see in App Store)
- `CFBundleVersion` = `1` (build number — monotonically increasing per
  upload to App Store Connect)

→ For the **first TestFlight build**, `1.0.0+1` is fine.

→ Every subsequent upload needs the build number bumped (`+2`, `+3`,
…). App Store Connect rejects duplicate build numbers under the same
marketing version. There's a make-life-easier convention some teams
use: `version: 1.0.0+$(date +%s)` to auto-increment, but you can just
bump it manually in pubspec when you cut a build.

## 7. Build the IPA — → action

```bash
# Make sure everything still passes
flutter test
flutter analyze

# Clean build for release
flutter clean
flutter pub get
cd ios && pod install --repo-update && cd ..

# Build the release IPA (requires Xcode + a signing identity)
flutter build ipa --release
```

The artifact lands at `build/ios/ipa/ccrlogger.ipa`.

Common gotchas:
- If `pod install` fails on the macOS-SDK-shadowing issue, see the
  workaround already in `CLAUDE.md` under "Xcode 26 + Command Line
  Tools".
- If signing fails, open `ios/Runner.xcworkspace` in Xcode → Runner
  target → Signing & Capabilities → make sure "Automatically manage
  signing" is on and your team is selected. First time only.

## 8. App Store Connect setup — → action

Manual steps in https://appstoreconnect.apple.com (you have the
developer account active):

1. **My Apps → +** → New App
   - Platform: iOS
   - Name: "CCRLog" (or whatever display name you picked)
   - Primary language: English (UK or US)
   - Bundle ID: `nl.despaankamer.ccrlogger` — pick from the dropdown.
     If it's not there, create it first via Apple Developer →
     Certificates, Identifiers & Profiles → Identifiers → new App ID
     with that bundle ID.
   - SKU: anything unique (e.g. `ccrlog-ios`)
   - User access: Full Access

2. **App Information** tab
   - Category: Primary = "Sports", Secondary = "Productivity"
     (no "Diving" category exists; Sports is where Subsurface, Dive
     Mate, etc. live)
   - Content rights: "Does not contain, show, or access third-party
     content"
   - Age rating: 4+ (no objectionable content)
   - Privacy Policy URL: **required** — see §10 below

3. **Pricing and Availability**
   - Price: Free (most divelog apps are; sets expectations)
   - Availability: All countries or selected

4. **App Privacy** — answer the questionnaire matching the manifest:
   - Data Collected: Email, Crash Data, Performance Data, Coarse
     Location, Photos or Videos, User Content
   - Each: "Linked to user" yes, "Used for tracking" no
   - Purpose for all: "App Functionality" (+ Authentication for email)

5. **App Review Information** tab
   - Sign-in info: provide a test account (create one in Supabase
     specifically for review — `applereview@despaankamer.nl` or
     similar) so the reviewer can sign in without your real account.
   - Demo account: include if any features require login (subsurface
     sync, attachment upload). Sign-in optional for the basic dive
     viewer / planner / blender.
   - Notes: short paragraph explaining the app is for tech / CCR
     divers, requires a Shearwater BLE dive computer for the import
     feature (review can skip BT testing — the Plan and Blend tabs
     are fully exercisable without one).

## 9. Screenshots — → action

Apple requires screenshots for at least one device class. For a
first release the minimum is:

- **iPhone 6.7"** (iPhone 15 Pro Max, 16 Pro Max — 1290 × 2796 portrait)
- **iPhone 6.5"** (iPhone 14 Plus — 1242 × 2688) — optional now;
  Apple's auto-scales from 6.7"
- **iPad 12.9"** (iPad Pro — 2048 × 2732) — only required if your
  app supports iPad (`UISupportedInterfaceOrientations~ipad` is set,
  so yes)

3–10 screenshots per device class. Suggested CCRLog set:

1. **Dive list** — your live import showing real Petrel dives.
2. **Dive detail with profile chart** — the per-dive deep-dive view
   that's the differentiator.
3. **Cell health longitudinal chart** — the feature no other app has.
4. **Dive Plan tab** — Tx 18/45 plan with gas-safety chips visible.
5. **Bailout plan** — bailout section showing tank recommendations.
6. **Blend tab** — Tx 21/35 fill plan with hot-fill banner.
7. **Settings → Gas blending** — show the price + temp configuration.

→ Capture via `flutter run` on a real iPhone 15 Pro Max simulator (the
simulator screenshots match Apple's required pixel sizes). Save them
to `docs/app-store-assets/` (create the dir).

## 10. Privacy policy — → action

Apple **requires** a publicly-accessible privacy policy URL before
your app can go live. CCRLog already has a `PRIVACY.md` under `docs/`
that's a reasonable starting point.

Options:
- **Quick**: convert `docs/PRIVACY.md` to HTML and host it on a
  page under `despaankamer.nl/ccrlog/privacy` (you control that
  domain). Plug the URL into App Store Connect.
- **Cleaner**: stand up a tiny static GitHub Pages site on
  `egbertdepauw.github.io/ccrlogger/privacy/` and link it.

Mandatory contents (Apple's checklist):
- What data is collected (cross-reference the privacy manifest)
- How it's used + retained
- Third parties involved (Supabase, Cloudflare R2 via the
  attachment uploader, PowerSync, Sentry)
- How to request deletion ("delete your account in Settings, or
  email …")
- Children's data (we don't target under-13)
- Contact email

## 11. TestFlight (recommended) — → action

Before going to the App Store, ship to TestFlight first:

1. In Xcode: `Product → Archive` (after `flutter build ipa`, the
   archive is in Xcode's Organizer)
2. `Distribute App → App Store Connect → Upload`
3. Wait for the build to appear under App Store Connect → TestFlight
   (usually 15–30 min for processing)
4. Add yourself (and a couple of CCR-diving friends) as internal
   testers
5. Run the app for a week on the real Petrel + a real fill blend
6. Then submit the same build for App Store review

## 12. Submission — → action

App Store Connect → App → "Prepare for Submission":
1. Pick the TestFlight build for this version
2. Fill marketing copy (see §13)
3. Submit for review

Apple's review typically takes 24–48h for a fresh app, sometimes
longer for medical-adjacent apps. Diving isn't classified as medical,
but if the reviewer flags it, your "app description" should
explicitly say "for recreational and technical diving training; not a
substitute for proper dive planning software certified by …".

## 13. Marketing copy template

Fill these in App Store Connect → Prepare for Submission.

### Subtitle (30 chars max)
> *Tech & CCR dive log + planner*

### Promotional Text (170 chars)
> *Built for technical and CCR divers using Shearwater computers.
> Detailed dive analysis, per-cell health trends, gas planning, and
> partial-pressure blending — all offline-first.*

### Description (4000 chars)
> CCRLog is a dive log + planner built specifically for technical and
> CCR (closed-circuit rebreather) divers using Shearwater dive
> computers (Petrel 1/2/3, Perdix / Perdix AI / Perdix 2, Peregrine,
> NERD 2).
>
> Unlike general-purpose dive logs that treat CCR as an afterthought,
> CCRLog assumes the closed circuit is your default and surfaces the
> data that actually matters for cell health, bailout readiness, and
> gas planning.
>
> **What's in the app**
>
> • Import dives over Bluetooth from your Shearwater computer
> • Detailed multi-trace dive profile: depth, PPO2 (voted),
>   setpoint, individual cell mV, GF99, tank pressure, scrubber
>   time, solenoid fires
> • Longitudinal cell health analysis: track each O₂ cell's mV
>   trend across dozens of dives so you can spot drift before a
>   cell fails on you
> • Scrubber session tracking with minutes-used warnings
> • Surface GF, CNS %, OTU, gas density and END as first-class
>   numbers on every dive
> • Bailout-from-trigger planner: tells you how much OC bailout
>   you actually need to surface from the deepest moment of the
>   dive on your real tissue state
> • Dive planner: multi-level CCR and OC plans with per-gas
>   safety checks (MOD / END / PPO₂), drain recommendations,
>   gas-switch detection, and ICD warnings
> • Gas blending calculator: partial-pressure blending with
>   van-der-Waals real-gas math, hot-fill compensation, fill-
>   sequence options, and cost calculation
> • Equipment register: dive computers, cells, scrubber sessions,
>   cylinders
> • Optional cloud sync across all your devices
>
> CCRLog is built for Shearwater divers. Import from other brands
> isn't supported today.
>
> Disclaimer: CCRLog is a logging and analysis tool. Use a
> certified dive planner / dive computer for in-water decompression
> decisions and follow your training agency's standards.

### Keywords (100 chars total, comma-separated, no spaces around commas)
> *ccr,rebreather,dive,scuba,trimix,shearwater,divelog,deco,blender,gas*

### Support URL
> Anywhere you'll respond — could be `despaankamer.nl/ccrlog/support`
> or a GitHub Issues link.

### Marketing URL (optional)
> The product landing page if you have one. Leave blank if not.

## 14. Post-submission

After Apple approves the build, you flip "Release this version" to
either:
- **Manually** — you choose when it goes live
- **Automatically after approval** — Apple releases it immediately

For a first release I'd go manual so you can pick a calm day to
post on Scubaboard / r/ScubaDiving and watch for first-day support
emails.

---

## Quick recovery if something goes wrong at build time

| Symptom | Fix |
|---|---|
| "Library not loaded: @rpath/libgit2-…" at launch | `git2dart_binaries` workaround — see CLAUDE.md |
| "ld: building for 'iOS' but linking in dylib built for macOS" | CLT SDK shadowing — see CLAUDE.md |
| Pod install fails on `flutter clean` | `cd ios && rm -rf Pods Podfile.lock && pod install` |
| Archive failed: missing provisioning profile | Open Xcode → Signing & Capabilities → "Try Again" on the team picker |
| App Store rejection: privacy manifest mismatch | Open `ios/Runner/PrivacyInfo.xcprivacy` against the rejection email and adjust |
