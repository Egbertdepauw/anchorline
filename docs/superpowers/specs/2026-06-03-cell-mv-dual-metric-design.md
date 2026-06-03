# Cell mV chart — dual-metric + health reference lines

**Date:** 2026-06-03
**Status:** Approved, pending implementation
**Area:** `lib/ui/widgets/cell_mv_chart.dart`, `lib/ui/screens/equipment/cell_detail_screen.dart`, `lib/data/db/equipment_dao.dart`

## Problem

The per-cell mV chart on the Cell detail screen renders an orange line with no
axis labels, no scale, and no reference — you can't tell whether a spike is a
2 mV wobble or a 20 mV cliff, nor when degradation began. Axis labels/scales were
added in a prior change. This spec covers the remaining work to make the chart
*diagnostic*.

A deeper issue surfaced during design: the chart plots **surface mV** while the
"Healthy / Watch / Replace" pill is computed from **peak mV** — two different
metrics:

- **Surface mV** (`EquipmentDao._computeSurfaceMv`): mean of `cellMv[slot]` over
  samples with `depth < 1.0 m` and `mv >= 5.0`. This tracks the loop PPO2 at the
  surface (air vs an O2 flush), which varies dive-to-dive. A galvanic cell reads
  ~10 mV in air but ~50 mV in pure O2 at the surface, so the surface trace mixes
  real cell behaviour with whatever was in the loop that day. An absolute
  "healthy band" over this trace would mislead.
- **Peak mV** (`EquipmentDao._peakMvForSlot` → `analysis/cell_health.dart`):
  per-dive max, occurring near setpoint PPO2 (~1.3) at depth. Far more comparable
  across dives, and it is what drives the health verdict via
  `recentPeak / baselinePeak` (≥0.85 healthy, ≥0.70 watch, else replace).

## Goals

1. Let the user view both metrics, switchable, so surface mV stays available but
   the diagnostic peak-mV view is front-and-centre.
2. On the peak-mV view, draw the exact health reference the pill uses: a baseline
   line plus the 0.85× (Watch) and 0.70× (Replace) threshold lines.
3. Auto-fit the Y-axis so the thresholds are always visible. No zero-based toggle
   (YAGNI — the threshold lines provide the reference).

## Non-goals

- Changing the health heuristic in `analysis/cell_health.dart`. The thresholds
  (5-dive baseline, 0.85/0.70 ratios) are reused as-is.
- A PPO2-normalised ("mV per ATA", calibration-coefficient) metric. Worth
  considering later but out of scope here.
- Longitudinal cross-*cell* comparison. This screen stays single-cell.

## Design

### Data layer — `equipment_dao.dart`

Add a single-pass loader:

```dart
typedef MvPoint = ({DateTime date, double mv, String diveId});

Future<({List<MvPoint> surface, List<MvPoint> peak})> mvSeriesForCell(
    String cellId) async { ... }
```

- Iterates the cell's dive window (`_divesInWindow(installedDate, retiredDate)`)
  once, loading sample blobs once via `_samplesForDives`.
- Per dive: compute surface mV (`_computeSurfaceMv`) and peak mV
  (`_peakMvForSlot`); append to the respective list when non-null. The two lists
  may differ in length (peak only requires `mv >= 5` anywhere; surface also
  requires `depth < 1`).
- Refactor the existing `surfaceMvSeriesForCell` to delegate to
  `mvSeriesForCell(cellId).surface` so there is one source of truth and existing
  callers/tests keep working.

**Baseline for the threshold lines** is *not* recomputed — it reuses
`CellHealth.baselinePeakMv` already produced by `evaluateHealthForCell` (max peak
of the first 5 dives). When fewer than 5 dives exist, `baselinePeakMv` is null and
the chart omits the threshold lines.

### Widget — `cell_mv_chart.dart`

API change. New props:

```dart
const CellMvChart({
  required List<MvPoint> surfaceSeries,
  required List<MvPoint> peakSeries,
  double? baselinePeakMv,
  double height = 220,
  void Function(String diveId)? onDiveTap,
});
```

- Internal state `CellMvMetric { surface, peak }`, **defaulting to `peak`** (the
  diagnostic view; consistent with the pill). Trivial to flip to `surface`.
- A `SegmentedButton<CellMvMetric>` at the top (labels "Surface mV" / "Peak mV"),
  mirroring the `SegmentedButton` usage in `lib/ui/widgets/plan_settings_panel.dart`.
  The chart fills the remaining height below it.
- `_ChartLayout` is parameterised by the active series plus optional threshold
  values. When thresholds are present (peak view with a baseline), the Y-range
  spans `min(0.70×baseline, dataMin) … max(baseline, dataMax)`, padded to a nice
  range, so all three reference lines and all data points are visible. Surface
  view (no thresholds) keeps the current padded nice-range behaviour.
- `_ChartPainter`, on the peak view with a baseline, draws:
  - solid **baseline** line in a muted colour (`textSecondary`), labelled `base`;
  - dashed **0.85×** line in amber (`AppColors.wreck.statusWarning`), labelled `0.85×`;
  - dashed **0.70×** line in red (`AppColors.wreck.statusDanger`), labelled `0.70×`.
  - Labels sit at the right edge in the existing JetBrains Mono 9pt axis style.
  - A small `_drawDashedLine` helper mirrored from `dive_profile_chart.dart`.
- Axes, gridlines, the orange data line, dots, tap-to-select, and the tooltip are
  all preserved. The tooltip's `mV` unit applies to both metrics.
- Per-metric empty state: if the active series is empty, show
  "No peak-mV data yet" / "No surface-mV data yet".

### Screen — `cell_detail_screen.dart`

- `_load()` calls `mvSeriesForCell`, stores `_surface` and `_peak`, and passes
  both plus `_health?.baselinePeakMv` into `CellMvChart`.
- "Dives with mV data: N" switches from `_series.length` to the **peak** series
  count (the superset / most representative of "has cell data").

### Data flow

```
_load()
  ├─ dao.mvSeriesForCell(cellId)      → (surface, peak)   [one sample pass]
  └─ dao.evaluateHealthForCell(cellId) → CellHealth        [pill + baselinePeakMv]
        │
        ▼
CellMvChart(surfaceSeries, peakSeries, baselinePeakMv)
        │
        ▼
_ChartPainter: active metric line + (peak view) baseline / 0.85× / 0.70×
```

### Error handling / edge cases

- `baselinePeakMv == null` (<5 dives) → no threshold lines, chart still renders.
- Active series empty → empty-state text.
- Single data point → dots only, no line (existing layout clamps prevent
  divide-by-zero).
- Data peaking above baseline → range includes `dataMax` so nothing clips.

## Testing

- **DAO test** (mirror `test/data/db/cell_mv_from_powersync_test.dart`): seed
  sample blobs for a cell and assert `mvSeriesForCell` returns surface = mean of
  `mv` where `depth < 1`, and peak = max `mv >= 5`, per dive.
- **Widget test** (new `test/ui/widgets/cell_mv_chart_test.dart`): pump with both
  series + a baseline; verify it renders without exception in both metric modes
  (tap the segmented control to switch), and that an empty active series shows the
  empty-state text. No goldens.
- `flutter analyze` clean, `flutter test` passing.

## Out of scope / follow-ups

- PPO2-normalised mV metric (the true calibration-coefficient health signal).
- Surfacing the same dual-metric chart in a future cross-cell longitudinal view.
