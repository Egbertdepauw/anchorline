# Information tab cleanup — Implementation Plan

> Originally bundled with Surface GF / Max GF; Task 1 verified that Shearwater binaries don't carry per-sample GF99, so the GF work was deferred to Phase 3 (see the spec's deferred section). This plan is just the Information tab.

**Goal:** Add polarity caption pairs (Bad↔Good etc.) under each star row on the Information tab, and surface Water type + Atm. pressure as read-only rows from the dive-level fields the Shearwater binary already gives us.

**Reference spec:** `docs/superpowers/specs/2026-05-11-gf-stats-and-info-tab-design.md`

---

## Task 1: Information tab — caption pairs + water/atm rows

**Files:**
- Modify: `lib/ui/widgets/dive_information_section.dart`
- Modify: `lib/ui/screens/dive_detail_screen.dart` (one-line constructor update)
- Test: `test/ui/widgets/dive_information_section_test.dart`

### Step 1: Write the failing tests

In `test/ui/widgets/dive_information_section_test.dart`, add inside the existing main():

```dart
testWidgets('star rows show polarity caption pairs', (tester) async {
  await tester.pumpWidget(_harness(dive: _testDive()));
  await tester.pumpAndSettle();
  expect(find.text('Large'), findsOneWidget);
  expect(find.text('Small'), findsOneWidget);
  expect(find.text('Bad'), findsOneWidget);
  expect(find.text('Good'), findsOneWidget);
  expect(find.text('Strong'), findsNWidgets(2)); // current + surge
  expect(find.text('Weak'), findsNWidgets(2));
  expect(find.text('Freezing'), findsOneWidget);
  expect(find.text('Comfy'), findsOneWidget);
});

testWidgets('water type row renders Fresh for density 1000', (tester) async {
  await tester.pumpWidget(_harness(
    dive: _testDive(waterDensityKgM3: 1000, atmosphericPressureMbar: 1003),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Water type'), findsOneWidget);
  expect(find.text('Fresh — 1.000 g/L'), findsOneWidget);
});

testWidgets('water type row renders Salt for density 1025', (tester) async {
  await tester.pumpWidget(_harness(
    dive: _testDive(waterDensityKgM3: 1025),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Salt — 1.025 g/L'), findsOneWidget);
});

testWidgets('atm pressure row renders mbar value', (tester) async {
  await tester.pumpWidget(_harness(
    dive: _testDive(atmosphericPressureMbar: 1003),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Atm. pressure'), findsOneWidget);
  expect(find.text('1003 mbar'), findsOneWidget);
});
```

Adapt `_harness` and `_testDive` to whatever the test file already has — if no harness exists, build a minimal one that wraps `DiveInformationSection` in a `MaterialApp` + Scaffold and provides a stub `DiveAnnotationsNotifier`.

Run: `flutter test test/ui/widgets/dive_information_section_test.dart` — expect failures.

### Step 2: Extend `_ratingRow` with subtitle pair

In `lib/ui/widgets/dive_information_section.dart`, change `_ratingRow` to take two subtitle strings and render them as a caption row aligned under the star block. The exact layout depends on `StarRating`'s rendered width — use a `SizedBox` to match it, or wrap the stars + captions in a single `Column` so the caption row inherits the star block's width.

Update each call site:

```dart
_ratingRow('Visibility', _n.visibility, _n.setVisibility,
    subtitleLeft: 'Bad', subtitleRight: 'Good'),
_ratingRow('Surface waves', _n.wavesize, _n.setWavesize,
    subtitleLeft: 'Large', subtitleRight: 'Small'),
_ratingRow('Current', _n.current, _n.setCurrent,
    subtitleLeft: 'Strong', subtitleRight: 'Weak'),
_ratingRow('Surge', _n.surge, _n.setSurge,
    subtitleLeft: 'Strong', subtitleRight: 'Weak'),
_ratingRow('Chill', _n.chill, _n.setChill,
    subtitleLeft: 'Freezing', subtitleRight: 'Comfy'),
```

### Step 3: Add `Dive` parameter + water/atm rows

Add `final Dive dive;` to `DiveInformationSection`'s constructor. Update the construction site in `dive_detail_screen.dart` to pass `dive: widget.dive`.

Add the rendering helper + two rows to `build()`, sited near the existing temperature row:

```dart
String _waterTypeLabel(int densityKgM3) {
  if (densityKgM3 < 1010) return 'Fresh';
  if (densityKgM3 >= 1020) return 'Salt';
  return 'Brackish';
}

Widget _readOnlyRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(children: [
    SizedBox(width: 110, child: Text(label)),
    Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
  ]),
);

// In build():
_readOnlyRow(
  'Water type',
  '${_waterTypeLabel(widget.dive.waterDensityKgM3)}'
  ' — ${(widget.dive.waterDensityKgM3 / 1000).toStringAsFixed(3)} g/L',
),
_readOnlyRow(
  'Atm. pressure',
  '${widget.dive.atmosphericPressureMbar} mbar',
),
```

### Step 4: Run tests + analyzer

```bash
flutter test test/ui/widgets/dive_information_section_test.dart
flutter analyze
flutter test
```
Expected: new tests pass, 0 analyzer issues, all 638+ existing tests still green.

### Step 5: Commit + push

```bash
git add lib/ui/widgets/dive_information_section.dart \
        lib/ui/screens/dive_detail_screen.dart \
        test/ui/widgets/dive_information_section_test.dart
git commit -m "$(cat <<'EOF'
feat(ui): polarity captions + Water type + Atm. pressure on Information tab

Star rows now show Subsurface-convention captions under the stars
(Visibility Bad↔Good, Surface waves Large↔Small, Current/Surge
Strong↔Weak, Chill Freezing↔Comfy) so the rating direction is
self-explanatory.

Adds two read-only rows surfacing the dive-level waterDensityKgM3 and
atmosphericPressureMbar from the Shearwater binary: water type maps
to Fresh / Brackish / Salt via density threshold, displayed alongside
the raw g/L value; atm. pressure shows mbar directly.

Surface GF % / Max GF % was bundled with this work originally, but
verification against a real Petrel 3 fixture proved Shearwater
binaries don't carry per-sample GF99 — Subsurface computes Surface GF
via ZHL-16 tissue replay. GF moves to its own Phase 3 session.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

### Step 6: Update memory

In `/Users/egbert/.claude/projects/-Users-egbert-Dev-CCRLog-ccrlogger/memory/project_next_session_priority.md`:
- Mark Information tab cleanup as done.
- Promote ZHL-16 tissue replay (Surface GF + Max GF + tissue compartments) as the **Phase 3 starting point** with the spec's breadcrumbs (Subsurface source files, suggested output shape via SampleCodec's missing-column-tolerant decode pattern).
