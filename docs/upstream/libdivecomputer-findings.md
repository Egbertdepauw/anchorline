# libdivecomputer: what Anchorline can share back

Anchorline's Shearwater parser is a Dart translation of libdivecomputer's
Shearwater code. Its author, Jef Driesen, allows Anchorline to ship that
code through the app stores, on the condition that improvements go back to
libdivecomputer (see [`CONTRIBUTING.md`](../../CONTRIBUTING.md#code-derived-from-libdivecomputer)).

This page lists where Anchorline's Shearwater parser and download code
differ from libdivecomputer. It says which differences libdivecomputer
could use, and what the evidence for each one is. Only items that hold up
against today's libdivecomputer master and a real log are proposed for
sending. Egbert sends anything upstream himself.

Checked on 2026-11-15 against:

- **libdivecomputer master**, commit `14f9293` (2026-11-12),
  <https://github.com/libdivecomputer/libdivecomputer>. This includes the
  2026 changes made after Anchorline's port: the model number read
  directly (`f351434`), variable-length init responses (`661cb6e`) and
  Perdix 3 support (`b924092`).
- **Subsurface's libdivecomputer fork**, branch `Subsurface-DS9`, commit
  `469f28d` (2026-11-09), <https://github.com/subsurface/libdc>.
- **Anchorline** `main` at `9ed38ef`: `lib/shearwater/parser/`,
  `lib/shearwater/ble/` and the parser types in
  `packages/subsurface_core/lib/shearwater/parser/`.

## Summary

| Item | Verdict | Kind | How it goes upstream |
| --- | --- | --- | --- |
| Deleted dives hide other dives from the download | Confirmed bug in libdivecomputer master and in the Subsurface fork | Bug fix | C patch [`0001`](patches/0001-Fix-missing-Shearwater-dives-after-a-deleted-dive.patch) |
| Scrubber stack time | Confirmed field; libdivecomputer doesn't read it, the Subsurface fork does | New field | Short note with evidence; adding it needs a new API field, so it's Jef's call |
| LRE decoder accepts a trailing partial 9-bit value | No gap in libdivecomputer; no real log needs it | None | Nothing to send |
| Multi-dive buffers (`_findDiveEnd`) | Anchorline-only; libdivecomputer's download never produces them | None | Nothing to send |
| Manifest fields at +8 and +24 | Real fields, but libdivecomputer doesn't need them | None | Nothing to send (layout recorded below) |
| NAK 0x24 recovery and pipelined block requests | Anchorline-only; only happens when blocks are requested past the end of a dive | None | Nothing to send |
| Raw cell millivolts kept | Design choice for cell-health analysis | Anchorline-only | Nothing to send |

## The evidence

All findings rest on one recording from Egbert's Petrel 3 (hardware
0xB407, firmware V103 DiveCAN, log version 17):

- [`test/fixtures/raw/subsurface2.combined.txt`](../../test/fixtures/raw/subsurface2.combined.txt)
  is a BLE trace of Subsurface downloading from that Petrel. Subsurface
  uses libdivecomputer, so every request in the trace is
  libdivecomputer's own. It holds five manifest downloads and nine dive
  downloads. Eight dives (#711 to #718) are complete; the ninth (#710)
  stops after 133 blocks, followed by the shutdown command.
- [`test/fixtures/manifest.bin`](../../test/fixtures/manifest.bin) is the
  five manifest pages from that trace, unchanged.
- [`test/fixtures/dives/dive_711.bin`](../../test/fixtures/dives/) to
  `dive_718.bin` are byte for byte the dives that libdivecomputer
  decompressed from that trace.

Two tools in [`tools/`](tools/) reproduce everything below:

- [`shearwater_trace.py`](tools/shearwater_trace.py) decodes the trace:
  for every download it prints the requested address and size, every
  block's length, whether each length passes libdivecomputer's 9-bit
  check, where the LRE end marker falls and how the download ended. It
  can also write out the manifest and every dive's compressed stream.
- [`petrel_replay.c`](tools/petrel_replay.c) is a simulated Petrel that
  serves those recorded bytes over libdivecomputer's custom I/O stream.
  It runs libdivecomputer's own Shearwater driver against them and
  reports any manifest record that was never downloaded.

See [Reproducing the results](#reproducing-the-results) for the commands.

## 1. Deleted dives hide other dives from the download

**Verdict: bug in libdivecomputer. Worth sending as a C patch.**

### What libdivecomputer does today

When a dive is deleted on a Shearwater, its 32-byte manifest record stays
where it is, with the header 0x5A23 instead of 0xA5C4.
`shearwater_petrel_device_foreach()` in `src/shearwater_petrel.c` walks
each 48-record manifest page, counting valid records in `count` and
deleted ones in `deleted`. It stops at the dive that matches the
fingerprint or at the first record that is neither. Then it appends the
page to the list of dives to download:

```c
if (!dc_buffer_append (manifests, data, count * RECORD_SIZE)) {
```

That copies the first `count` records of the page. Any deleted records
among them take up places in that span, so the last `deleted` records
before the stop point are cut off. The download loop then skips the
deleted records it did copy. Every valid dive among the records that were
cut off is never downloaded, without any error or warning. That is up to
one dive for every deleted record in the page:

- on an incremental download, the oldest new dives (the ones just newer
  than the last download) go missing;
- on a full download, the last dives of each full page go missing.

The skip for deleted dives was added in 2018 (`864b40c`, "Shearwater:
skip deleted dives"); the append line is older and wasn't updated. The
Subsurface fork has the same line.

### What Anchorline does differently

`ShearwaterBleTransport.readManifest()` keeps walking each record and
skips deleted ones as it goes, so it never loses a valid record.

### Evidence

The Petrel's own manifest has no deleted dives, so the bug can't be seen
in the recording as it is. The replay harness shows it with
libdivecomputer's own code: it serves the recorded manifest with one or
more records marked deleted (header 0x5A23, which is all the Petrel
changes), and the recorded dive data.

| Scenario | libdivecomputer master `14f9293` | With the patch |
| --- | --- | --- |
| As recorded, fingerprint at #710 | 8 of 8 dives | 8 of 8 dives |
| #716 deleted, fingerprint at #710 | 6 of 7; **#711 missing** | 7 of 7 |
| #716 and #713 deleted, fingerprint at #710 | 4 of 6; **#712 and #711 missing** | 6 of 6 |
| Full log, #716 deleted | 228 of 229; **#671 missing** | 229 of 229 |
| Full log, records 0, 47 and 50 deleted | 225 of 227; **#672 and #623 missing** | 227 of 227 |
| Full log, nothing deleted | 230 of 230 | 230 of 230 |

For the full-log runs, dives that aren't in the recording are served as
empty dives (a stream that is just the LRE end marker), because the
question is only which dives libdivecomputer asks for.

### The fix

Append every record up to the point where the loop stopped, deleted ones
included. At that point `offset` is exactly `(count + deleted) *
RECORD_SIZE`:

```c
if (!dc_buffer_append (manifests, data, offset)) {
```

The download loop already skips deleted records, and the progress
calculation already counts them, so nothing else changes. The patch,
[`patches/0001-Fix-missing-Shearwater-dives-after-a-deleted-dive.patch`](patches/0001-Fix-missing-Shearwater-dives-after-a-deleted-dive.patch),
applies with `git am` to libdivecomputer master `14f9293` and, with `git
apply`, to the Subsurface fork.

## 2. Scrubber stack time

**Verdict: a real field that upstream libdivecomputer doesn't read.
Worth a short note; no patch.**

### Where it is

In the Petrel Native Format, with log version 11 or later, three 16-bit
big-endian values, all in seconds:

| Value | Location |
| --- | --- |
| Configured stack time (0 when the scrubber timer is off) | opening record 6 (type 0x16), bytes 1–2 |
| Stack time remaining at the start of the dive | opening record 6, bytes 3–4 |
| Stack time remaining at the end of the dive | closing record 6 (type 0x26), bytes 3–4 |

### What libdivecomputer does today

Upstream libdivecomputer doesn't read these bytes, and it has no field to
report them: there is no `DC_FIELD_STRING` or scrubber field in its API.
The Subsurface fork reads the same three values from the same offsets
(log version 11 and later) and reports them as text fields ("Configured
stack time", "Remaining stack time at start/at end"). Anchorline took the
offsets from the fork, so this isn't Anchorline's discovery.

### Evidence

Eight consecutive dives in the fixtures (Petrel 3, firmware V103, log
version 17) are consistent with each other:

| Dive | Configured | At start | At end | Used | Dive time |
| --- | --- | --- | --- | --- | --- |
| #711 | 25,200 s | 25,199 s | 22,211 s | 2,988 s | 2,933 s |
| #712 | 25,200 s | 22,211 s | 17,892 s | 4,319 s | 4,263 s |
| #713 | 25,200 s | 17,891 s | 14,687 s | 3,204 s | 3,149 s |
| #714 | 25,200 s | 14,687 s | 10,847 s | 3,840 s | 3,784 s |
| #715 | 25,200 s | 10,847 s | 7,347 s | 3,500 s | 3,444 s |
| #716 | 25,200 s | 7,347 s | 3,671 s | 3,676 s | 3,620 s |
| #717 | 25,200 s | 25,200 s | 23,777 s | 1,423 s | 1,367 s |
| #718 | 25,200 s | 23,777 s | 20,293 s | 3,484 s | 3,428 s |

The configured time is 7 hours. The time left at the end of one dive is
the time left at the start of the next (once 1 second apart). It resets
to the full 7 hours at #717, a fresh fill. Each dive uses 55 to 56
seconds more than its dive time.

### How it could go upstream

As a note: the offsets, the log version, and this table as independent
confirmation of what the Subsurface fork already decodes. Whether and how
to expose it is an API decision for Jef.

## 3. LRE decoder and a trailing partial 9-bit value

**Verdict: no gap in libdivecomputer. Nothing to send.**

### What libdivecomputer does today

`shearwater_common_decompress_lre()` decompresses each block as it
arrives. It rejects a block whose length isn't a whole number of 9-bit
values, which in bytes means a multiple of 9.

### What Anchorline does differently

`lreDecode()` in `lib/shearwater/parser/decompressor.dart` ignores up to
8 leftover bits at the end instead of failing. Anchorline needs that
because it decodes the whole buffer received so far after every block,
not one block at a time. A commit from May 2026 claimed that block
boundaries fall in the middle of a 9-bit value, so per-block decoding
"does not work". The trace shows that claim was wrong.

### Evidence

- The Petrel 3 announces its block size in the init response:
  `75 10 92`, a maximum packet of 0x92 = 146 bytes, which is a 2-byte
  header plus 144 bytes of data. 144 bytes is exactly 128 values of 9
  bits.
- All 3,009 compressed blocks in the trace are 144 bytes long, the last
  block of each dive included. Every one passes libdivecomputer's check.
- In each of the eight complete dive downloads, the LRE end marker is in
  the last block. libdivecomputer then sends the quit command and the
  Petrel acknowledges it (`77 00`).
- For the Perdix 3, libdivecomputer's own comment in
  `shearwater_common.c` gives the largest observed dive packet as 0x0902
  bytes, which is 0x900 = 2,304 bytes of data, also a multiple of 9.

No real log needs the tolerance, so there is nothing to change upstream.

## 4. Multi-dive buffers

**Verdict: Anchorline-only. Nothing to send.**

`_findDiveEnd()` and `parseOne()` in `lib/shearwater/parser/dive_parser.dart`
split a buffer that holds several dives back to back. Such a buffer only
existed during an Anchorline experiment in May 2026 that downloaded the
whole log in one session. That design was reverted in June 2026 (#40);
Anchorline now downloads one dive at a time, as libdivecomputer does.

libdivecomputer requests each dive from its manifest address with the
size set to 0xFFFFFF and stops at the end marker. In the trace, each of
the eight complete downloads holds exactly one dive: one final record
(type 0xFF) followed by zero padding to the next 128-byte boundary. The
claims in Anchorline's code that "the LRE end-marker only fires at the
very end of the on-flash log" and that libdivecomputer "has always done
one big download" are wrong; see [Follow-ups in Anchorline](#follow-ups-in-anchorline).

## 5. Manifest fields at +8 and +24

**Verdict: real fields that libdivecomputer doesn't need. Nothing to send.**

libdivecomputer reads three things from a 32-byte manifest record: the
header (+0), the fingerprint (+4) and the dive's start address (+20).
`ManifestParser` in Anchorline also reads +8 and +24. Checked against the
eight complete dives, the record looks like this (all big-endian):

| Offset | Size | Meaning | Evidence for #718 |
| --- | --- | --- | --- |
| +0 | 2 | Header: 0xA5C4 valid, 0x5A23 deleted | 0xA5C4 |
| +2 | 2 | Dive number | 718 |
| +4 | 4 | Start time, also the fingerprint | same as opening record 0, bytes 12–15 |
| +8 | 4 | A second timestamp: start time plus the dive time, less 5 or 6 seconds | start + 3,423 s |
| +12 | 4 | Dive time in seconds | 3,428 s, same as closing record 0 |
| +16 | 2 | Maximum depth in 0.1 m | 392, same as closing record 0 |
| +18 | 2 | A second counter, always the dive number minus 486 on this unit | 232 |
| +20 | 4 | Start address of the dive, relative to the log base | 0x008A6AC0 |
| +24 | 4 | An end address of unknown meaning | 0x008B9C20 |
| +28 | 4 | Constant on this unit | 0x00020002 |

The +24 field is not the download size. For #718 it is 78,176 bytes past
the start address, while the Petrel sent 54,576 compressed bytes that
decompressed to 49,152. It isn't the next dive's start either: the gap to
the next newer dive's start address is 33 to 47 kB. From May 2026 until
#40, Anchorline used +24 to set the download size. That made it ask for
blocks past the end of the dive, which caused the NAK in item 6.

Everything in +8 to +18 is also in the dive itself, so libdivecomputer
gains nothing from reading it. The layout is kept here as a reference
only.

## 6. NAK 0x24 recovery and pipelined block requests

**Verdict: Anchorline-only. Nothing to send.**

`ShearwaterProtocol.download()` in `lib/shearwater/ble/protocol.dart` can
keep more than one block request in flight. It also treats a NAK with code
0x24 (request sequence error) as the end of the download and skips the
quit command. According to Anchorline's own debugging notes (`bf3e3f8`,
`dd85b20`), the Petrel sends that NAK when it gets a block request after
the end of the dive's data. libdivecomputer sends one request at a time
and stops at the end marker, so it never asks for more. In the trace,
none of the 14 downloads gets a NAK.

Anchorline itself now downloads like libdivecomputer: one request at a
time (`pipelineWindow: 1`) and size 0xFFFFFF. The NAK handling is only a
safety net.

The speed-up that came with this work, a block round trip down from about
530 ms to 85 ms on Android, came from Android Bluetooth settings: high
connection priority, renewed every 6 seconds, and the 2M PHY. That is a
matter for apps on Android, not for libdivecomputer. The only record of
the measurement is the commit message (`bf3e3f8`), so it isn't proposed
here.

## 7. Raw cell millivolts

**Verdict: a design choice. Nothing to send.**

libdivecomputer reports a ppO2 per sensor: the raw cell value (sample
bytes 12, 14 and 15 after the record type) times that sensor's
calibration factor. It only reports the sensors the Petrel marks as
calibrated, and it ignores all of them when every calibrated sensor still
has the factory value 2100, because their readings are then probably
wrong.

Anchorline stores the raw values, whatever the calibration, and keeps the
calibration factors with the dive so the app can work out a ppO2 when it
shows one. It needs the raw millivolts to track a cell's output over its
lifetime. That is analysis libdivecomputer doesn't do, and its API
reports ppO2, not millivolts.

Context, not a finding: on this DiveCAN Petrel 3 the calibration mask is
0x07 and all three factors are 2100 on every dive, so libdivecomputer
reports only the controller's ppO2 and no per-cell values. On dives #711
and #718 the median ratio of that ppO2 to the average of the three raw
values is 0.0211 bar per unit, close to the factory 2100 (0.021).
The Subsurface fork already estimates a DiveCAN calibration for this
case.

## Follow-ups in Anchorline

The other direction: things Anchorline should take from today's
libdivecomputer, and code comments in Anchorline that the trace shows are
wrong. None of these are upstream items.

- **Model number.** Anchorline still maps the hardware ID (RDBI 0x8050)
  through a copy of the table libdivecomputer removed in `f351434`. An
  unknown hardware ID gives `ShearwaterModel.unknown`. libdivecomputer now
  reads the model number directly with RDBI 0x8060.
- **Init response.** `protocol.dart` requires the second byte of the
  download init response to be 0x10. libdivecomputer reads the length of
  the maximum-packet field from that byte (`661cb6e`), which newer devices
  need.
- **Perdix 3.** libdivecomputer supports the Perdix 3's newer protocol
  variant (`b924092`, `06120b0`); Anchorline doesn't.
- **GNSS location.** libdivecomputer reads the dive's start and end
  location from opening and closing record 9 for log version 17 and later
  (`2686320`, `77759ab`); Anchorline doesn't.
- **Wrong comments.** These say the Petrel's LRE end marker only comes at
  the end of the whole log, that block boundaries split 9-bit values, that
  the manifest's +24 field is the exact compressed size, or that
  libdivecomputer downloads the whole log in one go:
  `ManifestEntry.endAddress` in `manifest_parser.dart`, the block loop in
  `protocol.dart`, `lreDecode()` in `decompressor.dart`, `ParseResult` and
  `_findDiveEnd()` in `dive_parser.dart`, and `downloadDives()` and
  `DownloadProgressEvent` in `shearwater_ble_transport.dart`.
- **Freedive temperature.** Anchorline reads one byte at offset 3 of a
  freedive sample; libdivecomputer reads a signed 16-bit value in 0.1 °C.

## Reproducing the results

You need Python 3, a C compiler, autotools and libtool.

Decode the trace and write out the replay data:

```bash
python3 -I docs/upstream/tools/shearwater_trace.py test/fixtures/raw/subsurface2.combined.txt --dump /tmp/petrel
```

The ninth dive download (#710) is incomplete in the trace. Remove it so
the replay serves #710 as an empty dive:

```bash
rm /tmp/petrel/807c9ce0.lre /tmp/petrel/807c9ce0.bin
```

Build libdivecomputer master as a static library:

```bash
git clone https://github.com/libdivecomputer/libdivecomputer.git /tmp/libdc && cd /tmp/libdc && autoreconf --install && ./configure --disable-shared --without-libusb --without-hidapi --without-bluez --prefix=/tmp/libdc-prefix && make && make install
```

On macOS with Homebrew, run `autoreconf` as `LIBTOOLIZE=glibtoolize
autoreconf --install`.

Build and run the replay:

```bash
cc -o /tmp/petrel_replay docs/upstream/tools/petrel_replay.c -I/tmp/libdc-prefix/include /tmp/libdc-prefix/lib/libdivecomputer.a
```

```bash
/tmp/petrel_replay /tmp/petrel/manifest.bin /tmp/petrel --delete 2 --fingerprint 8
```

`--delete N` marks manifest record N (0 is the newest dive) as deleted.
`--fingerprint N` makes libdivecomputer stop at record N, as on an
incremental download. The program exits with status 3 when a valid dive
wasn't downloaded. To test the fix, apply the patch in `/tmp/libdc` with
`git am`, rebuild, and run the same commands.
