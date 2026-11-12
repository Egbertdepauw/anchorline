# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
7. **All user data syncs across signed-in devices.** Every device the user is signed in on must look at the same canonical state — dives, annotations, equipment, attachments (including the file bytes via R2), all of it. The only acceptable device-local state is (a) intentionally-not-synced raw inputs the parser can re-derive (raw BLE blobs), (b) transient transit state for in-flight operations (pending upload paths, last-imported-fingerprint per DC), and (c) caches that exist purely to avoid network round-trips (downloaded R2 bytes). Anything that affects what the user *sees* must sync. When adding a new entity, ask "if I edit this on the iPhone, will it appear on macOS without me thinking about it?" — if no, you're doing it wrong. New PowerSync-backed tables also need a corresponding line added to `infra/powersync-sync-rules.yaml` (and that file actually deployed to the PowerSync dashboard) before sync works end-to-end. They also need an explicit `grant ... to authenticated, service_role` in the migration that creates them. Supabase no longer auto-grants new tables, so without it every upload to that table fails with `permission denied` (see `supabase/README.md`; `lint_migrations.sh` enforces it).
8. **Single commit point for dives.** Importing a dive is an atomic operation: the raw blob, the parsed dive, samples, events, and gases all commit together or not at all. Mid-import BLE disconnects must leave the database in a consistent state. This is the import-side analog of `flush()` in the existing libdc log extractor — keep it as one place in the code.

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
- **Use agents whenever possible.** This is a solo-dev project and the codebase is now large enough that doing every line of every feature in the foreground is wasteful. For any task that's a self-contained build (a new DAO + tests, a new widget + tests, a new parser, a new screen wired into existing seams), dispatch a build agent in the background. Foreground work belongs to: integration steps that touch seams the agent can't see, decisions that need user input, and anything where the agent's output needs to be vetted against running code before moving on. Parallelize agents whenever the file sets don't overlap. Keep the prompts concrete: name the files to read, the files to write, the conventions to mirror, and the verify-before-returning steps (`flutter analyze` clean, `flutter test` passing). Always pass `model` explicitly: `"sonnet"` for routine build agents, `"opus"` only for design, debugging and review work.

### Where the rest lives

- **Build/toolchain failures** (git2dart, Xcode 26 SDK shadowing, Gradle/AGP/KGP/JBR): `.claude/skills/toolchain-gotchas`. Hard rules from it: never resurrect the vendored libcrypto dylib or its build phase; don't add `id("kotlin-android")` back to `:app`; stay on AGP 8.x until #82; never fix a JBR jump with `flutter config --jdk-dir`.
- **Live sync incidents** (PowerSync slot, Reset Everything, stale bootstrap clone, owner_id NULL, Subsurface Cloud corruption): `.claude/skills/sync-recovery`. Hard rule: **never remove the write-direction safety hold in `sync_orchestrator.dart`** until the serializer emits per-sample `dc_supplied_ppo2=` and per-dive conflict aborts exist. Users must sign in before bootstrap-import.
- **Phase 1 scope, build order, feature stack-rank, extract_libdc_log fixture workflow**: `docs/PROJECT_PLAN.md`.

## Out of scope (forever, probably)

- Forward-looking dive planning. Different app, different mental model. Resist scope creep here.
- Anything not Shearwater for the foreseeable future. The "expand to libdc" Phase 4 is conditional, not promised.
- Social / sharing features beyond per-dive export. The audience self-selects toward people who don't want their dives on a feed.
- Insurance / certification card storage, training records, etc. Adjacent but not core.
