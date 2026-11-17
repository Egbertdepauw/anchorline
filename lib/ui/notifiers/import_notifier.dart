/// State machine for the BLE import wizard.
///
/// Drives the import flow: idle → scanning → connecting →
/// readingManifest → downloading → done / error.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../ble/ble_central.dart';
import '../../ble/ble_central_default.dart';
import '../../devices/libdc/ble_central_libdc_link.dart';
import '../../devices/libdc/libdc_ble_profile.dart';
import '../../devices/libdc/libdc_download_source.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/db/import_state_dao.dart';
import '../../data/import/import_problem_reporter.dart';
import '../../devices/dive_download_source.dart';
import '../../devices/shearwater/shearwater_download_source.dart';
import '../../shearwater/ble/ble_io_impl.dart';
import '../../shearwater/ble/mock_ble_transport.dart';
import '../../shearwater/ble/shearwater_ble_transport.dart';
import '../../shearwater/ble/shearwater_link.dart';
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

/// What a device seen in the scan is.
enum ImportDeviceKind {
  /// Advertises the Shearwater service; goes to the Dart reader.
  shearwater,

  /// Its advertised name matches at least one libdivecomputer model.
  libdc,

  /// Has a name, but libdivecomputer doesn't recognise it. Offered to the
  /// model picker ("My computer isn't listed").
  unmatched,
}

/// One device seen in the scan.
class ImportScanResult {
  const ImportScanResult({
    required this.id,
    required this.name,
    required this.kind,
    this.candidates = const [],
  });

  /// The id [BleCentral.peripheral] takes.
  final String id;

  /// The advertised name, or '' (a Shearwater device may give none).
  final String name;

  final ImportDeviceKind kind;

  /// The libdivecomputer models the name matches; empty unless [kind] is
  /// [ImportDeviceKind.libdc].
  final List<LibdcDescriptor> candidates;
}

/// An open connection to a libdivecomputer device.
class LibdcOpened {
  const LibdcOpened({
    required this.connection,
    required this.close,
    required this.gattSummary,
  });

  final LibdcConnection connection;
  final Future<void> Function() close;

  /// One line per GATT service and characteristic, for the recording.
  final List<String> gattSummary;
}

/// Connects to [d]'s device. The default goes through
/// [BleCentralLibdcLink]; tests pass a stand-in.
typedef LibdcOpener = Future<LibdcOpened> Function(
    BleCentral central, ImportScanResult r, LibdcDescriptor d);

/// A short English reason for a libdivecomputer download that stopped with
/// [status], for the message shown to the diver.
String libdcStopReason(LibdcStatus status) => switch (status) {
      LibdcStatus.timeout => 'the computer stopped answering',
      LibdcStatus.io => 'the connection dropped',
      LibdcStatus.protocol => 'unexpected data from the computer',
      LibdcStatus.cancelled => 'cancelled',
      _ => 'error ${status.name}',
    };

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
  final ImportProblemReporter _report;
  final bool useMock;
  final BleCentral? _centralOverride;
  final List<LibdcDescriptor> Function(String name) _matchBle;
  final Map<String, List<LibdcDescriptor>> _matchCache = {};
  int _scanGeneration = 0;
  final LibdcOpener? _libdcOpener;
  final LibdcStarter? _libdcStarter;

  // The libdivecomputer download in progress or just finished.
  bool _libdc = false;
  String? _libdcVendor;
  String? _recordingText;
  List<String> _gattSummary = const [];

  /// The one central the scan runs through, for both engines.
  BleCentral get _central => _centralOverride ?? defaultBleCentral();

  bool _disposed = false;
  ImportFlowState _state = ImportFlowState.idle;
  DiveDownloadSource? _source;
  DcIdentity? _identity;
  List<DiveListing> _newDives = [];
  int _downloadedCount = 0;
  int _totalToDownload = 0;
  int? _currentDiveNumber;
  String? _errorMessage;
  int _failedCount = 0;
  int _refreshedCount = 0;
  bool _forceFullReimport = false;
  bool _recordNextDownload = false;

  // Per-dive download progress, surfaced live during the bulk BLE
  // transfer so the import screen can show "Downloading dive N of M
  // (X%)" instead of a single global indeterminate spinner.
  int? _currentDiveIndex; // 0-based, into the manifest passed to downloadAll.
  int? _totalDives;
  int? _diveBytes;
  int? _diveTotalBytes;
  DiveListing? _currentEntry;

  // Throttle for notifyListeners during the high-frequency progress
  // stream. Coalesces multiple updates into a single rebuild at ~10 Hz
  // so a multi-minute download doesn't pin the UI thread.
  static const Duration _notifyMinGap = Duration(milliseconds: 100);
  int _lastNotifyMs = 0;
  Timer? _pendingNotify;

  // Mock
  bool _mockDeviceAvailable = false;

  // Real BLE
  final List<ImportScanResult> _discoveredDevices = [];
  StreamSubscription<BleScanResult>? _scanSubscription;

  ImportNotifier({
    required DiveDao dao,
    required ImportStateDao importStateDao,
    required EquipmentDao equipmentDao,
    UsageTracker? usageTracker,
    this.useMock = false,
    ImportProblemReporter? reporter,
    BleCentral? central,
    List<LibdcDescriptor> Function(String name)? matchBle,
    LibdcOpener? libdcOpener,
    LibdcStarter? libdcStarter,
  })  : _libdcOpener = libdcOpener,
        _libdcStarter = libdcStarter,
        _centralOverride = central,
        _matchBle = matchBle ?? Libdc.matchBle,
        _dao = dao,
        _importStateDao = importStateDao,
        _equipmentDao = equipmentDao,
        _usageTracker = usageTracker,
        _report = reporter ?? reportImportProblemToSentry;

  // ── Accessors ──────────────────────────────────────────────────────────────

  ImportFlowState get state => _state;
  DcIdentity? get identity => _identity;
  List<DiveListing> get newDives => List.unmodifiable(_newDives);
  int get downloadedCount => _downloadedCount;
  int get totalToDownload => _totalToDownload;
  int? get currentDiveNumber => _currentDiveNumber;
  String? get errorMessage => _errorMessage;
  int get failedCount => _failedCount;

  /// Dives of the current download whose stored data was refreshed in place.
  /// A detail screen opened before the download may show stale cylinder rows.
  int get refreshedCount => _refreshedCount;

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
  DiveListing? get currentEntry => _currentEntry;

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

  /// When true, the next libdivecomputer download records the packets as
  /// well as the log, so the file can be shared with us. Off by default.
  bool get recordNextDownload => _recordNextDownload;
  set recordNextDownload(bool value) {
    if (_recordNextDownload == value) return;
    _recordNextDownload = value;
    notifyListeners();
  }

  /// Whether the download in progress (or just finished) is a
  /// libdivecomputer one rather than a Shearwater one.
  bool get isLibdcDownload => _libdc;

  /// The recording of the last libdivecomputer download: its log and
  /// envelopes, plus the packets when recording was on. Null before one ends
  /// and after a failed connect.
  String? get lastRecordingText => _recordingText;

  /// The GATT services and characteristics of the last libdivecomputer
  /// device, one line each.
  List<String> get lastGattSummary => List.unmodifiable(_gattSummary);

  /// Devices seen during scanning: Shearwater and libdivecomputer ones, and
  /// named devices nobody recognises ([ImportDeviceKind.unmatched]).
  List<ImportScanResult> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  // ── Scanning ───────────────────────────────────────────────────────────────

  /// Begin scanning. Transitions immediately to [ImportFlowState.scanning].
  ///
  /// In mock mode, [mockDeviceAvailable] becomes `true` after a short delay.
  /// Real BLE devices are discovered through the [BleCentral] and collected
  /// into [discoveredDevices].
  void startScan() {
    _scanGeneration++;
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
    final generation = _scanGeneration;
    // On macOS the Core Bluetooth manager starts in `unknown` and only
    // reaches `on` after the OS finishes initializing the adapter (and the
    // user has answered the Bluetooth permission prompt). Calling scan
    // before that races and fails with CBManagerStateUnknown.
    final BleCentral central;
    try {
      central = _central;
    } catch (e) {
      debugPrint('BLE central unavailable: $e');
      return;
    }
    final adapter =
        await waitForAdapterOn(central, const Duration(seconds: 15));
    // A reset, a new scan or a selection during the wait ends this one;
    // exactly one scan may run (the same central connects afterwards).
    if (_disposed || generation != _scanGeneration) return;
    if (adapter != BleAdapterState.on) {
      debugPrint('BLE adapter never reached on state: $adapter');
      return;
    }

    // One scan, no service filter: Shearwater computers are told apart by
    // their service UUID, the others by their advertised name.
    try {
      unawaited(_scanSubscription?.cancel());
      _scanSubscription = central
          .scan(timeout: const Duration(seconds: 15))
          .listen(_onScanResult,
              onError: (Object e) => debugPrint('BLE scan error: $e'));
    } catch (e) {
      debugPrint('BLE scan error: $e');
    }
  }

  void _onScanResult(BleScanResult r) {
    if (_disposed) return;
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final ImportScanResult? result;
    if (r.advertises(shearwaterServiceUuid)) {
      // Shearwater stays unlisted on Windows, as before: its transport is
      // flutter_blue_plus, which has no Windows support.
      result = isWindows
          ? null
          : ImportScanResult(
              id: r.id, name: r.name, kind: ImportDeviceKind.shearwater);
    } else if (r.name.isEmpty) {
      result = null;
    } else {
      // matchBle walks libdivecomputer's descriptors over FFI; one name is
      // advertised many times.
      final candidates = _matchCache.putIfAbsent(r.name, () => _matchBle(r.name));
      result = ImportScanResult(
        id: r.id,
        name: r.name,
        kind: candidates.isNotEmpty
            ? ImportDeviceKind.libdc
            : ImportDeviceKind.unmatched,
        candidates: candidates,
      );
    }
    if (result == null) return;
    final i = _discoveredDevices.indexWhere((d) => d.id == r.id);
    if (i < 0) {
      _discoveredDevices.add(result);
    } else {
      // The same device again: only a newly learned name or kind changes
      // anything.
      final old = _discoveredDevices[i];
      if (old.kind == ImportDeviceKind.shearwater &&
          result.kind != ImportDeviceKind.shearwater) {
        // A later report without the service UUID (the stack reports the
        // advertisement and the scan response apart) must not demote a
        // listed Shearwater; at most it brings a name.
        if (result.name.isEmpty || result.name == old.name) return;
        _discoveredDevices[i] = ImportScanResult(
            id: old.id, name: result.name, kind: ImportDeviceKind.shearwater);
      } else {
        if (old.name == result.name && old.kind == result.kind) return;
        _discoveredDevices[i] = result;
      }
    }
    notifyListeners();
  }

  void _stopScan() {
    _scanGeneration++;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      _central.stopScan().catchError((Object _) {});
    } catch (_) {}
  }

  // ── Connect (mock) ─────────────────────────────────────────────────────────

  /// Connect to the mock device and read device info.
  ///
  /// Transitions: scanning → connecting → readingManifest.
  Future<void> selectMockDevice() async {
    _libdc = false;
    _stopScan();
    await _enableWakelock();
    _state = ImportFlowState.connecting;
    notifyListeners();

    await _connectLink(
      MockBleTransport(perDiveDelay: const Duration(milliseconds: 100)),
    );
  }

  /// Connects through [link] as the mock device would. Tests use it to
  /// inject a link that misbehaves.
  @visibleForTesting
  Future<void> connectLinkForTest(ShearwaterLink link) async {
    _libdc = false;
    _stopScan();
    _state = ImportFlowState.connecting;
    notifyListeners();
    await _connectLink(link);
  }

  Future<void> _connectLink(ShearwaterLink link) async {
    try {
      if (link is MockBleTransport) await link.connectMock();
      _source = await ShearwaterDownloadSource.open(link);
      _identity = _source!.identity;
      // The mock device has never been registered as a dive computer.
      if (link is! MockBleTransport) await _registerComputer(_identity!);
      _state = ImportFlowState.readingManifest;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _state = ImportFlowState.error;
      await _closeLink(link);
      await _disableWakelock();
    }
    notifyListeners();
  }

  // ── Connect (real BLE) ─────────────────────────────────────────────────────

  /// Connect to a real BLE device and read device info.
  ///
  /// Transitions: scanning → connecting → readingManifest.
  Future<void> selectRealDevice(BluetoothDevice device) async {
    _libdc = false;
    _stopScan();
    await _enableWakelock();
    _state = ImportFlowState.connecting;
    notifyListeners();

    ShearwaterLink? link;
    try {
      final transport = ShearwaterBleTransport();
      link = transport;
      await transport.connect(device);
      final source = await ShearwaterDownloadSource.open(transport);
      _source = source;
      final identity = source.identity;
      _identity = identity;
      await _registerComputer(identity);
      _state = ImportFlowState.readingManifest;
    } catch (e) {
      _errorMessage = 'Connection failed: $e';
      _state = ImportFlowState.error;
      await _closeLink(link);
      await _disableWakelock();
      _source = null;
    }
    notifyListeners();
  }

  // ── Connect and download (libdivecomputer) ─────────────────────────────────

  /// Connects to a libdivecomputer device and downloads from it. [d] is the
  /// model the user chose, or the first candidate of the chosen family: the
  /// family decides the protocol, and the model comes from the device info.
  ///
  /// Transitions: scanning → connecting → downloading → done / error. There
  /// is no manifest step: libdivecomputer cannot list dives first. Never
  /// throws; a failure ends in [ImportFlowState.error].
  Future<void> selectLibdcDevice(ImportScanResult r, LibdcDescriptor d) async {
    _stopScan();
    _libdc = true;
    _libdcVendor = d.vendor;
    _recordingText = null;
    _gattSummary = const [];
    await _enableWakelock();
    _state = ImportFlowState.connecting;
    notifyListeners();

    try {
      final opened = await (_libdcOpener ?? _openLibdc)(_central, r, d);
      _gattSummary = opened.gattSummary;
      final source = LibdcDownloadSource(
        descriptor: d,
        connection: opened.connection,
        closeConnection: opened.close,
        fingerprints: _forceFullReimport ? null : _importStateDao,
        record: _recordNextDownload,
        starter: _libdcStarter,
      );
      _source = source;
    } catch (e) {
      // BleException messages are short fixed texts; anything else gets a
      // generic one, never the raw error.
      _errorMessage = 'Connection failed: '
          '${e is BleException ? e.message : 'could not connect'}';
      _state = ImportFlowState.error;
      await _disableWakelock();
      notifyListeners();
      return;
    }
    await downloadAll();
  }

  static Future<LibdcOpened> _openLibdc(
      BleCentral central, ImportScanResult r, LibdcDescriptor d) async {
    final link = await BleCentralLibdcLink.connect(
      central,
      r.id,
      advertisedName: r.name,
      profile: libdcProfileFor(d),
    );
    return LibdcOpened(
      connection: LibdcBleConnection(link),
      close: link.close,
      gattSummary: link.gattSummary,
    );
  }

  /// Asks a running libdivecomputer download to stop. The dives that have
  /// arrived are kept.
  void cancelDownload() {
    final s = _source;
    if (s is LibdcDownloadSource) s.cancel();
  }

  /// Records the connected computer in `dive_computers`. Failures are local
  /// and non-fatal.
  Future<void> _registerComputer(DcIdentity identity) async {
    try {
      await _equipmentDao.upsertDiveComputer(
        vendor: identity.vendor,
        product: identity.product,
        serial: identity.serial,
        model: identity.computerModel,
        firmwareVersion: identity.firmware,
        family: identity.family,
        modelCode: identity.modelCode,
      );
    } catch (e) {
      debugPrint('Failed to upsert DiveComputer row: $e');
    }
  }

  /// Disconnects a link whose source never opened (a failed connect or
  /// device-info read), so the Bluetooth connection is not left dangling.
  Future<void> _closeLink(ShearwaterLink? link) async {
    try {
      await link?.disconnect();
    } catch (_) {}
  }

  // ── Manifest ───────────────────────────────────────────────────────────────

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
      final lastFp = _forceFullReimport
          ? null
          : await _importStateDao.getLastFingerprint(_identity!.importStateKey);
      var entries = await _source!.listDives(sinceFingerprint: lastFp);

      if (!_forceFullReimport && entries.isNotEmpty) {
        final existing = await _dao.alreadyDownloadedAmong(
          entries.map((l) => (
                diveId: l.diveId,
                startTimeSeconds: l.startTimestamp,
                diveNumber: l.diveNumber,
              )).toList(growable: false),
          vendor: _identity!.vendor,
          serial: _identity!.serial,
        );
        if (existing.isNotEmpty) {
          entries = [
            for (final e in entries)
              if (!existing.contains(e.diveId)) e,
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
  Future<void> downloadAll([List<DiveListing>? subset]) async {
    final toDownload = subset ?? _newDives;
    _totalToDownload = toDownload.length;
    _state = ImportFlowState.downloading;
    _downloadedCount = 0;
    _failedCount = 0;
    _refreshedCount = 0;
    _currentDiveIndex = null;
    _totalDives = toDownload.length;
    _diveBytes = null;
    _diveTotalBytes = null;
    _currentEntry = null;
    notifyListeners();

    // libdivecomputer learns the computer during the download (see
    // DiveSourceIdentified), so the serial can change from 0.
    var serial = _identity?.serial ?? 0;
    Uint8List? lastSuccessfulFingerprint;

    // Persist each dive as soon as it lands. The earlier two-phase split
    // existed to avoid interleaving disk writes with BLE downloads, but
    // the actual BLE timeout culprits turned out to be elsewhere
    // (iOS screen-lock → wakelock_plus; disconnect handshake hang →
    // 3s cap in ShearwaterDownloadSource.close). PowerSync writes are
    // sub-second; the Petrel log-mode session timer is ~60s, so per-dive
    // commits leave plenty of headroom — and a mid-batch BLE drop now keeps
    // every dive that already made it to disk.
    try {
      await for (final event in _source!.download(selection: toDownload)) {
        switch (event) {
          case DiveSourceProgress():
            _currentDiveIndex = event.diveIndex;
            _totalDives = event.totalDives;
            _diveBytes = event.diveBytes;
            _diveTotalBytes = event.diveTotalBytes;
            _currentEntry = event.listing;
            _currentDiveNumber = event.listing?.diveNumber;
            _notifyThrottled();

          case DiveSourceIdentified():
            // Shearwater never emits this; engines that learn the computer
            // during the download announce it here.
            final id = event.identity;
            _identity = id;
            serial = id.serial;
            await _registerComputer(id);

          case DiveSourceDive():
            _currentDiveNumber = event.listing?.diveNumber;
            try {
              final outcome = await _dao.importDive(
                converted: event.converted,
                rawBlob: event.rawBlob,
                parserVersion: event.parserVersion,
              );
              switch (outcome) {
                case ImportOutcome.refreshed:
                  _refreshedCount++;
                  _downloadedCount++;
                  lastSuccessfulFingerprint = event.fingerprint;
                case ImportOutcome.inserted:
                case ImportOutcome.insertedFlagged:
                  _downloadedCount++;
                  lastSuccessfulFingerprint = event.fingerprint;
                case ImportOutcome.unchanged:
                  break;
                case ImportOutcome.rejected:
                  _failedCount++;
                  _report(
                    const UnusableParse(),
                    null,
                    'download',
                  );
              }
            } catch (e, st) {
              debugPrint('Failed to import dive ${event.listing?.diveNumber}');
              _failedCount++;
              _report(e, st, 'download');
            }
            await _applyScrubberEvents(serial);
            // After a dive lands, force a non-throttled rebuild so
            // the "N of M imported" counter updates immediately —
            // each save is the most informative UX moment.
            _flushNotify();

          case DiveSourceDiveFailed():
            _currentDiveNumber = event.listing?.diveNumber;
            debugPrint('Failed to import dive ${event.listing?.diveNumber}');
            _failedCount++;
            _report(event.error, event.stack, 'download');
            await _applyScrubberEvents(serial);
            _flushNotify();

          case DiveSourceFinished():
            // Shearwater never emits this. Keep the recording for sharing,
            // and move the fingerprint only when no dive failed: a failed
            // dive must be fetched again next time.
            _recordingText = event.recordingText;
            final key = event.importStateKey;
            final keep = event.fingerprintToKeep;
            if (_failedCount == 0 && key != null && keep != null) {
              await _importStateDao.saveLastFingerprint(key, keep);
            }
        }
      }
    } catch (e) {
      _errorMessage = _libdc
          ? 'Download stopped (${e is LibdcDownloadFailed ? libdcStopReason(e.status) : 'unexpected error'}). '
              '$_downloadedCount dives saved.'
          : 'Connection lost. $_downloadedCount of $_totalToDownload dives downloaded.';
      _state = ImportFlowState.error;
    }

    // Release the link. The source caps the wait (see its close()).
    await _source!.close();

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
        'engine': _libdc ? 'libdc' : 'shearwater',
        'vendor': _identity?.vendor ?? _libdcVendor,
      });
    } else if (_state == ImportFlowState.error) {
      _usageTracker?.track('import_failed', {
        'dives': _downloadedCount,
        'total': _totalToDownload,
        'engine': _libdc ? 'libdc' : 'shearwater',
        'vendor': _identity?.vendor ?? _libdcVendor,
        // Truncate to keep telemetry rows small and avoid leaking
        // long-string user context in the rare case the error string
        // includes them.
        'reason': (_errorMessage ?? '').length > 200
            ? (_errorMessage ?? '').substring(0, 200)
            : (_errorMessage ?? ''),
        'mock': useMock,
      });
    }

    // Save fingerprint for incremental sync. libdivecomputer saves its own
    // at DiveSourceFinished, and only after a download without failures.
    if (!_libdc && lastSuccessfulFingerprint != null) {
      await _importStateDao.saveLastFingerprint(
        _identity!.importStateKey,
        lastSuccessfulFingerprint,
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

  // Forward-compatible: the parser does not currently surface
  // scrubberResetAt. Failures here are local and non-fatal.
  Future<void> _applyScrubberEvents(int serial) async {
    try {
      await _equipmentDao.applyScrubberEvents(
        scrubberResetAt: null,
        dcSerial: serial,
      );
    } catch (e) {
      debugPrint('Failed to apply scrubber events: $e');
    }
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
    unawaited(_source?.close());
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
    _source = null;
    _identity = null;
    _newDives = [];
    _downloadedCount = 0;
    _totalToDownload = 0;
    _currentDiveNumber = null;
    _errorMessage = null;
    _failedCount = 0;
    _refreshedCount = 0;
    _mockDeviceAvailable = false;
    _discoveredDevices.clear();
    _forceFullReimport = false;
    _libdc = false;
    _libdcVendor = null;
    _recordingText = null;
    _gattSummary = const [];
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
}
