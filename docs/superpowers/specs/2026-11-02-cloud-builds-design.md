# Cloud builds — design

Date: 2026-11-02
Status: approved by Egbert on 2026-11-02; not implemented
Context: `docs/RELEASE_AND_MONETISATION.md`,
`docs/superpowers/specs/2026-10-07-website-design.md`,
`docs/superpowers/specs/2026-10-07-subscriptions-entitlements-design.md`

## Why

Every Anchorline build that reaches a user is made by hand on Egbert's
Mac today: signing certificates, the notary profile and the Android
keystore live on that one machine, and a release means a long manual
checklist (`docs/BETA_DISTRIBUTION.md` §7) per platform. Windows builds
need a separate x64 machine. Before the app and its repository go public,
every build that ships should come from the cloud instead, so that:

- a release is one deliberate act (pushing a tag), not an evening of
  steps that only one machine can perform;
- what ships is built from the public source, in the open, which is what
  an open-source project's users can reasonably expect;
- collaborators can contribute without needing Egbert's machine or
  secrets.

## Goals

- Releases (`vX.Y.Z` tags) are built, signed and delivered for all five
  platforms by GitHub Actions, with no step on Egbert's Mac.
- Developer builds of `main` (nightlies) come from the same pipeline,
  on a schedule once the repository is public and on demand at any time.
- The cloud sets version and build numbers; nobody bumps them by hand.
- Signing secrets live in GitHub and are only readable by release and
  nightly runs.
- Windows, Linux and nightly desktop builds are published where the
  Anchorline website reads them.

## Non-goals

- Server code (`worker/`, the planned `server/` Subsurface sync service)
  and Dart packages such as the planned `packages/subsurface_core`. Their
  updates are rare and nobody installs them; they get their own pipelines
  when needed.
- Submitting to store review. The pipeline stops once builds are in
  TestFlight and in Google Play; Egbert submits and promotes by hand.
- Windows code signing at the start (see §7).
- Linux distribution packages, Homebrew, an Android APK download.
- Building the website itself.

## Anti-goals

- A build machine Egbert has to keep alive. No self-hosted runners: the
  goal is to get off his Mac, and GitHub advises that self-hosted runners
  "should almost never be used for public repositories".
- Secrets that a pull request, a fork, or a collaborator's branch can read.
- A nightly that damages someone's release install or its data.
- Focus on nightlies at the expense of releases. Releases are the point;
  nightlies reuse the same pipeline and stay simple.

## Decisions

"Egbert" marks his decisions in the design conversation; "my call" marks
choices made in writing this up, for him to check.

| Question | Decision | By |
|---|---|---|
| Scope of "all packages" | App builds only, all five platforms | Egbert |
| What is a release | A new version tag: `v1.2.0`, `v1.3.0`, or a hotfix `v1.2.1` | Egbert |
| What is a nightly | A developer build of `main`, for people who want the latest and accept the risk | Egbert |
| Phone nightlies | TestFlight (iOS) and Play internal testing (Android), for Egbert and a few collaborators | Egbert |
| Desktop nightlies | Public downloads on the website (macOS, Windows, Linux) | Egbert |
| Release numbering | Releases change the first two digits (`v1.2.0`); hotfixes the last (`v1.2.1`) | Egbert |
| Nightly numbering | The next release's version, told apart by build number (`1.3.0 (57)`) | Egbert, on my proposal |
| Where builds run | GitHub-hosted runners only | Agreed |
| Where the pipeline stops | Builds in TestFlight and Play; Egbert submits for review and promotes | Agreed |
| Nightly schedule while private | Off; on-demand only until the repo is public | Agreed |
| Windows signing | Unsigned at the start; a slot for signing later | Egbert |
| Desktop nightlies install next to the release | Yes, as "Anchorline Nightly" with separate data | Agreed |
| Website publish of a release | Automatic at the end of the release run | My call |
| GitHub Release per release tag | Yes, with notes and the Windows and Linux files | My call |
| Release notes source | The annotated tag's message | My call |
| Self-signed Windows certificate | No: it gives users no more trust than unsigned | My call |
| Fixing a release that turns out broken | Tags never move; the fix ships as the next patch | My call |
| Where desktop nightlies keep their data | A nightly-only folder; release data stays where it is | My call |
| Who can touch signing once public | One protected environment for `main` and `v*` tags; merges to `main` need Egbert's approval; branch dry runs build unsigned | My call |
| Who builds the website's publish command | This work, since the pipeline is its first user | My call |

## Design

### 1. What is built, for whom, and where it goes

| Platform | Release (`vX.Y.Z` tag) | Nightly (schedule or button) |
|---|---|---|
| iOS | `.ipa` uploaded to TestFlight, not given to the nightly testers | `.ipa` uploaded to TestFlight and added to the "Nightly" internal group |
| macOS | Mac App Store `.pkg` uploaded to TestFlight for Mac, not given to the nightly testers | Developer ID `.dmg`, notarised and stapled, on the website's nightly list |
| Android | `.aab` uploaded to Play's production track as a **draft** (or to closed testing while the account has no production access; see Rollout) | `.aab` on Play's internal testing track, rolled out |
| Windows | Inno Setup installer on the website and on the GitHub Release | Installer on the website's nightly list |
| Linux | AppImage (x64) on the website and on the GitHub Release | AppImage on the website's nightly list |

- Store builds go no further than TestFlight and a Play draft. Egbert
  tries them, then submits for review and rolls out by hand.
- After a hotfix release the pipeline starts a nightly run of `main`
  straight away (see §4), so phones in the nightly groups stay on a
  build newer than the hotfix.
- Developer builds on a developer's own machine (Egbert's, a
  collaborator's) stay for development and testing. They are never
  uploaded to a store or the website.

### 2. Versions and build numbers

**Release version** comes from the tag: `v1.2.0` → `1.2.0`.

- `vX.Y.0` tags must point at a commit on `main`.
- Hotfix tags `vX.Y.Z` with Z > 0 must point at a commit on the branch
  `release/X.Y`. That branch is created from the `vX.Y.0` tag only when a
  hotfix is needed. The fix lands on `main` first through a normal PR and
  is then cherry-picked onto `release/X.Y`.
- The tag must be annotated (it carries the release notes, §9).
- Any other tag shape (`v1.2`, `v1.2.0-beta`, a lightweight tag) stops
  the run before anything is built.
- **A tag is never moved or reused.** If a release turns out broken,
  whether a build fails on a code bug or a problem shows up in TestFlight
  before submission, the fix ships as the next patch (`v1.2.1` from
  `release/1.2`). A release whose Windows and Linux files reached the
  website is public anyway, so moving forward is the only consistent
  option. Infrastructure failures (a runner hiccup, an Apple outage) are
  retried with "Re-run failed jobs" on the same tag (§4). The prepare
  stage refuses a tag whose version is already in the website's releases
  list or has a GitHub Release.

**Nightly version** is the next release's version: take the highest
`vX.Y.Z` tag in the repository and add one to the middle digit, with the
last digit 0. After `v1.2.0` (and any `v1.2.N` hotfixes), nightlies are
`1.3.0`. With the current tags (`v1.1.0` only) the first cloud nightly is
`1.2.0`.

- Why not count nightlies in the last digit: hotfixes need it.
- Why the next version: App Store Connect refuses new builds for a
  version that is already live in the store, so a nightly must carry a
  version above the last release. A hotfix `1.2.1` can still follow
  nightlies of `1.3.0`, because Apple only compares against the last
  released version.

**Build number** is one counter shared by every cloud run, release or
nightly: `BUILD_NUMBER_BASE + github.run_number`.

- Every run of the single build workflow (§4) gets a new `run_number`,
  so the counter only goes up. Google Play rejects any build number it
  has seen on any track, which is why releases and nightlies cannot have
  separate counters.
- `BUILD_NUMBER_BASE` is a repository variable. Its first value must put
  the first cloud build above every build number already uploaded to
  Play and TestFlight (the highest known is 42; check both consoles).
  Proposed: 100.
- Renaming or recreating the workflow file restarts `run_number` at 1.
  Don't; if it happens, raise `BUILD_NUMBER_BASE`. The same applies after
  an emergency manual build (§11).
- Dry runs (§4) use numbers too. Gaps are fine.

**Example**

| Build | Version (build) | From |
|---|---|---|
| Release | 1.2.0 (154) | tag `v1.2.0` on `main` |
| Nightlies | 1.3.0 (155), 1.3.0 (156), 1.3.0 (157) | `main` |
| Hotfix | 1.2.1 (158) | tag `v1.2.1` on `release/1.2` |
| Nightly after the hotfix | 1.3.0 (159) | `main`, started by the hotfix run |
| Next release | 1.3.0 (163) | tag `v1.3.0` on `main` |

**`pubspec.yaml`'s `version:`** is no longer maintained. CI passes
`--build-name` and `--build-number`, which override it. Local developer
builds show whatever it says. The "chore(version): bump build number"
PRs stop.

**Where the logic lives:** a small Dart script under `tool/ci/`,
stdlib only, with unit tests. Input: the list of tags, the trigger (tag,
schedule, button) and the ref. Output: channel, version, build number,
and whether to build. Bash only glues it into the workflow.

### 3. Where builds run

All on GitHub-hosted runners, pinned so a silent image update can't
change a release.

| Jobs | Runner | Notes |
|---|---|---|
| iOS, macOS | `macos-26` (arm64) | Xcode pinned to one exact 26.x version, at least 26.1 (26.0's `altool` can attach a build to the wrong app). Today's default on the image is 26.6. |
| Android | `ubuntu-24.04` | `ubuntu-latest` is moving to 26.04 during November 2026; pin. |
| Linux | An Ubuntu LTS image, pinned | The oldest LTS image GitHub still offers is preferred, so the AppImage runs on older distributions (builder verifies, §12). |
| Windows | `windows-2025` | Real x64, so the Windows-on-ARM problem (#3) does not affect shipping builds. |
| Prepare, tests, publishing, TestFlight group assignment | `ubuntu-24.04` | Anything that waits (e.g. on Apple's build processing) runs here, never on a Mac, because Mac minutes cost ten times more while the repo is private. |

**Toolchain pins and traps**

- **Flutter**: one pinned version, read from one place shared with
  `check.yml` (3.44.0 today). Bumping Flutter stays a deliberate PR.
- **JDK**: pinned with `actions/setup-java` (Temurin 21) on Android,
  Windows and Linux. Windows and Linux need it because `sentry_flutter`
  pulls in `package:jni`. CI does not use Android Studio's bundled JBR, so
  the local JBR trap from `toolchain-gotchas` doesn't apply there; the
  Gradle 9.3.1 / AGP 8.13.2 / KGP 2.3.20 coupling stays untouched.
- **iOS release link error** (`libobjc.A.tbd ... built for 'macOS
  macCatalyst zippered'`): the Apple jobs `unset LIBRARY_PATH SDKROOT`
  and select the pinned Xcode explicitly. If the error still appears on
  the runner, moving `/Library/Developer/CommandLineTools/SDKs` aside with
  `sudo` is allowed there. Research on 2026-11-02 suggests the local cause
  on Egbert's Mac is a `LIBRARY_PATH` export in a shell profile rather
  than the Command Line Tools SDK; see "Follow-ups".
- **`git2dart_binaries`' macOS `libgit2.dylib` needs macOS 26** at
  runtime. That affects users, not the build; the runner's OS doesn't
  matter for building.

### 4. The pipeline

One workflow, `.github/workflows/build.yml`, so that every run shares
one `run_number` (§2). It may call reusable per-platform workflows; those
share the caller's run number. `check.yml` stays as it is.

**Triggers**

| Trigger | Channel | Delivers |
|---|---|---|
| Push of a tag matching `v*` | release | As in §1, release column |
| Schedule (nightly, e.g. 02:00 UTC) | nightly | As in §1, nightly column. Only if `main` changed since the last nightly that delivered. Off while the repo is private (repository variable, e.g. `NIGHTLY_SCHEDULE=on`). |
| "Run workflow" button on `main` | nightly | Same as a scheduled nightly, but always builds |
| "Run workflow" button on any other branch, or with `dry_run` ticked | dry run | Builds and signs everything, uploads nowhere. For testing pipeline changes from a PR branch. |

The button has an input to pick platforms (default: all), so a
TestFlight build for Egbert's phone doesn't have to wait for Windows.

**Stages**

1. **Prepare** (Linux). Runs the version script (§2). For a release:
   validates the tag rules and reads the tag message. For a scheduled
   nightly: compares `main` with the commit of the last nightly that
   delivered and stops if nothing changed. Checks the Apple certificates'
   expiry (§7). Runs `flutter analyze` and `flutter test`, so nothing
   ships from a red commit even if `check.yml` was skipped.
2. **Build** (five jobs in parallel, no fail-fast). Each builds, signs
   and uploads its platform. A failing platform doesn't stop the others.
3. **Deliver** (Linux, after the builds it needs):
   - TestFlight: for nightlies, wait for Apple's processing and add the
     iOS build to the "Nightly" internal group.
   - Website: upload the desktop files and update the manifest (§8). For
     a release this needs both Windows and Linux to have succeeded; for a
     nightly, each platform that succeeded is listed.
   - GitHub Release (releases only): notes, Windows and Linux files,
     and a `SHA256SUMS` file.
   - After a hotfix (Z > 0): start a nightly run of `main` through
     `workflow_dispatch`, so nightly testers stay on a newer build
     (allowed with `GITHUB_TOKEN`; needs `actions: write`).

**Failures and re-runs**

- GitHub's failure email is the notification.
- "Re-run failed jobs" keeps the run number and so the build number;
  jobs that already uploaded are not repeated. "Re-run all jobs" would
  try to upload the same build number again and be refused by the
  stores. The docs say so. Treating "this build already exists" as
  success in the upload steps is a nice-to-have.
- Each job has a timeout, so a hung Apple upload can't burn Mac minutes
  for hours.
- Workflow artifacts (files passed between jobs) are kept 1–3 days. The
  durable copies are in the stores, the bucket and GitHub Releases.

### 5. Per platform

**iOS.** Flutter build, `pod install` from the committed `Podfile.lock`,
archive and export with the App Store profile, upload with the App Store
Connect API key (`xcrun altool --upload-package ... --apple-id <app id>`,
or `xcodebuild -exportArchive` with `destination=upload`; builder's
choice). With Xcode 26 `altool`'s exit code is unreliable, so its output
is checked too. dSYMs go to Sentry (§10).

**macOS.** One archive per run.

- Release: export with `macos/export_options_mas.plist` (signing switched
  to manual for CI), upload the `.pkg` to App Store Connect.
- Nightly: export with `macos/export_options_devid.plist` under the
  nightly identity (§6), notarise with `notarytool` using the API key,
  staple, wrap in a `.dmg`, sign and notarise the `.dmg`.
- dSYMs go to Sentry (§10).

**Android.** `flutter build appbundle --release`. The upload keystore and
`android/key.properties` are written from secrets at build time, at the
paths the local build uses. Uploaded with the Google Play Developer API:
releases to the production track with status `draft`, nightlies to the
internal track rolled out.

**Windows.** `flutter build windows --release`, then Inno Setup 6
(`windows/installer/anchorline.iss`, installed on the runner if the image
lacks it). Unsigned at the start. A signing step sits between the build
and the installer, and on the installer itself, switched off until
signing exists (§7).

**Linux.** `flutter build linux --release` (x64) after installing the
build dependencies (GTK 3, ninja, clang, libsecret for
`flutter_secure_storage`, and whatever else the plugins need), then an
AppImage. `linux/CMakeLists.txt` still has the template's
`APPLICATION_ID "com.example.ccrlogger"` and `BINARY_NAME "ccrlogger"`;
they become `nl.despaankamer.ccrlogger` and `anchorline` first. No Linux
users exist yet, so the change of data folder this causes is harmless.

### 6. Nightlies on the desktop: a separate app

A desktop nightly installs next to the release as "Anchorline Nightly"
and shares no local state with it: not the databases, the Subsurface
clone, logs, preferences, secure storage or caches. Then a nightly that
changes the local database format can't break someone's release install.

| Platform | Release | Nightly |
|---|---|---|
| macOS | `nl.despaankamer.ccrlogger`, "Anchorline" (Mac App Store) | `nl.despaankamer.ccrlogger.nightly`, "Anchorline Nightly" (`.dmg`) |
| Windows | Inno `AppId` as today, "Anchorline", `ProductName` "Anchorline" | A new, fixed `AppId`, "Anchorline Nightly", its own install folder, `ProductName` "Anchorline Nightly" |
| Linux | `nl.despaankamer.ccrlogger` | `nl.despaankamer.ccrlogger.nightly` |

**Where the data goes.** A different identity is not enough on its own:

- The app opens `ccrlogger.sqlite`, `powersync.db`, `subsurface_clone/`
  and the BLE debug log in `getApplicationDocumentsDirectory()`
  (`lib/main.dart`, `lib/sync/cloud/powersync_database.dart`,
  `lib/ui/app_shell.dart`, `lib/shearwater/ble/ble_debug_logger.dart`).
- On macOS that folder is inside the app's sandbox container, so the
  nightly bundle id separates it.
- On Windows and Linux it is the user's own Documents folder, the same
  for every app. A nightly there would open the release's database.
- So nightly builds (`BUILD_CHANNEL=nightly`) keep all of these in a
  nightly-only folder: the application support folder of the nightly
  identity, or an "Anchorline Nightly" subfolder; builder's call, as long
  as no file is shared. One place in the code decides the data folder, so
  no path is missed.
- Release builds keep today's location in this work. That the release
  app's data sits loose in Documents (and on Windows is often synced by
  OneDrive) is its own problem; see "Follow-ups".

Other notes:

- The macOS nightly bundle id needs its own App ID in the Apple
  developer portal and a Developer ID provisioning profile, because the
  app uses the restricted `keychain-access-groups` entitlement
  (`macos/Runner/Release.entitlements`).
- Phone nightlies keep the release identity. TestFlight and Play's
  internal track replace the store app on the few testers' phones, which
  is what they signed up for.
- The cost: a free user (no sync) starts a desktop nightly with an empty
  logbook and re-imports from the dive computer. Paying users get their
  dives back by signing in.
- Every nightly shows that it is one: "Nightly", version and build
  number in its About/Settings screen.

**Build-time settings CI passes** (`--dart-define`)

| Setting | Values | Read by |
|---|---|---|
| `BUILD_CHANNEL` | `release`, `nightly` | Nightly label (above), Sentry environment (§10) |
| `DISTRIBUTION_CHANNEL` | `app_store`, `play_store`, `website` | The update check (website spec) and how a subscription is bought (subscriptions spec). Both specs call for "a build-time setting"; this fixes its name and values. |

The other existing defines (`SENTRY_DSN`, `POWERSYNC_ENDPOINT`,
`ATTACHMENTS_SIGNER_URL`) keep their compiled-in defaults, exactly as in
today's local release builds; none of them is secret. Nightlies use the
same production servers as releases, because that's where people's dives
live.

### 7. Signing and secrets

**What GitHub holds** (names are suggestions; builder's call)

| Secret | What | Used by |
|---|---|---|
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` | App Store Connect API key: a **Team** key with the App Manager role. Replaces the app-specific password for notarising, too. | iOS, macOS, TestFlight group assignment |
| `APPLE_DISTRIBUTION_P12` + password | Apple Distribution certificate | iOS, Mac App Store |
| `MAC_INSTALLER_P12` + password | Mac Installer Distribution certificate | Mac App Store `.pkg` |
| `DEVELOPER_ID_P12` + password | Developer ID Application certificate | macOS nightly `.dmg` |
| Provisioning profiles | iOS App Store, Mac App Store, Developer ID (nightly bundle id) | iOS, macOS. Stored as secrets or fetched with the API key at build time; builder's call. |
| `ANDROID_KEYSTORE` + `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` | The existing upload keystore | Android |
| `PLAY_SERVICE_ACCOUNT_JSON` | A Google service account with release rights on this app only | Android |
| `SENTRY_AUTH_TOKEN` | The existing org token (`project:releases`) | iOS, macOS |
| R2 credential | Limited to reading and writing the downloads bucket: a Cloudflare API token if the publish command uses `wrangler`, or an R2 access key pair if it uses an S3 client | Publishing (§8) |

Non-secret settings (bucket name, account id, public base URL,
`BUILD_NUMBER_BASE`, `NIGHTLY_SCHEDULE`) are repository variables.

**How the secrets get there.** Egbert exports them on his Mac and runs
`gh secret set NAME < file`. Values are never echoed, logged or pasted
into a chat; base64 files are decoded into `$RUNNER_TEMP` during a job.
The originals stay backed up in 1Password, where the keystore already
lives.

**Signing on the Mac runners** is manual: the `.p12` files go into a
temporary keychain created per job (e.g. `apple-actions/import-codesign-certs`).
Xcode's cloud-managed signing is not used, because it doesn't cover the
Developer ID path from CI (Apple bug FB16835802, still open in October
2026).

**Expiry.** Apple Distribution and Mac Installer certificates last one
year and their profiles expire with them; Developer ID lasts five years.
The prepare stage warns 30 days before any expiry and fails with a clear
message after it, so an expired certificate never surfaces as a cryptic
signing error halfway through a release.

**Who can read the secrets**

- While the repo is private: repository secrets. Only Egbert has write
  access. `check.yml` and anything triggered by a pull request never use
  secrets, and no workflow uses `pull_request_target`.
- When the repo goes public, before the nightly schedule is switched on:
  - secrets move into one environment, `signing`, that only runs from
    `main` and from `v*` tags. Releases and nightlies need nearly the
    same keys, so splitting them would protect little. Environments are
    free on public repos; on a private repo they need a paid plan;
  - a branch ruleset on `main` requires a pull request approved by
    Egbert, so nobody else can merge a workflow change that reads the
    keys. No required reviewer on the environment itself, so scheduled
    nightlies don't wait for a click;
  - a tag ruleset lets only Egbert create or delete `v*` tags;
  - workflows from outside contributors' pull requests need approval
    before running;
  - dry runs from other branches can't reach the environment, so they
    build without signing or uploading. A signing change is proven by a
    button run on `main` after merging. Before the repo is public, dry
    runs can still sign, since the secrets are repository secrets.
- Third-party actions are pinned to commit SHAs, with Dependabot keeping
  them current. Each job declares the least `permissions` it needs
  (`contents: write` only where a GitHub Release is made, `actions:
  write` only where the post-hotfix nightly is started).

**Windows signing (later).** The recommended route when it's wanted is
Microsoft's Artifact Signing, Basic tier ($9.99 a month), under De
Spaankamer BV, so Windows shows the BV as publisher. It logs in from
GitHub with OIDC, so no secret is stored. It needs a KvK extract, an
`@despaankamer.nl` address, an ID check, possibly a BV at least three
years old, and up to 20 working days for approval. SmartScreen's
"unknown app" warning stays for the first weeks whatever the signing,
until downloads build reputation. Until then the website mentions the
"More info → Run anyway" click.

### 8. Publishing to the website

The website spec's bucket and releases list are used as designed, with
three changes.

1. **Who writes.** The website spec says only Egbert's machine writes
   the bucket. That becomes: only the build pipeline writes it, with the
   R2 credential in §7. The spec's publish command (uploads, verifies
   each file, writes `manifest.json` last, refuses to overwrite an
   existing version) runs in CI. Egbert can still run it by hand in an
   emergency. The command doesn't exist yet. The website spec already
   places it in this repository, and this work builds it, because the
   pipeline is its first user; the website project only reads the
   bucket. Its tool (`wrangler` or an S3 client) is the builder's call.
2. **Nightly list.** A second list, `nightly/manifest.json`, with the
   same format-1 shape as `releases/manifest.json`. Files go under
   `nightly/<version>-<build>/`, e.g.
   `nightly/1.3.0-157/Anchorline-Nightly-1.3.0-157-windows-x64.exe`. A
   nightly stays for two weeks: the publisher drops older entries from
   the list, and an R2 lifecycle rule on the `nightly/` prefix deletes
   the files. Release files are kept indefinitely.
3. **macOS key.** Nightly lists carry a `macos` entry (the `.dmg`) next
   to `windows-x64` and `linux-x64`. Readers already ignore keys they
   don't know.

- Release files are named as in the website spec:
  `Anchorline-1.2.0-windows-x64.exe`, `Anchorline-1.2.0-linux-x64.AppImage`.
- The bucket is filled from the first cloud release on, even before the
  website exists. Until the domain does, links use the bucket's public
  URL.
- A release goes live on the website automatically at the end of its
  run (my call): the tag is already the deliberate act, and the same
  code has run as nightlies first. To pull a bad release, the publish
  command gains a "roll back" action that makes a previous version
  `latest` again without deleting anything.

### 9. Release notes

- **Releases:** the annotated tag's message, as written for `v1.1.0`. It
  becomes the GitHub Release body and the website's `notes`. A tag
  without a message stops the release in the prepare stage.
- **Store "What's new":** typed by Egbert when he submits for review.
  Not automated.
- **Nightlies:** generated: the subjects of the commits on `main` since
  the previous nightly (one per merged PR, since PRs are squash-merged).
  They go into the nightly list's `notes`.

### 10. Sentry

- Release and nightly builds report under the Sentry release
  `nl.despaankamer.ccrlogger@<version>+<build>` with environment
  `release` or `nightly` (from `BUILD_CHANNEL`), so nightly crashes don't
  mix with release ones. This needs a small app change where Sentry is
  initialised (`lib/main.dart`).
- iOS and macOS jobs upload dSYMs with `sentry_dart_plugin`, as
  `macos/scripts/upload_sentry_dsyms.sh` does by hand today, with the
  token from §7.
- Symbols for Android, Windows and Linux stay out of scope, as today.

### 11. When the pipeline is broken

Shipping doesn't depend on the pipeline alone. The existing manual docs
(`docs/BETA_DISTRIBUTION.md`, `docs/MACOS_DISTRIBUTION.md`,
`docs/TESTFLIGHT_QUICKSTART.md`, `docs/WINDOWS_DISTRIBUTION.md`) stay as
the emergency route, marked as such. An emergency manual build uses a
build number above the last cloud build, and `BUILD_NUMBER_BASE` is then
raised so the next cloud build is above it again.

## Cost

Prices checked on 2026-11-02
([GitHub runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing),
[included usage](https://docs.github.com/en/billing/concepts/product-billing/github-actions)).
Minutes are estimates, to be replaced by measured times after the first
runs.

| Job | Runner | Minutes | Cost while private |
|---|---|---|---|
| Prepare and tests | Linux, $0.006/min | 8 | $0.05 |
| iOS | macOS, $0.062/min | 20 | $1.24 |
| macOS | macOS | 25 | $1.55 |
| Android | Linux | 12 | $0.07 |
| Windows | Windows, $0.010/min | 15 | $0.15 |
| Linux | Linux | 10 | $0.06 |
| Deliver (TestFlight wait, website, GitHub Release) | Linux | 15 | $0.09 |
| **One full five-platform run** | | | **about $3.20** |

- **While the repo is private:** GitHub Free includes $12 of runner time
  a month (about four full runs), Pro $18. With no nightly schedule and
  a few button runs and releases a month, expect $0–15 a month. Going
  over the included amount needs a payment method on file; without one,
  jobs stop. Mac-only button runs (iOS for Egbert's phone) cost about
  $1.30.
- **Once the repo is public:** $0. Standard GitHub-hosted runners, Macs
  included, are free and unlimited for public repositories, so the
  nightly schedule costs nothing.
- **Storage:** workflow artifacts kept 1–3 days stay inside the free
  500 MB. R2 stays inside its free 10 GB with two weeks of nightlies
  (three desktop files of about 60–100 MB each per nightly) plus
  releases.
- **Windows signing, when wanted:** $9.99 a month (about $120 a year).
- Apple's and Google's developer fees are already paid and don't change.

## Changes to other documents and code

- **Website spec** (`2026-10-07-website-design.md`): the bucket is
  written by the pipeline; the nightly list; the `macos` key; the
  publish command's "roll back" action (§8).
- **Distribution docs** (`BETA_DISTRIBUTION.md`, `MACOS_DISTRIBUTION.md`,
  `TESTFLIGHT_QUICKSTART.md`, `WINDOWS_DISTRIBUTION.md`,
  `APP_STORE_SUBMISSION.md`): a new short `docs/RELEASING.md` describes
  the cloud flow (tag, check TestFlight/Play, submit, hotfix branches,
  re-runs, secrets renewal); the old docs get a banner saying they are
  the emergency route, and their versioning sections point to §2.
- **`CLAUDE.md` and memory:** no more version-bump PRs; releases are
  tags.
- **App code:** `BUILD_CHANNEL` and `DISTRIBUTION_CHANNEL` read and
  shown; Sentry release and environment; the desktop nightly identity
  and its own data folder (§6); the Linux `APPLICATION_ID` and binary
  name.
- **`windows/installer/anchorline.iss`:** its comment says the data
  lives under `%LOCALAPPDATA%`; it actually lives in Documents (§6).
  Correct the comment, and give the nightly variant its own `AppId`.

## Rollout

Each step is its own PR, following the usual issue → branch → PR flow.

| Step | Result |
|---|---|
| 1 | Version script with tests; app reads `BUILD_CHANNEL` / `DISTRIBUTION_CHANNEL`, shows the nightly label, sets Sentry's environment, and gives desktop nightlies their own data folder; Linux id fix |
| 2 | Accounts and secrets set up (checklist below) |
| 3 | `build.yml` in dry-run form: all five platforms build and sign, nothing is uploaded. Run from a branch. |
| 4 | Nightly delivery via the button: TestFlight Nightly group, Play internal, the bucket's nightly list. Desktop nightly identity verified. |
| 5 | The next release (`v1.2.0` or whatever is next) built and delivered by the cloud end to end. Egbert promotes it in the stores. |
| 6 | `docs/RELEASING.md`, banners on the old docs, CLAUDE.md update |
| 7 | When the repo goes public: the `signing` environment, the `main` and tag rulesets, outside-contributor approval, then `NIGHTLY_SCHEDULE=on` |
| Later | Windows signing |

**Set up outside the code (step 2)**

- App Store Connect: a Team API key (App Manager); a "Nightly" internal
  TestFlight group with **automatic distribution off**, so release and
  hotfix builds don't reach it (the setting may be fixed when a group is
  created, so make a new group); the highest build numbers already used
  for iOS and macOS.
- Apple developer portal: App ID `nl.despaankamer.ccrlogger.nightly`; a
  Developer ID provisioning profile for it; the three certificates
  exported as `.p12`.
- Google Play: a service account with release rights on Anchorline; the
  highest `versionCode` already used; whether the developer account has
  production access. Personal accounts created after November 2023 must
  first run a closed test (12 testers for 14 days). Until it has access,
  release builds go to a closed testing track instead of a production
  draft.
- Cloudflare: the downloads bucket (the beta docs named it
  `anchorline-downloads`), public access, a lifecycle rule for
  `nightly/`, a token limited to that bucket.
- GitHub: secrets and variables (§7); a payment method if runs will
  exceed the included amount while private.

## Testing

- **Version script:** unit tests for no tags, `v1.1.0` → nightly `1.2.0`,
  hotfix tags present, the highest tag being a hotfix, every invalid tag
  shape, tags on the wrong branch, build-number arithmetic.
- **Publish command:** as in the website spec (dry run, scratch bucket,
  refusal to overwrite, manifest last), plus the nightly list's pruning.
- **Pipeline:** dry runs from a branch before anything is delivered.
- **Before the first cloud release, check by hand on real devices:**
  - an iOS nightly appears in the Nightly group and installs; a release
    build doesn't reach that group;
  - the Play internal build installs; the release draft is on production;
  - the macOS `.dmg` opens with no Gatekeeper warning (`spctl -a -vv`)
    and installs next to the Mac App Store version, with separate data;
  - the Windows nightly installs next to a release install, with separate
    data, and both uninstall cleanly;
  - the Linux AppImage starts on a clean Ubuntu LTS and one other
    distribution, and BLE import and Subsurface sync load their native
    libraries;
  - a test event from a nightly shows in Sentry with environment
    `nightly` and, on macOS, symbolicated frames.

## Left to the builder

- Workflow file layout (one file or reusable workflows), job names, and
  which community actions to use.
- The upload tool for App Store Connect, how provisioning profiles are
  obtained, and the tool for the TestFlight group assignment, keeping to
  the project's dependency-light preference.
- AppImage tooling, the Linux runner image, and the Linux build
  dependencies.
- Exact secret and variable names.
- The nightly schedule's time of day.

## Risks and open items

- **Linux has the least mileage.** A release build has run once
  (#120); an AppImage has never been made. Plugin support on Linux (BLE
  through BlueZ, secure storage through libsecret) and the system
  libraries `git2dart_binaries`' `libgit2.so`/`libssh2.so` expect (likely
  OpenSSL) must be checked on a clean machine.
- **Play app state.** If Google still counts the app as a draft, it only
  accepts draft releases. Internal testing has been rolled out before, so
  this is unlikely, but the first upload will tell.
- **Starting build number.** Must be checked in both consoles before
  `BUILD_NUMBER_BASE` is set.
- **GitHub plan.** Free or Pro only changes the included amount while
  private.
- **Windows SmartScreen.** Unsigned installers show a warning until
  signing exists and reputation has built up.
- **macOS sync floor.** The `.dmg` inherits the existing caveat:
  Subsurface sync needs macOS 26 and Apple Silicon.

## Follow-ups outside this design

- **Desktop data in the Documents folder.** On Windows and Linux the
  release app keeps its databases and the Subsurface clone directly in
  the user's Documents folder. That clutters a user folder and, on
  Windows, often puts a live SQLite database under OneDrive sync, which
  risks corruption. Moving it to the application support folder needs a
  one-time migration for existing installs and is its own piece of work.
- `toolchain-gotchas` may describe the wrong cause of the iOS release
  link error. Research on 2026-11-02 points to a `LIBRARY_PATH` export
  (still in `~/.bash_profile`, commented out in `~/.zshenv` since
  2026-05-13) rather than the Command Line Tools SDK. Command Line Tools
  27.2, installed on 2026-11-02, has put the SDK folder back, so the next
  local `flutter build ipa --release` will show which explanation is
  right.
