# Dive List Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the per-row mini-map thumbnail from the dive list and add an AppBar action that opens `SitesMapScreen` fitted to all sites.

**Architecture:** Two small commits. Commit 1 is one TDD cycle that strips the mini-map widget + its constructor wiring from `DiveTile` and `DiveListScreen`, replacing two scattered tests with a single regression guard. Commit 2 adds an `IconButton(Icons.map_outlined)` to `AppShell`'s AppBar, gated to the Dives tab, that opens `SitesMapScreen` with null coords (SitesMapScreen already handles the "fit all sites" path).

**Tech Stack:** Flutter, flutter_test, flutter_map, latlong2

**Spec:** [docs/superpowers/specs/2026-05-12-dive-list-polish-design.md](../specs/2026-05-12-dive-list-polish-design.md)

---

## Task 1: Strip the mini-map thumbnail from `DiveTile` + `DiveListScreen`

**Files:**
- Modify: `test/ui/widgets/dive_tile_test.dart` (replace tests at lines ~74-113 with one regression guard)
- Modify: `lib/ui/widgets/dive_tile.dart` (remove import line ~11, field line ~19, constructor param line ~32, rendering block lines ~52-67)
- Modify: `lib/ui/screens/dive_list_screen.dart` (remove `onMiniMapTap:` argument lines ~361-367, remove `sites_map_screen.dart` import line ~20)

- [ ] **Step 1: Write the failing regression test**

Open `test/ui/widgets/dive_tile_test.dart`. Replace the two tests at lines 74-113 (the `'DiveTile shows mini map when annotation has coords'` and `'DiveTile omits mini map when annotation lacks coords'` testWidgets blocks) with a single regression guard:

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

Keep the existing `import 'package:ccrlogger/ui/widgets/site_mini_map.dart';` line — `find.byType(SiteMiniMap)` requires the type symbol to resolve.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/ui/widgets/dive_tile_test.dart --plain-name "DiveTile never renders a SiteMiniMap"`
Expected: FAIL with `Expected: no matching candidates / Actual: Found 1 widget with type "SiteMiniMap"` (or similar). The current `DiveTile` still renders the mini-map when coords are present, so the regression guard fires.

- [ ] **Step 3: Remove mini-map rendering + constructor wiring from `DiveTile`**

Open `lib/ui/widgets/dive_tile.dart`. Apply these four edits:

**3a.** Delete the import line:
```dart
import 'site_mini_map.dart';
```
(currently line 11)

**3b.** Delete the field declaration:
```dart
  final VoidCallback? onMiniMapTap;
```
(currently line 19)

**3c.** Delete the constructor parameter line:
```dart
    this.onMiniMapTap,
```
(currently inside the `const DiveTile({...})` constructor at line ~32)

**3d.** Delete lines 52-67 — the entire conditional block plus the trailing `Spacing.md` gap:

```dart
            if (annotation?.siteLatitude != null &&
                annotation?.siteLongitude != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onMiniMapTap,
                child: IgnorePointer(
                  child: SiteMiniMap(
                    lat: annotation!.siteLatitude!,
                    lon: annotation!.siteLongitude!,
                    size: 56,
                  ),
                ),
              )
            else
              const SizedBox(width: 56),
            const SizedBox(width: Spacing.md),
```

The `Row`'s `children` list should now begin directly with the `SizedBox(width: 56, height: 36, child: sparklineData != null ? DepthSparkline(...) : Container(...))` block.

- [ ] **Step 4: Remove `onMiniMapTap` wiring from `DiveListScreen`**

Open `lib/ui/screens/dive_list_screen.dart`. Apply two edits:

**4a.** Inside `_DiveTileWithSparkline.build` (around lines 350-388), delete the entire `onMiniMapTap:` argument passed to `DiveTile`. The block to remove looks like:

```dart
          onMiniMapTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SitesMapScreen(
              dao: annotationsDao,
              currentLat: ann?.siteLatitude,
              currentLon: ann?.siteLongitude,
            ),
          )),
```

After removal, the `DiveTile(...)` call should retain its other arguments unchanged (`dive`, `sparklineData`, `annotation`, `sequenceNumber`, `onTap`).

**4b.** Verify no other reference to `SitesMapScreen` remains in this file:
```bash
grep -n SitesMapScreen lib/ui/screens/dive_list_screen.dart
```
Expected: no output. Then delete the import line:
```dart
import 'sites_map_screen.dart';
```
(currently line 20)

- [ ] **Step 5: Run `flutter analyze` and the test suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test test/ui/widgets/dive_tile_test.dart`
Expected: All tests pass (the regression guard is now satisfied because `DiveTile` no longer renders a `SiteMiniMap`).

Run: `flutter test`
Expected: Full suite passes. If anything else fails, investigate — but no other file depends on the mini-map slot per the spec.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/widgets/dive_tile.dart lib/ui/screens/dive_list_screen.dart test/ui/widgets/dive_tile_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): drop mini-map thumbnail from dive list rows

The 56-px SiteMiniMap thumbnail added visual noise without information
value — every row with coords also already shows the site name as text.
Sparkline and text content shift left by ~72 px, giving the site-name
text more headroom on narrow phones. Replaced two scattered mini-map
tests with one regression guard. The AppBar map action that replaces
this navigation affordance lands in the next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add the AppBar "Dive sites map" action to `AppShell`

**Files:**
- Modify: `lib/ui/app_shell.dart` (add `sites_map_screen.dart` import + new IconButton inside `AppBar.actions`)

No automated test — deferred per spec. AppShell stubbing requires Supabase, PowerSync, attachments, and DAO wiring; the manual smoke test in Step 4 below covers AppBar behaviour for this PR.

- [ ] **Step 1: Add the `SitesMapScreen` import**

Open `lib/ui/app_shell.dart`. Near the existing `import 'screens/dive_list_screen.dart';` line (currently line 39), add:

```dart
import 'screens/sites_map_screen.dart';
```

Keep the import block alphabetically sorted with the other `screens/` imports if the file follows that convention. Current order around lines 39-42:
```dart
import 'screens/dive_list_screen.dart';
import 'screens/equipment/equipment_landing_screen.dart';
import 'screens/import_screen.dart';
import 'screens/settings_screen.dart';
```

The new import goes after `import_screen.dart` and before `settings_screen.dart`:
```dart
import 'screens/dive_list_screen.dart';
import 'screens/equipment/equipment_landing_screen.dart';
import 'screens/import_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sites_map_screen.dart';
```

- [ ] **Step 2: Insert the IconButton before the Settings action**

Open `lib/ui/app_shell.dart`. Locate the `AppBar` constructor inside `build()` (currently lines 240-267). The current `actions` list looks like:

```dart
        actions: [
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    // ... constructor args
                  ),
                ));
              },
            ),
        ],
```

Insert a new entry BEFORE the existing `if (_currentIndex == 0) IconButton(...Settings...)` so the actions list becomes:

```dart
        actions: [
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
          if (_currentIndex == 0)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    // ... existing args unchanged
                  ),
                ));
              },
            ),
        ],
```

Do NOT modify the SettingsScreen IconButton — leave its existing constructor arguments untouched. The new IconButton goes immediately above it, both with the same `if (_currentIndex == 0)` guard.

- [ ] **Step 3: Run `flutter analyze` and the test suite**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: Full suite passes. No test directly exercises AppShell's AppBar actions, but the suite must still be clean after the change.

- [ ] **Step 4: Manual smoke test**

Run the app: `flutter run -d macos` (or any available device).

Verify:
1. The Dive list rows no longer show a left-side map thumbnail. The sparkline appears at the left edge (after the colored mode-border) instead of after a 72-px gap.
2. The top-right AppBar on the Dives tab shows TWO icons: a map outline icon, then the existing settings cog.
3. Tapping the map icon opens `SitesMapScreen`. The map fits the bounds of all sites in the database (or shows a single point at z=11 if there's only one, or the empty-world view at z=2 if there are none).
4. Tapping the Settings cog still opens `SettingsScreen` as before.
5. Switch to Import / Equipment / Settings tabs — BOTH the map and Settings icons disappear from the AppBar (both are gated by `_currentIndex == 0`).
6. Switch back to Dives — both icons reappear.

If any step fails, do NOT commit. Investigate and fix in this task before proceeding.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/app_shell.dart
git commit -m "$(cat <<'EOF'
feat(ui): AppBar map action opens SitesMapScreen from the dive list

Completes Track 3. The "Dive sites map" button appears on the Dives tab
only, immediately before the Settings cog. SitesMapScreen called with
null coords already fits all sites in view via its existing
CameraFit.bounds(LatLngBounds.fromPoints(points)) path, so no
SitesMapScreen change is needed.

No automated test for the AppBar action — AppShell wiring (Supabase,
PowerSync, attachments) makes test stubbing heavy. Manual smoke test
covered: icon appears only on Dives tab, opens fitted SitesMapScreen,
disappears on other tabs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Definition of done

After Task 2 commits:
1. `flutter analyze` reports zero issues.
2. `flutter test` passes the full suite.
3. Manual smoke test (Task 2, Step 4) passes on macOS.
4. Two commits land on `main`:
   - `feat(ui): drop mini-map thumbnail from dive list rows`
   - `feat(ui): AppBar map action opens SitesMapScreen from the dive list`
