# App Shell + Dark Theme + Dive List

## Context

CCRLogger has Steps 1-5 complete: parser, BLE transport, data model, persistence. The app still runs the Flutter counter demo. This spec covers the first UI deliverable: a working app that displays imported dives with a dark theme, bottom navigation, and a dive list with mini-profile sparklines.

## App Structure

### Theme

- Material 3 dark theme as default.
- Color scheme seeded from cyan (#4FC3F7) — the CCR accent color.
- Surface/background: deep navy (#0D1B2A or similar dark tone, not pure black).
- Card surfaces slightly elevated from background for depth.
- No light theme toggle in this iteration (added with Settings screen later).

### Navigation

- `BottomNavigationBar` with 4 tabs:
  1. **Dives** — dive list (implemented in this spec)
  2. **Import** — placeholder screen ("Import from dive computer")
  3. **Equipment** — placeholder screen
  4. **Settings** — placeholder screen
- Dive detail pushes on top of the Dives tab (standard `Navigator.push`).
- Each tab preserves its own scroll position.

### State Management

- `ChangeNotifier` subclasses, no external packages.
- `DiveListNotifier` — loads all dives from `DiveDao`, notifies on change.
- Provided via `ListenableBuilder` or a simple inherited widget.
- Database instance created once at app startup and passed down.

## Dive List Screen

### Layout

- `SliverAppBar` with app title "CCRLog".
- Dives grouped by month. Section headers: "April 2026", "March 2026", etc.
- Each dive is a **mini-profile tile** (see below).
- Pull-to-refresh triggers re-query from database.
- Empty state: centered message "No dives yet" with a button to navigate to Import tab.

### Mini-Profile Tile

Each tile is a horizontal row:

```
┌──────────┬──────────────────────────────────────────┐
│ ▕sparkline│  CC  #718                      19 Apr   │
│ ▕  (mode  │  28.4m · 57min · SP 1.30 · GF 45/80   │
│ ▕  color) │  📍 Vobster Quay                        │
└──────────┴──────────────────────────────────────────┘
```

- **Left border stripe** — 3px, mode color.
- **Sparkline** — 56×36px `CustomPainter`, draws a simplified depth profile from the sample data. Stroke color matches mode. Background: darker surface.
- **Top row** — mode label (text in mode color, e.g. "CC"), dive number bold, date right-aligned.
- **Middle row** — max depth, duration, setpoint (CCR) or primary gas (OC), GF low/high.
- **Bottom row** — site name if annotated, otherwise omitted (tile shrinks to 2 lines).
- Tap navigates to dive detail (placeholder for now — just shows dive ID).

### Dive Mode Colors

| Mode | Label | Color | Hex |
|------|-------|-------|-----|
| CC / CC2 | CC | Cyan | #4FC3F7 |
| OC Tec / OC Rec | OC | Orange | #FF9800 |
| SC | SC | Purple | #AB47BC |
| Gauge / PPO2 | GA | Blue-grey | #78909C |
| Freedive | FD | Teal | #26A69A |

### Sparkline Widget

- `CustomPainter` that takes a `Float32List` of depth values.
- Draws a single polyline, Y-axis inverted (deeper = lower), X-axis spans full width.
- Downsamples to ~30 points max for performance (pick every Nth sample).
- No axes, labels, or grid — just the shape.
- Stroke width: 1.5px, anti-aliased.
- Background: transparent (painted on dark card surface).

### Month Grouping

- Group dives by `startTime` year + month.
- Section header: sticky, bold, slightly smaller text. Format: "April 2026".
- Use `SliverList` with section headers for efficient scrolling.

## Data Flow

### Database Initialization

- `AppDatabase` created with `NativeDatabase` in app documents directory.
- Single instance, passed to `DiveDao` and notifiers.
- On first launch (empty database): optionally seed with fixture dives for development. Controlled by a debug flag, not shipped in release.

### DiveListNotifier

```dart
class DiveListNotifier extends ChangeNotifier {
  final DiveDao _dao;
  List<Dive> _dives = [];
  bool _loading = false;

  List<Dive> get dives => _dives;
  bool get loading => _loading;

  Future<void> loadDives() async { ... }
}
```

- Loads all dives on init.
- Groups computed as a getter (not stored separately).
- Sparkline data loaded lazily per-dive from `DiveDao.getSamples()` with an in-memory LRU cache.

### Sparkline Data Cache

- Decompressing sample blobs is expensive. Cache decompressed depth arrays.
- Simple `Map<String, Float32List>` limited to ~50 entries (most recent dives).
- Loaded on-demand when tile scrolls into view, not upfront for all dives.

## Files to Create/Modify

| File | Purpose |
|------|---------|
| `lib/main.dart` | Replace counter demo with app shell |
| `lib/ui/theme/app_theme.dart` | Dark theme definition |
| `lib/ui/app_shell.dart` | Bottom nav + tab scaffold |
| `lib/ui/screens/dive_list_screen.dart` | Dive list with month grouping |
| `lib/ui/screens/placeholder_screen.dart` | Placeholder for Import/Equipment/Settings tabs |
| `lib/ui/widgets/dive_tile.dart` | Mini-profile tile widget |
| `lib/ui/widgets/sparkline.dart` | Depth sparkline CustomPainter |
| `lib/ui/notifiers/dive_list_notifier.dart` | ChangeNotifier for dive list state |
| `lib/ui/util/dive_mode_color.dart` | Mode → color mapping |
| `lib/ui/util/format.dart` | Formatting helpers (depth, duration, date) |

## Development Seeding

For development, a helper function seeds the database with the 8 fixture dives:

```dart
Future<void> seedFixtures(AppDatabase db) async {
  // Only in debug mode, only if database is empty.
  // Parse each fixture .bin, convert, import via DiveDao.
}
```

This lives in a `lib/dev/` directory and is excluded from release builds via `kDebugMode`.

## Verification

- App launches with dark theme, bottom nav visible.
- Dives tab shows month-grouped list with sparklines.
- Sparkline colors match dive mode.
- Tiles show dive number, depth, duration, setpoint/gas, GF, site name.
- Tapping a tile navigates (to a placeholder detail screen for now).
- Pull-to-refresh reloads the list.
- Empty state shows when no dives exist.
- `flutter analyze` clean, all existing 142 tests still pass.
