# GF stats + Information tab — design

**Status:** approved 2026-05-11.

**Owner:** CCRLog UI / parser.

**Context:** After Phase 1 of the Subsurface write-direction sync shipped, the next user-facing priority is showing Surface GF % and Max GF % on the dive detail, plus making the Information tab's star ratings self-explanatory and surfacing the dive-level water type + atmospheric pressure that the Shearwater binary already gives us. The user supplied Subsurface's ENVIRONMENT panel as the visual reference.

## Goals (this session)

1. Display **Max GF (DC)** and **Surface GF (DC)** in Dive Detail's statistics row, computed from Shearwater's per-sample GF99.
2. Add label pairs to Information-tab star ratings: Surface waves `Large ↔ Small`, Visibility `Bad ↔ Good`, Current `Strong ↔ Weak`, Surge `Strong ↔ Weak`, Chill `Freezing ↔ Comfy`.
3. Show **Water type** ("Fresh — 1.000 g/L") and **Atm. pressure** ("1003 mbar") as read-only rows on the Information tab, sourced from the existing `Dive.waterDensity` and `Dive.atmosphericPressureMbar` fields.

## Non-goals (deferred)

- **ZHL-16 tissue replay** for Subsurface-exact Surface GF. Out of scope; Phase 3. We use Shearwater's DC-computed GF99 and label the stat `(DC)` so the source is honest. Replacing this with a Subsurface-compatible replay is a separate future feature.
- Editable water type / atm pressure overrides. The DC's values are authoritative for now; no `DiveAnnotation` additions, no schema migration.
- Surfacing GF for OC dives. The DC only computes GF in CCR/Buhlmann modes; OC dives will show `—` for GF.
- Backfilling GF for already-imported dives. New dives parsed after this change carry GF99; existing dives show `—` until re-imported.

## Architecture

### Per-sample GF99 extraction

Shearwater's sample record carries the DC's runtime GF99 as a single byte at offset 16 (verified against libdc's `shearwater_petrel.c`). The value is an unsigned percent (0–~150, occasionally higher on aggressive ascents). Petrel/Perdix/Peregrine all emit it in the same slot; older Predator-flavour records don't, and we treat the field as zero in that case.

```
dive_parser.dart  (sample loop)
  → DiveSample.gf99 : int        (raw percent, 0 when DC didn't log it)

dive_converter.dart  (DiveSample → SampleSet packing)
  → SampleSet.gf99Percent : Float32List   (raw percent as double)
```

### Codec backward-compat

The columnar sample blob currently has 13 named columns. Adding `gf99` means:

- `SampleCodec.encode()` writes the new `'gf99'` column.
- `SampleCodec.decode()` reads `'gf99'` if present, else returns `Float32List(sampleCount)` (zero-filled). Old blobs decode without errors.

The UI treats an all-zero `gf99Percent` as "no GF data" and hides the GF stat cell. This keeps OC dives clean and gracefully handles pre-existing dives — re-importing populates GF for any dive the user cares enough to refresh.

### Statistics display

`dive_detail_screen.dart` builds its stats row from a list of cells (line ~729). Add a new `_gfCell` factory:

```
Max  78%
Surf 14%      ← two-line cell, `(DC)` caption underneath
```

The cell is hidden when `max(gf99Percent) == 0`. Surface GF = `gf99Percent[sampleCount-1]`; Max GF = `max(gf99Percent[0..sampleCount-1])`.

### Information tab

`dive_information_section.dart` currently renders each star row via `_ratingRow(label, value, onChanged)`. Extend the helper:

```dart
_ratingRow(
  'Visibility',
  _n.visibility, _n.setVisibility,
  subtitleLeft: 'Bad', subtitleRight: 'Good',
)
```

The subtitle pair renders as a thin caption row beneath the stars, left- and right-aligned to the star block (not the full row width — so the words sit beneath the first and last star). Star polarity convention:

| Row             | Left (1 star) | Right (5 stars) |
|-----------------|---------------|-----------------|
| Surface waves   | Large         | Small           |
| Visibility      | Bad           | Good            |
| Current         | Strong        | Weak            |
| Surge           | Strong        | Weak            |
| Chill           | Freezing      | Comfy           |

These match Subsurface's UI exactly, including the inverted-feeling polarity on Current/Surge ("more stars = less of the bad thing").

Above or below the temperature row, render two new display-only rows:

- **Water type** — formatted from `Dive.waterDensity` (kg/m³). Heuristic: `< 1010` → "Fresh", `≥ 1020` → "Salt", in between → "Brackish". Always also show the raw `g/L` value (e.g. `Fresh — 1.000 g/L`).
- **Atm. pressure** — `${Dive.atmosphericPressureMbar} mbar`.

These are non-editable. The widget receives the `Dive` instance (currently only `defaultWaterTempC` is passed) — extend the constructor to accept the full Dive.

## Tests required before merging

1. **Parser GF99 extraction.** A fixture-driven test that loads an existing Petrel 3 `.bin` and asserts `samples.last.gf99` matches a known value from libdc's CSV output. If the offset is wrong, this fails loudly and the implementation pivots to the correct offset before anything downstream.
2. **Codec round-trip.** Encode a SampleSet with non-zero `gf99Percent`, decode, assert equality. Encode without writing the `gf99` column (legacy path), decode, assert the field is zero-filled length-`sampleCount`.
3. **DiveDetailScreen widget test.** Renders the GF cell when `gf99Percent` has data; hides it when all-zero.
4. **DiveInformationSection widget test.** Asserts the subtitle labels are visible under each star row with the correct text. Asserts the Water type and Atm. pressure rows render the right strings for `waterDensity=1000`/`atmosphericPressureMbar=1003`.

`flutter test test/shearwater/ test/data/sample_codec/ test/ui/widgets/dive_information_section_test.dart test/ui/screens/dive_detail_screen_test.dart` must pass before merging.

## Code changes (anticipated)

- `lib/shearwater/parser/dive_parser.dart` — extract byte 16 of each dive-sample record.
- `lib/shearwater/parser/parsed_dive.dart` — add `int gf99` to `DiveSample`.
- `lib/shearwater/parser/dive_converter.dart` — pack `gf99` into the columnar `SampleSet`.
- `lib/data/models/sample_set.dart` — add `Float32List gf99Percent`.
- `lib/data/sample_codec/sample_codec.dart` — encode/decode `gf99` with missing-column tolerance.
- `lib/ui/screens/dive_detail_screen.dart` — `_gfCell` factory + insert into the stats row, hidden when no data.
- `lib/ui/widgets/dive_information_section.dart` — extend `_ratingRow` with subtitle pairs, add Water type + Atm. pressure read-only rows; constructor takes the `Dive`.
- Test files mirroring the touched code paths.

The mapper / sync layers do not change — GF is a read-side display feature; CCRLog doesn't push GF99 to Subsurface (Subsurface computes its own from replay).

## Phase 3 follow-up captured here so the next session has breadcrumbs

When tissue replay lands, the GF cell switches from `(DC)` to the replayed value and the `(DC)` caption goes away. The parser's `gf99` field stays — it's still useful for cross-checking the replay's correctness, and the DC's number is the user's reference if they're cross-checking against the device on the surface.
