/// BLE scan for Phomemo label printers (issue #114).
///
/// A thin layer over the shared [BleCentral] seam (`lib/ble/`), like
/// `phomemo_ble_printer.dart`. The scan mechanics (adapter wait,
/// subscribe-then-scan, the growing sorted list) live in [BleDeviceScan];
/// this file only says what a Phomemo printer looks like.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../ble/ble_central.dart';
import '../../../ble/ble_central_default.dart';
import '../../../ble/ble_device_scan.dart';
import '../../label_printer.dart';
import '../phomemo_encoder.dart';
import 'phomemo_ble_printer.dart' show kBluetoothOnTimeout;

/// The name shown for a printer that advertises no name.
const String _kUnnamedPrinter = 'Phomemo printer';

/// Finds Phomemo printers: devices that advertise [kPhomemoServiceUuid], or
/// whose name starts with one of [kPhomemoNamePrefixes].
class PhomemoBleScanner implements LabelPrinterScanner {
  PhomemoBleScanner({BleCentral? central}) : _centralOverride = central;

  final BleCentral? _centralOverride;

  BleCentral get _central => _centralOverride ?? defaultBleCentral();

  BleDeviceScan? _run;

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
    final run = BleDeviceScan(
      central: _central,
      timeout: timeout,
      adapterTimeout: kBluetoothOnTimeout,
      match: phomemoNameOf,
      error: LabelPrinterException.new,
      unnamed: _kUnnamedPrinter,
      caseInsensitiveSort: true,
    );
    _run = run;
    return run.stream.map(
      (found) => [
        for (final d in found) FoundLabelPrinter(id: d.id, name: d.name),
      ],
    );
  }

  @override
  Future<void> stop() async {
    _run?.end();
    _run = null;
    await _central.stopScan();
  }
}

/// The name to list [r] under when it is a Phomemo printer, or null.
@visibleForTesting
String? phomemoNameOf(BleScanResult r) {
  final upper = r.name.toUpperCase();
  final named = kPhomemoNamePrefixes.any(
    (p) => upper.startsWith(p.toUpperCase()),
  );
  if (!named && !r.advertises(kPhomemoServiceUuid)) return null;
  return r.name.isNotEmpty ? r.name : _kUnnamedPrinter;
}
