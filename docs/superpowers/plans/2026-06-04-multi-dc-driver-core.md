# Multi-DC Driver Core (`LibDartDc`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce the vendor-neutral `lib/devices/` device layer (`LibDartDc`) — the `Transport`, `DiveComputerDriver`, and registry interfaces plus the neutral domain vocabulary — without changing any runtime behavior.

**Architecture:** Additive new files under `lib/devices/` that depend only on `dart:typed_data` and the plain domain models in `lib/data/models/` (no Flutter, BLE, or DB). Three small "extract + re-export shim" refactors move shared vocabulary (`DiveMode`, `DecoModel`, `TankUsage`, `ConvertedDive`) out of `lib/shearwater/` into the neutral layer, keeping every existing import compiling via `export` shims. This is the foundation that the Shearwater-driver wrap (Plan #2) and each DC port build on. **No behavior changes; the BLE download path and `ImportNotifier` are untouched here.**

**Tech Stack:** Dart 3.11, Flutter, `flutter_test`. Pure-Dart layer (no codegen).

**Source spec:** `docs/superpowers/specs/2026-06-04-multi-dc-driver-architecture-design.md`

---

## Scope

This is **Plan #1 of a series**. It delivers only the abstraction core. Explicitly **out of scope** (later plans):

- **Plan #2:** Wrap Shearwater as the first `DiveComputerDriver`; generalize `ImportNotifier`; introduce `Dive.dcModel : DcModelId`. (The risky integration.)
- **Plan #3:** Data-model changes — per-cell PPO2 channels + event persistence.
- **Plan #4+:** Per-DC ports (Ratio → Divesoft+Symbios → OSTC).

## Pre-flight

- [ ] **Create a feature branch** (the repo's rule: never commit on `main`).

```bash
cd /Users/egbert/Dev/CCRLog/ccrlogger
git fetch origin
git switch -c feat/multi-dc-driver-core
```

## File structure

**Created (all pure Dart, no Flutter/BLE/DB imports):**

- `lib/devices/models/dive_enums.dart` — neutral `DiveMode`, `DecoModel`, `TankUsage` (moved from `lib/shearwater/`)
- `lib/devices/models/converted_dive.dart` — neutral `ConvertedDive` (moved from `lib/shearwater/parser/dive_converter.dart`)
- `lib/devices/models/dc_model.dart` — new `DcVendor`, `DcModelId`
- `lib/devices/transport.dart` — new `Transport` interface (generalizes `BleIo`)
- `lib/devices/dive_computer_driver.dart` — new `DiveComputerDriver` + `DiscoveryFilter`, `DcDeviceInfo`, `DiveDescriptor`, `DownloadModel`, `TransportKind`, `DriverEvent`
- `lib/devices/dive_computer_registry.dart` — new `DiveComputerRegistry`
- `test/devices/transport_test.dart`, `test/devices/dive_computer_registry_test.dart`, `test/devices/dive_enums_reexport_test.dart`

**Modified (extract + re-export shim, or one-line supertype):**

- `lib/shearwater/parser/constants.dart` — remove `DiveMode`/`DecoModel`, add re-export
- `lib/shearwater/parser/parsed_dive.dart` — remove `TankUsage`, import + re-export it
- `lib/shearwater/parser/dive_converter.dart` — remove `ConvertedDive` class, import + re-export it
- `lib/shearwater/ble/protocol.dart` — `BleIo` `implements Transport` (one line + import)

---

## Task 1: Extract `DiveMode` + `DecoModel` into the neutral layer

**Files:**
- Create: `lib/devices/models/dive_enums.dart`
- Modify: `lib/shearwater/parser/constants.dart:47-82` (remove the two enums, add a re-export)
- Test: `test/devices/dive_enums_reexport_test.dart`

- [ ] **Step 1: Write the new neutral enums file**

Create `lib/devices/models/dive_enums.dart` with the two enums copied **verbatim** from `constants.dart` (so behavior, `value`s, and helpers are identical):

```dart
/// Vendor-neutral dive vocabulary for the LibDartDc device layer.
///
/// Pure Dart — no Flutter, BLE, or I/O dependency. Drivers (Shearwater and
/// ported DCs) and the domain model share these enums. The integer `value`s
/// mirror the Shearwater binary encoding because that is where they were
/// first defined; other vendors map their own raw values onto these.
library;

// ── Dive modes ─────────────────────────────────────────────────

enum DiveMode {
  cc(0), // Closed Circuit
  ocTec(1), // Open Circuit Technical
  gauge(2),
  ppo2(3),
  sc(4), // Semi-Closed
  cc2(5), // Closed Circuit variant 2
  ocRec(6), // Open Circuit Recreational
  freedive(7),
  avelo(12);

  final int value;
  const DiveMode(this.value);

  static DiveMode fromValue(int v) =>
      DiveMode.values.firstWhere((m) => m.value == v, orElse: () => ocTec);

  bool get isCcr => this == cc || this == cc2 || this == sc;
}

// ── Deco models ────────────────────────────────────────────────

enum DecoModel {
  gf(0), // Buhlmann with Gradient Factors
  vpmb(1),
  vpmbGfs(2),
  dciem(3);

  final int value;
  const DecoModel(this.value);

  static DecoModel fromValue(int v) =>
      DecoModel.values.firstWhere((m) => m.value == v, orElse: () => gf);
}
```

- [ ] **Step 2: Remove the enums from `constants.dart` and add a re-export shim**

In `lib/shearwater/parser/constants.dart`, delete lines **47–82** — both the `// ── Dive modes ──` and `// ── Deco models ──` banners and the full `DiveMode` and `DecoModel` enum bodies. Then add a single re-export near the top of the file's body (just after the `library;` line on line 6):

```dart
// DiveMode and DecoModel moved to the vendor-neutral device layer. Re-exported
// here so the ~25 existing `import '.../constants.dart'` call sites keep working.
export '../../devices/models/dive_enums.dart' show DiveMode, DecoModel;
```

Leave every other constant in `constants.dart` untouched.

- [ ] **Step 3: Write the re-export regression test**

Create `test/devices/dive_enums_reexport_test.dart`:

```dart
import 'package:ccrlogger/devices/models/dive_enums.dart';
import 'package:ccrlogger/shearwater/parser/constants.dart' as constants;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DiveMode is usable from the neutral layer with unchanged values', () {
    expect(DiveMode.cc.value, 0);
    expect(DiveMode.avelo.value, 12);
    expect(DiveMode.fromValue(5), DiveMode.cc2);
    expect(DiveMode.cc.isCcr, isTrue);
    expect(DiveMode.ocTec.isCcr, isFalse);
  });

  test('DecoModel is usable from the neutral layer with unchanged values', () {
    expect(DecoModel.gf.value, 0);
    expect(DecoModel.fromValue(99), DecoModel.gf); // orElse fallback
  });

  test('constants.dart still re-exports the same DiveMode type', () {
    // Identity check: the symbol reached via constants.dart is the same enum.
    const constants.DiveMode m = DiveMode.cc;
    expect(m, DiveMode.cc);
  });
}
```

- [ ] **Step 4: Run analyzer and tests**

```bash
flutter analyze
flutter test test/devices/dive_enums_reexport_test.dart
```
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 5: Run the full suite to prove the move broke no existing import**

```bash
flutter test
```
Expected: all tests pass (DiveMode/DecoModel resolve through the re-export at every existing call site).

- [ ] **Step 6: Commit**

```bash
git add lib/devices/models/dive_enums.dart lib/shearwater/parser/constants.dart test/devices/dive_enums_reexport_test.dart
git commit -m "refactor(devices): extract DiveMode/DecoModel to neutral device layer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Hoist `TankUsage` into the neutral layer

**Files:**
- Modify: `lib/devices/models/dive_enums.dart` (append `TankUsage`)
- Modify: `lib/shearwater/parser/parsed_dive.dart:173` (remove the enum, import + re-export it)
- Test: extend `test/devices/dive_enums_reexport_test.dart`

- [ ] **Step 1: Append `TankUsage` to the neutral enums file**

Add to the end of `lib/devices/models/dive_enums.dart`:

```dart

// ── Tank usage ─────────────────────────────────────────────────

enum TankUsage { none, sidemount, oxygen, diluent }
```

- [ ] **Step 2: Remove `TankUsage` from `parsed_dive.dart`, import + re-export it**

In `lib/shearwater/parser/parsed_dive.dart`:
- Delete the line `enum TankUsage { none, sidemount, oxygen, diluent }` (line 173).
- Add an import at the top of the file (with the other imports):

```dart
import '../../devices/models/dive_enums.dart';
```

- Add a re-export so external call sites that do `import '.../parsed_dive.dart'` still see `TankUsage`:

```dart
export '../../devices/models/dive_enums.dart' show TankUsage;
```

(`parsed_dive.dart` uses `TankUsage` internally on `TankInfo`/`TankUsage.none`; the new import satisfies those references.)

- [ ] **Step 3: Add a regression assertion**

Append to `test/devices/dive_enums_reexport_test.dart` inside `main()`:

```dart
  test('TankUsage is available from the neutral layer', () {
    expect(TankUsage.values, hasLength(4));
    expect(TankUsage.diluent.index, 3);
  });
```

- [ ] **Step 4: Run analyzer + targeted test**

```bash
flutter analyze
flutter test test/devices/dive_enums_reexport_test.dart
```
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 5: Full-suite regression**

```bash
flutter test
```
Expected: all pass (every `TankUsage` reference — converter, UI, Subsurface mapper — resolves through import or re-export).

- [ ] **Step 6: Commit**

```bash
git add lib/devices/models/dive_enums.dart lib/shearwater/parser/parsed_dive.dart test/devices/dive_enums_reexport_test.dart
git commit -m "refactor(devices): hoist TankUsage to neutral device layer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Hoist `ConvertedDive` into the neutral layer

**Files:**
- Create: `lib/devices/models/converted_dive.dart`
- Modify: `lib/shearwater/parser/dive_converter.dart:23-29` (remove the class, import + re-export)
- Test: `test/devices/converted_dive_test.dart`

- [ ] **Step 1: Create the neutral `ConvertedDive`**

Create `lib/devices/models/converted_dive.dart` (constructor kept non-`const`, matching the original — `Dive`/`SampleSet` are not const-constructible):

```dart
/// Result of converting a parsed dive: domain [Dive] + [SampleSet].
///
/// Lives in the vendor-neutral device layer so any driver — Shearwater or a
/// ported DC — can produce one and hand it to `DiveDao.importDive`, the
/// source-agnostic commit seam. Pure Dart: depends only on the plain domain
/// models, not on Flutter/BLE/DB.
library;

import '../../data/models/dive.dart';
import '../../data/models/sample_set.dart';

class ConvertedDive {
  final Dive dive;
  final SampleSet samples;

  ConvertedDive({required this.dive, required this.samples});
}
```

- [ ] **Step 2: Remove `ConvertedDive` from `dive_converter.dart`, import + re-export**

In `lib/shearwater/parser/dive_converter.dart`:
- Delete the `ConvertedDive` class definition (lines 23-29, the `/// Result of converting a parsed dive.` doc + class body).
- Add to the imports:

```dart
import '../../devices/models/converted_dive.dart';
```

- Add a re-export under the imports so existing `import '.../dive_converter.dart'` sites still see `ConvertedDive`:

```dart
export '../../devices/models/converted_dive.dart' show ConvertedDive;
```

The `DiveConverter.convert(...)` method still returns `ConvertedDive` (now resolved via the import) with no body change.

- [ ] **Step 3: Write the re-export identity test**

Create `test/devices/converted_dive_test.dart`. This proves the move + re-export without constructing the wide `Dive`/`SampleSet` types — the existing converter/import suite (Step 5) already exercises real `ConvertedDive` construction end-to-end:

```dart
import 'package:ccrlogger/devices/models/converted_dive.dart' as neutral;
import 'package:ccrlogger/shearwater/parser/dive_converter.dart' as shearwater;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ConvertedDive resolves to one type via the neutral and the '
      'shearwater (re-exported) import paths', () {
    // A class name used as an expression is its Type object; identical
    // classes compare equal. If the re-export pointed at a different (e.g.
    // duplicated) class, this would fail.
    expect(neutral.ConvertedDive, shearwater.ConvertedDive);
  });
}
```

- [ ] **Step 4: Run analyzer + test**

```bash
flutter analyze
flutter test test/devices/converted_dive_test.dart
```
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 5: Full-suite regression**

```bash
flutter test
```
Expected: all pass (the bootstrap importer, `ImportNotifier`, and the converter all still see `ConvertedDive`).

- [ ] **Step 6: Commit**

```bash
git add lib/devices/models/converted_dive.dart lib/shearwater/parser/dive_converter.dart test/devices/converted_dive_test.dart
git commit -m "refactor(devices): hoist ConvertedDive to neutral device layer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Add `DcVendor` + `DcModelId`

**Files:**
- Create: `lib/devices/models/dc_model.dart`
- Test: `test/devices/dc_model_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/devices/dc_model_test.dart`:

```dart
import 'package:ccrlogger/devices/models/dc_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DcModelId has value equality and a stable hashCode', () {
    const a = DcModelId(DcVendor.shearwater, 'petrel3');
    const b = DcModelId(DcVendor.shearwater, 'petrel3');
    const c = DcModelId(DcVendor.divesoft, 'liberty');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('DcModelId.toString is vendor:model', () {
    expect(const DcModelId(DcVendor.divesoft, 'liberty').toString(),
        'divesoft:liberty');
  });

  test('a Set<DcModelId> dedupes equal ids', () {
    final s = {
      const DcModelId(DcVendor.shearwater, 'petrel3'),
      const DcModelId(DcVendor.shearwater, 'petrel3'),
    };
    expect(s, hasLength(1));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/devices/dc_model_test.dart
```
Expected: FAIL — `Target of URI doesn't exist: '.../dc_model.dart'`.

- [ ] **Step 3: Implement `dc_model.dart`**

Create `lib/devices/models/dc_model.dart`:

```dart
/// Vendor-neutral dive-computer identity for the LibDartDc device layer.
///
/// `DcModelId` replaces vendor-specific model enums (e.g. `ShearwaterModel`)
/// at the device-layer boundary so a registry can route by model without
/// importing any vendor package. Pure Dart.
library;

enum DcVendor {
  shearwater,
  ratio,
  divesoft,
  halcyon,
  heinrichsWeikamp,
  garmin,
  suunto,
}

/// A specific dive-computer model, vendor-qualified.
class DcModelId {
  final DcVendor vendor;

  /// Vendor-specific model key, lower-case and stable, e.g. `petrel3`,
  /// `liberty`, `ostc4`.
  final String model;

  const DcModelId(this.vendor, this.model);

  @override
  bool operator ==(Object other) =>
      other is DcModelId && other.vendor == vendor && other.model == model;

  @override
  int get hashCode => Object.hash(vendor, model);

  @override
  String toString() => '${vendor.name}:$model';
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/devices/dc_model_test.dart
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/devices/models/dc_model.dart test/devices/dc_model_test.dart
git commit -m "feat(devices): add vendor-neutral DcVendor + DcModelId

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Add the `Transport` interface and make `BleIo` implement it

**Files:**
- Create: `lib/devices/transport.dart`
- Modify: `lib/shearwater/ble/protocol.dart:29` (`BleIo implements Transport` + import)
- Test: `test/devices/transport_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/devices/transport_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ccrlogger/devices/transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements Transport {
  final List<Uint8List> written = [];
  bool drained = false;

  @override
  Future<void> writeBytes(Uint8List data) async => written.add(data);

  @override
  Future<List<Uint8List>> readFrames() async =>
      [Uint8List.fromList(const [1, 2, 3])];

  @override
  void drainPendingFrames() => drained = true;
}

void main() {
  test('Transport can be implemented and driven polymorphically', () async {
    final Transport t = _FakeTransport();
    await t.writeBytes(Uint8List.fromList(const [9]));
    final frames = await t.readFrames();
    t.drainPendingFrames();
    expect(frames.single, const [1, 2, 3]);
    expect((t as _FakeTransport).written.single, const [9]);
    expect(t.drained, isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/devices/transport_test.dart
```
Expected: FAIL — `Target of URI doesn't exist: '.../transport.dart'`.

- [ ] **Step 3: Implement `transport.dart`**

Create `lib/devices/transport.dart`:

```dart
/// Transport abstraction for the LibDartDc device layer.
///
/// A duplex byte/frame pipe to a dive computer. The app supplies the
/// implementation: a BLE transport (all platforms) today, a desktop USB
/// transport later. Pure Dart — no Flutter, no BLE, no I/O package.
///
/// Mirrors the existing `BleIo` surface exactly so the Shearwater BLE stack
/// already satisfies it (see `lib/shearwater/ble/protocol.dart`).
library;

import 'dart:typed_data';

abstract class Transport {
  /// Write a single frame (e.g. one BLE characteristic write).
  Future<void> writeBytes(Uint8List data);

  /// Read the next set of frames constituting a complete protocol packet.
  Future<List<Uint8List>> readFrames();

  /// Discard frames that have arrived but not yet been consumed (used to
  /// resync between operations when the device emitted latent responses).
  void drainPendingFrames();
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/devices/transport_test.dart
```
Expected: PASS.

- [ ] **Step 5: Make `BleIo` implement `Transport`**

In `lib/shearwater/ble/protocol.dart`:
- Add to the imports near the top (after the existing imports, line ~14):

```dart
import '../../devices/transport.dart';
```

- Change the class declaration on line 29 from:

```dart
abstract class BleIo {
```

to:

```dart
abstract class BleIo implements Transport {
```

The three abstract methods (`writeBytes`, `readFrames`, `drainPendingFrames`) already match `Transport` exactly, so no other change is needed — concrete implementations (`FlutterBluePlusBleIo`, the test mocks) automatically satisfy `Transport` too.

- [ ] **Step 6: Verify the supertype change compiles and breaks nothing**

```bash
flutter analyze
flutter test test/devices/transport_test.dart test/shearwater
```
Expected: `No issues found!` and all Shearwater protocol/transport tests pass (proves `BleIo` and its impls still satisfy every existing use *and* now `Transport`).

- [ ] **Step 7: Commit**

```bash
git add lib/devices/transport.dart lib/shearwater/ble/protocol.dart test/devices/transport_test.dart
git commit -m "feat(devices): add Transport interface; BleIo implements it

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Add the `DiveComputerDriver` interface + supporting types

**Files:**
- Create: `lib/devices/dive_computer_driver.dart`
- Test: `test/devices/dive_computer_driver_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/devices/dive_computer_driver_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ccrlogger/devices/dive_computer_driver.dart';
import 'package:ccrlogger/devices/models/dc_model.dart';
import 'package:ccrlogger/devices/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// A no-op driver that exercises every member of the interface.
class _StubDriver implements DiveComputerDriver {
  @override
  String get vendorName => 'Stub';
  @override
  List<DcModelId> get supportedModels =>
      const [DcModelId(DcVendor.shearwater, 'petrel3')];
  @override
  DiscoveryFilter get discovery => const DiscoveryFilter.ble(['fe25c237']);
  @override
  DownloadModel get downloadModel => DownloadModel.incrementalStream;

  @override
  Future<DcDeviceInfo> open(Transport t) async => const DcDeviceInfo(
        model: DcModelId(DcVendor.shearwater, 'petrel3'),
        serial: '0001',
        firmware: 'V1',
      );
  @override
  Future<List<DiveDescriptor>> enumerate({Uint8List? lastFingerprint}) async =>
      [];
  @override
  Stream<DriverEvent> download(List<DiveDescriptor> dives) =>
      const Stream<DriverEvent>.empty();
  @override
  Future<void> close() async {}
}

void main() {
  test('a driver exposes neutral metadata', () {
    final d = _StubDriver();
    expect(d.discovery.transport, TransportKind.ble);
    expect(d.discovery.bleServiceUuids, ['fe25c237']);
    expect(d.supportedModels.single,
        const DcModelId(DcVendor.shearwater, 'petrel3'));
    expect(d.downloadModel, DownloadModel.incrementalStream);
  });

  test('open returns neutral device info', () async {
    final info = await _StubDriver().open(_NullTransport());
    expect(info.serial, '0001');
    expect(info.model.vendor, DcVendor.shearwater);
  });

  test('DriverEvent has a progress and a dive-ready variant', () {
    const p = DriverProgress(diveIndex: 0, totalDives: 2, bytes: 10, totalBytes: 100);
    expect(p, isA<DriverEvent>());
    expect(p.totalDives, 2);
  });

  test('DiscoveryFilter.usb carries vendor/product ids', () {
    const f = DiscoveryFilter.usb([(vendorId: 0x0403, productId: 0x6001)]);
    expect(f.transport, TransportKind.usb);
    expect(f.usbIds.single.vendorId, 0x0403);
  });
}

class _NullTransport implements Transport {
  @override
  Future<void> writeBytes(Uint8List data) async {}
  @override
  Future<List<Uint8List>> readFrames() async => const [];
  @override
  void drainPendingFrames() {}
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/devices/dive_computer_driver_test.dart
```
Expected: FAIL — `Target of URI doesn't exist: '.../dive_computer_driver.dart'`.

- [ ] **Step 3: Implement `dive_computer_driver.dart`**

Create `lib/devices/dive_computer_driver.dart`:

```dart
/// The dive-computer driver contract for the LibDartDc device layer.
///
/// A driver knows how to talk to one vendor's computers over an injected
/// [Transport]: open/identify, enumerate the dive list, and download each
/// dive, terminating in a [ConvertedDive] — the source-agnostic value that
/// `DiveDao.importDive` already accepts. Pure Dart: discovery (BLE scan / USB
/// enumeration) stays in the app, which hands the driver an opened transport.
library;

import 'dart:typed_data';

import 'models/converted_dive.dart';
import 'models/dc_model.dart';
import 'transport.dart';

/// The physical link a driver speaks over. BLE is available on every
/// platform; USB is desktop-only.
enum TransportKind { ble, usb }

/// How a dive computer surfaces its dive data.
enum DownloadModel {
  /// Streams dives newest-first; the orchestrator can stop early once it
  /// reaches an already-imported dive.
  incrementalStream,

  /// Requires a full raw memory dump that is then demultiplexed.
  fullDump,
}

/// How the app finds this dive computer on a transport.
class DiscoveryFilter {
  final TransportKind transport;

  /// BLE GATT service UUIDs to filter scan results on (when [transport] is
  /// [TransportKind.ble]).
  final List<String> bleServiceUuids;

  /// USB vendor/product id pairs to match (when [transport] is
  /// [TransportKind.usb]).
  final List<({int vendorId, int productId})> usbIds;

  const DiscoveryFilter.ble(this.bleServiceUuids)
      : transport = TransportKind.ble,
        usbIds = const [];

  const DiscoveryFilter.usb(this.usbIds)
      : transport = TransportKind.usb,
        bleServiceUuids = const [];
}

/// Identity read from a connected device.
class DcDeviceInfo {
  final DcModelId model;
  final String serial;
  final String firmware;

  const DcDeviceInfo({
    required this.model,
    required this.serial,
    required this.firmware,
  });
}

/// A dive header sufficient for dedup + ordering, read before download.
class DiveDescriptor {
  final int diveNumber;

  /// Dive start time, epoch seconds UTC — feeds `generateDiveId`.
  final int startTimestampUtc;

  /// Opaque per-dive fingerprint for incremental-sync cutoffs.
  final Uint8List fingerprint;

  /// Optional size hint for progress UIs.
  final int? sizeHintBytes;

  const DiveDescriptor({
    required this.diveNumber,
    required this.startTimestampUtc,
    required this.fingerprint,
    this.sizeHintBytes,
  });
}

/// Events streamed by [DiveComputerDriver.download].
sealed class DriverEvent {
  const DriverEvent();
}

/// Periodic download progress for the current dive.
class DriverProgress extends DriverEvent {
  final int diveIndex;
  final int totalDives;
  final int bytes;
  final int totalBytes;

  const DriverProgress({
    required this.diveIndex,
    required this.totalDives,
    required this.bytes,
    required this.totalBytes,
  });
}

/// A fully parsed-and-converted dive, ready for `DiveDao.importDive`.
class DriverDiveReady extends DriverEvent {
  final ConvertedDive dive;

  /// Original device bytes, retained for re-parse. Drivers with no
  /// recoverable raw blob pass an empty list with a sentinel [parserVersion].
  final Uint8List rawBlob;

  /// The driver's parser version, stamped on the import for cache
  /// invalidation.
  final int parserVersion;

  const DriverDiveReady({
    required this.dive,
    required this.rawBlob,
    required this.parserVersion,
  });
}

/// One vendor's dive-computer driver.
///
/// Construction must be cheap and side-effect-free (no I/O): the registry
/// instantiates drivers to read their metadata. All link activity happens
/// inside [open]/[enumerate]/[download]/[close].
abstract class DiveComputerDriver {
  String get vendorName;
  List<DcModelId> get supportedModels;
  DiscoveryFilter get discovery;
  DownloadModel get downloadModel;

  /// Identify the device over an already-opened [Transport].
  Future<DcDeviceInfo> open(Transport t);

  /// Read the dive list. Pass [lastFingerprint] for incremental sync.
  Future<List<DiveDescriptor>> enumerate({Uint8List? lastFingerprint});

  /// Download [dives], emitting progress then a [DriverDiveReady] per dive.
  Stream<DriverEvent> download(List<DiveDescriptor> dives);

  /// Release the link.
  Future<void> close();
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/devices/dive_computer_driver_test.dart
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/devices/dive_computer_driver.dart test/devices/dive_computer_driver_test.dart
git commit -m "feat(devices): add DiveComputerDriver interface + event types

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Add the `DiveComputerRegistry`

**Files:**
- Create: `lib/devices/dive_computer_registry.dart`
- Test: `test/devices/dive_computer_registry_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/devices/dive_computer_registry_test.dart`:

```dart
import 'dart:typed_data';

import 'package:ccrlogger/devices/dive_computer_driver.dart';
import 'package:ccrlogger/devices/dive_computer_registry.dart';
import 'package:ccrlogger/devices/models/dc_model.dart';
import 'package:ccrlogger/devices/transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDriver implements DiveComputerDriver {
  @override
  final String vendorName;
  @override
  final List<DcModelId> supportedModels;
  @override
  final DiscoveryFilter discovery;
  @override
  final DownloadModel downloadModel;

  _FakeDriver(this.vendorName, this.supportedModels, this.discovery,
      [this.downloadModel = DownloadModel.incrementalStream]);

  @override
  Future<DcDeviceInfo> open(Transport t) async => throw UnimplementedError();
  @override
  Future<List<DiveDescriptor>> enumerate({Uint8List? lastFingerprint}) async =>
      const [];
  @override
  Stream<DriverEvent> download(List<DiveDescriptor> dives) =>
      const Stream<DriverEvent>.empty();
  @override
  Future<void> close() async {}
}

const _petrel = DcModelId(DcVendor.shearwater, 'petrel3');
const _ostc = DcModelId(DcVendor.heinrichsWeikamp, 'ostc2');

DiveComputerRegistry _registry() {
  final r = DiveComputerRegistry();
  r.register(() =>
      _FakeDriver('Shearwater', const [_petrel], const DiscoveryFilter.ble(['fe25'])));
  r.register(() => _FakeDriver('HW-OSTC', const [_ostc],
      const DiscoveryFilter.usb([(vendorId: 0x0403, productId: 0x6001)])));
  return r;
}

void main() {
  test('availableFor a BLE-only platform yields only BLE drivers', () {
    final drivers = _registry().availableFor({TransportKind.ble}).toList();
    expect(drivers, hasLength(1));
    expect(drivers.single.vendorName, 'Shearwater');
  });

  test('availableFor desktop (ble+usb) yields both', () {
    final drivers =
        _registry().availableFor({TransportKind.ble, TransportKind.usb}).toList();
    expect(drivers, hasLength(2));
  });

  test('forModel returns the driver whose supportedModels contains the id', () {
    final d = _registry().forModel(_ostc);
    expect(d, isNotNull);
    expect(d!.vendorName, 'HW-OSTC');
  });

  test('forModel returns null for an unregistered model', () {
    expect(_registry().forModel(const DcModelId(DcVendor.garmin, 'mk2')), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
flutter test test/devices/dive_computer_registry_test.dart
```
Expected: FAIL — `Target of URI doesn't exist: '.../dive_computer_registry.dart'`.

- [ ] **Step 3: Implement `dive_computer_registry.dart`**

Create `lib/devices/dive_computer_registry.dart`:

```dart
/// Registry of dive-computer drivers, filtered by platform reachability.
///
/// Drivers are registered as factories; the registry instantiates them to
/// read their metadata (cheap, side-effect-free by contract) and to produce
/// a fresh instance per import session. Moving a DC from "libdc territory" to
/// "ported" is a one-line change here: swap which factory handles its model.
library;

import 'dive_computer_driver.dart';
import 'models/dc_model.dart';

class DiveComputerRegistry {
  final List<DiveComputerDriver Function()> _factories;

  DiveComputerRegistry([List<DiveComputerDriver Function()>? factories])
      : _factories = [...?factories];

  /// Register a driver factory. Construction must be side-effect-free.
  void register(DiveComputerDriver Function() factory) =>
      _factories.add(factory);

  /// Fresh driver instances reachable given the transports available on the
  /// current platform (BLE everywhere; USB on desktop only).
  Iterable<DiveComputerDriver> availableFor(Set<TransportKind> transports) sync* {
    for (final make in _factories) {
      final driver = make();
      if (transports.contains(driver.discovery.transport)) {
        yield driver;
      }
    }
  }

  /// A fresh driver instance that handles [model], or null if none is
  /// registered for it.
  DiveComputerDriver? forModel(DcModelId model) {
    for (final make in _factories) {
      final driver = make();
      if (driver.supportedModels.contains(model)) {
        return driver;
      }
    }
    return null;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
flutter test test/devices/dive_computer_registry_test.dart
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/devices/dive_computer_registry.dart test/devices/dive_computer_registry_test.dart
git commit -m "feat(devices): add DiveComputerRegistry with platform filtering

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] **Full analyze + test sweep**

```bash
flutter analyze
flutter test
```
Expected: `No issues found!` and the entire suite passes — the device layer is in place and no existing behavior changed.

- [ ] **Purity check — `lib/devices/` imports nothing forbidden**

```bash
grep -rnE "import .*(flutter_blue_plus|drift|powersync|package:flutter/)" lib/devices/ || echo "CLEAN: lib/devices has no BLE/DB/Flutter imports"
```
Expected: `CLEAN: ...`. (The device layer must stay pure so `LibDartDc` is extractable later. `package:flutter/foundation.dart` is also disallowed here — if anything trips this, move it out.)

## Done criteria

- `lib/devices/` exists with `Transport`, `DiveComputerDriver`, `DiveComputerRegistry`, and neutral vocabulary (`DiveMode`, `DecoModel`, `TankUsage`, `ConvertedDive`, `DcModelId`).
- `BleIo` implements `Transport`.
- All existing imports still compile (re-export shims), full suite green, `lib/devices/` import-pure.
- No runtime behavior changed. Ready for **Plan #2: Shearwater as the first driver.**
