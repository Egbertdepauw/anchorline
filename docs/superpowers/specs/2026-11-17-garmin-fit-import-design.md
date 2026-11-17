# Garmin dives from FIT files — design

**Date:** 2026-11-17
**Status:** Draft, for Egbert's review (approaches chosen by Egbert, 2026-11-17)
**Builds on:** [`2026-11-15-libdivecomputer-brands-design.md`](2026-11-15-libdivecomputer-brands-design.md)
(the brands spec). This design replaces its phase 4 ("Garmin, as FIT file
import") and changes its rollout order (section 11).

## Why

Many divers own Garmin gear, and the Descent line is newer and more modern
than the cable computers in the brands spec's phase 3. So Garmin comes
before cable and classic Bluetooth computers, and after the Bluetooth LE
computers of phase 2. The most important thing is that a Garmin diver has a
way to bring their dives into Anchorline at all.

A typical Descent owner never plugs the watch in. Their dives reach Garmin
Connect over Bluetooth through the phone, and Garmin Connect can hand back
the untouched dive files. So a file import reaches nearly every Garmin
diver, on every platform, without any Garmin hardware on our side.

## Goals

- A diver can import Garmin Descent dives on all five platforms from:
  - one or more `.fit` files (copied off the watch, or from anywhere else);
  - the zip that Garmin Connect's "Export Original" gives for one activity;
  - the zip of Garmin's whole-account export, which holds every activity
    the diver ever uploaded.
- Imported Garmin dives go through the same import, storage and sync as
  every other dive: raw data kept and re-parseable, metric storage, a
  single commit per dive, everything synced, and the in-place refresh of
  the brands spec (section 7a).
- Importing the same dive twice, from any of those sources, never makes a
  duplicate.
- Garmin's CCR mode, gases, tank pressure from Descent T1/T2 transmitters,
  decompression data and real time zones arrive in the existing model.
- The app is honest about what has been checked: Garmin models we haven't
  seen real files from are marked "not yet tested by us", with a way to
  send us a file.

## Non-goals

- Reading the watch directly over USB (MTP). Only the original Descent Mk1
  shows up as a drive; every later Descent uses MTP, which macOS and iOS
  can't read, and nobody here has a Descent to test with. This is a later
  step (section 11).
- Linking a Garmin Connect account so dives arrive by themselves. Garmin's
  developer programme requires a company, has paused new sign-ups since
  September 2026, and would run through our server. A later step if Garmin
  reopens.
- Apnea and freediving sessions (Garmin's apnea and apnea-hunt activities).
  Anchorline is built for scuba and CCR divers; these files are counted and
  skipped.
- Heart rate, GPS positions, N2 load and the other values the analysis
  doesn't use yet. They stay in the raw file (section 4), as the brands
  spec does for libdivecomputer's heart rate and location.
- Writing anything to Garmin devices or to Garmin Connect.
- Pushing new Garmin dives to Subsurface Cloud. The writer skips
  non-Shearwater dives it hasn't pushed before (section 7); teaching it
  other brands is its own design.
- Pairing one dive logged by two computers (a backup Descent next to a
  Petrel). The import flags these (section 6); pairing them is its own
  design, for every brand.

## Anti-goals

- **Garmin's licence in Anchorline.** Garmin's FIT SDK licence (below)
  forbids exactly what Anchorline is: open source under a copyleft licence,
  distributed to the public. No Garmin SDK code, no port of it, and no table
  generated from its `Profile.xlsx` may enter the repo.
- **Pretending a model works.** As in the brands spec.
- **Losing a dive from a big export.** A whole-account export can hold
  thousands of activities and run to gigabytes. Running out of memory, or
  stopping at the first odd file, would be worse than not offering it.

## The FIT licence

Garmin publishes the FIT SDK under the "Flexible and Interoperable Data
Transfer (FIT) Protocol License Agreement" (the `LICENSE.txt` in Garmin's
`fit-*-sdk` repositories on GitHub). The licensed thing is the SDK, "that
includes documentation describing the FIT protocol and related source code
files". The terms that matter:

- the grant is for "internal business purposes";
- no distributing or publishing the SDK or its features (2c);
- no derivative under a licence that requires source to be disclosed,
  that is, no copyleft (2d);
- no use in safety-critical applications (2g);
- the SDK is Garmin's confidential information (4);
- modifications are licensed back to Garmin (5).

So the SDK, anything ported from it, and its profile spreadsheet can't go
into GPL Anchorline. The pub.dev package `fit_sdk` describes itself as a
port of Garmin's C# SDK, despite its MIT label, so it is out as well. The
other Dart packages are too small (`dart_fit_decoder` has no dive messages)
or AGPL (`fit_parser`).

The FIT file format itself is a set of facts: how a file is laid out and
which number means which value. Subsurface (GPL-2.0, through Linus
Torvalds's LGPL Garmin parser in its libdivecomputer fork) and GoldenCheetah
(GPL) read FIT files with decoders of their own. Anchorline does the same:
a small decoder written from those facts, without downloading or reading
Garmin's SDK, its `Profile.xlsx` or its developer documentation. Facts come
from Subsurface's Garmin parser (read for facts, not translated, as the
brands spec does for Subsurface's Bluetooth code), other openly licensed
decoders, and real files. This is a judgement, not legal advice.

"Garmin", "Descent" and "FIT" are used only to name what the files are. No
logos, and no claim of FIT certification.

## Approaches considered

### How dives get in

1. **Files only** (chosen). Pure Dart, the same on every platform, testable
   without Garmin hardware. New dives later mean one export per dive from
   Garmin Connect's website, or copying files off the watch with the
   computer's own tools.
2. **Files, plus reading the watch over USB where the platform allows.**
   Windows (its own MTP support) and Android (its USB host MTP support),
   with native code per platform; a Mk1 as a drive. A Mac would need
   libmtp, iPhones can't do it, and divers report watches often not showing
   up on Android phones. Needs a real watch to build and test.
3. **Files, plus a Garmin Connect account link.** The best experience, but
   not possible today (see Non-goals).

Egbert chose 1: "This way Garmin users have an option to import their
dives. That's the most important thing." 2 follows once someone can test
with a real watch, 3 if Garmin reopens sign-ups.

### A dive another computer already logged

1. **Separate dives, flagged** (chosen). A Garmin dive that overlaps a
   stored dive from another computer is marked in the list and starts
   unticked. No new tables.
2. **Link the two now** as one dive with several computers. A new synced
   table, its migration and UI, for a problem every brand shares.

Egbert chose 1 ("mark and untick").

### Dives already on Subsurface Cloud

1. **Keep their edits flowing** (chosen). The writer still merges the lines
   Anchorline owns into a dive that is already on Subsurface Cloud, whatever
   its brand, and skips only non-Shearwater dives it never pushed.
2. **Skip every non-Shearwater dive,** as phase 2's plan has it. Notes and
   other edits on those dives would stop reaching Subsurface Cloud after a
   FIT import, where they reach it today.

Egbert chose 1 ("keep edits flowing").

### The reader

1. **Anchorline's own Dart reader** (chosen). Pure Dart, like the
   Shearwater reader; no native build.
2. **Subsurface's Garmin parser.** It exists only in Subsurface's
   libdivecomputer fork, and the brands spec links upstream libdivecomputer
   only, pinned, with no private fork. It would also need the native
   library of phase 2 for a format that needs no native code.
3. **Garmin's SDK, or a Dart port of it.** Ruled out by the licence.

## Design

### 1. Where the code lives

A new pure-Dart package, `packages/fit_reader/`, next to
`packages/subsurface_core/`:

```
packages/fit_reader/
  lib/fit_reader.dart          public API
  lib/src/container.dart       the FIT file layout: header, definition and
                               data messages, compressed timestamps,
                               developer fields (skipped), CRC
  lib/src/messages.dart        the dive-relevant messages and fields, by
                               number, with units (section 3)
  lib/src/dive_reader.dart     FIT file → FitDive (messages gathered)
  lib/src/mapping.dart         FitDive → ConvertedDive
  lib/src/products.dart        Garmin product ids → model names
  test/                        container, mapping and fixture tests
  test/support/fit_writer.dart a small FIT writer for synthetic test files
  tool/anonymise_fit.dart      anonymiser for real files (section 9)
```

- No Flutter, file I/O, database or zip code; it takes bytes and returns
  parsed structures, like the Shearwater parser. A purity test enforces it,
  as in `subsurface_core`.
- It depends on `subsurface_core` for `ConvertedDive`, `Dive`, `SampleSet`
  and `DiveEvent`.
- It reads any FIT file whose sport is diving, whoever made it. Subsurface's
  test data includes a Suunto Ocean FIT file, so at least Suunto writes the
  same messages. Non-Garmin files get the same tier rule (section 9).
- The server-side Subsurface sync service can use the package later, the
  way it uses `subsurface_core`.

### 2. Getting the files (the app)

The import screen gets a second way in next to the Bluetooth scan:

```
Import dives

  [ Scan for a dive computer ]        Bluetooth

  [ Import Garmin files… ]            .fit files, or a Garmin Connect
                                      export (.zip)
  Where do I find them? ›
```

- **Picking:** the existing `file_picker` dependency, several files at once,
  `.fit` and `.zip`. On desktop the picker can also choose a folder, which is
  read recursively (a Mk1's `Garmin/Activity`, or a folder copied off any
  watch).
- **Zips:** `.fit` entries are read wherever they sit in the zip, and `.zip`
  entries inside it are opened too, two levels deep (Garmin's account
  export is a zip of zips; its folder names vary). Anchorline reads zips
  with a small reader of its own in the app (`lib/devices/fit/`), on
  `dart:io`'s raw deflate (`ZLibDecoder(raw: true)`), with Zip64 for large
  exports. `package:archive` is in the tree today only through a dev tool
  (`flutter_launcher_icons`), so using it would ship it and its `posix`
  dependency in every build; CLAUDE.md asks to resist that when Dart can do
  the job. The outer zip is read from disk through its central directory,
  entry by entry. An inner zip that is stored uncompressed is read in place;
  a compressed one is extracted to a temporary file, read, and deleted
  before the next. Each `.fit` entry (a few hundred kilobytes) is held in
  memory only while it is read.
- **Sorting the files:** each `.fit` file is read only as far as needed to
  tell whether it is a dive: its file id, and its sport message, which comes
  before the samples in the files we've seen (when it doesn't, the reader
  falls back to the session message). Runs, rides and other activities are counted and
  skipped. So are apnea sessions. A file that isn't FIT at all, or fails its
  CRC, is counted as unreadable and the import carries on.
- **"Where do I find them?"** is a short help sheet:
  - one dive: Garmin Connect website, the activity, the gear menu, "Export
    Original";
  - every dive at once: Garmin account, Data Management, "Export Your Data"
    (Garmin emails a link, which can take days);
  - from the watch with its cable: the `Garmin/Activity` folder, through
    Explorer on Windows or the file manager on Linux; on a Mac, a tool such
    as OpenMTP; a Descent Mk1 shows up as a drive.

  OpenMTP is named as an example, not endorsed, and the sheet links nothing
  outside Garmin's own pages.

### 3. Reading a FIT dive

The container decoder handles everything the format allows: both byte
orders, compressed timestamp headers, developer fields (their bytes are
skipped, using their declared sizes), messages it doesn't know (skipped by
size) and invalid-value markers per base type. A file that ends early or
fails its CRC is unreadable: it is counted, never half-imported.

The messages the reader uses, each named here for the builder (numbers and
units come from the sources in "The FIT licence"):

| Message | What Anchorline takes |
|---|---|
| file id | type (activity), manufacturer, product, serial number, time created |
| device info | product, serial, software version of the main device |
| sport / session | sport and sub-sport (dive kind), start time, total time |
| activity | local timestamp (gives the time zone) |
| record | time, depth, temperature, CNS, next stop depth and time, time to surface, NDL |
| event | gas switches, dive alerts (setpoint switches, deco, ascent, others) |
| dive settings | deco model, GF low/high, water type and density, CCR low and high setpoints with their switch modes and depths |
| dive gas | O2 and He percentages, status (enabled, backup only, disabled), mode (open circuit or CCR diluent) |
| dive summary | the session's max and average depth, bottom time, the watch's own dive number |
| sensor profile | tank transmitters: sensor id, rated and reserve pressure, volume |
| tank update | transmitter id and pressure |
| tank summary | per transmitter: start and end pressure |

Everything else in the file is skipped but kept in the raw file (section 4).

### 4. Identity, duplicates and the raw file

**Dive id.** `sha256('fit:<manufacturer>:<serial>:<time created>')`,
truncated to 32 hex characters like every other id. All three come from the
file's own file-id message, written by the watch when it closed the file.
They are the same whether the file comes off the watch, from "Export
Original", or from the account export (Garmin Connect hands back the
original file). Nothing in the id depends on how the reader interprets the
dive, so a reader fix never changes it, and the id is frozen at first
import as for every engine. If a file holds more than one dive session,
`:<n>` is appended for the second and later ones.

**Duplicates.** Before reading a whole file, the import computes its id and
looks it up, so the list can show "Already in Anchorline". Committing goes
through `DiveDao.importDive` as for downloads: the same id with an equal or
newer reader version only stores a missing raw file; an older stored
version is refreshed in place (brands spec 7a). Two copies of one file in
one pick are imported once.

**Subsurface copies.** A diver who used Subsurface with their Garmin may
have those dives in Anchorline already, from the Subsurface Cloud bootstrap.
The existing same-dive matcher applies: vendor Garmin, the serial
(Subsurface writes Garmin serials in decimal, which `subsurfaceSerialForms`
already covers for non-Shearwater brands), and a start within the window.
A matched copy is refreshed under its own id.

That refresh sets `dc_family` on a row that had none, which moves the dive,
its samples and its bailout rows from the stream older builds read to the
gated one. libdivecomputer downloads meet Subsurface copies the same way,
and the phase 2 plan (PR #235, Task 8) settles it for both: a refresh never
changes a `dc_family` that is already set; only a copy's NULL may become
set, and then `dives`, `dive_samples` and `dive_bailout_carry` change in
one transaction. A refresh whose engine differs from the stored row's
writes nothing, not even the raw blob. FIT dives follow that rule. On a
device still running a build from before phase 2, a refreshed copy
disappears until that device updates, as for libdivecomputer.

**Fingerprint.** Phase 2 adds a synced `dives.dc_fingerprint` column, and
the matcher then pairs two stored downloads only when their fingerprints
are equal. FIT dives fill it with the lower-case hex of the file id's
serial and time created (and the session number, as for the id). The
watch's dive number would mostly do, but it can be missing, and then two
short dives from one watch less than a minute apart would be taken for one.

**Dive computers.** Each watch becomes a `dive_computers` row keyed by
(vendor, serial), as in the brands spec. One pick may hold dives from more
than one watch (a diver who moved from a Mk2 to a Mk3); the source
announces each watch before its first dive.

**Raw file.** The whole FIT file is kept in `dive_raw_blobs`, exactly as
read, in a small envelope:

- magic `ALFT`, envelope version;
- where it came from (single file, Connect export, account export, folder);
- the file's name inside its source (for example
  `2023-08-17-08-51-59.fit`), which Subsurface uses as its fingerprint for
  Garmin downloads, for the later Subsurface writer;
- the FIT bytes.

A FIT file is self-describing, so re-parsing needs nothing else. A dive file
is a few hundred kilobytes (the two real Mk1 dives below are 257 and 321
kB); raw blobs stay local, as today.

### 5. Mapping into Anchorline's model

**Brand fields.** `dc_vendor` "Garmin" (from the manufacturer; other makers
by their name), `dc_product` the model name from the product id ("Descent
Mk1"; an unknown id becomes "Garmin product 1234", or the file's own product
name when it has one), `dc_model_code` the product id, `dc_model`
`ShearwaterModel.unknown`, `dc_serial` the file's serial, `dc_firmware`
from the software version.

**The FIT engine.** The brands spec marks a libdivecomputer dive by
`dc_family` being set, and the sync gate and the Subsurface writer key on
it. FIT dives must be kept from older builds and from the writer in the same
way, so they set `dc_family` too, to a reserved value libdivecomputer can
never use: `kFitDcFamily = -1` (libdivecomputer's families are positive).
Engine logic that today asks "is `dc_family` set" asks which engine instead:
null is Shearwater, -1 is FIT, anything else is libdivecomputer. Each engine
keeps its own parser version (`kFitParserVersion`, starting at 1, bumped
whenever the FIT reader's output changes, with a guard test like
Shearwater's).

**Time.** FIT times are UTC. The activity's local timestamp gives the
watch's offset, so:

- `start_time` is the session start plus that offset, stored as if UTC,
  like every other dive (the wall-clock rule of the brands spec);
- `utc_offset_minutes` is that offset. Garmin is the first engine that
  always gives one;
- without a local timestamp, the builder falls back to the device settings'
  offset, then to none (UTC wall clock), and says so in the code.

**Dive number.** The watch's own count from the session's dive summary goes
into `dc_dive_number`, so the matcher's dive-number rule works for Garmin
as it does for Shearwater.

**Dive mode.** Sub-sport CCR diving → `cc`; single-gas and multi-gas diving
→ `ocTec`; gauge → `gauge`. Apnea is skipped before mapping (section 2).

**Gases.** Each enabled or backup-only dive gas becomes a mix. A CCR
diluent gas → `isDiluent`; open-circuit gases on a CCR dive → bailout, as
the app already assumes. Disabled gases are left out.

**Setpoints.** Garmin has no oxygen cells. A CCR dive starts on the low
setpoint, and the setpoint-switch alerts (automatic or manual, low or high)
move it, as Subsurface reads it. The setpoint channel carries that trace;
`ppo2Bar`, cell millivolts and per-cell ppO2 stay empty, and the UI hides
what's empty, as for the setpoint-only brands of phase 2 (Ratio, Suunto).
Analyses that need the loop's ppO2 on such dives use what phase 2 settles
for setpoint-only CCR dives.

**Tanks.** Each tank transmitter in the sensor profiles becomes a
`DiveTank` (its rated and reserve pressure, start and end pressure from the
tank summary) and a `tankPressuresBar` channel fed by the tank updates.

**Samples.** Garmin records about once a second, sometimes irregularly. The
mapping collects per-time rows and resamples them onto a fixed grid at the
file's own interval (the most common gap), carrying forward values logged
only on change, as the brands spec does for libdivecomputer. Events keep
their exact times, and the raw file keeps the original timing.

| FIT | Anchorline |
|---|---|
| record depth | depth |
| record temperature | temperature |
| record CNS | CNS |
| record next stop depth / time, time to surface, NDL | deco stop depth, deco/NDL time, TTS |
| gas switch events | gas mix index, plus a gas switch event |
| setpoint switch alerts | setpoint, plus a setpoint change event |
| tank updates | tank pressure channel per transmitter |
| other dive alerts | events: deco and ceiling warnings, ascent warnings, the rest as `other` with their raw code |
| heart rate, position, N2 load, SAC, RMV, ascent rate | not stored; kept in the raw file |

**Header fields.** Deco model (Garmin uses Bühlmann ZHL-16C with GF low and
high), water density (from the dive settings, or from the water type),
max depth and duration from the samples, as for the other engines.

### 6. The import path

- An app-side `FitFileSource` implements the brands spec's
  `DiveDownloadSource`. It can list dives: after sorting the picked files
  (section 2) it reads each dive file once and returns a `DiveListing` per
  dive (date, depth, duration, model, computed id), so the existing
  manifest list, with its checkboxes, shows them. `DiveListing` has no
  depth, duration or model today, so it gains optional fields for them,
  which the other engines leave empty. `download` emits
  `DiveSourceIdentified` for each watch before its first dive, then
  `DiveSourceDive` per dive, and `DiveSourceDiveFailed` for a dive that
  maps to nothing usable.
- Files need no saved "last fingerprint" per computer. Duplicates are found
  by id (section 4).
- **A dive another computer already logged.** Many CCR divers wear a
  Descent as a backup next to a Petrel, so the same immersion arrives
  twice, once per computer, and nothing above pairs them (different brand
  and serial). A FIT dive whose time span overlaps a stored, not deleted
  dive from another computer is shown in the list as "Overlaps your
  Petrel 3 dive" (that dive's model name) and starts unticked, so nobody
  doubles their logbook by accident. Ticking it imports it as a dive of its
  own. One dive with several computers is a design of its own, for every
  brand (a Petrel with a Perdix backup has the same problem today).
- Each dive commits as every dive does: one PowerSync transaction for the
  synced rows, then the raw blob as the separate local write, with the same
  marker if that write fails (brands spec section 6).
- **After a reader update,** the background re-parse (brands spec 7a)
  covers FIT raw blobs too, with the FIT parser version.

The list, during and after reading:

```
Garmin files

  Reading 212 of 1,480 files…

  34 dives            1,439 other activities skipped
   3 apnea sessions skipped     4 files unreadable

  ☑ 17 Aug 2023  08:51   51.8 m   98 min   Descent Mk1
  ☑ 21 Oct 2023  12:13   62.0 m  106 min   Descent Mk1
  ☐ 02 Jun 2024  10:02   31.0 m   62 min   Descent Mk3i  Already in Anchorline
  ☐ 09 Jun 2024  09:40   48.3 m   91 min   Descent Mk3i  Overlaps your Petrel 3 dive
  …
                                         [ Import 33 dives ]
```

(The first two rows are the real Mk1 files of section 9; the rest is
made up.) The finished screen is today's, plus a note when a model isn't
checked (section 9).

### 7. Sync, older builds and Subsurface Cloud

- FIT dives sync like every dive (`dives`, `dive_samples`, `dive_computers`),
  through the brands spec's `libdc_dives` stream, because `dc_family` is set.
  Builds from before phase 2 never receive them. No stream or migration
  change is needed.
- Phase 2 builds (`dc_engines = 2`) that have no FIT reader may receive FIT
  dives from another device. That is safe only if phase 2 treats a family
  it doesn't know (`-1`, or one not compiled in) as a plain non-Shearwater
  dive:
  - show it, with its vendor and product names;
  - in the refresh rule, compare engines rather than "`dc_family` is set",
    so a FIT dive and a libdivecomputer dive never refresh each other;
  - leave it out of the libdivecomputer re-parse (its candidates are rows
    with `dc_family` set, so `-1` must be excluded, or a FIT blob would be
    marked as a failed libdivecomputer parse);
  - never look it up in libdivecomputer's descriptors (tier badge, labels).

  These requirements were sent to the phase 2 work on 2026-11-17. Builds
  with the FIT reader keep sending `dc_engines = 2`.
- **Subsurface Cloud.** Phase 2's planner leaves out every dive with
  `dc_family` set, before any matching. Egbert ruled (2026-11-17) that edits
  must keep flowing for dives that are already on Subsurface Cloud: a diver
  who used Subsurface with their Garmin has those dives there, Anchorline
  holds them as Subsurface copies, and importing the FIT files turns the
  copies into FIT dives. So the planner leaves out only non-Shearwater dives
  that match no dive in the remote snapshot (matched on serial and start
  time, as today). A matched one gets the existing-dive merge of the lines
  Anchorline owns (notes, buddies, site, rating), never a change to its
  Divecomputer file, and no setpoint trace injected. Never-pushed FIT dives
  stay off Subsurface Cloud, and the sync screen says why. This changes
  phase 2's Task 9 and was sent to that work with the requirements above;
  it applies to libdivecomputer dives the same way.

### 8. What Garmin divers get

| Garmin data | What Anchorline shows |
|---|---|
| depth, temperature, deco, CNS | the full profile and the analyses that use them (gas density, END, deco replay) |
| CCR mode with setpoints | setpoint trace, diluent and bailout gases; no cell views |
| T1/T2 tank pressure | tank pressure per transmitter |
| time zone | stored, as information, like the others |

### 9. Tiers, real files and fixtures

- **Tier per Garmin model** (product id), not per family: FIT is one format,
  but each model writes different fields (tank transmitters, newer alerts).
  A model is checked when the repo has a real file from it with its
  expected output, and someone has compared that output with what Subsurface
  shows for the same file. The checked list lives in code with the fixture
  name for each; a test fails if a checked model has no fixture. Non-Garmin
  FIT dives are always "not yet tested by us" until the same holds.
- **The first real files:** Subsurface's repository (GPL-2.0, compatible
  with Anchorline's licence) holds two real Descent Mk1 FIT files,
  `dives/garmin_2023-08-17-08-51-59.fit` and
  `dives/garmin_2023-10-21-12-13-38.fit`. Both are CCR dives (setpoints 0.7
  and 1.3, a trimix diluent, bailout gases), 5,000 and 6,275 samples. They
  are anonymised, committed with a note on where they come from, and
  compared by Egbert with Subsurface's reading of the same files. Once that
  comparison passes, the Mk1 is checked. The same repository has a Suunto
  Ocean FIT file, kept as a fixture for the reader but not checked.
- **Anonymising** (`tool/anonymise_fit.dart`, the way #191 did Shearwater):
  replace the serial everywhere it appears, clear GPS positions, drop the
  user profile and any names, and rewrite the CRC. The tool uses the
  package's own decoder and a writer for the same container.
- **Synthetic files** from the test writer cover what the real files don't:
  tank transmitters, open-circuit and gauge dives, apnea, big-endian
  messages, compressed timestamps, developer fields, a missing local
  timestamp, two dive sessions in one file, a truncated file and a bad CRC.
- **"Send us this file":** when an imported dive comes from a model that
  isn't checked, the finished screen says so and offers to share that
  dive's FIT file (from the raw blob) through the share sheet. The share
  text says plainly that the file contains the diver's dives, serial number,
  GPS positions and heart rate. The README and website ask for Garmin files
  next to the libdivecomputer recordings.

### 10. Testing

- **Container tests:** every header form, byte order, invalid values,
  developer fields, unknown messages, compressed timestamps, CRC, truncation.
- **Mapping tests** on synthetic files for each dive kind and for the cases
  in section 9.
- **Fixture tests:** the anonymised Mk1 files and the Suunto Ocean file
  against committed expected output (as for Shearwater).
- **Import tests:** a pick with loose files, a Connect export, a nested
  account export with non-dive activities, apnea and unreadable files;
  duplicates within a pick and against stored dives; a Subsurface copy
  refreshed under its own id; two watches in one pick.
- **Memory:** a synthetic account export of about a gigabyte imports with
  memory staying bounded, on a phone as well as in tests.
- **Refresh and re-parse:** a newer FIT parser version refreshes stored FIT
  dives; another engine never overwrites them.
- **Overlap:** a FIT dive overlapping a stored Petrel dive is flagged and
  unticked; one overlapping only another FIT dive from the same watch, or a
  deleted dive, is not.
- **Subsurface Cloud:** a refreshed copy that is already on Subsurface Cloud
  still gets its notes merged and its Divecomputer file untouched; a
  never-pushed FIT dive is left out and counted.
- `flutter analyze` clean and `flutter test` passing on every PR, plus
  `dart test` in `packages/fit_reader`.

### 11. Rollout

The brands spec's phases become:

1. Groundwork (done).
2. Bluetooth LE computers (in progress).
3. **Garmin and other FIT files: this design.**
   - a. File import, as above.
   - b. Later, reading the watch over USB: a Mk1 as a drive, MTP on Windows
     and Android. Needs a real watch. On macOS and Linux, MTP needs libmtp,
     which needs libusb, so it waits for phase 4's decision on libusb.
   - c. Later, a Garmin Connect account link, if Garmin reopens sign-ups.
4. **Cable and classic-Bluetooth computers** (the old phase 3, unchanged).
   It needs phase 2's `packages/libdivecomputer`, so it can't start before
   phase 2 anyway, and gets its own design then.

Build order for 3a, in reviewable PRs:

1. `packages/fit_reader` with fixtures, synthetic writer, anonymiser and
   tests. It touches nothing phase 2 touches, so it can be built while
   phase 2 is in progress.
2. The app side: the FIT engine marker and engine-aware refresh and
   re-parse, the raw-blob envelope, `FitFileSource`, the import screen,
   tiers, the overlap flag and "Send us this file". It builds on phase 2's
   PR C (migration 0028 with `dc_fingerprint`, Task 8's refresh rule, the
   writer skip with Egbert's amendment, `dc_engines = 2`), so it starts once
   that is merged. It doesn't need phase 2's Bluetooth PRs (D, E). Per
   Egbert's order, Garmin ships after the Bluetooth computers.
3. Documents (section 12), with PR 2 or on their own.

### 12. Changes to other documents

- **Brands spec:** the rollout (its section 12) and its non-goal "Garmin in
  the first phases" point here; phases 3 and 4 swap. Its section 4's
  `LibdcBleLink` and its tables are unchanged.
- **`CLAUDE.md`:** the `dive_id` rule gains the FIT form (section 4);
  `packages/fit_reader` is pure Dart like `subsurface_core`, and no Garmin
  SDK code or `Profile.xlsx` table may enter it; the out-of-scope line about
  non-Shearwater computers, already due to change with phase 2, mentions
  Garmin files.
- **`NOTICE.md`:** the provenance of the Mk1 and Suunto fixtures, and the
  trademark note.
- **README and website:** the request for Garmin files.

## Checks on real devices (Egbert)

Nobody here has a Descent, so the checks use the real Mk1 files, files made
with the test writer, and Egbert's own Petrel dives:

1. Open the two Mk1 files in Subsurface and compare them with Anchorline's
   import: start time, duration, max depth, gases, setpoint changes,
   temperature and the profile's shape. When they agree, the Mk1 becomes
   checked.
2. On each of the five platforms, import the Mk1 files through the picker,
   once as loose `.fit` files and once inside a zip made like a Connect
   export. On iOS, from the Files app.
3. Import the same files again: nothing new, and the list says "Already in
   Anchorline".
4. A test file whose dive overlaps one of Egbert's Petrel dives: it shows
   "Overlaps your Petrel 3 dive" and starts unticked.
5. On a second device with the same account, the imported dives arrive by
   sync; on an installed store build from before phase 2, they don't
   appear.
6. On a phone, a synthetic account export of about a gigabyte imports
   without the app being killed, and the cache copy is gone afterwards.

## Left to the builder

- The exact numbers and scales of every field in section 3, from the
  sources allowed in "The FIT licence", checked against the real files.
- The envelope's byte layout.
- A stable stand-in for the serial when a file has none (the Suunto Ocean
  sample has none), built only from the file id's own fields.
- How the picker offers folders per platform, and whether a folder pick is
  offered on mobile.
- Resampling details: grid choice, gaps, a record with no depth.
- Which dive alerts map to which event types.
- The product id table's contents (names and ids are facts; Subsurface's
  model list is one source).
- The share text and the help sheet's wording.
- How phase 2's shared pieces look in code; this design names what it
  needs, not their shape.

## Risks

- **Garmin's licence reading.** Garmin could see a FIT decoder in GPL code
  as a derivative of its documentation. Mitigated by writing only from
  facts and openly licensed sources, as Subsurface and GoldenCheetah do,
  and by keeping the reader small and dive-only.
- **Newer models write fields we haven't seen.** Mitigated by the tier
  label, the raw file (a fix re-parses every stored dive), and the request
  for files.
- **Garmin changes its export.** The account export's layout has changed
  before (its folder names vary). The import reads any `.fit` at any depth
  rather than relying on names.
- **Big exports on phones.** `file_picker` copies a picked file into the
  app's cache on iOS and Android, so a several-gigabyte export needs that
  much free space, plus room for the largest compressed inner zip, while
  the import runs. The copy is deleted when the import ends, and the import
  says so plainly when space runs out.

## Follow-ups outside this design

- Phase 3b and 3c (section 11).
- One dive logged by several computers, for every brand (section 6).
- Heart rate as a sample channel, and the watch's GPS entry and exit
  offered for the dive site.
- The Subsurface writer for other brands, including Garmin (it would need
  the watch's file name, kept in the envelope).
- Opening `.fit` and `.zip` files from other apps ("Open in Anchorline")
  on iOS and Android.
