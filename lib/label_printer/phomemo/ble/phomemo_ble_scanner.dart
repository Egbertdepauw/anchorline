/// BLE scan for Phomemo label printers (issue #114).
///
/// A thin `flutter_blue_plus` layer, like `phomemo_ble_printer.dart`, with
/// the adapter-wait and subscribe-then-scan pattern of
/// `ImportNotifier._startRealScan`. No unit tests; checked on the hardware
/// in Task 15 of the issue #114 plan.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../label_printer.dart';
import '../phomemo_encoder.dart';
import 'phomemo_ble_printer.dart';

/// The name shown for a printer that advertises no name.
const String _kUnnamedPrinter = 'Phomemo printer';

/// Finds Phomemo printers: devices that advertise [kPhomemoServiceUuid], or
/// whose name starts with one of [kPhomemoNamePrefixes].
class PhomemoBleScanner implements LabelPrinterScanner {
  PhomemoBleScanner();

  _ScanRun? _run;

  /// Scans for [timeout] once the stream is listened to. The stream emits
  /// the printers found so far, sorted by name, each time the list changes,
  /// and closes when the scan ends. It emits a [LabelPrinterException]
  /// first when Bluetooth is off or the scan can't start. A new [scan]
  /// ends the previous one.
  @override
  Stream<List<FoundLabelPrinter>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    _run?.end();
    final run = _ScanRun(timeout);
    _run = run;
    return run.stream;
  }

  @override
  Future<void> stop() async {
    _run?.end();
    _run = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Phomemo BLE: stopScan failed: $e');
    }
  }
}

/// One [PhomemoBleScanner.scan]: its output stream and what feeds it.
class _ScanRun {
  _ScanRun(this._timeout) {
    _out = StreamController<List<FoundLabelPrinter>>(
      onListen: () => unawaited(_start()),
      onCancel: end,
    );
  }

  final Duration _timeout;
  late final StreamController<List<FoundLabelPrinter>> _out;

  /// The printers found, by remote id.
  final Map<String, FoundLabelPrinter> _found = {};

  StreamSubscription<List<ScanResult>>? _results;
  Timer? _timer;
  bool _ended = false;

  Stream<List<FoundLabelPrinter>> get stream => _out.stream;

  Future<void> _start() async {
    if (_ended) return;
    if (!await waitForBluetoothOn(kBluetoothOnTimeout)) {
      _fail(const LabelPrinterException('Bluetooth is off'));
      return;
    }
    if (_ended) return;

    // Subscribe before starting the scan so no advertisement is missed.
    // scanResults first re-emits the previous scan's list, which may hold
    // printers no longer in range: skip it. startScan then pushes an empty
    // list and the new results.
    _results = FlutterBluePlus.scanResults
        .skip(1)
        .listen(
          _onResults,
          onError: (Object e) {
            debugPrint('Phomemo BLE: scan failed: $e');
            _fail(const LabelPrinterException('Bluetooth scan failed'));
          },
        );
    // flutter_blue_plus stops the radio scan at its own timeout; this one
    // ends the stream.
    _timer = Timer(_timeout, end);
    try {
      await FlutterBluePlus.startScan(timeout: _timeout);
    } catch (e) {
      debugPrint('Phomemo BLE: startScan failed: $e');
      _fail(const LabelPrinterException('Bluetooth scan failed'));
    }
  }

  void _onResults(List<ScanResult> results) {
    if (_ended) return;
    var changed = false;
    for (final r in results) {
      if (!_isPhomemo(r)) continue;
      final id = r.device.remoteId.str;
      final name = _nameOf(r);
      final known = _found[id];
      // Keep a real name once seen, even if a later packet has none.
      if (known != null && (known.name == name || name == _kUnnamedPrinter)) {
        continue;
      }
      _found[id] = FoundLabelPrinter(id: id, name: name);
      changed = true;
    }
    if (changed) _out.add(_sorted());
  }

  List<FoundLabelPrinter> _sorted() {
    final list = _found.values.toList();
    list.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return list;
  }

  void _fail(LabelPrinterException e) {
    if (_ended) return;
    _out.addError(e);
    end();
  }

  /// Ends this run: cancels the subscription and timer and closes the
  /// stream. Leaves the radio scan alone; [PhomemoBleScanner.stop] stops
  /// it, and otherwise flutter_blue_plus stops it at the timeout.
  void end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_results?.cancel());
    _results = null;
    unawaited(_out.close());
  }
}

bool _isPhomemo(ScanResult r) {
  if (r.advertisementData.serviceUuids.contains(Guid(kPhomemoServiceUuid))) {
    return true;
  }
  return [
    r.advertisementData.advName,
    r.device.advName,
    r.device.platformName,
  ].any(_hasPhomemoPrefix);
}

bool _hasPhomemoPrefix(String name) {
  final upper = name.toUpperCase();
  return kPhomemoNamePrefixes.any((p) => upper.startsWith(p.toUpperCase()));
}

/// The advertised name, falling back to the platform's name for the device
/// and then to [_kUnnamedPrinter]. `device.advName` keeps the last name the
/// device advertised, for packets that carry none.
String _nameOf(ScanResult r) {
  for (final name in [
    r.advertisementData.advName,
    r.device.advName,
    r.device.platformName,
  ]) {
    if (name.trim().isNotEmpty) return name.trim();
  }
  return _kUnnamedPrinter;
}
