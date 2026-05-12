# Dive Detail Polish + Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tighten the Dive Detail layout (inline rating + 4-column stats), swap the graph toggle for a segmented horizontal bar, and persist both graph toggle preferences and map layer style across sessions.

**Architecture:** Seven tasks ordered to keep the build green at every commit. Tasks 1-2 swap the toggle widget (enum relocation first, then widget). Task 3 extends `SettingsNotifier` with two new persisted preferences. Task 4 rewires the dive detail to read from `SettingsNotifier` and drops local trace ownership from `DiveDetailNotifier`. Task 5 wires the map-style preference into `SitesMapScreen` + `SiteMapView` + `AppShell`. Tasks 6-7 ship the inline rating + 4-column stats polish.

**Tech Stack:** Flutter, flutter_test, shared_preferences, ChangeNotifier

**Spec:** [docs/superpowers/specs/2026-05-12-dive-detail-polish-and-persistence-design.md](../specs/2026-05-12-dive-detail-polish-and-persistence-design.md)

---

## Task 1: Relocate the `TraceType` enum to its new home (no behavior change)

This is a mechanical refactor that creates the destination file with just the enum, lets every existing caller keep working, and clears the path for Task 2's widget swap.

**Files:**
- Create: `lib/ui/widgets/trace_segmented_bar.dart`
- Modify: `lib/ui/notifiers/dive_detail_notifier.dart` (remove enum at line 14, add import)
- Modify (import line only): `lib/ui/screens/dive_detail_screen.dart`, `lib/ui/widgets/trace_toggle.dart`, `lib/ui/widgets/profile_chart.dart`, `lib/ui/widgets/crosshair_tooltip.dart`, `test/ui/notifiers/dive_detail_notifier_test.dart`, `test/ui/widgets/profile_chart_test.dart`, `test/ui/widgets/trace_toggle_test.dart`, `test/ui/widgets/crosshair_overlay_test.dart`

- [ ] **Step 1: Create the new file holding only the enum**

Create `lib/ui/widgets/trace_segmented_bar.dart` with:

```dart
/// Segmented bar that toggles which traces draw on the profile chart.
library;

/// The set of data traces that can be toggled on/off in the profile chart.
enum TraceType { ppo2, setpoint, deco, cells, tanks, gasChanges }
```

The widget body lands in Task 2.

- [ ] **Step 2: Remove the enum from `dive_detail_notifier.dart`**

Open `lib/ui/notifiers/dive_detail_notifier.dart`. Delete the enum declaration at line 13-14:

```dart
/// The set of data traces that can be toggled on/off in the profile chart.
enum TraceType { ppo2, setpoint, deco, cells, tanks, gasChanges }
```

Add a new import line so the rest of the file (which uses `TraceType` in `_visibleTraces`, `_defaultTraces`, etc.) still resolves:

```dart
import '../widgets/trace_segmented_bar.dart' show TraceType;
```

Place this import alphabetically among the other relative imports.

- [ ] **Step 3: Update every other caller's import**

Each of these files currently relies on `TraceType` being exported from `dive_detail_notifier.dart`. Some import it transitively, some directly. Audit each and ensure they have a direct import of either `'../widgets/trace_segmented_bar.dart' show TraceType` (for files in `lib/`) or `'package:ccrlogger/ui/widgets/trace_segmented_bar.dart' show TraceType` (for tests). Concretely:

- `lib/ui/screens/dive_detail_screen.dart` — already imports `'../notifiers/dive_detail_notifier.dart'`; that file no longer exports `TraceType`. Add a direct import.
- `lib/ui/widgets/trace_toggle.dart` — uses `TraceType` in `_traceChipData`. Add a direct import (or change the existing one).
- `lib/ui/widgets/profile_chart.dart` — uses `TraceType` in its API. Add direct import.
- `lib/ui/widgets/crosshair_tooltip.dart` — same.
- `test/ui/notifiers/dive_detail_notifier_test.dart` — uses `TraceType` in test assertions.
- `test/ui/widgets/profile_chart_test.dart` — same.
- `test/ui/widgets/trace_toggle_test.dart` — same.
- `test/ui/widgets/crosshair_overlay_test.dart` — same.

If a file accidentally re-exports `TraceType` (none should), leave the re-export removed.

- [ ] **Step 4: Run verification**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: All tests pass with no behavior change.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/widgets/trace_segmented_bar.dart \
        lib/ui/notifiers/dive_detail_notifier.dart \
        lib/ui/screens/dive_detail_screen.dart \
        lib/ui/widgets/trace_toggle.dart \
        lib/ui/widgets/profile_chart.dart \
        lib/ui/widgets/crosshair_tooltip.dart \
        test/ui/notifiers/dive_detail_notifier_test.dart \
        test/ui/widgets/profile_chart_test.dart \
        test/ui/widgets/trace_toggle_test.dart \
        test/ui/widgets/crosshair_overlay_test.dart
git commit -m "$(cat <<'EOF'
refactor(ui): relocate TraceType enum to trace_segmented_bar.dart

Pure move — the enum now lives next to the widget that will own its
rendering (lands in Task 2). DiveDetailNotifier and all other consumers
import it from the new location. No behaviour change.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Replace `TraceToggleChips` with `TraceSegmentedBar`

TDD: write the failing widget tests first, then build the widget, then swap the call site, then delete the old widget file.

**Files:**
- Modify: `lib/ui/widgets/trace_segmented_bar.dart` (add the widget body to the enum-only file from Task 1)
- Create: `test/ui/widgets/trace_segmented_bar_test.dart`
- Delete: `lib/ui/widgets/trace_toggle.dart`
- Delete: `test/ui/widgets/trace_toggle_test.dart`
- Modify: `lib/ui/screens/dive_detail_screen.dart` (swap `TraceToggleChips` → `TraceSegmentedBar` at line ~470, update import)

- [ ] **Step 1: Write the failing widget tests**

Create `test/ui/widgets/trace_segmented_bar_test.dart` with:

```dart
import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  testWidgets('TraceSegmentedBar renders six segments with their labels',
      (tester) async {
    await tester.pumpWidget(_wrap(TraceSegmentedBar(
      visibleTraces: const {TraceType.ppo2, TraceType.deco},
      onToggle: (_) {},
    )));
    expect(find.text('PPO2'), findsOneWidget);
    expect(find.text('Setpoint'), findsOneWidget);
    expect(find.text('Cells'), findsOneWidget);
    expect(find.text('Deco'), findsOneWidget);
    expect(find.text('Tanks'), findsOneWidget);
    expect(find.text('Gas'), findsOneWidget);
  });

  testWidgets('tapping an unselected segment calls onToggle with its TraceType',
      (tester) async {
    TraceType? toggled;
    await tester.pumpWidget(_wrap(TraceSegmentedBar(
      visibleTraces: const {TraceType.ppo2},
      onToggle: (t) => toggled = t,
    )));
    await tester.tap(find.text('Cells'));
    expect(toggled, TraceType.cells);
  });

  testWidgets('tapping a selected segment calls onToggle with its TraceType',
      (tester) async {
    TraceType? toggled;
    await tester.pumpWidget(_wrap(TraceSegmentedBar(
      visibleTraces: const {TraceType.ppo2},
      onToggle: (t) => toggled = t,
    )));
    await tester.tap(find.text('PPO2'));
    expect(toggled, TraceType.ppo2);
  });

  testWidgets('TraceSegmentedBar wraps its segments in a horizontal SingleChildScrollView',
      (tester) async {
    await tester.pumpWidget(_wrap(TraceSegmentedBar(
      visibleTraces: const {},
      onToggle: (_) {},
    )));
    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(TraceSegmentedBar),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/widgets/trace_segmented_bar_test.dart`
Expected: FAIL — compile error `The class 'TraceSegmentedBar' isn't defined`.

- [ ] **Step 3: Implement `TraceSegmentedBar`**

Open `lib/ui/widgets/trace_segmented_bar.dart` (currently just the enum from Task 1). Replace its contents with:

```dart
/// Segmented bar that toggles which traces draw on the profile chart.
library;

import 'package:flutter/material.dart';

import '../components/status_dot.dart';
import '../theme/tokens.dart';

/// The set of data traces that can be toggled on/off in the profile chart.
enum TraceType { ppo2, setpoint, deco, cells, tanks, gasChanges }

const _segmentData = <TraceType, ({String label, Color color})>{
  TraceType.ppo2: (label: 'PPO2', color: Color(0xFFFFCC66)),
  TraceType.setpoint: (label: 'Setpoint', color: Color(0xFFA0AEB6)),
  TraceType.cells: (label: 'Cells', color: Color(0xFF4ADE80)),
  TraceType.deco: (label: 'Deco', color: Color(0xFFF39C12)),
  TraceType.tanks: (label: 'Tanks', color: Color(0xFF60A5FA)),
  TraceType.gasChanges: (label: 'Gas', color: Color(0xFF60A5FA)),
};

/// Connected segmented control of [TraceType] toggles. Six segments share
/// a single rounded outline with 1-px dividers; selected segments tint
/// up. On narrow screens the bar overflows right and scrolls
/// horizontally.
class TraceSegmentedBar extends StatelessWidget {
  final Set<TraceType> visibleTraces;
  final ValueChanged<TraceType> onToggle;

  const TraceSegmentedBar({
    super.key,
    required this.visibleTraces,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: Radii.chipBr,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in _segmentData.entries) ...[
              _Segment(
                label: entry.value.label,
                dotColor: entry.value.color,
                selected: visibleTraces.contains(entry.key),
                onTap: () => onToggle(entry.key),
                scheme: scheme,
              ),
              if (entry.key != _segmentData.keys.last)
                Container(width: 1, color: scheme.outline),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.dotColor,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  final String label;
  final Color dotColor;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? scheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm + 2, vertical: Spacing.xs + 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(
              color: selected ? dotColor : dotColor.withValues(alpha: 0.4),
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: selected ? scheme.onSurface : scheme.outlineVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the new widget tests**

Run: `flutter test test/ui/widgets/trace_segmented_bar_test.dart`
Expected: PASS — all four tests green.

- [ ] **Step 5: Swap the call site in `DiveDetailScreen`**

Open `lib/ui/screens/dive_detail_screen.dart`. Change the import at line 39:

```dart
// From:
import '../widgets/trace_toggle.dart';
// To:
import '../widgets/trace_segmented_bar.dart';
```

Find the `TraceToggleChips(` usage around line 470 and replace with:

```dart
TraceSegmentedBar(
    visibleTraces: _notifier.visibleTraces,
    onToggle: _notifier.toggleTrace),
```

(Same arguments — the widget interface is identical to the old `TraceToggleChips`. We rewire the data source to `SettingsNotifier` in Task 4.)

- [ ] **Step 6: Delete the retired widget and its test file**

```bash
rm lib/ui/widgets/trace_toggle.dart test/ui/widgets/trace_toggle_test.dart
```

- [ ] **Step 7: Run verification**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes (the new widget tests + all existing tests).

- [ ] **Step 8: Commit**

```bash
git add lib/ui/widgets/trace_segmented_bar.dart \
        lib/ui/screens/dive_detail_screen.dart \
        test/ui/widgets/trace_segmented_bar_test.dart
git add -u lib/ui/widgets/trace_toggle.dart test/ui/widgets/trace_toggle_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): segmented bar replaces trace toggle chip wrap

Per item 10 of the Track 4 spec. TraceSegmentedBar is a single
horizontally-scrollable bar of six connected segments — one signal for
selection (tinted background), with the trace-colour dot still leading
each label for chart correlation. Retires lib/ui/widgets/trace_toggle.dart
and its test file. Behaviour identical to the old chips for now; the
data source moves from DiveDetailNotifier to SettingsNotifier in Task 4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Extend `SettingsNotifier` with the two new persisted preferences

TDD: write failing notifier tests first, then implement the extensions.

**Files:**
- Modify: `lib/ui/notifiers/settings_notifier.dart`
- Create: `test/ui/notifiers/settings_notifier_test.dart`

- [ ] **Step 1: Write the failing notifier tests**

Create `test/ui/notifiers/settings_notifier_test.dart` with:

```dart
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/widgets/map_tile_sources.dart' show MapLayerStyle;
import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart' show TraceType;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('visibleTraces', () {
    test('defaults to {ppo2, setpoint, deco, gasChanges} when prefs empty',
        () async {
      final n = SettingsNotifier();
      await n.load();
      expect(n.visibleTraces, {
        TraceType.ppo2,
        TraceType.setpoint,
        TraceType.deco,
        TraceType.gasChanges,
      });
    });

    test('toggleTrace flips membership and notifies', () async {
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.toggleTrace(TraceType.cells);
      expect(n.visibleTraces.contains(TraceType.cells), isTrue);
      expect(notifyCount, 1);
      await n.toggleTrace(TraceType.cells);
      expect(n.visibleTraces.contains(TraceType.cells), isFalse);
      expect(notifyCount, 2);
    });

    test('toggleTrace persists across reload', () async {
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.toggleTrace(TraceType.cells); // add
      await n1.toggleTrace(TraceType.setpoint); // remove (was in defaults)
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.visibleTraces.contains(TraceType.cells), isTrue);
      expect(n2.visibleTraces.contains(TraceType.setpoint), isFalse);
    });
  });

  group('mapLayerStyle', () {
    test('defaults to MapLayerStyle.normal when prefs empty', () async {
      final n = SettingsNotifier();
      await n.load();
      expect(n.mapLayerStyle, MapLayerStyle.normal);
    });

    test('setMapLayerStyle persists across reload', () async {
      final n1 = SettingsNotifier();
      await n1.load();
      await n1.setMapLayerStyle(MapLayerStyle.satellite);
      final n2 = SettingsNotifier();
      await n2.load();
      expect(n2.mapLayerStyle, MapLayerStyle.satellite);
    });

    test('setMapLayerStyle no-ops when style unchanged', () async {
      final n = SettingsNotifier();
      await n.load();
      var notifyCount = 0;
      n.addListener(() => notifyCount++);
      await n.setMapLayerStyle(MapLayerStyle.normal); // already normal
      expect(notifyCount, 0);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart`
Expected: FAIL with compile errors — `visibleTraces`, `toggleTrace`, `mapLayerStyle`, `setMapLayerStyle` are not defined on `SettingsNotifier`.

- [ ] **Step 3: Extend `SettingsNotifier`**

Replace the contents of `lib/ui/notifiers/settings_notifier.dart` with:

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/map_tile_sources.dart' show MapLayerStyle;
import '../widgets/trace_segmented_bar.dart' show TraceType;

class SettingsNotifier extends ChangeNotifier {
  static const _kSpeedColored = 'use_speed_colored_graph';
  static const _kVisibleTraces = 'visible_traces';
  static const _kMapLayerStyle = 'map_layer_style';

  static const _defaultVisibleTraces = <TraceType>{
    TraceType.ppo2,
    TraceType.setpoint,
    TraceType.deco,
    TraceType.gasChanges,
  };

  bool _useSpeedColoredGraph = true;
  Set<TraceType> _visibleTraces = {..._defaultVisibleTraces};
  MapLayerStyle _mapLayerStyle = MapLayerStyle.normal;

  bool get useSpeedColoredGraph => _useSpeedColoredGraph;
  Set<TraceType> get visibleTraces => Set.unmodifiable(_visibleTraces);
  MapLayerStyle get mapLayerStyle => _mapLayerStyle;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _useSpeedColoredGraph = prefs.getBool(_kSpeedColored) ?? true;

    final tracesList = prefs.getStringList(_kVisibleTraces);
    if (tracesList != null) {
      _visibleTraces = tracesList
          .map((n) =>
              TraceType.values.where((t) => t.name == n).firstOrNull)
          .whereType<TraceType>()
          .toSet();
    }

    final styleName = prefs.getString(_kMapLayerStyle);
    if (styleName != null) {
      _mapLayerStyle = MapLayerStyle.values
              .where((s) => s.name == styleName)
              .firstOrNull ??
          MapLayerStyle.normal;
    }

    notifyListeners();
  }

  Future<void> setUseSpeedColoredGraph(bool v) async {
    if (_useSpeedColoredGraph == v) return;
    _useSpeedColoredGraph = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSpeedColored, v);
  }

  Future<void> toggleTrace(TraceType t) async {
    if (_visibleTraces.contains(t)) {
      _visibleTraces.remove(t);
    } else {
      _visibleTraces.add(t);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kVisibleTraces,
      _visibleTraces.map((t) => t.name).toList(),
    );
  }

  Future<void> setMapLayerStyle(MapLayerStyle s) async {
    if (_mapLayerStyle == s) return;
    _mapLayerStyle = s;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMapLayerStyle, s.name);
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/ui/notifiers/settings_notifier_test.dart`
Expected: PASS — all six tests green.

- [ ] **Step 5: Run full suite + analyze**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/notifiers/settings_notifier.dart \
        test/ui/notifiers/settings_notifier_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): persist visibleTraces + mapLayerStyle in SettingsNotifier

Two new SharedPreferences-backed fields: visibleTraces (Set<TraceType>,
key=visible_traces, stored as List<String> of enum names) defaults to
{ppo2, setpoint, deco, gasChanges}; mapLayerStyle (MapLayerStyle, key=
map_layer_style, stored as enum name) defaults to normal. Pure addition
to SettingsNotifier — no consumers wired yet; that lands in Tasks 4-5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Rewire dive detail to read trace toggles from `SettingsNotifier`

Drop `DiveDetailNotifier`'s ownership of `_visibleTraces`. `DiveDetailScreen` reads from `SettingsNotifier` instead, and rebuilds its toggle-bar + chart subtree on notifier changes via `ListenableBuilder`.

**Files:**
- Modify: `lib/ui/notifiers/dive_detail_notifier.dart` (remove `_visibleTraces` field, `_defaultTraces`, `toggleTrace`, `visibleTraces` getter)
- Modify: `test/ui/notifiers/dive_detail_notifier_test.dart` (delete tests for the dropped state)
- Modify: `lib/ui/screens/dive_detail_screen.dart` (make `settingsNotifier` required; rewire trace + chart reads; wrap subtree in `ListenableBuilder`)
- Modify: `lib/ui/screens/dive_detail_pager.dart` (drop nullable `?` from the field if its constructor allows; if the pager already requires it, no change)
- Modify: `lib/ui/screens/dive_list_screen.dart` (same — drop nullable if applicable)
- Modify (only if test breaks): any widget test that passes `null` for `settingsNotifier` — provide `SettingsNotifier()` instead.

- [ ] **Step 1: Identify which tests pass null for `settingsNotifier`**

Run:
```bash
grep -rn "settingsNotifier:" test/ 2>/dev/null
grep -rn "settingsNotifier" test/ 2>/dev/null
```

Note any test that constructs `DiveDetailScreen` or `DiveDetailPager` without providing a real `SettingsNotifier`. Those tests need a constructor update (Step 5).

- [ ] **Step 2: Strip `_visibleTraces` ownership from `DiveDetailNotifier`**

Open `lib/ui/notifiers/dive_detail_notifier.dart`. Apply these deletions:

**2a.** Remove the field declaration (currently line 30):
```dart
final Set<TraceType> _visibleTraces;
```

**2b.** Remove the `visibleTraces` getter (currently lines 44-45):
```dart
/// Currently visible trace types.
Set<TraceType> get visibleTraces => _visibleTraces;
```

**2c.** Remove the constructor initializer that builds `_visibleTraces` from `_defaultTraces`. The constructor currently looks like:
```dart
DiveDetailNotifier({
  required this.dive,
  required DiveDao dao,
  EquipmentDao? equipmentDao,
})  : _dao = dao,
      _equipmentDao = equipmentDao,
      _visibleTraces = _defaultTraces(dive.diveMode);
```
becomes:
```dart
DiveDetailNotifier({
  required this.dive,
  required DiveDao dao,
  EquipmentDao? equipmentDao,
})  : _dao = dao,
      _equipmentDao = equipmentDao;
```

**2d.** Remove the static `_defaultTraces` helper (currently lines 61-72):
```dart
static Set<TraceType> _defaultTraces(int diveModeValue) {
  final mode = DiveMode.fromValue(diveModeValue);
  if (mode.isCcr) {
    return {
      TraceType.ppo2,
      TraceType.setpoint,
      TraceType.deco,
      TraceType.gasChanges,
    };
  }
  return {TraceType.deco, TraceType.gasChanges};
}
```

**2e.** Remove the `toggleTrace` method (currently lines 105-113):
```dart
/// Toggle the visibility of [trace] and notify listeners.
void toggleTrace(TraceType trace) {
  if (_visibleTraces.contains(trace)) {
    _visibleTraces.remove(trace);
  } else {
    _visibleTraces.add(trace);
  }
  notifyListeners();
}
```

**2f.** Remove the `TraceType` import from this file if no other reference remains (most likely it's gone — verify with `grep -n TraceType lib/ui/notifiers/dive_detail_notifier.dart`). If the import line `import '../widgets/trace_segmented_bar.dart' show TraceType;` is now unused, delete it.

**2g.** Remove the `DiveMode` import if it was only used by `_defaultTraces` — verify by grepping for `DiveMode` in the same file. If unused, drop:
```dart
import '../../shearwater/parser/constants.dart';
```

- [ ] **Step 3: Strip the dropped-state tests from `dive_detail_notifier_test.dart`**

Open `test/ui/notifiers/dive_detail_notifier_test.dart`. Find every test that asserts on `_visibleTraces`, `visibleTraces` getter, `toggleTrace` method, or `_defaultTraces` behaviour, and delete those test bodies. Keep all other tests (sample loading, crosshair, etc.) untouched.

Common patterns to remove (your file may have variations):
- `test('default traces include ppo2 + setpoint for CCR', ...)`
- `test('default traces are deco + gasChanges for OC', ...)`
- `test('toggleTrace flips membership', ...)`

Also remove any `import '../../...trace_segmented_bar.dart' show TraceType;` if no surviving tests reference `TraceType`.

- [ ] **Step 4: Make `settingsNotifier` required in `DiveDetailScreen`**

Open `lib/ui/screens/dive_detail_screen.dart`. Update the field declaration (around line 48):

```dart
// From:
final SettingsNotifier? settingsNotifier;
// To:
final SettingsNotifier settingsNotifier;
```

And the constructor (around line 92):

```dart
// From:
this.settingsNotifier,
// To:
required this.settingsNotifier,
```

- [ ] **Step 5: Rewire trace reads + chart reads in `DiveDetailScreen`**

In `lib/ui/screens/dive_detail_screen.dart`, find the existing chart + toggle section (currently around lines 424-475). Replace the `_notifier.visibleTraces` and `_notifier.toggleTrace` reads with `widget.settingsNotifier.visibleTraces` and `widget.settingsNotifier.toggleTrace`. Wrap the affected subtree (ProfileChart + CrosshairTooltip + TraceSegmentedBar) in a single `ListenableBuilder` so the subtree rebuilds when toggles change.

The structure becomes:

```dart
if (_notifier.samples != null) ...[
  ListenableBuilder(
    listenable: widget.settingsNotifier,
    builder: (context, _) {
      final visibleTraces = widget.settingsNotifier.visibleTraces;
      return Column(
        children: [
          Builder(builder: (context) {
            final samples = _notifier.samples!;
            final useSpeedColored =
                widget.settingsNotifier.useSpeedColoredGraph;
            return SizedBox(
              height: 250,
              child: LayoutBuilder(builder: (context, constraints) {
                return CrosshairOverlay(
                  sampleCount: samples.sampleCount,
                  chartLeftPad: 40,
                  chartRightPad: 44,
                  onIndexChanged: _notifier.setCrosshairIndex,
                  onRelease: _notifier.clearCrosshair,
                  child: Stack(children: [
                    ProfileChart(
                        samples: samples,
                        visibleTraces: visibleTraces,
                        crosshairIndex: _notifier.crosshairIndex,
                        cellsBySlot: _notifier.activeCells,
                        tanks: _decodeTanks(),
                        mappedCylinders: _notifier.mappedCylinders,
                        gasMixes: _decodeGasMixes(),
                        useSpeedColoredGraph: useSpeedColored),
                    if (_notifier.crosshairIndex != null)
                      CrosshairTooltip(
                        samples: _notifier.samples!,
                        sampleIndex: _notifier.crosshairIndex!,
                        visibleTraces: visibleTraces,
                        chartX: 40 +
                            (_notifier.crosshairIndex! /
                                    (_notifier.samples!.sampleCount - 1)) *
                                (constraints.maxWidth - 84),
                        chartWidth: constraints.maxWidth,
                        cellsBySlot: _notifier.activeCells,
                        tanks: _decodeTanks(),
                        mappedCylinders: _notifier.mappedCylinders,
                        gasMixes: _decodeGasMixes(),
                      ),
                  ]),
                );
              }),
            );
          }),
          TraceSegmentedBar(
              visibleTraces: visibleTraces,
              onToggle: widget.settingsNotifier.toggleTrace),
        ],
      );
    },
  ),
  _buildStatsRow(theme),
  _buildAnnotationsSection(),
],
```

(The exact lines to replace are the current `if (_notifier.samples != null) ...` block. Keep `_buildStatsRow` and `_buildAnnotationsSection` outside the `ListenableBuilder` — they don't depend on the notifier's state.)

The `?? true` fallback on `useSpeedColoredGraph` goes away because `settingsNotifier` is now non-null.

- [ ] **Step 6: Drop nullable `?` from upstream pager**

Open `lib/ui/screens/dive_detail_pager.dart` (line ~45). The field is declared `final SettingsNotifier? settingsNotifier;`. Change to `final SettingsNotifier settingsNotifier;` and the constructor `this.settingsNotifier,` (line ~62) becomes `required this.settingsNotifier,`.

`lib/ui/screens/dive_list_screen.dart` already requires it (line 33: `final SettingsNotifier settingsNotifier;`) — no change needed.

- [ ] **Step 7: Update widget tests that pass `null` (or omit the param)**

For each test identified in Step 1, add `settingsNotifier: SettingsNotifier()` to the constructor call. Import `package:ccrlogger/ui/notifiers/settings_notifier.dart` at the top of each affected test file.

Note: `SettingsNotifier()` is cheap to construct in tests — it only hits SharedPreferences when `load()` or a setter is called. Tests that don't call `load()` get the in-memory defaults, which is fine.

- [ ] **Step 8: Run `flutter analyze` and the test suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(ui): dive detail reads visibleTraces from SettingsNotifier

DiveDetailNotifier no longer owns _visibleTraces — that state is now
persisted in SettingsNotifier (Task 3). DiveDetailScreen reads through
widget.settingsNotifier and rebuilds its toggle-bar + chart subtree on
notifier changes via ListenableBuilder. The notifier is now required-
non-null on DiveDetailScreen / DiveDetailPager. Tests that previously
passed null now provide a fresh SettingsNotifier instance.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Wire map style into `SitesMapScreen`, `SiteMapView`, and `AppShell`

Move `_style` from local `StatefulWidget` state to `SettingsNotifier`. Both map widgets accept a `SettingsNotifier`, drop their local state, and rebuild via `ListenableBuilder`.

**Files:**
- Modify: `lib/ui/screens/sites_map_screen.dart`
- Modify: `lib/ui/widgets/site_map_view.dart`
- Modify: `lib/ui/app_shell.dart` (pass `settingsNotifier` into `SitesMapScreen` push)
- Modify: any other caller of `SitesMapScreen` or `SiteMapView` — likely `lib/ui/screens/dive_detail_screen.dart` (header mini-map tap), `lib/ui/widgets/dive_annotations_section.dart` (site form view)
- Modify (only if test breaks): affected widget tests

- [ ] **Step 1: Identify all callers**

Run:
```bash
grep -rn "SitesMapScreen(" lib/ test/ 2>/dev/null
grep -rn "SiteMapView(" lib/ test/ 2>/dev/null
```

List every call site. Production callers must be updated to pass `settingsNotifier`. Tests must be updated similarly.

- [ ] **Step 2: Update `SitesMapScreen` constructor + state**

Open `lib/ui/screens/sites_map_screen.dart`. Add the new field + constructor param:

```dart
class SitesMapScreen extends StatefulWidget {
  final DiveAnnotationsDao dao;
  final double? currentLat;
  final double? currentLon;
  final SettingsNotifier settingsNotifier;

  const SitesMapScreen({
    super.key,
    required this.dao,
    required this.currentLat,
    required this.currentLon,
    required this.settingsNotifier,
  });

  @override
  State<SitesMapScreen> createState() => _SitesMapScreenState();
}
```

Import `'../notifiers/settings_notifier.dart';` at the top.

In `_SitesMapScreenState`:
1. Remove `MapLayerStyle _style = MapLayerStyle.normal;`.
2. Inside `build()`, wrap the `Stack` containing the map + the toggle in `ListenableBuilder(listenable: widget.settingsNotifier, builder: ...)`. Inside the builder, read `widget.settingsNotifier.mapLayerStyle` as the local `style` variable.
3. The `MapLayerToggle.onChanged` callback becomes:
   ```dart
   onChanged: (next) => widget.settingsNotifier.setMapLayerStyle(next),
   ```
4. The `TileLayer.urlTemplate` reads `tileUrlFor(style)` where `style` is the local from the builder.

Concrete `build()` body shape:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('Dive sites')),
    body: _sites == null
        ? const Center(child: CircularProgressIndicator())
        : ListenableBuilder(
            listenable: widget.settingsNotifier,
            builder: (context, _) {
              final style = widget.settingsNotifier.mapLayerStyle;
              return Stack(
                children: [
                  _buildMap(_sites!, style),
                  Positioned(
                    top: Spacing.sm,
                    right: Spacing.sm,
                    child: MapLayerToggle(
                      current: style,
                      onChanged: (next) =>
                          widget.settingsNotifier.setMapLayerStyle(next),
                    ),
                  ),
                ],
              );
            },
          ),
  );
}
```

Change `_buildMap` to accept `style` as a parameter and use it for `tileUrlFor(style)` instead of reading from the deleted local.

- [ ] **Step 3: Update `SiteMapView` constructor + state**

Open `lib/ui/widgets/site_map_view.dart`. Apply the same pattern:

```dart
class SiteMapView extends StatefulWidget {
  const SiteMapView({
    super.key,
    required this.lat,
    required this.lon,
    required this.settingsNotifier,
    this.siteName,
    this.onTap,
  });

  final double lat;
  final double lon;
  final SettingsNotifier settingsNotifier;
  final String? siteName;
  final VoidCallback? onTap;

  @override
  State<SiteMapView> createState() => _SiteMapViewState();
}
```

Import `'../notifiers/settings_notifier.dart';`.

In `_SiteMapViewState`:
1. Remove `MapLayerStyle _style = MapLayerStyle.normal;`.
2. Wrap the `Stack` body in `ListenableBuilder(listenable: widget.settingsNotifier, ...)` reading `widget.settingsNotifier.mapLayerStyle` as `style`.
3. `MapLayerToggle.onChanged` becomes `(next) => widget.settingsNotifier.setMapLayerStyle(next)`.
4. The `SiteMiniMap.tileUrl` reads `tileUrlFor(style)`.

Since `SiteMapView` currently uses `LayoutBuilder` for sizing, the rebuild order should be `LayoutBuilder` outermost, then `ListenableBuilder` inside (so layout doesn't rebuild needlessly on notifier ticks). The body shape becomes:

```dart
@override
Widget build(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final lat = widget.lat;
  final lon = widget.lon;
  final siteName = widget.siteName;
  final onTap = widget.onTap;
  final coordsLabel = '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';

  return LayoutBuilder(builder: (context, constraints) {
    final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
    final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 220.0;
    return ListenableBuilder(
      listenable: widget.settingsNotifier,
      builder: (context, _) {
        final style = widget.settingsNotifier.mapLayerStyle;
        return Stack(
          children: [
            SiteMiniMap(
              lat: lat,
              lon: lon,
              width: w,
              height: h,
              markerSize: 24,
              tileUrl: tileUrlFor(style),
            ),
            Positioned(
              right: Spacing.sm,
              top: Spacing.sm,
              child: MapLayerToggle(
                current: style,
                onChanged: (next) =>
                    widget.settingsNotifier.setMapLayerStyle(next),
              ),
            ),
            Positioned(
              left: Spacing.sm,
              right: Spacing.sm,
              bottom: Spacing.sm,
              child: InkWell(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm, vertical: Spacing.xs),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.85),
                    borderRadius: Radii.cardBr,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (siteName != null && siteName.isNotEmpty)
                        Text(
                          siteName,
                          style: AppTypography.body.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (siteName != null && siteName.isNotEmpty)
                        const SizedBox(height: Spacing.xs),
                      Text(
                        coordsLabel,
                        style: AppTypography.readoutSm.copyWith(
                          color: scheme.outlineVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  });
}
```

- [ ] **Step 4: Update every call site**

For each call site found in Step 1, add `settingsNotifier: <appropriate-instance>` as a constructor argument.

Production call sites:
- `lib/ui/app_shell.dart` — the AppBar map action push (Task 2 of Track 3 added this). Pass `widget.settingsNotifier`.
- `lib/ui/screens/dive_detail_screen.dart` — header `SitesMapScreen` push (around line 317). Pass `widget.settingsNotifier`.
- `lib/ui/widgets/dive_annotations_section.dart` — constructs BOTH `SiteMapView` (line ~150) AND `SitesMapScreen` (line ~156). Its constructor doesn't currently take a `SettingsNotifier` — add `required SettingsNotifier settingsNotifier` to its constructor and field, then pass `widget.settingsNotifier` to both the `SiteMapView` and `SitesMapScreen` constructor calls inside the file.

Then update `DiveAnnotationsSection`'s caller in `lib/ui/screens/dive_detail_screen.dart` (`_buildAnnotationsSection` around line 667) to pass `settingsNotifier: widget.settingsNotifier`.

Test call sites:
- `test/ui/widgets/dive_annotations_section_test.dart` (line ~39), `test/ui/widgets/dive_annotations_section_site_tabs_test.dart` (line ~53), `test/ui/widgets/dive_annotations_section_divemaster_test.dart` (line ~35) — add `settingsNotifier: SettingsNotifier()` to each `DiveAnnotationsSection(...)` call. Import `package:ccrlogger/ui/notifiers/settings_notifier.dart` at the top of each.
- Any `SitesMapScreen(...)` or `SiteMapView(...)` constructor in `test/` — add `settingsNotifier: SettingsNotifier()`.

- [ ] **Step 5: Run `flutter analyze` and the test suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(ui): persist map layer style via SettingsNotifier

SitesMapScreen and SiteMapView drop their local _style state and read
mapLayerStyle through SettingsNotifier (added in Task 3). Subtrees
rebuild via ListenableBuilder on style change. AppShell, DiveDetailScreen,
and DiveAnnotationsSection thread the notifier through their map pushes.
Style choice now survives app restarts.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Inline the StarRating into the header right column (item 8)

No automated test — visual polish, manual smoke test covers per spec.

**Files:**
- Modify: `lib/ui/widgets/star_rating.dart` (add `size` parameter)
- Modify: `lib/ui/screens/dive_detail_screen.dart` (insert StarRating into the right column; delete the standalone stars row)

- [ ] **Step 1: Add a `size` parameter to `StarRating`**

Open `lib/ui/widgets/star_rating.dart`. Replace its contents with:

```dart
import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  final int? value; // 1-5 or null
  final void Function(int? value) onChanged;
  final double size;

  const StarRating({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: size,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              minWidth: size + 4,
              minHeight: size + 4,
            ),
            icon: Icon(
              i <= (value ?? 0) ? Icons.star : Icons.star_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: () {
              if (value == i) {
                onChanged(null);
              } else {
                onChanged(i);
              }
            },
          ),
      ],
    );
  }
}
```

The `iconSize`, `padding`, and tighter `constraints` are needed because `IconButton`'s default 48-px tap target would otherwise dominate the right column at small star sizes.

- [ ] **Step 2: Insert StarRating into the dive detail header right column**

Open `lib/ui/screens/dive_detail_screen.dart`. Find the right `Column` in the header (currently around lines 390-405):

```dart
Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(formatDepth(dive.maxDepthMm),
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: modeColor)),
      Text(
          '${formatDuration(dive.durationSeconds)} ${formatGf(dive.gfLow, dive.gfHigh)}',
          style: TextStyle(
              color: theme.colorScheme.onSurface
                  .withValues(alpha: 0.5),
              fontSize: 11)),
    ]),
```

Add the StarRating as a third child:

```dart
Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(formatDepth(dive.maxDepthMm),
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: modeColor)),
      Text(
          '${formatDuration(dive.durationSeconds)} ${formatGf(dive.gfLow, dive.gfHigh)}',
          style: TextStyle(
              color: theme.colorScheme.onSurface
                  .withValues(alpha: 0.5),
              fontSize: 11)),
      StarRating(
        value: _annotationsNotifier.rating,
        onChanged: (v) => _annotationsNotifier.setRating(v),
        size: 14,
      ),
    ]),
```

- [ ] **Step 3: Delete the standalone stars-row container**

Open `lib/ui/screens/dive_detail_screen.dart`. Find the standalone stars row (currently around lines 410-421):

```dart
// Star rating: own row so the header text column isn't
// squeezed by 5 stars on narrow screens.
Container(
  color: const Color(0xFF152238),
  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
  alignment: Alignment.centerRight,
  child: StarRating(
    value: _annotationsNotifier.rating,
    onChanged: (v) =>
        _annotationsNotifier.setRating(v),
  ),
),
```

Delete the entire block (the `Container` and its preceding comment). The header's `Container` (one above this) absorbs the remaining padding naturally.

- [ ] **Step 4: Run `flutter analyze` and the test suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes. If a widget test asserts on the old standalone stars-row layout, update it to look for StarRating inside the header instead.

- [ ] **Step 5: Manual smoke test**

Run the app on macOS. Open any dive's detail screen. Verify:
- Stars appear in the header's right column, below "57 min · 35/85" (or wherever the duration/GF line is).
- No second stars row exists below the header.
- Tapping a star still sets the rating.
- The header is visibly shorter than before.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/widgets/star_rating.dart lib/ui/screens/dive_detail_screen.dart
git commit -m "$(cat <<'EOF'
feat(ui): inline StarRating into the dive detail header right column

Item 8 of the Track 4 spec. The dedicated stars row (taking ~32 px of
vertical real estate) is gone; the 5 stars now sit beneath depth +
duration in the existing right column, at size 14 instead of 24.
StarRating gains a size parameter (default 24, override 14 here).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Drop `minCellWidth` to 80 px so stats land at 4 columns on mobile (item 9)

One-number change. No automated test.

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart` (line ~796)

- [ ] **Step 1: Change the threshold**

Open `lib/ui/screens/dive_detail_screen.dart`. Find the line in `_buildStatsRow` (around line 796):

```dart
const minCellWidth = 95.0;
```

Change it to:

```dart
const minCellWidth = 80.0;
```

- [ ] **Step 2: Run `flutter analyze` and the test suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes.

- [ ] **Step 3: Manual smoke test**

Run the app on macOS or an iPhone simulator in portrait. Open a dive with a full stats row (CCR dive with PPO2 + CNS + Temp + V-speed + Gas + Stack + Tanks). Verify:
- The stats row shows 4 cells per row instead of 3.
- Text inside cells is still legible at the narrower width.
- On tablet / desktop window widths, the row stays single-line (no regression).

- [ ] **Step 4: Commit**

```bash
git add lib/ui/screens/dive_detail_screen.dart
git commit -m "$(cat <<'EOF'
feat(ui): stats row drops to 80-px min cell width for 4 cols on mobile

Item 9 of the Track 4 spec. iPhone-portrait now fits 4 stat cells per
row (was 3 at the previous 95-px threshold). Tablet/desktop unaffected
— still single-row.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Definition of done

After Task 7 commits:
1. `flutter analyze` reports zero issues.
2. `flutter test` passes the full suite.
3. Manual smoke tests (Tasks 6.5 and 7.3) pass on macOS.
4. Manual persistence smoke tests pass:
   - Toggle Cells on a CCR dive. Kill and relaunch the app. Reopen any dive — Cells is still on.
   - Open the sites map (AppBar action). Switch to Satellite. Close, relaunch, reopen — initial layer is Satellite.
5. Seven commits land on `main`.
