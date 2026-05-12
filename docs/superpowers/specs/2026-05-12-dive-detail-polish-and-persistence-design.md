# Dive Detail Polish + Persistence — Design Spec

**Date:** 2026-05-12
**Track:** 4 of the multi-track UI work (after Information Tab v2, Map provider polish, Dive List polish).
**Source request:** items 8, 9, 10 of the original eleven-item plan, plus two persistence asks added by the user mid-day:
- Item 8 — shrink the top dive details bar; rating takes too much screen real estate.
- Item 9 — PPO2 / CNS columns display as 3 on mobile, want 4.
- Item 10 — redesign the graph toggles; user doesn't like the current look.
- (+) Persist graph toggle preferences across sessions.
- (+) Persist map / satellite layer choice across sessions.

## Goal

Polish the dive detail screen's information density and toggle affordance, and lift two pieces of in-memory UI state into the existing `SettingsNotifier` so they survive across app launches.

## Why

The detail screen is the surface the diver looks at longest after import. Three friction points:

1. **The 5-star rating sits on its own full-width row.** Roughly 32 px of vertical real estate dedicated to a value most divers set once and never edit again on subsequent visits. The information cost of inlining it is small; the screen-time benefit on phones is real.

2. **Stats row falls to 3 columns on iPhone-portrait.** With 7-9 stat tiles to render, the current 95-px minimum-cell-width threshold means 374-px-of-content / 95 ≈ 3 cells per row plus spacing. A 4-cell row reads more like a dashboard and reduces total vertical height by ~25%.

3. **Graph toggles look busy.** Each chip carries three "selected/deselected" signals (border colour, background tint, dot opacity) on top of the trace-colour dot. Three signals for one bit of state is over-specified.

The two persistence asks are direct beta feedback: Track 2's spec deferred map-style persistence pending feedback, and the same "I changed it on dive A, why didn't dive B remember?" friction applies to graph toggles. Both are SharedPreferences-grade preferences that already have a clean home in `SettingsNotifier`.

## Decisions locked during brainstorming

- **Item 8 placement:** Rating moves to the right column of the header row, inline beneath depth/duration. No separate row. Smaller star size to fit the column.
- **Item 9 mechanism:** Lower `minCellWidth` from 95 → 80 px. Existing adaptive Wrap/Row logic unchanged. Single-number tweak.
- **Item 10 affordance:** Segmented horizontal bar (connected cells, single outline, dividers between). On widths too narrow to fit all six segments, the bar scrolls horizontally (`SingleChildScrollView(scrollDirection: Axis.horizontal)`).
- **Graph toggle persistence granularity:** Global single set. Setpoint/Cells toggles remain visible regardless of dive mode — the chart already handles missing trace data without crashing or rendering anything, so a toggle that does nothing on OC dives is harmless.
- **Map style persistence storage:** Existing `SettingsNotifier`, alongside `useSpeedColoredGraph`. No new notifier class.

## Scope

### In scope

1. **Top bar layout** — `StarRating` widget moves into the header's right `Column`, beneath duration/GF; the dedicated stars row container is removed. Star size reduces to fit the column (~14-16 px). The rating's tap-to-edit interaction stays.

2. **Stats row column count** — `const minCellWidth = 95.0` in `_buildStatsRow` becomes `const minCellWidth = 80.0`. No other change.

3. **Graph toggle widget redesign** — `lib/ui/widgets/trace_toggle.dart` (the `TraceToggleChips` Wrap-of-pills widget) is deleted. A new `lib/ui/widgets/trace_segmented_bar.dart` ships `TraceSegmentedBar`, a connected segmented control wrapped in a horizontally-scrolling viewport. Six segments — PPO2, Setpoint, Cells, Deco, Tanks, Gas — each with a small trace-colour dot and the existing label.

4. **Graph toggle persistence** — `SettingsNotifier` gains:
   - Private `Set<TraceType> _visibleTraces`, hydrated on `load()` from SharedPreferences key `visible_traces` (stored as `List<String>` of `TraceType` enum names).
   - Public `Set<TraceType> get visibleTraces` getter (returns an unmodifiable view).
   - Public `Future<void> toggleTrace(TraceType t)` mutator. Flips membership, calls `notifyListeners()`, then async-writes the new list to SharedPreferences.
   - Initial state on first launch: `{ppo2, setpoint, deco, gasChanges}` (current CCR default).
   - `DiveDetailNotifier` loses its `_visibleTraces` field, `_defaultTraces` helper, `toggleTrace` method, and `visibleTraces` getter. Consumers read/write through `SettingsNotifier`.

5. **Map style persistence** — `SettingsNotifier` gains:
   - Private `MapLayerStyle _mapLayerStyle`, hydrated on `load()` from SharedPreferences key `map_layer_style` (stored as the enum's `name`).
   - Public `MapLayerStyle get mapLayerStyle` getter.
   - Public `Future<void> setMapLayerStyle(MapLayerStyle s)` mutator.
   - Initial state on first launch: `MapLayerStyle.normal`.
   - `SitesMapScreen` and `SiteMapView` accept a `SettingsNotifier` and replace their local `_style` `StatefulWidget` state with reads/writes through the notifier.

6. **`TraceType` enum relocation** — the enum currently lives in `lib/ui/notifiers/dive_detail_notifier.dart` (which loses ownership of the visibility set entirely). Hoist `TraceType` to `lib/ui/widgets/trace_segmented_bar.dart`. `SettingsNotifier` imports it from there. Roughly 72 references across `lib/` and `test/` need their import lines updated — mechanical sed-style change.

7. **Tests:**
   - New `test/ui/notifiers/settings_notifier_test.dart` — round-trip persistence for both new preferences, default values on empty SharedPreferences, no-op on identical-value setters.
   - New `test/ui/widgets/trace_segmented_bar_test.dart` — selected/unselected rendering, tap toggles, horizontal scroll behaviour.
   - Update `test/ui/notifiers/dive_detail_notifier_test.dart` — remove assertions on the dropped `_visibleTraces` ownership.
   - No automated test for the layout changes in items 8 + 9 (visual/numeric polish; manual smoke test covers, consistent with Tracks 1-3).

### Out of scope

- No icon-only toggles (decided against during option C confirmation).
- No per-mode or per-dive remembered preferences (decided against — global is the chosen granularity).
- No additional map styles beyond Normal / Satellite.
- No filter logic to hide Setpoint/Cells toggles on OC dives.
- No changes to the chart renderer (`profile_chart.dart`) — it already keys off the `visibleTraces` set.
- No changes to `MapLayerToggle` itself (the floating button stays; it still emits `MapLayerStyle` on tap; only its callers change to write to `SettingsNotifier` rather than local state).

## Architecture

Three subsystems, each with a single clear seam:

1. **Layout** — items 1+2 above. Pure widget tree edits inside `_buildDetailsTab` and `_buildStatsRow`.

2. **Toggles widget** — item 3. Self-contained widget swap. The widget's public surface is identical to the old `TraceToggleChips` (`visibleTraces` Set, `onToggle` callback), so the call site change is just a rename.

3. **Persistence** — items 4+5+6. `SettingsNotifier` becomes the owner of two new state fields. Consumers (`DiveDetailScreen`, `SitesMapScreen`, `SiteMapView`) shift from owning local state to reading/writing through the notifier.

### Component flow

```
SettingsNotifier (singleton at app shell)
  ├── visibleTraces: Set<TraceType>          ← NEW (persisted)
  ├── toggleTrace(TraceType t)               ← NEW (persists + notifies)
  ├── mapLayerStyle: MapLayerStyle           ← NEW (persisted)
  ├── setMapLayerStyle(MapLayerStyle s)      ← NEW (persists + notifies)
  └── useSpeedColoredGraph: bool             (existing, unchanged)

DiveDetailScreen
  ├── reads SettingsNotifier.visibleTraces
  ├── passes to TraceSegmentedBar(visibleTraces: ..., onToggle: notifier.toggleTrace)
  └── passes to ProfileChart(visibleTraces: ...)

SitesMapScreen / SiteMapView
  ├── reads SettingsNotifier.mapLayerStyle
  ├── passes to TileLayer(urlTemplate: tileUrlFor(style))
  └── MapLayerToggle.onChanged → notifier.setMapLayerStyle(...)
```

### Detailed file changes

#### `lib/ui/notifiers/settings_notifier.dart`

Add fields, hydration, getters, mutators:

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/map_tile_sources.dart' show MapLayerStyle;
import '../widgets/trace_segmented_bar.dart' show TraceType;

class SettingsNotifier extends ChangeNotifier {
  static const _kSpeedColored = 'use_speed_colored_graph';
  static const _kVisibleTraces = 'visible_traces';
  static const _kMapLayerStyle = 'map_layer_style';

  bool _useSpeedColoredGraph = true;
  Set<TraceType> _visibleTraces = {
    TraceType.ppo2,
    TraceType.setpoint,
    TraceType.deco,
    TraceType.gasChanges,
  };
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
          .map((n) => TraceType.values.where((t) => t.name == n).firstOrNull)
          .whereType<TraceType>()
          .toSet();
    }
    final styleName = prefs.getString(_kMapLayerStyle);
    if (styleName != null) {
      _mapLayerStyle = MapLayerStyle.values
          .where((s) => s.name == styleName)
          .firstOrNull ?? MapLayerStyle.normal;
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

#### `lib/ui/notifiers/dive_detail_notifier.dart`

Remove:
- `enum TraceType { ... }` (moved to trace_segmented_bar.dart)
- `final Set<TraceType> _visibleTraces;`
- `static Set<TraceType> _defaultTraces(int diveModeValue) { ... }`
- `Set<TraceType> get visibleTraces => _visibleTraces;`
- `void toggleTrace(TraceType trace) { ... }`

Constructor signature simplifies accordingly. Import of `TraceType` shifts to the new home.

#### `lib/ui/widgets/trace_toggle.dart`

**Delete the file.** Old widget retired in favour of `TraceSegmentedBar`.

#### `lib/ui/widgets/trace_segmented_bar.dart` (NEW)

```dart
library;

import 'package:flutter/material.dart';

import '../components/status_dot.dart';
import '../theme/tokens.dart';

enum TraceType { ppo2, setpoint, cells, deco, tanks, gasChanges }

const _segmentData = <TraceType, ({String label, Color color})>{
  TraceType.ppo2: (label: 'PPO2', color: Color(0xFFFFCC66)),
  TraceType.setpoint: (label: 'Setpoint', color: Color(0xFFA0AEB6)),
  TraceType.cells: (label: 'Cells', color: Color(0xFF4ADE80)),
  TraceType.deco: (label: 'Deco', color: Color(0xFFF39C12)),
  TraceType.tanks: (label: 'Tanks', color: Color(0xFF60A5FA)),
  TraceType.gasChanges: (label: 'Gas', color: Color(0xFF60A5FA)),
};

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

#### `lib/ui/screens/dive_detail_screen.dart`

Three regions change:

1. **Header right column** (around lines 390-405) — add `StarRating` below the duration line. Remove the standalone stars-row `Container` (around lines 412-421) entirely. `StarRating` (lib/ui/widgets/star_rating.dart) currently has no `size` parameter — add a `final double size = 24` default with a `size: 14` override at the new call site. Existing callers that don't pass `size` get unchanged behaviour.

2. **Trace toggle render** (around line 470) — change `TraceToggleChips(visibleTraces: _notifier.visibleTraces, onToggle: _notifier.toggleTrace)` to `TraceSegmentedBar(visibleTraces: widget.settingsNotifier!.visibleTraces, onToggle: widget.settingsNotifier!.toggleTrace)`. The two earlier references at lines 441 and 452 (passing `_notifier.visibleTraces` to `ProfileChart` and `CrosshairTooltip`) also flip to `widget.settingsNotifier!.visibleTraces`.

3. **Stats row threshold** (around line 796) — `const minCellWidth = 95.0` → `const minCellWidth = 80.0`.

The `DiveDetailScreen` constructor's `SettingsNotifier? settingsNotifier;` becomes `required SettingsNotifier settingsNotifier;` (non-null). Tests that previously passed `null` provide a fresh `SettingsNotifier()` instance instead (cheap to construct — SharedPreferences hydration is lazy).

To ensure the toggle bar and chart rebuild when the notifier's state changes, wrap the affected widget subtrees in `ListenableBuilder(listenable: widget.settingsNotifier, builder: (ctx, _) => ...)`. Specifically the trace segmented bar and the profile chart need rebuild on toggle. Don't blanket-wrap the entire `_buildDetailsTab` — keep the wrap focused on the consumers.

#### `lib/ui/screens/sites_map_screen.dart`

Constructor gains a required `SettingsNotifier settingsNotifier`. Local `MapLayerStyle _style = MapLayerStyle.normal;` is removed. The `_style` getter is replaced by `widget.settingsNotifier.mapLayerStyle`. `MapLayerToggle.onChanged` callback becomes `(next) => widget.settingsNotifier.setMapLayerStyle(next)`. State class becomes simpler — no local style management.

The screen needs to rebuild on notifier changes — wrap the body in `ListenableBuilder(listenable: widget.settingsNotifier, builder: ...)`. Same pattern is used for `SiteMapView` below.

#### `lib/ui/widgets/site_map_view.dart`

Same pattern as `SitesMapScreen`: gain a `SettingsNotifier settingsNotifier` constructor parameter, drop local `_style`, read/write through the notifier, listen for rebuilds.

#### `lib/ui/app_shell.dart`

Wire `widget.settingsNotifier` into the AppBar map action's `SitesMapScreen(...)` push and any other call sites that construct `SitesMapScreen` or `SiteMapView`.

#### Test files

- **NEW** `test/ui/notifiers/settings_notifier_test.dart`:
  - `'visibleTraces defaults to {ppo2, setpoint, deco, gasChanges} when SharedPreferences empty'`
  - `'toggleTrace flips membership and notifies'`
  - `'toggleTrace persists across reload'` (round-trip — call `toggleTrace`, create a fresh notifier, `load`, assert)
  - `'mapLayerStyle defaults to MapLayerStyle.normal when empty'`
  - `'setMapLayerStyle persists across reload'`
  - `'setMapLayerStyle no-ops when style unchanged'`

- **NEW** `test/ui/widgets/trace_segmented_bar_test.dart`:
  - `'TraceSegmentedBar renders six segments'`
  - `'tapping an unselected segment calls onToggle with its TraceType'`
  - `'tapping a selected segment calls onToggle with its TraceType'`
  - `'visibleTraces controls per-segment styling'`
  - `'bar is wrapped in horizontal SingleChildScrollView'` (regression — verifies overflow strategy)

- **UPDATE** `test/ui/notifiers/dive_detail_notifier_test.dart`:
  - Delete tests for `_visibleTraces` defaults and `toggleTrace` (those concerns moved to `SettingsNotifier`).
  - Verify the notifier still functions correctly without the field (e.g., other state — crosshair, samples — still works).

## Risks

- **`StarRating` widget may not support a `size` constructor param today.** If absent, add one. Trivial change.
- **Test files referencing `null` for `settingsNotifier`.** Tests that exercise `DiveDetailScreen` without providing a notifier won't render the toggle bar correctly. Audit and provide a real `SettingsNotifier` (which is safe to construct in-test since it reads SharedPreferences lazily) or a fake.
- **`TraceType` enum relocation may need import updates across many files.** Likely just `dive_detail_notifier.dart`, the screen, the chart, the crosshair tooltip, and tests. `grep -rn 'TraceType' lib/ test/` to find the full set before refactoring.

## Testing strategy

- `flutter analyze` clean.
- `flutter test` passes the full suite.
- Manual smoke test on macOS (the user's primary dev target):
  1. **Top bar:** open a dive — rating appears inline under depth/duration, no separate row, no excessive vertical space.
  2. **Stats row:** rotate to portrait on a mobile width — verify 4 stat tiles per row (current count: PPO2, CNS, Temp, V-speed in row 1; Gas, Tanks, Stack, [empty] in row 2).
  3. **Graph toggles:** segmented bar appears below the chart. Tapping a segment toggles the corresponding trace. On narrow widths, the bar scrolls horizontally.
  4. **Toggle persistence:** toggle Cells on, navigate away, kill and relaunch app, open any dive — Cells is still on.
  5. **Map style persistence:** open the dive sites map from the AppBar, switch to satellite. Close, relaunch — open the same map — satellite is the initial layer. Open the dive detail of a dive with coords — the header mini-map also opens with satellite (if SiteMapView is also reading the notifier; if SiteMapView uses SiteMiniMap with default OSM, that's per-spec — the SiteMapView itself is the map-with-toggle).

## Definition of done

1. All ten production files edited per the spec.
2. `flutter analyze` reports zero issues.
3. `flutter test` passes the full suite.
4. Manual smoke tests pass on macOS.
5. Spec-driven commits land on `main`. Suggested commit decomposition (subject to plan):
   - Persistence foundation: SettingsNotifier extensions + tests.
   - Layout polish: top bar inline rating + 4-column stats threshold.
   - Toggle widget swap: TraceSegmentedBar + tests + retire trace_toggle.dart.
   - Wiring: rewire DiveDetailScreen / SitesMapScreen / SiteMapView to read through SettingsNotifier; drop ownership from DiveDetailNotifier.
