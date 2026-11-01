import 'dart:async';

import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/label_printer/label_printer.dart';

/// A [LabelPrinter] that records what it is asked to do and fails on cue.
///
/// Shared by the print service tests and the UI tests that print.
class FakeLabelPrinter implements LabelPrinter {
  FakeLabelPrinter({
    this.failOnConnect,
    this.hangOnConnect = false,
    this.faultOnPrint,
    this.warnings = const [],
    this.printGate,
  });

  /// Thrown by [connect] when set.
  final Object? failOnConnect;

  /// [connect] never completes, like a printer that is off or out of range.
  final bool hangOnConnect;

  /// Thrown by [printLabel] as a [LabelPrinterException] carrying the fault.
  final PrinterFault? faultOnPrint;

  /// Returned by [printLabel] when it succeeds.
  final List<PrinterFault> warnings;

  /// [printLabel] waits for this before it finishes, so a test can hold a
  /// print in flight. The job is already in [printed] while it waits.
  final Completer<void>? printGate;

  int connects = 0;
  int disconnects = 0;

  /// The jobs received, in order: the bitmap and the number of copies.
  final List<(LabelBitmap, int)> printed = [];

  @override
  Stream<PrinterFault> get faults => const Stream.empty();

  @override
  Future<void> connect() async {
    connects++;
    if (hangOnConnect) return Completer<void>().future;
    final e = failOnConnect;
    if (e != null) throw e;
  }

  @override
  Future<List<PrinterFault>> printLabel(
    LabelBitmap bitmap, {
    int copies = 1,
  }) async {
    printed.add((bitmap, copies));
    await printGate?.future;
    final fault = faultOnPrint;
    if (fault != null) {
      throw LabelPrinterException(printerFaultMessage(fault), fault: fault);
    }
    return warnings;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }
}

/// A [LabelPrinterScanner] that behaves like the real one.
///
/// It emits [printers] once, and only when there are any: a scan that finds
/// nothing emits no data event, it just closes. With [error] set it emits
/// that error instead, like the real scanner does when Bluetooth is off (a
/// [LabelPrinterException]), and then closes.
///
/// The stream closes at once, as a scan does at its timeout. With [scanGate]
/// set it stays open until the gate completes, as a scan does while it runs,
/// so a test can see the "searching" state and close the dialog mid-scan.
class FakeLabelPrinterScanner implements LabelPrinterScanner {
  FakeLabelPrinterScanner({
    this.printers = const [],
    this.error,
    this.scanGate,
  });

  final List<FoundLabelPrinter> printers;
  final Object? error;

  /// The stream stays open until this completes.
  final Completer<void>? scanGate;

  /// How many times [stop] was called.
  int stops = 0;

  @override
  Stream<List<FoundLabelPrinter>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    final e = error;
    if (e != null) throw e;
    if (printers.isNotEmpty) yield printers;
    await scanGate?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}
