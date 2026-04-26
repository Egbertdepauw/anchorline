# App Shell + Dark Theme + Dive List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Flutter counter demo with a working dark-themed app showing a dive list with mini-profile sparklines, grouped by month, using data from the Drift database.

**Architecture:** Bottom-nav app shell with 4 tabs (only Dives implemented, others placeholder). `DiveListNotifier` (ChangeNotifier) loads data from `DiveDao`. Sparkline depth data loaded lazily with an in-memory cache. Development seeder populates the database with 8 fixture dives.

**Tech Stack:** Flutter Material 3, Drift (existing), ChangeNotifier, CustomPainter (sparkline), path_provider (DB path).

---

### Important: Drift generates a `Dive` class in `database.g.dart`

The Drift-generated `Dive` (at `lib/data/db/database.g.dart:582`) has raw int fields (`startTime` as unix seconds, `maxDepthMm` as int, `diveMode` as int code). The domain `Dive` class in `lib/data/models/dive.dart` has typed fields (`startTime` as `DateTime`, `maxDepthMeters` as `double`, `diveMode` as `DiveMode` enum). The UI layer works with the Drift row class directly and uses utility functions to convert for display. This avoids an extra mapping layer while keeping things simple.

Throughout this plan, `Dive` refers to the **Drift-generated row class** unless explicitly noted. Import it from `package:ccrlogger/data/db/database.dart`.

---

### Task 1: Utility — dive mode color mapping

**Files:**
- Create: `lib/ui/util/dive_mode_color.dart`
- Test: `test/ui/util/dive_mode_color_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/util/dive_mode_color_test.dart
import 'package:ccrlogger/shearwater/parser/constants.dart';
import 'package:ccrlogger/ui/util/dive_mode_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CC mode returns cyan', () {
    expect(diveModeColor(DiveMode.cc.value), equals(const Color(0xFF4FC3F7)));
  });

  test('OC Tec mode returns orange', () {
    expect(diveModeColor(DiveMode.ocTec.value), equals(const Color(0xFFFF9800)));
  });

  test('SC mode returns purple', () {
    expect(diveModeColor(DiveMode.sc.value), equals(const Color(0xFFAB47BC)));
  });

  test('Gauge mode returns blue-grey', () {
    expect(diveModeColor(DiveMode.gauge.value), equals(const Color(0xFF78909C)));
  });

  test('Freedive mode returns teal', () {
    expect(diveModeColor(DiveMode.freedive.value), equals(const Color(0xFF26A69A)));
  });

  test('CC2 returns same as CC', () {
    expect(diveModeColor(DiveMode.cc2.value), equals(diveModeColor(DiveMode.cc.value)));
  });

  test('diveModeLabel returns correct labels', () {
    expect(diveModeLabel(DiveMode.cc.value), equals('CC'));
    expect(diveModeLabel(DiveMode.ocTec.value), equals('OC'));
    expect(diveModeLabel(DiveMode.sc.value), equals('SC'));
    expect(diveModeLabel(DiveMode.gauge.value), equals('GA'));
    expect(diveModeLabel(DiveMode.freedive.value), equals('FD'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/util/dive_mode_color_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/util/dive_mode_color.dart
import 'package:flutter/material.dart';

import '../../shearwater/parser/constants.dart';

const _ccColor = Color(0xFF4FC3F7);
const _ocColor = Color(0xFFFF9800);
const _scColor = Color(0xFFAB47BC);
const _gaugeColor = Color(0xFF78909C);
const _freediveColor = Color(0xFF26A69A);

Color diveModeColor(int diveModeValue) {
  final mode = DiveMode.fromValue(diveModeValue);
  return switch (mode) {
    DiveMode.cc || DiveMode.cc2 => _ccColor,
    DiveMode.ocTec || DiveMode.ocRec || DiveMode.avelo => _ocColor,
    DiveMode.sc => _scColor,
    DiveMode.gauge || DiveMode.ppo2 => _gaugeColor,
    DiveMode.freedive => _freediveColor,
  };
}

String diveModeLabel(int diveModeValue) {
  final mode = DiveMode.fromValue(diveModeValue);
  return switch (mode) {
    DiveMode.cc || DiveMode.cc2 => 'CC',
    DiveMode.ocTec || DiveMode.ocRec || DiveMode.avelo => 'OC',
    DiveMode.sc => 'SC',
    DiveMode.gauge || DiveMode.ppo2 => 'GA',
    DiveMode.freedive => 'FD',
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/util/dive_mode_color_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/util/dive_mode_color.dart test/ui/util/dive_mode_color_test.dart
git commit -m "feat: add dive mode color and label mapping"
```

---

### Task 2: Utility — display formatting helpers

**Files:**
- Create: `lib/ui/util/format.dart`
- Test: `test/ui/util/format_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/util/format_test.dart
import 'package:ccrlogger/ui/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDepth', () {
    test('formats depth in meters from mm', () {
      expect(formatDepth(28400), equals('28.4m'));
    });

    test('formats shallow depth', () {
      expect(formatDepth(1200), equals('1.2m'));
    });

    test('formats zero depth', () {
      expect(formatDepth(0), equals('0.0m'));
    });
  });

  group('formatDuration', () {
    test('formats minutes only', () {
      expect(formatDuration(3428), equals('57min'));
    });

    test('formats hours and minutes', () {
      expect(formatDuration(7200), equals('2h 0min'));
    });

    test('formats hours and minutes mixed', () {
      expect(formatDuration(5520), equals('1h 32min'));
    });
  });

  group('formatDate', () {
    test('formats unix timestamp to short date', () {
      // 19 Apr 2026 10:38:45 UTC = 1776591525
      expect(formatDateShort(1776591525), equals('19 Apr'));
    });
  });

  group('formatMonthYear', () {
    test('formats unix timestamp to month year', () {
      expect(formatMonthYear(1776591525), equals('April 2026'));
    });
  });

  group('formatSetpoint', () {
    test('formats setpoint from database value', () {
      // Stored in dive's gasMixesJson, but displayed as "SP 1.30"
      expect(formatSetpoint(1.3), equals('SP 1.30'));
    });
  });

  group('formatGf', () {
    test('formats GF low/high', () {
      expect(formatGf(35, 75), equals('GF 35/75'));
    });

    test('returns empty for null values', () {
      expect(formatGf(null, null), equals(''));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/util/format_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/util/format.dart
import 'package:intl/intl.dart';

/// Format depth from millimeters to display string.
String formatDepth(int depthMm) {
  final meters = depthMm / 1000.0;
  return '${meters.toStringAsFixed(1)}m';
}

/// Format duration from seconds to display string.
String formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) {
    return '${hours}h ${minutes}min';
  }
  return '${minutes}min';
}

final _dayMonth = DateFormat('d MMM');
final _monthYear = DateFormat('MMMM yyyy');

/// Format unix timestamp to "19 Apr" style.
String formatDateShort(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  return _dayMonth.format(dt);
}

/// Format unix timestamp to "April 2026" style.
String formatMonthYear(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  return _monthYear.format(dt);
}

/// Format setpoint for display.
String formatSetpoint(double sp) => 'SP ${sp.toStringAsFixed(2)}';

/// Format gradient factors for display.
String formatGf(int? low, int? high) {
  if (low == null || high == null) return '';
  return 'GF $low/$high';
}
```

**Note:** This requires adding the `intl` package. Add to pubspec.yaml:
```yaml
  intl: ^0.19.0
```

- [ ] **Step 4: Add intl dependency and run test**

Run: `flutter pub get && flutter test test/ui/util/format_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/ui/util/format.dart test/ui/util/format_test.dart
git commit -m "feat: add display formatting helpers (depth, duration, date, GF)"
```

---

### Task 3: Sparkline widget

**Files:**
- Create: `lib/ui/widgets/sparkline.dart`
- Test: `test/ui/widgets/sparkline_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/widgets/sparkline_test.dart
import 'dart:typed_data';

import 'package:ccrlogger/ui/widgets/sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DepthSparkline widget', () {
    testWidgets('renders without error', (tester) async {
      final depths = Float32List.fromList([0, 5, 10, 20, 30, 30, 25, 15, 5, 0]);
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 56,
          height: 36,
          child: DepthSparkline(
            depths: depths,
            color: Colors.cyan,
          ),
        ),
      ));

      expect(find.byType(DepthSparkline), findsOneWidget);
      expect(find.byType(CustomPaint), findsOneWidget);
    });

    testWidgets('renders with empty data', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 56,
          height: 36,
          child: DepthSparkline(
            depths: Float32List(0),
            color: Colors.cyan,
          ),
        ),
      ));

      expect(find.byType(DepthSparkline), findsOneWidget);
    });

    testWidgets('renders with single point', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 56,
          height: 36,
          child: DepthSparkline(
            depths: Float32List.fromList([10.0]),
            color: Colors.orange,
          ),
        ),
      ));

      expect(find.byType(DepthSparkline), findsOneWidget);
    });
  });

  group('downsample', () {
    test('returns original if <= maxPoints', () {
      final data = Float32List.fromList([1, 2, 3, 4, 5]);
      final result = downsampleDepth(data, 30);
      expect(result, equals(data));
    });

    test('downsamples large arrays to ~maxPoints', () {
      final data = Float32List(1000);
      for (var i = 0; i < 1000; i++) {
        data[i] = i.toDouble();
      }
      final result = downsampleDepth(data, 30);
      expect(result.length, lessThanOrEqualTo(34)); // some tolerance
      expect(result.length, greaterThanOrEqualTo(28));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/sparkline_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/widgets/sparkline.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Tiny depth profile sparkline rendered with CustomPainter.
///
/// Y-axis is inverted: deeper = lower on screen. No axes or labels.
class DepthSparkline extends StatelessWidget {
  final Float32List depths;
  final Color color;

  const DepthSparkline({
    super.key,
    required this.depths,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(
        depths: downsampleDepth(depths, 30),
        color: color,
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final Float32List depths;
  final Color color;

  _SparklinePainter({required this.depths, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (depths.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    var maxDepth = 0.0;
    for (final d in depths) {
      if (d > maxDepth) maxDepth = d;
    }
    if (maxDepth == 0) return;

    final path = ui.Path();
    final xStep = size.width / (depths.length - 1);
    final padding = 2.0;
    final yScale = (size.height - padding * 2) / maxDepth;

    for (var i = 0; i < depths.length; i++) {
      final x = i * xStep;
      final y = padding + depths[i] * yScale; // deeper = larger y = lower
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.depths != depths || old.color != color;
}

/// Downsample a depth array to at most [maxPoints] by picking every Nth sample.
Float32List downsampleDepth(Float32List data, int maxPoints) {
  if (data.length <= maxPoints) return data;
  final step = data.length / maxPoints;
  final result = Float32List(maxPoints);
  for (var i = 0; i < maxPoints; i++) {
    result[i] = data[(i * step).floor()];
  }
  return result;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/sparkline_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/sparkline.dart test/ui/widgets/sparkline_test.dart
git commit -m "feat: add depth sparkline CustomPainter widget"
```

---

### Task 4: Dark theme

**Files:**
- Create: `lib/ui/theme/app_theme.dart`

- [ ] **Step 1: Create the theme file**

```dart
// lib/ui/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF4FC3F7);
  static const _surfaceColor = Color(0xFF0D1B2A);
  static const _cardColor = Color(0xFF152238);

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
      surface: _surfaceColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _surfaceColor,
      cardColor: _cardColor,
      appBarTheme: AppBarTheme(
        backgroundColor: _surfaceColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _surfaceColor,
        selectedItemColor: _seedColor,
        unselectedItemColor: colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/ui/theme/app_theme.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/ui/theme/app_theme.dart
git commit -m "feat: add Material 3 dark theme (deep navy surface, cyan accent)"
```

---

### Task 5: Sparkline data cache + DiveListNotifier

**Files:**
- Create: `lib/ui/notifiers/dive_list_notifier.dart`
- Test: `test/ui/notifiers/dive_list_notifier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/notifiers/dive_list_notifier_test.dart
import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/notifiers/dive_list_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late DiveListNotifier notifier;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveDao(db);
    notifier = DiveListNotifier(dao);

    // Seed 3 dives
    for (final num in [711, 712, 718]) {
      final data =
          File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
      final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
      final parsed = parser.parse(data);
      final converted = DiveConverter.convert(
        parsed: parsed,
        dcSerial: 0xB89641E4,
        dcDiveNumber: num,
        dcModel: ShearwaterModel.petrel3,
      );
      await dao.importDive(
        converted: converted,
        rawBlob: data,
        parserVersion: 1,
      );
    }
  });

  tearDown(() async {
    notifier.dispose();
    await db.close();
  });

  test('loadDives populates dives list', () async {
    await notifier.loadDives();
    expect(notifier.dives, hasLength(3));
  });

  test('dives are ordered by start time descending', () async {
    await notifier.loadDives();
    for (var i = 1; i < notifier.dives.length; i++) {
      expect(notifier.dives[i].startTime,
          lessThanOrEqualTo(notifier.dives[i - 1].startTime));
    }
  });

  test('groupedByMonth groups dives correctly', () async {
    await notifier.loadDives();
    final groups = notifier.groupedByMonth;
    expect(groups, isNotEmpty);
    // Each key is a "Month Year" string
    for (final key in groups.keys) {
      expect(key, matches(RegExp(r'^[A-Z][a-z]+ \d{4}$')));
    }
  });

  test('getSparklineData returns depth data for a dive', () async {
    await notifier.loadDives();
    final diveId = notifier.dives.first.id;
    final depths = await notifier.getSparklineData(diveId);
    expect(depths, isNotNull);
    expect(depths!.length, greaterThan(0));
  });

  test('getSparklineData caches results', () async {
    await notifier.loadDives();
    final diveId = notifier.dives.first.id;
    final depths1 = await notifier.getSparklineData(diveId);
    final depths2 = await notifier.getSparklineData(diveId);
    expect(identical(depths1, depths2), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/notifiers/dive_list_notifier_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/notifiers/dive_list_notifier.dart
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_dao.dart';
import '../util/format.dart';

class DiveListNotifier extends ChangeNotifier {
  final DiveDao _dao;
  List<Dive> _dives = [];
  bool _loading = false;
  final _sparklineCache = _LruCache<String, Float32List>(50);

  DiveListNotifier(this._dao);

  List<Dive> get dives => _dives;
  bool get loading => _loading;

  /// Dives grouped by month. Keys are "April 2026" style strings.
  /// Preserves insertion order (most recent month first).
  LinkedHashMap<String, List<Dive>> get groupedByMonth {
    final groups = LinkedHashMap<String, List<Dive>>();
    for (final dive in _dives) {
      final key = formatMonthYear(dive.startTime);
      groups.putIfAbsent(key, () => []).add(dive);
    }
    return groups;
  }

  Future<void> loadDives() async {
    _loading = true;
    notifyListeners();
    _dives = await _dao.getAllDives();
    _loading = false;
    notifyListeners();
  }

  /// Get depth data for the sparkline, with LRU caching.
  Future<Float32List?> getSparklineData(String diveId) async {
    final cached = _sparklineCache.get(diveId);
    if (cached != null) return cached;

    final samples = await _dao.getSamples(diveId);
    if (samples == null) return null;

    _sparklineCache.put(diveId, samples.depthMeters);
    return samples.depthMeters;
  }
}

/// Simple LRU cache with a max size.
class _LruCache<K, V> {
  final int _maxSize;
  final _map = LinkedHashMap<K, V>();

  _LruCache(this._maxSize);

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value; // move to end (most recent)
    }
    return value;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > _maxSize) {
      _map.remove(_map.keys.first);
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/notifiers/dive_list_notifier_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/notifiers/dive_list_notifier.dart test/ui/notifiers/dive_list_notifier_test.dart
git commit -m "feat: add DiveListNotifier with month grouping and sparkline cache"
```

---

### Task 6: Dive tile widget

**Files:**
- Create: `lib/ui/widgets/dive_tile.dart`
- Test: `test/ui/widgets/dive_tile_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/widgets/dive_tile_test.dart
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/shearwater/parser/constants.dart';
import 'package:ccrlogger/ui/widgets/dive_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal Dive row for testing. The Drift-generated Dive class requires
// all fields, so we construct one directly.
Dive _makeDive({
  int diveMode = 0, // CC
  int diveNumber = 718,
  int maxDepthMm = 28400,
  int durationSeconds = 3428,
  int? gfLow = 35,
  int? gfHigh = 75,
  int startTime = 1776591525,
}) {
  return Dive(
    id: 'test-dive-id',
    dcSerial: 123,
    dcDiveNumber: diveNumber,
    startTime: startTime,
    endTime: startTime + durationSeconds,
    utcOffsetMinutes: null,
    durationSeconds: durationSeconds,
    maxDepthMm: maxDepthMm,
    diveMode: diveMode,
    decoModel: 0,
    gfLow: gfLow,
    gfHigh: gfHigh,
    atmosphericPressureMbar: 1013,
    waterDensity: 1025,
    logVersion: 14,
    dcModel: 3,
    dcFirmware: null,
    sampleIntervalMs: 10000,
    gasMixesJson: '[{"o2":21,"he":35,"dil":true}]',
    rawBlob: Uint8List(0),
    parserVersion: 1,
    importedAt: 1776591525,
  );
}

void main() {
  testWidgets('DiveTile shows dive number', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiveTile(
          dive: _makeDive(),
          sparklineData: Float32List.fromList([0, 10, 20, 30, 20, 10, 0]),
          onTap: () {},
        ),
      ),
    ));

    expect(find.text('#718'), findsOneWidget);
  });

  testWidgets('DiveTile shows depth', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiveTile(
          dive: _makeDive(),
          sparklineData: Float32List.fromList([0, 10, 20, 30, 20, 10, 0]),
          onTap: () {},
        ),
      ),
    ));

    expect(find.textContaining('28.4m'), findsOneWidget);
  });

  testWidgets('DiveTile shows mode label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiveTile(
          dive: _makeDive(diveMode: DiveMode.ocTec.value),
          sparklineData: Float32List.fromList([0, 10, 20, 10, 0]),
          onTap: () {},
        ),
      ),
    ));

    expect(find.text('OC'), findsOneWidget);
  });

  testWidgets('DiveTile renders without sparkline data', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiveTile(
          dive: _makeDive(),
          sparklineData: null,
          onTap: () {},
        ),
      ),
    ));

    expect(find.byType(DiveTile), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/widgets/dive_tile_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/widgets/dive_tile.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../util/dive_mode_color.dart';
import '../util/format.dart';
import 'sparkline.dart';

class DiveTile extends StatelessWidget {
  final Dive dive;
  final Float32List? sparklineData;
  final VoidCallback onTap;

  const DiveTile({
    super.key,
    required this.dive,
    required this.sparklineData,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final modeColor = diveModeColor(dive.diveMode);
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: modeColor, width: 3),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Sparkline
            SizedBox(
              width: 56,
              height: 36,
              child: sparklineData != null && sparklineData!.isNotEmpty
                  ? DepthSparkline(depths: sparklineData!, color: modeColor)
                  : Container(
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: mode label, dive number, date
                  Row(
                    children: [
                      Text(
                        diveModeLabel(dive.diveMode),
                        style: TextStyle(
                          color: modeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '#${dive.dcDiveNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatDateShort(dive.startTime),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Middle row: stats
                  Text(
                    _buildStatsLine(),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildStatsLine() {
    final parts = <String>[
      formatDepth(dive.maxDepthMm),
      formatDuration(dive.durationSeconds),
    ];

    final gf = formatGf(dive.gfLow, dive.gfHigh);
    if (gf.isNotEmpty) parts.add(gf);

    return parts.join(' · ');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/widgets/dive_tile_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/dive_tile.dart test/ui/widgets/dive_tile_test.dart
git commit -m "feat: add DiveTile widget with sparkline, mode color, stats"
```

---

### Task 7: Placeholder screen + app shell + dive list screen

**Files:**
- Create: `lib/ui/screens/placeholder_screen.dart`
- Create: `lib/ui/screens/dive_list_screen.dart`
- Create: `lib/ui/app_shell.dart`

- [ ] **Step 1: Create placeholder screen**

```dart
// lib/ui/screens/placeholder_screen.dart
import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Create dive list screen**

```dart
// lib/ui/screens/dive_list_screen.dart
import 'package:flutter/material.dart';

import '../notifiers/dive_list_notifier.dart';
import '../util/format.dart';
import '../widgets/dive_tile.dart';

class DiveListScreen extends StatefulWidget {
  final DiveListNotifier notifier;

  const DiveListScreen({super.key, required this.notifier});

  @override
  State<DiveListScreen> createState() => _DiveListScreenState();
}

class _DiveListScreenState extends State<DiveListScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
    widget.notifier.loadDives();
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final notifier = widget.notifier;

    if (notifier.loading && notifier.dives.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifier.dives.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.scuba_diving, size: 48,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No dives yet',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          ],
        ),
      );
    }

    final groups = notifier.groupedByMonth;

    return RefreshIndicator(
      onRefresh: notifier.loadDives,
      child: CustomScrollView(
        slivers: [
          for (final entry in groups.entries) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final dive = entry.value[index];
                  return _DiveTileWithSparkline(
                    dive: dive,
                    notifier: notifier,
                  );
                },
                childCount: entry.value.length,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiveTileWithSparkline extends StatefulWidget {
  final dynamic dive; // Drift Dive row
  final DiveListNotifier notifier;

  const _DiveTileWithSparkline({required this.dive, required this.notifier});

  @override
  State<_DiveTileWithSparkline> createState() => _DiveTileWithSparklineState();
}

class _DiveTileWithSparklineState extends State<_DiveTileWithSparkline> {
  @override
  void initState() {
    super.initState();
    _loadSparkline();
  }

  Future<void> _loadSparkline() async {
    await widget.notifier.getSparklineData(widget.dive.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: widget.notifier.getSparklineData(widget.dive.id),
      builder: (context, snapshot) {
        return DiveTile(
          dive: widget.dive,
          sparklineData: snapshot.data,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Dive #${widget.dive.dcDiveNumber} detail (coming soon)')),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 3: Create app shell**

```dart
// lib/ui/app_shell.dart
import 'package:flutter/material.dart';

import '../data/db/dive_dao.dart';
import 'notifiers/dive_list_notifier.dart';
import 'screens/dive_list_screen.dart';
import 'screens/placeholder_screen.dart';

class AppShell extends StatefulWidget {
  final DiveDao diveDao;

  const AppShell({super.key, required this.diveDao});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final DiveListNotifier _diveListNotifier;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _diveListNotifier = DiveListNotifier(widget.diveDao);
    _screens = [
      DiveListScreen(notifier: _diveListNotifier),
      const PlaceholderScreen(title: 'Import from dive computer', icon: Icons.bluetooth),
      const PlaceholderScreen(title: 'Equipment', icon: Icons.build_outlined),
      const PlaceholderScreen(title: 'Settings', icon: Icons.settings_outlined),
    ];
  }

  @override
  void dispose() {
    _diveListNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CCRLog')),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.scuba_diving), label: 'Dives'),
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: 'Import'),
          BottomNavigationBarItem(icon: Icon(Icons.build_outlined), label: 'Equipment'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Verify all three files compile**

Run: `flutter analyze lib/ui/`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/placeholder_screen.dart lib/ui/screens/dive_list_screen.dart lib/ui/app_shell.dart
git commit -m "feat: add app shell with bottom nav, dive list screen, placeholders"
```

---

### Task 8: Development fixture seeder

**Files:**
- Create: `lib/dev/fixture_seeder.dart`

- [ ] **Step 1: Create the seeder**

```dart
// lib/dev/fixture_seeder.dart
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/db/database.dart';
import '../data/db/dive_dao.dart';
import '../shearwater/parser/dive_converter.dart';
import '../shearwater/parser/dive_parser.dart';
import '../shearwater/parser/hardware.dart';

/// Seed the database with fixture dives for development.
///
/// Only runs in debug mode and only if the database is empty.
Future<void> seedFixtures(AppDatabase db) async {
  if (!kDebugMode) return;

  final dao = DiveDao(db);
  final dives = await dao.getAllDives();
  if (dives.isNotEmpty) return; // Already seeded

  const diveNumbers = [711, 712, 713, 714, 715, 716, 717, 718];
  final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);

  for (final num in diveNumbers) {
    final file = File('test/fixtures/dives/dive_$num.bin');
    if (!file.existsSync()) continue;

    final rawBlob = file.readAsBytesSync();
    final parsed = parser.parse(rawBlob);
    final converted = DiveConverter.convert(
      parsed: parsed,
      dcSerial: 0xB89641E4,
      dcDiveNumber: num,
      dcModel: ShearwaterModel.petrel3,
    );

    await dao.importDive(
      converted: converted,
      rawBlob: rawBlob,
      parserVersion: 1,
    );
  }

  debugPrint('Seeded ${diveNumbers.length} fixture dives');
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/dev/fixture_seeder.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/dev/fixture_seeder.dart
git commit -m "feat: add debug fixture seeder for development"
```

---

### Task 9: Wire up main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Replace main.dart**

Replace the entire contents of `lib/main.dart` with:

```dart
// lib/main.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/db/database.dart';
import 'data/db/dive_dao.dart';
import 'dev/fixture_seeder.dart';
import 'ui/app_shell.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbDir = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(dbDir.path, 'ccrlogger.sqlite'));
  final db = AppDatabase(NativeDatabase(dbFile));

  await seedFixtures(db);

  runApp(CCRLogApp(db: db));
}

class CCRLogApp extends StatelessWidget {
  final AppDatabase db;

  const CCRLogApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCRLog',
      theme: AppTheme.dark(),
      home: AppShell(diveDao: DiveDao(db)),
      debugShowCheckedModeBanner: false,
    );
  }
}
```

- [ ] **Step 2: Run analysis**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 3: Run all existing tests**

Run: `flutter test`
Expected: All 142+ tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: wire up app shell with dark theme, database, fixture seeder"
```

---

### Task 10: Launch, verify, and push

- [ ] **Step 1: Launch the app on a simulator or device**

Run: `flutter run` (select an available device/simulator)

Verify:
- App launches with dark navy theme
- Bottom nav has 4 tabs: Dives, Import, Equipment, Settings
- Dives tab shows 8 fixture dives grouped by month
- Each tile has a depth sparkline in cyan (CC mode)
- Tiles show dive number, depth, duration, GF
- Tapping a tile shows a snackbar ("coming soon")
- Import/Equipment/Settings tabs show placeholder content
- Pull-to-refresh works on the dive list

- [ ] **Step 2: Run all tests and analyzer**

```bash
flutter test
flutter analyze
```

Expected: All tests pass, no analyzer issues

- [ ] **Step 3: Final commit and push**

```bash
git add -A
git status  # verify nothing unexpected
git commit -m "chore: final Step 6.1 cleanup"
git push origin main
```
