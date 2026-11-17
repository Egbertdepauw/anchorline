# Third-party code, data and assets

Anchorline builds on other people's work. This page lists what was taken
from other projects, who holds the copyright, and under which licence it
is used. For how Anchorline itself is licensed, see
[`LICENSING.md`](LICENSING.md).

## libdivecomputer: the Shearwater dive log parser

The Shearwater dive log parser is a Dart translation of libdivecomputer's
Shearwater code. Without libdivecomputer it would not exist.

- **Project:** libdivecomputer, <https://www.libdivecomputer.org>,
  <https://github.com/libdivecomputer/libdivecomputer>
- **Copyright:** Copyright (C) 2012–2013 Jef Driesen, with contributions
  to the parser by Dirk Hohndel, Anton Lundin and others (see the
  libdivecomputer history)
- **Licence:** GNU Lesser General Public License, version 2.1 or (at your
  option) any later version. The text is in
  [`LICENSES/LGPL-2.1.txt`](LICENSES/LGPL-2.1.txt).
- **Translated from:** `src/shearwater_predator_parser.c`,
  `src/shearwater_common.c` and `.h`, and `src/shearwater_petrel.c`, as
  of libdivecomputer's git master in spring 2026
- **Files in Anchorline:** these keep libdivecomputer's licence, and each
  carries its copyright and licence notice:
  - `lib/shearwater/parser/dive_parser.dart`
  - `packages/subsurface_core/lib/shearwater/parser/constants.dart`
  - `lib/shearwater/parser/decompressor.dart`
  - `packages/subsurface_core/lib/shearwater/parser/hardware.dart`
- **Changes and improvements:** changes to these files stay public under
  the same licence, and improvements that would help libdivecomputer are
  shared back with its community. See
  [`CONTRIBUTING.md`](CONTRIBUTING.md#code-from-libdivecomputer).
- **Findings for libdivecomputer:** what Anchorline has found that
  libdivecomputer could use, with the evidence, is in
  [`docs/upstream/libdivecomputer-findings.md`](docs/upstream/libdivecomputer-findings.md).
  The patches in `docs/upstream/patches/` change libdivecomputer itself
  and are under its licence. The tools in `docs/upstream/tools/` are
  under the LGPL version 2.1 or later as well.

The Bluetooth download code in `lib/shearwater/ble/` and
`lib/shearwater/parser/slip_decoder.dart` is Anchorline's own
implementation. It used libdivecomputer's `shearwater_common.c` and
`shearwater_petrel.c` as its reference for the Shearwater protocol.

## libdivecomputer: the linked library

Anchorline links libdivecomputer itself, to download from dive computers
of other manufacturers over Bluetooth and to read their logs. The library
is built from source, as a dynamic library, in every build.

- **Project:** libdivecomputer, <https://www.libdivecomputer.org>,
  <https://github.com/libdivecomputer/libdivecomputer>
- **Licence:** GNU Lesser General Public License, version 2.1 or (at your
  option) any later version (`aes.c` is public domain). The text ships
  with the source in
  [`packages/libdivecomputer/third_party/libdivecomputer/COPYING`](packages/libdivecomputer/third_party/libdivecomputer/COPYING)
  and is listed on the in-app licence page.
- **Pinned commit:** `0194f09d91c850b18480e73a9fa7b276c926043c`, recorded
  in [`packages/libdivecomputer/UPSTREAM`](packages/libdivecomputer/UPSTREAM)
- **Source and patches:** the full source is in
  [`packages/libdivecomputer/third_party/libdivecomputer/`](packages/libdivecomputer/third_party/libdivecomputer/).
  It always equals the pinned commit plus the patches in
  [`packages/libdivecomputer/patches/`](packages/libdivecomputer/patches/).
  Every patch is also sent to libdivecomputer's maintainer.
- **Copyright:** with Jef Driesen, the author of most of the library, whose
  permission to use it in Anchorline covers his code in the whole library.
  Other authors keep the copyright on their code. Their names are in the
  source headers. They include Linus Torvalds (Suunto EON Steel, Core and
  D5, Deepblu Cosmiq, Oceans S1), Jan Matoušek (Divesoft Freedom and
  Liberty), Anton Lundin (the OSTC 3 and newer download side, `hw_ostc3.c`; the parser is Jef's), Janice McLaughlin (Aqualung
  i330R, Apeks DSX), Ryan Gardner (Deep Six, Crest, Genesis, Scorpena),
  John Van Ostrand (Cochran) and David Carron (McLean).
- **Which families ship:** every build carries every family, the store
  builds as well as the website builds. If an author asks for a family to
  be left out of the store builds, it goes on the leave-out list, the
  `leave_out_families` define in the `hooks: user_defines` block of
  [`pubspec.yaml`](pubspec.yaml). The list is empty today.
- **Anchorline's own C layer** in `packages/libdivecomputer/native/` is
  licensed under the LGPL version 2.1 or later as well.

## Subsurface: decompression constants and file format

- **Project:** Subsurface, <https://subsurface-divelog.org>,
  <https://github.com/subsurface/subsurface>, GNU GPL version 2
- **Decompression constants:** the ZHL-16C tissue compartment values in
  `lib/analysis/deco/tissue_model.dart` were taken from Subsurface's
  `core/deco.cpp`. They are Bühlmann's published ZHL-16C parameters.
- **File format:** the Subsurface Cloud reader and writer
  (`lib/sync/subsurface_git/`, `packages/subsurface_core/`) is
  Anchorline's own code. It reads and writes Subsurface's git storage
  format so that the two programs can share dives; no Subsurface source
  code was copied.
- **Bluetooth facts:** the GATT service and characteristic UUIDs that
  dive computers expose over Bluetooth LE, the characteristics to skip,
  and the credit numbers for the Telit and u-blox serial bridges (254
  credits at connect, 32 left as the low-water mark, 222 per refill) in
  `lib/devices/libdc/libdc_ble_profile.dart` and
  `lib/devices/libdc/ble_central_libdc_link.dart` are facts taken from
  Subsurface's `core/qt-ble.cpp`. The code is Anchorline's own; no
  Subsurface source code was copied.

## Garmin and FIT

Anchorline imports dives from FIT files written by Garmin and Suunto
devices. The reader is in `packages/fit_reader/` and is Anchorline's own
code.

- **No Garmin code:** no Garmin FIT SDK code, port of it, or
  `Profile.xlsx` table is in Anchorline. Garmin's FIT SDK licence forbids
  copyleft use. The facts about how the files are laid out come from
  Subsurface's Garmin parser and from real files.
- **Test fixtures:** `packages/fit_reader/test/fixtures/` holds two Garmin
  Descent Mk1 dives and a Suunto Ocean dive. They come from Subsurface's
  test data (<https://github.com/subsurface/subsurface> at commit
  `1cf5569`, folder `dives/`), which is under the GNU GPL version 2. They
  were anonymised with `packages/fit_reader/tool/anonymise_fit.dart`.
- **Trademarks:** Garmin, Descent and FIT are trademarks of their owners.
  Anchorline uses them only to name the files and devices it reads, and is
  not affiliated with or endorsed by Garmin or Suunto.

## Fonts

- **Inter**, `fonts/Inter-VariableFont.ttf`: Copyright 2016 The Inter
  Project Authors, <https://github.com/rsms/inter>
- **JetBrains Mono**, `fonts/JetBrainsMono-VariableFont.ttf`:
  Copyright 2020 The JetBrains Mono Project Authors,
  <https://github.com/JetBrains/JetBrainsMono>

Both fonts are licensed under the SIL Open Font License, version 1.1. The
text is in [`fonts/OFL.txt`](fonts/OFL.txt).

## Dart and Flutter packages

The app depends on open-source Dart and Flutter packages, each under its
own licence. They are listed in `pubspec.yaml` and `pubspec.lock`.

## SOLO bridge firmware

The firmware in `firmware/solo_bridge/` is a separate program under the
Apache License 2.0; see its own `LICENSE` and any notices in that folder.
