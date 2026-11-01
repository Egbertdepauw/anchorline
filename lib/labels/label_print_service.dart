/// Prints a saved gas analysis as a cylinder label (issue #114).
///
/// Pure Dart, no Flutter imports. The UI calls `printAnalysis` or
/// `printTestLabel`; the service builds the label, renders it, connects to
/// the saved printer, prints, and disconnects. The renderer, the printer and
/// the settings come in as functions, so the service is tested with fakes
/// and wired to the real ones in one place.
///
/// A print never hangs: a printer that is off, out of range, or behind a
/// Bluetooth adapter that is off never answers `connect()`, so the wait is
/// cut at [LabelPrintService.connectTimeout] and reported as "Printer not
/// found". Every failure is a [LabelPrinterException] with a message fit
/// for the user, except a render error, which is a bug and passes through.
library;

import '../data/models/gas_analysis.dart';
import '../label_printer/label_bitmap.dart';
import '../label_printer/label_printer.dart';
import 'cylinder_label.dart';

/// Draws [label] as the bitmap the printer prints.
typedef LabelRenderer = Future<LabelBitmap> Function(CylinderLabel label);

/// The printer saved under [printerId] (a [FoundLabelPrinter.id]).
typedef LabelPrinterFactory = LabelPrinter Function(String printerId);

/// The most copies one print job sends; more is clamped. The Phomemo
/// encoder clamps to the same number (`kPhomemoMaxCopies`).
const int kMaxLabelCopies = 9;

const String _kNoPrinter = 'No label printer set up';
const String _kPrinterNotFound = 'Printer not found';

class LabelPrintService {
  LabelPrintService({
    required LabelRenderer render,
    required LabelPrinterFactory printerFor,
    required this.scanner,
    required String? Function() printerId,
    required bool Function() use14ForDeeperMixes,
    this.connectTimeout = const Duration(seconds: 15),
    DateTime Function() now = DateTime.now,
  })  : _render = render,
        _printerFor = printerFor,
        _printerId = printerId,
        _use14ForDeeperMixes = use14ForDeeperMixes,
        _now = now;

  /// Finds printers in range, for the "Find printer" dialog.
  final LabelPrinterScanner scanner;

  /// How long to wait for the printer to connect.
  final Duration connectTimeout;

  final LabelRenderer _render;
  final LabelPrinterFactory _printerFor;
  final String? Function() _printerId;
  final bool Function() _use14ForDeeperMixes;
  final DateTime Function() _now;

  /// Whether a printer is saved. Says nothing about it being in range.
  bool get isConfigured => _printerId() != null;

  /// The label for [a] under the current "Use 1.4 for deeper mixes"
  /// setting, so a reprint follows a setting changed since the first print.
  CylinderLabel labelFor(GasAnalysis a) => CylinderLabel.fromAnalysis(
        a,
        use14ForDeeperMixes: _use14ForDeeperMixes(),
      );

  /// Prints [copies] (1 to [kMaxLabelCopies]) of the label for [a]. Returns
  /// the printer's warnings, such as a low battery.
  ///
  /// Throws a [LabelPrinterException] when no printer is saved, when the
  /// printer can't be reached ("Printer not found" after [connectTimeout]),
  /// or when it reports a fault that stops the job.
  Future<List<PrinterFault>> printAnalysis(GasAnalysis a, {int copies = 1}) =>
      _print(labelFor(a), copies);

  /// Prints the sample label of Settings → "Print test label", dated now.
  /// Throws and returns like [printAnalysis].
  Future<List<PrinterFault>> printTestLabel() => _print(
        CylinderLabel.testLabel(
          now: _now(),
          use14ForDeeperMixes: _use14ForDeeperMixes(),
        ),
        1,
      );

  Future<List<PrinterFault>> _print(CylinderLabel label, int copies) async {
    final id = _printerId();
    if (id == null) throw const LabelPrinterException(_kNoPrinter);

    // Render before connecting, so a render error doesn't hold the BLE link.
    final bitmap = await _render(label);

    final printer = _printerFor(id);
    try {
      await _connect(printer);
      return await printer.printLabel(
        bitmap,
        copies: copies.clamp(1, kMaxLabelCopies),
      );
    } finally {
      // Also after a failed or abandoned connect, so a link that comes up
      // late is closed. A failure to disconnect must not hide the result.
      try {
        await printer.disconnect();
      } catch (_) {}
    }
  }

  /// Connects, giving up after [connectTimeout]. Whatever goes wrong other
  /// than a [LabelPrinterException] (a timeout, or a raw platform error from
  /// the Bluetooth stack) means the printer can't be reached.
  Future<void> _connect(LabelPrinter printer) async {
    try {
      await printer.connect().timeout(connectTimeout);
    } on LabelPrinterException {
      rethrow;
    } catch (_) {
      throw const LabelPrinterException(_kPrinterNotFound);
    }
  }
}
