# GF stats + Information tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Display Shearwater's per-sample GF99 as Max GF / Surface GF on Dive Detail, label the Information-tab star rows with their polarity pairs (Subsurface convention), and surface read-only Water type + Atm. pressure on the Information tab from existing Dive fields.

**Architecture:** Parser extracts GF99 from sample byte 16; SampleSet gains `gf99Percent`; codec round-trips it with a missing-column-tolerant decode for old blobs; UI reads it via `max()` + last-value and shows it conditionally. Information tab gains caption pairs on each star row and two display-only environment rows.

**Reference spec:** `docs/superpowers/specs/2026-05-11-gf-stats-and-info-tab-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/shearwater/parser/parsed_dive.dart` | Modify | Add `int gf99` to `DiveSample`. |
| `lib/shearwater/parser/dive_parser.dart` | Modify | Extract `data[offset + pnfOffset + 16]` into the new field; default 0 for `logRecordAveloSample` and Predator-flavour records. |
| `lib/shearwater/parser/dive_converter.dart` | Modify | Pack each sample's GF99 into the columnar `SampleSet.gf99Percent`. |
| `lib/data/models/sample_set.dart` | Modify | Add `final Float32List gf99Percent`. |
| `lib/data/sample_codec/sample_codec.dart` | Modify | `encode` writes `'gf99'`; `decode` reads if present, else zero-fills. |
| `lib/ui/screens/dive_detail_screen.dart` | Modify | Add `_gfCell(maxGf, surfaceGf, theme)`; insert into the stats row when `max(gf99) > 0`. |
| `lib/ui/widgets/dive_information_section.dart` | Modify | Add subtitle pairs (Bad↔Good etc.) on star rows; add Water type + Atm. pressure read-only rows. Constructor takes the `Dive`. |
| `test/shearwater/dive_parser_gf99_test.dart` | Create | Fixture-driven offset verification. |
| `test/data/sample_codec/sample_codec_test.dart` | Modify | Add gf99 round-trip + missing-column tolerance. |
| `test/ui/widgets/dive_information_section_test.dart` | Modify | Subtitle pair visibility, water type + atm pressure rows. |
| `test/ui/screens/dive_detail_screen_test.dart` | Modify | GF cell renders when gf99 has data; hidden when zero. |

---

## Task 1: Verify the GF99 byte offset against a real Petrel 3 fixture

The spec assumes GF99 lives at byte 16 of each `logRecordDiveSample`. Before touching production code we prove it with a one-off test that loads an existing fixture, prints what byte 16 looks like across the samples, and compares against the dive's known surfacing GF. This is investigation, not TDD — we throw the test away once the offset is confirmed.

**Files:**
- Create: `test/shearwater/_gf99_offset_probe.dart` (delete after Task 2 lands)

- [ ] **Step 1: Pick a fixture**

```bash
ls test/fixtures/shearwater/ | head -20
```

Choose any `.bin` from a Petrel 3 (or any Shearwater) where you know the diver's surface GF (the user can confirm from a Subsurface screenshot if needed; otherwise we'll trust the value the test prints and cross-check it visually against the dive's known surfacing trace).

- [ ] **Step 2: Write a probe test that parses + dumps byte 16**

```dart
import 'dart:io';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe byte 16 of each sample on a Petrel 3 fixture', () {
    final bytes = File('test/fixtures/shearwater/<chosen>.bin').readAsBytesSync();
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    final dive = parser.parse(bytes);
    // Print last 20 samples + their raw byte 16.
    for (var i = dive.samples.length - 20; i < dive.samples.length; i++) {
      // We can't see byte 16 from outside the parser yet, so the probe
      // patches dive_parser.dart locally to print(`gf99=${data[offset + 16 + pnfOffset]}`)
      // and reads that side-channel here. Crude but it's a 5-minute probe.
    }
  });
}
```

Crude side-channel: add a `print` inside `dive_parser.dart`'s sample loop temporarily and run the probe. **Revert the print before Task 2's commit.**

- [ ] **Step 3: Verify**

Expected behaviour at byte 16:
- Values rise during the dive, peak near the deepest deco-stop window, decay toward the surface.
- Surfacing value typically 20–80% for a well-paced CCR ascent.
- All-zero across the dive on early Predator / Avelo samples — that's fine, those don't log GF.

If byte 16 doesn't behave like a GF: try byte 17 (Subsurface's libdc might disagree with my memory) or read libdc's `shearwater_petrel.c` directly. Update the spec's offset before continuing.

- [ ] **Step 4: Commit the probe (so it's in git for posterity)**

```bash
git add test/shearwater/_gf99_offset_probe.dart
git commit -m "test: probe Shearwater sample byte 16 for GF99 offset verification

Throwaway probe. Confirms (or refutes) the spec's assumption that GF99
lives at offset 16 of each dive sample record on Petrel 3. Delete this
file after Task 2 ships the real parser support.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Parser extracts GF99 into `DiveSample`

**Files:**
- Modify: `lib/shearwater/parser/parsed_dive.dart` — `DiveSample`
- Modify: `lib/shearwater/parser/dive_parser.dart` — sample loop
- Test: `test/shearwater/dive_parser_gf99_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Petrel 3 sample carries GF99 from byte offset 16', () {
    final bytes = File('test/fixtures/shearwater/<chosen>.bin').readAsBytesSync();
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    final dive = parser.parse(bytes);
    // Surfacing GF99 should be > 0 and < 200.
    final surfacing = dive.samples.last.gf99;
    expect(surfacing, greaterThan(0));
    expect(surfacing, lessThan(200));
    // Max GF should not exceed 200.
    final maxGf = dive.samples.map((s) => s.gf99).reduce(
        (a, b) => a > b ? a : b);
    expect(maxGf, lessThan(200));
  });
}
```

(Use whatever fixture you confirmed in Task 1. Hard-code the surfacing GF99 from the probe printout instead of `greaterThan(0)` for a stronger assertion.)

Run: `flutter test test/shearwater/dive_parser_gf99_test.dart`
Expected: FAIL — `gf99` not defined on `DiveSample`.

- [ ] **Step 2: Add the field**

In `lib/shearwater/parser/parsed_dive.dart`, add `gf99` to `DiveSample`:

```dart
class DiveSample {
  // ... existing fields ...
  final int gf99;  // Shearwater DC's per-sample gradient factor (percent).
                   // 0 when the DC doesn't log it (Predator-flavour /
                   // Avelo samples).
}
```

Update the constructor to take `required this.gf99`.

- [ ] **Step 3: Extract from the sample loop**

In `lib/shearwater/parser/dive_parser.dart`, find the `DiveSample(...)` construction around line 596. Add:

```dart
gf99: type == logRecordDiveSample
    ? data[offset + pnfOffset + 16]
    : 0,
```

(If Task 1 revealed a different offset, use that instead. If the offset depends on `cache.isPetrel`, gate accordingly.)

- [ ] **Step 4: Run tests**

```bash
flutter test test/shearwater/
flutter analyze
```

Expected: new test PASSES. Existing parser tests may need `gf99: 0` added to `DiveSample(...)` calls in their `_makeSample()` helpers — fix any compile errors. 0 analyzer issues.

- [ ] **Step 5: Delete the Task-1 probe**

```bash
git rm test/shearwater/_gf99_offset_probe.dart
```

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(shearwater): parser extracts per-sample GF99

Byte 16 of each logRecordDiveSample carries the DC's runtime gradient
factor (verified against a real Petrel 3 fixture). Surfaced on
DiveSample as the .gf99 int field, 0 when the DC didn't log it
(Predator-flavour and Avelo records).

Removes the throwaway offset probe from Task 1.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Pack GF99 into `SampleSet` + codec round-trip

**Files:**
- Modify: `lib/data/models/sample_set.dart` — add `Float32List gf99Percent`
- Modify: `lib/shearwater/parser/dive_converter.dart` — pack
- Modify: `lib/data/sample_codec/sample_codec.dart` — encode + decode (missing-column tolerant)
- Test: `test/data/sample_codec/sample_codec_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/data/sample_codec/sample_codec_test.dart`:

```dart
test('gf99 round-trips through encode/decode', () {
  final samples = _sampleSetWith(
    gf99Percent: Float32List.fromList([45.0, 60.0, 72.0]),
    sampleCount: 3,
  );
  final blobs = SampleCodec.encode(samples);
  expect(blobs.containsKey('gf99'), isTrue);
  final decoded = SampleCodec.decode(
    diveId: 'd1', sampleCount: 3, sampleIntervalMs: 10000,
    columns: blobs,
  );
  expect(decoded.gf99Percent.toList(), [45.0, 60.0, 72.0]);
});

test('decode tolerates legacy blobs missing the gf99 column', () {
  final samples = _sampleSetWith(
    gf99Percent: Float32List.fromList([45.0, 60.0]),
    sampleCount: 2,
  );
  final blobs = SampleCodec.encode(samples);
  blobs.remove('gf99'); // simulate a pre-feature stored blob.
  final decoded = SampleCodec.decode(
    diveId: 'd1', sampleCount: 2, sampleIntervalMs: 10000,
    columns: blobs,
  );
  expect(decoded.gf99Percent.length, 2);
  expect(decoded.gf99Percent.every((v) => v == 0.0), isTrue);
});
```

Adapt `_sampleSetWith(...)` to whatever fixture helper exists. If none, add a top-level helper that builds a `SampleSet` with sane zero-filled defaults and only overrides the fields the test cares about.

Run the tests: FAIL — `gf99Percent` not defined.

- [ ] **Step 2: Add the field**

In `lib/data/models/sample_set.dart`:

```dart
/// Shearwater DC's per-sample gradient factor in percent. Zero when
/// the DC didn't log GF (OC dives, Predator-flavour records, pre-
/// feature imports). UI hides the GF stat when all-zero.
final Float32List gf99Percent;
```

Add to the constructor's required list. Update the `SampleSet(...)` calls in test helpers to pass `gf99Percent: Float32List(sampleCount)` (zero-filled) where not specified.

- [ ] **Step 3: Pack GF99 in the converter**

In `lib/shearwater/parser/dive_converter.dart`, find the existing `Float32List` packing loop. Add:

```dart
final gf99 = Float32List(samples.length);
for (var i = 0; i < samples.length; i++) {
  gf99[i] = samples[i].gf99.toDouble();
}
```

Pass `gf99Percent: gf99` to the `SampleSet(...)` constructor.

- [ ] **Step 4: Encode + decode in the codec**

In `lib/data/sample_codec/sample_codec.dart` `encode()` map literal:

```dart
'gf99': ColumnPacker.packFloat32(samples.gf99Percent),
```

In `decode()`, find the section that builds the SampleSet from the columns map. Add a tolerant read:

```dart
final gf99 = columns.containsKey('gf99')
    ? ColumnPacker.unpackFloat32(columns['gf99']!)
    : Float32List(sampleCount);
```

Pass `gf99Percent: gf99` to the SampleSet constructor in `decode()`.

- [ ] **Step 5: Run tests + analyzer**

```bash
flutter test test/data/sample_codec/ test/shearwater/
flutter analyze
```
Expected: 0 analyzer issues, all tests pass. Any test that constructed a `SampleSet(...)` directly may need `gf99Percent: Float32List(n)` — fix each.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: SampleSet carries gf99Percent column

Adds gf99Percent to SampleSet, plumbs it through the parser→converter
path, and round-trips it through SampleCodec. Decode is tolerant of
pre-feature blobs (no gf99 column → zero-filled length-sampleCount
return), so old dives degrade gracefully — the UI hides the GF stat
when the column is all-zero.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: GF stat cell in Dive Detail

**Files:**
- Modify: `lib/ui/screens/dive_detail_screen.dart` — add `_gfCell`
- Test: `test/ui/screens/dive_detail_screen_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
testWidgets('GF stat cell renders when samples carry gf99', (tester) async {
  final samples = _sampleSetWithGf99([0, 10, 30, 65, 78, 45, 14]);
  await tester.pumpWidget(_diveDetailHarness(samples: samples));
  await tester.pumpAndSettle();
  expect(find.text('Max'), findsOneWidget);
  expect(find.text('78%'), findsOneWidget);
  expect(find.text('Surf'), findsOneWidget);
  expect(find.text('14%'), findsOneWidget);
  expect(find.text('(DC)'), findsOneWidget);
});

testWidgets('GF stat cell hidden when gf99 is all-zero', (tester) async {
  final samples = _sampleSetWithGf99([0, 0, 0, 0]);
  await tester.pumpWidget(_diveDetailHarness(samples: samples));
  await tester.pumpAndSettle();
  expect(find.text('Max'), findsNothing);
  expect(find.text('Surf'), findsNothing);
});
```

Run: FAIL — no `_gfCell` exists.

- [ ] **Step 2: Add `_gfCell` and wire it in**

In `lib/ui/screens/dive_detail_screen.dart`, near the existing `_avgMinMaxCell` helper, add:

```dart
Widget _gfCell(int maxGf, int surfaceGf, ThemeData theme) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('GF (DC)',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 2),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Max', style: theme.textTheme.bodySmall),
          const SizedBox(width: 4),
          Text('$maxGf%', style: theme.textTheme.bodyMedium),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Surf', style: theme.textTheme.bodySmall),
          const SizedBox(width: 4),
          Text('$surfaceGf%', style: theme.textTheme.bodyMedium),
        ],
      ),
    ],
  );
}
```

In the `build` of the stats row, compute and insert (after the existing cells, before tanks/stack):

```dart
int? maxGf;
int? surfaceGf;
if (samples.gf99Percent.isNotEmpty) {
  var m = 0;
  for (var i = 0; i < samples.sampleCount; i++) {
    final v = samples.gf99Percent[i].round();
    if (v > m) m = v;
  }
  if (m > 0) {
    maxGf = m;
    surfaceGf = samples.gf99Percent[samples.sampleCount - 1].round();
  }
}
// ... in the cells list:
if (maxGf != null) _gfCell(maxGf, surfaceGf!, theme),
```

- [ ] **Step 3: Run tests + analyzer**

```bash
flutter test test/ui/screens/dive_detail_screen_test.dart
flutter analyze
```
Expected: tests pass, 0 analyzer issues.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(ui): Max GF / Surface GF stat cell on Dive Detail

Reads from SampleSet.gf99Percent. Shows the cell only when the DC
logged GF (max value > 0); OC dives and pre-feature imports show
nothing. Labelled '(DC)' to flag the data source — Phase 3's ZHL-16
replay will replace the source without changing the cell's shape.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Information tab — star subtitle labels

**Files:**
- Modify: `lib/ui/widgets/star_rating.dart` OR `lib/ui/widgets/dive_information_section.dart` — depending on where the cleanest insertion point is. Inspect first; prefer adding `subtitleLeft` / `subtitleRight` parameters to `_ratingRow` in `dive_information_section.dart` so `StarRating` stays generic.
- Test: `test/ui/widgets/dive_information_section_test.dart`

- [ ] **Step 1: Failing test**

```dart
testWidgets('star rows show polarity caption pairs', (tester) async {
  await tester.pumpWidget(_diveInfoHarness());
  await tester.pumpAndSettle();
  // Subsurface convention pairs.
  expect(find.text('Large'), findsOneWidget);
  expect(find.text('Small'), findsOneWidget);
  expect(find.text('Bad'), findsOneWidget);
  expect(find.text('Good'), findsOneWidget);
  expect(find.text('Strong'), findsNWidgets(2));  // current + surge
  expect(find.text('Weak'), findsNWidgets(2));
  expect(find.text('Freezing'), findsOneWidget);
  expect(find.text('Comfy'), findsOneWidget);
});
```

Run: FAIL.

- [ ] **Step 2: Extend `_ratingRow`**

In `lib/ui/widgets/dive_information_section.dart`, change the helper signature:

```dart
Widget _ratingRow(
  String label,
  int? value,
  ValueChanged<int?> onChanged, {
  required String subtitleLeft,
  required String subtitleRight,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        StarRating(value: value, onChanged: onChanged),
        // Caption pair aligned beneath the stars.
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(subtitleLeft,
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(width: 90), // tune to star block width
              Text(subtitleRight,
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ],
    ),
  );
}
```

The exact spacing depends on `StarRating`'s width — if the layout looks off in practice, switch to a `Row` with `mainAxisAlignment: spaceBetween` constrained to the star block width via a `SizedBox`.

Then update the call sites:

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

- [ ] **Step 3: Run tests + analyzer**

```bash
flutter test test/ui/widgets/dive_information_section_test.dart
flutter analyze
```

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(ui): polarity caption pairs under each Information-tab star row

Adds Subsurface-convention labels beneath each star block — Visibility
Bad↔Good, Surface waves Large↔Small, Current/Surge Strong↔Weak, Chill
Freezing↔Comfy. Makes the rating direction self-explanatory instead
of relying on the diver to remember which way is the 'good' side.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Information tab — Water type + Atm. pressure read-only rows

**Files:**
- Modify: `lib/ui/widgets/dive_information_section.dart` — constructor takes Dive; add two read-only rows
- Modify: `lib/ui/screens/dive_detail_screen.dart` (or wherever `DiveInformationSection` is constructed) — pass the dive
- Test: `test/ui/widgets/dive_information_section_test.dart`

- [ ] **Step 1: Failing test**

```dart
testWidgets('water type + atm pressure rows render from Dive fields',
    (tester) async {
  final dive = _testDive(
    waterDensityKgM3: 1000,
    atmosphericPressureMbar: 1003,
  );
  await tester.pumpWidget(_diveInfoHarness(dive: dive));
  await tester.pumpAndSettle();
  expect(find.text('Water type'), findsOneWidget);
  expect(find.text('Fresh — 1.000 g/L'), findsOneWidget);
  expect(find.text('Atm. pressure'), findsOneWidget);
  expect(find.text('1003 mbar'), findsOneWidget);
});

testWidgets('water type maps salt density to "Salt"', (tester) async {
  final dive = _testDive(waterDensityKgM3: 1025, atmosphericPressureMbar: 1013);
  await tester.pumpWidget(_diveInfoHarness(dive: dive));
  await tester.pumpAndSettle();
  expect(find.text('Salt — 1.025 g/L'), findsOneWidget);
});
```

Run: FAIL — section doesn't accept a Dive yet.

- [ ] **Step 2: Constructor + rows**

In `lib/ui/widgets/dive_information_section.dart`:

```dart
class DiveInformationSection extends StatefulWidget {
  final DiveAnnotationsNotifier notifier;
  final Dive dive;
  final double? defaultWaterTempC;

  const DiveInformationSection({
    super.key,
    required this.notifier,
    required this.dive,
    this.defaultWaterTempC,
  });
  // ...
}
```

In `build()`, add the two read-only rows. A small helper:

```dart
String _waterTypeLabel(int densityKgM3) {
  if (densityKgM3 < 1010) return 'Fresh';
  if (densityKgM3 >= 1020) return 'Salt';
  return 'Brackish';
}

Widget _readOnlyRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    ),
  );
}
```

Insert into the build, near the temp row:

```dart
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

- [ ] **Step 3: Update the construction site**

In `dive_detail_screen.dart` (or wherever `DiveInformationSection(...)` is built), pass `dive: widget.dive`.

- [ ] **Step 4: Run tests + analyzer**

```bash
flutter test test/ui/widgets/dive_information_section_test.dart
flutter test test/ui/screens/
flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(ui): Water type + Atm. pressure read-only rows on Information tab

Surfaces the dive-level waterDensityKgM3 and atmosphericPressureMbar
that the Shearwater binary already gives us. Density maps to Fresh /
Brackish / Salt by threshold (< 1010 / 1010–1019 / ≥ 1020) and shows
the raw g/L value alongside. Editable overrides are out of scope —
the DC's values are authoritative for now.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Full-suite verification + push

- [ ] **Step 1: Run everything**

```bash
flutter analyze
flutter test
```
Expected: 0 issues, all green.

- [ ] **Step 2: Manual UI smoke**

Run the app, open a recently-imported dive (Petrel 3 CCR with deco):
- Information tab shows the caption pairs beneath each star row, and the Water type / Atm. pressure rows.
- Dive Detail shows `Max NN% / Surf NN% (DC)`.
Open an older dive (pre-feature):
- GF cell absent.
Open an OC dive (if available):
- GF cell absent.

- [ ] **Step 3: Push**

```bash
git push origin main
```

- [ ] **Step 4: Update memory**

In `/Users/egbert/.claude/projects/-Users-egbert-Dev-CCRLog-ccrlogger/memory/project_next_session_priority.md`, mark Surface GF % as **shipped** and add a Phase 3 follow-up entry: "replace Shearwater DC's GF99 with Subsurface-compatible ZHL-16 replay; the parser's `gf99` field stays for cross-checking."
