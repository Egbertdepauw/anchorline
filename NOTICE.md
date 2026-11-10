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
  - `lib/shearwater/parser/constants.dart`
  - `lib/shearwater/parser/decompressor.dart`
  - `lib/shearwater/parser/hardware.dart`

The Bluetooth download code in `lib/shearwater/ble/` and
`lib/shearwater/parser/slip_decoder.dart` is Anchorline's own
implementation. It used libdivecomputer's `shearwater_common.c` and
`shearwater_petrel.c` as its reference for the Shearwater protocol.

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
