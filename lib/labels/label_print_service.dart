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
///
/// Jobs run one at a time, in the order they were asked for: two jobs on
/// one printer would share its Bluetooth link (see `_enqueue`).
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
    this.connectTimeout = const Duration(seconds: 25),
    DateTime Function() now = DateTime.now,
  })  : _render = render,
        _printerFor = printerFor,
        _printerId = printerId,
        _use14ForDeeperMixes = use14ForDeeperMixes,
        _now = now;

  /// Finds printers in range, for the "Find printer" dialog.
  final LabelPrinterScanner scanner;

  /// How long to wait for the printer to connect, counted from when the
  /// job reaches the front of the queue. Longer than the printer's own
  /// worst case (up to 10 s for the Bluetooth adapter, 10 s for the link,
  /// then service discovery), so its more specific errors, such as
  /// "Bluetooth is off", arrive before this cuts the wait.
  final Duration connectTimeout;

  final LabelRenderer _render;
  final LabelPrinterFactory _printerFor;
  final String? Function() _printerId;
  final bool Function() _use14ForDeeperMixes;
  final DateTime Function() _now;

  /// The end of the job queued last. The next job starts once it is over,
  /// whether it printed or failed. Never completes with an error.
  Future<void> _lastJob = Future<void>.value();

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
  /// The label is built now. The job then waits for every job asked for
  /// before it.
  ///
  /// Throws a [LabelPrinterException] when no printer is saved, when the
  /// printer can't be reached ("Printer not found" after [connectTimeout]),
  /// or when it reports a fault that stops the job.
  Future<List<PrinterFault>> printAnalysis(GasAnalysis a, {int copies = 1}) =>
      _enqueue(labelFor(a), copies);

  /// Prints the sample label of Settings → "Print test label", dated now.
  /// Queues, throws and returns like [printAnalysis].
  Future<List<PrinterFault>> printTestLabel() => _enqueue(
        CylinderLabel.testLabel(
          now: _now(),
          use14ForDeeperMixes: _use14ForDeeperMixes(),
        ),
        1,
      );

  /// Runs the job once every job queued before it has ended.
  ///
  /// `flutter_blue_plus` keeps one link per remote id, so two jobs for the
  /// same printer share it, even with a [LabelPrinter] each: one job's
  /// disconnect would cut the other mid-print, and their writes would
  /// interleave (status queries inside the other's raster). Two log entries
  /// printed back to back, a Retry followed by "Save & print", or a test
  /// print during either would all do this without the queue.
  ///
  /// Everything in the job starts only when it reaches the front, the
  /// connect timeout included.
  Future<List<PrinterFault>> _enqueue(CylinderLabel label, int copies) {
    final job = _lastJob.then((_) => _print(label, copies));
    // The next job waits for this one to end, not for it to succeed: the
    // error is for this job's caller only.
    _lastJob = job.then<void>((_) {}, onError: (Object _) {});
    return job;
  }

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
