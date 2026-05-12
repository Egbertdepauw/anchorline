# Dive List Polish — Design Spec

**Date:** 2026-05-12
**Track:** 3 of the multi-track UI work (after Information Tab v2 + map provider polish).
**Source request:** item 6 of the original eleven-item plan — "Remove the dive map thumbnail from the dive list screen." Expanded in brainstorming to include an AppBar entry point so the route to the all-sites map view isn't lost.

## Goal

Strip the per-row mini-map thumbnail from the dive list. Replace the lost
navigation affordance with a single AppBar action on the Dives tab that
opens `SitesMapScreen` fitted to all known sites. No other changes to the
dive list row, search/filter, or sites map screen.

## Why

The mini-map thumbnail on each list row added visual noise without adding
information: pin location at 56 px is impossible to read, and every row
with coords also already shows the site name as text in the same row. The
thumbnail's only unique value was as a tap target to open the all-sites
map screen. Promoting that tap target to an AppBar icon makes it more
discoverable (top-right corner is where users look for screen-level
navigation) and frees ~72 px of horizontal headroom in each row for the
site-name text on narrow phones.

## Scope

### In scope

1. Remove the `SiteMiniMap` widget + its 56-px placeholder slot from
   `DiveTile`.
2. Remove the `onMiniMapTap` callback parameter from `DiveTile` (only
   caller is `DiveListScreen`).
3. Remove the `Navigator.push(SitesMapScreen(...))` wiring from
   `DiveListScreen`.
4. Add an `IconButton(Icons.map_outlined)` to `AppShell`'s AppBar
   `actions`, sequenced before the existing Settings cog, gated by the
   same `if (_currentIndex == 0)` as Settings. Tap opens
   `SitesMapScreen(dao: _diveAnnotationsDao, currentLat: null,
   currentLon: null)`. Tooltip: "Dive sites map".
5. Update affected widget tests.

### Out of scope

- `SiteMiniMap` widget itself stays in the codebase — still used in the
  dive detail header and site form view.
- `SitesMapScreen` is unchanged. It already handles the
  `currentLat == null && currentLon == null` path correctly via
  `CameraFit.bounds(LatLngBounds.fromPoints(points))`.
- No FAB, no list-vs-map toggle on the dive list, no per-row interaction
  changes (tap-to-detail, swipe-to-delete remain identical).
- No design-token changes. The freed 72 px just becomes additional
  horizontal headroom for the `Expanded` text column inside `DiveTile`'s
  `Row`.

## Architecture

Three file edits, one new test assertion, two deleted test cases. Each
edit is local and has no cross-cutting impact.

### Files touched

| File | Change |
|------|--------|
| `lib/ui/widgets/dive_tile.dart` | Remove mini-map slot (lines ~52-66) and the `onMiniMapTap` constructor param + field. |
| `lib/ui/screens/dive_list_screen.dart` | Remove the `onMiniMapTap:` argument in `_DiveTileWithSparkline.build` (lines ~361-367). |
| `lib/ui/app_shell.dart` | Add new `IconButton` to `AppBar.actions` before the Settings button, gated by `_currentIndex == 0`. |
| `test/ui/widgets/dive_tile_test.dart` | Replace the two mini-map tests with one regression guard. Drop `site_mini_map.dart` import. |
| `test/ui/app_shell_test.dart` (existing or new) | Add a smoke test for the AppBar map action pushing `SitesMapScreen`. |

### Component flow (after change)

```
DiveListScreen
  └── _DiveTileWithSparkline (per row)
        └── DiveTile
              ├── colored border (mode indicator)
              ├── DepthSparkline (56×36)
              ├── Expanded(
              │     Column(
              │       Row(mode label · #N · site name · date),
              │       NumericReadout(depth · duration · GF),
              │       optional buddies line,
              │     )
              │   )

AppShell.AppBar (when _currentIndex == 0):
  ├── IconButton(Icons.map_outlined)  ← NEW
  │     → SitesMapScreen(dao, currentLat: null, currentLon: null)
  └── IconButton(Icons.settings_outlined)
        → SettingsScreen(...)
```

## Detailed changes

### `lib/ui/widgets/dive_tile.dart`

Delete the `if (annotation?.siteLatitude != null && annotation?.siteLongitude != null) ... else const SizedBox(width: 56)` block AND the `const SizedBox(width: Spacing.md)` that follows it.

Delete the `final VoidCallback? onMiniMapTap;` field and remove
`this.onMiniMapTap` from the constructor.

Delete the `'site_mini_map.dart'` import — `SiteMiniMap` is no longer
referenced from this file.

### `lib/ui/screens/dive_list_screen.dart`

Delete the `onMiniMapTap: () => Navigator.of(context).push(...)` argument
passed to `DiveTile` inside `_DiveTileWithSparkline.build`. The import
of `sites_map_screen.dart` can be removed if no other reference remains
in the file (verify before deleting).

### `lib/ui/app_shell.dart`

Inside the `actions: [...]` list of the `AppBar` (around lines 242-266),
insert a new entry before the existing `if (_currentIndex == 0) IconButton(...Settings...)`:

```dart
if (_currentIndex == 0)
  IconButton(
    tooltip: 'Dive sites map',
    icon: const Icon(Icons.map_outlined),
    onPressed: () {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SitesMapScreen(
          dao: _diveAnnotationsDao,
          currentLat: null,
          currentLon: null,
        ),
      ));
    },
  ),
```

Add `import 'screens/sites_map_screen.dart';` to the file's imports.

### `test/ui/widgets/dive_tile_test.dart`

Replace the two existing mini-map tests (lines 74-113) with one
regression guard:

```dart
testWidgets('DiveTile never renders a SiteMiniMap', (tester) async {
  final now = DateTime.now();
  final ann = dom.DiveAnnotation(
    diveId: 'test-dive-id',
    siteLatitude: 51.5,
    siteLongitude: 3.7,
    createdAt: now,
    updatedAt: now,
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DiveTile(
        dive: _makeDive(),
        sparklineData: Float32List.fromList([0, 10, 0]),
        annotation: ann,
        onTap: () {},
      ),
    ),
  ));
  expect(find.byType(SiteMiniMap), findsNothing);
});
```

Keep the `package:ccrlogger/ui/widgets/site_mini_map.dart` import — the
regression guard uses `find.byType(SiteMiniMap)` so the type name still
needs to resolve.

### `test/ui/screens/app_shell_test.dart`

No AppShell test file exists today (verified). Adding one requires
wiring fake DAOs, Supabase, PowerSync, and attachments through the
constructor. **Decision:** defer the AppBar test to a follow-up and ship
only the DiveTile regression guard for this track. Manual smoke test
(see Testing strategy) covers the AppBar behaviour for this PR.

If we choose to add a test anyway, it should:

1. Build AppShell with stub DAOs.
2. Verify on the Dives tab that an `IconButton` with `Icons.map_outlined`
   is present in the `AppBar.actions`.
3. Tap it and assert `find.byType(SitesMapScreen)` after the next pump.
4. Switch to another tab (e.g., Equipment) and verify the map icon is no
   longer in the AppBar.

## Risks

- **None significant.** Each file edit is local; the affected behaviour
  (mini-map tap → SitesMapScreen) is preserved via the new entry point
  rather than removed.

## Testing strategy

- `flutter analyze` clean after changes.
- `flutter test test/ui/widgets/dive_tile_test.dart` passes with the
  replaced regression guard.
- Manual smoke test: Build app, observe (a) dive list rows no longer
  have a left-side map thumbnail, (b) map icon appears in top-right
  AppBar on Dives tab, (c) tapping it opens SitesMapScreen showing all
  sites, (d) switching to other tabs hides the icon.

## Definition of done

1. All three production files edited per the spec.
2. `flutter analyze` reports zero issues.
3. `flutter test` passes (full suite, not just touched files).
4. Manual smoke test described above passes on macOS (the user's primary
   dev target).
5. Single commit (or small commit chain) lands on `main`.
