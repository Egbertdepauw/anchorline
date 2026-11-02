# Multi-dive-computer driver architecture (`LibDartDc`)

**Date:** 2026-06-04
**Status:** Draft — pending review
**Area:** new `lib/devices/` framework; `lib/shearwater/` (wrapped, not moved); `lib/data/models/sample_set.dart`; `lib/data/sample_codec/`; `lib/data/db/dive_dao.dart`; `lib/ui/notifiers/import_notifier.dart`

## Problem

CCRLog imports from Shearwater only. We want to support more dive computers —
prioritised, easy-first: **Ratio → Divesoft (Liberty/Freedom) → Halcyon Symbios →
Heinrichs-Weikamp OSTC**, with Garmin Descent and newer Suunto (Ocean/Nautic) as
later special cases. The Shearwater import path is a set of concrete, vendor-named
classes with no driver abstraction, so adding a vendor today would mean forking the
orchestrator.

This spec defines the **driver abstraction** that makes multi-DC support possible,
the **engine strategy** (pure-Dart ports, not libdivecomputer FFI), and the
**data-model changes** the new vendors force. It is the architecture spec; each DC
port is a follow-on spec/plan that slots into this framework.

## North star

`LibDartDc` — a **standalone, pure-Dart, dependency-free dive-computer library**.
libdivecomputer (in its Subsurface fork) is used as the *blueprint* — we port its
backends to Dart — never as a linked C dependency. Shearwater is already this
library's first member. The endgame: every technical DC we care about parsed in
pure Dart, no native build, running everywhere Flutter runs.

## Decisions & rationale

### 1. Two pure-Dart engines; **no FFI**

Shearwater stays on the existing pure-Dart parser. Other DCs get **new pure-Dart
ports** of their libdc backends. We do **not** link or FFI-bridge libdivecomputer.

Why not FFI (the conventional answer):

- **Native-build tax.** Any FFI — even "parser-only FFI" where transport stays in
  Dart — requires compiling libdc for every target (macOS, iOS, Android, Windows,
  Linux). This project has repeatedly bled on exactly this class of work (the
  git2dart libgit2/libcrypto saga; Xcode SDK shadowing; Windows not yet building).
  A pure-Dart port has **zero** native build and works on iOS/Windows/Linux/Web for
  free.
- **Transport mismatch.** libdc's cross-platform BLE story is uneven (no Android
  BLE in libdc — Subsurface supplies it). With FFI we'd have to bridge
  `flutter_blue_plus` into libdc's synchronous custom-I/O transport anyway. We
  already own a working Dart BLE transport.
- **North-star alignment.** FFI would be throwaway scaffolding; the roadmap ends at
  pure Dart regardless. Skipping the FFI rung means no rework.
- **The near-term list needs none of FFI's breadth.** The Phase-1 DCs are clean
  serial-over-BLE protocols — "another Shearwater" each. The DCs that could justify
  FFI's instant breadth (Garmin's FIT format, USB-only Suunto) are exactly the ones
  deferred.

**Escape hatch (documented, not default):** the driver interface is agnostic to
*how* a driver parses. If a future parser is genuinely uneconomical to reimplement
(Garmin FIT is the candidate), that one driver could be backed by parser-only FFI
without disturbing the others. This is the exception, accepted only with eyes open
about the native-build cost it reintroduces.

### 2. Shearwater stays pure-Dart — evidence, not assertion

A field-coverage cross-check of our Dart parser against libdc's Shearwater backend
found: our parser is a **direct port of `shearwater_predator_parser.c`** (it reads
the identical bytes at identical offsets), so routing Shearwater through libdc would
gain **zero** new fields while **losing** the three things the app is built around:

- **Raw per-cell mV** — libdc multiplies each cell by its calibration factor and
  emits per-cell *PPO2*, discarding the mV. Our longitudinal cell-health feature
  needs the raw mV.
- **Scrubber / stack time** — absent from libdc entirely.
- **Fine dive-mode taxonomy** (OC-tec vs OC-rec, cc vs cc2, Avelo) — libdc's
  `DC_FIELD_DIVEMODE` collapses to 5 coarse modes.

Nothing in libdc is worth backfilling (solenoid, GF99/surfGF, OTU, device battery
are missing from both; avg-depth / surface-temp are trivial local derivations). The
decision to keep Shearwater on Dart is therefore data-backed.

### 3. The convergence seam already exists and is already source-agnostic

`ConvertedDive → DiveDao.importDive(converted, rawBlob, parserVersion)` is **already
hit by two unrelated sources**: the Shearwater BLE path and the Subsurface-git
bootstrap importer (which builds `ConvertedDive` directly, bypassing the Shearwater
parser). Everything downstream of `ConvertedDive` — dedup by `dive_id`, the
PowerSync/Drift commit, the columnar codec, resumability — is already vendor-neutral.

**Consequence:** the driver abstraction does *not* touch persistence. A driver only
has to **terminate in `ConvertedDive` + raw blob.** This makes the change far
smaller and safer than "add a second import engine."

## Architecture

### Layered model

```
┌──────────────────────────────────────────────────────────────────┐
│  APP  (Flutter — BLE, USB, DB, UI)                                 │
│   • Transport impls:  BleTransport (flutter_blue_plus)             │
│                       UsbTransport (desktop, Phase 2)              │
│   • Discovery: scan/enumerate, filtered by driver.discovery        │
│   • Import orchestrator (generalised ImportNotifier):              │
│       open → enumerate → dedup → download → COMMIT                 │
│       (per-dive atomic, resumable on disconnect)                   │
│   • Persistence: DiveDao.importDive() → PowerSync   [UNCHANGED]    │
└───────────────▲───────────────────────────────────▲──────────────┘
                │ injects Transport                  │ emits ConvertedDive + rawBlob
┌───────────────┴───────────────────────────────────┴──────────────┐
│  LibDartDc   (pure Dart — NO Flutter, NO BLE, NO DB)              │
│   • Transport            (interface — duplex byte/frame pipe)     │
│   • DiveComputerDriver   (interface)                              │
│   • DiveComputerRegistry (vendor/model → driver, platform-filtered)│
│   • Drivers + parsers:   Shearwater · Ratio · Divesoft · Symbios  │
│                          · OSTC · …                               │
│   • Neutral domain vocab: DiveMode · DecoModel · TankUsage ·      │
│                           DcModelId · ConvertedDive · Dive · …    │
└──────────────────────────────────────────────────────────────────┘
```

`LibDartDc` is **transport-agnostic and persistence-agnostic**: it defines
`Transport` as an *interface* and emits plain domain structs. BLE/USB transport
*implementations* and the DB commit live in the app. This is the same purity rule
as the existing Shearwater parser, extended to the whole DC layer — and it is what
makes `LibDartDc` extractable as a standalone package later (CLI reparse tools,
server-side reparse).

**Initial home:** `lib/devices/` holds the framework (interfaces, registry, neutral
vocab) and new drivers. `lib/shearwater/` is **referenced, not moved** in the first
pass (its driver wrapper implements the `lib/devices/` interface) to keep the diff
small; consolidation under `LibDartDc` is the eventual extraction step, not a
prerequisite.

### `DiveComputerDriver` interface

The mapper's first cut took a `BluetoothDevice` directly, which would leak
`flutter_blue_plus` into the pure layer. Corrected: **discovery stays app-side; an
opened `Transport` is injected.** The driver never imports BLE.

```dart
abstract class DiveComputerDriver {
  String          get vendor;
  List<DcModelId> get supportedModels;
  DiscoveryFilter get discovery;      // BLE service UUIDs  |  USB VID:PID
  DownloadModel   get downloadModel;  // incrementalStream  |  fullDump

  Future<DeviceInfo>           open(Transport t);
  Future<List<DiveDescriptor>> enumerate({Uint8List? lastFingerprint});
  Stream<DriverEvent>          download(List<DiveDescriptor> dives); // terminal → ConvertedDive + rawBlob
  Future<void>                 close();
}
```

- `DiveDescriptor` is the vendor-neutral header the orchestrator needs:
  `{ diveNumber, startTimestampUtc, fingerprint, sizeHintBytes? }` — everything
  `generateDiveId` and dedup consume. (Shearwater's flash-address `ManifestEntry`
  becomes a Shearwater-internal detail behind `enumerate`.)
- `DriverEvent` mirrors today's `DownloadEvent`: progress events plus a terminal
  event carrying `ConvertedDive` + `rawBlob`. Drivers with no recoverable raw blob
  pass `Uint8List(0)` + a sentinel `parserVersion`, exactly as the Subsurface
  bootstrap does (`parserVersion: -1`).
- **`parse` is a pure function** inside each driver (bytes → `ConvertedDive`),
  separable for `.bin`-fixture tests — same contract Shearwater has today.

### `Transport` interface

Generalise the **existing `BleIo`** seam (`lib/shearwater/ble/protocol.dart`),
already a clean byte-I/O abstraction with a real impl and a mock:

```dart
abstract class Transport {
  Future<void>          writeBytes(Uint8List data);
  Future<List<Uint8List>> readFrames();   // one frame per BLE notification / USB chunk
  void                  drainPendingFrames();
}
```

- `BleTransport` (today's `FlutterBluePlusBleIo`) implements it now — all platforms.
- `UsbTransport` implements it for desktop in Phase 2.
- `ShearwaterProtocol` already sits on `BleIo`, so Shearwater-as-driver is a
  near-mechanical wrap.

### Registry & discovery filtering

```dart
class DiveComputerRegistry {
  Iterable<DiveComputerDriver> availableFor(Platform p, Set<TransportKind> t);
  DiveComputerDriver? forModel(DcModelId id);
}
```

- The download-source picker lists only drivers whose transport is reachable on the
  current platform: **BLE = all platforms; USB = desktop only.** Unreachable DCs do
  not appear — no "tap to connect, then fail" dead-ends.
- The BLE scanner filters on each driver's `discovery` service UUIDs. **Per-vendor
  UUIDs differ even when packet structure is near-identical** (confirmed for
  Divesoft vs Halcyon), so discovery keys on per-driver UUIDs, never a shared
  descriptor.
- **Migration = a one-line registry change.** Moving a DC from "libdc territory" to
  "ported" is swapping which driver `forModel` returns. Nothing else moves.

### Shearwater as the first driver

Build step one is **not** "port Ratio" — it is **extract the interface from the
existing, working Shearwater code**, with `ShearwaterDriver` as the reference
implementation over the current `ShearwaterProtocol` / parser / `DiveConverter`.
This validates the interface against a Petrel you own *before* any new port. If the
interface can't express Shearwater cleanly, that surfaces immediately on known-good
ground. The mock transport becomes "just another driver," collapsing the
real-vs-mock branching in `ImportNotifier`.

## Data-model changes

### A. Vendor-neutral vocabulary hoist (first PR)

`Dive.dcModel` is typed `ShearwaterModel`, and `DiveMode` / `DecoModel` /
`TankUsage` physically live under `lib/shearwater/parser/` despite being app-wide
vocabulary (imported by domain, UI, and the Subsurface mapper). Hoist them to a
neutral home (`lib/devices/models/`) and introduce a `DcModelId` (vendor + model
identifier) so non-Shearwater drivers don't import `lib/shearwater/`. Mechanical but
touches many imports — done first so everything else builds on neutral types.

### B. Per-cell PPO2 channels (model both)

`SampleSet` today carries only raw mV (`cellMv0/1/2`); per-cell PPO2 is derived at
*display* time as `mV × sensorCalibration[N]`. Other CCRs on the roadmap
(**Divesoft Liberty, Halcyon Symbios**) expose **per-cell PPO2 already calibrated,
not raw mV**. Decision: **model both.**

- Add `cellPpo2_0/1/2` columnar `Float32List` channels to `SampleSet`; bump the
  `SampleCodec` version (additive, back-compatible decode of old blobs).
- Shearwater writes mV (PPO2 still derived from calibration). Divesoft/Symbios write
  per-cell PPO2 only; their mV channels stay empty.
- **mV-drift cell-health analysis stays Shearwater-grade** (it needs mV). A
  per-cell-PPO2 *view* for other CCRs is wired when the first Divesoft/Symbios tester
  lands — implement the channels now to avoid a forced codec migration later.

**Boundary note:** this is orthogonal to `2026-06-03-cell-mv-dual-metric-design.md`,
which is about two *readings* of the mV channel (surface-mean vs per-dive-peak) and
explicitly defers PPO2-normalised health metrics. This spec adds a PPO2 *storage*
channel for vendors that lack mV; it does not change the mV-based health heuristic.

### C. Persist events (bug fix folded in)

`DiveDao.importDive` currently writes **no events** — parsed `DiveEvent`s are dropped
at commit, contradicting CLAUDE.md's "samples, events, and gases all commit
together." Every roadmap DC also emits events (gas switches, alarms, bookmarks).
Wire events into the atomic commit as part of this work, so the convergence seam
honours the architectural principle for all drivers.

## Phasing

- **Phase 1 — BLE DCs (all platforms).** Reuses the existing `flutter_blue_plus`
  transport; ships on mobile *and* desktop. Order: Ratio → Divesoft → Symbios → OSTC.
- **Phase 2 — USB DCs (desktop only: macOS/Windows/Linux).** Adds the
  `UsbTransport` (HID/serial) implementation — a new desktop-only native dependency,
  built only when a USB-only DC reaches the top of the list. Picks up serial OSTCs,
  the USB-HID Suunto family, etc.
- **Later special cases:** Garmin Descent (FIT-format heavy; parser-FFI escape
  hatch is the fallback if a Dart FIT reader proves uneconomical) and newer Suunto
  Ocean/Nautic (not in libdc at all — needs protocol work, not a port).

## Per-DC notes & build order

All Phase-1 vendors use **serial-over-BLE** (Nordic UART `6E400001-…` or a
vendor-specific equivalent) — clean stream protocols, "another Shearwater" in shape.

| Order | DC | libdc backend | Transport | Notes |
|------:|----|---------------|-----------|-------|
| 0 | **Shearwater** (existing) | `shearwater_*` (already ported) | BLE | Wrapped as first driver — interface reference |
| 1 | **Ratio** (iDive/iX3M family) | DiveSystem iDive family (`divesystem_idive` — Ratio rebadges DiveSystem; confirm exact backend at port time) | BLE | First *new* port — validates interface on novel hardware |
| 2 | **Divesoft** (Liberty/Freedom) | `freedom` | BLE | CCR — per-cell PPO2 channels exercised here |
| 3 | **Halcyon Symbios** | `halcyon_symbios` (separate, **parallel** to `freedom`) | BLE | Shared Oxygen-Scientific roots → reuse Divesoft record shape; port right after Divesoft |
| 4 | **Heinrichs-Weikamp OSTC** (Plus/Sport/4 — BLE variants) | `hw_ostc3` | BLE | Older serial OSTC 2 variants → Phase 2 (USB) |

Exact libdc backend filenames are verified against the **Subsurface fork** when each
DC's port plan is written; the names above are the expected families.

Dependency-ordered build sequence (each its own follow-on spec/plan):

1. Vendor-neutral vocabulary hoist (§A).
2. `LibDartDc` core: `Transport` (generalise `BleIo`), `DiveComputerDriver`,
   `DiveDescriptor`, `DeviceInfo`, `DiscoveryFilter`, `DownloadModel`, `DriverEvent`,
   `DiveComputerRegistry`. No behaviour change.
3. `ShearwaterDriver` wrap + generalise `ImportNotifier` to drive a selected driver;
   mock becomes a driver. (Interface validated against Petrel 3.)
4. Data-model: per-cell PPO2 channels + codec bump (§B); persist events (§C).
5. Port **Ratio** (DiveSystem iDive family) — first new DC.
6. Port **Divesoft** (`freedom`) + **Symbios** (`halcyon_symbios`) descriptor.
7. Port **OSTC** (`hw_ostc3`, BLE models).

## Testing strategy

- **`.bin` fixtures per driver.** Each driver's pure `parse` is fixture-tested,
  exactly as Shearwater is. Any Subsurface-running tester supplies a `.read.bin` via
  the `extract_libdc_log.py` pipeline → it becomes a regression fixture, so a DC can
  be ported and validated **without owning the hardware**.
- **Shearwater-through-driver diff.** Route a Petrel 3 download through
  `ShearwaterDriver` and assert the resulting `ConvertedDive` is byte-identical to
  the current direct path — proves the abstraction is lossless before any new port.
- **Reference implementations** to study (not depend on): `deepsealabs/libdc-swift`
  (custom BLE I/O transport shape) and Simone Carletti's *Dive Exporter* (real-world
  raw-BLE Halcyon Symbios extraction).
- `flutter analyze` clean, `flutter test` passing on every step.

## Out of scope / follow-ups

- **`importDive` two-commit-points atomicity.** Today dives+samples commit in a
  PowerSync transaction, then the raw blob writes to Drift *separately* — atomicity
  doesn't span the raw blob (a pre-existing violation of principle #8: a parsed dive
  could end up with no source bytes to re-parse from). Flagged, **not fixed here**
  unless a failure surfaces it. Worth a dedicated follow-up.
- **Parser-only FFI escape hatch** for Garmin FIT — documented, deferred.
- **`UsbTransport`** implementation — Phase 2.
- **Garmin Descent** and **newer Suunto Ocean/Nautic** — later special cases.
- **PPO2-normalised cell-health metric** — already deferred by the dual-metric spec;
  unchanged here.

## Open risks

- **Halcyon Symbios hardware.** No device in hand yet; the port is fixture-driven
  until a tester surfaces. The Divesoft-parallel backend de-risks the parser, but
  the BLE handshake needs a real device or a captured trace to finalise.
- **Per-DC protocol drift across firmware** — the same risk Shearwater has; mitigated
  by the growing fixture library.
- **USB on desktop** reintroduces a (smaller, desktop-only) native dependency in
  Phase 2 — the one place the "no native build" property doesn't hold.
