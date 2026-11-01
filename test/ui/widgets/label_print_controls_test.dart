import 'dart:async';

import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/label_printer/label_printer.dart';
import 'package:ccrlogger/labels/cylinder_label.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:ccrlogger/ui/widgets/label_print_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/fake_label_printer.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

final _analysis = GasAnalysis(
  id: 'a1',
  analysedAt: DateTime(2026, 10, 31, 9),
  o2Percent: 32.1,
  hePercent: 0,
  stable: true,
  targetO2Percent: 32,
  targetHePercent: 0,
);

/// [_analysis] as it might be stored later: edited, or the same.
GasAnalysis _stored({
  String? analysedBy,
  int targetO2 = 32,
  GasRole gasRole = GasRole.bailout,
}) =>
    GasAnalysis(
      id: 'a1',
      analysedBy: analysedBy,
      analysedAt: DateTime(2026, 10, 31, 9),
      o2Percent: 32.1,
      hePercent: 0,
      stable: true,
      targetO2Percent: targetO2,
      targetHePercent: 0,
      gasRole: gasRole,
    );

/// A [LabelPrintService] on fakes. Each print job takes the next printer in
/// [printers], so a test can make the first attempt fail and the next work.
LabelPrintService _service(
  List<FakeLabelPrinter> printers, {
  LabelRenderer? render,
  List<CylinderLabel>? rendered,
}) {
  var next = 0;
  return LabelPrintService(
    render: render ??
        (label) async {
          rendered?.add(label);
          return LabelBitmap.blank(384, 240);
        },
    printerFor: (_) => printers[next++],
    scanner: FakeLabelPrinterScanner(),
    printerId: () => 'dev-1',
    use14ForDeeperMixes: () => false,
  );
}

/// A screen with one button that runs [onTap] with its own context.
Widget _host(Future<void> Function(BuildContext) onTap) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const ValueKey('go'),
            onPressed: () => onTap(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _printFrom(
  WidgetTester tester,
  LabelPrintService service, {
  int copies = 1,
  Future<GasAnalysis?> Function()? reload,
}) async {
  await tester.pumpWidget(
    _host(
      (context) => printWithFeedback(
        context,
        service: service,
        analysis: _analysis,
        copies: copies,
        reload: reload,
      ),
    ),
  );
  await tester.tap(_key('go'));
  await tester.pumpAndSettle();
}

/// Runs [body] with `debugPrint` captured.
Future<List<String?>> _captureDebugPrint(Future<void> Function() body) async {
  final logged = <String?>[];
  final old = debugPrint;
  debugPrint = (message, {wrapWidth}) => logged.add(message);
  try {
    await body();
  } finally {
    debugPrint = old;
  }
  return logged;
}

void main() {
  group('labelPrintedMessage', () {
    test('one label, no warnings', () {
      expect(labelPrintedMessage(1, const []), 'Label printed.');
    });

    test('several labels, no warnings', () {
      expect(labelPrintedMessage(2, const []), 'Printed 2 labels.');
      expect(labelPrintedMessage(9, const []), 'Printed 9 labels.');
    });

    test('adds each warning as a sentence', () {
      expect(
        labelPrintedMessage(1, [PrinterFault.lowBattery]),
        'Label printed. Printer battery is low.',
      );
      expect(
        labelPrintedMessage(
          3,
          [PrinterFault.lowBattery, PrinterFault.noLabels],
        ),
        'Printed 3 labels. Printer battery is low. Out of labels.',
      );
    });

    test('does not double a full stop', () {
      expect(
        labelPrintedMessage(1, [PrinterFault.overheated]),
        'Label printed. Printer is overheated. Let it cool down.',
      );
    });
  });

  group('CopiesStepper', () {
    Future<List<int>> pump(WidgetTester tester, int start) async {
      final changes = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CopiesStepper(
                  value: changes.isEmpty ? start : changes.last,
                  onChanged: (v) => setState(() => changes.add(v)),
                );
              },
            ),
          ),
        ),
      );
      return changes;
    }

    String shown(WidgetTester tester) =>
        tester.widget<Text>(_key('copies-value')).data!;

    VoidCallback? onPressed(WidgetTester tester, String key) =>
        tester.widget<IconButton>(_key(key)).onPressed;

    testWidgets('shows the value between − and +', (tester) async {
      await pump(tester, 3);

      expect(shown(tester), '3');
      expect(_key('copies-dec'), findsOneWidget);
      expect(_key('copies-inc'), findsOneWidget);
    });

    testWidgets('+ and − step by one', (tester) async {
      final changes = await pump(tester, 1);

      await tester.tap(_key('copies-inc'));
      await tester.pump();
      await tester.tap(_key('copies-inc'));
      await tester.pump();
      await tester.tap(_key('copies-dec'));
      await tester.pump();

      expect(changes, [2, 3, 2]);
      expect(shown(tester), '2');
    });

    testWidgets('stops at 1', (tester) async {
      final changes = await pump(tester, 1);

      await tester.tap(_key('copies-dec'));
      await tester.pump();

      expect(changes, isEmpty);
      expect(shown(tester), '1');
      expect(onPressed(tester, 'copies-dec'), isNull);
      expect(onPressed(tester, 'copies-inc'), isNotNull);
    });

    testWidgets('stops at 9', (tester) async {
      final changes = await pump(tester, 9);

      await tester.tap(_key('copies-inc'));
      await tester.pump();

      expect(changes, isEmpty);
      expect(shown(tester), '9');
      expect(onPressed(tester, 'copies-inc'), isNull);
      expect(onPressed(tester, 'copies-dec'), isNotNull);
    });
  });

  group('showCopiesDialog', () {
    int? result;
    var done = false;

    Future<void> open(WidgetTester tester) async {
      result = null;
      done = false;
      await tester.pumpWidget(
        _host((context) async {
          result = await showCopiesDialog(context);
          done = true;
        }),
      );
      await tester.tap(_key('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('starts at 1 and prints 1', (tester) async {
      await open(tester);
      expect(tester.widget<Text>(_key('copies-value')).data, '1');

      await tester.tap(_key('copies-dialog-print'));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(result, 1);
      expect(_key('copies-dialog-print'), findsNothing);
    });

    testWidgets('returns the chosen number', (tester) async {
      await open(tester);

      await tester.tap(_key('copies-inc'));
      await tester.pump();
      await tester.tap(_key('copies-inc'));
      await tester.pump();
      await tester.tap(_key('copies-inc'));
      await tester.pump();
      await tester.tap(_key('copies-dec'));
      await tester.pump();
      expect(tester.widget<Text>(_key('copies-value')).data, '3');

      await tester.tap(_key('copies-dialog-print'));
      await tester.pumpAndSettle();

      expect(result, 3);
    });

    testWidgets('Cancel returns null', (tester) async {
      await open(tester);
      await tester.tap(_key('copies-inc'));
      await tester.pump();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(result, isNull);
    });

    testWidgets('dismissing the dialog returns null', (tester) async {
      await open(tester);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(result, isNull);
    });
  });

  group('printWithFeedback', () {
    testWidgets('prints one label and says so', (tester) async {
      final printer = FakeLabelPrinter();
      await _printFrom(tester, _service([printer]));

      expect(printer.printed, hasLength(1));
      expect(printer.printed.single.$2, 1);
      expect(find.text('Label printed.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('prints the copies asked for and says how many',
        (tester) async {
      final printer = FakeLabelPrinter();
      await _printFrom(tester, _service([printer]), copies: 2);

      expect(printer.printed.single.$2, 2);
      expect(find.text('Printed 2 labels.'), findsOneWidget);
    });

    testWidgets('adds the printer\'s warnings to the message', (tester) async {
      final printer = FakeLabelPrinter(warnings: [PrinterFault.lowBattery]);
      await _printFrom(tester, _service([printer]));

      expect(
        find.text('Label printed. Printer battery is low.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows the failure with Retry when the printer is not found',
        (tester) async {
      final printer = FakeLabelPrinter(failOnConnect: Exception('no link'));
      await _printFrom(tester, _service([printer]));

      expect(find.text('Printer not found'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Label printed.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a fault that stops the job, with Retry',
        (tester) async {
      final printer = FakeLabelPrinter(faultOnPrint: PrinterFault.coverOpen);
      await _printFrom(tester, _service([printer]));

      expect(find.text('Printer cover is open'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Retry prints again: one failed job, then exactly one print',
        (tester) async {
      final failing = FakeLabelPrinter(failOnConnect: Exception('no link'));
      final working = FakeLabelPrinter();
      await _printFrom(tester, _service([failing, working]), copies: 2);
      expect(find.text('Retry'), findsOneWidget);
      expect(failing.printed, isEmpty);
      expect(working.connects, 0);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(failing.printed, isEmpty);
      expect(working.printed, hasLength(1));
      // Same arguments as the first call.
      expect(working.printed.single.$2, 2);
      expect(find.text('Printed 2 labels.'), findsOneWidget);
      expect(find.text('Printer not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a new print replaces a failure bar that was left up',
        (tester) async {
      final failing = FakeLabelPrinter(failOnConnect: Exception('no link'));
      final working = FakeLabelPrinter();
      await _printFrom(tester, _service([failing, working]));
      expect(find.text('Printer not found'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // The user ignores the failure and prints again.
      await tester.tap(_key('go'));
      await tester.pumpAndSettle();

      expect(working.printed, hasLength(1));
      expect(find.text('Label printed.'), findsOneWidget);
      expect(find.text('Printer not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('Retry that fails again offers Retry again', (tester) async {
      final first = FakeLabelPrinter(failOnConnect: Exception('no link'));
      final second = FakeLabelPrinter(faultOnPrint: PrinterFault.noLabels);
      final third = FakeLabelPrinter();
      await _printFrom(tester, _service([first, second, third]));

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Out of labels'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Label printed.'), findsOneWidget);
      expect(third.printed, hasLength(1));
    });

    testWidgets('an unexpected error shows "Printing failed" with Retry',
        (tester) async {
      var renders = 0;
      final service = _service(
        [FakeLabelPrinter()],
        render: (_) async {
          renders++;
          if (renders == 1) throw StateError('render bug');
          return LabelBitmap.blank(384, 240);
        },
      );

      final logged = await _captureDebugPrint(
        () => _printFrom(tester, service),
      );

      expect(find.text('Printing failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The error is not swallowed silently.
      expect(logged.join(), contains('render bug'));

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Label printed.'), findsOneWidget);
    });

    testWidgets('survives the screen going away while the printer works',
        (tester) async {
      final gate = Completer<void>();
      final printer = FakeLabelPrinter(printGate: gate);
      await tester.pumpWidget(
        _host(
          (context) => printWithFeedback(
            context,
            service: _service([printer]),
            analysis: _analysis,
            copies: 1,
          ),
        ),
      );
      await tester.tap(_key('go'));
      await tester.pump();
      await tester.pump();
      expect(printer.printed, hasLength(1));

      // The whole app goes away mid-print, then the printer finishes.
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('Retry still works after the widget that printed is gone',
        (tester) async {
      final failing = FakeLabelPrinter(failOnConnect: Exception('no link'));
      final working = FakeLabelPrinter();
      final service = _service([failing, working]);

      // The button that prints can go away (a dialog closing, a card
      // collapsing) while the SnackBar, which belongs to the Scaffold, stays.
      late StateSetter setHost;
      var showButton = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHost = setState;
                if (!showButton) return const SizedBox();
                return Builder(
                  builder: (context) => ElevatedButton(
                    key: const ValueKey('go'),
                    onPressed: () => printWithFeedback(
                      context,
                      service: service,
                      analysis: _analysis,
                      copies: 1,
                    ),
                    child: const Text('go'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(_key('go'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      setHost(() => showButton = false);
      await tester.pumpAndSettle();
      expect(_key('go'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(working.printed, hasLength(1));
      expect(find.text('Label printed.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // The failure bar outlives the screen that printed, so the diver can fix
  // the entry (or delete it) in the log before tapping its Retry. Retry
  // must then never print what the entry no longer says.
  group('printWithFeedback Retry with reload', () {
    const deleted = 'This analysis was deleted.';
    const changed = 'This analysis changed. Print it again from the log.';

    /// Prints [_analysis] on a printer that fails, then a [working] one,
    /// with [reload] as the re-read. Returns how often [reload] ran.
    Future<int Function()> failThenRetry(
      WidgetTester tester, {
      required FakeLabelPrinter working,
      required FutureOr<GasAnalysis?> Function() reload,
      List<CylinderLabel>? rendered,
      int copies = 1,
    }) async {
      var reloads = 0;
      final failing = FakeLabelPrinter(failOnConnect: Exception('no link'));
      await _printFrom(
        tester,
        _service([failing, working], rendered: rendered),
        copies: copies,
        reload: () async {
          reloads++;
          return reload();
        },
      );
      expect(find.text('Printer not found'), findsOneWidget);
      expect(reloads, 0, reason: 'the first print uses the analysis given');
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      return () => reloads;
    }

    testWidgets('prints the entry as stored now, with the same copies',
        (tester) async {
      final working = FakeLabelPrinter();
      final rendered = <CylinderLabel>[];
      final reloads = await failThenRetry(
        tester,
        working: working,
        rendered: rendered,
        copies: 2,
        // Edited since, but not the mix or role: the initials now print.
        reload: () => _stored(analysedBy: 'EdP'),
      );

      expect(reloads(), 1);
      expect(working.printed.single.$2, 2);
      expect(rendered, hasLength(2));
      expect(rendered.first.analysedBy, isNull);
      expect(rendered.last.analysedBy, 'EdP');
      expect(rendered.last.mixName, 'EAN32');
      expect(find.text('Printed 2 labels.'), findsOneWidget);
    });

    testWidgets('a deleted entry is not printed', (tester) async {
      final working = FakeLabelPrinter();
      await failThenRetry(tester, working: working, reload: () => null);

      expect(working.connects, 0);
      expect(find.text(deleted), findsOneWidget);
      expect(find.text('Printer not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('an entry whose desired mix changed is not printed',
        (tester) async {
      final working = FakeLabelPrinter();
      await failThenRetry(
        tester,
        working: working,
        reload: () => _stored(targetO2: 36),
      );

      expect(working.connects, 0);
      expect(find.text(changed), findsOneWidget);
      expect(find.text('Printer not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('an entry whose gas role changed is not printed',
        (tester) async {
      final working = FakeLabelPrinter();
      await failThenRetry(
        tester,
        working: working,
        reload: () => _stored(gasRole: GasRole.diluent),
      );

      expect(working.connects, 0);
      expect(find.text(changed), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a re-read that fails prints nothing and offers Retry again',
        (tester) async {
      final working = FakeLabelPrinter();
      var reads = 0;
      final logged = await _captureDebugPrint(() async {
        await failThenRetry(
          tester,
          working: working,
          reload: () {
            if (++reads == 1) throw StateError('log unreadable');
            return _stored();
          },
        );
      });

      expect(working.connects, 0);
      expect(find.text('Printing failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(logged.join(), contains('log unreadable'));

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(working.printed, hasLength(1));
      expect(find.text('Label printed.'), findsOneWidget);
    });
  });
}
