# Project plan (Phase 1)

Moved out of CLAUDE.md so it does not load into every session.

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


## Notes on the related extract_libdc_log project

There is a separate small project (`extract_libdc_log.py`) that extracts raw `.read.bin` and `.write.bin` byte streams from libdivecomputer logfiles produced by Subsurface or `dctool -vv`. That project is the practical workaround for the macOS limitation that `dctool` lacks a built-in CoreBluetooth BLE backend, so on macOS the workflow for capturing reference protocol traces is: have Subsurface do the BLE download with verbose logging enabled, save the libdc logfile, then run `extract_libdc_log.py` to recover the raw bytes that flowed over the wire.

The `.read.bin` files produced by that tool are exactly the kind of fixtures this project's parser should be tested against. Treat the two projects as complementary: that one captures protocol traces from real dive computers on macOS, this one consumes them in tests.

