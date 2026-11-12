# Gas Density + END Traces — Design Spec

**Date:** 2026-05-13
**Track:** B of the four-track 2026-05-13 wishlist.
**Source request:** User wants toggleable chart traces and max-value stat tiles for both gas density and END, colour-graded so it's visible where the gas crosses CCR safety thresholds.

## Goal

Add per-sample gas-density and END calculations to the profile chart as
two new toggleable traces (driven from the segmented bar), plus two new
StatTiles in the row below the chart showing the dive's max value of
each, colour-graded by the thresholds the trace itself uses.

## Why

Modern CCR + tech-diving education places gas density and END at the
front of safety analysis. Density >5.7 g/L is associated with elevated
CO₂-retention risk (Anthony/Mitchell); END >30 m is associated with
inert-gas narcosis. Today the user has to mentally compute both —
density not at all, END only roughly via "depth vs helium fraction"
intuition. Surfacing both per-sample makes it visible whether a dive
crossed the thresholds and for how long.

This track was originally roadmap-priority 2 yesterday. It depends on
nothing else and unblocks the rest of the tech-analysis Track.

## Decisions locked during brainstorming

- **Gas density thresholds:** standard tech (`<5.2 g/L green, 5.2–5.7
  orange, >5.7 red`). Matches Shearwater's own warning at 5.7.
- **END formula default:** N₂ + O₂ both count as narcotic (modern
  US-Navy / IANTD / TDI teaching). Settings toggle
  `endCountsOxygen` (default ON) — when off, switches to the
  formula counting only N₂.
- **END thresholds:** `<30 m green, 30–40 m orange, >40 m red`. No
  Settings option; these are near-universal in tech education.
- **Trace placement:** END shares the depth axis (END is always at or
  shallower than current depth, overlays naturally). Density has no
  explicit axis — its colour-graded bands ARE the visual scale; the
  exact number lives in the StatTile.
- **Stat tile content:** max value only, no time-in-band stat.
- **Segmented bar:** two new segments `Density` and `END` added to the
  right of the existing six. Default **OFF** for both (keep the chart
  un-cluttered for casual dives; user-toggleable, persists per Track
  4's persistence mechanism).
- **Edge cases:** OC works the same way (active gas mix at each sample
  drives the calc). Gas-switch points create a density discontinuity —
  show as a vertical step matching the existing dashed gas-change
  indicator. Samples without an active mix (rare, parser fallback) are
  skipped, not rendered as zero.

## Scope

### In scope

1. **Per-sample density calculation** in a new
   `lib/analysis/gas_density.dart` — input is a `SampleSet`, output is
   a `Float32List` of `length = sampleCount`, one density value per
   sample (g/L). Uses the per-sample `gasMixIndex` to look up the mix's
   density at 1 ATA, then multiplies by ambient pressure derived from
   `samples.depthMeters[i]` + `dive.atmosphericPressureMbar`.
2. **Per-sample END calculation** in a new `lib/analysis/end.dart` —
   same shape as density. Formula choice from `SettingsNotifier`.
3. **Gas mix density helpers** in `lib/analysis/gas_density.dart` —
   constants for `o2DensityAt1Atm = 1.314 g/L`, `n2DensityAt1Atm =
   1.165 g/L`, `heDensityAt1Atm = 0.166 g/L`, weighted sum function
   `mixDensityAt1Atm(o2, he) -> double`.
4. **Two new chart traces** in `lib/ui/widgets/profile_chart.dart`,
   following the existing TraceType pattern. The colour of each
   sample-segment is chosen by the value's band (green/orange/red).
5. **Two new TraceType enum entries** `TraceType.density` and
   `TraceType.end`, added to `lib/ui/widgets/trace_segmented_bar.dart`.
6. **Two new segments** in `TraceSegmentedBar`'s `_segmentData` map
   with labels "Density" and "END".
7. **Two new StatTiles** in `_buildStatsRow` of `dive_detail_screen.dart`:
   `Max ρ` showing the max density in g/L with the value text coloured by
   the same threshold bands, and `Max END` showing the max END in metres
   with the same colour treatment.
8. **`endCountsOxygen` setting** on `SettingsNotifier` — SharedPreferences
   key `end_counts_oxygen`, default `true`. Getter + setter + load.
9. **Settings UI** — new row in the Settings page (Graph subsection):
   "Count O₂ as narcotic in END" with a Switch tile.
10. **Tests:**
    - `test/analysis/gas_density_test.dart` — air at 30 m → 4.9 g/L,
      18/45 at 60 m → ~3.4 g/L, EAN 50 at 6 m → 2.0 g/L (table-driven)
    - `test/analysis/end_test.dart` — air at 30 m → 30 m,
      18/45 at 60 m / formula A → 28.5 m, 18/45 at 60 m / formula B →
      22.8 m, N₂ 79% at 30 m → 30 m
    - Extend `test/ui/notifiers/settings_notifier_test.dart` with
      `endCountsOxygen` round-trip
    - `test/ui/widgets/profile_chart_test.dart` — visible-traces set
      including density/END renders the new traces; toggling them off
      doesn't render
    - `test/ui/widgets/trace_segmented_bar_test.dart` — extend the
      "renders eight segments" test (was six)

### Out of scope

- Per-segment width changes on the chart trace (uniform stroke width;
  colour is the only band signal)
- Time-in-red statistics (e.g. "spent 2 min over 5.7 g/L") — could ship
  later if useful
- Hard limits / alarms — chart shows the colour, user reads it; no
  automated warnings
- Custom user-defined thresholds — values are hardcoded constants;
  could become Settings entries later if requested
- "Best gas at depth" suggester widget — distinct feature
- Compatibility with old samples that don't carry mix info — those just
  render no density/END trace

## Architecture

### Component flow

```
SettingsNotifier
  └── endCountsOxygen (bool, default true, persisted)

lib/analysis/gas_density.dart
  ├── const o2DensityAt1Atm, n2DensityAt1Atm, heDensityAt1Atm
  ├── mixDensityAt1Atm(o2Fraction, heFraction) -> double  (g/L)
  └── computeDensitySeries(SampleSet, gasMixes, atmMbar) -> Float32List

lib/analysis/end.dart
  └── computeEndSeries(SampleSet, gasMixes, countsOxygen) -> Float32List

lib/ui/widgets/profile_chart.dart
  └── ProfileChart consumes density + end series when those traces are
      in visibleTraces, draws as colour-banded line segments

lib/ui/screens/dive_detail_screen.dart
  └── _buildStatsRow adds Max-ρ and Max-END StatTiles, colour from the
      max value's threshold band
```

### Formulas

**Gas density:**
```
mixDensityAt1Atm = o2 * 1.314 + he * 0.166 + (1 - o2 - he) * 1.165   // g/L
ambientPressureBar = atmMbar/1000 + depthMeters/10                    // bar
densityAtSample = mixDensityAt1Atm * ambientPressureBar               // g/L
```

**END (formula A, default, "N₂ + O₂ count"):**
```
END(m) = max(0, (depth + 10) * (1 - heFraction) - 10)
```

**END (formula B, when `endCountsOxygen == false`):**
```
END(m) = max(0, (depth + 10) * (n2Fraction / 0.79) - 10)
```

The `max(0, ...)` clamp keeps shallow heliox readings from going negative.

### Threshold bands

```
density (g/L):  [0, 5.2) green   [5.2, 5.7) orange   [5.7, inf) red
END (m):        [0, 30)  green   [30, 40)   orange   [40, inf)  red
```

Constants live in `gas_density.dart` and `end.dart` respectively (so
the chart, stat tile, and tests all reference the same source).

## Risks

- **Performance:** computing density/END per sample is O(N) and runs
  on every chart rebuild. Profile a 4 000-sample dive (current cap) —
  should be <5 ms. Cache the result on the notifier so repeated
  rebuilds don't recompute. (Same pattern as existing per-sample
  derived series, e.g. CNS.)
- **Settings toggle affects the END series globally** — when the user
  flips `endCountsOxygen` while viewing a dive, the trace needs to
  recompute. `ListenableBuilder` on `SettingsNotifier` already wraps
  the chart subtree (Track 4), so this rebuild fires automatically.
  The cached `endSeries` must invalidate when the setting flips —
  store the cache key alongside the result and bust on mismatch.

## Testing strategy

- Unit tests with table-driven inputs covering the formula corner cases
- Widget tests verifying the new segments render + StatTiles appear
- `flutter analyze` clean
- `flutter test` passes (target 699 + ~6 new = 705)
- Manual smoke: open a CCR dive on trimix, toggle Density on — see
  colour bands; toggle off; flip the Settings toggle for END — see the
  trace lower itself; check the StatTiles update

## Definition of done

1. Both analysis modules with unit tests
2. SettingsNotifier extension + test
3. TraceType enum extended (segmented-bar test count updated)
4. ProfileChart renders both new traces
5. `_buildStatsRow` shows both StatTiles
6. Settings UI shows the "Count O₂ as narcotic in END" switch
7. `flutter analyze` clean, full suite green
8. Manual smoke on a real dive passes
