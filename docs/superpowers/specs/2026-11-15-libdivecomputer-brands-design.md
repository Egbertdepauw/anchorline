# Dive computers beyond Shearwater, through libdivecomputer — design

**Date:** 2026-11-15
**Status:** Approved by Egbert, 2026-11-15
**Revised:** 2026-11-16, sections 2, 10 and 12: the other authors' code
ships in every build, the store builds too, and is left out of the store
builds only if an author asks.
**Supersedes:** the engine decision ("pure-Dart ports, no FFI") in
[`2026-06-04-multi-dc-driver-architecture-design.md`](2026-06-04-multi-dc-driver-architecture-design.md).
Its data-model changes and the idea of one download shape for every brand
carry over, as described below.
**Changes:** the "Out of scope" line about non-Shearwater computers in
`CLAUDE.md`, the Tech stack line about libdivecomputer, and the `dive_id`
rule (section 13).

## Why

Anchorline only reads Shearwater computers today. Egbert wants to reach more
divers, not one particular diver waiting for one particular computer. The
analysis that makes Anchorline worth using (gas density, END, deco replay,
bailout tracking, the CCR-first layout) works for any dive with a depth
profile and gases. Only a few features depend on Shearwater-specific data:
cell millivolts and scrubber time.

libdivecomputer already reads 357 models from 37 brands. Linking it, rather
than translating it, gives Anchorline that whole list in one integration.

`CLAUDE.md` says non-Shearwater support is out of scope "forever, probably",
and calls the libdivecomputer phase conditional. This design changes that,
because reaching more divers is now a goal. Shearwater stays the default
case and keeps its own reader.

## Goals

- Anchorline downloads from every dive computer upstream libdivecomputer
  can read over Bluetooth LE, on all five platforms (iOS, Android, macOS,
  Windows, Linux).
- Later, cable and classic-Bluetooth computers on desktop (and classic
  Bluetooth on Android), and Garmin through FIT files.
- Dives from other brands go through the same import, storage and sync as
  Shearwater dives. They obey the same principles: raw data kept and
  re-parseable, metric storage, a single commit per dive, everything synced.
- The app is honest about what has been checked. Brands checked against
  real downloads are listed normally. The rest are marked "not yet tested
  by us", with a way for the diver to send a recording.
- Fixes and findings go back to libdivecomputer, as `CONTRIBUTING.md`
  promises.

## Non-goals

- Porting libdivecomputer backends to Dart. A brand is ported only when the
  analysis needs control that the library can't give and we can test it on
  real hardware. Today that is Shearwater, which is already ported.
- Reading Shearwater through libdivecomputer. Shearwater keeps the Dart
  reader.
- Infrared (IrDA) computers: 19 old Uwatec and Subgear models.
- Classic Bluetooth on iOS. Apple doesn't allow it without the MFi
  programme, so the older classic-Bluetooth-only models (Ratio iX3M GPS,
  HW Frog, Tecdiving) will never work on iPhones.
- Garmin in the first phases (section 12, phase 4).
- Writing settings to dive computers, firmware updates, or anything beyond
  downloading dives.
- A web build. FFI does not exist there.

## Anti-goals

- **Pretending a brand works.** Listing a computer we've never seen as if
  we'd tested it, then losing or garbling a diver's dives, would cost more
  trust than the extra brands gain. The two tiers exist to prevent this.
- **A private fork of libdivecomputer.** Every change we make to its code
  is a patch that goes back upstream. If we end up carrying changes Jef
  hasn't seen, the agreement with him is broken.
- **Breaking Shearwater.** Existing dive ids and analysis for Shearwater
  must not change, and its import changes only by gaining the refresh
  (section 7a).
- **Native-build pain spreading.** The library must build from a normal
  `flutter build` on every platform, locally and in CI, with no manual
  steps. See the git2dart history in the `toolchain-gotchas` skill.

## Approaches considered

### Engine: port, link, or both

1. **Port each backend to Dart** (the June draft). No native build, full
   control over output, bugs are Dart exceptions. But every upstream change
   has to be re-translated by hand, for every brand. Since 2023 the files
   for Halcyon, Ratio, Divesoft and Suunto have had 16–20 commits each, and
   Shearwater 50. Releases are rare (v0.9.0 in June 2025, about every two
   years), but master changes constantly, and Subsurface builds from a
   commit too. Our own Shearwater port, translated in spring 2026, already
   misses four things libdivecomputer gained since (PR #213). And we can't
   test translations of computers we don't own.
2. **Link libdivecomputer through FFI.** One integration gives every brand.
   Catching up is moving one pinned commit, and the code that runs is the
   code Subsurface users run daily. Costs: a native build on five
   platforms, a small C layer for Bluetooth, and patches to libdivecomputer
   when we need data it drops.
3. **Both, decided per brand** (chosen). Link by default. Port only where
   the analysis needs control and we own hardware to test with. Shearwater
   is ported already. Any other brand can move later, behind the same
   download shape.

Egbert chose 3: "only port what we need ported, like Shearwater".

### Which libdivecomputer

1. **Upstream master, pinned to a commit** (chosen). This is Jef's code,
   and the agreement and the share-back are with him. It lacks Garmin, a few
   fields, and some fixes that Subsurface carries.
2. **Subsurface's fork (`subsurface/libdc`, branch `Subsurface-DS9`).** It
   has Garmin, more fields and fixes, and many daily users. But its headers
   are not ABI-compatible with upstream (it inserts enum values), it moves
   on Subsurface's schedule, improvements would flow to Subsurface rather
   than to Jef, and its Garmin code is by Linus Torvalds.

Egbert chose upstream, pinned. He asked that our findings for Halcyon,
Garmin and anything else go back to Jef.

### What to list

1. Tech and CCR brands only.
2. Everything libdivecomputer reads.
3. **Everything, in two tiers** (chosen): checked families listed normally,
   the rest marked "not yet tested by us", with a way to send a recording.

## Design

### 1. Where the code lives

A new pure-Dart package, `packages/libdivecomputer/`, next to
`packages/subsurface_core/`:

```
packages/libdivecomputer/
  third_party/libdivecomputer/   upstream source at the pinned commit,
                                 with our patches applied (include/, src/,
                                 COPYING, NEWS, the files the build needs)
  patches/                       one .patch per change, plus README.md
                                 listing each patch's upstream status
  UPSTREAM                       pinned commit, its date, the patch list
  native/                        Anchorline's C layer (section 4) and the
                                 fixed config.h / version.h per platform
  hook/build.dart                builds the native library (section 2)
  ffigen.yaml
  lib/libdivecomputer.dart       the public Dart API
  lib/src/bindings.g.dart        generated by ffigen, committed
  lib/src/mapping/               libdivecomputer output → ConvertedDive
  tool/update_upstream.sh        moves the pin (section 3)
  test/                          replay tests and fixtures (section 11)
```

- No Flutter imports, no BLE plugin imports, no database. Like
  `subsurface_core`, a purity test enforces it. The app supplies Bluetooth
  through an interface (section 4).
- The mapping code depends on `subsurface_core` for `ConvertedDive`, `Dive`
  and `SampleSet`.
- The source is vendored, not a git submodule. This project works in many
  git worktrees, and submodules need an extra init step in each one and in
  CI. The vendored tree must always equal "pinned commit + `patches/`";
  `tool/update_upstream.sh` is the only way it changes.
- Anchorline's C layer is licensed LGPL-2.1-or-later, like the library it
  is compiled into, so the native library has one licence and the layer
  could be offered upstream.

### 2. Building the native library

Built by a Dart build hook (`hook/build.dart`) with `package:hooks` and
`package:native_toolchain_c`. This is the standard way in current Flutter
to ship C code: `flutter build` and `flutter test` compile it with each
platform's own toolchain (Xcode clang, the Android NDK, MSVC, clang/gcc on
Linux), with no CocoaPods, Gradle or CMake changes.

- **What's compiled:** libdivecomputer's `src/*.c` for the families in this
  build (see "Left-out families" below), plus `native/`. One dynamic library per
  target. On iOS and macOS the hook output becomes a framework.
- **No optional dependencies in phases 1–2:** no libusb, hidapi, BlueZ or
  libmtp. Bluetooth goes through custom I/O (section 4). Serial support is
  built into libdivecomputer (POSIX and Win32) and comes for free.
- **`config.h` and `version.h`:** libdivecomputer normally gets these from
  autotools. We commit fixed versions per platform family (POSIX, Windows)
  in `native/`, and the update script regenerates `version.h` from the
  pinned commit.
- **Left-out families (section 10):** every build compiles every family.
  The hook can still leave families out, for a store build whose author
  asked for that: it reads a list of families to leave out, passed as a
  hook user-define (from `pubspec.yaml` or the build command; the builder
  picks the mechanism that works per build). The list starts empty.
  Left-out families' source files are not compiled.
  Generated stub functions return `DC_STATUS_UNSUPPORTED`, so no
  libdivecomputer file needs patching. The Dart side asks the native
  library which families are present and lists only those. Code that isn't
  compiled isn't distributed.
- **CI:** `check.yml` runs `flutter test` on Ubuntu, which builds the hook
  for Linux. The cloud release builds (2026-11-02 spec) don't exist yet,
  and macOS, iOS, Android and Windows builds are made by hand today. So
  phase 2 adds a workflow, `libdivecomputer-build.yml`, that builds the
  native library and runs a small load-and-list-descriptors check on
  macOS (for macOS and iOS), Windows (MSVC), Ubuntu (Android NDK) and
  Linux. It runs on PRs that touch `packages/libdivecomputer/**` and on
  every pin move. The repo is public, so these runners cost nothing. When
  the cloud release builds arrive, they compile the library the same way,
  with each platform's own toolchain. Nothing is prebuilt or downloaded.
- **Fallback:** if build hooks fail on one platform at Flutter 3.44 and the
  failure can't be fixed cleanly, that platform gets a library prebuilt by
  a CI job, the way Subsurface builds it (static configure for iOS, ndk for
  Android, MSVC project for Windows). This is a fallback, not the plan.

### 3. Moving the pin

`tool/update_upstream.sh <commit>`:

1. Fetches upstream at `<commit>`, replaces `third_party/libdivecomputer/`.
2. Applies `patches/*.patch` in order. A patch that upstream has merged
   fails to apply; the script says so, and the patch is deleted in the same
   PR.
3. Regenerates `version.h` and `bindings.g.dart`, and writes `UPSTREAM`.
4. Leaves the diff for review.

A pin move is its own PR. It bumps the libdivecomputer parser version
(section 7) and must keep every replay test passing. Read the upstream
commits between the old and new pin before merging: the "Known changes"
part of the PR description lists those that touch a checked family.

### 4. Bluetooth: the C layer between libdivecomputer and Dart

libdivecomputer's custom I/O (`dc_custom_open` with `dc_custom_cbs_t`)
expects blocking calls: `read` must wait until a packet arrives or the
timeout passes. Dart can't block inside a callback, and
`NativeCallable.listener` can't return values. Subsurface solves this on a
download thread that pumps Qt events; libdc-swift uses a queue and a
semaphore. Anchorline uses a small C layer (`native/anchorline_io.c`):

- **A download runs on its own isolate.** That isolate calls
  `dc_device_open` and `dc_device_foreach`, and blocks inside them for the
  whole download. All libdivecomputer calls for that download happen on
  this isolate's thread.
- **The Bluetooth connection stays on the main isolate,** using the app's
  `BleCentral` seam (`lib/ble/ble_central.dart`). That seam already works
  for scanning, connecting, writing and notifications on all five
  platforms, Windows included through the in-app WinRT channel.
  (The Shearwater import still uses `flutter_blue_plus` directly and so has
  no Windows support; that's a follow-up, not part of this work.)
- **Reads:** the main isolate passes each BLE notification to the C layer
  with a direct, thread-safe FFI call that appends it to an inbound queue.
  The C layer's `read` takes one packet per call (libdivecomputer treats
  BLE as packet-oriented) and waits on a condition variable up to the
  timeout libdivecomputer set.
- **Writes:** the C layer's `write` puts the bytes in an outbound slot,
  wakes the main isolate through a `NativeCallable.listener` port, and waits
  until the main isolate reports the GATT write finished or failed (with a
  timeout), so ordering is kept.
- **ioctls:** `BLE_GET_NAME` returns the advertised name given at start.
  `BLE_CHARACTERISTIC_READ` and `_WRITE` go to the main isolate the same way
  as writes. `GET_PINCODE` and access codes are not supported at first. Only
  the Aqualung i330R and Apeks DSX need them, so those stay unlisted until a
  PIN prompt exists.
- **Every callback is implemented or explicitly refused.** libdivecomputer
  treats any missing callback as success (`custom.c`). A missing `sleep`
  would mean no delay, and a missing `purge` would leave stale packets in
  the queue, and many Bluetooth backends call `sleep`, `purge` and `poll`
  (Ratio, OSTC, Mares, Halcyon). So the C layer implements `set_timeout`,
  `read`, `write`, `poll` (packets waiting?), `purge` and `flush` (clear the
  inbound queue), `sleep`, `ioctl` and `close`. The serial-line callbacks
  (`set_break`, `set_dtr`, `set_rts`, `get_lines`, `configure`) return
  `DC_STATUS_UNSUPPORTED`, unless a backend turns out to need them over
  Bluetooth.
- **Events and dives to Dart:** progress, device info, clock and each
  downloaded dive (data plus fingerprint) are copied and posted to the main
  isolate through the listener port. Dart frees the copies.
- **Cancel:** a flag set from Dart, read by libdivecomputer's cancel
  callback.
- **Recording:** when the diver asked for one (section 9), the C layer
  keeps every packet read and written, with timestamps, in memory.
- **Replay:** the same C layer can be fed a recording instead of a live
  connection. The replay tests (section 11) and bug reproduction use this.
- **Bluetooth behaviour per family:** libdivecomputer doesn't know about
  GATT, and some computers need more than a service and two
  characteristics. A small per-family profile in the app says:
  - which service and which write and notify characteristics to use;
  - which characteristics to ignore (Halcyon and McLean have ones that must
    be skipped);
  - any flow control. The OSTC's Telit/u-blox Bluetooth module uses
    credit-based flow control, and packets from other characteristics must
    be dropped.

  Subsurface's `core/qt-ble.cpp` is the reference for what each family
  needs. We implement the behaviour from those protocol facts rather than
  translating Subsurface's code, because Subsurface's GPL code isn't
  covered by any app-store permission. UUIDs and similar facts get a
  mention in `NOTICE.md`.
- **`BleCentral` gains a characteristic read,** on every platform
  including the Windows channel. Today it can only write and receive
  notifications, and Cressi needs a read.

The Dart side is an interface the app implements over `BleCentral`:

```dart
abstract class LibdcBleLink {
  String get advertisedName;
  Stream<Uint8List> get notifications;
  Future<void> write(Uint8List bytes);
  Future<Uint8List> readCharacteristic(String uuid);
  Future<void> writeCharacteristic(String uuid, Uint8List bytes);
}
```

Cable computers (phase 3) use libdivecomputer's own serial code
(`dc_serial_open`) on desktop, with no custom I/O.

### 5. Choosing a computer

- The Bluetooth scan shows every device whose advertised name matches a
  descriptor, through `dc_descriptor_filter(descriptor, DC_TRANSPORT_BLE,
  name)`. Shearwater devices keep going to the Shearwater reader;
  libdivecomputer's Shearwater descriptors are never offered.
- When a name matches several models of one family, any of them works: the
  family decides the protocol, and the model comes from the device info
  during download. When a name matches more than one family, the diver
  picks.
- A manual picker lists every compiled-in model by brand, for computers
  whose names don't match, and for cable computers later.
- Each family shows its tier: no badge when checked, "Not yet tested by us"
  otherwise.

### 6. The import path

- One download shape for every engine, as the June draft proposed: open a
  connection, download, emit `ConvertedDive` plus raw blob per dive, commit
  through `DiveDao.importDive`. The Shearwater reader is wrapped behind it
  without changing its behaviour.
- libdivecomputer decides which dives are new itself: we pass the last
  fingerprint with `dc_device_set_fingerprint`, and it downloads newest
  first and stops at the known dive. So the libdivecomputer driver can't
  list dives before downloading; the flow is "download everything new". A
  "download everything again" option passes no fingerprint, and refreshes
  the dives it already has (section 7a).
- The last fingerprint is saved per computer in `ImportStateDao`, keyed
  `libdc:<family>:<serial>`, so serial numbers from different brands can't
  collide. This is device-local transit state (principle 7b).
- Each dive commits the way Shearwater dives do today: the synced rows
  (`dives`, `dive_samples`, now with events) in one PowerSync transaction,
  then the raw blob in a separate local write. That second write is the
  known gap in principle 8 that the June draft flagged. It is not fixed
  here, but if it fails the dive is marked so the next download stores the
  blob again.
- **Duplicates across sources:** a download that matches a dive imported
  from Subsurface Cloud refreshes that dive instead of adding a second one
  (section 7a).

### 7. Mapping libdivecomputer's data into Anchorline's model

**Identity.**

- `dive_id` for these dives is
  `sha256('libdc:<vendor>:<serial>:<fingerprint hex>')`, truncated to 32 hex
  characters like today. The fingerprint is the raw bytes libdivecomputer
  uses as its own per-dive key on one computer (Subsurface uses it the same
  way). Every input comes straight from the computer, never from a parser:
  the start time could change when a parser bug is fixed, and family
  numbers can change between libdivecomputer versions (upstream already
  folded two Uwatec families into one). Either would give an existing dive
  a new id and create a duplicate. The id is also frozen at first import;
  nothing recomputes it. Shearwater dive ids don't change.
- `dc_dive_number` is 0: upstream libdivecomputer has no dive-number field.
  The list already shows the app's own sequence number first.
- `dc_serial` comes from the device-info event. If a family reports no
  serial (0), the builder picks a stable stand-in and documents it.

**Time.** The whole app treats `start_time` as the computer's wall-clock
time, stored as if it were UTC: every formatter displays it that way,
Shearwater dives are stored that way, and the Subsurface bootstrap import
stores Subsurface's times that way. Subsurface itself stores wall-clock
time too. libdivecomputer dives follow the same rule:

- `start_time` is the wall-clock date and time libdivecomputer reports,
  stored as if UTC.
- When the computer reports its time zone (Divesoft, Halcyon from
  firmware 1.9, newer Ratio firmware), the offset goes into
  `utc_offset_minutes` as information. Nothing applies it yet, as today.
- Some families take the zone from the phone (`dc_datetime_localtime`).
  The mapping uses the wall-clock fields, so the result doesn't depend on
  where the phone is.

So the same dive from a Subsurface copy and from a download shows the same
start time.

**Parsing the same way every time.** During a download libdivecomputer's
`dc_parser_new` uses the device-info model and applies the clock, while
`dc_parser_new2` (re-parsing from stored bytes) uses the descriptor's model
and no clock. The two can differ: Halcyon's device-info model is not its
descriptor model. So Anchorline always parses with `dc_parser_new2` and the
descriptor chosen for the download, both at download time and later. The
envelope stores that descriptor's family and model, and the device-info
model separately. For each checked family, a replay test asserts that
`dc_parser_new` and `dc_parser_new2` give the same dive. If they don't for
some family, we propose a fix upstream. The few parsers that need the clock
(ReefNet, Uwatec Memomouse) are cable-only and are handled in phase 3.

**Brand and model.** `dc_model` today stores the index of the
`ShearwaterModel` enum. New columns on `dives` and `dive_computers`:

- `dc_vendor` and `dc_product` (text, as libdivecomputer names them:
  "Divesoft", "Liberty").
- `dc_family` and `dc_model_code` (integers from libdivecomputer; null for
  Shearwater).

Shearwater rows get vendor and product filled in from their enum, and keep
`dc_model`. `dc_model` is NOT NULL, so libdivecomputer dives store the
`ShearwaterModel.unknown` index (13) there. `dive_computers.serial` stops
being unique on its own; the key becomes (vendor, serial). The bootstrap
importer keeps the model name from Subsurface instead of reducing it to
`unknown`. Each change needs a Supabase migration with explicit grants, the
PowerSync schema update and a check of `infra/powersync-sync-streams.yaml`.

**Older app versions.** Builds already installed read `dc_model` as a
Shearwater model and would push a Divesoft dive to Subsurface Cloud as a
"Shearwater" with cells computed from millivolts it doesn't have. And the
sync planner never rewrites a dive's Divecomputer file once pushed, so the
mistake would stay. So old builds must never receive these dives. The new
app sends a sync parameter (for example `dc_engines: 2`) with its
connection, and the sync rules give dives with `dc_family` set only to
clients that send it. Old builds keep syncing their Shearwater dives
normally and see the other brands after updating. This ships in phase 1,
before any libdivecomputer dive exists. The builder writes it for whichever
of sync rules or Sync Streams (#208) is live at the time.

**Subsurface Cloud.** In phase 2 the Subsurface writer skips dives with
`dc_family` set, and the sync screen says why. The writer is built around
Shearwater today: its model names, three cells computed from millivolts,
and its own `deviceid` and `diveid` scheme. A follow-up design teaches it
the other brands: vendor and product names, per-cell ppO2 for up to four
cells, and Subsurface's own ids for these dives (`deviceid` from the
serial, `diveid` from the SHA-1 of the fingerprint). With Subsurface's own
ids, a diver who also downloads in Subsurface doesn't get the dive twice.
The server-side sync service shares this mapper, so it gets the same
change.

**Raw blob.** Principle 2 holds: the dive's bytes are stored in
`dive_raw_blobs` (local, as today), wrapped in a small envelope so the dive
can be re-parsed without the computer:

- magic `ALDC`, envelope version;
- libdivecomputer pinned commit;
- vendor and product names, and the descriptor's family and model (what
  `dc_parser_new2` needs);
- model, serial and firmware from the device info;
- the fingerprint;
- the clock pair (`devtime`, `systime`), which a few parsers use;
- the dive data exactly as `dc_device_foreach` gave it.

`parser_version` for these dives is a separate counter, starting at 1,
bumped on every pin move or mapping change. Whether a dive came from
libdivecomputer is known from `dc_family` being set. Re-parsing is covered
in section 7a.

**Samples.** libdivecomputer reports samples as a stream: a `TIME` (in ms)
starts each sample, followed by the values the computer logged at that
moment. Anchorline's `SampleSet` is columnar with a fixed interval.

- The mapping collects per-time rows, then resamples them onto a fixed grid
  at the computer's own interval (the most common gap between samples).
  Values a computer logs only when they change (setpoint, gas, sometimes
  temperature) are carried forward.
- Events keep their exact times.
- The raw blob keeps the original timing, so a better mapping can re-derive
  it. If a family turns out to log irregularly by design, revisit this for
  that family.

| libdivecomputer | Anchorline |
|---|---|
| `DEPTH` | depth |
| `TEMPERATURE` | temperature |
| `PPO2` with `sensor = DC_SENSOR_NONE` | ppO2 (voted); if absent, the median of the cells |
| `PPO2` with `sensor = n` | new per-cell ppO2 channels (below) |
| `SETPOINT` | setpoint |
| `CNS` | CNS |
| `DECO` (type, time, depth, TTS) | deco stop depth, deco/NDL time, TTS |
| `GASMIX` | gas mix index |
| `PRESSURE` (tank n) | tank pressure channel n |
| `EVENT` | events (below) |
| `HEARTBEAT`, `BEARING`, `RBT`, `LOCATION`, `VENDOR` | not stored in phase 1; still in the raw blob |

**Per-cell ppO2.** A new `SampleSet` field, `cellPpo2Bar`, a list of
channels like `tankPressuresBar`, because Divesoft reports up to four
cells. The codec gets a matching optional column, and old blobs decode
unchanged. Shearwater keeps writing mV and leaves this empty.

**Header fields.** `DIVEMODE` CCR → `cc`, SCR → `sc`, OC → `ocTec`,
GAUGE → `gauge`, FREEDIVE → `freedive`. `DECOMODEL` → deco model, with GF
low/high when given. `ATMOSPHERIC`, `SALINITY` → pressure and water
density. `GASMIX` with usage `DILUENT` → diluent; usage `OXYGEN` → oxygen;
other mixes on a CCR dive → bailout, as the app already assumes. `TANK` →
`DiveTank`. Anything libdivecomputer doesn't give (cell mV, calibration,
scrubber time) stays empty, and the UI hides what's empty, as it does for
OC dives.

**Events.** Today `importDive` stores no events at all, for Shearwater
either; the June draft found this. This work fixes it for both engines.
Events are imported data that other devices can't re-derive (raw blobs
don't sync), so they sync with the dive's samples: a compact `events` blob
column on `dive_samples`. `DiveEventType` widens to the libdivecomputer
events worth showing (gas change, setpoint change, bookmark, deco/ceiling
and ascent warnings, others as the builder finds useful); the rest are kept
in the blob with their raw type number.

### 7a. Refreshing a dive's imported data in place

Today an imported dive never changes. `getRawBlob` has no callers,
`parser_version` is always 1, and `importDive` skips any dive whose id
already exists. That leaves three gaps, for both engines:

- a reader fix never reaches dives already imported;
- "download everything again" can't repair anything;
- a diver who brought their history in from Subsurface Cloud gets every
  dive twice on their first download, because the Subsurface copy has a
  different id. This already happens for Shearwater: bootstrap ids are
  built from Subsurface's dive counter.

Egbert chose to close all three in phase 1 with one mechanism for both
engines: **a refresh replaces a dive's imported data and keeps everything
else.**

**What a refresh replaces:**

- on the `dives` row, every column the reader fills: times, duration,
  depth, dive mode, deco model and GF, atmospheric pressure, water
  density, log version, model and firmware, the brand fields (section 7),
  sample interval, gas mixes, tanks, calibration, stack times, and
  `parser_version`;
- the whole `dive_samples` row, events included;
- the local raw blob.

**What a refresh keeps:**

- the dive's `id`. It is fixed at first import, whatever the source, and a
  refresh never changes it, so every row that points at the dive stays
  attached;
- everything layered on the dive: annotations (notes, buddies, site,
  rating, the user's dive number), attachments, merge links, bailout carry
  and dive cylinders;
- `owner_id`, `imported_at`, `deleted_at` (a refresh never brings back a
  deleted dive) and `subsurface_uploaded_at`.

`dc_serial` and `dc_dive_number` take the download's values when the
refresh comes from a download, and otherwise stay as they are.

**Gas mix indexes.** `dive_cylinders` is keyed by gas mix index. If a
refresh changes the gas mix list, each cylinder row moves to the index of
the same mix (same O2 and He). A row whose mix no longer exists is kept
and shown as unassigned, never deleted.

**One rule for when a refresh may write.** Each engine has its own
parser version: the libdivecomputer counter (section 7), and a Shearwater
counter that from now on goes up whenever the Shearwater reader's output
changes. A refresh writes only when its result comes from a higher
version of the same engine than the stored dive's, or the stored dive is
a Subsurface copy (`parser_version` -1). A device with an older reader
never overwrites a newer result. Downloading the same dive again with the
same reader changes nothing except storing the raw blob, as today.

**Never lose a good dive.** If the new parse fails, or gives a dive with
no samples or no duration, the stored dive stays as it is and the failure
goes to Sentry.

**One transaction, as an import.** The `dives` and `dive_samples` updates
go in one PowerSync write transaction and bump the rows' `version`; the
raw blob is the separate local write, with the same gap and the same
marker as section 6. Other devices receive the refreshed dive through
sync. `dive_derived_stats` is keyed by parser version, so each device
recomputes its stats.

**Where refreshes come from:**

1. **A reader update.** After an app update, the device that holds a
   dive's raw blob re-parses it in the background, one dive per
   transaction, so an interrupted run carries on next time. A dive whose
   raw blob is on no device (raw blobs don't sync, principle 7) can only
   be refreshed by downloading it again.
2. **A download meets a dive it already has** (same id): it refreshes
   when the stored version is lower, otherwise it only stores the raw
   blob. "Download everything again" goes through this path for every
   dive the computer still holds.
3. **A download matches a Subsurface copy.** When a downloaded dive's id
   doesn't exist, the import looks for the same dive under another id:
   same brand, same serial, and a wall-clock start within a small window.
   Download ids are computed, so such a dive came from Subsurface Cloud
   (possibly already refreshed by an earlier download). The serial is
   compared the way Subsurface wrote it for that family (hex for
   Shearwater, decimal for most upstream parsers), which the bootstrap
   importer gets wrong today. If exactly one dive matches, the download
   is treated as that dive, under its id, with the version rule above: a
   Subsurface copy is refreshed, an already refreshed one only gets the
   raw blob. If more than one matches, nothing is replaced: the dive is
   imported as new and flagged together with its candidates. The copy
   keeps `subsurface_uploaded_at`, so it is never pushed to Subsurface
   Cloud a second time.

The bootstrap importer uses the same matching rule, so a bootstrap run
after downloads doesn't create duplicates either. When it finds a
downloaded dive it skips it, as today.

### 8. What CCR divers on other brands get

| Brand | Cell data from libdivecomputer | What Anchorline shows |
|---|---|---|
| Shearwater | (own reader) raw mV | unchanged: full cell-health analysis |
| Divesoft Freedom/Liberty | per-cell ppO2, up to 4 cells | per-cell ppO2 traces and a per-dive cell agreement summary |
| Halcyon Symbios | per-cell ppO2, 3 cells | same as Divesoft |
| OSTC with sensors | per-cell ppO2 | same as Divesoft |
| Ratio, Suunto | setpoint only | setpoint trace; no cell views |

- **Per-dive cell agreement:** the largest spread between cells, the time
  any cell stayed away from the others by more than a threshold, and each
  cell against the setpoint. The builder picks thresholds and shows them to
  Egbert.
- **Longitudinal cell health from ppO2** (a cell drifting relative to the
  others across many dives) is a separate later design, built on these
  channels.
- **Divesoft millivolts:** the Divesoft log contains raw cell millivolts
  (`MEASURE_ID_OXYGEN_MV`), but libdivecomputer converts them to ppO2 with
  the calibration and drops the mV. The first patch we propose to Jef
  exposes them; how the API should carry them is his call. Once it's merged
  upstream, Divesoft dives fill the existing mV channels and get the
  Shearwater-grade analysis. Until then, this stays a proposal and Anchorline
  does not carry it as a local patch.

### 9. Tiers and recordings

- **The tier belongs to a family,** not a model, because models in a family
  share one parser. A family is checked when the repo has at least one
  replay recording from a real computer of that family, with its expected
  output, and someone has compared that output with what the computer
  itself or Subsurface shows. The list of checked families lives in code
  with the fixture name for each; a test fails if a checked family has no
  fixture.
- **"Share this download":** offered after a download, and after one that
  failed. If the diver turns on "record this download" before starting, the
  C layer keeps the packets. The share sheet exports one file with the
  recording, libdivecomputer's log and the dive envelopes. The diver
  attaches it to a GitHub issue or an email. No new server. The share text
  says plainly that the file contains the diver's dives, serial number and
  any GPS positions.
- **Before a recording goes in the repo,** it is anonymised the way the
  Shearwater fixtures were (#191).
- **Recordings from Subsurface:** divers can make one today, before this
  ships, by saving Subsurface's libdivecomputer log during a normal
  download. The replay needs every packet separately and in order, so it
  reads the combined trace (the `.combined.txt` form, as PR #213's
  `test/fixtures/raw/subsurface2.combined.txt`), not the joined `.read.bin`.
  `extract_libdc_log.py` lives outside the repo today
  (`/Users/egbert/Dev/CCRLog/`); phase 2 moves it into `tool/` so
  contributors can use it.
- **Which families we look for first:** the CCR families, Divesoft and
  Halcyon, then Ratio, Suunto and OSTC. The repo's README and the website
  ask for recordings.

### 10. Licence

- **libdivecomputer is LGPL-2.1-or-later** throughout (`aes.c` is public
  domain). Anchorline is GPL-2.0-only with an app-store exception; LGPL code
  can be used in it.
- **The stores are the only open question.** LGPL 2.1 forbids adding
  restrictions on recipients, and the App Store's and other stores' terms
  arguably do. That is why `LICENSING.md` has an exception for Anchorline's
  own code. That exception can't cover libdivecomputer's code.
- **Jef's permission.** Jef wrote to Egbert: "You are free to use the
  library in your application". That covers his code in the whole library,
  not only the Shearwater parts. The #211 wording in `CONTRIBUTING.md` and
  `NOTICE.md`, which mentions only the ported Shearwater parser, is widened
  to the linked library.
- **Other authors.** Copyright stays with whoever wrote the code, and Jef
  can't give permission for code that isn't his. The headers name other
  authors for these families:

  | Author | Families |
  |---|---|
  | Linus Torvalds | Suunto EON Steel / Core / D5, Deepblu Cosmiq, Oceans S1 |
  | Jan Matoušek (with Jef) | Divesoft Freedom / Liberty |
  | Anton Lundin | OSTC 3 and newer (download side) |
  | Janice McLaughlin | Aqualung i330R, Apeks DSX |
  | Ryan Gardner (with Jef) | Deep Six, Crest, Genesis, Scorpena |
  | John Van Ostrand | Cochran |
  | David Carron (with Jef) | McLean |

  **Every build carries these families,** the **store builds** (iOS,
  Google Play, Mac App Store) as well as the **website builds** (Windows,
  Linux, and anything else distributed outside the stores). Egbert's email
  to Jef (2026-11-16) says so and asks him to pass it on: if any of these
  authors would rather not have their code in the store builds, their
  families go on the leave-out list (section 2) for those builds, and the
  website builds keep them. The list changes in one place.
- **Precedent, for context:** Subsurface-mobile ships the whole library in
  the App Store and Google Play without an exception. In a 2019 talk
  (reported by LWN) the project said it had declared its licence to Apple
  and Google and was never challenged. Its maintainer wrote that they asked
  some library authors, who were fine with it.
- **Obligations:** the full library source with our patches is in the repo.
  `NOTICE.md` gets a libdivecomputer entry for the linked library, and the
  in-app licence page lists it (through `LicenseRegistry`). The native
  library is dynamic on every platform. Because the whole app is open
  source, LGPL's relinking requirement is met either way.

### 11. Testing

- **Replay tests** in `packages/libdivecomputer/test/` run the real native
  build against recordings through the C layer's replay mode, and compare
  the resulting `ConvertedDive`s with committed expected output. They test
  the whole download, not only the parser, and run in CI on Linux. This is
  the same idea as PR #213's simulated Petrel.
- **Mapping tests** in pure Dart feed synthetic libdivecomputer output
  (fields and sample streams) to the mapping and check edge cases:
  resampling, missing values, four cells, no time zone, no serial.
- **Simulated computers** for three families we don't own: Halcyon
  Symbios, OSTC and Ratio. Each is a scripted stand-in that answers
  libdivecomputer's commands over the C layer's replay path, the way a
  real computer would, with synthetic dives in that family's log format.
  Between them they cover the three kinds of Bluetooth behaviour in
  section 4: characteristics to ignore (Halcyon), credit-based flow
  control (OSTC), and backends that lean on `sleep`, `purge` and `poll`
  (Ratio). They also cover the mapping cases: three cells (Halcyon), cells
  from the OSTC, and setpoint only (Ratio). Faults can be injected: a bad
  checksum, a NAK, a dropped packet, a disconnect halfway.

  A stand-in is written from our reading of libdivecomputer's code, so it
  can only find bugs in Anchorline's layers (C layer, Bluetooth profiles,
  mapping), never a difference between libdivecomputer and the real
  computer. A family stays "not yet tested by us" until a real recording
  checks it (section 9).
- **C layer tests:** timeouts, packets bigger than the buffer, cancel
  mid-download, a write that never completes, unhandled ioctls.
- **Refresh tests** (section 7a): a refresh keeps the id and every
  annotation, attachment, merge link, bailout carry and cylinder row;
  cylinders follow their mix when the gas list changes; an older reader
  never overwrites a newer result; a failed parse leaves the dive as it
  was; a Subsurface copy is matched, including the hex and decimal
  serials, and refreshed under its own id; two matching copies replace
  nothing. The Subsurface case uses a real Subsurface repo fixture next to
  a replay of the same dives.
- **Shearwater stays identical:** existing Shearwater tests pass unchanged,
  and a Petrel 3 download through the new shared download shape gives the
  same dives as before (as the June draft required).
- **Build check:** the first build step proves the hook builds and loads on
  all five platforms before anything else depends on it.
- `flutter analyze` clean and `flutter test` passing on every PR, plus
  `dart test` in each package.

### 12. Rollout

Each phase is one or more PRs, planned separately.

1. **Groundwork. No new brands visible.**
   - Brand fields (`dc_vendor`, `dc_product`, `dc_family`,
     `dc_model_code`) with the migration and sync changes; the
     `dive_computers` key change; the bootstrap importer keeping model
     names.
   - Per-cell ppO2 channels and the codec change.
   - Events stored and synced, for Shearwater too.
   - The in-place refresh (section 7a) for Shearwater: re-parse from the
     raw blob after a reader update, refresh on a repeated download, and
     the Subsurface copy match, also used by the bootstrap importer. The
     Shearwater parser version starts counting.
   - The sync parameter that keeps libdivecomputer dives away from older
     app versions (section 7), shipped and rolled out before phase 2.
   - The shared download shape, with Shearwater wrapped behind it and
     verified on a Petrel 3.
2. **Bluetooth computers on all five platforms.**
   - `packages/libdivecomputer/` with the build hook, pinned upstream,
     patch folder, bindings, C layer, mapping and replay tests, and the
     `libdivecomputer-build.yml` workflow (section 2).
   - The app's `LibdcBleLink` over `BleCentral` (with the new
     characteristic read), the per-family Bluetooth profiles, the scan and
     picker, the tiers, "record" and "Share this download".
   - `extract_libdc_log.py` moved into `tool/`.
   - The simulated Halcyon Symbios, OSTC and Ratio (section 11).
   - The Subsurface writer skips these dives (section 7).
   - libdivecomputer dives use the same refresh, with their own parser
     version.
   - The per-dive cell agreement summary for families with cells.
   - Every Bluetooth family listed, "not yet tested by us" until a
     recording checks it.
   - Store and website builds carry the same families. If an author asks
     for their code to stay out of the store builds, the leave-out list
     drops it there (sections 2 and 10).
3. **Cable and classic-Bluetooth computers.** libdivecomputer's serial
   code and a port picker on desktop. Classic Bluetooth through
   libdivecomputer's own code on Windows, and through the app on Android
   and Linux; this brings in the older Ratio iX3M GPS, HW Frog and
   Tecdiving models. Whether USB HID (via hidapi) and plain USB (via
   libusb) are worth their extra native dependency is decided then.
   Android USB cables through the existing SOLO USB channel are a possible
   later step.
4. **Garmin, as FIT file import.** Garmin computers hand over FIT files
   over USB rather than speaking a protocol, and Garmin isn't in upstream
   libdivecomputer. A later design picks between Subsurface's Garmin parser
   and a Dart FIT reader, and covers getting the files on phones.

### 13. Changes to other documents

- **`CLAUDE.md`:**
  - Tech stack: libdivecomputer is linked through FFI, pinned to an
    upstream commit, built with a Dart build hook in
    `packages/libdivecomputer/`; Shearwater stays pure Dart; a brand is
    ported only when needed.
  - Working in this project: the `dive_id` rule gains the libdivecomputer
    form (section 7); `packages/libdivecomputer/` is pure Dart plus its
    native build, the pin moves only through `tool/update_upstream.sh`, and
    every patch goes upstream; imported data changes only through the
    refresh in section 7a.
  - Out of scope: the "Anything not Shearwater" line goes, replaced by the
    Garmin and IrDA notes from this design's non-goals.
- **`docs/PROJECT_PLAN.md`:** the "Phase 4 if at all" line about
  non-Shearwater computers points to this design.
- **June draft (`2026-06-04-multi-dc-driver-architecture-design.md`):**
  status becomes "Superseded in part by 2026-11-15 libdivecomputer
  design".
- **`NOTICE.md`, `CONTRIBUTING.md`:** widened as in section 10.
- **`toolchain-gotchas` skill:** a section on the build hook once phase 2
  has built on all platforms.

## Left to the builder

- The exact hook user-define mechanism for the leave-out list, per build
  (it starts empty).
- `config.h` contents per platform; which `src/` files are platform-only.
- The ffigen version and configuration.
- Isolate lifetime (one per download or one long-lived), and the C layer's
  queue sizes and default timeouts.
- The per-family Bluetooth profiles in detail, and how to pick among
  several candidate services for a family with no profile yet.
- BLE write chunking if a write is larger than the MTU.
- Resampling details: grid choice, how to treat a sample with no depth.
- Which libdivecomputer events map to which `DiveEventType`s, and the
  events blob encoding.
- The stand-in when a family reports serial 0.
- The start-time window for matching a Subsurface copy (a minute is a
  starting point), and how a Subsurface model string is compared with a
  brand.
- Which values a Shearwater re-parse takes from the stored row rather
  than the raw blob (for example the model and serial).
- When the background re-parse runs, and how the diver sees flagged
  pairs.
- The thresholds for the cell agreement summary (shown to Egbert).
- Picker and badge layout, following the existing import screen.
- The share file's format.

## Risks

- **Build hooks on all five platforms.** The standard path, but new to this
  project. Mitigated by making it the first step of phase 2, with a
  prebuilt fallback.
- **Untested families misbehave.** A family we've never seen might hang or
  produce odd dives. Mitigated by the tier label, the recordings, raw blobs
  that allow re-parsing after a fix, and per-dive atomic commits.
- **Native crashes.** A bug in C takes the app down rather than throwing.
  Sentry captures native crashes; replay recordings make them reproducible.
- **Bluetooth differences per platform.** Notification sizes, MTU and write
  behaviour differ. The `BleCentral` seam already absorbs some of this for
  the SOLO bridge and the label printer.
- **An author asks to be left out.** If one of the other authors (section
  10) asks for their code to stay out of the store builds, those families
  leave the store builds from the next release: divers on those builds keep
  their dives but can't download new ones there. Website builds aren't
  affected.
- **A refresh bug damages many dives at once.** A refresh rewrites
  imported data on every device through sync. Mitigated by the refresh
  tests, the rule that a failed or empty parse never replaces a dive, and
  user data never being touched.
- **Upstream moves under us.** A pin move may change output for a checked
  family. Replay tests catch it, and the pin only moves in a reviewed PR.

## Follow-ups outside this design

- Shearwater import on Windows: move it onto `BleCentral`.
- The Subsurface writer for other brands, with Subsurface's own ids
  (section 7).
- The raw-blob write joining the PowerSync transaction (principle 8).
- Cleaning up the duplicate pairs that already exist (Shearwater downloads
  after a bootstrap import). The refresh prevents new ones but doesn't
  fold existing pairs, which may both carry annotations.
- Pushing refreshed dives to Subsurface Cloud. The writer never rewrites a
  dive it has pushed, so Subsurface keeps the older data.
- The PIN prompt for Aqualung i330R / Apeks DSX.
- Longitudinal ppO2-based cell health (section 8).
- The Divesoft millivolt patch to Jef (section 8).
- Phase 3 and phase 4 designs.
