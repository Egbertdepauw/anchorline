# Dive Detail Screen + Profile Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the dive detail screen with a multi-trace profile chart, trace toggle chips, long-press crosshair, stats row, and gas mixes section — navigable from the dive list.

**Architecture:** `DiveDetailNotifier` (ChangeNotifier) loads a Drift `Dive` row + `SampleSet`. The profile chart is a `CustomPainter` that renders multiple traces from the SampleSet's Float32List columns. Trace visibility is managed as a `Set<TraceType>`. The crosshair is a `GestureDetector` overlay that snaps to sample indices.

**Tech Stack:** Flutter CustomPainter, ChangeNotifier, existing Drift database + DiveDao + SampleSet.

---

### Key types referenced in this plan

**Drift `Dive` row** (from `package:ccrlogger/data/db/database.dart`): `id` (String), `dcSerial` (int), `dcDiveNumber` (int), `startTime` (int, unix seconds), `endTime` (int), `durationSeconds` (int), `maxDepthMm` (int), `diveMode` (int code), `gfLow` (int?), `gfHigh` (int?), `gasMixesJson` (String), `dcModel` (int), `sampleIntervalMs` (int).

**`SampleSet`** (from `package:ccrlogger/data/models/sample_set.dart`): `sampleCount` (int), `depthMeters` (Float32List), `ppo2Bar` (Float32List), `setpointBar` (Float32List), `cellMv0/1/2` (Float32List), `decoStopDepthMeters` (Float32List), `temperatureCelsius` (Float32List), `cns` (Float32List), `sampleIntervalMs` (int).

**`DiveDao`** (from `package:ccrlogger/data/db/dive_dao.dart`): `getSamples(String diveId)` → `Future<SampleSet?>`.

**`DiveMode`** (from `package:ccrlogger/shearwater/parser/constants.dart`): enum with `.isCcr` getter.

**Existing utilities**: `diveModeColor(int)`, `diveModeLabel(int)`, `formatDepth(int depthMm)`, `formatDuration(int seconds)`, `formatDateShort(int unixSeconds)`, `formatGf(int?, int?)` — all in `lib/ui/util/`.

**`ShearwaterModel`** (from `package:ccrlogger/shearwater/parser/hardware.dart`): enum with `.name` for display.

---

### Task 1: TraceType enum and DiveDetailNotifier

**Files:**
- Create: `lib/ui/notifiers/dive_detail_notifier.dart`
- Test: `test/ui/notifiers/dive_detail_notifier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/notifiers/dive_detail_notifier_test.dart
import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/shearwater/parser/constants.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/notifiers/dive_detail_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late Dive diveRow;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveDao(db);

    final data = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    final parsed = parser.parse(data);
    final converted = DiveConverter.convert(
      parsed: parsed,
      dcSerial: 0xB89641E4,
      dcDiveNumber: 718,
      dcModel: ShearwaterModel.petrel3,
    );
    await dao.importDive(converted: converted, rawBlob: data, parserVersion: 1);
    final dives = await dao.getAllDives();
    diveRow = dives.first;
  });

  tearDown(() async {
    await db.close();
  });

  test('loadSamples populates samples', () async {
    final notifier = DiveDetailNotifier(dive: diveRow, dao: dao);
    await notifier.loadSamples();
    expect(notifier.samples, isNotNull);
    expect(notifier.samples!.sampleCount, greaterThan(0));
    notifier.dispose();
  });

  test('CCR dive defaults to ppo2 + setpoint + deco visible', () async {
    final notifier = DiveDetailNotifier(dive: diveRow, dao: dao);
    // Dive 718 is CCR (diveMode == 0 == DiveMode.cc)
    expect(notifier.visibleTraces.contains(TraceType.ppo2), isTrue);
    expect(notifier.visibleTraces.contains(TraceType.setpoint), isTrue);
    expect(notifier.visibleTraces.contains(TraceType.deco), isTrue);
    expect(notifier.visibleTraces.contains(TraceType.cells), isFalse);
    expect(notifier.visibleTraces.contains(TraceType.tanks), isFalse);
    notifier.dispose();
  });

  test('toggleTrace flips visibility and notifies', () async {
    final notifier = DiveDetailNotifier(dive: diveRow, dao: dao);
    var notified = false;
    notifier.addListener(() => notified = true);

    expect(notifier.visibleTraces.contains(TraceType.cells), isFalse);
    notifier.toggleTrace(TraceType.cells);
    expect(notifier.visibleTraces.contains(TraceType.cells), isTrue);
    expect(notified, isTrue);

    notified = false;
    notifier.toggleTrace(TraceType.cells);
    expect(notifier.visibleTraces.contains(TraceType.cells), isFalse);
    expect(notified, isTrue);
    notifier.dispose();
  });

  test('setCrosshairIndex notifies', () async {
    final notifier = DiveDetailNotifier(dive: diveRow, dao: dao);
    await notifier.loadSamples();

    var notified = false;
    notifier.addListener(() => notified = true);

    notifier.setCrosshairIndex(42);
    expect(notifier.crosshairIndex, equals(42));
    expect(notified, isTrue);

    notified = false;
    notifier.clearCrosshair();
    expect(notifier.crosshairIndex, isNull);
    expect(notified, isTrue);
    notifier.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/notifiers/dive_detail_notifier_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/notifiers/dive_detail_notifier.dart
import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_dao.dart';
import '../../data/models/sample_set.dart';
import '../../shearwater/parser/constants.dart';

enum TraceType { ppo2, setpoint, deco, cells, tanks }

class DiveDetailNotifier extends ChangeNotifier {
  final Dive dive;
  final DiveDao _dao;

  SampleSet? _samples;
  final Set<TraceType> _visibleTraces;
  int? _crosshairIndex;
  bool _loading = false;

  SampleSet? get samples => _samples;
  Set<TraceType> get visibleTraces => _visibleTraces;
  int? get crosshairIndex => _crosshairIndex;
  bool get loading => _loading;

  DiveDetailNotifier({required this.dive, required DiveDao dao})
      : _dao = dao,
        _visibleTraces = _defaultTraces(dive.diveMode);

  static Set<TraceType> _defaultTraces(int diveModeValue) {
    final mode = DiveMode.fromValue(diveModeValue);
    if (mode.isCcr) {
      return {TraceType.ppo2, TraceType.setpoint, TraceType.deco};
    }
    return {TraceType.deco};
  }

  Future<void> loadSamples() async {
    _loading = true;
    notifyListeners();
    _samples = await _dao.getSamples(dive.id);
    _loading = false;
    notifyListeners();
  }

  void toggleTrace(TraceType trace) {
    if (_visibleTraces.contains(trace)) {
      _visibleTraces.remove(trace);
    } else {
      _visibleTraces.add(trace);
    }
    notifyListeners();
  }

  void setCrosshairIndex(int index) {
    _crosshairIndex = index;
    notifyListeners();
  }

  void clearCrosshair() {
    _crosshairIndex = null;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/notifiers/dive_detail_notifier_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/notifiers/dive_detail_notifier.dart test/ui/notifiers/dive_detail_notifier_test.dart
git commit -m "feat: add DiveDetailNotifier with trace visibility and crosshair state"
```

---

### Task 2: Profile chart CustomPainter

**Files:**
- Create: `lib/ui/widgets/profile_chart.dart`
- Test: `test/ui/widgets/profile_chart_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/widgets/profile_chart_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/notifiers/dive_detail_notifier.dart';
import 'package:ccrlogger/ui/widgets/profile_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSet _loadSamples() {
  final data = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
  final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
  final parsed = parser.parse(data);
  final converted = DiveConverter.convert(
    parsed: parsed,
    dcSerial: 0xB89641E4,
    dcDiveNumber: 718,
    dcModel: ShearwaterModel.petrel3,
  );
  return converted.samples;
}

void main() {
  testWidgets('ProfileChart renders with real dive data', (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 250,
          child: ProfileChart(
            samples: samples,
            visibleTraces: {TraceType.ppo2, TraceType.setpoint, TraceType.deco},
            crosshairIndex: null,
          ),
        ),
      ),
    ));

    expect(find.byType(ProfileChart), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('ProfileChart renders with crosshair active', (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 250,
          child: ProfileChart(
            samples: samples,
            visibleTraces: {TraceType.ppo2},
            crosshairIndex: 50,
          ),
        ),
      ),
    ));

    expect(find.byType(ProfileChart), findsOneWidget);
  });

  testWidgets('ProfileChart renders with cells enabled', (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 250,
          child: ProfileChart(
            samples: samples,
            visibleTraces: {TraceType.ppo2, TraceType.cells},
            crosshairIndex: null,
          ),
        ),
      ),
    ));

    expect(find.byType(ProfileChart), findsOneWidget);
  });

  testWidgets('ProfileChart renders with empty traces', (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 250,
          child: ProfileChart(
            samples: samples,
            visibleTraces: {},
            crosshairIndex: null,
          ),
        ),
      ),
    ));

    expect(find.byType(ProfileChart), findsOneWidget);
  });

  test('ProfileChartPainter shouldRepaint on data changes', () {
    final samples = _loadSamples();
    final traces1 = <TraceType>{TraceType.ppo2};
    final traces2 = <TraceType>{TraceType.ppo2, TraceType.cells};

    final p1 = ProfileChartPainter(samples: samples, visibleTraces: traces1, crosshairIndex: null);
    final p2 = ProfileChartPainter(samples: samples, visibleTraces: traces2, crosshairIndex: null);
    final p3 = ProfileChartPainter(samples: samples, visibleTraces: traces1, crosshairIndex: 10);

    expect(p1.shouldRepaint(p2), isTrue); // traces changed
    expect(p1.shouldRepaint(p3), isTrue); // crosshair changed
    expect(p1.shouldRepaint(p1), isFalse); // same
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/profile_chart_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write implementation**

```dart
// lib/ui/widgets/profile_chart.dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models/sample_set.dart';
import '../notifiers/dive_detail_notifier.dart';

/// Padding around the chart area for axis labels.
const _leftPad = 40.0;
const _rightPad = 44.0;
const _topPad = 8.0;
const _bottomPad = 24.0;

/// Trace colors matching the design spec.
const _depthColor = Color(0xFF4FC3F7);
const _ppo2Color = Color(0xFF66BB6A);
const _setpointColor = Color(0xFFFF9800);
const _decoColor = Color(0xFFFF9800);
const _cell0Color = Color(0xFFEF5350);
const _cell1Color = Color(0xFFFFEE58);
const _cell2Color = Color(0xFF42A5F5);
const _crosshairColor = Color(0x80FFFFFF);

/// The PPO2 Y-axis maximum in bar.
const _ppo2Max = 2.0;

class ProfileChart extends StatelessWidget {
  final SampleSet samples;
  final Set<TraceType> visibleTraces;
  final int? crosshairIndex;

  const ProfileChart({
    super.key,
    required this.samples,
    required this.visibleTraces,
    required this.crosshairIndex,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ProfileChartPainter(
        samples: samples,
        visibleTraces: visibleTraces,
        crosshairIndex: crosshairIndex,
      ),
      size: Size.infinite,
    );
  }
}

class ProfileChartPainter extends CustomPainter {
  final SampleSet samples;
  final Set<TraceType> visibleTraces;
  final int? crosshairIndex;

  ProfileChartPainter({
    required this.samples,
    required this.visibleTraces,
    required this.crosshairIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.sampleCount < 2) return;

    final chartLeft = _leftPad;
    final chartRight = size.width - _rightPad;
    final chartTop = _topPad;
    final chartBottom = size.height - _bottomPad;
    final chartWidth = chartRight - chartLeft;
    final chartHeight = chartBottom - chartTop;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    // Clip to chart area for traces.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(chartLeft, chartTop, chartRight, chartBottom));

    final n = samples.sampleCount;
    final depths = samples.depthMeters;

    // Compute max depth for Y scaling.
    var maxDepth = 0.0;
    for (var i = 0; i < n; i++) {
      if (depths[i] > maxDepth) maxDepth = depths[i];
    }
    // Round up to nearest 5m for clean grid.
    maxDepth = (maxDepth / 5).ceil() * 5.0;
    if (maxDepth < 5) maxDepth = 5;

    double xForIndex(int i) => chartLeft + (i / (n - 1)) * chartWidth;
    double yForDepth(double d) => chartTop + (d / maxDepth) * chartHeight;
    double yForPpo2(double p) => chartBottom - (p / _ppo2Max) * chartHeight;

    // ── Grid lines ──
    _drawGrid(canvas, chartLeft, chartRight, chartTop, chartBottom, maxDepth);

    // ── Deco ceiling ──
    if (visibleTraces.contains(TraceType.deco)) {
      _drawDecoCeiling(canvas, n, xForIndex, yForDepth, chartTop);
    }

    // ── Depth trace (always on) ──
    _drawDepthTrace(canvas, n, depths, xForIndex, yForDepth, chartTop);

    // ── PPO2 trace ──
    if (visibleTraces.contains(TraceType.ppo2)) {
      _drawTrace(canvas, n, samples.ppo2Bar, xForIndex, yForPpo2, _ppo2Color, 1.5);
    }

    // ── Setpoint trace ──
    if (visibleTraces.contains(TraceType.setpoint)) {
      _drawTrace(canvas, n, samples.setpointBar, xForIndex, yForPpo2, _setpointColor, 1.0, dashed: true);
    }

    // ── Cell mV traces ──
    if (visibleTraces.contains(TraceType.cells)) {
      _drawTrace(canvas, n, samples.cellMv0, xForIndex, yForPpo2, _cell0Color, 1.0);
      _drawTrace(canvas, n, samples.cellMv1, xForIndex, yForPpo2, _cell1Color, 1.0);
      _drawTrace(canvas, n, samples.cellMv2, xForIndex, yForPpo2, _cell2Color, 1.0);
    }

    // ── Crosshair ──
    if (crosshairIndex != null && crosshairIndex! >= 0 && crosshairIndex! < n) {
      final x = xForIndex(crosshairIndex!);
      canvas.drawLine(
        Offset(x, chartTop),
        Offset(x, chartBottom),
        Paint()..color = _crosshairColor..strokeWidth = 1.0,
      );
    }

    canvas.restore();

    // ── Axis labels (outside clip) ──
    _drawDepthAxisLabels(canvas, chartLeft, chartTop, chartBottom, maxDepth);
    _drawTimeAxisLabels(canvas, chartLeft, chartRight, chartBottom, n);

    if (visibleTraces.contains(TraceType.ppo2) ||
        visibleTraces.contains(TraceType.cells) ||
        visibleTraces.contains(TraceType.setpoint)) {
      _drawPpo2AxisLabels(canvas, chartRight, chartTop, chartBottom);
    }
  }

  void _drawGrid(Canvas canvas, double left, double right, double top, double bottom, double maxDepth) {
    final paint = Paint()..color = const Color(0xFF1A2A40)..strokeWidth = 0.5;
    final step = maxDepth <= 20 ? 5.0 : 10.0;
    for (var d = 0.0; d <= maxDepth; d += step) {
      final y = top + (d / maxDepth) * (bottom - top);
      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    }
  }

  void _drawDepthTrace(Canvas canvas, int n, dynamic depths, double Function(int) xFor, double Function(double) yFor, double chartTop) {
    // Filled area
    final fillPath = ui.Path();
    fillPath.moveTo(xFor(0), chartTop);
    for (var i = 0; i < n; i++) {
      fillPath.lineTo(xFor(i), yFor(depths[i]));
    }
    fillPath.lineTo(xFor(n - 1), chartTop);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = _depthColor.withValues(alpha: 0.1)..style = PaintingStyle.fill);

    // Stroke
    final strokePath = ui.Path();
    for (var i = 0; i < n; i++) {
      final x = xFor(i);
      final y = yFor(depths[i]);
      if (i == 0) { strokePath.moveTo(x, y); } else { strokePath.lineTo(x, y); }
    }
    canvas.drawPath(strokePath, Paint()..color = _depthColor..strokeWidth = 2.0..style = PaintingStyle.stroke..isAntiAlias = true);
  }

  void _drawDecoCeiling(Canvas canvas, int n, double Function(int) xFor, double Function(double) yFor, double chartTop) {
    final deco = samples.decoStopDepthMeters;
    final path = ui.Path();
    var hasData = false;
    for (var i = 0; i < n; i++) {
      if (deco[i] > 0) {
        if (!hasData) {
          path.moveTo(xFor(i), chartTop);
          hasData = true;
        }
        path.lineTo(xFor(i), yFor(deco[i]));
      } else if (hasData) {
        path.lineTo(xFor(i), chartTop);
        hasData = false;
      }
    }
    if (hasData) {
      path.lineTo(xFor(n - 1), chartTop);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = _decoColor.withValues(alpha: 0.15)..style = PaintingStyle.fill);
  }

  void _drawTrace(Canvas canvas, int n, dynamic data, double Function(int) xFor, double Function(double) yFor, Color color, double strokeWidth, {bool dashed = false}) {
    final path = ui.Path();
    for (var i = 0; i < n; i++) {
      final x = xFor(i);
      final y = yFor(data[i].toDouble());
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    final paint = Paint()..color = color..strokeWidth = strokeWidth..style = PaintingStyle.stroke..isAntiAlias = true;
    if (dashed) {
      // Simple dash: draw path as dashed using PathMetrics
      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        var distance = 0.0;
        while (distance < metric.length) {
          final end = math.min(distance + 6, metric.length);
          final segment = metric.extractPath(distance, end);
          canvas.drawPath(segment, paint);
          distance += 10; // 6px dash + 4px gap
        }
      }
    } else {
      canvas.drawPath(path, paint);
    }
  }

  void _drawDepthAxisLabels(Canvas canvas, double left, double top, double bottom, double maxDepth) {
    final step = maxDepth <= 20 ? 5.0 : 10.0;
    for (var d = 0.0; d <= maxDepth; d += step) {
      final y = top + (d / maxDepth) * (bottom - top);
      _drawText(canvas, '${d.toInt()}m', Offset(left - 4, y - 5), TextAlign.right, const Color(0xFF556677), 9);
    }
  }

  void _drawTimeAxisLabels(Canvas canvas, double left, double right, double bottom, int n) {
    final totalMinutes = (n * samples.sampleIntervalMs) / 60000.0;
    final step = totalMinutes <= 30 ? 5 : totalMinutes <= 60 ? 10 : 15;
    final chartWidth = right - left;
    for (var m = 0; m <= totalMinutes; m += step) {
      final x = left + (m / totalMinutes) * chartWidth;
      _drawText(canvas, '$m', Offset(x, bottom + 4), TextAlign.center, const Color(0xFF556677), 9);
    }
  }

  void _drawPpo2AxisLabels(Canvas canvas, double right, double top, double bottom) {
    for (var p = 0.0; p <= _ppo2Max; p += 0.5) {
      final y = bottom - (p / _ppo2Max) * (bottom - top);
      _drawText(canvas, p.toStringAsFixed(1), Offset(right + 4, y - 5), TextAlign.left, const Color(0xFF556677), 9);
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextAlign align, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.right ? offset.dx - tp.width : align == TextAlign.center ? offset.dx - tp.width / 2 : offset.dx;
    tp.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(ProfileChartPainter old) =>
      old.samples != samples ||
      !_setsEqual(old.visibleTraces, visibleTraces) ||
      old.crosshairIndex != crosshairIndex;

  static bool _setsEqual<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/profile_chart_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/profile_chart.dart test/ui/widgets/profile_chart_test.dart
git commit -m "feat: add ProfileChart multi-trace CustomPainter"
```

---

### Task 3: Trace toggle chips widget

**Files:**
- Create: `lib/ui/widgets/trace_toggle.dart`
- Test: `test/ui/widgets/trace_toggle_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/widgets/trace_toggle_test.dart
import 'package:ccrlogger/ui/notifiers/dive_detail_notifier.dart';
import 'package:ccrlogger/ui/widgets/trace_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows all 5 trace chips', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TraceToggleChips(
          visibleTraces: {TraceType.ppo2, TraceType.setpoint, TraceType.deco},
          onToggle: (_) {},
        ),
      ),
    ));

    expect(find.text('PPO2'), findsOneWidget);
    expect(find.text('Setpoint'), findsOneWidget);
    expect(find.text('Cells'), findsOneWidget);
    expect(find.text('Deco'), findsOneWidget);
    expect(find.text('Tanks'), findsOneWidget);
  });

  testWidgets('tapping a chip calls onToggle', (tester) async {
    TraceType? toggled;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TraceToggleChips(
          visibleTraces: {TraceType.ppo2},
          onToggle: (t) => toggled = t,
        ),
      ),
    ));

    await tester.tap(find.text('Cells'));
    expect(toggled, equals(TraceType.cells));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/trace_toggle_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write implementation**

```dart
// lib/ui/widgets/trace_toggle.dart
import 'package:flutter/material.dart';

import '../notifiers/dive_detail_notifier.dart';

const _traceChipData = <TraceType, ({String label, Color color})>{
  TraceType.ppo2: (label: 'PPO2', color: Color(0xFF66BB6A)),
  TraceType.setpoint: (label: 'Setpoint', color: Color(0xFFFF9800)),
  TraceType.cells: (label: 'Cells', color: Color(0xFFEF5350)),
  TraceType.deco: (label: 'Deco', color: Color(0xFFFF9800)),
  TraceType.tanks: (label: 'Tanks', color: Color(0xFF90A4AE)),
};

class TraceToggleChips extends StatelessWidget {
  final Set<TraceType> visibleTraces;
  final ValueChanged<TraceType> onToggle;

  const TraceToggleChips({
    super.key,
    required this.visibleTraces,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final entry in _traceChipData.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(entry.value.label),
                selected: visibleTraces.contains(entry.key),
                onSelected: (_) => onToggle(entry.key),
                selectedColor: entry.value.color.withValues(alpha: 0.3),
                checkmarkColor: entry.value.color,
                side: BorderSide(
                  color: visibleTraces.contains(entry.key)
                      ? entry.value.color
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                ),
                labelStyle: TextStyle(
                  color: visibleTraces.contains(entry.key)
                      ? entry.value.color
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/trace_toggle_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/trace_toggle.dart test/ui/widgets/trace_toggle_test.dart
git commit -m "feat: add trace toggle filter chips for profile chart"
```

---

### Task 4: Crosshair overlay widget

**Files:**
- Create: `lib/ui/widgets/crosshair_overlay.dart`
- Test: `test/ui/widgets/crosshair_overlay_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/widgets/crosshair_overlay_test.dart
import 'package:ccrlogger/ui/widgets/crosshair_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders child widget', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CrosshairOverlay(
          sampleCount: 100,
          chartLeftPad: 40,
          chartRightPad: 44,
          onIndexChanged: (_) {},
          onRelease: () {},
          child: const SizedBox(width: 360, height: 250),
        ),
      ),
    ));

    expect(find.byType(CrosshairOverlay), findsOneWidget);
    expect(find.byType(GestureDetector), findsWidgets);
  });

  testWidgets('long press triggers callback', (tester) async {
    int? reportedIndex;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 250,
          child: CrosshairOverlay(
            sampleCount: 100,
            chartLeftPad: 40,
            chartRightPad: 44,
            onIndexChanged: (i) => reportedIndex = i,
            onRelease: () {},
            child: Container(color: Colors.black),
          ),
        ),
      ),
    ));

    // Long press in the middle of the chart area.
    final center = tester.getCenter(find.byType(CrosshairOverlay));
    await tester.longPress(center);
    await tester.pump();

    expect(reportedIndex, isNotNull);
    expect(reportedIndex, greaterThanOrEqualTo(0));
    expect(reportedIndex, lessThan(100));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/crosshair_overlay_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write implementation**

```dart
// lib/ui/widgets/crosshair_overlay.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CrosshairOverlay extends StatelessWidget {
  final int sampleCount;
  final double chartLeftPad;
  final double chartRightPad;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onRelease;
  final Widget child;

  const CrosshairOverlay({
    super.key,
    required this.sampleCount,
    required this.chartLeftPad,
    required this.chartRightPad,
    required this.onIndexChanged,
    required this.onRelease,
    required this.child,
  });

  int _indexFromX(double x, double totalWidth) {
    final chartWidth = totalWidth - chartLeftPad - chartRightPad;
    if (chartWidth <= 0 || sampleCount < 2) return 0;
    final fraction = ((x - chartLeftPad) / chartWidth).clamp(0.0, 1.0);
    return (fraction * (sampleCount - 1)).round().clamp(0, sampleCount - 1);
  }

  void _onUpdate(Offset position, double width) {
    final index = _indexFromX(position.dx, width);
    HapticFeedback.selectionClick();
    onIndexChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onLongPressStart: (details) => _onUpdate(details.localPosition, constraints.maxWidth),
          onLongPressMoveUpdate: (details) => _onUpdate(details.localPosition, constraints.maxWidth),
          onLongPressEnd: (_) => onRelease(),
          child: child,
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/crosshair_overlay_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/crosshair_overlay.dart test/ui/widgets/crosshair_overlay_test.dart
git commit -m "feat: add CrosshairOverlay with long-press gesture and haptic snap"
```

---

### Task 5: Crosshair tooltip widget

**Files:**
- Create: `lib/ui/widgets/crosshair_tooltip.dart`

- [ ] **Step 1: Create the tooltip widget**

```dart
// lib/ui/widgets/crosshair_tooltip.dart
import 'package:flutter/material.dart';

import '../../data/models/sample_set.dart';
import '../notifiers/dive_detail_notifier.dart';

class CrosshairTooltip extends StatelessWidget {
  final SampleSet samples;
  final int sampleIndex;
  final Set<TraceType> visibleTraces;
  final double chartX;
  final double chartWidth;

  const CrosshairTooltip({
    super.key,
    required this.samples,
    required this.sampleIndex,
    required this.visibleTraces,
    required this.chartX,
    required this.chartWidth,
  });

  @override
  Widget build(BuildContext context) {
    final i = sampleIndex.clamp(0, samples.sampleCount - 1);
    final timeMs = (i + 1) * samples.sampleIntervalMs;
    final minutes = timeMs ~/ 60000;
    final seconds = (timeMs % 60000) ~/ 1000;

    final rows = <_TooltipRow>[
      _TooltipRow('Time', '$minutes:${seconds.toString().padLeft(2, '0')}'),
      _TooltipRow('Depth', '${samples.depthMeters[i].toStringAsFixed(1)}m'),
    ];

    if (visibleTraces.contains(TraceType.ppo2)) {
      rows.add(_TooltipRow('PPO2', '${samples.ppo2Bar[i].toStringAsFixed(2)} bar'));
    }
    if (visibleTraces.contains(TraceType.setpoint)) {
      rows.add(_TooltipRow('SP', '${samples.setpointBar[i].toStringAsFixed(2)} bar'));
    }
    if (visibleTraces.contains(TraceType.cells)) {
      rows.add(_TooltipRow('C1', '${samples.cellMv0[i].toStringAsFixed(2)}'));
      rows.add(_TooltipRow('C2', '${samples.cellMv1[i].toStringAsFixed(2)}'));
      rows.add(_TooltipRow('C3', '${samples.cellMv2[i].toStringAsFixed(2)}'));
    }
    rows.add(_TooltipRow('Temp', '${samples.temperatureCelsius[i].toStringAsFixed(1)}°C'));

    // Position: flip sides when near right edge.
    final onRightSide = chartX > chartWidth / 2;
    final alignment = onRightSide ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xE0152238),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(row.label,
                          style: const TextStyle(color: Color(0xFF778899), fontSize: 10)),
                    ),
                    Text(row.value,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TooltipRow {
  final String label;
  final String value;
  _TooltipRow(this.label, this.value);
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/ui/widgets/crosshair_tooltip.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/ui/widgets/crosshair_tooltip.dart
git commit -m "feat: add CrosshairTooltip for sample inspection"
```

---

### Task 6: Dive detail screen

**Files:**
- Create: `lib/ui/screens/dive_detail_screen.dart`

This screen wires together the header, profile chart, toggle chips, crosshair overlay, tooltip, stats row, and gas mixes section.

- [ ] **Step 1: Add format helper for gas mix display**

Add to `lib/ui/util/format.dart`:

```dart
/// Format a gas mix for display: "21/35" for trimix, "EAN32" for nitrox, "Air" for air.
String formatGasMix(int o2, int he) {
  if (he > 0) return '$o2/$he';
  if (o2 == 21) return 'Air';
  if (o2 == 100) return 'O2';
  return 'EAN$o2';
}

/// Format a date+time from unix seconds: "19 Apr 2026 · 10:38"
String formatDateTime(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  final date = _dayMonth.format(dt);
  final year = dt.year;
  final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  return '$date $year · $time';
}
```

- [ ] **Step 2: Create the dive detail screen**

```dart
// lib/ui/screens/dive_detail_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_dao.dart';
import '../../data/models/dive.dart';
import '../../shearwater/parser/hardware.dart';
import '../notifiers/dive_detail_notifier.dart';
import '../util/dive_mode_color.dart';
import '../util/format.dart';
import '../widgets/crosshair_overlay.dart';
import '../widgets/crosshair_tooltip.dart';
import '../widgets/profile_chart.dart';
import '../widgets/trace_toggle.dart';

class DiveDetailScreen extends StatefulWidget {
  final Dive dive;
  final DiveDao dao;

  const DiveDetailScreen({super.key, required this.dive, required this.dao});

  @override
  State<DiveDetailScreen> createState() => _DiveDetailScreenState();
}

class _DiveDetailScreenState extends State<DiveDetailScreen> {
  late final DiveDetailNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = DiveDetailNotifier(dive: widget.dive, dao: widget.dao);
    _notifier.addListener(_onChanged);
    _notifier.loadSamples();
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    _notifier.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final dive = widget.dive;
    final modeColor = diveModeColor(dive.diveMode);
    final theme = Theme.of(context);
    final modelName = ShearwaterModel.values.length > dive.dcModel
        ? ShearwaterModel.values[dive.dcModel].name
        : 'Unknown';

    return Scaffold(
      appBar: AppBar(
        title: Text('Dive #${dive.dcDiveNumber}'),
      ),
      body: _notifier.loading && _notifier.samples == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──
                  Container(
                    color: const Color(0xFF152238),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(diveModeLabel(dive.diveMode),
                                      style: TextStyle(color: modeColor, fontSize: 11, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 6),
                                  Text('#${dive.dcDiveNumber}',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Text(modelName,
                                      style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(formatDateTime(dive.startTime),
                                  style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatDepth(dive.maxDepthMm),
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: modeColor)),
                            Text('${formatDuration(dive.durationSeconds)} ${formatGf(dive.gfLow, dive.gfHigh)}',
                                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Profile Chart ──
                  if (_notifier.samples != null) ...[
                    SizedBox(
                      height: 250,
                      child: CrosshairOverlay(
                        sampleCount: _notifier.samples!.sampleCount,
                        chartLeftPad: 40,
                        chartRightPad: 44,
                        onIndexChanged: _notifier.setCrosshairIndex,
                        onRelease: _notifier.clearCrosshair,
                        child: Stack(
                          children: [
                            ProfileChart(
                              samples: _notifier.samples!,
                              visibleTraces: _notifier.visibleTraces,
                              crosshairIndex: _notifier.crosshairIndex,
                            ),
                            if (_notifier.crosshairIndex != null)
                              CrosshairTooltip(
                                samples: _notifier.samples!,
                                sampleIndex: _notifier.crosshairIndex!,
                                visibleTraces: _notifier.visibleTraces,
                                chartX: 40 + (_notifier.crosshairIndex! / (_notifier.samples!.sampleCount - 1)) * 276,
                                chartWidth: 360,
                              ),
                          ],
                        ),
                      ),
                    ),

                    // ── Toggle chips ──
                    TraceToggleChips(
                      visibleTraces: _notifier.visibleTraces,
                      onToggle: _notifier.toggleTrace,
                    ),

                    // ── Stats row ──
                    _buildStatsRow(theme),

                    // ── Gas mixes ──
                    _buildGasMixes(theme),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatsRow(ThemeData theme) {
    final samples = _notifier.samples!;
    final n = samples.sampleCount;

    // Avg PPO2
    var ppo2Sum = 0.0;
    for (var i = 0; i < n; i++) { ppo2Sum += samples.ppo2Bar[i]; }
    final avgPpo2 = n > 0 ? ppo2Sum / n : 0.0;

    // Max CNS
    var maxCns = 0.0;
    for (var i = 0; i < n; i++) { if (samples.cns[i] > maxCns) maxCns = samples.cns[i]; }

    // Min temp
    var minTemp = double.infinity;
    for (var i = 0; i < n; i++) { if (samples.temperatureCelsius[i] < minTemp) minTemp = samples.temperatureCelsius[i]; }

    // Primary gas
    final gasMixes = _parseGasMixes(widget.dive.gasMixesJson);
    final gasLabel = gasMixes.isNotEmpty
        ? formatGasMix(gasMixes[0]['o2'] as int, gasMixes[0]['he'] as int)
        : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _statCell('AVG PPO2', avgPpo2.toStringAsFixed(2), theme),
          _statCell('CNS', '${(maxCns * 100).toInt()}%', theme),
          _statCell('TEMP', '${minTemp.isFinite ? minTemp.toStringAsFixed(0) : '—'}°C', theme),
          _statCell('GAS', gasLabel, theme),
        ],
      ),
    );
  }

  Widget _statCell(String label, String value, ThemeData theme) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  Widget _buildGasMixes(ThemeData theme) {
    final gasMixes = _parseGasMixes(widget.dive.gasMixesJson);
    if (gasMixes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gas Mixes',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 8),
          for (final mix in gasMixes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (mix['dil'] as bool) ? const Color(0xFF4FC3F7) : const Color(0xFFFF9800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 32,
                    child: Text(
                      (mix['dil'] as bool) ? 'DIL' : 'GAS',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    ),
                  ),
                  Text(
                    formatGasMix(mix['o2'] as int, mix['he'] as int),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _parseGasMixes(String json) {
    try {
      final list = jsonDecode(json) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/ui/screens/dive_detail_screen.dart`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
git add lib/ui/util/format.dart lib/ui/screens/dive_detail_screen.dart
git commit -m "feat: add dive detail screen with header, chart, stats, gas mixes"
```

---

### Task 7: Wire navigation from dive list to detail

**Files:**
- Modify: `lib/ui/screens/dive_list_screen.dart`
- Modify: `lib/ui/app_shell.dart`

- [ ] **Step 1: Update AppShell to pass DiveDao to DiveListScreen**

In `lib/ui/app_shell.dart`, the `DiveListScreen` needs access to `DiveDao` so it can pass it to the detail screen. Modify the `DiveListScreen` constructor call to also pass the dao:

Change `DiveListScreen(notifier: _diveListNotifier)` to `DiveListScreen(notifier: _diveListNotifier, diveDao: widget.diveDao)`.

Then update `DiveListScreen` to accept and store `diveDao`.

- [ ] **Step 2: Update DiveListScreen to accept DiveDao and navigate**

In `lib/ui/screens/dive_list_screen.dart`:

1. Add `final DiveDao diveDao;` field to `DiveListScreen`
2. Update constructor to require it
3. In `_DiveTileWithSparkline`, replace the snackbar `onTap` with navigation:

```dart
onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DiveDetailScreen(dive: dive, dao: notifier_dao),
    ),
  );
},
```

The `_DiveTileWithSparkline` needs access to the `DiveDao`. Pass it from the `DiveListScreen`. The notifier already stores a `DiveDao` but it's private. The simplest approach: pass `diveDao` from the screen to the tile widget.

- [ ] **Step 3: Verify it compiles and existing tests pass**

Run: `flutter analyze && flutter test`
Expected: No issues, all tests pass (the dive list test doesn't exercise navigation, and widget tests for DiveTile don't depend on the list screen constructor)

- [ ] **Step 4: Commit**

```bash
git add lib/ui/app_shell.dart lib/ui/screens/dive_list_screen.dart
git commit -m "feat: wire dive list → detail navigation with DiveDao passthrough"
```

---

### Task 8: Final verification and push

- [ ] **Step 1: Run all tests**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 3: Build to verify compilation**

Run: `flutter build macos` (or `flutter build apk` depending on platform)
Expected: Build succeeds

- [ ] **Step 4: Push**

```bash
git push origin main
```
