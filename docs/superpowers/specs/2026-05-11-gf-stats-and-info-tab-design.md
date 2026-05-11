# Information tab cleanup + GF deferral — design

**Status:** approved 2026-05-11.

**Owner:** CCRLog UI.

**Context:** After Phase 1 of the Subsurface write-direction sync shipped, the next user-facing priorities were Surface GF % / Max GF % on the dive detail and Information-tab clarity (star polarity labels + visible Water type + Atm. pressure).

During scoping we verified against a real Petrel 3 fixture (`dive_711.bin`, 600 samples, full deco profile) that **Shearwater binaries do not log a per-sample GF99.** Every unused byte in the sample record is either a constant flag, a tank-pressure sentinel, or already-extracted state (setpoint at byte 18). libdc's parser confirms: it only extracts `gfLow` / `gfHigh` from the dive plan. The original "ship Shearwater's GF99 quickly" path doesn't exist — Subsurface computes Surface GF entirely via ZHL-16 tissue replay.

This spec is what's actually achievable in this session, plus a clean breadcrumb for the deferred work.

## Goals (this session)

1. Add polarity caption pairs under each Information-tab star row, matching Subsurface's convention: Surface waves `Large ↔ Small`, Visibility `Bad ↔ Good`, Current `Strong ↔ Weak`, Surge `Strong ↔ Weak`, Chill `Freezing ↔ Comfy`.
2. Show **Water type** (e.g. "Fresh — 1.000 g/L") and **Atm. pressure** (e.g. "1003 mbar") as read-only rows on the Information tab, sourced from the existing `Dive.waterDensity` and `Dive.atmosphericPressureMbar` fields.

## Deferred to Phase 3 (separate session, multi-day)

- **Surface GF % and Max GF % on Dive Detail.** Requires porting Subsurface's ZHL-16 tissue replay: 16 compartments with their a/b coefficients, gas-switching, M-value computation, sample-by-sample integration. Output: per-sample GF, Surface GF (at last sample), Max GF (across the dive), and tissue saturation traces. CLAUDE.md flags this as Phase 3 work — keep it Phase 3.
- The same replay enables the "tissue compartment replay, bailout-from-any-point" feature already on the Phase 3 list.

## Architecture (this session)

`dive_information_section.dart` is the only production file touched:

1. **Star subtitle labels.** Extend the existing `_ratingRow` helper to take `subtitleLeft` / `subtitleRight` strings, render them as a thin caption row beneath the stars aligned to the first and last star.
2. **Water type row.** Add a small `_readOnlyRow(label, value)` helper. The water-type label is derived from `Dive.waterDensityKgM3` via threshold: `< 1010` → "Fresh", `≥ 1020` → "Salt", in between → "Brackish". The g/L value is always shown alongside (e.g. "Fresh — 1.000 g/L"), so a diver checking salinity gets the number too.
3. **Atm. pressure row.** Same helper, value is `${Dive.atmosphericPressureMbar} mbar`.
4. **Constructor change.** `DiveInformationSection` currently receives `DiveAnnotationsNotifier` + `defaultWaterTempC`. Add a `final Dive dive` required parameter. Update the construction site in `dive_detail_screen.dart` to pass `dive: widget.dive`.

No schema migration. No new annotation fields. No editable overrides — the DC's values are authoritative.

## Tests

- **Widget test for label pairs.** Pumps the section, asserts `Large` / `Small` / `Bad` / `Good` / `Strong` (×2) / `Weak` (×2) / `Freezing` / `Comfy` are all visible.
- **Widget test for water-type row.** `waterDensityKgM3 = 1000` → "Fresh — 1.000 g/L". `waterDensityKgM3 = 1025` → "Salt — 1.025 g/L".
- **Widget test for atm-pressure row.** `atmosphericPressureMbar = 1003` → "1003 mbar".

`flutter test test/ui/widgets/dive_information_section_test.dart` covers all three. No parser, codec, or DB tests needed since no model code changes.

## Code changes

- `lib/ui/widgets/dive_information_section.dart` — extend `_ratingRow` with subtitle pair; add `_readOnlyRow` helper; add water + atm rows; constructor takes `Dive`.
- `lib/ui/screens/dive_detail_screen.dart` — pass `dive: widget.dive` to `DiveInformationSection`.
- `test/ui/widgets/dive_information_section_test.dart` — new assertions.

## Phase 3 breadcrumb (captured here so the next session has context)

The deferred GF work is its own session with its own brainstorming. Starting points:
- Subsurface source: `core/deco.cpp` (ZHL-16 tissue model), `core/divelist.cpp` (`get_surface_gf` or similar), `core/profile.cpp` (per-sample replay).
- Subsurface's "crosshair legend" shows the value the user wants — that's the visual confirmation reference.
- Output should produce per-sample GF as a `Float32List` parallel to existing sample columns, packed via `SampleCodec` (the codec already has a missing-column-tolerant decode pattern from Phase 1; reuse it).
- The dive-detail stats cell should label the source: "(replay)" once we ship it, or "(ZHL-16C 50/95)" if we want to be specific about the model variant.
