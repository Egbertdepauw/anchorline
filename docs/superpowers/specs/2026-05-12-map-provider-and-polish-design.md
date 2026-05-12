# Map provider + polish — design

**Status:** approved 2026-05-12.

**Owner:** CCRLog UI / maps.

**Context:** The two big map surfaces (`SitesMapScreen` full-screen, `SiteMapView` inside the Dive Detail Map tab) currently use OSM tiles hard-coded at the widget level. Two friction points users have noted:

1. Tapping the header mini-map of a specific dive opens `SitesMapScreen` zoomed to fit *all* the user's dive sites — when the diver wanted to see the one they came from.
2. No satellite imagery option — useful for confirming dive entry-point geography (shore access, reef edges) that road tiles don't show.

This spec covers Track 2 of today's plan (items 3, 4, 5).

## Goals

1. Add ESRI World Imagery as a satellite tile source. Provider URLs centralised in one file so the two big maps + the mini-map all reference one source of truth.
2. `SitesMapScreen` zooms to **z=14** centered on the current dive when opened from a specific dive. Other sites still pinned for context. Current dive's pin styled distinctly (larger + accent colour) so it stands out.
3. Floating "layer toggle" button on `SitesMapScreen` and `SiteMapView` switching between Normal (OSM) and Satellite (ESRI). State is per-instance — no app-wide persistence.

## Non-goals (deferred)

- Mapbox / Google Maps migration. Beta scale doesn't justify the API-key + billing setup. Re-evaluate at GA scale.
- App-wide map-style preference persistence. Per-map state is enough; user feedback during beta tells us if persistence is wanted.
- Satellite on mini-maps. The 72-px header thumbnail and dive-list tile thumbnails are too small for satellite to convey useful detail; they stay on OSM normal.
- Tile caching / offline-first map data. Live network only, same as today.
- Map style switching for the bigger world view (when no current dive is passed). Toggle still works on that path, but no special "default to satellite for ocean views" logic — too clever for now.

## Architecture

### Tile sources (new shared file)

`lib/ui/widgets/map_tile_sources.dart`:

```dart
/// OSM raster tiles. Free, no API key. OSM's ToS asks heavy users to
/// move to a commercial provider; beta-scale usage is fine.
const String osmTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// ESRI World Imagery — satellite raster tiles. Free for non-commercial
/// use, no API key required. Note: `{y}/{x}` swapped vs OSM.
const String esriSatelliteTileUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

enum MapLayerStyle { normal, satellite }

String tileUrlFor(MapLayerStyle style) => switch (style) {
      MapLayerStyle.normal => osmTileUrl,
      MapLayerStyle.satellite => esriSatelliteTileUrl,
    };
```

### Toggle widget (new)

`lib/ui/widgets/map_layer_toggle.dart`: a small floating button positioned top-right of any map. Takes `MapLayerStyle current` + `ValueChanged<MapLayerStyle> onChanged`. Icon switches based on `current` (Normal shows the satellite-alt icon to indicate "switch to satellite"; Satellite shows the map icon to indicate "switch back to normal"). Hard-edge 2px container per the design system, sodium-vapor accent.

### `SiteMiniMap` — minor change

Accept an optional `tileUrl` parameter defaulting to `osmTileUrl`. Existing callers (header mini-map at 72 px, dive-list tile if still present after Track 3) pass nothing → keep OSM normal as today. No toggle on this widget.

### `SitesMapScreen` — three changes

1. **Zoom-to-dive.** Inside `_buildMap`, change the `points.length > 1` path so that *when `currentLat/Lon` are non-null*, the options become `initialCenter: LatLng(currentLat, currentLon), initialZoom: 14`. The all-bounds-fit branch still applies when no current dive is passed (e.g. a future "All sites" entry point).
2. **Distinct current pin.** Current pin already detected via `_isCurrent(...)`. Restyle: width/height bumped to 44 (vs 36 default), colour is `AppColors.wreck.accentPrimary` instead of `Colors.redAccent`. Other pins stay at 36/redAccent.
3. **Satellite toggle.** Track `MapLayerStyle _style = MapLayerStyle.normal` in state. Wrap the `FlutterMap` in a `Stack` with `MapLayerToggle` positioned top-right. Pass `tileUrlFor(_style)` to the `TileLayer.urlTemplate`. `setState` on toggle.

### `SiteMapView` — same toggle treatment

Adds `_style` state + `MapLayerToggle` positioned top-right of the existing `Stack`. Forwards `tileUrl` to `SiteMiniMap`. Other layout (coords/name overlay strip) unchanged.

## Tests

- `map_tile_sources_test.dart` — `tileUrlFor(MapLayerStyle.normal)` returns OSM; `.satellite` returns ESRI; exhaustive.
- `map_layer_toggle_test.dart` — widget renders the right icon for each state; tap fires `onChanged` with the *opposite* style.
- `sites_map_screen_test.dart` — extend existing tests: when `currentLat/Lon` are passed alongside many sites, the FlutterMap's `initialCenter` is the current point and `initialZoom` is 14 (assert via `find.byType(FlutterMap)` + reading the rendered options if exposed, otherwise via golden / behavioural check that pin layout makes sense).
- `site_map_view_test.dart` — toggle button visible; tapping it swaps the tile URL (assert via reading the `TileLayer` from the widget tree).

If reading `MapOptions` off a built `FlutterMap` is too brittle, fall back to verifying observable side effects (e.g. the layer URL through the widget hierarchy).

## File touch list

- **New:**
  - `lib/ui/widgets/map_tile_sources.dart`
  - `lib/ui/widgets/map_layer_toggle.dart`
  - `test/ui/widgets/map_tile_sources_test.dart`
  - `test/ui/widgets/map_layer_toggle_test.dart`
- **Modify:**
  - `lib/ui/widgets/site_mini_map.dart` — optional `tileUrl` param, default uses `osmTileUrl`. Switch the hardcoded URL to the constant.
  - `lib/ui/screens/sites_map_screen.dart` — zoom-to-dive logic, distinct current pin, satellite toggle.
  - `lib/ui/widgets/site_map_view.dart` — satellite toggle button.
- **Tests modified:**
  - `test/ui/screens/sites_map_screen_test.dart` (if exists) — new assertions for zoom + current-pin styling + toggle visibility.

## Risk

- ESRI World Imagery has a fair-use clause for non-commercial apps. At beta scale this is fine; commercial deployment needs a different provider. Captured here so the deferral is explicit.
- Tile servers occasionally rate-limit. Both OSM and ESRI fail silently into blank tiles, so a network blip just looks like grey squares — no app crash.
- `flutter_map`'s `MapOptions` is immutable; swapping the URL via `setState` works because the `TileLayer` is rebuilt with a new key/URL. Existing app already relies on this pattern, so risk is low.

## Open questions

None blocking. The shape of the spec is locked.
