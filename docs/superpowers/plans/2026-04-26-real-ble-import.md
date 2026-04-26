# Real BLE Import + Incremental Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire real BLE hardware into the import flow so the app can scan, connect to, and import dives from a physical Shearwater dive computer. Add incremental sync via fingerprints and BLE platform permissions.

**Architecture:** The `ImportNotifier` gains a real-BLE code path alongside the existing mock. `ShearwaterBleTransport` (already implemented + tested against protocol traces) handles the actual BLE communication. A new `ImportStateDao` persists the last-imported fingerprint per dive computer for incremental sync. Platform permission entries are added for iOS and Android.

**Tech Stack:** flutter_blue_plus (existing), Drift ImportStates table (existing schema, needs DAO), existing ShearwaterBleTransport.

---

### Key existing pieces

- `ShearwaterBleTransport` (`lib/shearwater/ble/shearwater_ble_transport.dart`): `scan()` → `Stream<BluetoothDevice>`, `connect(BluetoothDevice)`, `readDeviceInfo()` → `Future<DeviceInfo>`, `readManifest({lastFingerprint})` → `Future<List<ManifestEntry>>`, `downloadDives(manifest)` → `Stream<DownloadedDive>`, `disconnect()`
- `ImportNotifier` (`lib/ui/notifiers/import_notifier.dart`): currently only uses `MockBleTransport`. Has `ImportFlowState` enum, `startScan()`, `selectMockDevice()`, `readManifestAndFilterNew()`, `downloadAll()`, `retry()`, `reset()`.
- `ImportScreen` (`lib/ui/screens/import_screen.dart`): renders all 7 states. Scanning step shows mock device card. Needs to also show real BLE devices.
- `ImportStates` table (`lib/data/db/tables.dart:166`): `dcSerial` (PK), `lastFingerprint` (blob?), `lastImportAt` (int?)
- `FlutterBluePlusBleIo` (`lib/shearwater/ble/ble_io_impl.dart`): real BLE I/O, service UUID `fe25c237-0ece-443c-b0aa-e02033e7029d`
- Platform configs: `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml` — currently have NO BLE permissions.

---

### Task 1: BLE platform permissions

**Files:**
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add iOS Bluetooth permissions**

Add these entries inside the top-level `<dict>` in `ios/Runner/Info.plist`, before the closing `</dict>`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>CCRLog needs Bluetooth to connect to your Shearwater dive computer and import dive logs.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>CCRLog needs Bluetooth to connect to your Shearwater dive computer and import dive logs.</string>
```

- [ ] **Step 2: Add Android Bluetooth and location permissions**

Add these inside the `<manifest>` tag in `android/app/src/main/AndroidManifest.xml`, before the `<application` tag:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 4: Commit**

```bash
git add ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml
git commit -m "feat: add BLE permissions for iOS and Android"
```

---

### Task 2: ImportState DAO for fingerprint persistence

**Files:**
- Create: `lib/data/db/import_state_dao.dart`
- Test: `test/data/db/import_state_dao_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/data/db/import_state_dao_test.dart
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/import_state_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ImportStateDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = ImportStateDao(db);
  });

  tearDown(() async { await db.close(); });

  test('getLastFingerprint returns null for unknown serial', () async {
    final fp = await dao.getLastFingerprint('DEADBEEF');
    expect(fp, isNull);
  });

  test('saveLastFingerprint stores and retrieves fingerprint', () async {
    final fp = Uint8List.fromList([0x69, 0xE4, 0xA3, 0x56]);
    await dao.saveLastFingerprint('B89641E4', fp);
    final retrieved = await dao.getLastFingerprint('B89641E4');
    expect(retrieved, equals(fp));
  });

  test('saveLastFingerprint updates existing entry', () async {
    final fp1 = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
    final fp2 = Uint8List.fromList([0x05, 0x06, 0x07, 0x08]);
    await dao.saveLastFingerprint('B89641E4', fp1);
    await dao.saveLastFingerprint('B89641E4', fp2);
    final retrieved = await dao.getLastFingerprint('B89641E4');
    expect(retrieved, equals(fp2));
  });

  test('different serials have independent fingerprints', () async {
    final fp1 = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
    final fp2 = Uint8List.fromList([0x05, 0x06, 0x07, 0x08]);
    await dao.saveLastFingerprint('AAAA', fp1);
    await dao.saveLastFingerprint('BBBB', fp2);
    expect(await dao.getLastFingerprint('AAAA'), equals(fp1));
    expect(await dao.getLastFingerprint('BBBB'), equals(fp2));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/db/import_state_dao_test.dart`
Expected: FAIL — file not found

- [ ] **Step 3: Write implementation**

```dart
// lib/data/db/import_state_dao.dart
import 'dart:typed_data';

import 'package:drift/drift.dart';

import 'database.dart';

class ImportStateDao {
  final AppDatabase _db;

  ImportStateDao(this._db);

  Future<Uint8List?> getLastFingerprint(String dcSerial) async {
    final query = _db.select(_db.importStates)
      ..where((t) => t.dcSerial.equals(dcSerial));
    final row = await query.getSingleOrNull();
    return row?.lastFingerprint;
  }

  Future<void> saveLastFingerprint(String dcSerial, Uint8List fingerprint) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.importStates).insertOnConflictUpdate(
      ImportStatesCompanion.insert(
        dcSerial: dcSerial,
        lastFingerprint: Value(fingerprint),
        lastImportAt: Value(now),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/db/import_state_dao_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/db/import_state_dao.dart test/data/db/import_state_dao_test.dart
git commit -m "feat: add ImportStateDao for fingerprint-based incremental sync"
```

---

### Task 3: Extend ImportNotifier with real BLE path

**Files:**
- Modify: `lib/ui/notifiers/import_notifier.dart`
- Test: `test/ui/notifiers/import_notifier_test.dart` (add test for real transport path setup)

This is the main wiring task. The `ImportNotifier` needs to:
1. Call `FlutterBluePlus.startScan()` during `startScan()` and collect discovered Shearwater devices
2. Expose `discoveredDevices` list for the UI
3. Add `selectRealDevice(BluetoothDevice)` that creates a `ShearwaterBleTransport`, connects, and reads device info
4. Update `readManifestAndFilterNew()` to use the real transport (with optional fingerprint from `ImportStateDao`)
5. Update `downloadAll()` to use the real transport
6. After successful import, save the newest fingerprint via `ImportStateDao`
7. Call `disconnect()` on completion or error

- [ ] **Step 1: Update ImportNotifier to support both mock and real BLE**

The updated `ImportNotifier` constructor takes an additional `ImportStateDao` parameter. The class gains:
- `_realTransport` (ShearwaterBleTransport?) for real BLE
- `_discoveredDevices` list populated during scanning
- `selectRealDevice(BluetoothDevice)` method
- `_importStateDao` for fingerprint persistence

```dart
// lib/ui/notifiers/import_notifier.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../data/db/dive_dao.dart';
import '../../data/db/import_state_dao.dart';
import '../../shearwater/ble/ble_io_impl.dart';
import '../../shearwater/ble/mock_ble_transport.dart';
import '../../shearwater/ble/shearwater_ble_transport.dart';
import '../../shearwater/parser/dive_converter.dart';
import '../../shearwater/parser/dive_parser.dart';
import '../../shearwater/parser/manifest_parser.dart';

enum ImportFlowState {
  idle,
  scanning,
  connecting,
  readingManifest,
  downloading,
  done,
  error,
}

class ImportNotifier extends ChangeNotifier {
  final DiveDao _dao;
  final ImportStateDao _importStateDao;
  final bool useMock;

  bool _disposed = false;
  ImportFlowState _state = ImportFlowState.idle;
  DeviceInfo? _deviceInfo;
  List<ManifestEntry> _newDives = [];
  int _downloadedCount = 0;
  int _totalToDownload = 0;
  int? _currentDiveNumber;
  String? _errorMessage;
  int _failedCount = 0;

  // Mock
  MockBleTransport? _mockTransport;
  bool _mockDeviceAvailable = false;

  // Real BLE
  ShearwaterBleTransport? _realTransport;
  final List<BluetoothDevice> _discoveredDevices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  ImportNotifier({
    required DiveDao dao,
    required ImportStateDao importStateDao,
    this.useMock = false,
  })  : _dao = dao,
        _importStateDao = importStateDao;

  // ── Accessors ──

  ImportFlowState get state => _state;
  DeviceInfo? get deviceInfo => _deviceInfo;
  List<ManifestEntry> get newDives => List.unmodifiable(_newDives);
  int get downloadedCount => _downloadedCount;
  int get totalToDownload => _totalToDownload;
  int? get currentDiveNumber => _currentDiveNumber;
  String? get errorMessage => _errorMessage;
  int get failedCount => _failedCount;
  bool get mockDeviceAvailable => _mockDeviceAvailable;
  List<BluetoothDevice> get discoveredDevices => List.unmodifiable(_discoveredDevices);

  // ── Scanning ──

  void startScan() {
    _state = ImportFlowState.scanning;
    _mockDeviceAvailable = false;
    _discoveredDevices.clear();
    notifyListeners();

    if (useMock) {
      Future<void>.delayed(const Duration(milliseconds: 300)).then((_) {
        if (_disposed) return;
        _mockDeviceAvailable = true;
        notifyListeners();
      });
    }

    // Start real BLE scan regardless of mock mode —
    // real devices can appear alongside the mock.
    _startRealScan();
  }

  void _startRealScan() {
    try {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        var changed = false;
        for (final result in results) {
          if (result.advertisementData.serviceUuids.any((uuid) =>
              uuid.toString().toLowerCase() ==
              shearwaterServiceUuid.toLowerCase())) {
            if (!_discoveredDevices.any((d) => d.remoteId == result.device.remoteId)) {
              _discoveredDevices.add(result.device);
              changed = true;
            }
          }
        }
        if (changed && !_disposed) notifyListeners();
      });
    } catch (e) {
      debugPrint('BLE scan error: $e');
    }
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  // ── Connect (mock) ──

  Future<void> selectMockDevice() async {
    _stopScan();
    _state = ImportFlowState.connecting;
    notifyListeners();

    try {
      _mockTransport = MockBleTransport(
        perDiveDelay: const Duration(milliseconds: 100),
      );
      await _mockTransport!.connectMock();
      _deviceInfo = await _mockTransport!.readDeviceInfo();
      _state = ImportFlowState.readingManifest;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _state = ImportFlowState.error;
    }
    notifyListeners();
  }

  // ── Connect (real BLE) ──

  Future<void> selectRealDevice(BluetoothDevice device) async {
    _stopScan();
    _state = ImportFlowState.connecting;
    notifyListeners();

    try {
      _realTransport = ShearwaterBleTransport();
      await _realTransport!.connect(device);
      _deviceInfo = await _realTransport!.readDeviceInfo();
      _state = ImportFlowState.readingManifest;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _state = ImportFlowState.error;
      try { await _realTransport?.disconnect(); } catch (_) {}
      _realTransport = null;
    }
    notifyListeners();
  }

  // ── Manifest ──

  bool get _isRealBle => _realTransport != null;

  Future<void> readManifestAndFilterNew() async {
    try {
      List<ManifestEntry> manifest;

      if (_isRealBle) {
        // Get last fingerprint for incremental sync
        final lastFp = await _importStateDao.getLastFingerprint(_deviceInfo!.serial);
        manifest = await _realTransport!.readManifest(lastFingerprint: lastFp);
      } else {
        manifest = await _mockTransport!.readManifest();
      }

      _newDives = manifest.where((e) => e.isValid).toList();
      _totalToDownload = _newDives.length;
    } catch (e) {
      _errorMessage = 'Failed to read manifest: $e';
      _state = ImportFlowState.error;
    }
    notifyListeners();
  }

  // ── Download ──

  Future<void> downloadAll() async {
    _state = ImportFlowState.downloading;
    _downloadedCount = 0;
    _failedCount = 0;
    notifyListeners();

    final parser = ShearwaterDiveParser(model: _deviceInfo!.model);
    final serial = int.parse(_deviceInfo!.serial, radix: 16);
    ManifestEntry? lastSuccessfulEntry;

    try {
      final diveStream = _isRealBle
          ? _realTransport!.downloadDives(_newDives)
          : _mockTransport!.downloadDives(_newDives);

      await for (final downloaded in diveStream) {
        _currentDiveNumber = downloaded.manifest.diveNumber;
        notifyListeners();

        try {
          final parsed = parser.parse(downloaded.data);
          final converted = DiveConverter.convert(
            parsed: parsed,
            dcSerial: serial,
            dcDiveNumber: downloaded.manifest.diveNumber,
            dcModel: _deviceInfo!.model,
          );
          final imported = await _dao.importDive(
            converted: converted,
            rawBlob: downloaded.data,
            parserVersion: 1,
          );
          if (imported) {
            _downloadedCount++;
            lastSuccessfulEntry = downloaded.manifest;
          }
        } catch (e) {
          debugPrint(
            'Failed to import dive ${downloaded.manifest.diveNumber}: $e',
          );
          _failedCount++;
        }
        notifyListeners();
      }

      _state = ImportFlowState.done;
    } catch (e) {
      _errorMessage =
          'Connection lost. $_downloadedCount of $_totalToDownload dives imported.';
      _state = ImportFlowState.error;
    }

    // Save last fingerprint for incremental sync
    if (lastSuccessfulEntry != null) {
      await _importStateDao.saveLastFingerprint(
        _deviceInfo!.serial,
        lastSuccessfulEntry!.fingerprint,
      );
    }

    // Disconnect real transport
    if (_isRealBle) {
      try { await _realTransport!.disconnect(); } catch (_) {}
    }

    _currentDiveNumber = null;
    notifyListeners();
  }

  // ── Error / retry ──

  void setError(String message) {
    _errorMessage = message;
    _state = ImportFlowState.error;
    notifyListeners();
  }

  void retry() {
    _reset();
    startScan();
  }

  void reset() {
    _reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopScan();
    _realTransport?.disconnect();
    super.dispose();
  }

  void _reset() {
    _state = ImportFlowState.idle;
    _deviceInfo = null;
    _newDives = [];
    _downloadedCount = 0;
    _totalToDownload = 0;
    _currentDiveNumber = null;
    _errorMessage = null;
    _failedCount = 0;
    _mockTransport = null;
    _mockDeviceAvailable = false;
    _realTransport = null;
    _discoveredDevices.clear();
    _stopScan();
  }
}
```

- [ ] **Step 2: Update existing ImportNotifier test**

Update `test/ui/notifiers/import_notifier_test.dart` to pass the new required `importStateDao` parameter. Create an in-memory `ImportStateDao` in setUp:

```dart
// In setUp, add:
late ImportStateDao importStateDao;

setUp(() {
  db = AppDatabase(NativeDatabase.memory());
  dao = DiveDao(db);
  importStateDao = ImportStateDao(db);
  notifier = ImportNotifier(dao: dao, importStateDao: importStateDao, useMock: true);
});
```

Add the import:
```dart
import 'package:ccrlogger/data/db/import_state_dao.dart';
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/ui/notifiers/import_notifier_test.dart`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/ui/notifiers/import_notifier.dart test/ui/notifiers/import_notifier_test.dart
git commit -m "feat: extend ImportNotifier with real BLE path and fingerprint sync"
```

---

### Task 4: Update ImportScreen for real BLE devices

**Files:**
- Modify: `lib/ui/screens/import_screen.dart`

The scanning step needs to show discovered real BLE devices alongside the mock device (when in debug mode).

- [ ] **Step 1: Update _buildScanning to show real devices**

In `_buildScanning`, after the mock device card, add a list of discovered real devices:

```dart
Widget _buildScanning(ImportNotifier n, ThemeData theme) {
  return Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
      const SizedBox(height: 24),
      const Text('Searching for dive computers...', style: TextStyle(fontSize: 16)),
      const SizedBox(height: 8),
      Text('Make sure your dive computer is in upload mode',
          style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 12)),

      // Mock device (debug only)
      if (n.mockDeviceAvailable) ...[
        const SizedBox(height: 16),
        Card(child: ListTile(
          leading: const Icon(Icons.bluetooth_connected),
          title: const Text('Petrel 3 (Mock)'),
          subtitle: const Text('Debug device'),
          onTap: () async {
            await n.selectMockDevice();
            if (n.state == ImportFlowState.readingManifest) {
              await n.readManifestAndFilterNew();
            }
          },
        )),
      ],

      // Real BLE devices
      for (final device in n.discoveredDevices) ...[
        const SizedBox(height: 8),
        Card(child: ListTile(
          leading: Icon(Icons.bluetooth, color: theme.colorScheme.primary),
          title: Text(device.platformName.isNotEmpty ? device.platformName : 'Shearwater DC'),
          subtitle: Text(device.remoteId.toString()),
          onTap: () async {
            await n.selectRealDevice(device);
            if (n.state == ImportFlowState.readingManifest) {
              await n.readManifestAndFilterNew();
            }
          },
        )),
      ],

      if (!n.mockDeviceAvailable && n.discoveredDevices.isEmpty) ...[
        const SizedBox(height: 24),
        Text('No devices found yet...',
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3), fontSize: 12)),
      ],
    ],
  ));
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/ui/screens/import_screen.dart
git commit -m "feat: show real BLE devices in import scan step"
```

---

### Task 5: Update AppShell to pass ImportStateDao

**Files:**
- Modify: `lib/ui/app_shell.dart`
- Modify: `lib/main.dart`

The `ImportNotifier` now requires `ImportStateDao`. Thread it through from `main.dart`.

- [ ] **Step 1: Update AppShell to accept and use ImportStateDao**

Add `ImportStateDao` import and create it from the database. Update `_importNotifier` construction:

In `lib/ui/app_shell.dart`:
```dart
import '../data/db/import_state_dao.dart';
```

In `initState`:
```dart
final importStateDao = ImportStateDao(widget.diveDao._db);
```

But `DiveDao._db` is private. Cleaner: pass the `AppDatabase` to `AppShell` directly, or pass `ImportStateDao` separately.

Simplest fix: `AppShell` takes `AppDatabase db` instead of (or in addition to) `DiveDao diveDao`. Then it creates both DAOs internally.

Update `lib/ui/app_shell.dart`:
```dart
class AppShell extends StatefulWidget {
  final AppDatabase db;

  const AppShell({super.key, required this.db});
  ...
}

class _AppShellState extends State<AppShell> {
  ...
  late final DiveDao _diveDao;
  late final ImportStateDao _importStateDao;

  @override
  void initState() {
    super.initState();
    _diveDao = DiveDao(widget.db);
    _importStateDao = ImportStateDao(widget.db);
    _diveListNotifier = DiveListNotifier(_diveDao);
    _importNotifier = ImportNotifier(dao: _diveDao, importStateDao: _importStateDao, useMock: kDebugMode);
  }
```

Update `IndexedStack` children to use `_diveDao`:
```dart
DiveListScreen(notifier: _diveListNotifier, diveDao: _diveDao),
```

- [ ] **Step 2: Update main.dart**

Change `AppShell(diveDao: DiveDao(db))` to `AppShell(db: db)`.

- [ ] **Step 3: Verify everything compiles and tests pass**

Run: `flutter analyze && flutter test`
Expected: No issues, all tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/ui/app_shell.dart lib/main.dart
git commit -m "feat: thread AppDatabase through AppShell, wire ImportStateDao"
```

---

### Task 6: Verify and push

- [ ] **Step 1: Run all tests**

Run: `flutter test`
Expected: All tests pass

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 3: Build for iOS (verify BLE permissions included)**

Run: `flutter build ios --no-codesign` (or `flutter build macos` for desktop)
Expected: Build succeeds

- [ ] **Step 4: Push**

```bash
git push origin main
```
