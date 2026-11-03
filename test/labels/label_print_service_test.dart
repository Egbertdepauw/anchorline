import 'dart:async';

import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/label_printer/label_printer.dart';
import 'package:ccrlogger/labels/cylinder_label.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/fake_label_printer.dart';

final _when = DateTime(2026, 10, 31, 18, 5);

/// An EAN32 with no desired mix: 1.6 gives a 40 m MOD, 1.4 a 33 m one.
GasAnalysis _analysis() => GasAnalysis(
      id: 'a1',
      analysedAt: _when,
      o2Percent: 32,
      hePercent: 0,
      stable: true,
    );

/// A [LabelPrintService] wired to a [FakeLabelPrinter], with the settings
/// the service reads as plain fields a test can flip between calls.
class _Rig {
  _Rig({
    FakeLabelPrinter? printer,
    this.printerId = 'printer-1',
    this.use14 = false,
    Duration connectTimeout = const Duration(seconds: 15),
    DateTime? now,
  })  : printer = printer ?? FakeLabelPrinter(),
        scanner = FakeLabelPrinterScanner() {
    service = LabelPrintService(
      render: (label) async {
        rendered.add(label);
        return bitmap;
      },
      printerFor: (id) {
        requestedIds.add(id);
        return this.printer;
      },
      scanner: scanner,
      printerId: () => printerId,
      use14ForDeeperMixes: () => use14,
      connectTimeout: connectTimeout,
      now: () => now ?? _when,
    );
  }

  final FakeLabelPrinter printer;
  final FakeLabelPrinterScanner scanner;
  final bitmap = LabelBitmap.blank(384, 240);
  final rendered = <CylinderLabel>[];
  final requestedIds = <String>[];
  String? printerId;
  bool use14;
  late final LabelPrintService service;
}

/// A matcher for a [LabelPrinterException] with [message].
Matcher _printerError(String message) => isA<LabelPrinterException>()
    .having((e) => e.message, 'message', message);

/// A printer whose disconnect fails, like a link that drops mid-teardown.
class _DisconnectFails extends FakeLabelPrinter {
  @override
  Future<void> disconnect() async {
    await super.disconnect();
    throw StateError('disconnect failed');
  }
}

/// A [FakeLabelPrinter] that writes each step to a [log] shared with other
/// printers, so a test sees the order of two jobs' steps.
class _LoggingPrinter extends FakeLabelPrinter {
  _LoggingPrinter(this.name, this.log, {super.failOnConnect, super.printGate});

  final String name;
  final List<String> log;

  @override
  Future<void> connect() {
    log.add('$name connect');
    return super.connect();
  }

  @override
  Future<List<PrinterFault>> printLabel(
    LabelBitmap bitmap, {
    int copies = 1,
  }) {
    log.add('$name print');
    return super.printLabel(bitmap, copies: copies);
  }

  @override
  Future<void> disconnect() {
    log.add('$name disconnect');
    return super.disconnect();
  }
}

/// A service whose jobs take the next printer in [printers] each, as the
/// app's does (a new `PhomemoBlePrinter` per job). [render] defaults to a
/// blank bitmap.
LabelPrintService _serviceOn(
  List<FakeLabelPrinter> printers, {
  LabelRenderer? render,
  Duration connectTimeout = const Duration(seconds: 15),
}) {
  var next = 0;
  return LabelPrintService(
    render: render ?? (_) async => LabelBitmap.blank(384, 240),
    printerFor: (_) => printers[next++],
    scanner: FakeLabelPrinterScanner(),
    printerId: () => 'printer-1',
    use14ForDeeperMixes: () => false,
    connectTimeout: connectTimeout,
  );
}

void main() {
  group('isConfigured', () {
    test('follows printerId()', () {
      final rig = _Rig(printerId: null);
      expect(rig.service.isConfigured, isFalse);
      rig.printerId = 'printer-1';
      expect(rig.service.isConfigured, isTrue);
      rig.printerId = null;
      expect(rig.service.isConfigured, isFalse);
    });
  });

  test('exposes the scanner it was given', () {
    final rig = _Rig();
    expect(identical(rig.service.scanner, rig.scanner), isTrue);
  });

  // The printer's own connect can take 10 s for the Bluetooth adapter plus
  // 10 s for the link, then service discovery. A shorter wait here would
  // cut it off and hide its more specific error.
  test('waits 25 s for a connect by default', () {
    final service = LabelPrintService(
      render: (_) async => LabelBitmap.blank(384, 240),
      printerFor: (_) => FakeLabelPrinter(),
      scanner: FakeLabelPrinterScanner(),
      printerId: () => 'printer-1',
      use14ForDeeperMixes: () => false,
    );
    expect(service.connectTimeout, const Duration(seconds: 25));
  });

  // flutter_blue_plus keeps one link per remote id, so two jobs for the
  // same printer share it: one job's disconnect would cut the other
  // mid-print, and their writes would interleave.
  group('one job at a time', () {
    test('a second job connects only after the first has disconnected',
        () async {
      final log = <String>[];
      final gate = Completer<void>();
      final service = _serviceOn([
        _LoggingPrinter('A', log, printGate: gate),
        _LoggingPrinter('B', log),
      ]);

      final first = service.printAnalysis(_analysis());
      final second = service.printAnalysis(_analysis(), copies: 2);
      await pumpEventQueue();
      // A is held mid-print; B hasn't touched the link.
      expect(log, ['A connect', 'A print']);

      gate.complete();
      expect(await first, isEmpty);
      expect(await second, isEmpty);
      expect(log, [
        'A connect', 'A print', 'A disconnect', //
        'B connect', 'B print', 'B disconnect',
      ]);
    });

    test('a test print waits for an analysis print, and the other way round',
        () async {
      final log = <String>[];
      final gateA = Completer<void>();
      final gateB = Completer<void>();
      final service = _serviceOn([
        _LoggingPrinter('A', log, printGate: gateA),
        _LoggingPrinter('B', log, printGate: gateB),
        _LoggingPrinter('C', log),
      ]);

      final analysis1 = service.printAnalysis(_analysis());
      final testPrint = service.printTestLabel();
      final analysis2 = service.printAnalysis(_analysis());
      await pumpEventQueue();
      expect(log, ['A connect', 'A print']);

      gateA.complete();
      await analysis1;
      await pumpEventQueue();
      expect(log, ['A connect', 'A print', 'A disconnect', 'B connect',
          'B print']);

      gateB.complete();
      await testPrint;
      await analysis2;
      expect(log, [
        'A connect', 'A print', 'A disconnect', //
        'B connect', 'B print', 'B disconnect',
        'C connect', 'C print', 'C disconnect',
      ]);
    });

    test('a failing job does not fail the next one', () async {
      final log = <String>[];
      final service = _serviceOn([
        _LoggingPrinter('A', log, failOnConnect: StateError('raw platform')),
        _LoggingPrinter('B', log),
      ]);

      final first = service.printAnalysis(_analysis());
      final second = service.printAnalysis(_analysis());
      await expectLater(first, throwsA(_printerError('Printer not found')));
      expect(await second, isEmpty);
      expect(log, [
        'A connect', 'A disconnect', //
        'B connect', 'B print', 'B disconnect',
      ]);
    });

    test('a render error does not fail the next job', () async {
      var renders = 0;
      final printer = FakeLabelPrinter();
      final service = _serviceOn(
        [printer],
        render: (_) async {
          if (++renders == 1) throw StateError('render bug');
          return LabelBitmap.blank(384, 240);
        },
      );

      final first = service.printAnalysis(_analysis());
      final second = service.printTestLabel();
      await expectLater(first, throwsA(isA<StateError>()));
      expect(await second, isEmpty);
      expect(printer.printed, hasLength(1));
    });

    test('a queued job\'s connect timeout starts when it reaches the front',
        () async {
      final gate = Completer<void>();
      final waiting = FakeLabelPrinter();
      final service = _serviceOn(
        [FakeLabelPrinter(printGate: gate), waiting],
        connectTimeout: const Duration(milliseconds: 100),
      );

      final first = service.printAnalysis(_analysis());
      final second = service.printAnalysis(_analysis());
      // The first job holds the printer for longer than the timeout.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(waiting.connects, 0);

      gate.complete();
      expect(await first, isEmpty);
      expect(await second, isEmpty);
      expect(waiting.connects, 1);
      expect(waiting.printed, hasLength(1));
    });
  });

  group('printAnalysis', () {
    test('connects, prints once with the copies, and disconnects', () async {
      final rig = _Rig();
      final warnings = await rig.service.printAnalysis(_analysis(), copies: 3);
      expect(warnings, isEmpty);
      expect(rig.requestedIds, ['printer-1']);
      expect(rig.printer.connects, 1);
      expect(rig.printer.printed, hasLength(1));
      expect(identical(rig.printer.printed.single.$1, rig.bitmap), isTrue);
      expect(rig.printer.printed.single.$2, 3);
      expect(rig.printer.disconnects, 1);
    });

    test('renders the label for the analysis', () async {
      final rig = _Rig();
      await rig.service.printAnalysis(_analysis());
      expect(rig.rendered, hasLength(1));
      expect(rig.rendered.single.mixName, 'EAN32');
      expect(rig.rendered.single.headlineText, '40');
    });

    test('sends 1 copy by default', () async {
      final rig = _Rig();
      await rig.service.printAnalysis(_analysis());
      expect(rig.printer.printed.single.$2, 1);
    });

    test('clamps copies to 1..9', () async {
      final rig = _Rig();
      await rig.service.printAnalysis(_analysis(), copies: 12);
      await rig.service.printAnalysis(_analysis(), copies: 0);
      await rig.service.printAnalysis(_analysis(), copies: -2);
      await rig.service.printAnalysis(_analysis(), copies: 9);
      expect(rig.printer.printed.map((p) => p.$2), [9, 1, 1, 9]);
    });

    test('throws "No label printer set up" without touching the printer',
        () async {
      final rig = _Rig(printerId: null);
      await expectLater(
        rig.service.printAnalysis(_analysis()),
        throwsA(_printerError('No label printer set up')),
      );
      expect(rig.requestedIds, isEmpty);
      expect(rig.rendered, isEmpty);
      expect(rig.printer.connects, 0);
      expect(rig.printer.disconnects, 0);
    });

    test('a connect failure is "Printer not found", and still disconnects',
        () async {
      final rig = _Rig(
        printer: FakeLabelPrinter(failOnConnect: StateError('raw platform')),
      );
      await expectLater(
        rig.service.printAnalysis(_analysis()),
        throwsA(_printerError('Printer not found')),
      );
      expect(rig.printer.printed, isEmpty);
      expect(rig.printer.disconnects, 1);
    });

    test('a LabelPrinterException from connect passes through unchanged',
        () async {
      final rig = _Rig(
        printer: FakeLabelPrinter(
          failOnConnect: const LabelPrinterException('Bluetooth is off'),
        ),
      );
      await expectLater(
        rig.service.printAnalysis(_analysis()),
        throwsA(_printerError('Bluetooth is off')),
      );
      expect(rig.printer.disconnects, 1);
    });

    // Review Focus 1: a printer that is off or out of range never answers
    // connect(). The wait must end, with a message, instead of hanging.
    test('a connect that never completes ends as "Printer not found"',
        () async {
      final rig = _Rig(
        printer: FakeLabelPrinter(hangOnConnect: true),
        connectTimeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        rig.service.printAnalysis(_analysis()),
        throwsA(_printerError('Printer not found')),
      );
      expect(rig.printer.connects, 1);
      expect(rig.printer.printed, isEmpty);
      expect(rig.printer.disconnects, 1);
    });

    test('a fatal fault surfaces with the fault, and disconnects', () async {
      final rig = _Rig(
        printer: FakeLabelPrinter(faultOnPrint: PrinterFault.noLabels),
      );
      await expectLater(
        rig.service.printAnalysis(_analysis()),
        throwsA(
          isA<LabelPrinterException>()
              .having((e) => e.fault, 'fault', PrinterFault.noLabels)
              .having(
                (e) => e.message,
                'message',
                'Out of labels, or the cover is open',
              ),
        ),
      );
      expect(rig.printer.printed, hasLength(1));
      expect(rig.printer.disconnects, 1);
    });

    test('returns the printer warnings and still completes', () async {
      final rig = _Rig(
        printer: FakeLabelPrinter(warnings: [PrinterFault.lowBattery]),
      );
      final warnings = await rig.service.printAnalysis(_analysis());
      expect(warnings, [PrinterFault.lowBattery]);
      expect(rig.printer.printed, hasLength(1));
      expect(rig.printer.disconnects, 1);
    });

    test('a render error never connects', () async {
      final printer = FakeLabelPrinter();
      final service = LabelPrintService(
        render: (_) async => throw StateError('render failed'),
        printerFor: (_) => printer,
        scanner: FakeLabelPrinterScanner(),
        printerId: () => 'printer-1',
        use14ForDeeperMixes: () => false,
      );
      await expectLater(
        service.printAnalysis(_analysis()),
        throwsA(isA<StateError>()),
      );
      expect(printer.connects, 0);
      expect(printer.disconnects, 0);
    });

    test('a failing disconnect does not turn a good print into an error',
        () async {
      final rig = _Rig(printer: _DisconnectFails());
      final warnings = await rig.service.printAnalysis(_analysis());
      expect(warnings, isEmpty);
      expect(rig.printer.printed, hasLength(1));
      expect(rig.printer.disconnects, 1);
    });

    test('a failing disconnect does not hide the print error', () async {
      final printer = _DisconnectFailsAfterFault();
      final rig = _Rig(printer: printer);
      await expectLater(
        rig.service.printAnalysis(_analysis()),
        throwsA(
          isA<LabelPrinterException>()
              .having((e) => e.fault, 'fault', PrinterFault.coverOpen),
        ),
      );
      expect(printer.disconnects, 1);
    });
  });

  group('labelFor', () {
    test('reads use14ForDeeperMixes at call time', () {
      final rig = _Rig();
      expect(rig.service.labelFor(_analysis()).headlineCaption, 'MOD 1.6');
      // A reprint after the setting changed uses the current setting.
      rig.use14 = true;
      final label = rig.service.labelFor(_analysis());
      expect(label.headlineCaption, 'MOD 1.4');
      expect(label.headlineText, '33');
      rig.use14 = false;
      expect(rig.service.labelFor(_analysis()).headlineCaption, 'MOD 1.6');
    });
  });

  group('printTestLabel', () {
    test('renders the test label dated from now()', () async {
      final rig = _Rig(now: DateTime(2027, 1, 5, 9));
      final warnings = await rig.service.printTestLabel();
      expect(warnings, isEmpty);
      expect(rig.rendered, hasLength(1));
      expect(rig.rendered.single.mixName, 'Tx21/35');
      expect(rig.rendered.single.footerRight, '5 Jan 27');
      expect(rig.printer.connects, 1);
      expect(rig.printer.printed.single.$2, 1);
      expect(rig.printer.disconnects, 1);
    });

    test('follows the current use14ForDeeperMixes setting', () async {
      final rig = _Rig(use14: true);
      await rig.service.printTestLabel();
      expect(rig.rendered.single.headlineCaption, 'MOD 1.4');
    });

    test('returns the printer warnings', () async {
      final rig = _Rig(
        printer: FakeLabelPrinter(warnings: [PrinterFault.lowBattery]),
      );
      expect(await rig.service.printTestLabel(), [PrinterFault.lowBattery]);
    });

    test('throws "No label printer set up" when none is set', () async {
      final rig = _Rig(printerId: null);
      await expectLater(
        rig.service.printTestLabel(),
        throwsA(_printerError('No label printer set up')),
      );
      expect(rig.printer.connects, 0);
    });
  });

  group('FakeLabelPrinterScanner', () {
    test('emits its printers', () async {
      const found = [FoundLabelPrinter(id: 'a', name: 'M110')];
      final scanner = FakeLabelPrinterScanner(printers: found);
      final lists = await scanner.scan().toList();
      expect(lists, hasLength(1));
      expect(lists.single.single.id, 'a');
    });

    test('emits nothing, then closes, when it finds nothing', () async {
      final lists = await FakeLabelPrinterScanner().scan().toList();
      expect(lists, isEmpty);
    });

    test('stays open until its gate completes', () async {
      final gate = Completer<void>();
      var closed = false;
      FakeLabelPrinterScanner(scanGate: gate)
          .scan()
          .listen((_) {}, onDone: () => closed = true);
      await pumpEventQueue();
      expect(closed, isFalse);
      gate.complete();
      await pumpEventQueue();
      expect(closed, isTrue);
    });

    test('emits the given error on the stream, like a scan failure', () async {
      final scanner = FakeLabelPrinterScanner(
        error: const LabelPrinterException('Bluetooth is off'),
      );
      await expectLater(
        scanner.scan(),
        emitsError(_printerError('Bluetooth is off')),
      );
    });
  });
}

/// A printer that reports a fatal fault and then fails to disconnect.
class _DisconnectFailsAfterFault extends _DisconnectFails {
  @override
  Future<List<PrinterFault>> printLabel(
    LabelBitmap bitmap, {
    int copies = 1,
  }) async {
    await super.printLabel(bitmap, copies: copies);
    throw const LabelPrinterException(
      'Printer cover is open',
      fault: PrinterFault.coverOpen,
    );
  }
}
