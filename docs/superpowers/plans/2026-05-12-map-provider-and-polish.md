# Map provider + polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralise tile-URL constants, add ESRI satellite as a togglable layer on the two big maps, and have `SitesMapScreen` zoom to z=14 on the dive the user came from (with the current pin styled distinctly).

**Architecture:** All map widgets reference a new `lib/ui/widgets/map_tile_sources.dart` for URL constants and a `MapLayerStyle` enum. A new `MapLayerToggle` widget renders the floating Normal/Satellite button. `SiteMiniMap` accepts an optional `tileUrl` (defaults to OSM) but exposes no toggle UI. `SitesMapScreen` and `SiteMapView` each carry a local `MapLayerStyle` state and pass the resolved URL to their `TileLayer`. `SitesMapScreen` switches to point-center + zoom-14 when `currentLat/Lon` are non-null and renders the current pin larger in `accentPrimary`.

**Tech Stack:** Flutter, Dart, `flutter_map` (raster tiles), existing design-system tokens (`AppColors.wreck`, `Spacing`, `Radii`).

**Reference spec:** `docs/superpowers/specs/2026-05-12-map-provider-and-polish-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/ui/widgets/map_tile_sources.dart` | Create | OSM + ESRI URL constants, `MapLayerStyle` enum, `tileUrlFor()` |
| `lib/ui/widgets/map_layer_toggle.dart` | Create | Floating button switching between Normal/Satellite |
| `lib/ui/widgets/site_mini_map.dart` | Modify | Optional `tileUrl` param, switch hardcoded URL to constant |
| `lib/ui/screens/sites_map_screen.dart` | Modify | Zoom-to-dive when currentLat/Lon set, distinct current pin, satellite toggle |
| `lib/ui/widgets/site_map_view.dart` | Modify | Add satellite toggle button |
| `test/ui/widgets/map_tile_sources_test.dart` | Create | URL constants + `tileUrlFor` exhaustive |
| `test/ui/widgets/map_layer_toggle_test.dart` | Create | Icon per state + onChanged toggles |
| `test/ui/screens/sites_map_screen_test.dart` | Create (if missing) / modify | Zoom-14 + current-pin styling assertions |

---

## Task 1: Shared tile sources + enum

**Files:**
- Create: `lib/ui/widgets/map_tile_sources.dart`
- Test: `test/ui/widgets/map_tile_sources_test.dart`

- [ ] **Step 1: Failing test**

Create `test/ui/widgets/map_tile_sources_test.dart`:

```dart
import 'package:ccrlogger/ui/widgets/map_tile_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tileUrlFor returns OSM for normal style', () {
    expect(tileUrlFor(MapLayerStyle.normal), osmTileUrl);
    expect(osmTileUrl, contains('tile.openstreetmap.org'));
  });

  test('tileUrlFor returns ESRI World Imagery for satellite style', () {
    expect(tileUrlFor(MapLayerStyle.satellite), esriSatelliteTileUrl);
    expect(esriSatelliteTileUrl, contains('server.arcgisonline.com'));
    expect(esriSatelliteTileUrl, contains('World_Imagery'));
  });

  test('MapLayerStyle has exactly two values', () {
    expect(MapLayerStyle.values.length, 2);
  });
}
```

Run: `flutter test test/ui/widgets/map_tile_sources_test.dart`
Expected: FAIL — file doesn't exist.

- [ ] **Step 2: Create the file**

```dart
/// OSM raster tiles. Free, no API key. OSM's ToS asks heavy users to
/// move to a commercial provider; beta-scale usage is fine.
const String osmTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// ESRI World Imagery — satellite raster tiles. Free for non-commercial
/// use, no API key required. Note: `{y}/{x}` swapped vs OSM.
const String esriSatelliteTileUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

/// Visual style for a map's base layer. Used by [SitesMapScreen] and
/// [SiteMapView] to swap the active [TileLayer] URL. Mini-maps don't
/// expose a toggle and always render `normal`.
enum MapLayerStyle { normal, satellite }

String tileUrlFor(MapLayerStyle style) => switch (style) {
      MapLayerStyle.normal => osmTileUrl,
      MapLayerStyle.satellite => esriSatelliteTileUrl,
    };
```

- [ ] **Step 3: Run tests + analyzer**

```bash
flutter test test/ui/widgets/map_tile_sources_test.dart
flutter analyze lib/ui/widgets/map_tile_sources.dart
```
Expected: 3 tests pass, 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/widgets/map_tile_sources.dart test/ui/widgets/map_tile_sources_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): centralise map tile URLs + MapLayerStyle enum

OSM (normal) + ESRI World Imagery (satellite) URL constants in a
single file. tileUrlFor() returns the right template per style.
Sets up the satellite toggle in subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: MapLayerToggle widget

**Files:**
- Create: `lib/ui/widgets/map_layer_toggle.dart`
- Test: `test/ui/widgets/map_layer_toggle_test.dart`

- [ ] **Step 1: Failing test**

Create `test/ui/widgets/map_layer_toggle_test.dart`:

```dart
import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/widgets/map_layer_toggle.dart';
import 'package:ccrlogger/ui/widgets/map_tile_sources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows satellite-alt icon when current is Normal', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: MapLayerToggle(
          current: MapLayerStyle.normal,
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.byIcon(Icons.satellite_alt), findsOneWidget);
    expect(find.byIcon(Icons.layers_outlined), findsNothing);
  });

  testWidgets('shows layers icon when current is Satellite', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: MapLayerToggle(
          current: MapLayerStyle.satellite,
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
    expect(find.byIcon(Icons.satellite_alt), findsNothing);
  });

  testWidgets('tap fires onChanged with the opposite style', (tester) async {
    MapLayerStyle? received;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: MapLayerToggle(
          current: MapLayerStyle.normal,
          onChanged: (v) => received = v,
        ),
      ),
    ));
    await tester.tap(find.byType(MapLayerToggle));
    expect(received, MapLayerStyle.satellite);
  });
}
```

Run: `flutter test test/ui/widgets/map_layer_toggle_test.dart`
Expected: FAIL — widget doesn't exist.

- [ ] **Step 2: Implement the widget**

Create `lib/ui/widgets/map_layer_toggle.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'map_tile_sources.dart';

/// Floating Normal/Satellite layer toggle for a map. Sized small so it
/// sits unobtrusively in a corner. The icon represents the layer the
/// user would switch TO if they tap (so Normal mode shows the
/// satellite icon, and vice versa).
class MapLayerToggle extends StatelessWidget {
  const MapLayerToggle({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final MapLayerStyle current;
  final ValueChanged<MapLayerStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = current == MapLayerStyle.normal
        ? MapLayerStyle.satellite
        : MapLayerStyle.normal;
    final icon = current == MapLayerStyle.normal
        ? Icons.satellite_alt
        : Icons.layers_outlined;
    return Material(
      color: scheme.surfaceContainer.withValues(alpha: 0.92),
      borderRadius: Radii.cardBr,
      child: InkWell(
        borderRadius: Radii.cardBr,
        onTap: () => onChanged(next),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Icon(
            icon,
            size: 20,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Run tests + analyzer**

```bash
flutter test test/ui/widgets/map_layer_toggle_test.dart
flutter analyze lib/ui/widgets/map_layer_toggle.dart
```
Expected: 3 tests pass, 0 issues.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/widgets/map_layer_toggle.dart test/ui/widgets/map_layer_toggle_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): MapLayerToggle floating button

Small material button toggling Normal/Satellite. Icon represents the
target layer (Normal mode shows satellite-alt to invite switching).
Consumed by SitesMapScreen + SiteMapView in subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: SiteMiniMap accepts optional tileUrl

**Files:**
- Modify: `lib/ui/widgets/site_mini_map.dart`

- [ ] **Step 1: Update the widget**

In `lib/ui/widgets/site_mini_map.dart`:

Add the new optional parameter to the constructor:

```dart
  /// Tile URL template. Defaults to OSM. Mini-maps don't expose a
  /// toggle (too small for satellite to add useful detail); callers
  /// pass nothing and stay on OSM.
  final String tileUrl;

  const SiteMiniMap({
    super.key,
    required this.lat,
    required this.lon,
    this.size = 64,
    this.width,
    this.height,
    this.markerSize,
    this.tileUrl = osmTileUrl,
  });
```

Add the import:

```dart
import 'map_tile_sources.dart';
```

Replace the hardcoded `urlTemplate` line in the `TileLayer`:

```dart
            TileLayer(
              urlTemplate: tileUrl,
              userAgentPackageName: 'app.ccrlogger',
            ),
```

(Was: `urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',`)

- [ ] **Step 2: Verify existing tests still pass**

```bash
flutter test test/ui/widgets/site_map_view_test.dart
flutter analyze
```
Expected: existing SiteMiniMap callers (SiteMapView's test, dive_tile_test, etc.) still pass — the default for `tileUrl` keeps the existing behaviour.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/widgets/site_mini_map.dart
git commit -m "$(cat <<'EOF'
refactor(ui): SiteMiniMap reads from map_tile_sources

Optional tileUrl parameter (default = osmTileUrl). No behavioural
change for existing callers. Sets up SiteMapView to forward its
satellite-toggle state in the next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: SiteMapView gains the toggle

**Files:**
- Modify: `lib/ui/widgets/site_map_view.dart`
- Test: `test/ui/widgets/site_map_view_test.dart`

- [ ] **Step 1: Failing test**

Append to `test/ui/widgets/site_map_view_test.dart`:

```dart
  testWidgets('SiteMapView shows the layer-toggle button', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SiteMapView(
          lat: 52.2366,
          lon: 4.9570,
          siteName: 'Vinkeveen',
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(MapLayerToggle), findsOneWidget);
    // Default style is normal — toggle shows the satellite-alt icon
    expect(find.byIcon(Icons.satellite_alt), findsOneWidget);
  });

  testWidgets('tapping the layer toggle swaps the TileLayer URL',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SiteMapView(
          lat: 52.2366,
          lon: 4.9570,
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Verify TileLayer is using OSM url initially
    final beforeSiteMiniMap = tester.widget<SiteMiniMap>(find.byType(SiteMiniMap));
    expect(beforeSiteMiniMap.tileUrl, osmTileUrl);

    await tester.tap(find.byType(MapLayerToggle));
    await tester.pump();

    final afterSiteMiniMap = tester.widget<SiteMiniMap>(find.byType(SiteMiniMap));
    expect(afterSiteMiniMap.tileUrl, esriSatelliteTileUrl);
  });
```

Add imports at the top of the test file if not already present:

```dart
import 'package:ccrlogger/ui/widgets/site_mini_map.dart';
import 'package:ccrlogger/ui/widgets/map_layer_toggle.dart';
import 'package:ccrlogger/ui/widgets/map_tile_sources.dart';
```

Run: `flutter test test/ui/widgets/site_map_view_test.dart`
Expected: the new tests FAIL — `MapLayerToggle` not found in `SiteMapView`.

- [ ] **Step 2: Convert SiteMapView to StatefulWidget**

In `lib/ui/widgets/site_map_view.dart`:

Change `StatelessWidget` → `StatefulWidget`, add the state class. Pattern:

```dart
class SiteMapView extends StatefulWidget {
  const SiteMapView({
    super.key,
    required this.lat,
    required this.lon,
    this.siteName,
    this.onTap,
  });

  final double lat;
  final double lon;
  final String? siteName;
  final VoidCallback? onTap;

  @override
  State<SiteMapView> createState() => _SiteMapViewState();
}

class _SiteMapViewState extends State<SiteMapView> {
  MapLayerStyle _style = MapLayerStyle.normal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lat = widget.lat;
    final lon = widget.lon;
    final siteName = widget.siteName;
    final onTap = widget.onTap;
    final coordsLabel =
        '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
      final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 220.0;
      return Stack(
        children: [
          SiteMiniMap(
            lat: lat,
            lon: lon,
            width: w,
            height: h,
            markerSize: 24,
            tileUrl: tileUrlFor(_style),
          ),
          Positioned(
            right: Spacing.sm,
            top: Spacing.sm,
            child: MapLayerToggle(
              current: _style,
              onChanged: (next) => setState(() => _style = next),
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
    });
  }
}
```

Add imports:

```dart
import 'map_layer_toggle.dart';
import 'map_tile_sources.dart';
```

- [ ] **Step 3: Run tests + analyzer**

```bash
flutter test test/ui/widgets/site_map_view_test.dart
flutter analyze
```
Expected: all SiteMapView tests pass (new + existing), 0 analyzer issues.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/widgets/site_map_view.dart test/ui/widgets/site_map_view_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): SiteMapView gains a satellite toggle

Floating MapLayerToggle in the top-right of the Map tab. State is
per-instance (no persistence). SiteMiniMap inside gets the resolved
tileUrl from tileUrlFor() so it actually swaps layers on tap.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: SitesMapScreen — zoom-to-dive + distinct current pin

**Files:**
- Modify: `lib/ui/screens/sites_map_screen.dart`
- Test: `test/ui/screens/sites_map_screen_test.dart` (create if absent)

- [ ] **Step 1: Failing test**

Run `ls test/ui/screens/sites_map_screen_test.dart 2>&1` to check if it exists. If yes, append; otherwise create with the full harness.

Test cases needed:

```dart
testWidgets('opens at zoom 14 centred on the current dive when given',
    (tester) async {
  // Pump SitesMapScreen with currentLat/Lon set + the DAO returning
  // multiple sites including the current one.
  // Assert the FlutterMap initialised with center near (currentLat, currentLon)
  // and initialZoom == 14.
});

testWidgets('current pin renders in accent colour at size 44',
    (tester) async {
  // Pump with currentLat/Lon matching one of the seeded sites.
  // Find the Marker tree, assert the current one's child Icon has
  // size: 44 and color: AppColors.wreck.accentPrimary.
});

testWidgets('zoom-out preserves other-site pins', (tester) async {
  // Pump with currentLat/Lon + 3 other sites.
  // Assert MarkerLayer contains 4 markers total (1 current + 3 others).
});

testWidgets('layer toggle swaps the TileLayer URL', (tester) async {
  // Pump, find MapLayerToggle, tap it, assert TileLayer.urlTemplate
  // is now esriSatelliteTileUrl.
});
```

If you can't reliably read `FlutterMap.options` (since `MapOptions` is on the inner state), inspect the rendered widget tree (the markers list, the TileLayer URL) instead. Don't over-fit on internal API.

Use the existing `DiveAnnotationsDao` fakes (if any) for the DAO seam; otherwise create a minimal fake that returns a known list of sites for `distinctSiteCoords()`.

Run: `flutter test test/ui/screens/sites_map_screen_test.dart`
Expected: new tests FAIL (zoom + accent colour + toggle not implemented).

- [ ] **Step 2: Implement the changes**

In `lib/ui/screens/sites_map_screen.dart`:

**A) Switch to local style state + toggle.** Convert the existing State so it owns:

```dart
MapLayerStyle _style = MapLayerStyle.normal;
```

Wrap the existing `_buildMap` output in a `Stack`:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('Dive sites')),
    body: _sites == null
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              _buildMap(_sites!),
              Positioned(
                top: Spacing.sm,
                right: Spacing.sm,
                child: MapLayerToggle(
                  current: _style,
                  onChanged: (next) => setState(() => _style = next),
                ),
              ),
            ],
          ),
  );
}
```

**B) Use the shared tile URL.** Replace the `_tileUrlTemplate` constant + `urlTemplate: _tileUrlTemplate` with:

```dart
import '../widgets/map_tile_sources.dart';
import '../widgets/map_layer_toggle.dart';
import '../theme/tokens.dart';
```

```dart
TileLayer(
  urlTemplate: tileUrlFor(_style),
  userAgentPackageName: 'app.ccrlogger',
),
```

Remove the old `const String _tileUrlTemplate = ...;` declaration.

**C) Zoom-to-dive.** In `_buildMap`:

```dart
final cLat = widget.currentLat;
final cLon = widget.currentLon;
final MapOptions options;
if (points.isEmpty) {
  options = const MapOptions(
    initialCenter: LatLng(0, 0),
    initialZoom: 2,
  );
} else if (cLat != null && cLon != null) {
  // Came from a specific dive — focus on it at z=14.
  options = MapOptions(
    initialCenter: LatLng(cLat, cLon),
    initialZoom: 14,
  );
} else if (points.length == 1) {
  options = MapOptions(
    initialCenter: points.first,
    initialZoom: 11,
  );
} else {
  options = MapOptions(
    initialCameraFit: CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(48),
    ),
  );
}
```

**D) Distinct current pin.** The existing `MarkerLayer` already branches on `_isCurrent(...)`. Change the current branch to:

```dart
Marker(
  point: LatLng(s.lat, s.lon),
  width: 44,
  height: 44,
  child: Icon(Icons.location_pin,
      color: AppColors.wreck.accentPrimary, size: 44),
)
```

Other-pin branch stays at 36/redAccent.

Add the import for the palette if missing:

```dart
import '../theme/tokens.dart';
```

- [ ] **Step 3: Run tests + analyzer**

```bash
flutter test test/ui/screens/sites_map_screen_test.dart
flutter test  # full suite — existing tests that touched this screen need to still pass
flutter analyze
```
Expected: every test passes, 0 analyzer issues.

If the header-mini-map test from Track 1 (`tapping the header mini-map opens SitesMapScreen`) now asserts on the wrong pin colour, update narrowly — the assertion was about navigation, not colour.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/screens/sites_map_screen.dart test/ui/screens/sites_map_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): zoom-to-dive + satellite toggle on SitesMapScreen

When opened from a specific dive (currentLat/Lon set), the map now
centers on that dive at zoom 14 — other sites still pinned for
context. Current dive's pin is rendered in the sodium-vapor accent
at 44px so it stands out from the redAccent 36px other-site pins.
Layer toggle in the top-right swaps between OSM normal and ESRI
satellite. State is per-screen-instance (no persistence).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Full-suite verification + push

- [ ] **Step 1: Full sweep**

```bash
flutter analyze
flutter test
```
Expected: 0 analyzer issues, every test passes.

- [ ] **Step 2: Manual smoke**

Run on macOS or iPhone. Walk through:

1. **Existing dive with coords** — open Dive Detail → Map tab shows the layer toggle button top-right. Tap it → tiles swap to satellite imagery. Tap again → back to normal. Tap the overlay strip → opens `SitesMapScreen`.
2. **SitesMapScreen, opened from a dive** — view is zoomed to z=14 on the dive; the dive's pin is amber and bigger; other-site pins (if any) are red and smaller. Layer toggle in the top-right works.
3. **SitesMapScreen, opened with no currentLat/Lon** (if any code path triggers this — search for `SitesMapScreen(dao:` callers) — falls back to all-sites bounds fit. No regression.
4. **Header mini-map on Details tab** — stays OSM normal, no toggle button (correct).
5. **Dive-list tile thumbnail** (if still present per Track 3 timing) — stays OSM normal.

- [ ] **Step 3: Push**

```bash
git push origin main
```

- [ ] **Step 4: Update memory**

Edit `/Users/egbert/.claude/projects/-Users-egbert-Dev-CCRLog-ccrlogger/memory/project_next_session_priority.md`: mark Track 2 (map provider + polish) as shipped; note Tracks 3 and 4 are next.

---

## Self-Review

**Spec coverage:**
- Item 3 (provider) → Task 1 (constants) + Task 3 (SiteMiniMap reads them) + Task 5 (SitesMapScreen reads them).
- Item 4 (zoom-to-dive + distinct pin) → Task 5.
- Item 5 (satellite toggle) → Task 2 (toggle widget) + Task 4 (SiteMapView) + Task 5 (SitesMapScreen).

**Placeholder scan:** no TBDs. Every step has either code or a concrete command. Test stubs in Task 5 are described behaviourally with explicit assertion targets; if `MapOptions` is hard to inspect through `find.byType`, the fallback is reading the rendered TileLayer / Marker tree which is straightforward.

**Type consistency:** `MapLayerStyle` defined in Task 1, consumed in Tasks 2/3/4/5 with the same name. `tileUrlFor()` returns `String`. `MapLayerToggle` props (`current: MapLayerStyle`, `onChanged: ValueChanged<MapLayerStyle>`) match between widget definition and call sites.

**One pragmatic note:** Task 5's test on `SitesMapScreen` may need a tiny fake of `DiveAnnotationsDao` that responds to `distinctSiteCoords()` with a hard-coded list. The implementer should follow whatever fake pattern already exists in the test directory (likely `FakeSessionSource` and DAO fakes from prior tests).
