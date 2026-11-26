/// State machine for the BLE import wizard.
///
/// Drives the import flow: idle → scanning → connecting →
/// readingManifest → downloading → done / error.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:path_provider/path_provider.dart';
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
import '../../devices/fit/fit_file_source.dart';
import '../../devices/fit/fit_inputs.dart';
import '../../devices/fit/fit_listing_marks.dart';
import '../../devices/fit/fit_tiers.dart';
import '../../devices/shearwater/shearwater_download_source.dart';
import '../../shearwater/ble/ble_io_impl.dart';
import '../../shearwater/ble/mock_ble_transport.dart';
import '../../shearwater/ble/shearwater_ble_transport.dart';
import '../../shearwater/ble/shearwater_link.dart';
import '../../sync/cloud/usage_tracker.dart';
import '../util/fit_picker.dart' show deletePickedCopies;

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


/// Makes the FIT source for an import. The default is [FitFileSource]; tests
/// pass a stand-in.
typedef FitSourceFactory = FitDownloadSource Function({
  required List<FitInput> inputs,
  required Directory workDir,
  required void Function(FitScanCounts) onProgress,
});

FitDownloadSource _defaultFitSource({
  required List<FitInput> inputs,
  required Directory workDir,
  required void Function(FitScanCounts) onProgress,
}) =>
    FitFileSource(inputs: inputs, workDir: workDir, onProgress: onProgress);

/// The app's cache and temporary folders: the only places a picker's copies
/// of picked files may be deleted from. Desktop has none: file_picker copies
/// files only on Android and iOS, and a file picked from /tmp or %TEMP% is the
/// user's own. [desktop] is a test seam.
Future<List<Directory>> defaultFitCopyRoots({bool? desktop}) async {
  if (desktop ?? (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    return const [];
  }
  final roots = <Directory>[];
  try {
    roots.add(await getTemporaryDirectory());
  } catch (_) {}
  try {
    roots.add(await getApplicationCacheDirectory());
  } catch (_) {}
  return roots;
}

/// "1 dive" or "N dives".
String diveCountLabel(int n) => n == 1 ? '1 dive' : '$n dives';

/// The line naming the dives the computer would not send, lowest number
/// first and at most ten of them: "Skipped dive #1: the dive computer would
/// not send it." or "Skipped 3 dives the dive computer would not send: #1,
/// #4, #9."
String refusedDivesLabel(List<int> diveNumbers) {
  final sorted = [...diveNumbers]..sort();
  if (sorted.length == 1) {
    return 'Skipped dive #${sorted.single}: the dive computer would not '
        'send it.';
  }
  const shown = 10;
  final names = [for (final n in sorted.take(shown)) '#$n'].join(', ');
  final more =
      sorted.length > shown ? ' and ${sorted.length - shown} more' : '';
  return 'Skipped ${sorted.length} dives the dive computer would not send: '
      '$names$more.';
}

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
  int _downloadGeneration = 0;
  bool _cancelRequested = false;
  final LibdcOpener? _libdcOpener;
  final LibdcStarter? _libdcStarter;
  final FitSourceFactory _fitSourceFactory;
  final Future<Directory> Function() _tempDir;
  final Future<List<Directory>> Function() _pickedCopyRoots;
  List<FitInput> _fitPicked = const [];

  // The FIT file import in progress or just finished.
  bool _fit = false;

  // The wakelock the FIT scan holds; the download holds its own.
  bool _fitWakelock = false;
  FitScanCounts? _fitCounts;
  bool _fitListed = false;
  final Map<String, String> _untested = {};
  ({String diveId, String vendor, String? product})? _fitShareDive;

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
  final List<int> _refusedDiveNumbers = [];
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

  // Whether the scan has ended (its 15 s ran out, or it could not start), so
  // the screen can offer "Scan again".
  bool _scanEnded = false;
  bool _matchFailureLogged = false;

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
    FitSourceFactory? fitSourceFactory,
    Future<Directory> Function()? tempDir,
    Future<List<Directory>> Function()? pickedCopyRoots,
  })  : _pickedCopyRoots = pickedCopyRoots ?? defaultFitCopyRoots,
        _fitSourceFactory = fitSourceFactory ?? _defaultFitSource,
        _tempDir = tempDir ?? getTemporaryDirectory,
        _libdcOpener = libdcOpener,
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

  /// Dive numbers of the current download that the computer would not send
  /// (#261), in download order. Not counted in [failedCount]: nothing came
  /// down to fail, and another download asks for them again only when it
  /// re-imports all dives.
  List<int> get refusedDiveNumbers => List.unmodifiable(_refusedDiveNumbers);

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

  /// Whether the import in progress (or just finished) reads FIT files.
  bool get isFitImport => _fit;

  /// True while the FIT files are being read, before the dives are listed.
  bool get isFitReading =>
      _fit && _state == ImportFlowState.readingManifest && !_fitListed;

  /// How far the FIT scan has come; null outside a FIT import.
  FitScanCounts? get fitCounts => _fitCounts;

  /// The models of the dives imported from FIT files that Anchorline has not
  /// checked against a real recording ([kCheckedFitModels]).
  List<String> get untestedModels => List.unmodifiable(_untested.values);

  /// An imported dive of an untested model, for "Send us one of these
  /// dives". Null when there is none.
  ({String diveId, String vendor, String? product})? get fitShareDive =>
      _fitShareDive;

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
    _scanEnded = false;
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

  /// Scans again, keeping the one-scan guarantee: the running scan (if any)
  /// is stopped first.
  void scanAgain() {
    _stopScan();
    startScan();
  }

  /// True once the scan has stopped (after 15 s, or because it could not
  /// start) without the diver having picked a device.
  bool get scanEnded => _scanEnded;

  void _endScan(int generation) {
    if (_disposed || generation != _scanGeneration) return;
    _scanEnded = true;
    notifyListeners();
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
      _endScan(generation);
      return;
    }
    final adapter =
        await waitForAdapterOn(central, const Duration(seconds: 15));
    // A reset, a new scan or a selection during the wait ends this one;
    // exactly one scan may run (the same central connects afterwards).
    if (_disposed || generation != _scanGeneration) return;
    if (adapter != BleAdapterState.on) {
      debugPrint('BLE adapter never reached on state: $adapter');
      _endScan(generation);
      return;
    }

    // One scan, no service filter: Shearwater computers are told apart by
    // their service UUID, the others by their advertised name.
    try {
      unawaited(_scanSubscription?.cancel());
      _scanSubscription = central
          .scan(timeout: const Duration(seconds: 15))
          .listen(_onScanResult,
              onError: (Object e) {
                debugPrint('BLE scan error: $e');
                _endScan(generation);
              },
              onDone: () => _endScan(generation));
    } catch (e) {
      debugPrint('BLE scan error: $e');
      _endScan(generation);
    }
  }

  void _onScanResult(BleScanResult r) {
    if (_disposed) return;
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final ImportScanResult? result;
    if (r.advertises(shearwaterServiceUuid)) {
      // Shearwater stays unlisted on Windows, as before: its transport is
      // flutter_blue_plus, which has no Windows support. An entry listed
      // from an earlier report without the UUID goes too, or the picker
      // would offer the Petrel for another brand's model.
      if (isWindows) {
        if (_discoveredDevices.any((d) => d.id == r.id)) {
          _discoveredDevices.removeWhere((d) => d.id == r.id);
          notifyListeners();
        }
        return;
      }
      result = ImportScanResult(
              id: r.id, name: r.name, kind: ImportDeviceKind.shearwater);
    } else if (r.name.isEmpty) {
      result = null;
    } else {
      // matchBle walks libdivecomputer's descriptors over FFI; one name is
      // advertised many times.
      final candidates = _matchCache.putIfAbsent(r.name, () {
        try {
          return _matchBle(r.name);
        } catch (e) {
          // The native library may have failed to load; treat the name as
          // unrecognised rather than throwing in every advertisement.
          if (!_matchFailureLogged) {
            _matchFailureLogged = true;
            debugPrint('libdivecomputer name matching failed: $e');
          }
          return const <LibdcDescriptor>[];
        }
      });
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
    // A second tap while connecting or downloading must not start a second
    // connection.
    if (_state == ImportFlowState.connecting ||
        _state == ImportFlowState.downloading) {
      return;
    }
    _stopScan();
    _libdc = true;
    _libdcVendor = d.vendor;
    _recordingText = null;
    _gattSummary = const [];
    _cancelRequested = false;
    // Leave the scanning state before the first await.
    _state = ImportFlowState.connecting;
    notifyListeners();
    await _enableWakelock();

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
      // A BleException carries a short English description meant for the
      // user (see ble_central.dart). Any other error could hold anything, so
      // it gets a generic text and never the raw error.
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
  ///
  /// The download then ends in the error state with "Download stopped
  /// (cancelled). N dives saved.", and counts as failed in the telemetry.
  void cancelDownload() {
    final s = _source;
    if (s is! LibdcDownloadSource) return;
    _cancelRequested = true;
    s.cancel();
  }

  String _libdcStoppedMessage(String reason) =>
      'Download stopped ($reason). ${diveCountLabel(_downloadedCount)} saved.';

  /// For the log line of a dive that failed to import; libdivecomputer
  /// downloads have no listing to name it by.
  String _diveLabel(DiveListing? listing) => listing != null
      ? '${listing.diveNumber}'
      : 'number ${_downloadedCount + _failedCount + 1} of this download';

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

  // ── FIT files ──────────────────────────────────────────────────────────────

  /// Reads [inputs] (FIT files, Garmin exports, folders), lists the dives in
  /// them and marks the ones the diver already has. Goes to
  /// [ImportFlowState.readingManifest] straight away; [fitCounts] updates
  /// while the files are read, and [newDives] holds the marked listings when
  /// it returns. The diver then picks dives and [downloadAll] imports them.
  ///
  /// Never throws; a failure ends in [ImportFlowState.error]. Nothing is
  /// saved under the source's import state key: a file import has no
  /// fingerprint to keep.
  Future<void> importFitFiles(List<FitInput> inputs) async {
    if (_state == ImportFlowState.connecting ||
        _state == ImportFlowState.downloading ||
        isFitReading) {
      return;
    }
    _reset();
    _fit = true;
    _fitPicked = inputs;
    _fitCounts = FitScanCounts();
    _fitListed = false;
    _state = ImportFlowState.readingManifest;
    final generation = _downloadGeneration;
    notifyListeners();
    _fitWakelock = true;
    unawaited(_enableWakelock());

    FitDownloadSource? source;
    try {
      final temp = await _tempDir();
      // Cancelled or reset while the folder was looked up: no source yet, so
      // nothing may be assigned or scanned.
      if (_disposed || generation != _downloadGeneration) return;
      // A random name: another user of the temp folder cannot guess it.
      final workDir = await temp.createTemp('fit-import-');
      if (_disposed || generation != _downloadGeneration) {
        try {
          await workDir.delete(recursive: true);
        } catch (_) {}
        return;
      }
      source = _fitSourceFactory(
        inputs: inputs,
        workDir: workDir,
        onProgress: (c) {
          if (_disposed || generation != _downloadGeneration) return;
          _fitCounts = c;
          _notifyThrottled();
        },
      );
      _source = source;
      final listed = await source.listDives();
      if (_disposed || generation != _downloadGeneration) {
        // Reset or cancelled meanwhile: the reset closed the source.
        await source.close();
        return;
      }
      final marked = await markFitListings(_dao, source, listed);
      if (_disposed || generation != _downloadGeneration) {
        await source.close();
        return;
      }
      _newDives = marked;
      _totalToDownload = marked.where((l) => l.preselected).length;
      _fitListed = true;
    } catch (e, st) {
      if (_disposed || generation != _downloadGeneration) return;
      _errorMessage = 'Could not read these files.';
      _state = ImportFlowState.error;
      _report(e, st, 'download');
      _trackFitFailure(_errorMessage!);
      _source = null;
      unawaited(source?.close());
      unawaited(_releaseFitPicked(inputs));
    } finally {
      // The scan is over: let the screen sleep again, unless a reset or a
      // newer import took over (the reset let go of this one's lock itself).
      if (_fitWakelock && generation == _downloadGeneration) {
        _fitWakelock = false;
        await _disableWakelock();
      }
    }
    _flushNotify();
  }

  /// Ends in the error state with [message] after the files could not even be
  /// picked (the copy into the cache failed, say).
  void failFitPick(String message) {
    _reset();
    _fit = true;
    _errorMessage = message;
    _state = ImportFlowState.error;
    _trackFitFailure(message);
    notifyListeners();
  }

  void _trackFitFailure(String reason) {
    // The vendor is not known before a dive is read.
    _usageTracker?.track('import_failed', {
      'dives': 0,
      'total': 0,
      'engine': 'fit',
      'reason': reason,
      'mock': useMock,
    });
  }

  /// Deletes the picker's cache copies of the files this import was given
  /// (never a picked folder, never anything outside the app's cache).
  ///
  /// [picked] is the list of the import being finished, never read from
  /// [_fitPicked] after an await: a newer import's copies must stay.
  Future<void> _releaseFitPicked(List<FitInput> picked) async {
    if (identical(_fitPicked, picked)) _fitPicked = const [];
    if (picked.isEmpty) return;
    try {
      await deletePickedCopies(picked, await _pickedCopyRoots());
    } catch (_) {}
  }

  /// Reads the stored raw blob of a dive, for sharing it.
  Future<Uint8List?> rawBlobOf(String diveId) => _dao.getRawBlob(diveId);

  /// Stops reading the files and goes back to idle, closing the source.
  void cancelFitImport() => reset();

  // ── Download ───────────────────────────────────────────────────────────────

  /// Download and persist all queued dives.
  ///
  /// Each dive is parsed and committed atomically. Failures on individual
  /// dives are counted in [failedCount] and do not abort the stream. Dives
  /// the computer refuses to send are listed in [refusedDiveNumbers].
  ///
  /// Shearwater: on completion (success or connection error), the newest
  /// successfully imported fingerprint is saved via [ImportStateDao] for
  /// incremental sync on the next import session.
  ///
  /// libdivecomputer: nothing is saved per dive. At the end of the download
  /// ([DiveSourceFinished]) the newest dive's fingerprint is saved, and only
  /// when the download finished cleanly and no dive failed.
  ///
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
    _refusedDiveNumbers.clear();
    _currentDiveIndex = null;
    _totalDives = toDownload.length;
    _diveBytes = null;
    _diveTotalBytes = null;
    _currentEntry = null;
    notifyListeners();

    // What the rest of this method needs is captured now: a Retry during the
    // up-to-3 s close below resets the notifier under us.
    final libdc = _libdc;
    final fit = _fit;
    final fitPicked = _fitPicked;
    final source = _source!;
    if (fit) unawaited(_enableWakelock());
    // Neither engine saves a fingerprint per dive: libdivecomputer does at its
    // end, FIT files never do.
    final perDiveFingerprints = !libdc && !fit;
    DcIdentity? fitIdentity;
    final untested = <String, String>{};
    ({String diveId, String vendor, String? product})? shareDive;
    final generation = ++_downloadGeneration;

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
      await for (final event in source.download(selection: toDownload)) {
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
            fitIdentity = id;
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
                  if (perDiveFingerprints) {
                    lastSuccessfulFingerprint = event.fingerprint;
                  }
                  // A refresh may have stored the blob under a Subsurface
                  // copy's id, which the outcome does not name: the model
                  // counts as untested, but the dive is no share candidate.
                  _noteFitDive(fitIdentity, event, untested, null);
                case ImportOutcome.inserted:
                case ImportOutcome.insertedFlagged:
                  _downloadedCount++;
                  if (perDiveFingerprints) {
                    lastSuccessfulFingerprint = event.fingerprint;
                  }
                  _noteFitDive(
                      fitIdentity, event, untested, (v) => shareDive ??= v);
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
              debugPrint('Failed to import dive ${_diveLabel(event.listing)}');
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
            debugPrint('Failed to import dive ${_diveLabel(event.listing)}');
            _failedCount++;
            _report(event.error, event.stack, 'download');
            await _applyScrubberEvents(serial);
            _flushNotify();

          case DiveSourceDiveRefused():
            // The computer would not send this dive; the download goes on
            // with the next one. Not reported as a problem: no data came
            // down, so there is nothing of ours that failed.
            _currentDiveNumber = event.listing.diveNumber;
            _refusedDiveNumbers.add(event.listing.diveNumber);
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
      _errorMessage = fit
          ? 'Import stopped. $_downloadedCount of $_totalToDownload dives imported.'
          : libdc
          ? _libdcStoppedMessage(_cancelRequested
              ? 'cancelled'
              : e is LibdcDownloadFailed
                  ? libdcStopReason(e.status)
                  : 'unexpected error')
          : 'Connection lost. $_downloadedCount of $_totalToDownload dives downloaded.';
      _state = ImportFlowState.error;
    }
    // A cancelled download ends quietly, but it is not a completed import:
    // the diver sees why it stopped and the telemetry counts it as failed.
    if (libdc && _cancelRequested && _state != ImportFlowState.error) {
      _errorMessage = _libdcStoppedMessage('cancelled');
      _state = ImportFlowState.error;
    }

    final engine = fit ? 'fit' : (libdc ? 'libdc' : 'shearwater');
    final vendor = _identity?.vendor ?? _libdcVendor;
    final identity = _identity;

    // Release the link. The source caps the wait (see its close()).
    await source.close();
    if (fit) await _releaseFitPicked(fitPicked);

    // Save fingerprint for incremental sync, from what was captured above, so
    // that a reset or dispose during the close does not skip it.
    // libdivecomputer saves its own at DiveSourceFinished, and only after a
    // download without failures.
    if (perDiveFingerprints && lastSuccessfulFingerprint != null) {
      await _importStateDao.saveLastFingerprint(
        identity!.importStateKey,
        lastSuccessfulFingerprint,
      );
    }

    // A Retry or a new import during that wait owns the notifier now.
    if (generation != _downloadGeneration || _disposed) {
      // Release the wakelock only when no new connection holds it.
      if (_state == ImportFlowState.idle ||
          _state == ImportFlowState.scanning ||
          _state == ImportFlowState.done ||
          _state == ImportFlowState.error) {
        await _disableWakelock();
      }
      return;
    }

    if (fit) {
      _untested
        ..clear()
        ..addAll(untested);
      _fitShareDive = shareDive;
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
        'refused': _refusedDiveNumbers.length,
        'mock': useMock,
        'engine': engine,
        'vendor': vendor,
      });
    } else if (_state == ImportFlowState.error) {
      _usageTracker?.track('import_failed', {
        'dives': _downloadedCount,
        'total': _totalToDownload,
        'refused': _refusedDiveNumbers.length,
        'engine': engine,
        'vendor': vendor,
        // Truncate to keep telemetry rows small and avoid leaking
        // long-string user context in the rare case the error string
        // includes them.
        'reason': (_errorMessage ?? '').length > 200
            ? (_errorMessage ?? '').substring(0, 200)
            : (_errorMessage ?? ''),
        'mock': useMock,
      });
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

  /// Remembers the model of an imported FIT dive when it is not a checked
  /// one, and one dive of it to share.
  void _noteFitDive(
    DcIdentity? id,
    DiveSourceDive event,
    Map<String, String> untested,
    void Function(({String diveId, String vendor, String? product}))? share,
  ) {
    if (!_fit || id == null) return;
    if (isCheckedFitModel(id.product ?? id.modelLabel)) return;
    untested.putIfAbsent(id.modelLabel, () => id.modelLabel);
    share?.call((
      diveId: event.converted.dive.id,
      vendor: id.vendor,
      product: id.product,
    ));
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
    if (_fit) unawaited(_releaseFitPicked(_fitPicked));
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
    // A FIT import holds a work folder: let go of it.
    if (_fit) {
      unawaited(_source?.close());
      unawaited(_releaseFitPicked(_fitPicked));
    }
    if (_fitWakelock) {
      _fitWakelock = false;
      unawaited(_disableWakelock());
    }
    _fit = false;
    _fitCounts = null;
    _fitListed = false;
    _untested.clear();
    _fitShareDive = null;
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
    _refusedDiveNumbers.clear();
    _mockDeviceAvailable = false;
    _discoveredDevices.clear();
    _forceFullReimport = false;
    _downloadGeneration++;
    _cancelRequested = false;
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
