# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & development commands

```bash
# Run the app (debug, pick a device/simulator)
flutter run

# Run all tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Static analysis (uses flutter_lints via analysis_options.yaml)
flutter analyze

# Get/update dependencies
flutter pub get

# Code generation (needed after changing Drift schemas, once Drift is added)
dart run build_runner build --delete-conflicting-outputs

# Format code
dart format lib/ test/
```

**SDK requirement:** Dart ^3.11.5 (see pubspec.yaml `environment.sdk`).

## What this project is

A mobile-first dive logging and analysis app for **technical and CCR divers**, with a deliberate focus on **Shearwater dive computers** (Petrel 1/2/3, Perdix / Perdix AI / Perdix 2, Peregrine / Peregrine TX, NERD 2). The audience is people diving JJ-CCR, SF2, X-CCR, Choptima, Liberty, and similar units that use a Petrel as the controller, plus OC tech divers using Perdix or Peregrine.

This is **not** a Subsurface clone. Subsurface is a generalist divelog that has to serve freedivers, recreational, tech, and CCR from the same UI; this app makes the opposite trade and assumes CCR is the default case, OC is degenerate. The differentiator is post-dive analysis that doesn't exist anywhere else mobile-friendly today: per-cell mV trends across the lifetime of the cell, scrubber session tracking, solenoid fire analysis, surfGF/CNS/OTU as first-class numbers, and gas density / END overlays on the profile.

The project is **open source** (license TBD — likely GPLv2 or AGPLv3 to align with the dive software ecosystem; revisit before first public release).

Development is **solo for now**, possibly with collaborators later. There is **no timeline pressure** — this is a build-it-right-the-first-time project, not a ship-fast project. Optimize for code that someone else (or future-self) can pick up and understand, not for shipping speed.

## Why this project exists

The data needed for serious post-dive analysis has been logged in Shearwater dive logs for years, and nobody surfaces it well:

- **Shearwater Cloud** is fundamentally a backup utility for Shearwater customers, not an analysis tool.
- **Subsurface** is a generalist log; CCR is supported but not central to the design. Mobile-side it's a Qt port and feels like one.
- **MultiDeco** is a planner, not a logbook.
- **Divesoft Logbook** is closed and hardware-locked.

The single most defensible feature is **longitudinal cell health analysis**. Cells age unpredictably, current-limited cells fail in ways that aren't obvious until they kill someone, and the per-dive mV data needed to predict drift is already in every Petrel log. Nobody is doing this. If the app does nothing else well, doing this well makes it worth building.

## Tech stack

- **Flutter / Dart** for the app. Chosen primarily because `dart:ffi` gives the cleanest path to wrapping libdivecomputer later, and because custom rendering (the dive profile) is first-class in Flutter rather than an add-on. React Native and KMP were considered and rejected; see prior design discussion.
- **Pure-Dart Shearwater protocol implementation** for Phase 1. No FFI yet. Reimplementing libdivecomputer wholesale was considered and rejected — too much maintenance debt for too little gain. Long-term plan is pure Dart for Shearwater (the protocol we care about) and FFI to libdivecomputer for the long tail of other manufacturers if/when that becomes a priority.
- **`flutter_blue_plus`** for BLE. Mature enough; quirks are well-known and worked around in the community.
- **Drift (SQLite)** for local persistence. Type-safe Dart queries, rock-solid storage, decades of trust. Isar was considered and rejected — faster but its maintenance trajectory has been uncertain.
- **Sample data stored as packed columnar binary blobs**, not row-per-sample. One row per sample × 200 dives × thousands of samples is a performance cliff; pack the columns, gzip, decompress on render, LRU-cache recent profiles.
- **No cloud / sync in Phase 1.** Phase 2 will likely use **PowerSync** or **Supabase** on top of Postgres; sync semantics for divelog data are non-trivial and worth ceding to a dedicated sync engine rather than rolling our own.
- **Stdlib-flavored, dependency-light.** Resist adding packages for things Dart can do natively. Every dependency is a future maintenance liability.

## Architectural principles

These are the load-bearing decisions. Violating them creates more pain than they save.

1. **The dive computer is the source of truth, the user annotates on top.** Imported data is immutable. User data (notes, buddies, sites, equipment links, ratings) is layered. This makes re-import safe, makes parser bugs fixable later via re-parse, and avoids whole classes of "I edited a sample and now my deco replay is wrong" bugs.
2. **Store raw, parse on demand, cache aggressively.** Always keep the original Shearwater binary blob alongside the parsed dive. Tag it with the parser version that produced the cached parse. When the parser is updated, re-parse from raw without re-downloading from the DC.
3. **CCR-first, OC-second.** Default UI assumes closed circuit. OC is a degenerate case where setpoint, cells, and diluent collapse to "not applicable." This is the inverse of every generic logbook and it's what makes the app worth building.
4. **Metric in the database, convert at the UI layer.** Always. Don't store imperial — conversions accumulate floating-point error, and Shearwater logs metric internally regardless of the diver's display preference. UI can show whatever the user wants, with per-field overrides because tech divers mix units (depth in meters, pressure in psi is a real combination some people prefer).
5. **Single-segment dives in the data model, merge in the UI.** Shearwater logs each underwater segment as a separate dive. "Merge dives" is a display-only concern in Phase 1, possibly a stored relationship in Phase 2.
6. **Sync metadata everywhere from day one.** Add `created_at`, `updated_at`, `deleted_at`, `version`, `sync_status` to every user-editable entity even though sync isn't implemented in Phase 1. Bolting these on later is much harder than designing them in. Don't add them to immutable imported data — that doesn't sync, it gets re-derived from the raw blob.
7. **All user data syncs across signed-in devices.** Every device the user is signed in on must look at the same canonical state — dives, annotations, equipment, attachments (including the file bytes via R2), all of it. The only acceptable device-local state is (a) intentionally-not-synced raw inputs the parser can re-derive (raw BLE blobs), (b) transient transit state for in-flight operations (pending upload paths, last-imported-fingerprint per DC), and (c) caches that exist purely to avoid network round-trips (downloaded R2 bytes). Anything that affects what the user *sees* must sync. When adding a new entity, ask "if I edit this on the iPhone, will it appear on macOS without me thinking about it?" — if no, you're doing it wrong. New PowerSync-backed tables also need a corresponding line added to `infra/powersync-sync-rules.yaml` (and that file actually deployed to the PowerSync dashboard) before sync works end-to-end.
8. **Single commit point for dives.** Importing a dive is an atomic operation: the raw blob, the parsed dive, samples, events, and gases all commit together or not at all. Mid-import BLE disconnects must leave the database in a consistent state. This is the import-side analog of `flush()` in the existing libdc log extractor — keep it as one place in the code.

## Repository layout (target)

```
lib/
  shearwater/        # Pure-Dart Shearwater protocol parser + BLE transport
    parser/          # Binary format parsing, no I/O dependency
    ble/             # BLE transport, calls into parser
    fixtures/        # (test only) known-good .bin files from dctool
  data/
    db/              # Drift schema + DAOs
    models/          # Domain entities (Dive, SampleSet, Cell, etc.)
    sample_codec/    # Columnar sample blob encode/decode
  analysis/          # Derived computations: cell health, gas density, surfGF, etc.
  ui/
    screens/         # dive_list, dive_detail, import_flow, equipment, settings
    widgets/         # profile_chart, cell_health_chart, ...
    theme/
  main.dart
test/                # Unit tests; protocol parser is heavily tested against fixtures
integration_test/    # End-to-end tests with a mocked BLE backend
```

The Shearwater parser must be **a pure Dart library with no Flutter or BLE dependencies**, so it can be unit-tested in isolation with `.bin` fixtures and so it stays portable (CLI tools, server-side reparse, etc.). The BLE transport is a thin layer that feeds bytes into the parser.

## Phase 1 scope (what we are building first)

1. Connect to a Shearwater DC over BLE, authenticate, read the dive list, download dives.
2. Parse the binary into `Dive` + `SampleSet` + `Event` + `Gas` records.
3. Persist to local SQLite via Drift.
4. Display dive list (chronological, grouped by trip/month, color-coded by mode).
5. Display dive detail with multi-trace profile chart (depth, PPO2 voted, setpoint, optional traces for cells, GF99, tank pressure, scrubber, solenoid fires).
6. User-editable annotations: site, notes, buddies, conditions, rating, tags.
7. Equipment: dive computers, unit configurations, cells, scrubber sessions, cylinders.
8. Import flow as a guided multi-step UI with robust handling of BLE disconnects (per-dive atomic commits, resumable from where it stopped).
9. Settings: units, default GF, default algorithm, theme (default dark), data export to Subsurface XML / UDDF, debug-mode raw blob viewer.

## Explicitly NOT in Phase 1

Listed so scope stays honest:

- Cloud sync, accounts, multi-device — Phase 2.
- Tissue compartment replay, bailout-from-any-point — Phase 3.
- Cross-dive statistics dashboards — Phase 3 (the per-cell longitudinal view is Phase 1, but generalized stats are not).
- Photos / media on dives — Phase 2 at earliest; rabbit hole.
- Importing from non-Shearwater dive computers — Phase 4 if at all (probably via libdc FFI when we get there).
- Public dive sharing, social features — likely never.
- Web companion app — Phase 4 if at all.
- Decompression planning (forward-looking, not analysis) — different app, do not merge.

## Build order (recommended)

This order isolates the risk and keeps something demonstrable at every step.

1. **Bench-dump real binaries.** Pair a Petrel (ideally Petrel 3) and pull raw downloads with `dctool`. Verify byte-by-byte what's in the protocol. Specifically: scrubber time per-sample vs. sparse, cell mV resolution, solenoid fire encoding, voted-out semantics. An afternoon here saves weeks of design rework.
2. **Pure-Dart binary parser, fed from `.bin` fixtures.** No BLE yet. Unit tests against known-good `dctool` output. By the time this works the protocol is well understood.
3. **BLE transport, single dive happy path.** Connect, auth, read dive list, pull one dive, parse. No incremental sync, no resumability.
4. **Data model + Drift schema.** Informed by what the parser actually emits, not by a priori design.
5. **Persistence + dedup.** Stable dive identity hash, atomic import, raw blob retention.
6. **UI in order:** dive list → dive detail (with profile) → import flow → equipment → settings. Profile chart is the hardest UI piece; don't rush it.
7. **Multi-dive import, resumability, error recovery.** Once the happy path is solid.
8. **Private alpha with 3–5 CCR divers.** Real dive computers, real diving. Their feedback shapes the polish phase.

## Working in this project

- **Pure-Dart Shearwater parser is sacred.** No Flutter imports, no BLE imports, no I/O. It takes bytes, returns parsed structures. This is the most important architectural boundary in the project.
- **Tests against real binaries from real dive computers.** The Shearwater protocol drifts between firmware versions. Build a fixture library of `.bin` files spanning Petrel 1 / 2 / 3, Perdix variants, and Peregrine variants, ideally across multiple firmware versions per model. Parser changes must keep all fixtures passing.
- **Don't reinvent libdivecomputer.** When in doubt about protocol semantics, the libdc Shearwater backend (`shearwater_petrel.c`, `shearwater_predator.c`, `shearwater_common.c`) is the reference. Cross-check.
- **Keep the data model immutable for imported data.** If something needs to change, it's either user annotation (separate fields) or it's a parser bug (re-parse from raw).
- **Preserve raw blobs forever.** Storage is cheap; rebuilding parsed data when a parser bug is fixed is invaluable.
- **Sample storage is columnar packed binary, not row-per-sample.** This is non-negotiable for performance. If you find yourself wanting one row per sample, re-read this section.
- **`dive_id` is `hash(serial, dc_dive_number, start_timestamp_utc)`.** Don't trust just the timestamp; Petrels have had clock issues. Don't trust just the dive number; serial is the disambiguator across multiple computers.
- **CCR mode is the default UI assumption.** OC dives hide the CCR-specific fields; they don't restructure the layout.
- **Dark theme is the default.** Tech divers dive in dark places and surface in dark cars.
- **Use agents whenever possible.** This is a solo-dev project and the codebase is now large enough that doing every line of every feature in the foreground is wasteful. For any task that's a self-contained build (a new DAO + tests, a new widget + tests, a new parser, a new screen wired into existing seams), dispatch a build agent in the background. Foreground work belongs to: integration steps that touch seams the agent can't see, decisions that need user input, and anything where the agent's output needs to be vetted against running code before moving on. Parallelize agents whenever the file sets don't overlap. Keep the prompts concrete: name the files to read, the files to write, the conventions to mirror, and the verify-before-returning steps (`flutter analyze` clean, `flutter test` passing).

### Known third-party defects + local workarounds

- **`git2dart_binaries` 1.10.3 has three macOS packaging defects.** Each fails differently — the first two SIGABRT at launch (`dyld: Library not loaded: @rpath/...`), the third throws at first sync attempt (`Bad state: Unable to resolve git2dart_binaries package location.`). **Workaround applied locally** — the package files in `~/.pub-cache/hosted/pub.dev/git2dart_binaries-1.10.3/` have been edited:
   1. **Misnamed dylib.** `libgit2.dylib` has install_name `@rpath/libgit2-experimental.1.9.dylib`. File renamed locally to match.
   2. **Missing vendored dependency.** `libssh2.1.dylib` (a libgit2 dependency) ships in the package but wasn't declared in the podspec's `vendored_libraries`, so it never embedded into the `.app`. Added to the podspec.
   3. **Mismatched DynamicLibrary.open arg.** `lib/src/util.dart` opens `'libgit2.dylib'`, which doesn't match the renamed file (or the install_name). Patched to open `'libgit2-experimental.1.9.dylib'` on macOS. The fallback path uses `Isolate.resolvePackageUriSync`, which doesn't work in compiled Flutter apps (no `package_config.json` at runtime), so the open call must succeed first try.
   **This fix lives only in pub-cache** — it survives `flutter clean` / `flutter pub get` / `pod install`, but NOT `dart pub cache clean` or a fresh machine. If macOS sync starts breaking after a cache wipe, redo all three:
   ```bash
   cd ~/.pub-cache/hosted/pub.dev/git2dart_binaries-1.10.3/macos
   mv libgit2.dylib libgit2-experimental.1.9.dylib
   # Edit git2dart_binaries.podspec — replace s.vendored_libraries with:
   #   s.vendored_libraries = ['libgit2-experimental.1.9.dylib', 'libssh2.1.dylib']
   # Edit ../lib/src/util.dart line ~19 — replace the macOS branch with:
   #   return (name: 'libgit2-experimental.1.9.dylib', subDir: 'macos');
   cd <repo>/macos && rm -rf Pods Podfile.lock && pod install
   ```
   Upstream issue: https://github.com/DartGit-dev/git2dart_binaries/issues/14. When upstream ships a fixed version, pin it in pubspec and delete this section.

## Sync recovery procedures

These are the recovery paths for issues we've actually hit on the live deployment. Follow them in order — most are fast and safe, the last is destructive.

### PowerSync replication slot stalls Postgres

Symptom: app sync indicator goes red. Supabase dashboard shows Database/PostgREST/Storage all "Unhealthy". PowerSync's dashboard issues panel reports `connect ECONNREFUSED ...:5432`, `No replicated commit in more than NNNNNs`, `postgres query failed`. Restarting the project from the dashboard brings it back up still unhealthy.

What's happening: PowerSync's connection died at some point; its logical-replication slot keeps WAL pinned in Postgres; on the NANO compute tier the WAL partition fills up; Postgres stops accepting connections. A restart can't recover because the slot still pins WAL on startup.

Recovery (try in order):

1. **Drop the slot via SQL Editor / Management API SQL endpoint** while Postgres is still partially responsive:
   ```sql
   SELECT pg_terminate_backend(active_pid)
   FROM pg_replication_slots WHERE active_pid IS NOT NULL;
   SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots;
   ```
2. If SQL paths all return `ECONNREFUSED`, the project is fully wedged. Best lever left: **`POST /v1/projects/{ref}/pause` then `POST /v1/projects/{ref}/restore` via the Management API** (the dashboard's pause button silently no-ops once Postgres is dead, but the API call sometimes still goes through).
3. If pause/restore also fails, **recreate the project from scratch** (`POST /v1/projects` with same org_slug + region). Apply migrations from `supabase/migrations/` (the bundle script in `/tmp/ccrl_fresh_setup.sql` is the consolidated form). Patch the new project ref + anon key into `lib/sync/cloud/cloud_config.dart` and `worker/wrangler.toml`. Repoint PowerSync's source-DB connection in PowerSync's dashboard. Redeploy worker (`cd worker && npx wrangler deploy`). User does a fresh import on the device.

Long-term mitigation: move `dive_samples` out of replication (it's the heaviest sync table by an order of magnitude — its WAL volume is what makes the NANO tier vulnerable), or upgrade tier so the WAL partition is bigger.

### "Reset Everything" doesn't fully clear local state

`Settings → Reset everything` calls `psDb.disconnectAndClear()` which is supposed to wipe the local PowerSync SQLite. **In practice it leaves rows behind** — confirmed 2026-05-10. Subsequent bootstrap-imports then dedup-skip those stale rows by `(dcSerial, startTime)` and never re-parse, so old broken data persists.

If a re-import doesn't fix the data, the cleanest workaround is to **delete the local PowerSync SQLite file directly**:
```bash
rm /Users/<you>/Library/Containers/com.example.ccrlogger/Data/Documents/powersync.db*
```
then restart the app and re-import. The wildcard catches `.db`, `.db-wal`, and `.db-shm`.

Long-term fix: rework `Settings → Reset everything` to also `rm` the SQLite file as a fallback, or file an upstream PowerSync bug.

### Bootstrap clone goes stale relative to user's main repo

CCRLog keeps an internal git clone of the Subsurface repo at `~/Library/Containers/com.example.ccrlogger/Data/Documents/subsurface_clone/<email>-bootstrap/`. Bootstrap-import reads from **this clone**, not from any external git checkout the user might also have.

If the user's Subsurface app re-uploaded older dives with newer DC recordings (e.g. switching primary DC), the cloud branch updates — but **CCRLog's clone is never refreshed across bootstrap runs**. Result: bootstrap re-parses stale data, producing wrong PPO2/setpoint traces because the older Subsurface format uses sparse `dc_supplied_ppo2=` and frequent rounded `po2=` tokens, whereas the modern Petrel-3 format inverts that ratio.

Recovery: delete the clone alongside the local DB:
```bash
rm -rf ~/Library/Containers/com.example.ccrlogger/Data/Documents/subsurface_clone
rm /Users/<you>/Library/Containers/com.example.ccrlogger/Data/Documents/powersync.db*
```
then restart and re-import — bootstrap will re-clone fresh.

Long-term fix: bootstrap should `git fetch && git reset --hard origin/<branch>` before reading, or compare commit hashes and re-clone on mismatch.

### Sign in BEFORE bootstrap-import, not after

Sample data flowing through `dao.importDive()` stamps `owner_id` from the current Supabase session at write time. If the user is **not signed in** when bootstrap runs, every `dives` and `dive_samples` row gets `owner_id = NULL`. Sync indicator goes green because there's no auth needed locally — but the moment the user signs in, PowerSync's CRUD upload fails every row with `new row violates row-level security policy for table "dives"`.

The existing `OwnerIdBackfiller` (run on first sign-in) **omits `dives` and `dive_samples`** — it only stamps the seven smaller equipment/annotation tables. So a sign-in after a not-signed-in import doesn't fix it; the only recovery today is to wipe local state and re-import while signed in.

Long-term fix: extend `OwnerIdBackfiller` with SQL `UPDATE` paths that stamp `owner_id = $userId WHERE owner_id IS NULL` against the existing PowerSync local rows for `dives` and `dive_samples`. The current backfiller does Drift→PowerSync copies; this needs to be an in-place PowerSync update instead.

### Subsurface-Cloud branch corruption from CCRLog write-direction sync

Historical incident (2026-05-08): an early version of the CCRLog → Subsurface git write-direction sync emitted samples in the older Subsurface format (sparse `dc_supplied_ppo2=`, frequent `po2=`) and force-pushed a commit titled "CCRLog sync — N dives" to Subsurface Cloud, **overwriting the user's authoritative recordings** for those dives. The user's main repo at `~/Dev/CCRLog/ss_git/...` retained the correct working-tree content because it hadn't fetched yet, but the cloud branch held the corrupt commit.

A safety hold is currently in place in `sync_orchestrator.dart` that throws unconditionally to prevent the write-direction code from running until the planner is rewritten. **Do not remove that hold without first**:

1. Making the serializer emit `dc_supplied_ppo2=` per-sample (current code only emits `po2=` based step values, which is what produced the broken output).
2. Adding conflict resolution: when CCRLog's planned write would change a Divecomputer file in a way that loses data Subsurface previously recorded, **abort that per-dive write** rather than overwrite.

If a user reports their Subsurface Cloud is corrupted again: have them force-push their main repo's HEAD over the cloud branch (`git push --force origin HEAD:<branch>`), reset Subsurface app's local cache (so it doesn't re-push the bad commit), then in CCRLog `rm -rf subsurface_clone` and re-bootstrap.

## Stack-rank of features by user value

When prioritizing within Phase 1 polish, this is roughly the order:

1. Reliable, fast import from a Petrel (the table stake — if this is flaky, nothing else matters)
2. Clean profile rendering with PPO2 + setpoint as first-class traces
3. Per-cell mV inspection on a single dive
4. Longitudinal per-cell mV trend across all dives on that cell
5. Scrubber session tracking with minutes-used warnings
6. Surface GF / CNS / OTU prominence in the dive summary
7. Solenoid fire visualization
8. Gas density / END overlays
9. Bailout gas time tracking (which gases were breathed vs. carried)
10. Trip / location organization

Items 3 and 4 are the differentiator. Item 1 is the prerequisite for everything.

## Out of scope (forever, probably)

- Forward-looking dive planning. Different app, different mental model. Resist scope creep here.
- Anything not Shearwater for the foreseeable future. The "expand to libdc" Phase 4 is conditional, not promised.
- Social / sharing features beyond per-dive export. The audience self-selects toward people who don't want their dives on a feed.
- Insurance / certification card storage, training records, etc. Adjacent but not core.

## Notes on the related extract_libdc_log project

There is a separate small project (`extract_libdc_log.py`) that extracts raw `.read.bin` and `.write.bin` byte streams from libdivecomputer logfiles produced by Subsurface or `dctool -vv`. That project is the practical workaround for the macOS limitation that `dctool` lacks a built-in CoreBluetooth BLE backend, so on macOS the workflow for capturing reference protocol traces is: have Subsurface do the BLE download with verbose logging enabled, save the libdc logfile, then run `extract_libdc_log.py` to recover the raw bytes that flowed over the wire.

The `.read.bin` files produced by that tool are exactly the kind of fixtures this project's parser should be tested against. Treat the two projects as complementary: that one captures protocol traces from real dive computers on macOS, this one consumes them in tests.
