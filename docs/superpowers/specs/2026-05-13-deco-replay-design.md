# Tissue Replay Engine (ZHL-16C + VPM-B) — Design Spec

**Date:** 2026-05-13
**Track:** C of the four-track 2026-05-13 wishlist. Foundational — Tracks D (bailout) and the existing roadmap item "Surface GF % display" both depend on this.
**Source request:** User wants per-sample tissue saturation replay surfaced as chart traces, stat tiles, and a heatmap. Toggle between ZHL-16C and VPM-B. Take Subsurface as the reference; improve where reasonable.

## Goal

Build a pure-Dart deco-replay engine that consumes a parsed dive's
sample stream and produces, per dive:

- Per-sample GF99 (instantaneous gradient factor) trace
- Per-sample deco ceiling (m) trace
- Per-sample tissue saturation (16-band, ZHL-16C) heatmap data
- Aggregate Surface GF (would-be GF if surfaced now) and Max GF stats
- An API method `tissueStateAt(diveId, sampleIndex)` for Track D

…with the user able to switch between the ZHL-16C and VPM-B algorithms
per-dive, and tune VPM-B conservatism via a global Settings entry.

## Why

Surface GF, Max GF, ceiling profile, and per-tissue saturation are the
foundational outputs of any modern dive analysis tool. Shearwater shows
them in flight; Subsurface shows them post-dive; we don't show them at
all today. Beyond the standalone value, the engine unblocks the
"bailout gas requirement" track (D) which needs `tissueStateAt(t)` to
plan ascents.

Reference for fidelity: Subsurface's `core/deco.cpp`. Reference for
algorithm specs: Erik Baker's GF papers (1998–2005) for ZHL-16C+GF and
the Yount-Hoffman / Erik Baker VPM-B writeups.

## Decisions locked during brainstorming

- **Outputs in v1:** all four — GF99 trace, ceiling trace, Surface GF +
  Max GF stat tiles, tissue saturation heatmap. Full Subsurface-equivalent.
- **Algorithm selection:** **per-dive**, persisted. Small dropdown
  control inline near the chart (`[ZHL-16C ▾]` / `[VPM-B ▾]`).
  Default ZHL-16C on first view.
- **GF source for ZHL-16C:** dive's recorded GF low/high from the
  Petrel binary (already parsed into `Dive.gfLow` / `gfHigh`). No
  override UI in v1.
- **VPM-B conservatism:** global Settings only. Integer 0–4. Default 2.
- **Tissue heatmap:** collapsible section below the chart, default
  collapsed. Header `Tissue saturation [ZHL-16C] ▾`.
- **Implementation strategy:** hybrid port. Canonical *data* (M-values,
  half-times, a/b coefficients, VPM-B critical radii / conservatism
  schedules) lifted verbatim from Subsurface. Integration *logic*
  reimplemented in idiomatic Dart with explicit unit tests validating
  against Subsurface's output on a fixed set of test dives, with
  tolerance ±0.5 GF99 / ±2 % Surface GF.
- **Caching:** in-memory cache keyed by `(diveId, algorithm,
  vpmbConservatism, gfLow, gfHigh)`. Recompute when any key changes.
  No persistent cache — replay is sub-second for typical dives.

## Scope

### In scope

1. **Algorithm engines** — pure Dart, no FFI:
   - `lib/analysis/deco/tissue_model.dart` — ZHL-16C constants
     (16 tissue compartments, N₂ + He half-times, Workman/Bühlmann
     a/b coefficients lifted from Subsurface). Pure data, no logic.
   - `lib/analysis/deco/vpmb_constants.dart` — VPM-B critical-radii
     tables, conservatism-schedule data lifted from Subsurface.
   - `lib/analysis/deco/zhl16c.dart` — ZHL-16C+GF integration loop.
     Schreiner equation for tissue loading per sample interval.
     GF99 = `(supersaturation / m_value_gradient) * 100`. Ceiling from
     the most-saturated compartment.
   - `lib/analysis/deco/vpmb.dart` — VPM-B replay. Bubble model:
     initial critical radius per compartment, regenerated per ascent
     phase, conservatism applies a "set point" reduction on allowed
     supersaturation.
   - `lib/analysis/deco/replay_result.dart` — output value object:
     ```dart
     class DecoReplayResult {
       final Float32List gf99Series;        // length = sampleCount
       final Float32List ceilingMeters;     // length = sampleCount
       final List<Float32List> tissueLoadsPct;  // 16 × sampleCount,
                                            // each = current load
                                            // relative to M-value (%)
       final double surfaceGfFinal;         // GF if surfaced at last sample
       final double maxGf99;                // peak GF99 across the dive
       final DecoAlgorithm algorithm;
       final int? vpmbConservatism;         // null for ZHL-16C
       final int? gfLow;
       final int? gfHigh;
     }
     ```
   - `lib/analysis/deco/replay_engine.dart` — orchestrator. Holds an
     in-memory `LinkedHashMap<CacheKey, DecoReplayResult>` capped at 16
     entries (LRU eviction). Dispatch to ZHL-16C or VPM-B based on the
     per-dive selection.

2. **SettingsNotifier extension:**
   - `int get vpmbConservatism` (range 0–4, default 2)
   - `Future<void> setVpmbConservatism(int v)` — clamps to 0..4
   - SharedPreferences key `vpmb_conservatism`
   - Settings UI: segmented selector `+0 / +1 / +2 / +3 / +4` in the
     Deco subsection

3. **Per-dive algorithm selection (persisted):**
   - New column `display_deco_algorithm TEXT` on `dive_annotations`
     (PowerSync-synced so the choice follows the user across devices).
     Values: `'zhl16c'`, `'vpmb'`. NULL = use default (`'zhl16c'`).
   - Migration `0010_display_deco_algorithm.sql` adds the column.
   - `DiveAnnotation` model gains `String? displayDecoAlgorithm` field.
   - `DiveAnnotationsNotifier` gains `String get displayDecoAlgorithm`
     (default `'zhl16c'`) + `Future<void>
     setDisplayDecoAlgorithm(String)`.
   - UI: small `DropdownButton` rendered inline above the segmented
     trace bar on the Details tab. Label: `Algorithm: ZHL-16C ▾`.

4. **New chart traces:**
   - `TraceType.gf99` and `TraceType.ceiling` added to the enum in
     `trace_segmented_bar.dart`. `_segmentData` extended with both —
     labels "GF99" and "Ceiling". Both default off in the persisted set.
   - `ProfileChart` consumes `gf99Series` and `ceilingMeters` from the
     replay result. GF99 trace shares the existing PPO2 right axis but
     scaled to 0–150 % (the GF range we care about). Ceiling trace
     shares the depth axis (ceiling is always at-or-shallower-than
     current depth, overlays naturally as a line above the depth fill).

5. **New stat tiles in `_buildStatsRow`:**
   - `Surface GF` — colour-graded: green ≤ user's GF-high, orange
     between GF-high and 100, red >100
   - `Max GF` — same colour rules applied to the dive's peak GF99

6. **Tissue saturation heatmap widget:**
   - `lib/ui/widgets/tissue_saturation_heatmap.dart` — collapsible
     section. When expanded, renders 16 horizontal bands (one per ZHL-16
     compartment, fastest at top, slowest at bottom). Each band is a
     row of pixels coloured by saturation:
     - <70 % of M-value = blue / "loading"
     - 70–95 % = yellow / "near limit"
     - 95–100 % = orange / "at limit"
     - >100 % = red / "supersaturated"
   - X-axis aligns with the profile chart's time axis above.
   - Tap on the header expands/collapses; state persisted to a
     `tissueHeatmapExpanded` Settings field (default false).

7. **API for Track D:**
   - `ReplayEngine.tissueStateAt(diveId, sampleIndex) -> TissueState`
     returning a snapshot the bailout-planner can use to forward-simulate
     an OC ascent from that point.

8. **Tests:**
   - `test/analysis/deco/tissue_model_test.dart` — constant table
     integrity (16 compartments, both N₂ and He half-times, all a/b
     defined)
   - `test/analysis/deco/zhl16c_test.dart` — fixture dives. Input a
     known dive, assert GF99 series and Surface GF match Subsurface's
     output within tolerance. Start with 3 fixture dives spanning OC
     air, OC trimix deco, CCR trimix.
   - `test/analysis/deco/vpmb_test.dart` — same fixture dives, output
     compared against Subsurface's VPM-B at each conservatism level.
   - `test/analysis/deco/replay_engine_test.dart` — cache hits don't
     recompute (assert via a counting wrapper); cache evicts at >16
     entries; invalidates when algorithm or conservatism changes.
   - Extend `test/ui/notifiers/settings_notifier_test.dart` with
     `vpmbConservatism` round-trip + clamp test.
   - `test/ui/widgets/tissue_saturation_heatmap_test.dart` — renders
     16 bands; collapsed by default; tap-to-expand state propagates.
   - Extend `test/ui/widgets/profile_chart_test.dart` for the new
     traces.
   - Schema migration test for `display_deco_algorithm` column.

### Out of scope for v1

- Algorithms other than ZHL-16C+GF and VPM-B (no VVAL-18, RGBM, B-RGBM,
  ZHL-16A, ZHL-16B)
- Per-dive GF override (use the recorded values verbatim)
- Per-dive VPM-B conservatism override (global only)
- Comparison view (two algorithms side-by-side simultaneously)
- Bailout-from-any-point ascent simulation (that's Track D)
- Individual-tissue zoom view, per-compartment toggle
- "Recreate the deco schedule" — we replay what happened, we don't
  re-plan
- Tissue-state visualisation as anything other than the 16-band
  heatmap (no spaghetti plot, no 3D)

## Architecture

### Layered structure

```
lib/analysis/deco/
  tissue_model.dart       — ZHL-16C constants (pure data)
  vpmb_constants.dart     — VPM-B critical radii + conservatism tables (pure data)
  schreiner.dart          — Tissue-loading equation, shared by both algorithms
  zhl16c.dart             — ZHL-16C+GF replay loop, M-value calculation
  vpmb.dart               — VPM-B replay loop, bubble-radius regeneration
  replay_result.dart      — Output value object
  replay_engine.dart      — Orchestrator + cache + dispatch
```

Each file has one responsibility:

- **`tissue_model.dart`** — defines `class TissueCompartment` (half-time
  N₂ + He, Bühlmann a/b), exposes `const List<TissueCompartment>
  zhl16cTissues` with 16 entries. No logic, just data.
- **`vpmb_constants.dart`** — VPM-B `R0_n2[16]`, `R0_he[16]` initial
  critical radii, plus conservatism-level → "γ" + "γc" reduction
  factors lifted from Subsurface's `core/deco.cpp`.
- **`schreiner.dart`** — single function `loadCompartment(currentLoad,
  inertGasPp, halfTimeMin, intervalSec) -> double`. The Schreiner
  equation. Used by both algorithms.
- **`zhl16c.dart`** — class `Zhl16cReplay`. Method `run(SampleSet,
  gasMixes, gfLow, gfHigh) -> DecoReplayResult`. Per sample: update
  every compartment via Schreiner, compute GF99 from current
  supersaturation, compute ceiling from the most-saturated compartment.
- **`vpmb.dart`** — class `VpmbReplay`. Method `run(SampleSet,
  gasMixes, conservatism) -> DecoReplayResult`. Per sample: update
  compartments, regenerate bubble radii on ascent, derive allowed
  supersaturation from current radii + conservatism factors. Compute
  GF99 equivalent + ceiling.
- **`replay_engine.dart`** — class `DecoReplayEngine`. Holds the LRU
  cache. Method `replay(Dive dive, SampleSet samples, List<DiveGasMix>
  gasMixes, DiveAnnotation annotation, SettingsNotifier settings) ->
  DecoReplayResult`. Picks algorithm from `annotation.displayDecoAlgorithm
  ?? 'zhl16c'`. Reads `vpmbConservatism` + `gfLow` / `gfHigh` from the
  appropriate sources.

### Data flow

```
DiveDetailScreen.build
  ↓
DecoReplayEngine.replay(dive, samples, gasMixes, annotation, settings)
  ↓
Cache hit? → return cached DecoReplayResult
Cache miss → dispatch:
  if annotation.displayDecoAlgorithm == 'vpmb':
    → VpmbReplay.run(samples, gasMixes, settings.vpmbConservatism)
  else:
    → Zhl16cReplay.run(samples, gasMixes, dive.gfLow, dive.gfHigh)
  ↓
Result cached + returned to UI for trace + stat + heatmap rendering
```

### Persisted state

- **Per-dive:** `dive_annotations.display_deco_algorithm` (text, nullable)
- **Per-user (Settings):** `vpmbConservatism` (int 0–4), `tissueHeatmapExpanded` (bool)
- **Per-dive (already exists from Petrel parse):** `Dive.gfLow`, `Dive.gfHigh`

### File touch summary

| File | Change |
|---|---|
| `supabase/migrations/0010_display_deco_algorithm.sql` | **NEW** — add column to `dive_annotations` |
| `lib/data/db/database.dart` | Bump schema version; add `displayDecoAlgorithm` column to `DiveAnnotationsTable` |
| `lib/data/models/annotation.dart` | Add `String? displayDecoAlgorithm` field, copyWith, fromRow |
| `lib/data/db/dive_annotations_dao.dart` | Plumb the column through upsert + read paths |
| `lib/ui/notifiers/dive_annotations_notifier.dart` | Getter + setter, dirty-flag plumbing |
| `lib/ui/notifiers/settings_notifier.dart` | `vpmbConservatism` + `tissueHeatmapExpanded` fields |
| `lib/analysis/deco/*.dart` | **NEW** files (six) per the layered structure above |
| `lib/ui/widgets/trace_segmented_bar.dart` | Extend enum + `_segmentData` |
| `lib/ui/widgets/profile_chart.dart` | Consume new series for GF99 + Ceiling traces |
| `lib/ui/widgets/tissue_saturation_heatmap.dart` | **NEW** widget |
| `lib/ui/screens/dive_detail_screen.dart` | Inline algorithm dropdown, Surface GF + Max GF stat tiles, heatmap collapsible section |
| `lib/ui/screens/settings_screen.dart` | VPM-B conservatism segmented selector |
| Tests | Six new test files + extensions to four existing |
| `infra/powersync-sync-rules.yaml` | Add `display_deco_algorithm` to the synced column list |

## Validation strategy

**Fixture-based regression tests.** For each algorithm, store 3 known
test dives in `test/analysis/deco/fixtures/`:

1. `oc_air_30m_20min.bin` — recreational profile, no deco
2. `oc_trimix_60m_20min_decostops.bin` — tech profile with deco
3. `ccr_trimix_setpoint_120min.bin` — long CCR dive with setpoint
   changes

For each fixture we record Subsurface's outputs (`gf99`, `surface_gf`,
`ceiling`) at every 60-second interval into a sibling YAML file. The
test then runs our engine on the same `.bin` and asserts every recorded
output matches within tolerance (±0.5 GF99, ±2 % Surface GF, ±0.5 m
ceiling).

This is the same approach Subsurface itself uses in its own
`tests/testdeco.c`. Our tolerance is intentionally non-zero — even
Subsurface has shipped GF99 fixes over the years, and exact byte-match
isn't the goal; "close enough that the user can't tell the difference"
is.

When a fixture starts failing after a code change, the diff in the
output reveals exactly what changed and we can audit whether it's a bug
or an intentional improvement. If improvement, regenerate the fixture
YAML.

## Risks

- **Subsurface deco code has 20+ years of accumulated bug fixes.**
  Reimplementing means we'll potentially re-introduce some. Mitigation:
  the fixture-test approach catches divergence early. We can compare
  byte-for-byte if needed.
- **VPM-B's bubble-regeneration logic is the most error-prone part.**
  Subsurface's implementation has nuances around ascent-phase detection
  that aren't fully documented in the academic papers. We'll need to
  trace through their code carefully. Plan: port `core/deco.cpp`
  function-by-function with the fixture tests verifying each step.
- **Performance:** 16 compartments × 4 000 samples × Schreiner equation
  = 64 000 floating-point updates per replay. That's <50 ms on any
  modern device. The LRU cache means repeat views are free.
- **Schema migration on existing devices:** the new column needs to
  hydrate cleanly into existing PowerSync local data. Standard pattern
  — add column NULL, existing rows get NULL, treated as "use default
  algorithm".
- **Algorithm consistency between display and Track D's bailout calc:**
  Track D uses the same engine for ascent planning. Result must be
  deterministic given the same inputs — no random seeding, no
  time-dependent state.

## Testing strategy

- Unit tests for `tissue_model.dart` constants (table integrity)
- Schreiner equation unit test with worked examples from Bühlmann's book
- Per-algorithm fixture regression tests (3 fixtures × 2 algorithms = 6
  test groups, each asserting ~30 time-points)
- Engine cache tests (hit/miss/invalidation/LRU eviction)
- Widget tests for new chart traces + heatmap + stat tiles
- Schema migration test
- Integration smoke: load a real dive, exercise both algorithms, verify
  no crashes + reasonable numbers

`flutter analyze` must come back clean; `flutter test` target is +20
new tests (~720 total).

## Definition of done

1. All six analysis files with unit + fixture tests
2. Migration applied, `dive_annotations.display_deco_algorithm` exists
   on both Postgres + PowerSync local
3. SettingsNotifier extended; UI for VPM-B conservatism
4. ProfileChart renders both new traces correctly
5. Inline algorithm dropdown wired to per-dive persistence
6. Surface GF + Max GF stat tiles display + colour-grade correctly
7. Tissue heatmap renders + collapses + persists state
8. `tissueStateAt(diveId, sampleIndex)` API exposed for Track D
9. `flutter analyze` clean, full suite green
10. Manual smoke against the user's own dives: open a CCR trimix dive
    in ZHL-16C, see plausible GF99 + ceiling + heatmap; switch to
    VPM-B via the inline dropdown, see the numbers shift; tune VPM-B
    conservatism in Settings, see it reflect on the dive
