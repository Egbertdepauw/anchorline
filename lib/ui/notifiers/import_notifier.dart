/// State machine for the BLE import wizard.
///
/// Drives the import flow: idle → scanning → connecting →
/// readingManifest → downloading → done / error.
library;

import 'package:flutter/foundation.dart';

import '../../data/db/dive_dao.dart';
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
  MockBleTransport? _mockTransport;
  bool _mockDeviceAvailable = false;

  ImportNotifier({required DiveDao dao, this.useMock = false}) : _dao = dao;

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

  // ── State transitions ──────────────────────────────────────────────────────

  /// Begin scanning. Transitions immediately to [ImportFlowState.scanning].
  ///
  /// In mock mode, [mockDeviceAvailable] becomes `true` after a short delay.
  void startScan() {
    _state = ImportFlowState.scanning;
    _mockDeviceAvailable = false;
    notifyListeners();

    if (useMock) {
      Future<void>.delayed(const Duration(milliseconds: 300)).then((_) {
        if (_disposed) return;
        _mockDeviceAvailable = true;
        notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Connect to the mock device and read device info.
  ///
  /// Transitions: scanning → connecting → readingManifest.
  Future<void> selectMockDevice() async {
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

  /// Read the manifest and filter out dives that are already in the database.
  ///
  /// The pre-filter is an optimisation: the authoritative dedup happens
  /// inside [DiveDao.importDive], which returns `false` for existing dives.
  /// Because mock manifest entries use synthetic timestamps (not the blob's
  /// actual start time), we skip the pre-filter for mock entries to avoid
  /// false-positive hits.  All valid entries are queued; duplicates will be
  /// discarded by [DiveDao.importDive] at import time.
  Future<void> readManifestAndFilterNew() async {
    try {
      final manifest = await _mockTransport!.readManifest();
      _newDives = manifest.where((e) => e.isValid).toList();
      _totalToDownload = _newDives.length;
    } catch (e) {
      _errorMessage = 'Failed to read manifest: $e';
      _state = ImportFlowState.error;
    }
    notifyListeners();
  }

  /// Download and persist all queued dives.
  ///
  /// Each dive is parsed and committed atomically. Failures on individual
  /// dives are counted in [failedCount] and do not abort the stream.
  Future<void> downloadAll() async {
    _state = ImportFlowState.downloading;
    _downloadedCount = 0;
    _failedCount = 0;
    notifyListeners();

    final parser = ShearwaterDiveParser(model: _deviceInfo!.model);
    final serial = int.parse(_deviceInfo!.serial, radix: 16);

    try {
      await for (final downloaded in _mockTransport!.downloadDives(_newDives)) {
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
          await _dao.importDive(
            converted: converted,
            rawBlob: downloaded.data,
            parserVersion: 1,
          );
          _downloadedCount++;
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
  }
}
