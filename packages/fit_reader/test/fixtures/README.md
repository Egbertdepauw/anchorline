# FIT fixtures

Real dive files, anonymised, used by `fixtures_test.dart` and
`reader_output_guard_test.dart`.

| File | Device | Origin |
| --- | --- | --- |
| `garmin_mk1_ccr_2023-08-17.fit` | Garmin Descent Mk1, CCR dive | `dives/garmin_2023-08-17-08-51-59.fit` |
| `garmin_mk1_ccr_2023-10-21.fit` | Garmin Descent Mk1, CCR dive | `dives/garmin_2023-10-21-12-13-38.fit` |
| `suunto_ocean_nitrox.fit` | Suunto Ocean, open-circuit nitrox dive | `dives/suunto_ocean_nitrox.fit` |

## Where they come from

All three come from the Subsurface repository,
`github.com/subsurface/subsurface`, folder `dives/`, at commit `1cf5569`.
Subsurface is licensed GPL-2.0, and these files were added there on
2026-10-31. The paths in the table are the paths in that repository.

## Anonymisation

Each file was passed through `tool/anonymise_fit.dart`, which patches the
file in place (same layout, same size) and recomputes the CRC. What it does:

- clears the serial: every serial number field (file id, device info) became
  `1000000001`, and so did any other 4-byte integer equal to the file's
  original serial;
- clears the position fields Subsurface declares (session, lap and record
  messages), setting them to the invalid marker;
- clears every field of the user profile message (set to the invalid marker);
- zeroes every string in messages 3, 2, 23 and 49 (user profile, device
  settings, device info, file creator).

What it does NOT do:

- it does not sweep positions by value, so a position in a field Subsurface
  does not declare stays;
- it does not clear strings in other messages;
- it does not inspect developer fields or repeated field numbers;
- it does not touch heart rate or other physiological messages.

Review its output by hand before committing any file that isn't already
public.

The Suunto file has no serial, so it keeps serial 0.

To reproduce, run `dart run tool/anonymise_fit.dart <in.fit> <out.fit>`
from `packages/fit_reader`.

The original, unanonymised files are not in this repository. Never commit
them.
