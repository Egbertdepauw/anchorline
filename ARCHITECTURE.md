# Anchorline: architecture and working rules

This file is the single source of truth for how Anchorline is built and how to work on it, for people and AI coding agents alike. `CLAUDE.md` (Claude Code) and `AGENTS.md` (Codex, Cursor, Gemini CLI, Copilot and other agents) only point here. Change the rules here, never there.

## What this project is

**Anchorline** is a mobile-first dive logging and analysis app for **technical and CCR divers**, with a deliberate focus on **Shearwater dive computers** (Petrel 1/2/3, Perdix / Perdix AI / Perdix 2, Peregrine / Peregrine TX, NERD 2). The audience is people diving JJ-CCR, SF2, X-CCR, Choptima, Liberty, and similar units that use a Petrel as the controller, plus OC tech divers using Perdix or Peregrine. It runs on iOS, Android, macOS, Windows and Linux. The repository is `Egbertdepauw/anchorline`; the package and app ids still say `ccrlogger` and stay that way.

This is **not** a Subsurface clone. Subsurface is a generalist divelog that has to serve freedivers, recreational, tech, and CCR from the same UI; this app makes the opposite trade and assumes CCR is the default case, OC is degenerate. The differentiator is post-dive analysis that doesn't exist anywhere else mobile-friendly today: per-cell mV trends across the lifetime of the cell, scrubber session tracking, solenoid fire analysis, surfGF/CNS/OTU as first-class numbers, and gas density / END overlays on the profile.

The project is **open source**: GPL-2.0-only, with an extra permission for app store distribution. Third-party code keeps its own licence (the Shearwater parser translated from libdivecomputer is LGPL-2.1-or-later), and the name and logo are not licensed to others. See `LICENSING.md`, `NOTICE.md` and `CONTRIBUTING.md`.

Development is **solo for now**, possibly with collaborators later. There is **no timeline pressure** — this is a build-it-right-the-first-time project, not a ship-fast project. Optimize for code that someone else (or future-self) can pick up and understand, not for shipping speed.

## Why this project exists

The data needed for serious post-dive analysis has been logged in Shearwater dive logs for years, and nobody surfaces it well:

- **Shearwater Cloud** is fundamentally a backup utility for Shearwater customers, not an analysis tool.
- **Subsurface** is a generalist log; CCR is supported but not central to the design. Mobile-side it's a Qt port and feels like one.
- **MultiDeco** is a planner, not a logbook.
- **Divesoft Logbook** is closed and hardware-locked.

The single most defensible feature is **longitudinal cell health analysis**. Cells age unpredictably, current-limited cells fail in ways that aren't obvious until they kill someone, and the per-dive mV data needed to predict drift is already in every Petrel log. Nobody is doing this. If the app does nothing else well, doing this well makes it worth building.

## Tech stack

- **Flutter / Dart** for the app. Chosen primarily because `dart:ffi` gives the cleanest path to libdivecomputer, and because custom rendering (the dive profile) is first-class in Flutter rather than an add-on. React Native and KMP were considered and rejected.
- **Pure-Dart Shearwater protocol implementation.** Shearwater stays pure Dart. Reimplementing libdivecomputer wholesale was considered and rejected — too much maintenance debt for too little gain. Other brands go through **libdivecomputer, linked through FFI**, pinned to an upstream commit and built by a Dart build hook in `packages/libdivecomputer/`. A brand is ported to Dart only when the analysis needs control the library can't give and we can test it on real hardware (see `docs/superpowers/specs/2026-11-15-libdivecomputer-brands-design.md`).
- **Pure-Dart FIT reader** (`packages/fit_reader/`) for Garmin and Suunto dive files.
- **`flutter_blue_plus`** for BLE. Mature enough; quirks are well-known and worked around in the community.
- **Drift (SQLite)** for device-local tables (raw blobs, import state). Type-safe Dart queries, rock-solid storage, decades of trust. Isar was considered and rejected — faster but its maintenance trajectory has been uncertain.
- **PowerSync on Supabase (Postgres + Auth)** for everything that syncs. Sync semantics for divelog data are non-trivial and worth ceding to a dedicated sync engine rather than rolling our own. Synced data lives in PowerSync's own SQLite database, not in Drift: read dives and samples through PowerSync (`_ps` in the DAOs). The Drift `dives` and `dive_samples` tables are legacy and don't hold current dives.
- **Attachments in Cloudflare R2**, through the Worker in `worker/` (presigned URLs and upload limits only).
- **Subsurface Cloud sync over git** with `git2dart` (libgit2).
- **New backend work goes into one Dart service**, not into the Worker and not in a second language: most backend jobs need the parser, the sample codec or the Subsurface format, which exist only in Dart. `packages/subsurface_core` is already shared with it.
- **Sentry** for crash reports, redacted (see "Privacy, secrets and diagnostics").
- **Sample data stored as packed columnar binary blobs**, not row-per-sample. One row per sample × 200 dives × thousands of samples is a performance cliff; pack the columns, gzip, decompress on render, LRU-cache recent profiles.
- **Stdlib-flavored, dependency-light.** Resist adding packages for things Dart can do natively. Every dependency is a future maintenance liability.

## Architectural principles

These are the load-bearing decisions. Violating them creates more pain than they save. Keep the numbers stable: code comments, migrations and `lint_migrations.sh` cite them.

1. **The dive computer is the source of truth, the user annotates on top.** Imported data is immutable. User data (notes, buddies, sites, equipment links, ratings) is layered. This makes re-import safe, makes parser bugs fixable later via re-parse, and avoids whole classes of "I edited a sample and now my deco replay is wrong" bugs.
2. **Store raw, parse on demand, cache aggressively.** Always keep the original binary blob alongside the parsed dive. Tag it with the parser version that produced the cached parse. When the parser is updated, re-parse from raw without re-downloading from the DC.
3. **CCR-first, OC-second.** Default UI assumes closed circuit. OC is a degenerate case where setpoint, cells, and diluent collapse to "not applicable." This is the inverse of every generic logbook and it's what makes the app worth building.
4. **Metric in the database, convert at the UI layer.** Always. Don't store imperial — conversions accumulate floating-point error, and Shearwater logs metric internally regardless of the diver's display preference. UI can show whatever the user wants, with per-field overrides because tech divers mix units (depth in meters, pressure in psi is a real combination some people prefer).
5. **Single-segment dives in the data model; a merge is a stored link.** Shearwater logs each underwater segment as a separate dive, and imported dives stay that way. Merging is user data in `dive_merge_links`. A merged dive in the UI has a synthetic group id with no `dives` row, so per-dive child writes (notes, attachments, equipment links) must use `annotationsDiveId`, the earliest real member; otherwise PowerSync drops the orphaned row.
6. **Sync metadata everywhere.** Every user-editable table carries `created_at`, `updated_at`, `deleted_at`, `version` and `sync_status` (see `supabase/migrations/0025_open_blends.sql`). Imported dives sync too and carry `deleted_at`, `version` and `sync_status`, but their content is never edited (principle 1). Raw blobs stay device-local and carry none.
7. **All user data syncs across signed-in devices.** Every device the user is signed in on must look at the same canonical state — dives, annotations, equipment, attachments (including the file bytes via R2), all of it. The only acceptable device-local state is (a) intentionally-not-synced raw inputs the parser can re-derive (raw BLE blobs), (b) transient transit state for in-flight operations (pending upload paths, last-imported-fingerprint per DC), and (c) caches that exist purely to avoid network round-trips (downloaded R2 bytes). Anything that affects what the user *sees* must sync. When adding a new entity, ask "if I edit this on the iPhone, will it appear on macOS without me thinking about it?" — if no, you're doing it wrong. New PowerSync-backed tables also need a corresponding line added to `infra/powersync-sync-streams.yaml` (and that file actually deployed to the PowerSync dashboard) before sync works end-to-end. They also need an explicit `grant ... to authenticated, service_role` in the migration that creates them. Supabase no longer auto-grants new tables, so without it every upload to that table fails with `permission denied` (see `supabase/README.md`; `lint_migrations.sh` enforces it). They also need `primary key (owner_id, id)`, not `id` alone: ids are computed from hardware and dive data, so two accounts can share one (0027; `lint_migrations.sh` enforces it).
8. **Single commit point for dives.** Importing a dive is an atomic operation: the raw blob, the parsed dive, samples, events, and gases all commit together or not at all. Mid-import BLE disconnects must leave the database in a consistent state. This is the import-side analog of `flush()` in the existing libdc log extractor — keep it as one place in the code.

## Working in this project

### Package boundaries

- **Pure-Dart Shearwater parser is sacred.** No Flutter imports, no BLE imports, no I/O. It takes bytes, returns parsed structures. This is the most important architectural boundary in the project.
- **`packages/subsurface_core` is pure Dart and shared with the server.** The Subsurface git format (parser, serializer), both mappers, the sync planner, the snapshot builder, the domain models (`Dive`, `SampleSet`, `DiveAnnotation`), the sample codec and the parser's data types (`constants`, `hardware`, `parsed_dive`, `dive_converter`) live there, laid out exactly as they were under the app's `lib/`. No Flutter, Drift, PowerSync or I/O imports; `packages/subsurface_core/test/purity_test.dart` enforces it. Mapper and planner take `SubsurfaceDiveInput` / `SubsurfaceCylinderInput` / `SubsurfaceDiveComputerInput`; the app builds those from Drift rows in `lib/sync/subsurface_git/drift_sync_inputs.dart`. Run its tests with `dart test` from that directory; CI does.
- **`packages/fit_reader` is pure Dart like `subsurface_core`.** It reads FIT dive files from Garmin and Suunto devices into parsed structures; FIT dives use `dc_family = -1`. The only real fixtures are two Descent Mk1 dives and a Suunto Ocean dive, and no model counts as tested yet (`kCheckedFitModels` in `lib/devices/fit/fit_tiers.dart` is empty); every model shows 'Not yet tested by us' until it has a checked fixture. Garmin dives come in as FIT files only for now (not through libdivecomputer). Reading the watch directly over USB (MTP) is a later step and a Garmin Connect account link a possible one; see the 2026-11-17 Garmin FIT design, section 11. No Flutter, Drift or I/O imports. No Garmin FIT SDK code, port of it, or `Profile.xlsx` table may enter it: Garmin's FIT SDK licence forbids copyleft use. Facts come from Subsurface's Garmin parser and from real files. Its fixtures in `test/fixtures/` (two Garmin Descent Mk1 dives and a Suunto Ocean dive) come from Subsurface's test data (github.com/subsurface/subsurface at 1cf5569, `dives/`, GPL-2.0), anonymised with `tool/anonymise_fit.dart`; see `NOTICE.md`. Run its tests with `dart test` from that directory.
- **`packages/libdivecomputer/` is pure Dart plus its native build.** No Flutter imports. The pin moves only through `tool/update_upstream.sh`, the vendored tree always equals "pinned commit + `patches/`", and every patch goes upstream. Imported data changes only through the refresh (spec section 7a), never by editing in place.

### Dive data and import

- **Tests against real binaries from real dive computers.** The Shearwater protocol drifts between firmware versions. Build a fixture library of `.bin` files spanning Petrel 1 / 2 / 3, Perdix variants, and Peregrine variants, ideally across multiple firmware versions per model. Parser changes must keep all fixtures passing. Fix a bug by writing the failing test first.
- **Don't reinvent libdivecomputer.** When in doubt about protocol semantics, the libdc Shearwater backend (`shearwater_petrel.c`, `shearwater_predator.c`, `shearwater_common.c`) is the reference. Cross-check.
- **Keep the data model immutable for imported data.** If something needs to change, it's either user annotation (separate fields) or it's a parser bug (re-parse from raw).
- **Preserve raw blobs forever.** Storage is cheap; rebuilding parsed data when a parser bug is fixed is invaluable.
- **Sample storage is columnar packed binary, not row-per-sample.** This is non-negotiable for performance. If you find yourself wanting one row per sample, re-read this section.
- **`dive_id` is `hash(serial, dc_dive_number, start_timestamp_utc)`.** Don't trust just the timestamp; Petrels have had clock issues. Don't trust just the dive number; serial is the disambiguator across multiple computers. For libdivecomputer dives it is `sha256('libdc:<vendor>:<serial>:<fingerprint hex>')` truncated to 32 hex characters (serial decimal, hex lower case), frozen at first import. For FIT dives it is `sha256('fit:<manufacturer>:<serial>:<time created>')` truncated to 32 hex characters, from the file id: all three are decimal integers taken raw from the file, and `<time created>` is the raw FIT value. `:<n>` is appended when the session is at position n ≥ 1 among all session messages in the file. A file without time created uses `start<raw session start>` in its place.
- **There are two `Dive` classes.** The UI and the DAOs use the Drift-generated `Dive` (`lib/data/db/database.g.dart`: flat int columns, times in epoch seconds). The domain `Dive` in `packages/subsurface_core` is for import and the Subsurface format only.

### Sync and the backend

- **Subsurface write sync is live; keep its two safeguards.** In 2026-05 an early version force-pushed samples in the wrong format and overwrote a user's recordings on Subsurface Cloud. Writing back is safe only because the serializer emits per-sample `dc_supplied_ppo2=` and the planner declines any dive with a foreign edit (`foreignEditConflict` in `sync_planner.dart`). Never weaken either, and the app never force-pushes to Subsurface Cloud. Users must sign in before bootstrap-import.
- **Migrations** go in `supabase/migrations/` with the next number and must pass `supabase/lint_migrations.sh`. Never rewrite one that has been deployed; add a new one. The maintainer deploys them by pasting into the Supabase SQL editor, so agents hand over the SQL and the steps and don't run `apply_migrations.sh`.
- **To check whether a migration that adds a column is live**, without the database password: ask the REST API for that column with the public anon key from `lib/sync/cloud/cloud_config.dart`, as in `GET <supabaseUrl>/rest/v1/<table>?select=<column>&limit=0`. `42501` (permission denied) means the column exists; `42703` (column does not exist) means the migration isn't deployed. Ask for a made-up column alongside it to see the difference.
- **When Supabase or PowerSync misbehaves, look at the dashboards first** (logs, replication slots) before theorizing from code. The recurring cause is a dead replication slot pinning the WAL; see the sync-recovery skill.

### UI and the user manual

- **CCR mode is the default UI assumption.** OC dives hide the CCR-specific fields; they don't restructure the layout.
- **Dark theme is the default.** Tech divers dive in dark places and surface in dark cars.
- **The user manual lives in `docs/user/`** and is published to anchorline.eu/manual by `dart tool/publish/publish.dart content`. A PR that changes what a screen shows updates that screen's page and screenshot there.

### Privacy, secrets and diagnostics

- **Sentry gets no error text.** `sentryBeforeSend` reduces every event to its type, SQLite code and stack. Report errors with `captureRedactedException` (`lib/diagnostics/sentry_redaction.dart`), and keep print breadcrumbs off.
- **Never print a secret.** Check whether a variable is set with `${VAR:+set}`; `${VAR:-unset}` prints the value when it is set. A secret that reaches a log, transcript or commit must be rotated. Secrets live in gitignored local files (such as `key.properties` and `sentry.env.local`), never in the repo.

### Code style and language

- **English for everything that ends up in git:** code, comments, docs, commit messages, branch names, PR and review text.
- **Don't run `dart format` on existing files.** Most of the tree isn't format-clean (249 of 342 files in `lib/` would change), so a format run buries the real change. Match the surrounding style by hand. CI runs analyze and test, not format.
- **Comments say why, not what.** Write one only when the reason isn't obvious from the code.

### Git and pull requests

The full workflow is in `CONTRIBUTING.md`. The parts that bite:

- Issue first, then a branch named `<type>/<issue>-<summary>`, Conventional Commits, a PR with `Closes #N`, squash merge, delete the branch. One concern per PR.
- `main` is protected: it needs a PR and a green **analyze + test** check, admins included, and nobody force-pushes.
- **Sign off every commit** with `git commit -s` (Developer Certificate of Origin).
- **Never discard work you didn't create.** The maintainer's checkout often holds long-lived uncommitted files. Run `git status` first, stash or commit instead of `git reset --hard`, `git checkout .` or `git clean`, and update `main` with `git pull --ff-only`.

### Builds and releases

- **Releases** follow `docs/RELEASING.md` (a two-week train once the stores launch). Per-platform steps are in `docs/*_DISTRIBUTION.md`, `docs/TESTFLIGHT_QUICKSTART.md` and `docs/APP_STORE_SUBMISSION.md`.
- **Write every `--dart-define` out.** zsh doesn't word-split a variable that holds several flags, so `$D` arrives as one define. Release builds need the defines listed in `docs/RELEASING.md`; check a build with `strings` on `libapp.so`.
- **Never `flutter install` onto an iPhone that holds real data.** It uninstalls first, which wipes the local database, the raw blobs and the import fingerprints. Install over the app with `xcrun devicectl device install app`.
- **Android release builds from a git worktree are debug-signed** unless `key.properties` and the upload keystore are linked in from the main checkout. Check the signature with `keytool` before shipping.

## Working with AI agents

- **These rules apply to every agent.** Claude Code loads this file through the `@ARCHITECTURE.md` import in `CLAUDE.md`; Codex, Cursor, Gemini CLI and other `AGENTS.md`-aware tools reach it through `AGENTS.md`. The skills in `.claude/skills/` are plain Markdown, so agents that don't load skills can read them as docs.
- **Use agents whenever possible.** This is a solo-dev project and the codebase is now large enough that doing every line of every feature in the foreground is wasteful. For any task that's a self-contained build (a new DAO + tests, a new widget + tests, a new parser, a new screen wired into existing seams), dispatch a build agent in the background. Foreground work belongs to: integration steps that touch seams the agent can't see, decisions that need user input, and anything where the agent's output needs to be vetted against running code before moving on. Parallelize agents whenever the file sets don't overlap. Keep the prompts concrete: name the files to read, the files to write, the conventions to mirror, and the verify-before-returning steps (`flutter analyze` clean, `flutter test` passing). In Claude Code, always pass `model` explicitly: `"sonnet"` for routine build agents, `"opus"` only for design, debugging and review work.
- **Specs before features.** Design specs and implementation plans live in `docs/superpowers/specs/` and `docs/superpowers/plans/`, named by date. A feature of any size starts with a spec the maintainer approves.
- **Verify before claiming done:** `flutter analyze` clean, `flutter test` passing, and `dart test` in every package you touched. For a UI change, run the app and use the feature; if you couldn't, say so.
- **Ask first for anything others can see or that is hard to undo:** pushing, opening or commenting on PRs and issues, deploying migrations or sync rules, publishing to anchorline.eu, sending mail.
- **Lessons go here, not into private memory.** When an agent learns something that applies to everyone working on the repo (a trap, a convention, a decision), it proposes a line for this file, or for a doc or skill linked from it. An agent's own memory is per-machine and invisible to other agents and contributors.

### Keeping this file useful

- It loads into every agent session, so keep it to rules and decisions. Long procedures go in `docs/` or a skill and get a line under "Where the rest lives".
- `CLAUDE.md` and `AGENTS.md` stay pointers to this file.

## Where the rest lives

- **Build/toolchain failures** (git2dart, Xcode 26 SDK shadowing, Gradle/AGP/KGP/JBR, the libdivecomputer build hook): `.claude/skills/toolchain-gotchas`. Hard rules from it: never resurrect the vendored libcrypto dylib or its build phase; don't add `id("kotlin-android")` back to `:app`; stay on AGP 8.x until #82; never fix a JBR jump with `flutter config --jdk-dir`.
- **Live sync incidents** (PowerSync slot, Reset Everything, stale bootstrap clone, owner_id NULL, Subsurface Cloud corruption): `.claude/skills/sync-recovery`.
- **Phase 1 scope, build order, feature stack-rank, extract_libdc_log fixture workflow**: `docs/PROJECT_PLAN.md`.
- **Contribution workflow**: `CONTRIBUTING.md`. **Licences**: `LICENSING.md`, `NOTICE.md`.
- **Releases and store builds**: `docs/RELEASING.md` and the platform guides in `docs/`.
- **Database and sync setup**: `supabase/README.md`, `infra/powersync-sync-streams.yaml`.

## Out of scope (forever, probably)

- Forward-looking dive planning. Different app, different mental model. Resist scope creep here.
- Infrared (IrDA) computers — 19 old Uwatec and Subgear models. Classic Bluetooth on iOS is also out: Apple requires MFi, so classic-only models (Ratio iX3M GPS, HW Frog, Tecdiving) never work on iPhones. See the 2026-11-15 libdivecomputer design.
- Social / sharing features beyond per-dive export. The audience self-selects toward people who don't want their dives on a feed.
- Insurance / certification card storage, training records, etc. Adjacent but not core.
