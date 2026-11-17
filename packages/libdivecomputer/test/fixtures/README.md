# Fixtures

## `petrel3_expected.json`

What the app's own Dart Shearwater reader gives for the eight dives of the
Petrel 3 download that the tests replay (the trace is
`test/fixtures/raw/subsurface2.combined.txt` at the repository root). Per dive:
start time (UTC epoch seconds), duration, max depth, gas mixes, sample count and
interval, and the depth, temperature, voted ppO2 and setpoint arrays.

It was made once, from the repository root, with the generator in the app's
tests (`ShearwaterDiveParser` plus `DiveConverter.convert` over
`test/fixtures/dives/dive_711.bin` to `dive_718.bin`, the same dives the trace
holds):

```sh
GENERATE_PETREL3_EXPECTED=1 flutter test test/tool/generate_petrel3_expected_test.dart
```

The generator stays in the repository as a test that is skipped unless
`GENERATE_PETREL3_EXPECTED` is set. Regenerate the file only when the Dart
reader's output changes on purpose.

`petrel3_cross_check_test.dart` compares libdivecomputer's output on a replay of
that trace against this file, and `output_guard_test.dart` pins the mapping's
output for each `kLibdcParserVersion`.

## How a family becomes "checked"

A family that is not Shearwater is "Not yet tested by us" until all of these
are done:

1. A real recording of a download from that family is made (the app's
   "share recording" on a real computer) and anonymised the way #191 did it:
   serial number, dates and position removed or replaced.
2. Its expected output is compared by a person with what the computer itself
   (its display or its own app) or Subsurface shows for the same dives, and
   written down as a JSON file here, like `petrel3_expected.json`.
3. A replay test like `petrel3_cross_check_test.dart` is added for it, with the
   differences it finds documented in the test's doc comment.
4. The family and the fixture's name go into `kCheckedLibdcFamilies`.
