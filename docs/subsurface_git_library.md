# Subsurface git sync — library investigation (Phase C)

**Status: ESCALATION — no library cleanly supports iOS today.**

This document captures the investigation done in Phase C of the Subsurface
git sync feature. Phase C is the FFI/native-library wrapper around a libgit2
binding that Phase D will drive (clone, pull, commit, push) against the
user's Subsurface Cloud git repo (`ssrf-cloud-eu.subsurface-divelog.org/git/<email>`,
HTTP basic auth).

The architectural memo (`memory/project_subsurface_git_sync.md`) said
"libgit2dart on every platform". When we went to verify, libgit2dart turned
out to be discontinued, and none of the live alternatives are a clean iOS
fit. Phase C is therefore blocked on a product decision before any wrapper
code is written. **No code was added to `lib/sync/subsurface_git/` in
this phase** — only this doc.

## What Phase C needed from a library

- Clone over HTTPS with HTTP basic auth (username + password from the OS
  keychain).
- Pull (fetch + fast-forward) with the same auth.
- `git add -A` equivalent (stage every file under the work tree, including
  deletes).
- Commit with a custom author identity.
- Push to origin, again HTTP basic auth.
- Runs in-process on iOS, Android, macOS. (The CCRLog app ships on all
  three; sync is per-device, no server-side proxy.)

## Candidates investigated (2026-05-08)

### 1. `libgit2dart` — DISCONTINUED

- pub.dev: <https://pub.dev/packages/libgit2dart>
- Last published: ~3 years ago.
- Listed platforms: Linux, macOS, Windows. **No iOS, no Android.**
- pub.dev marks the package "discontinued".
- This was the package the architectural memo named, but it has not been
  viable for some time. The memo is out of date.

### 2. `git2dart` (+ `git2dart_binaries`) — best maturity, **no iOS**

- pub.dev: <https://pub.dev/packages/git2dart> (v0.4.0, ~5 months old,
  verified publisher `dartgit.dev`)
- High-level API: `Repository`, `Remote`, `Credentials.userPass(...)`,
  `Repository.clone`, push/pull helpers. Matches what we need.
- Listed platforms (both `git2dart` and `git2dart_binaries` on pub):
  Android, Linux, macOS, Windows. **iOS is explicitly absent.**
- The `git2dart_binaries` repo (<https://github.com/dartgit-dev/git2dart_binaries>)
  has `android/`, `linux/`, `macos/`, `windows/` directories and **no
  `ios/` directory**. There are no shipped iOS binaries.
- Building libgit2 + libssh2 + mbedTLS for iOS ourselves and bolting them
  into a vendored fork is technically possible but a significant ongoing
  maintenance commitment (libgit2 + transitive deps, App Store
  bitcode/sign rules, simulator vs. device fat binaries, every Flutter
  upgrade, every libgit2 CVE).
- This is the option I'd pick if iOS were not on the table.

### 3. `dart_git` — pure Dart, abandoned

- pub.dev: <https://pub.dev/packages/dart_git>
- Pure Dart, so platform support is "wherever Dart runs" — including iOS.
- Last published 4 years ago. Repo states "experimental" and "subset of
  features required by GitJournal".
- The user's spec for Phase C explicitly said **do not pick `dart_git`
  without explicit justification — limited capability, not libgit2-class.**
- Push support and HTTP basic auth are not documented as working. Even if
  some CRUD path works, the Subsurface push will exercise corner cases
  (delta packfiles, fetch negotiation) that experimental implementations
  routinely miss.

### 4. `libgit2` (manichord) — abandoned stub

- pub.dev: <https://pub.dev/packages/libgit2> (v0.0.1, ~4 years ago)
- Lists iOS as a supported platform.
- README explicitly states most features are unimplemented (only a
  version probe works). Not a real option.

### 5. `git_bindings` (gitjournal.io) — Dart-3-incompatible

- pub.dev: <https://pub.dev/packages/git_bindings>
- iOS + Android, libgit2-based.
- Last published ~5 years ago, marked **Dart 3 incompatible**. CCRLog is
  on Dart 3.11.5; this package will not even resolve.

### 6. `ligit` (elias8) — claims iOS, but day-1 immature

- pub.dev: <https://pub.dev/packages/ligit> (v0.0.1, 18 days old,
  unverified uploader)
- Repo: <https://github.com/elias8/libgit2/tree/main/packages/ligit>
- Releases ship iOS dylibs:
  `libgit2-aarch64-ios.dylib`, `libgit2-aarch64-ios-simulator.dylib`,
  `libgit2-x86_64-ios-simulator.dylib`. Promising.
- Uses Dart's new build hooks (`hooks` + `code_assets`). That toolchain
  is itself still stabilizing; whether it produces a binary that passes
  App Store review (signing, embedded frameworks, bitcode) is unverified.
- Surface is **raw FFI bindings**, not a `Repository.clone`-style API.
  README/example show `init` + `commit` only. No clone, push, pull,
  remote, or credentials example. Unverified publisher.
- Picking this would mean: write our own clone/push/pull/credentials
  layer over raw libgit2 FFI, in a package that's two weeks old and has
  one example, while also being our first iOS shipper of the new Dart
  build-hook system. That is exactly the silent-pivot the user warned
  against.

### 7. Shell out to system `git` (`package:git`) — works on macOS desktop, **not on iOS**

- iOS doesn't ship a usable `git` binary and an App Store app cannot
  fork+exec arbitrary binaries it didn't ship itself. Same for Android
  in practice.
- Useful as a *desktop-only* fallback. Not a cross-platform answer.

## Recommendation: escalate

The user needs to choose between:

### Option A — Server-side sync (Cloudflare Worker / similar)

CCRLog generates the Subsurface text files locally and pushes them as a
JSON payload to a Worker that we run. The Worker holds the user's
Subsurface Cloud password (encrypted at rest), runs git on real Linux,
and pushes to Subsurface Cloud on the user's behalf.

- Pro: iOS, Android, macOS all work identically. The git operation runs
  somewhere with `git` and `libgit2` as native, well-tested code.
- Pro: Subsurface Cloud only sees one client identity per user (ours).
  No mobile-keychain-vs-desktop-keychain-drift.
- Pro: Aligns with how the rest of CCRLog's cloud sync already works
  (PowerSync + Supabase REST + the existing attachment-signing Worker).
- Con: Server cost / operational surface. We now have a service that
  holds Subsurface passwords. That's a meaningful security responsibility
  even with envelope encryption.
- Con: Adds latency. The user is offline-first; this introduces a
  network dependency for the sync step specifically (which is already
  network-dependent against Subsurface Cloud, so the marginal cost is
  small).
- Con: One more service to keep alive — long after the user has stopped
  using CCRLog actively, the Worker still has to be paid for.

### Option B — Desktop / macOS only sync, iOS gets the file-share fallback back

Use `git2dart` on macOS / Android (and ship the wrapper on those
platforms only), and on iOS keep / restore the existing UDDF-export
+ share-sheet fallback. Subsurface iOS can't import files, but
Subsurface macOS can, and a tech diver who logs on phone usually
also has a Mac — they sync from the Mac.

- Pro: No server. No backend liability. Wrapper code is small.
- Pro: `git2dart` is mature enough that this would actually ship.
- Con: iOS users have a worse experience than Android/macOS users for
  no reason intrinsic to their platform. That's a product smell.
- Con: We have to maintain two sync paths (git push + file share).
- Con: Contradicts the original architectural memo's "libgit2dart on
  every platform" goal.

### Option C — Wait, ship desktop now, revisit iOS

Pick `git2dart`, build the wrapper, ship sync on macOS + Android first,
and revisit iOS in 6–12 months. Either `ligit` matures (clone/push/auth
land + reports of App Store acceptance show up), or we pay the cost of
patching `git2dart_binaries` to also ship iOS dylibs ourselves.

- Pro: We don't block the rest of Phase C–E waiting for iOS.
- Pro: Lowest immediate cost.
- Con: Same UX gap as Option B until the iOS path lands.

## What was NOT done in Phase C

- No new packages were added to `pubspec.yaml`.
- No code was added to `lib/sync/subsurface_git/`.
- No tests were added under `test/sync/subsurface_git/`.
- No iOS / macOS Podfile changes.

The credentials store, repo wrapper, and tests in the Phase C spec are
all still TBD pending the A/B/C decision above. Once a path is picked
this doc can become "Subsurface git sync — library choice" with the
rationale.
