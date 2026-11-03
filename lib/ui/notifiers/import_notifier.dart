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
import 'package:subsurface_core/data/models/dive.dart' show generateDiveId;
import '../../shearwater/ble/ble_io_impl.dart';
import '../../shearwater/ble/mock_ble_transport.dart';
import '../../shearwater/ble/shearwater_ble_transport.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import '../../shearwater/parser/dive_parser.dart';
import '../../shearwater/parser/manifest_parser.dart';
import '../../sync/cloud/usage_tracker.dart';

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
  final UsageTracker? _usageTracker;
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

  // Per-dive download progress, surfaced live during the bulk BLE
  // transfer so the import screen can show "Downloading dive N of M
  // (X%)" instead of a single global indeterminate spinner.
  int? _currentDiveIndex; // 0-based, into the manifest passed to downloadAll.
  int? _totalDives;
  int? _diveBytes;
  int? _diveTotalBytes;
  ManifestEntry? _currentEntry;

  // Throttle for notifyListeners during the high-frequency progress
  // stream. Coalesces multiple updates into a single rebuild at ~10 Hz
  // so a multi-minute download doesn't pin the UI thread.
  static const Duration _notifyMinGap = Duration(milliseconds: 100);
  int _lastNotifyMs = 0;
  Timer? _pendingNotify;

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
    UsageTracker? usageTracker,
    this.useMock = false,
  })  : _dao = dao,
        _importStateDao = importStateDao,
        _equipmentDao = equipmentDao,
        _usageTracker = usageTracker;

  // ── Accessors ──────────────────────────────────────────────────────────────

  ImportFlowState get state => _state;
  DeviceInfo? get deviceInfo => _deviceInfo;
  List<ManifestEntry> get newDives => List.unmodifiable(_newDives);
  int get downloadedCount => _downloadedCount;
  int get totalToDownload => _totalToDownload;
  int? get currentDiveNumber => _currentDiveNumber;
  String? get errorMessage => _errorMessage;
  int get failedCount => _failedCount;

  /// 0-based index into the download subset of the dive currently
  /// streaming bytes from the device. Null until the first progress
  /// event has arrived, or after the download finishes.
  int? get currentDiveIndex => _currentDiveIndex;

  /// Total dives in the current download subset, mirrored from the
  /// transport's progress events. Mostly redundant with
  /// [totalToDownload] but kept distinct so the UI can fall back when
  /// the progress stream hasn't started yet.
  int? get totalDives => _totalDives;

  /// Fraction (0.0 – 1.0) of the current dive's compressed allocation
  /// that has streamed in so far. Null when no progress is known yet
  /// (use indeterminate UI in that case).
  double? get currentDiveProgress {
    final tot = _diveTotalBytes;
    if (tot == null || tot == 0) return null;
    return (_diveBytes ?? 0) / tot;
  }

  /// Manifest entry for the dive currently being downloaded, surfaced
  /// so the UI can show dive number + date alongside the progress bar.
  ManifestEntry? get currentEntry => _currentEntry;

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
  /// The Petrel's fingerprint pre-filter is the first line of defence; the
  /// local-DB existence check below is the belt-and-braces backup for when
  /// the saved fingerprint is stale (partial prior import, manual reset,
  /// fresh install with cloud-synced dives, etc). When [forceFullReimport]
  /// is on, both filters are bypassed so the user sees every dive on the
  /// device. The authoritative dedup still happens inside
  /// [DiveDao.importDive] regardless.
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

      var entries = manifest.where((e) => e.isValid).toList();

      if (!_forceFullReimport && entries.isNotEmpty) {
        final serial = int.parse(_deviceInfo!.serial, radix: 16);
        final ids = entries
            .map((e) => generateDiveId(serial, e.diveNumber, e.startTimestamp))
            .toList(growable: false);
        final existing = await _dao.existingDiveIdsAmong(ids);
        if (existing.isNotEmpty) {
          entries = [
            for (var i = 0; i < entries.length; i++)
              if (!existing.contains(ids[i])) entries[i],
          ];
        }
      }

      _newDives = entries;
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
  /// Downloads [subset] (defaults to every new dive) and persists each one.
  ///
  /// Pass [subset] from the UI when the user has unchecked some entries
  /// in the manifest list — useful for batching huge log lists into
  /// multiple sessions to dodge Petrel session timers and battery
  /// concerns. The fingerprint that gets saved at the end is the last
  /// imported dive in [subset]; if you skip older dives via the UI,
  /// they may be hidden from future incremental scans (use the
  /// "Force full re-scan" toggle to bring them back).
  Future<void> downloadAll([List<ManifestEntry>? subset]) async {
    final toDownload = subset ?? _newDives;
    _totalToDownload = toDownload.length;
    _state = ImportFlowState.downloading;
    _downloadedCount = 0;
    _failedCount = 0;
    _currentDiveIndex = null;
    _totalDives = toDownload.length;
    _diveBytes = null;
    _diveTotalBytes = null;
    _currentEntry = null;
    notifyListeners();

    final parser = ShearwaterDiveParser(model: _deviceInfo!.model);
    final serial = int.parse(_deviceInfo!.serial, radix: 16);
    ManifestEntry? lastSuccessfulEntry;

    // Persist each dive as soon as it lands. The earlier two-phase split
    // existed to avoid interleaving disk writes with BLE downloads, but
    // the actual BLE timeout culprits turned out to be elsewhere
    // (iOS screen-lock → wakelock_plus; disconnect handshake hang →
    // 3s cap below). PowerSync writes are sub-second; the Petrel
    // log-mode session timer is ~60s, so per-dive commits leave plenty
    // of headroom — and a mid-batch BLE drop now keeps every dive that
    // already made it to disk.
    try {
      final Stream<DownloadEvent> eventStream = _isRealBle
          ? _realTransport!.downloadDives(toDownload)
          : _mockTransport!.downloadDives(toDownload);

      await for (final event in eventStream) {
        switch (event) {
          case DownloadProgressEvent():
            _currentDiveIndex = event.diveIndex;
            _totalDives = event.totalDives;
            _diveBytes = event.diveBytes;
            _diveTotalBytes = event.diveTotalBytes;
            _currentEntry = event.currentEntry;
            _currentDiveNumber = event.currentEntry.diveNumber;
            _notifyThrottled();

          case DownloadedDive():
            final d = event;
            _currentDiveNumber = d.manifest.diveNumber;
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
            // Forward-compatible: parser does not currently surface
            // scrubberResetAt. Failures here are local and non-fatal.
            try {
              await _equipmentDao.applyScrubberEvents(
                scrubberResetAt: null,
                dcSerial: serial,
              );
            } catch (e) {
              debugPrint('Failed to apply scrubber events: $e');
            }
            // After a dive lands, force a non-throttled rebuild so
            // the "N of M imported" counter updates immediately —
            // each save is the most informative UX moment.
            _flushNotify();
        }
      }
    } catch (e) {
      _errorMessage =
          'Connection lost. $_downloadedCount of $_totalToDownload dives downloaded.';
      _state = ImportFlowState.error;
    }

    // Release the BLE link, but cap the wait. The Shearwater shutdown
    // handshake (a WDBI write the unit is meant to ack) silently never
    // returns once the Petrel has already left log mode — common after
    // the last selected dive came down. Three seconds is plenty for a
    // healthy disconnect; longer means the device already walked away.
    if (_isRealBle) {
      try {
        await _realTransport!
            .disconnect()
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('BLE disconnect timed out / failed (non-fatal): $e');
      }
    }

    if (_state != ImportFlowState.error) {
      _state = ImportFlowState.done;
    }

    // Beta telemetry: success / failure of the BLE import flow. Fires on
    // both the happy path and the error path so we can see the success
    // rate in the field. Mock-device imports are tagged separately so
    // they don't pollute the real-hardware signal.
    if (_state == ImportFlowState.done) {
      _usageTracker?.track('import_completed', {
        'dives': _downloadedCount,
        'total': _totalToDownload,
        'mock': useMock,
      });
    } else if (_state == ImportFlowState.error) {
      _usageTracker?.track('import_failed', {
        'dives': _downloadedCount,
        'total': _totalToDownload,
        // Truncate to keep telemetry rows small and avoid leaking
        // long-string user context in the rare case the error string
        // includes them.
        'reason': (_errorMessage ?? '').length > 200
            ? (_errorMessage ?? '').substring(0, 200)
            : (_errorMessage ?? ''),
        'mock': useMock,
      });
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
    _currentDiveIndex = null;
    _diveBytes = null;
    _diveTotalBytes = null;
    _currentEntry = null;
    _flushNotify();
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
    _pendingNotify?.cancel();
    _pendingNotify = null;
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
    _currentDiveIndex = null;
    _totalDives = null;
    _diveBytes = null;
    _diveTotalBytes = null;
    _currentEntry = null;
    _pendingNotify?.cancel();
    _pendingNotify = null;
    _stopScan();
  }

  /// Coalesce high-frequency progress updates. Fires `notifyListeners`
  /// immediately if at least [_notifyMinGap] has passed since the last
  /// emit, otherwise schedules a deferred fire so the latest state is
  /// still flushed within that window. ~10 Hz cap.
  void _notifyThrottled() {
    if (_disposed) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastNotifyMs >= _notifyMinGap.inMilliseconds) {
      _lastNotifyMs = nowMs;
      _pendingNotify?.cancel();
      _pendingNotify = null;
      notifyListeners();
      return;
    }
    if (_pendingNotify != null) return;
    final delay = Duration(
      milliseconds: _notifyMinGap.inMilliseconds - (nowMs - _lastNotifyMs),
    );
    _pendingNotify = Timer(delay, () {
      _pendingNotify = null;
      if (_disposed) return;
      _lastNotifyMs = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
    });
  }

  /// Cancel any pending throttled notify and fire immediately. Used at
  /// boundaries (per-dive save, end of download) where the user would
  /// otherwise notice the lag between actual state change and rebuild.
  void _flushNotify() {
    if (_disposed) return;
    _pendingNotify?.cancel();
    _pendingNotify = null;
    _lastNotifyMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }

  int? _parseFirmwareVersion(String firmware) {
    // "V103 DiveCAN" → 103
    final m = RegExp(r'V(\d+)').firstMatch(firmware);
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}
