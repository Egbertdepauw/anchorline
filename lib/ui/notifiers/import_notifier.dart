/// State machine for the BLE import wizard.
///
/// Drives the import flow: idle → scanning → connecting →
/// readingManifest → downloading → done / error.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/db/import_state_dao.dart';
import '../../shearwater/ble/ble_io_impl.dart';
import '../../shearwater/ble/mock_ble_transport.dart';
import '../../shearwater/ble/shearwater_ble_transport.dart';
import '../../shearwater/parser/dive_converter.dart';
import '../../shearwater/parser/dive_parser.dart';
import '../../shearwater/parser/manifest_parser.dart';

/// Phases of the import flow.
///
/// Named [ImportFlowState] to avoid collision with the Drift-generated
/// [ImportFlowState] data class from the [ImportFlowStates] table.
enum ImportFlowState {
  idle,
  scanning,
  connecting,
  readingManifest,
  downloading,
  done,
  error,
}

/// ChangeNotifier driving the BLE import wizard UI.
///
/// When constructed with `useMock: true` a [MockBleTransport] is used
/// instead of real BLE — useful in tests and for UI development on a
/// desktop without hardware.
class ImportNotifier extends ChangeNotifier {
  final DiveDao _dao;
  final ImportStateDao _importStateDao;
  final EquipmentDao _equipmentDao;
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
  bool _forceFullReimport = false;

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
    required EquipmentDao equipmentDao,
    this.useMock = false,
  })  : _dao = dao,
        _importStateDao = importStateDao,
        _equipmentDao = equipmentDao;

  // ── Accessors ──────────────────────────────────────────────────────────────

  ImportFlowState get state => _state;
  DeviceInfo? get deviceInfo => _deviceInfo;
  List<ManifestEntry> get newDives => List.unmodifiable(_newDives);
  int get downloadedCount => _downloadedCount;
  int get totalToDownload => _totalToDownload;
  int? get currentDiveNumber => _currentDiveNumber;
  String? get errorMessage => _errorMessage;
  int get failedCount => _failedCount;

  /// Whether the mock device advertisement is ready to be selected.
  bool get mockDeviceAvailable => _mockDeviceAvailable;

  /// When true, the next manifest read ignores the saved fingerprint and
  /// downloads every dive on the device (overriding incremental sync).
  bool get forceFullReimport => _forceFullReimport;
  set forceFullReimport(bool value) {
    if (_forceFullReimport == value) return;
    _forceFullReimport = value;
    notifyListeners();
  }

  /// Real BLE devices discovered during scanning.
  List<BluetoothDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  // ── Scanning ───────────────────────────────────────────────────────────────

  /// Begin scanning. Transitions immediately to [ImportFlowState.scanning].
  ///
  /// In mock mode, [mockDeviceAvailable] becomes `true` after a short delay.
  /// Real BLE devices are discovered via [FlutterBluePlus] and collected into
  /// [discoveredDevices].
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

    unawaited(_startRealScan());
  }

  Future<void> _startRealScan() async {
    // On macOS the Core Bluetooth manager starts in `unknown` and only
    // reaches `on` after the OS finishes initializing the adapter (and the
    // user has answered the Bluetooth permission prompt). Calling startScan
    // before that races and fails with CBManagerStateUnknown.
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('BLE adapter never reached on state: $e');
        return;
      }
      if (_disposed) return;
    }

    // Subscribe to results before starting the scan so we don't miss
    // advertisements that arrive immediately.
    try {
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        var changed = false;
        for (final result in results) {
          if (result.advertisementData.serviceUuids.any((uuid) =>
              uuid.toString().toLowerCase() ==
              shearwaterServiceUuid.toLowerCase())) {
            if (!_discoveredDevices
                .any((d) => d.remoteId == result.device.remoteId)) {
              _discoveredDevices.add(result.device);
              changed = true;
            }
          }
        }
        if (changed && !_disposed) notifyListeners();
      });
    } catch (e) {
      debugPrint('BLE scan results subscription error: $e');
    }

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15))
        .catchError((Object e) => debugPrint('BLE scan error: $e'));
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    FlutterBluePlus.stopScan().catchError((Object _) {});
  }

  // ── Connect (mock) ─────────────────────────────────────────────────────────

  /// Connect to the mock device and read device info.
  ///
  /// Transitions: scanning → connecting → readingManifest.
  Future<void> selectMockDevice() async {
    _stopScan();
    await _enableWakelock();
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
      await _disableWakelock();
    }
    notifyListeners();
  }

  // ── Connect (real BLE) ─────────────────────────────────────────────────────

  /// Connect to a real BLE device and read device info.
  ///
  /// Transitions: scanning → connecting → readingManifest.
  Future<void> selectRealDevice(BluetoothDevice device) async {
    _stopScan();
    await _enableWakelock();
    _state = ImportFlowState.connecting;
    notifyListeners();

    try {
      _realTransport = ShearwaterBleTransport();
      await _realTransport!.connect(device);
      _deviceInfo = await _realTransport!.readDeviceInfo();
      try {
        await _equipmentDao.upsertDiveComputer(
          serial: int.parse(_deviceInfo!.serial, radix: 16),
          model: _deviceInfo!.hardwareId,
          firmwareVersion: _parseFirmwareVersion(_deviceInfo!.firmware),
        );
      } catch (e) {
        debugPrint('Failed to upsert DiveComputer row: $e');
      }
      _state = ImportFlowState.readingManifest;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _state = ImportFlowState.error;
      try {
        await _realTransport?.disconnect();
      } catch (_) {}
      await _disableWakelock();
      _realTransport = null;
    }
    notifyListeners();
  }

  // ── Manifest ───────────────────────────────────────────────────────────────

  bool get _isRealBle => _realTransport != null;

  /// Read the manifest and filter out dives that are already in the database.
  ///
  /// For real BLE, passes the last known fingerprint from [ImportStateDao] so
  /// the device can return only newer dives (incremental sync).
  ///
  /// The pre-filter is an optimisation: the authoritative dedup happens
  /// inside [DiveDao.importDive], which returns `false` for existing dives.
  Future<void> readManifestAndFilterNew() async {
    try {
      List<ManifestEntry> manifest;

      if (_isRealBle) {
        final lastFp = _forceFullReimport
            ? null
            : await _importStateDao.getLastFingerprint(_deviceInfo!.serial);
        manifest =
            await _realTransport!.readManifest(lastFingerprint: lastFp);
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

  // ── Download ───────────────────────────────────────────────────────────────

  /// Download and persist all queued dives.
  ///
  /// Each dive is parsed and committed atomically. Failures on individual
  /// dives are counted in [failedCount] and do not abort the stream.
  ///
  /// On completion (success or connection error), the newest successfully
  /// imported fingerprint is saved via [ImportStateDao] for incremental sync
  /// on the next import session.
  Future<void> downloadAll() async {
    _state = ImportFlowState.downloading;
    _downloadedCount = 0;
    _failedCount = 0;
    notifyListeners();

    final parser = ShearwaterDiveParser(model: _deviceInfo!.model);
    final serial = int.parse(_deviceInfo!.serial, radix: 16);
    ManifestEntry? lastSuccessfulEntry;

    // Two-phase to keep BLE off the disk-write critical path. Shearwater
    // computers (Petrel 1/2 especially) drop the connection if we don't
    // request the next dive within ~15–30 seconds, and Phase 2.5's
    // PowerSync writes are heavy enough (14 base64'd blob columns) that
    // interleaving them with BLE downloads can blow that budget.
    //
    // Phase 1: pull every dive off the wire into memory as fast as the
    //          dive computer will hand them over. No disk I/O.
    // Phase 2: parse + persist sequentially with the BLE link already
    //          released. No timeout pressure.

    final downloaded = <DownloadedDive>[];
    try {
      final diveStream = _isRealBle
          ? _realTransport!.downloadDives(_newDives)
          : _mockTransport!.downloadDives(_newDives);

      await for (final d in diveStream) {
        _currentDiveNumber = d.manifest.diveNumber;
        notifyListeners();
        downloaded.add(d);
      }
    } catch (e) {
      _errorMessage =
          'Connection lost. ${downloaded.length} of $_totalToDownload dives downloaded.';
      _state = ImportFlowState.error;
      // Even on a partial download, persist whatever we did get so the
      // user doesn't have to repeat the BLE handshake from scratch.
    }

    // Release the BLE link before any disk work — no more timeout pressure.
    if (_isRealBle) {
      try {
        await _realTransport!.disconnect();
      } catch (_) {}
    }

    // Phase 2: parse + persist. Failures here are local; the BLE side
    // is already done.
    for (final d in downloaded) {
      _currentDiveNumber = d.manifest.diveNumber;
      notifyListeners();
      try {
        final parsed = parser.parse(d.data);
        final converted = DiveConverter.convert(
          parsed: parsed,
          dcSerial: serial,
          dcDiveNumber: d.manifest.diveNumber,
          dcModel: _deviceInfo!.model,
        );
        final imported = await _dao.importDive(
          converted: converted,
          rawBlob: d.data,
          parserVersion: 1,
        );
        if (imported) {
          _downloadedCount++;
          lastSuccessfulEntry = d.manifest;
        }
      } catch (e) {
        debugPrint('Failed to import dive ${d.manifest.diveNumber}: $e');
        _failedCount++;
      }
      // Forward-compatible: parser does not currently surface scrubberResetAt.
      try {
        await _equipmentDao.applyScrubberEvents(
          scrubberResetAt: null,
          dcSerial: serial,
        );
      } catch (e) {
        debugPrint('Failed to apply scrubber events: $e');
      }
      notifyListeners();
    }

    if (_state != ImportFlowState.error) {
      _state = ImportFlowState.done;
    }

    // Save fingerprint for incremental sync on real BLE imports
    if (_isRealBle && lastSuccessfulEntry != null) {
      await _importStateDao.saveLastFingerprint(
        _deviceInfo!.serial,
        lastSuccessfulEntry.fingerprint,
      );
    }

    // BLE work is fully done — let the screen sleep again.
    await _disableWakelock();

    _currentDiveNumber = null;
    notifyListeners();
  }

  // ── Error / retry ──────────────────────────────────────────────────────────

  /// Manually push into the error state (useful in tests).
  void setError(String message) {
    _errorMessage = message;
    _state = ImportFlowState.error;
    notifyListeners();
  }

  /// Reset and restart scanning after an error.
  void retry() {
    _reset();
    startScan();
  }

  /// Reset to idle without starting a scan.
  void reset() {
    _reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopScan();
    _realTransport?.disconnect();
    // Best-effort: don't await, the framework expects dispose to be sync.
    unawaited(_disableWakelock());
    super.dispose();
  }

  // ── Wakelock ──────────────────────────────────────────────────────────────
  //
  // iOS suspends BLE callbacks when the screen auto-locks (default 30s),
  // and the Petrel's log-mode session timer (~60s) fires shortly after,
  // killing the import even though the user is staring at the progress
  // screen. Hold a wakelock for the whole BLE-active window.
  //
  // Errors are swallowed: the platform implementations no-op on
  // unsupported targets, but tests can hit MissingPluginException and we
  // don't want that to fail the import flow.

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('Wakelock enable failed (non-fatal): $e');
    }
  }

  Future<void> _disableWakelock() async {
    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('Wakelock disable failed (non-fatal): $e');
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

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
    _forceFullReimport = false;
    _stopScan();
  }

  int? _parseFirmwareVersion(String firmware) {
    // "V103 DiveCAN" → 103
    final m = RegExp(r'V(\d+)').firstMatch(firmware);
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}
