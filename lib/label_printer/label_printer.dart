/// What the UI needs from a label printer (issue #114).
///
/// Pure Dart, no Flutter imports. [LabelPrinter] and [LabelPrinterScanner]
/// are the seam between the print service and a concrete printer. Only the
/// Phomemo M110 implements them today (`phomemo/`), but nothing here is
/// Phomemo-specific, so another printer can be added later.
library;

import 'label_bitmap.dart';

/// A condition a printer reports about itself.
enum PrinterFault { noLabels, coverOpen, overheated, lowBattery }

/// The user-facing text for [f].
String printerFaultMessage(PrinterFault f) => switch (f) {
  PrinterFault.noLabels => 'Out of labels',
  PrinterFault.coverOpen => 'Printer cover is open',
  PrinterFault.overheated => 'Printer is overheated. Let it cool down.',
  PrinterFault.lowBattery => 'Printer battery is low',
};

/// Whether [f] stops a print. A low battery is only a warning: the label
/// still prints.
bool isFatalPrinterFault(PrinterFault f) => f != PrinterFault.lowBattery;

/// A print or connection failure, with a message fit to show the user.
class LabelPrinterException implements Exception {
  const LabelPrinterException(this.message, {this.fault});

  final String message;

  /// The fault behind this failure, when the printer reported one.
  final PrinterFault? fault;

  @override
  String toString() => message;
}

/// A connection to one label printer.
abstract class LabelPrinter {
  /// Faults the printer reports, as they arrive.
  Stream<PrinterFault> get faults;

  Future<void> connect();

  /// Prints [copies] of [bitmap]. Returns the non-fatal faults (warnings)
  /// seen during the job. Throws a [LabelPrinterException] carrying the
  /// fault when a fatal one stops the job.
  Future<List<PrinterFault>> printLabel(LabelBitmap bitmap, {int copies = 1});

  Future<void> disconnect();
}

/// A printer discovered by a [LabelPrinterScanner].
class FoundLabelPrinter {
  const FoundLabelPrinter({required this.id, required this.name});

  /// The transport's id for the device (a BLE remote id).
  final String id;
  final String name;
}

/// Finds printers in range.
abstract class LabelPrinterScanner {
  /// Emits the growing list of printers found until [timeout] passes or
  /// [stop] is called.
  Stream<List<FoundLabelPrinter>> scan({
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> stop();
}
