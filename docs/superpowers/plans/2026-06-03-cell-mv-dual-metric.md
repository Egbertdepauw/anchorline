# Cell mV Chart — Dual-Metric + Health Reference Lines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the per-cell mV chart diagnostic — let the user toggle between Surface mV and Peak mV, and on the Peak view draw the baseline + 0.85×/0.70× threshold lines the health verdict already uses.

**Architecture:** A new `EquipmentDao.mvSeriesForCell` does one sample pass and returns both surface and peak series; `surfaceMvSeriesForCell` becomes a thin delegate. `CellMvChart` gains a `SegmentedButton` metric toggle and renders threshold lines (reusing `CellHealth.baselinePeakMv`, already computed by `evaluateHealthForCell`). The Cell detail screen wires both series + the baseline into the chart.

**Tech Stack:** Flutter/Dart, Drift + PowerSync (data), `CustomPainter` (chart), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-03-cell-mv-dual-metric-design.md`

---

## File Structure

- **Modify** `lib/data/db/equipment_dao.dart` — add `MvPoint` typedef + `mvSeriesForCell`; refactor `surfaceMvSeriesForCell` to delegate. (Reuses existing `_computeSurfaceMv`, `_peakMvForSlot`, `_divesInWindow`, `_samplesForDives`.)
- **Modify** `lib/ui/widgets/cell_mv_chart.dart` — new dual-series API, metric toggle, threshold lines, baseline-aware auto-fit range. Full rewrite of the widget (sole caller is the Cell detail screen).
- **Modify** `lib/ui/screens/equipment/cell_detail_screen.dart` — load both series, pass baseline, count by peak series.
- **Add test** `test/data/db/cell_mv_from_powersync_test.dart` — extend with a `mvSeriesForCell` case.
- **Create test** `test/ui/widgets/cell_mv_chart_test.dart` — widget render/toggle/empty-state.

**Note on the record type:** `CellMvChart` keeps its inline record type `({DateTime date, double mv, String diveId})`. Dart records are structural, so values typed as the DAO's `MvPoint` typedef pass into the widget's inline-typed params with no import and no coupling of the UI widget to the data layer.

---

### Task 1: DAO — `mvSeriesForCell` (surface + peak in one pass)

**Files:**
- Modify: `lib/data/db/equipment_dao.dart` (add typedef + method near the existing `surfaceMvSeriesForCell` ~line 380-406)
- Test: `test/data/db/cell_mv_from_powersync_test.dart` (add a second `test(...)`)

- [ ] **Step 1: Write the failing test**

Add this test inside the existing `main()` in `test/data/db/cell_mv_from_powersync_test.dart` (after the existing test, before the closing `}`). It mirrors the existing test's setup:

```dart
  test('mvSeriesForCell returns surface + peak series in one pass', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u');
    final diveDao = DiveDao(db, ps, session);
    final equipDao = EquipmentDao(db, ps, session);

    final data = File('test/fixtures/dives/dive_716.bin').readAsBytesSync();
    final parsed =
        ShearwaterDiveParser(model: ShearwaterModel.petrel3).parse(data);
    final converted = DiveConverter.convert(
      parsed: parsed,
      dcSerial: 0xB89641E4,
      dcDiveNumber: 716,
      dcModel: ShearwaterModel.petrel3,
    );
    await diveDao.importDive(
        converted: converted, rawBlob: data, parserVersion: 1);

    final dive = (await diveDao.getAllDives()).single;
    final installed = DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000)
        .subtract(const Duration(days: 1));
    final cellId = await equipDao.addCell(slot: 1, installedDate: installed);

    final result = await equipDao.mvSeriesForCell(cellId);
    expect(result.surface, isNotEmpty);
    expect(result.peak, isNotEmpty);
    expect(result.peak.first.diveId, dive.id);
    // peak = global max of mv>=5; surface = mean of a subset of those samples,
    // so peak.mv must be >= surface.mv for the same dive.
    expect(result.peak.first.mv,
        greaterThanOrEqualTo(result.surface.first.mv));

    // surfaceMvSeriesForCell now delegates to mvSeriesForCell(...).surface
    final legacy = await equipDao.surfaceMvSeriesForCell(cellId);
    expect(legacy.length, result.surface.length);
    expect(legacy.first.mv, result.surface.first.mv);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/db/cell_mv_from_powersync_test.dart`
Expected: FAIL — `The method 'mvSeriesForCell' isn't defined for the type 'EquipmentDao'`.

- [ ] **Step 3: Add the `MvPoint` typedef and `mvSeriesForCell`, refactor the delegate**

In `lib/data/db/equipment_dao.dart`, add the typedef at top level (just above the `class EquipmentDao` declaration — find the existing `class EquipmentDao`):

```dart
/// One per-dive mV reading for a cell: the dive's start, the mV value, and
/// the dive id (for tap-through to the dive).
typedef MvPoint = ({DateTime date, double mv, String diveId});
```

Then **replace** the existing `surfaceMvSeriesForCell` method (currently ~lines 380-406, the doc comment + method) with the new combined loader plus a thin delegate:

```dart
  /// Per-dive surface-mV AND peak-mV time series for a cell, computed in a
  /// single pass over the cell's dive window so the sample blobs are loaded
  /// once. Surface mV = mean of `cellMv[slot]` over samples with `depthM < 1.0`
  /// AND `cellMv >= 5.0`. Peak mV = max `cellMv[slot]` over samples with
  /// `cellMv >= 5.0`. The two lists may differ in length (a dive can have a
  /// peak reading but no in-record surface samples).
  Future<({List<MvPoint> surface, List<MvPoint> peak})> mvSeriesForCell(
      String cellId) async {
    final empty = (surface: <MvPoint>[], peak: <MvPoint>[]);
    final cell = await getCell(cellId);
    if (cell == null) return empty;
    final mvCol = cell.slot - 1;
    if (mvCol < 0 || mvCol > 2) return empty;

    final dives = await _divesInWindow(cell.installedDate, cell.retiredDate);
    if (dives.isEmpty) return empty;
    final samplesById = await _samplesForDives(dives);

    final surface = <MvPoint>[];
    final peak = <MvPoint>[];
    for (final dive in dives) {
      final sample = samplesById[dive.id];
      if (sample == null) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000);
      final s = _computeSurfaceMv(sample, mvCol);
      if (s != null) surface.add((date: date, mv: s, diveId: dive.id));
      final p = _peakMvForSlot(sample, mvCol);
      if (p != null) peak.add((date: date, mv: p, diveId: dive.id));
    }
    return (surface: surface, peak: peak);
  }

  /// Surface-mV series only. Thin delegate over [mvSeriesForCell] kept for
  /// existing callers.
  Future<List<MvPoint>> surfaceMvSeriesForCell(String cellId) async =>
      (await mvSeriesForCell(cellId)).surface;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/db/cell_mv_from_powersync_test.dart`
Expected: PASS (both the existing test and the new one).

- [ ] **Step 5: Commit**

```bash
git add lib/data/db/equipment_dao.dart test/data/db/cell_mv_from_powersync_test.dart
git commit -m "feat(cell-mv): add EquipmentDao.mvSeriesForCell (surface + peak in one pass)"
```

---

### Task 2: Widget — dual-metric `CellMvChart` with threshold lines

**Files:**
- Modify (full rewrite): `lib/ui/widgets/cell_mv_chart.dart`
- Test (create): `test/ui/widgets/cell_mv_chart_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/ui/widgets/cell_mv_chart_test.dart`:

```dart
import 'package:ccrlogger/ui/widgets/cell_mv_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final surface = <({DateTime date, double mv, String diveId})>[
    (date: DateTime(2025, 5, 1), mv: 12.0, diveId: 'd1'),
    (date: DateTime(2025, 6, 1), mv: 13.0, diveId: 'd2'),
  ];
  final peak = <({DateTime date, double mv, String diveId})>[
    (date: DateTime(2025, 5, 1), mv: 52.0, diveId: 'd1'),
    (date: DateTime(2025, 6, 1), mv: 48.0, diveId: 'd2'),
  ];

  testWidgets('defaults to Peak mV and toggles to Surface without error',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CellMvChart(
          surfaceSeries: surface,
          peakSeries: peak,
          baselinePeakMv: 52.0,
        ),
      ),
    ));

    expect(find.text('Peak mV'), findsOneWidget);
    expect(find.text('Surface mV'), findsOneWidget);

    await tester.tap(find.text('Surface mV'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty state when the active (peak) series is empty',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CellMvChart(
          surfaceSeries: surface,
          peakSeries: const [],
          baselinePeakMv: null,
        ),
      ),
    ));

    expect(find.text('No peak-mV data yet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/cell_mv_chart_test.dart`
Expected: FAIL — the current `CellMvChart` has a `series` param, not `surfaceSeries`/`peakSeries`/`baselinePeakMv`, so it won't compile.

- [ ] **Step 3: Rewrite the widget**

Replace the entire contents of `lib/ui/widgets/cell_mv_chart.dart` with:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which mV metric the chart is showing.
enum CellMvMetric { surface, peak }

class CellMvChart extends StatefulWidget {
  final List<({DateTime date, double mv, String diveId})> surfaceSeries;
  final List<({DateTime date, double mv, String diveId})> peakSeries;

  /// Peak-mV baseline (max peak of the first 5 dives, from CellHealth). When
  /// non-null, the peak view draws baseline / 0.85x (Watch) / 0.70x (Replace)
  /// reference lines. Null (fewer than 5 dives) => no reference lines.
  final double? baselinePeakMv;
  final double height;
  final void Function(String diveId)? onDiveTap;

  const CellMvChart({
    super.key,
    required this.surfaceSeries,
    required this.peakSeries,
    this.baselinePeakMv,
    this.height = 220,
    this.onDiveTap,
  });

  @override
  State<CellMvChart> createState() => _CellMvChartState();
}

class _CellMvChartState extends State<CellMvChart> {
  CellMvMetric _metric = CellMvMetric.peak;
  int? _selectedIndex;

  List<({DateTime date, double mv, String diveId})> get _series =>
      _metric == CellMvMetric.peak ? widget.peakSeries : widget.surfaceSeries;

  // Threshold lines apply to the peak view only, and only with a baseline.
  double? get _baseline =>
      _metric == CellMvMetric.peak ? widget.baselinePeakMv : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<CellMvMetric>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: CellMvMetric.surface, label: Text('Surface mV')),
              ButtonSegment(value: CellMvMetric.peak, label: Text('Peak mV')),
            ],
            selected: {_metric},
            onSelectionChanged: (s) => setState(() {
              _metric = s.first;
              _selectedIndex = null;
            }),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: _series.isEmpty
              ? Center(
                  child: Text(_metric == CellMvMetric.peak
                      ? 'No peak-mV data yet'
                      : 'No surface-mV data yet'),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final size =
                        Size(constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
                      onTapDown: (details) =>
                          _handleTap(details.localPosition, size),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ChartPainter(
                                _series,
                                theme,
                                _selectedIndex,
                                _baseline,
                              ),
                            ),
                          ),
                          if (_selectedIndex != null)
                            _Tooltip(
                              point: _series[_selectedIndex!],
                              onTap: widget.onDiveTap == null
                                  ? null
                                  : () => widget.onDiveTap!(
                                      _series[_selectedIndex!].diveId),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _handleTap(Offset tap, Size size) {
    final series = _series;
    final layout = _ChartLayout(size, series, _baseline);
    var bestIndex = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < series.length; i++) {
      final p = layout.pointAt(i);
      final dx = p.dx - tap.dx;
      final dy = p.dy - tap.dy;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i;
      }
    }
    // Only select if the tap is within ~32px of the nearest point.
    if (math.sqrt(bestDist) > 32) {
      setState(() => _selectedIndex = null);
      return;
    }
    setState(() => _selectedIndex = bestIndex);
  }
}

/// Geometry helper shared by the painter and the tap handler. The mV axis is
/// padded to a "nice" rounded range; when a [baseline] is present the range is
/// widened to keep the 0.70x..baseline reference lines visible.
class _ChartLayout {
  final Size size;
  final List<({DateTime date, double mv, String diveId})> series;
  final double? baseline;
  late final double minTime;
  late final double maxTime;
  late final double niceMinMv;
  late final double niceMaxMv;
  late final double mvStep;
  late final double timeRange;
  late final double mvRange;

  static const double left = 46.0;
  static const double right = 14.0;
  static const double top = 14.0;
  static const double bottom = 24.0;

  _ChartLayout(this.size, this.series, this.baseline) {
    minTime = series.first.date.millisecondsSinceEpoch.toDouble();
    maxTime = series.last.date.millisecondsSinceEpoch.toDouble();
    final mvs = series.map((p) => p.mv);
    var lo = mvs.reduce(math.min);
    var hi = mvs.reduce(math.max);
    final b = baseline;
    if (b != null && b > 0) {
      lo = math.min(lo, b * 0.70);
      hi = math.max(hi, b);
    }
    final (nMin, nMax, step) = _niceRange(lo, hi);
    niceMinMv = nMin;
    niceMaxMv = nMax;
    mvStep = step;
    timeRange = (maxTime - minTime).clamp(1, double.infinity).toDouble();
    mvRange = (niceMaxMv - niceMinMv).clamp(1.0, double.infinity);
  }

  double get plotW => (size.width - left - right).clamp(1.0, double.infinity);
  double get plotH => (size.height - top - bottom).clamp(1.0, double.infinity);

  double xAt(double timeMillis) =>
      left + ((timeMillis - minTime) / timeRange) * plotW;
  double yAt(double mv) => top + plotH - ((mv - niceMinMv) / mvRange) * plotH;

  Offset pointAt(int i) => Offset(
      xAt(series[i].date.millisecondsSinceEpoch.toDouble()),
      yAt(series[i].mv));
}

/// Round a [lo]-[hi] span out to nice gridline-friendly bounds, returning
/// `(niceMin, niceMax, step)`. A flat span gets a small symmetric band.
(double, double, double) _niceRange(double lo, double hi) {
  if ((hi - lo).abs() < 1e-9) {
    final band = lo.abs() < 1e-9 ? 1.0 : (lo.abs() * 0.1).clamp(0.5, 5.0);
    return (lo - band, lo + band, band);
  }
  final step = _niceStep(hi - lo, 4);
  final niceMin = (lo / step).floorToDouble() * step;
  final niceMax = (hi / step).ceilToDouble() * step;
  return (niceMin, niceMax, step);
}

double _niceStep(double range, int targetTicks) {
  final raw = range / targetTicks;
  if (raw <= 0) return 1;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final scaled = raw / mag;
  double niceScaled;
  if (scaled < 1.5) {
    niceScaled = 1;
  } else if (scaled < 3) {
    niceScaled = 2;
  } else if (scaled < 7) {
    niceScaled = 5;
  } else {
    niceScaled = 10;
  }
  return niceScaled * mag;
}

const _monthAbbr = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatMonthYear(DateTime d) {
  final local = d.toLocal();
  return "${_monthAbbr[local.month]} '${(local.year % 100).toString().padLeft(2, '0')}";
}

class _ChartPainter extends CustomPainter {
  final List<({DateTime date, double mv, String diveId})> series;
  final ThemeData theme;
  final int? selectedIndex;
  final double? baseline;

  _ChartPainter(this.series, this.theme, this.selectedIndex, this.baseline);

  static const _gridColor = Color(0xFF1A2832); // AppColors.wreck.chartGrid
  static const _axisLabel = Color(0xFFA0AEB6); // AppColors.wreck.textSecondary
  static const _watchColor = Color(0xFFF39C12); // AppColors.wreck.statusWarning
  static const _replaceColor = Color(0xFFE74C3C); // AppColors.wreck.statusDanger

  static const _labelStyle = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 9,
    color: _axisLabel,
    height: 1.0,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final layout = _ChartLayout(size, series, baseline);

    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = theme.colorScheme.outline
      ..strokeWidth = 1;

    // ── mV grid + labels ─────────────────────────────────────────────
    final decimals = layout.mvStep >= 1 ? 0 : 1;
    for (var v = layout.niceMinMv;
        v <= layout.niceMaxMv + 1e-6;
        v += layout.mvStep) {
      final y = layout.yAt(v);
      canvas.drawLine(
        Offset(_ChartLayout.left, y),
        Offset(_ChartLayout.left + layout.plotW, y),
        gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(text: v.toStringAsFixed(decimals), style: _labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(_ChartLayout.left - tp.width - 5, y - tp.height / 2));
    }

    // "mV" unit above the top of the axis.
    final unitTp = TextPainter(
      text: const TextSpan(
        text: 'mV',
        style: TextStyle(fontFamily: 'Inter', fontSize: 9, color: _axisLabel),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitTp.paint(canvas,
        Offset(_ChartLayout.left - unitTp.width - 5, _ChartLayout.top - 12));

    // ── Date axis (4 ticks evenly across the time span) ───────────────
    const dateTicks = 3; // 4 labels: i = 0..3
    for (var i = 0; i <= dateTicks; i++) {
      final frac = i / dateTicks;
      final t = layout.minTime + frac * layout.timeRange;
      final x = layout.xAt(t);
      final tp = TextPainter(
        text: TextSpan(
          text: _formatMonthYear(
              DateTime.fromMillisecondsSinceEpoch(t.round())),
          style: _labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      double lx;
      if (i == 0) {
        lx = x;
      } else if (i == dateTicks) {
        lx = x - tp.width;
      } else {
        lx = x - tp.width / 2;
      }
      tp.paint(canvas, Offset(lx, _ChartLayout.top + layout.plotH + 6));
    }

    // ── Threshold reference lines (peak view with a baseline) ─────────
    final b = baseline;
    if (b != null && b > 0) {
      _drawThreshold(canvas, layout, b, _axisLabel, 'base', dashed: false);
      _drawThreshold(canvas, layout, b * 0.85, _watchColor, '0.85x',
          dashed: true);
      _drawThreshold(canvas, layout, b * 0.70, _replaceColor, '0.70x',
          dashed: true);
    }

    // ── Axes ─────────────────────────────────────────────────────────
    canvas.drawLine(
      const Offset(_ChartLayout.left, _ChartLayout.top),
      Offset(_ChartLayout.left, _ChartLayout.top + layout.plotH),
      axisPaint,
    );
    canvas.drawLine(
      Offset(_ChartLayout.left, _ChartLayout.top + layout.plotH),
      Offset(_ChartLayout.left + layout.plotW,
          _ChartLayout.top + layout.plotH),
      axisPaint,
    );

    // ── Trend line + dots ────────────────────────────────────────────
    final linePaint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final dotPaint = Paint()..color = theme.colorScheme.primary;
    final selectedPaint = Paint()..color = theme.colorScheme.error;

    final path = Path()
      ..moveTo(layout.pointAt(0).dx, layout.pointAt(0).dy);
    for (var i = 1; i < series.length; i++) {
      final p = layout.pointAt(i);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < series.length; i++) {
      final p = layout.pointAt(i);
      final isSelected = i == selectedIndex;
      canvas.drawCircle(
        p,
        isSelected ? 5 : 3,
        isSelected ? selectedPaint : dotPaint,
      );
    }
  }

  void _drawThreshold(
    Canvas canvas,
    _ChartLayout layout,
    double mv,
    Color color,
    String label, {
    required bool dashed,
  }) {
    if (mv < layout.niceMinMv || mv > layout.niceMaxMv) return;
    final y = layout.yAt(mv);
    final x0 = _ChartLayout.left;
    final x1 = _ChartLayout.left + layout.plotW;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    if (dashed) {
      _drawDashedLine(canvas, Offset(x0, y), Offset(x1, y), paint,
          dashWidth: 4, gapWidth: 3);
    } else {
      canvas.drawLine(Offset(x0, y), Offset(x1, y), paint);
    }
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
            fontFamily: 'JetBrainsMono', fontSize: 9, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x1 - tp.width - 2, y - tp.height - 1));
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dashWidth,
    required double gapWidth,
  }) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return;
    final ux = dx / dist;
    final uy = dy / dist;
    var travelled = 0.0;
    var drawing = true;
    var cursor = a;
    while (travelled < dist) {
      final step = drawing ? dashWidth : gapWidth;
      final next = Offset(cursor.dx + ux * step, cursor.dy + uy * step);
      if (drawing) canvas.drawLine(cursor, next, paint);
      cursor = next;
      travelled += step;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.series != series ||
      old.theme != theme ||
      old.selectedIndex != selectedIndex ||
      old.baseline != baseline;
}

class _Tooltip extends StatelessWidget {
  final ({DateTime date, double mv, String diveId}) point;
  final VoidCallback? onTap;

  const _Tooltip({required this.point, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = point.date.toLocal().toString().split(' ').first;
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        color: theme.colorScheme.surface,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateStr, style: theme.textTheme.labelMedium),
                Text('${point.mv.toStringAsFixed(1)} mV',
                    style: theme.textTheme.titleMedium),
                if (onTap != null)
                  Text('Open dive →',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/widgets/cell_mv_chart_test.dart`
Expected: PASS (both `testWidgets`).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/cell_mv_chart.dart test/ui/widgets/cell_mv_chart_test.dart
git commit -m "feat(cell-mv): dual-metric chart with peak-view health threshold lines"
```

---

### Task 3: Screen — wire both series + baseline into the chart

**Files:**
- Modify: `lib/ui/screens/equipment/cell_detail_screen.dart` (state field ~37, `_load` ~57-74, build ~234 and ~241-244)

- [ ] **Step 1: Replace the `_series` state field with two fields**

In `_CellDetailScreenState` (around line 37), replace:

```dart
  List<({DateTime date, double mv, String diveId})> _series = const [];
```

with:

```dart
  List<({DateTime date, double mv, String diveId})> _surface = const [];
  List<({DateTime date, double mv, String diveId})> _peak = const [];
```

- [ ] **Step 2: Update `_load` to use `mvSeriesForCell`**

In `_load()` (around lines 60-66), replace:

```dart
    final series = await widget.dao.surfaceMvSeriesForCell(cell.id);
    final health = await widget.dao.evaluateHealthForCell(cell.id);
    if (!mounted) return;
    setState(() {
      _cell = cell;
      _series = series;
      _health = health;
```

with:

```dart
    final mv = await widget.dao.mvSeriesForCell(cell.id);
    final health = await widget.dao.evaluateHealthForCell(cell.id);
    if (!mounted) return;
    setState(() {
      _cell = cell;
      _surface = mv.surface;
      _peak = mv.peak;
      _health = health;
```

- [ ] **Step 3: Update the count line and the chart call**

In `build` (around line 234), replace:

```dart
                Text('Dives with mV data: ${_series.length}'),
```

with:

```dart
                Text('Dives with mV data: ${_peak.length}'),
```

And (around lines 241-244) replace:

```dart
                CellMvChart(
                  series: _series,
                  onDiveTap: _openDive,
                ),
```

with:

```dart
                CellMvChart(
                  surfaceSeries: _surface,
                  peakSeries: _peak,
                  baselinePeakMv: _health?.baselinePeakMv,
                  onDiveTap: _openDive,
                ),
```

- [ ] **Step 4: Verify analysis + full test suite are clean**

Run: `flutter analyze lib/ui/screens/equipment/cell_detail_screen.dart lib/ui/widgets/cell_mv_chart.dart lib/data/db/equipment_dao.dart`
Expected: `No issues found!`

Run: `flutter test`
Expected: All tests pass (the wiring is integration glue; behaviour is covered by the Task 1 DAO test and Task 2 widget test).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/equipment/cell_detail_screen.dart
git commit -m "feat(cell-mv): wire dual-metric series + baseline into Cell detail screen"
```

---

## Self-Review

**Spec coverage:**
- Goal 1 (both metrics, toggleable) → Task 2 `SegmentedButton` + `_metric` state. ✓
- Goal 2 (baseline + 0.85x/0.70x lines on peak view) → Task 2 `_drawThreshold` calls, baseline from `_health?.baselinePeakMv` in Task 3. ✓
- Goal 3 (auto-fit, no zero-based toggle) → Task 2 `_ChartLayout` widens range to include thresholds; no toggle added. ✓
- DAO `mvSeriesForCell` + delegate → Task 1. ✓
- Screen count switches to peak series → Task 3 Step 3. ✓
- Tests (DAO + widget) → Task 1 Step 1, Task 2 Step 1. ✓

**Type consistency:** `mvSeriesForCell` returns `({List<MvPoint> surface, List<MvPoint> peak})`; screen reads `mv.surface`/`mv.peak`; widget params `surfaceSeries`/`peakSeries` use the structurally-identical inline record type. `baselinePeakMv` is `double?` in `CellHealth`, the widget prop, and the painter field. `CellMvMetric` enum used consistently. ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete. ✓
