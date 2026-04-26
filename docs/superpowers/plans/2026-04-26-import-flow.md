# Import Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Import tab placeholder with a BLE import wizard that scans, connects, reads the manifest, downloads dives, and commits them to the database — with a mock backend for development.

**Architecture:** `ImportNotifier` (ChangeNotifier) drives a state machine (idle → scanning → connecting → readingManifest → downloading → done/error). `MockBleTransport` provides the same interface as `ShearwaterBleTransport` using bundled fixture assets. `ImportScreen` renders the current state as a step-based wizard UI.

**Tech Stack:** Flutter ChangeNotifier, existing ShearwaterBleTransport/DiveDao, rootBundle for mock fixture loading.

---

### Key existing types

- `ShearwaterBleTransport` (`lib/shearwater/ble/shearwater_ble_transport.dart`): `scan()` → `Stream<BluetoothDevice>`, `connect(BluetoothDevice)`, `connectWithIo(BleIo)`, `readDeviceInfo()` → `Future<DeviceInfo>`, `readManifest()` → `Future<List<ManifestEntry>>`, `downloadDives(List<ManifestEntry>)` → `Stream<DownloadedDive>`, `disconnect()`
- `DeviceInfo`: `serial` (String), `firmware` (String), `hardwareId` (int), `model` (ShearwaterModel), `baseAddress` (int)
- `ManifestEntry` (`lib/shearwater/parser/manifest_parser.dart`): `diveNumber` (int), `startTimestamp` (int), `endTimestamp` (int), `address` (int), `fingerprint` (Uint8List), `isValid` (bool)
- `DownloadedDive`: `manifest` (ManifestEntry), `data` (Uint8List)
- `DiveDao` (`lib/data/db/dive_dao.dart`): `importDive(converted, rawBlob, parserVersion)` → `Future<bool>`, `diveExists(diveId)` → `Future<bool>`, `getAllDives()` → `Future<List<Dive>>`
- `DiveConverter.convert(parsed, dcSerial, dcDiveNumber, dcModel)` → `ConvertedDive`
- `ShearwaterDiveParser(model).parse(Uint8List)` → `ParsedDive`
- `DiveListNotifier` (`lib/ui/notifiers/dive_list_notifier.dart`): `loadDives()` to refresh
- `AppShell` (`lib/ui/app_shell.dart`): bottom nav with `_currentIndex`, `_diveListNotifier`

---

### Task 1: Mock BLE transport

**Files:**
- Create: `lib/shearwater/ble/mock_ble_transport.dart`
- Test: `test/shearwater/ble/mock_ble_transport_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/shearwater/ble/mock_ble_transport_test.dart
import 'package:ccrlogger/shearwater/ble/mock_ble_transport.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readDeviceInfo returns Petrel 3 info', () async {
    final mock = MockBleTransport();
    await mock.connectMock();
    final info = await mock.readDeviceInfo();
    expect(info.serial, equals('B89641E4'));
    expect(info.model, equals(ShearwaterModel.petrel3));
    expect(info.firmware, contains('V103'));
  });

  test('readManifest returns 8 fixture entries', () async {
    final mock = MockBleTransport();
    await mock.connectMock();
    await mock.readDeviceInfo();
    final manifest = await mock.readManifest();
    expect(manifest.length, equals(8));
    expect(manifest.first.diveNumber, greaterThan(0));
  });

  test('downloadDives yields one blob per manifest entry', () async {
    final mock = MockBleTransport();
    await mock.connectMock();
    await mock.readDeviceInfo();
    final manifest = await mock.readManifest();
    final dives = await mock.downloadDives(manifest).toList();
    expect(dives.length, equals(8));
    for (final dive in dives) {
      expect(dive.data.length, greaterThan(0));
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shearwater/ble/mock_ble_transport_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write implementation**

```dart
// lib/shearwater/ble/mock_ble_transport.dart
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../parser/hardware.dart';
import '../parser/manifest_parser.dart';
import 'shearwater_ble_transport.dart';

/// Mock BLE transport using bundled fixture assets.
///
/// Provides the same high-level interface as [ShearwaterBleTransport]
/// without requiring real BLE hardware. Dives are loaded from
/// bundled test fixtures with configurable delay to simulate BLE transfer.
class MockBleTransport {
  DeviceInfo? _deviceInfo;
  final Duration perDiveDelay;

  MockBleTransport({this.perDiveDelay = const Duration(milliseconds: 500)});

  Future<void> connectMock() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  Future<DeviceInfo> readDeviceInfo() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _deviceInfo = DeviceInfo(
      serial: 'B89641E4',
      firmware: 'V103 DiveCAN',
      hardwareId: 0xB407,
      model: ShearwaterModel.petrel3,
      baseAddress: 0x80000000,
    );
    return _deviceInfo!;
  }

  Future<List<ManifestEntry>> readManifest() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    const diveNumbers = [711, 712, 713, 714, 715, 716, 717, 718];
    // Build mock manifest entries. Timestamps don't need to be exact —
    // the actual dive data comes from the fixture blobs.
    return diveNumbers.map((num) => ManifestEntry(
      header: 0xA5C4,
      diveNumber: num,
      fingerprint: Uint8List.fromList([0, 0, 0, num & 0xFF]),
      startTimestamp: 1776591525 + (num - 711) * 86400,
      endTimestamp: 1776591525 + (num - 711) * 86400 + 3600,
      address: num * 0x10000,
    )).toList().reversed.toList(); // most recent first
  }

  Stream<DownloadedDive> downloadDives(List<ManifestEntry> manifest) async* {
    for (final entry in manifest) {
      await Future<void>.delayed(perDiveDelay);
      try {
        final byteData = await rootBundle.load(
            'test/fixtures/dives/dive_${entry.diveNumber}.bin');
        yield DownloadedDive(
          manifest: entry,
          data: byteData.buffer.asUint8List(),
        );
      } catch (_) {
        // Skip dives without fixture files
      }
    }
  }

  Future<void> disconnect() async {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shearwater/ble/mock_ble_transport_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/shearwater/ble/mock_ble_transport.dart test/shearwater/ble/mock_ble_transport_test.dart
git commit -m "feat: add MockBleTransport using bundled fixture assets"
```

---

### Task 2: ImportNotifier state machine

**Files:**
- Create: `lib/ui/notifiers/import_notifier.dart`
- Test: `test/ui/notifiers/import_notifier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ui/notifiers/import_notifier_test.dart
import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/ui/notifiers/import_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late ImportNotifier notifier;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveDao(db);
    notifier = ImportNotifier(dao: dao, useMock: true);
  });

  tearDown(() async {
    notifier.dispose();
    await db.close();
  });

  test('starts in idle state', () {
    expect(notifier.state, equals(ImportState.idle));
  });

  test('startScan transitions to scanning', () {
    notifier.startScan();
    expect(notifier.state, equals(ImportState.scanning));
  });

  test('full mock flow reaches done state', () async {
    // Simulate the full flow: scan → select device → connect → read manifest → download
    notifier.startScan();
    expect(notifier.state, equals(ImportState.scanning));

    // Wait for mock device to appear
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(notifier.mockDeviceAvailable, isTrue);

    // Select mock device (triggers connect + readDeviceInfo)
    await notifier.selectMockDevice();
    expect(notifier.state, equals(ImportState.readingManifest));
    expect(notifier.deviceInfo, isNotNull);
    expect(notifier.deviceInfo!.serial, equals('B89641E4'));

    // Wait for manifest
    await notifier.readManifestAndFilterNew();
    expect(notifier.state, equals(ImportState.readingManifest));
    expect(notifier.newDives.length, equals(8));

    // Start download
    await notifier.downloadAll();
    expect(notifier.state, equals(ImportState.done));
    expect(notifier.downloadedCount, equals(8));
  });

  test('retry resets to scanning', () {
    notifier.setError('test error');
    expect(notifier.state, equals(ImportState.error));
    notifier.retry();
    expect(notifier.state, equals(ImportState.scanning));
  });

  test('dedup skips already-imported dives on second run', () async {
    // First full import
    notifier.startScan();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await notifier.selectMockDevice();
    await notifier.readManifestAndFilterNew();
    await notifier.downloadAll();
    expect(notifier.downloadedCount, equals(8));

    // Second import — reset and run again
    final notifier2 = ImportNotifier(dao: dao, useMock: true);
    notifier2.startScan();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await notifier2.selectMockDevice();
    await notifier2.readManifestAndFilterNew();
    expect(notifier2.newDives.length, equals(0)); // all already imported
    notifier2.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/notifiers/import_notifier_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write implementation**

```dart
// lib/ui/notifiers/import_notifier.dart
import 'package:flutter/foundation.dart';

import '../../data/db/dive_dao.dart';
import '../../data/models/dive.dart';
import '../../shearwater/ble/mock_ble_transport.dart';
import '../../shearwater/ble/shearwater_ble_transport.dart';
import '../../shearwater/parser/dive_converter.dart';
import '../../shearwater/parser/dive_parser.dart';
import '../../shearwater/parser/manifest_parser.dart';

enum ImportState { idle, scanning, connecting, readingManifest, downloading, done, error }

class ImportNotifier extends ChangeNotifier {
  final DiveDao _dao;
  final bool useMock;

  ImportState _state = ImportState.idle;
  DeviceInfo? _deviceInfo;
  List<ManifestEntry> _newDives = [];
  int _downloadedCount = 0;
  int _totalToDownload = 0;
  int? _currentDiveNumber;
  String? _errorMessage;
  int _failedCount = 0;

  // Mock transport
  MockBleTransport? _mockTransport;
  bool _mockDeviceAvailable = false;

  ImportNotifier({required DiveDao dao, this.useMock = false}) : _dao = dao;

  ImportState get state => _state;
  DeviceInfo? get deviceInfo => _deviceInfo;
  List<ManifestEntry> get newDives => _newDives;
  int get downloadedCount => _downloadedCount;
  int get totalToDownload => _totalToDownload;
  int? get currentDiveNumber => _currentDiveNumber;
  String? get errorMessage => _errorMessage;
  int get failedCount => _failedCount;
  bool get mockDeviceAvailable => _mockDeviceAvailable;

  void startScan() {
    _state = ImportState.scanning;
    _mockDeviceAvailable = false;
    notifyListeners();

    if (useMock) {
      Future<void>.delayed(const Duration(milliseconds: 300)).then((_) {
        _mockDeviceAvailable = true;
        notifyListeners();
      });
    }
  }

  Future<void> selectMockDevice() async {
    _state = ImportState.connecting;
    notifyListeners();

    try {
      _mockTransport = MockBleTransport(
        perDiveDelay: const Duration(milliseconds: 100),
      );
      await _mockTransport!.connectMock();
      _deviceInfo = await _mockTransport!.readDeviceInfo();
      _state = ImportState.readingManifest;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _state = ImportState.error;
    }
    notifyListeners();
  }

  Future<void> readManifestAndFilterNew() async {
    try {
      final manifest = await _mockTransport!.readManifest();
      // Filter out already-imported dives
      _newDives = [];
      for (final entry in manifest) {
        if (!entry.isValid) continue;
        // Check if we already have this dive by generating its ID
        final diveId = generateDiveId(
          int.parse(_deviceInfo!.serial, radix: 16),
          entry.diveNumber,
          entry.startTimestamp,
        );
        final exists = await _dao.diveExists(diveId);
        if (!exists) {
          _newDives.add(entry);
        }
      }
      _totalToDownload = _newDives.length;
    } catch (e) {
      _errorMessage = 'Failed to read manifest: $e';
      _state = ImportState.error;
    }
    notifyListeners();
  }

  Future<void> downloadAll() async {
    _state = ImportState.downloading;
    _downloadedCount = 0;
    _failedCount = 0;
    notifyListeners();

    final parser = ShearwaterDiveParser(model: _deviceInfo!.model);
    final serial = int.parse(_deviceInfo!.serial, radix: 16);

    try {
      await for (final downloaded in _mockTransport!.downloadDives(_newDives)) {
        try {
          _currentDiveNumber = downloaded.manifest.diveNumber;
          notifyListeners();

          final parsed = parser.parse(downloaded.data);
          final converted = DiveConverter.convert(
            parsed: parsed,
            dcSerial: serial,
            dcDiveNumber: downloaded.manifest.diveNumber,
            dcModel: _deviceInfo!.model,
          );
          await _dao.importDive(
            converted: converted,
            rawBlob: downloaded.data,
            parserVersion: 1,
          );
          _downloadedCount++;
        } catch (e) {
          debugPrint('Failed to import dive ${downloaded.manifest.diveNumber}: $e');
          _failedCount++;
        }
        notifyListeners();
      }
      _state = ImportState.done;
    } catch (e) {
      _errorMessage = 'Connection lost. $_downloadedCount of $_totalToDownload dives imported successfully.';
      _state = ImportState.error;
    }
    _currentDiveNumber = null;
    notifyListeners();
  }

  void setError(String message) {
    _errorMessage = message;
    _state = ImportState.error;
    notifyListeners();
  }

  void retry() {
    _state = ImportState.idle;
    _deviceInfo = null;
    _newDives = [];
    _downloadedCount = 0;
    _totalToDownload = 0;
    _currentDiveNumber = null;
    _errorMessage = null;
    _failedCount = 0;
    _mockTransport = null;
    _mockDeviceAvailable = false;
    notifyListeners();
    startScan();
  }

  void reset() {
    _state = ImportState.idle;
    _deviceInfo = null;
    _newDives = [];
    _downloadedCount = 0;
    _totalToDownload = 0;
    _currentDiveNumber = null;
    _errorMessage = null;
    _failedCount = 0;
    _mockTransport = null;
    _mockDeviceAvailable = false;
    notifyListeners();
  }
}
```

Note: The dedup in `readManifestAndFilterNew` generates the dive ID from the manifest's `startTimestamp`. However, the actual dive blob's start timestamp (from the opening record) may differ slightly. For the mock (which uses fixture blobs), the `DiveConverter` generates the ID from the blob's start timestamp — so the dedup check here uses the manifest timestamp while the actual import uses the blob timestamp. To make dedup work correctly, `readManifestAndFilterNew` should ideally check by `diveExists` using the same ID formula. Since the mock manifest timestamps are synthetic and won't match the fixture blob timestamps, the implementer should ensure the mock manifest entries use timestamps that match the fixture dive blobs' opening record timestamps. Alternatively, the filter can check whether any dive with that `dcDiveNumber` from that `dcSerial` already exists. The simplest approach: after downloading and importing, dedup is handled by `DiveDao.importDive` which returns `false` for duplicates. So the filter in `readManifestAndFilterNew` is a best-effort optimization — it's OK if it doesn't perfectly match.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/notifiers/import_notifier_test.dart`
Expected: PASS — if the dedup test fails, the implementer should adjust the mock manifest timestamps to match fixture blob timestamps, OR change the dedup filter to check by `dcDiveNumber + dcSerial` instead of generated ID.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/notifiers/import_notifier.dart test/ui/notifiers/import_notifier_test.dart
git commit -m "feat: add ImportNotifier state machine with mock support"
```

---

### Task 3: Import screen UI

**Files:**
- Create: `lib/ui/screens/import_screen.dart`

- [ ] **Step 1: Create the import screen**

This screen renders the current `ImportNotifier` state as a step-based wizard. Each state has its own visual representation.

```dart
// lib/ui/screens/import_screen.dart
import 'package:flutter/material.dart';

import '../notifiers/import_notifier.dart';
import '../util/format.dart';

class ImportScreen extends StatefulWidget {
  final ImportNotifier notifier;
  final VoidCallback onViewDives;

  const ImportScreen({super.key, required this.notifier, required this.onViewDives});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final n = widget.notifier;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: switch (n.state) {
        ImportState.idle => _buildIdle(theme),
        ImportState.scanning => _buildScanning(n, theme),
        ImportState.connecting => _buildConnecting(n, theme),
        ImportState.readingManifest => _buildManifest(n, theme),
        ImportState.downloading => _buildDownloading(n, theme),
        ImportState.done => _buildDone(n, theme),
        ImportState.error => _buildError(n, theme),
      },
    );
  }

  Widget _buildIdle(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          const Text('Import Dives', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Connect to your Shearwater dive computer',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => widget.notifier.startScan(),
            icon: const Icon(Icons.search),
            label: const Text('Start Scan'),
          ),
        ],
      ),
    );
  }

  Widget _buildScanning(ImportNotifier n, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
          const SizedBox(height: 24),
          const Text('Searching for dive computers...', style: TextStyle(fontSize: 16)),
          if (n.mockDeviceAvailable) ...[
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.bluetooth_connected),
                title: const Text('Petrel 3 (Mock)'),
                subtitle: const Text('Debug device'),
                onTap: () async {
                  await n.selectMockDevice();
                  if (n.state == ImportState.readingManifest) {
                    await n.readManifestAndFilterNew();
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnecting(ImportNotifier n, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
          const SizedBox(height: 24),
          Text('Connecting to ${n.deviceInfo?.model.name ?? 'dive computer'}...',
              style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildManifest(ImportNotifier n, ThemeData theme) {
    if (n.newDives.isEmpty && n.deviceInfo != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            const Text('All dives already imported', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 32),
            FilledButton(onPressed: widget.onViewDives, child: const Text('View Dives')),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (n.deviceInfo != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.bluetooth_connected, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.deviceInfo!.model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('S/N ${n.deviceInfo!.serial} · ${n.deviceInfo!.firmware}',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Found ${n.newDives.length} new dives',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => n.downloadAll(),
            icon: const Icon(Icons.download),
            label: Text('Import ${n.newDives.length} dives'),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloading(ImportNotifier n, ThemeData theme) {
    final progress = n.totalToDownload > 0 ? n.downloadedCount / n.totalToDownload : 0.0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 80, height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(value: progress, strokeWidth: 6),
                Text('${n.downloadedCount}/${n.totalToDownload}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (n.currentDiveNumber != null)
            Text('Downloading dive #${n.currentDiveNumber}...',
                style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text('${n.downloadedCount} of ${n.totalToDownload} imported',
              style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: LinearProgressIndicator(value: progress),
          ),
        ],
      ),
    );
  }

  Widget _buildDone(ImportNotifier n, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text('Imported ${n.downloadedCount} dives',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          if (n.failedCount > 0) ...[
            const SizedBox(height: 8),
            Text('${n.failedCount} failed',
                style: TextStyle(color: theme.colorScheme.error, fontSize: 14)),
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: widget.onViewDives,
            icon: const Icon(Icons.list),
            label: const Text('View Dives'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => widget.notifier.reset(),
            child: const Text('Import More'),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ImportNotifier n, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
          const SizedBox(height: 24),
          Text(n.errorMessage ?? 'An error occurred',
              style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
          if (n.downloadedCount > 0) ...[
            const SizedBox(height: 8),
            Text('${n.downloadedCount} dives were imported successfully',
                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => n.retry(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/ui/screens/import_screen.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/ui/screens/import_screen.dart
git commit -m "feat: add ImportScreen wizard UI with 5 states"
```

---

### Task 4: Wire import screen into app shell

**Files:**
- Modify: `lib/ui/app_shell.dart`

- [ ] **Step 1: Update AppShell**

Replace the Import placeholder with the real `ImportScreen`. The `AppShell` needs to:
1. Create an `ImportNotifier` (with `useMock: kDebugMode`)
2. Pass it to `ImportScreen`
3. Provide an `onViewDives` callback that switches to tab 0 and refreshes the dive list

Update `lib/ui/app_shell.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/db/dive_dao.dart';
import 'notifiers/dive_list_notifier.dart';
import 'notifiers/import_notifier.dart';
import 'screens/dive_list_screen.dart';
import 'screens/import_screen.dart';
import 'screens/placeholder_screen.dart';

class AppShell extends StatefulWidget {
  final DiveDao diveDao;

  const AppShell({super.key, required this.diveDao});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final DiveListNotifier _diveListNotifier;
  late final ImportNotifier _importNotifier;

  @override
  void initState() {
    super.initState();
    _diveListNotifier = DiveListNotifier(widget.diveDao);
    _importNotifier = ImportNotifier(dao: widget.diveDao, useMock: kDebugMode);
  }

  @override
  void dispose() {
    _diveListNotifier.dispose();
    _importNotifier.dispose();
    super.dispose();
  }

  void _onViewDives() {
    setState(() => _currentIndex = 0);
    _diveListNotifier.loadDives();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CCRLog')),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DiveListScreen(notifier: _diveListNotifier, diveDao: widget.diveDao),
          ImportScreen(notifier: _importNotifier, onViewDives: _onViewDives),
          const PlaceholderScreen(title: 'Equipment', icon: Icons.build_outlined),
          const PlaceholderScreen(title: 'Settings', icon: Icons.settings_outlined),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.scuba_diving), label: 'Dives'),
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: 'Import'),
          BottomNavigationBarItem(icon: Icon(Icons.build_outlined), label: 'Equipment'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles and tests pass**

Run: `flutter analyze && flutter test`
Expected: No issues, all tests pass

- [ ] **Step 3: Commit**

```bash
git add lib/ui/app_shell.dart
git commit -m "feat: wire ImportScreen into app shell, replacing placeholder"
```

---

### Task 5: Verify and push

- [ ] **Step 1: Run all tests**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 3: Push**

```bash
git push origin main
```
