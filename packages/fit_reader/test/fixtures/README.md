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
file in place (same layout, same size) and recomputes the CRC:

- every serial number field (file id, device info) became `1000000001`, and
  so did any other 4-byte integer that held the file's original serial;
- every GPS position in the session, lap and record messages was set to its
  invalid marker;
- every field of the user profile message was set to its invalid marker;
- every string in the user profile, device settings, device info and file
  creator messages was zeroed.

The Suunto file has no serial, so it keeps serial 0.

To reproduce, run `dart run tool/anonymise_fit.dart <in.fit> <out.fit>`
from `packages/fit_reader`.

The original, unanonymised files are not in this repository. Never commit
them.
