# Dive Annotations

## Context

The dive detail screen currently renders the immutable parsed-dive data: header, profile chart, sample inspection. There is no way for the user to attach human context — where the dive was, who they dived with, what they thought of it, which physical cylinders were in use.

The schema has anticipated this since v1: `DiveAnnotations` table (with `siteName`, `siteLatitudeE5`/`siteLongitudeE5`, `notes`, `buddiesJson`, `tagsJson`, `rating`, `conditions`) and a `DiveAnnotation` domain class in `lib/data/models/annotation.dart`. Neither has any DAO or UI integration. This spec lands both, plus a new `DiveCylinders` table that ties physical cylinders to the dive's gas mixes.

## Scope

**In scope:**

1. **Text/lookup annotations** on each dive: site name, latitude/longitude, notes, buddies, tags, rating (1–5), conditions.
2. **GPS + map picker** for site coordinates. Tap "Use current location" to fill from device GPS, or "Pick on map" to push a map screen with a draggable pin.
3. **Cylinder ↔ dive mapping**: for each gas mix in `Dives.gasMixesJson`, the user picks which cylinder held it. Active-time-per-mix is derived automatically from `DiveSamples.gasMixIdxBlob`.
4. **Inline editing** in the existing `DiveDetailScreen` (below the profile chart), with an explicit Save button.
5. **Autocomplete** for site names, buddies, and tags, sourced from prior annotations.

**Out of scope (separate specs / future work):**

- Cylinder timeline overlay rendered on top of the profile chart (data is there once mappings are saved; rendering belongs to a future "profile chart polish" pass).
- Auto-suggest a cylinder for each gas mix based on composition match (e.g. mix '100' → Oxygen cylinder).
- Conditions as structured fields (viz, current, swell as separate columns) — single freeform text matches the schema.
- Per-dive overrides for the recorded gas-mix composition (when the dive computer's mix is wrong). The DC's recording is authoritative for now.
- Media attachments — photos / videos along the dive — separate spec.

## Layout

The `DiveDetailScreen` keeps its current shape (header + profile chart) and gains an inline `DiveAnnotationsSection` immediately below the profile chart. Order of fields top to bottom:

1. **Site name** — `TextField` with autocomplete from prior annotations.
2. **Latitude / Longitude** — two side-by-side numeric `TextField`s, optional. Two buttons next to them: "Use current location" (GPS) and "Pick on map" (push the map picker).
3. **Notes** — multi-line `TextField`, ~4 lines tall.
4. **Buddies** — chip input (chips wrap; typing + Enter promotes to a chip; tap × to remove). Autocomplete from prior annotations.
5. **Tags** — chip input, same shape as Buddies.
6. **Rating** — five tappable star icons in a row. Tap N to set rating to N; tap the currently-active star to clear.
7. **Conditions** — single-line `TextField`, freeform.
8. **Gas mixes** — sub-section listing one row per mix in `dive.gasMixesJson`. Each row shows `'Mix N · 21/35 · ~12 min active'` and a `DropdownButton<String?>` picking from the user's `Cylinders` (with "—" as the unmapped sentinel).
9. **Save** — full-width `ElevatedButton`. Disabled until any field is dirty. Saves the `DiveAnnotations` row + all `DiveCylinders` rows in a single `db.transaction`.

## Schema

**New table — `DiveCylinders`** (additive, schema v2 → v3):

```dart
class DiveCylinders extends Table {
  TextColumn get diveId => text().references(Dives, #id)();
  IntColumn get gasMixIndex => integer()(); // index into Dives.gasMixesJson
  TextColumn get cylinderId => text().nullable()(); // FK to Cylinders.id; null = unmapped

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {diveId, gasMixIndex};
}
```

`DiveAnnotations` is unchanged. `siteLatitudeE5` / `siteLongitudeE5` already store fixed-point ints; the DAO converts to/from `double` at the boundary.

**Migration:** `database.dart`'s `MigrationStrategy.onUpgrade` gains `if (from < 3) await m.createTable(diveCylinders);`. `schemaVersion` bumps to 3.

**Migration test:** extend `migration_test.dart` with a v2 → v3 case mirroring the v1 → v2 pattern (seed a v2 schema with an existing `dive_annotations` row; open `AppDatabase`; verify the row survives and `dive_cylinders` is queryable).

## DAO

**New `DiveAnnotationsDao`** in `lib/data/db/dive_annotations_dao.dart`. Uses the `DriftAccessor` pattern, owning `DiveAnnotations` and `DiveCylinders` tables. Methods:

```
get(String diveId) -> Future<DiveAnnotation?>
upsert(DiveAnnotation annotation) -> Future<void>
listCylindersForDive(String diveId) -> Future<List<DiveCylinder>>
setDiveCylinder(String diveId, int gasMixIndex, String? cylinderId) -> Future<void>
saveAll(DiveAnnotation, List<({int gasMixIndex, String? cylinderId})>) -> Future<void>  // wraps both writes in db.transaction
distinctSiteNames() -> Future<List<String>>
distinctBuddies() -> Future<List<String>>
distinctTags() -> Future<List<String>>
```

JSON encoding/decoding for `buddiesJson` and `tagsJson` happens inside the DAO; consumers see `List<String>`. `siteLatitudeE5` / `siteLongitudeE5` ↔ `double?` conversion also happens inside the DAO.

**Existing domain class:** `DiveAnnotation` in `lib/data/models/annotation.dart` already exists and has all the right fields. Reuse it; the DAO maps Drift row → domain class on read.

## Notifier

**`DiveAnnotationsNotifier`** in `lib/ui/notifiers/dive_annotations_notifier.dart`:

- Constructed with `DiveAnnotationsDao`.
- `load(String diveId, List<({int index, String mix})> diveMixes)` — fetches the annotation row (or returns a blank one if no row exists yet) and the dive-cylinder rows. Pre-populates a `Map<int, String?> _cylinderByMix` from the rows; gas-mix indexes that don't have a row yet default to `null`.
- Field-level setters (`setSiteName`, `setLat`, `setLon`, `setNotes`, `setBuddies`, `setTags`, `setRating`, `setConditions`, `setCylinderForMix(index, cylinderId)`) — each flips `_dirty = true` and calls `notifyListeners`.
- `bool get dirty` — used by the Save button's enabled state.
- `Future<void> save()` — writes the annotation + cylinder mappings via `dao.saveAll(...)`, clears `_dirty`.

The notifier does not own the gas-switch timeline calculation; that's a UI-side derivation (see below).

## UI components

Three reusable widgets — kept small, focused, and individually testable:

### `lib/ui/widgets/chip_input.dart`

```
ChipInput({
  required List<String> initialValues,
  required List<String> autocompleteOptions,
  required void Function(List<String>) onChanged,
})
```

A `Wrap` of existing chips + a `TextField` at the end. Typing into the field, then Enter or comma, promotes the typed string to a chip and fires `onChanged`. Each chip has a `×` to remove. The `TextField` shows an `Autocomplete` dropdown filtered against `autocompleteOptions` minus current values.

### `lib/ui/widgets/star_rating.dart`

```
StarRating({int? value, required void Function(int? value) onChanged})
```

Five tappable star icons. Tap star N → `onChanged(N)`. Tap the currently-active star → `onChanged(null)`.

### `lib/ui/screens/map_picker_screen.dart`

```
MapPickerScreen({double? initialLat, double? initialLon})
```

Returns `({double lat, double lon})?` via `Navigator.pop` — null if user cancels.

- Uses `flutter_map` (OpenStreetMap tiles).
- On open: if `initialLat/Lon` set, centers there. Otherwise asks `geolocator` for current location. Otherwise uses a sensible fallback (e.g. `LatLng(0, 0)` with low zoom).
- Single draggable pin overlay. Tapping the map moves the pin to the tap location.
- AppBar action: `IconButton(Icons.my_location)` → re-centers and re-pins to current GPS.
- Bottom action: `ElevatedButton('Use this location')` → pops with the pin's coords.

**Tile-server URL is a constant** in `map_picker_screen.dart`:

```dart
// OSM tile server. Note: tile.openstreetmap.org's usage policy disallows
// production use in mobile apps; swap to a permitted provider (MapTiler /
// Stadia / self-hosted) before public release.
const _tileUrlTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
```

When the time comes to swap, the change is one line. The constant lives next to the picker so it's easy to find.

### `lib/ui/widgets/dive_annotations_section.dart`

The composite widget that owns its `DiveAnnotationsNotifier`, renders all eight sub-blocks above, and exposes only `Dive` + a per-mix-active-seconds map as inputs. Embedded into `DiveDetailScreen` as a child below the profile chart.

## Active-time-per-mix derivation

In `lib/data/sample_codec/`:

```dart
/// Returns a map of gasMixIndex → seconds-active for this dive,
/// computed by counting samples in [gasMixIdxBlob] (already unpacked
/// from the gzip blob) and multiplying by [sampleIntervalMs] / 1000.
Map<int, int> activeSecondsPerMix({
  required Uint8List gasMixIdxBlob, // raw bytes (already gunzipped) of Uint8List
  required int sampleCount,
  required int sampleIntervalMs,
}) { ... }
```

Note: `gasMixIdxBlob` is gzipped on disk; the helper expects the unpacked bytes (use `ColumnPacker.unpackUint8`). `DiveDetailScreen` calls this when its samples load, then passes the resulting map down to `DiveAnnotationsSection` so the gas-mixes sub-section can render `'~12 min active'` next to each mix.

## Wiring

- **`AppShell`** instantiates `DiveAnnotationsDao(widget.db)` once and stores it in a `late final _diveAnnotationsDao` field. Passes it down to `DiveListScreen` (which already receives `_diveDao`), which forwards it to `DiveDetailScreen`.
- **`DiveDetailScreen`** constructor gains a `DiveAnnotationsDao annotationsDao` parameter. The screen passes it (plus the dive, plus the active-seconds-per-mix map computed from samples) into `DiveAnnotationsSection`.
- **`DiveListScreen`** constructor gains a `DiveAnnotationsDao annotationsDao` parameter; pushes it to `DiveDetailScreen` on tap.

## Platform permissions

- **iOS** (`ios/Runner/Info.plist`): add `NSLocationWhenInUseUsageDescription` with copy like *"This app uses your location to record where each dive happened."*
- **macOS** (`macos/Runner/Info.plist` + `DebugProfile.entitlements` + `Release.entitlements`): add `NSLocationUsageDescription` to Info.plist; add `com.apple.security.personal-information.location` to both entitlement files.
- **Android** (`android/app/src/main/AndroidManifest.xml`): add `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />` and `<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />`.

The geolocator package itself handles runtime permission prompts on first GPS use; the platform manifests just declare the capability.

## Dependencies (pubspec.yaml)

Two new direct deps:

```yaml
geolocator: ^14.0.0   # GPS access
flutter_map: ^7.0.0   # OSM-based map picker
latlong2: ^0.9.0      # LatLng type used by flutter_map
```

(Pin to whatever majors are current at implementation time. `latlong2` is `flutter_map`'s coordinate type; `dart:math.Point<double>` could substitute but the `flutter_map` API takes `LatLng` directly.)

## Tests

- **DAO unit tests** — upsert/load round-trip, distinct lookups (siteNames / buddies / tags), `setDiveCylinder` round-trip and overwrite, `saveAll` writes both halves transactionally and is idempotent on re-save.
- **Migration test** — extend `migration_test.dart` with a v2 → v3 case that seeds an existing `dive_annotations` row, opens `AppDatabase`, asserts the row survives and `dive_cylinders` is empty + queryable + accepts inserts.
- **Notifier state-machine test** — `load → set fields → dirty == true → save → dirty == false`.
- **`activeSecondsPerMix` unit test** — synthetic blob of e.g. `[0, 0, 0, 1, 1, 2]` with 60s sample interval → `{0: 180, 1: 120, 2: 60}`.
- **Widget smoke tests** — `ChipInput` (renders chips, accepts new typing, fires onChanged), `StarRating` (renders, sets value on tap), `DiveAnnotationsSection` (renders for a fresh dive with no annotation row).
- `MapPickerScreen` is not unit-tested in MVP — it's a thin wrapper around `flutter_map` and `geolocator`, both of which are exercised in their own packages. A manual on-device test (open picker, drop pin, confirm, verify lat/lon round-trip) is the verification.

## Open verifications during implementation

- `flutter_map` and `geolocator` versions resolve cleanly against the project's existing constraints (Dart `^3.11.5`).
- macOS sandbox + location entitlement actually surfaces the permission prompt (Apple's privacy framework can be finicky; verify on first GPS attempt).
- `Dives.gasMixesJson` parses cleanly into a list of mix descriptors that the gas-mixes sub-section can render — confirm the JSON shape during Task 1 of the implementation plan.
