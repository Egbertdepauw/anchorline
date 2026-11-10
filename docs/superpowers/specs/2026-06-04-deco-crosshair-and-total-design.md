# Deco: crosshair readout + total deco — design

**Date:** 2026-06-04
**Status:** Approved design, ready for implementation plan
**Source:** Alex's wishlist, item "Deco" (first of three features; statistics and renumbering get their own specs)

## Goal

Two related additions to the dive-detail view:

1. **Crosshair deco readout** — as the profile crosshair moves, show the decompression state at that point in time: stop depth + minutes at the stop (or NDL when not in deco), TTS, plus live GF99 and ceiling.
2. **Total deco in the dive summary** — show two whole-dive deco numbers: **time in deco** and **peak TTS**.

The "minutes @ depth" the user asked for is the crosshair's **Stop / Stop time / NDL** rows.

## Non-goals

- No full multi-stop deco *schedule* (e.g. "6 m: 3 min, 3 m: 12 min"). The dive computer logs only the current first stop per sample; a full schedule would require deriving it from the replay engine and is out of scope.
- No new always-on profile trace for deco status. Deco state is read at the crosshair and summarized in the stats grid only. (GF99/ceiling traces already exist and are unchanged.)
- No unit-preference work. App is metric; depths in metres, times in minutes.

## Key principle: two data sources

This feature deliberately mirrors architectural principle #1 (*the dive computer is the source of truth; analysis is layered on top*). The readout draws from two sources, and we keep them visually undifferentiated but conceptually distinct:

| Value | Source | Notes |
|---|---|---|
| Stop depth, stop time, NDL, TTS | **DC-recorded**, per-sample (`SampleSet.decoStopDepthMeters`, `decoTimeSeconds`, `ttsSeconds`) | Always present. The DC's own reported obligation. |
| GF99, ceiling | **App-recomputed** by `DecoReplayEngine` (`DecoReplayResult.gf99Series`, `ceilingMeters`) | The app's tissue-model recomputation, not the DC's. |

Both "total deco" summary numbers (time in deco, peak TTS) are computed from **DC-recorded** sample data only — no replay dependency.

## Design

### 1. Shared computations — `lib/data/sample_codec/dive_stats.dart`

Add two pure top-level functions next to `computeOtu` / `minAvgMax` / `verticalSpeedExtremes`, matching their style (take typed arrays + counts, not the whole `SampleSet`). These are reused by the future statistics tab's "longest deco" stat, so the definition lives in exactly one place.

```dart
/// Total time spent in mandatory decompression, in seconds.
/// Counts samples carrying a non-zero deco stop depth and multiplies by
/// the sample interval. Returns 0 for a no-stop (NDL) dive.
int totalTimeInDecoSeconds({
  required Float32List decoStopDepthMeters,
  required int sampleCount,
  required int sampleIntervalMs,
});

/// Peak time-to-surface reached during the dive, in seconds.
/// Returns 0 if no TTS was ever recorded.
int peakTtsSeconds({
  required Int32List ttsSeconds,
  required int sampleCount,
});
```

- `totalTimeInDecoSeconds`: `count(i where decoStopDepthMeters[i] > 0) * sampleIntervalMs ~/ 1000`. **NaN-guard** the depth read (`v.isNaN || v <= 0` → skip), mirroring the existing guards in `computeOtu`/`minAvgMax` for merged-dive surface gaps.
- `peakTtsSeconds`: `max(ttsSeconds[0..n))`, clamped to `sampleCount`. `Int32List` carries no NaN.

**Definitions used throughout the app** (also drives the statistics tab later):
- *Time in deco* = total wall-clock time the DC reported a mandatory stop (ceiling > 0).
- *Peak TTS* = the single largest time-to-surface value the DC reported.

### 2. Crosshair readout — `lib/ui/widgets/crosshair_tooltip.dart`

`CrosshairTooltip` is a `StatelessWidget` that builds a list of `_Row(label, value)`. Add:

- A new constructor param: `final DecoReplayResult? decoReplay;` (nullable so tests / other callers can omit it). Add `import '../../analysis/deco/replay_result.dart';`.
- A private formatter: `static String _fmtMinutes(int seconds) => '${(seconds / 60).round()} min';` (Shearwater stop/TTS/NDL are whole-minute values stored as `×60`, so rounding is exact).
- A deco row-group, inserted **after the `Temp` row** (current line 85) and **before the Gas/tank rows**, at the clamped sample index `i`:

| Row | Condition | Value |
|---|---|---|
| `Stop` | `decoStopDepthMeters[i] > 0` | `'${decoStopDepthMeters[i].toStringAsFixed(1)}m'` |
| `Stop time` | `decoStopDepthMeters[i] > 0` | `_fmtMinutes(decoTimeSeconds[i])` |
| `NDL` | `decoStopDepthMeters[i] == 0 && decoTimeSeconds[i] > 0` | `_fmtMinutes(decoTimeSeconds[i])` |
| `TTS` | `ttsSeconds[i] > 0` | `_fmtMinutes(ttsSeconds[i])` |
| `Ceiling` | `decoReplay != null && i < ceilingMeters.length && ceilingMeters[i] > 0` | `'${ceilingMeters[i].toStringAsFixed(1)}m'` |
| `GF99` | `decoReplay != null && i < gf99Series.length` | `'${gf99Series[i].round()}%'` (band-coloured) |

All array reads are bounds-checked against the relevant `.length` (the per-sample deco arrays and the replay series are all aligned to `sampleCount`, but defensive clamps match the existing tooltip's `i.clamp(...)` discipline).

Row order and visual treatment (grouping hairline, GF99 colour, tabular figures) are specified under *Visual design (frontend-design pass)* below.

### 3. Dive summary stat tiles — `lib/ui/screens/dive_detail_screen.dart`

In `_buildStatsRow` (the secondary stats grid, ~line 1446), compute the two numbers from the already-loaded `samples` and append two `StatTile`s to the `cells` list, right after the existing `SurfGF` / `GF` tiles (after line 1507). Gate both on a deco dive so no-stop dives stay clean (mirrors the existing `showOtu` pattern):

```dart
final timeInDecoSec = totalTimeInDecoSeconds(
  decoStopDepthMeters: samples.decoStopDepthMeters,
  sampleCount: n,
  sampleIntervalMs: samples.sampleIntervalMs,
);
final peakTtsSec = peakTtsSeconds(ttsSeconds: samples.ttsSeconds, sampleCount: n);
final showDeco = timeInDecoSec > 0;
var deepestStopM = 0.0; // for the Deco tile hint
for (var i = 0; i < n; i++) {
  final d = samples.decoStopDepthMeters[i];
  if (!d.isNaN && d > deepestStopM) deepestStopM = d;
}
// ...in cells (neutral/white on purpose — see Visual design):
if (showDeco)
  StatTile(label: 'Deco', unit: 'min',
      value: '${(timeInDecoSec / 60).round()}',
      hint: 'max ${deepestStopM.toStringAsFixed(0)} m'),
if (showDeco)
  StatTile(label: 'TTS', unit: 'min', value: '${(peakTtsSec / 60).round()}'),
```

Labels `Deco` and `TTS` match the short-label convention of the surrounding tiles (`PPO2`, `CNS`, `OTU`, `SurfGF`, `GF`). The grid's existing wrap-vs-row logic flows the two extra tiles automatically. The deliberate neutral colour and the deepest-stop hint are covered under *Visual design* below.

### 4. Deco-replay availability ("always compute") — `lib/ui/screens/dive_detail_screen.dart`

The crosshair's GF99/ceiling must be present regardless of trace toggles. This is nearly free because the replay is **already computed unconditionally** for the stats grid (`_decoEngine.replay(...)` at line 1404, returning a non-null `DecoReplayResult`) and the engine caches by `(diveId, algorithm, gf, vpmb, surfacePressure)`.

Change in the chart's `LayoutBuilder` (lines 636–661):

- **Compute `decoReplay` unconditionally** — drop the `needsReplay` gate so `decoReplay` is always the cached result (same inputs as the stats row → cache hit, no second tissue simulation). `ProfileChart` keeps gating *trace drawing* on `visibleTraces`, so removing the gate causes **no visual change** to the chart itself.
- **Pass `decoReplay` to `CrosshairTooltip`** at line 712 (`decoReplay: decoReplay`). After the gate removal it is non-null for normal dives, so GF99/ceiling rows appear by default; the `decoReplay != null` guards in §2 remain as safety.
- **Fullscreen path:** `_openFullscreenChart` already forwards `decoReplay` (line 706) → it becomes the always-computed value. Also add `decoReplay:` to the `CrosshairTooltip` at `fullscreen_chart_screen.dart:213` (thread it through the fullscreen screen's existing `decoReplay` field).

> Note: replay returns a result for every dive (including OC/gauge), matching how SurfGF/GF already render for all dives. We keep that behavior — no per-mode suppression — for consistency.

## Visual design (frontend-design pass)

The register is **precision within CCRLog's existing dark system**, not reinvention — the deco readout should feel like it was always part of the dive computer's own UI. Each decision is anchored to an existing token.

**Crosshair tooltip**

- **Tabular figures everywhere.** The tooltip's value text is a raw `TextStyle` (unlike the rest of the app, which uses the tabular `NumericReadout`). Add `fontFeatures: const [FontFeature.tabularFigures()]` to the value style (~line 146). As the crosshair scrubs, digits no longer change width, so rows and the tooltip's edge stay rock-steady. This elevates the whole readout; the deco rows — which tick through stop time / TTS / GF99 across the ascent — benefit most. One property, zero layout-size change. (`FontFeature` comes from `dart:ui`, re-exported via `package:flutter/material.dart`.)
- **One grouped section, one hairline.** The deco rows render as a unit, set off by a single 1px divider in the tooltip's own label-grey (`Color(0xFF778899)` at ~25% alpha), inserted directly above them — and only when deco rows exist. Implement by allowing a divider marker among the rows (e.g. a `_Row.divider()` factory / `isDivider` flag) and rendering a thin `Container` for it. It's the minimal intervention that gives "decompression" its own identity in an otherwise flat list of up to ~15 rows. No header, no box — a hairline is enough.
- **GF99 is the single accent.** Its value is coloured by GF band — green `0xFF4ADE80` / amber `0xFFF59E0B` / red `0xFFDC2626` — exactly as the SurfGF/GF summary tiles already are, with the threshold from `decoReplay.gfHigh ?? 85`. Everything else in the group stays white. One meaningful pop of colour beats a wall of it. (The GF99 *trace* on the profile stays amber as a line identity; band-colouring the *readout* matches the app's established tile treatment, so this introduces no new convention.)
- **Group order:** Stop → Stop time / NDL → TTS → Ceiling → GF99 — DC-reported obligation first, model-derived ceiling/GF last.
- **Motion: deliberately none.** This is a real-time scrub readout; the design goal is instant response. An entrance fade/scale would read as lag. Restraint is the correct call here.

**Summary tiles**

- **`Deco` / `TTS` stay neutral white** (no `valueColor`) — on purpose. They sit immediately after the band-coloured SurfGF/GF tiles; keeping durations achromatic anchors the row and lets the risk-coloured tiles pop. A duration isn't a risk band.
- **The `Deco` tile carries a hint** (`AppTypography.caption`, the same secondary slot Temp uses for min/max): the deepest stop, e.g. `max 6 m`. The tile then says both *how long* and *how deep* the obligation was, in one glance, at no extra row cost. `TTS` stays hintless — peak TTS is already its own headline.

**Shared token**

- Extract the GF-band colour logic (today a local `colourForGf` closure in `_buildStatsRow`) into a shared `gfBandColor(double gf, {double gfHigh})` under `lib/ui/theme/`, so the tooltip and the tiles speak one colour language from one definition.

**Typography:** no new fonts. In a product with an established type system, impeccable *use* of `AppTypography` / `NumericReadout` is the refined choice; a novelty display font for two tiles would be the unrefined one.

## Formatting rules

- Stop depth / ceiling: one decimal metre, `'X.Xm'` (matches the tooltip's depth row).
- Stop time / NDL / TTS: whole minutes, `'X min'`.
- Summary `Deco` / `TTS` tiles: whole-minute integer value, unit `'min'`.
- GF99: integer percent, `'N%'`.

## Edge cases

- **NDL dive** (never any stop): no deco rows except an `NDL` line at the crosshair; both summary tiles hidden.
- **Merged dives:** surface-gap NaNs are skipped by the NaN guard in `totalTimeInDecoSeconds`; the crosshair clamps index and bounds-checks, so a NaN/zero stop simply renders as "not in deco" at that sample.
- **Very long deco** (> 60 min): still shown as minutes (e.g. `75 min`) — acceptable for the audience; no h:mm needed.
- **Replay unavailable / empty series** (defensive): `decoReplay != null` + length guards drop GF99/ceiling rows without error.

## Testing

- **Unit (primary):** extend `test/data/sample_codec/dive_stats_test.dart` for the two new helpers:
  - NDL-only dive → `totalTimeInDecoSeconds == 0`, hidden tiles.
  - Mixed dive: known count of in-deco samples × interval → exact seconds.
  - `peakTtsSeconds` returns the max, 0 when all-zero.
  - NaN in `decoStopDepthMeters` is skipped (merged-dive case).
  - Interval scaling (5 s vs 10 s sampling) yields proportional results.
- **Verify:** `flutter analyze` clean, `flutter test` green. Spot-check the dive-detail crosshair + summary on a real deco dive (manual).

## Files touched

| File | Change |
|---|---|
| `lib/data/sample_codec/dive_stats.dart` | + `totalTimeInDecoSeconds`, `peakTtsSeconds` |
| `lib/ui/theme/` (e.g. `gf_color.dart`) | + shared `gfBandColor(gf, {gfHigh})` |
| `lib/ui/widgets/crosshair_tooltip.dart` | + `decoReplay` param & import; `_fmtMinutes`; deco row-group; **tabular-figures value style**; **group hairline divider**; GF99 via `gfBandColor` |
| `lib/ui/screens/dive_detail_screen.dart` | compute replay unconditionally; pass `decoReplay` to tooltip; + 2 stat tiles (neutral, `Deco` with deepest-stop hint); swap local `colourForGf` → shared `gfBandColor` |
| `lib/ui/screens/fullscreen_chart_screen.dart` | pass `decoReplay` (`widget.decoReplay`) to its `CrosshairTooltip` |
| `test/data/sample_codec/dive_stats_test.dart` | + tests for the two helpers |

## Resolved decisions

- Total deco = **both** time-in-deco and peak TTS (this same time-in-deco definition feeds the future "longest deco" statistic).
- Crosshair shows **Stop + TTS + GF99/ceiling** (with NDL out of deco).
- GF99/ceiling at crosshair = **always computed** (cheap: reuses the stats grid's cached replay).
- Visual register = **refined precision within the existing dark system** (frontend-design pass): tabular figures, one grouping hairline, GF99 as the single band-coloured accent, neutral summary tiles, shared `gfBandColor`. No new fonts, no motion.
