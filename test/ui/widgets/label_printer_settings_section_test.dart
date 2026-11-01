import 'dart:async';

import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/label_printer/label_printer.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/settings_screen.dart';
import 'package:ccrlogger/ui/widgets/label_print_controls.dart';
import 'package:ccrlogger/ui/widgets/label_printer_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_label_printer.dart';

const _m110 = FoundLabelPrinter(id: 'dev-1', name: 'Phomemo M110');
const _other = FoundLabelPrinter(id: 'dev-2', name: 'Phomemo T02');

/// A real [SettingsNotifier] on mock prefs, and a [LabelPrintService] built
/// on the fakes and reading that notifier, as the app wires it.
class _Rig {
  _Rig._(this.settings, this.printer, this.scanner, this.service);

  final SettingsNotifier settings;
  final FakeLabelPrinter printer;
  final FakeLabelPrinterScanner scanner;
  final LabelPrintService service;

  static Future<_Rig> build({
    bool configured = false,
    FakeLabelPrinter? printer,
    FakeLabelPrinterScanner? scanner,
    LabelRenderer? render,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (configured) 'label_printer_id': 'dev-1',
      if (configured) 'label_printer_name': 'Phomemo M110',
    });
    final settings = SettingsNotifier();
    await settings.load();
    final fakePrinter = printer ?? FakeLabelPrinter();
    final fakeScanner = scanner ?? FakeLabelPrinterScanner();
    final service = LabelPrintService(
      render: render ?? (_) async => LabelBitmap.blank(384, 240),
      printerFor: (_) => fakePrinter,
      scanner: fakeScanner,
      printerId: () => settings.labelPrinterId,
      use14ForDeeperMixes: () => settings.labelUse14ForDeeperMixes,
    );
    return _Rig._(settings, fakePrinter, fakeScanner, service);
  }

  Widget get section => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LabelPrinterSettingsSection(
              settings: settings,
              printing: service,
            ),
          ),
        ),
      );
}

Finder _key(String k) => find.byKey(ValueKey(k));

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_key(key)).onPressed != null;

/// Opens the "Find printer" dialog and lets the scan run its course.
Future<void> _openFind(WidgetTester tester) async {
  await tester.tap(_key('label-printer-find'));
  await tester.pumpAndSettle();
}

void main() {
  group('with no printer', () {
    testWidgets('says so, offers Find printer and a disabled test print',
        (tester) async {
      final rig = await _Rig.build();
      await tester.pumpWidget(rig.section);

      expect(find.text('No printer set up'), findsOneWidget);
      expect(_enabled(tester, 'label-printer-find'), isTrue);
      expect(find.text('Print test label'), findsOneWidget);
      expect(_enabled(tester, 'label-printer-test'), isFalse);
      expect(_key('label-printer-forget'), findsNothing);
    });
  });

  group('Find printer', () {
    testWidgets('lists what the scanner finds', (tester) async {
      final rig = await _Rig.build(
        scanner: FakeLabelPrinterScanner(printers: [_m110, _other]),
      );
      await tester.pumpWidget(rig.section);
      await _openFind(tester);

      expect(_key('label-printer-result-dev-1'), findsOneWidget);
      expect(_key('label-printer-result-dev-2'), findsOneWidget);
      expect(find.text('Phomemo M110'), findsOneWidget);
      expect(find.text('Phomemo T02'), findsOneWidget);
      expect(find.text('Searching for printers…'), findsNothing);
      expect(find.textContaining('No printers found'), findsNothing);
    });

    testWidgets('saves the tapped printer and shows it with Forget printer',
        (tester) async {
      final rig = await _Rig.build(
        scanner: FakeLabelPrinterScanner(printers: [_m110, _other]),
      );
      await tester.pumpWidget(rig.section);
      await _openFind(tester);

      await tester.tap(_key('label-printer-result-dev-2'));
      await tester.pumpAndSettle();

      expect(rig.settings.labelPrinterId, 'dev-2');
      expect(rig.settings.labelPrinterName, 'Phomemo T02');
      // The dialog is gone; the section names the printer.
      expect(_key('label-printer-result-dev-1'), findsNothing);
      expect(find.text('Phomemo T02'), findsOneWidget);
      expect(find.text('No printer set up'), findsNothing);
      expect(_key('label-printer-forget'), findsOneWidget);
      expect(find.text('Forget printer'), findsOneWidget);
      expect(_enabled(tester, 'label-printer-test'), isTrue);
    });

    testWidgets('shows "searching" while the scan runs, with printers so far',
        (tester) async {
      final gate = Completer<void>();
      final rig = await _Rig.build(
        scanner: FakeLabelPrinterScanner(printers: [_m110], scanGate: gate),
      );
      await tester.pumpWidget(rig.section);
      await tester.tap(_key('label-printer-find'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Searching for printers…'), findsOneWidget);
      expect(_key('label-printer-result-dev-1'), findsOneWidget);

      // The scan times out: the dialog stops searching and keeps the list.
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Searching for printers…'), findsNothing);
      expect(_key('label-printer-result-dev-1'), findsOneWidget);
    });

    testWidgets('says no printers were found when the scan ends empty',
        (tester) async {
      // The real scanner emits no data event at all for an empty scan: the
      // stream just closes at the timeout.
      final rig = await _Rig.build();
      await tester.pumpWidget(rig.section);
      await _openFind(tester);

      expect(find.textContaining('No printers found'), findsOneWidget);
      expect(find.text('Searching for printers…'), findsNothing);
    });

    testWidgets('shows the scanner\'s error message when Bluetooth is off',
        (tester) async {
      final rig = await _Rig.build(
        scanner: FakeLabelPrinterScanner(
          error: const LabelPrinterException('Bluetooth is off'),
        ),
      );
      await tester.pumpWidget(rig.section);
      await _openFind(tester);

      expect(find.text('Bluetooth is off'), findsOneWidget);
      expect(find.text('Searching for printers…'), findsNothing);
      expect(find.textContaining('No printers found'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a generic message for an unexpected scan error',
        (tester) async {
      final rig = await _Rig.build(
        scanner: FakeLabelPrinterScanner(error: StateError('boom')),
      );
      await tester.pumpWidget(rig.section);
      await _openFind(tester);

      expect(find.text('Bluetooth scan failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stops the scan when the dialog is cancelled mid-scan',
        (tester) async {
      final rig = await _Rig.build(
        scanner: FakeLabelPrinterScanner(
          printers: [_m110],
          scanGate: Completer<void>(),
        ),
      );
      await tester.pumpWidget(rig.section);
      await tester.tap(_key('label-printer-find'));
      await tester.pump();
      await tester.pump();
      expect(rig.scanner.stops, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(rig.scanner.stops, 1);
      expect(rig.settings.labelPrinterId, isNull);
      expect(find.text('No printer set up'), findsOneWidget);
    });

    testWidgets('stops the scan when a printer is picked mid-scan',
        (tester) async {
      final rig = await _Rig.build(
        scanner: FakeLabelPrinterScanner(
          printers: [_m110],
          scanGate: Completer<void>(),
        ),
      );
      await tester.pumpWidget(rig.section);
      await tester.tap(_key('label-printer-find'));
      await tester.pump();
      await tester.pump();

      await tester.tap(_key('label-printer-result-dev-1'));
      await tester.pumpAndSettle();

      expect(rig.scanner.stops, 1);
      expect(rig.settings.labelPrinterId, 'dev-1');
    });

    testWidgets('can replace the saved printer', (tester) async {
      final rig = await _Rig.build(
        configured: true,
        scanner: FakeLabelPrinterScanner(printers: [_other]),
      );
      await tester.pumpWidget(rig.section);
      expect(find.text('Phomemo M110'), findsOneWidget);

      await _openFind(tester);
      await tester.tap(_key('label-printer-result-dev-2'));
      await tester.pumpAndSettle();

      expect(rig.settings.labelPrinterId, 'dev-2');
      expect(find.text('Phomemo T02'), findsOneWidget);
      expect(find.text('Phomemo M110'), findsNothing);
    });
  });

  group('Forget printer', () {
    testWidgets('clears the printer', (tester) async {
      final rig = await _Rig.build(configured: true);
      await tester.pumpWidget(rig.section);
      expect(find.text('Phomemo M110'), findsOneWidget);

      await tester.tap(_key('label-printer-forget'));
      await tester.pumpAndSettle();

      expect(rig.settings.labelPrinterId, isNull);
      expect(rig.settings.labelPrinterName, isNull);
      expect(find.text('No printer set up'), findsOneWidget);
      expect(_key('label-printer-forget'), findsNothing);
      expect(_enabled(tester, 'label-printer-test'), isFalse);
    });
  });

  group('Use 1.4 for deeper mixes', () {
    testWidgets('toggles the setting', (tester) async {
      final rig = await _Rig.build();
      await tester.pumpWidget(rig.section);
      expect(find.text('Use 1.4 for deeper mixes'), findsOneWidget);
      expect(
        find.text('MOD at ppO₂ 1.4 for mixes below 50 % O₂. '
            'Off: 1.6 for all mixes.'),
        findsOneWidget,
      );
      expect(
        tester.widget<SwitchListTile>(_key('label-printer-use14')).value,
        isFalse,
      );

      await tester.tap(_key('label-printer-use14'));
      await tester.pumpAndSettle();

      expect(rig.settings.labelUse14ForDeeperMixes, isTrue);
      expect(
        tester.widget<SwitchListTile>(_key('label-printer-use14')).value,
        isTrue,
      );

      await tester.tap(_key('label-printer-use14'));
      await tester.pumpAndSettle();
      expect(rig.settings.labelUse14ForDeeperMixes, isFalse);
    });
  });

  group('Print test label', () {
    testWidgets('prints one label on the saved printer', (tester) async {
      final rig = await _Rig.build(configured: true);
      await tester.pumpWidget(rig.section);

      await tester.tap(_key('label-printer-test'));
      await tester.pumpAndSettle();

      expect(rig.printer.printed, hasLength(1));
      expect(rig.printer.printed.single.$2, 1);
      expect(rig.printer.disconnects, 1);
      expect(find.text('Label printed.'), findsOneWidget);
    });

    testWidgets('adds the printer\'s warnings to the message', (tester) async {
      final rig = await _Rig.build(
        configured: true,
        printer: FakeLabelPrinter(warnings: [PrinterFault.lowBattery]),
      );
      await tester.pumpWidget(rig.section);

      await tester.tap(_key('label-printer-test'));
      await tester.pumpAndSettle();

      expect(
        find.text('Label printed. Printer battery is low.'),
        findsOneWidget,
      );
    });

    testWidgets('says "Printer not found" when the printer can\'t connect',
        (tester) async {
      final rig = await _Rig.build(
        configured: true,
        printer: FakeLabelPrinter(failOnConnect: Exception('no link')),
      );
      await tester.pumpWidget(rig.section);

      await tester.tap(_key('label-printer-test'));
      await tester.pumpAndSettle();

      expect(find.text('Printer not found'), findsOneWidget);
      expect(find.text('Label printed.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a fault that stops the job', (tester) async {
      final rig = await _Rig.build(
        configured: true,
        printer: FakeLabelPrinter(faultOnPrint: PrinterFault.coverOpen),
      );
      await tester.pumpWidget(rig.section);

      await tester.tap(_key('label-printer-test'));
      await tester.pumpAndSettle();

      expect(find.text('Printer cover is open'), findsOneWidget);
    });

    testWidgets('shows "Printing failed" for an unexpected error',
        (tester) async {
      final rig = await _Rig.build(
        configured: true,
        render: (_) async => throw StateError('render bug'),
      );
      await tester.pumpWidget(rig.section);

      final logged = <String?>[];
      final oldDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message);
      try {
        await tester.tap(_key('label-printer-test'));
        await tester.pumpAndSettle();
      } finally {
        debugPrint = oldDebugPrint;
      }

      expect(find.text('Printing failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The error is not swallowed silently.
      expect(logged.join(), contains('render bug'));
    });

    testWidgets('reports an unexpected error with its stack trace',
        (tester) async {
      final reports = <(Object, StackTrace)>[];
      final oldSink = labelPrintErrorSink;
      labelPrintErrorSink = (e, st) async => reports.add((e, st));
      addTearDown(() => labelPrintErrorSink = oldSink);
      final rig = await _Rig.build(
        configured: true,
        render: (_) async => throw StateError('render bug'),
      );
      await tester.pumpWidget(rig.section);

      await tester.tap(_key('label-printer-test'));
      await tester.pumpAndSettle();

      expect(find.text('Printing failed'), findsOneWidget);
      final (error, stack) = reports.single;
      expect(error, isA<StateError>());
      // The stack of the throw, not of the place that caught it.
      expect('$stack', contains('label_printer_settings_section_test.dart'));
    });

    testWidgets('replaces a print failure bar that was left up',
        (tester) async {
      final rig = await _Rig.build(configured: true);
      await tester.pumpWidget(rig.section);
      // A failed label print elsewhere left its bar up. It has a Retry, so
      // it stays until dismissed, and a new bar would queue behind it.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .showSnackBar(SnackBar(
            content: const Text('Printer not found'),
            action: SnackBarAction(label: 'Retry', onPressed: () {}),
          ));
      await tester.pumpAndSettle();
      expect(find.text('Printer not found'), findsOneWidget);

      await tester.tap(_key('label-printer-test'));
      await tester.pumpAndSettle();

      expect(rig.printer.printed, hasLength(1));
      expect(find.text('Label printed.'), findsOneWidget);
      expect(find.text('Printer not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('ignores a second tap while a print is in flight',
        (tester) async {
      final gate = Completer<void>();
      final rig = await _Rig.build(
        configured: true,
        printer: FakeLabelPrinter(printGate: gate),
      );
      await tester.pumpWidget(rig.section);

      await tester.tap(_key('label-printer-test'));
      await tester.pump();
      await tester.pump();
      expect(rig.printer.printed, hasLength(1));
      expect(_enabled(tester, 'label-printer-test'), isFalse);

      await tester.tap(_key('label-printer-test'), warnIfMissed: false);
      await tester.pump();
      expect(rig.printer.printed, hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();
      expect(rig.printer.printed, hasLength(1));
      expect(find.text('Label printed.'), findsOneWidget);
      expect(_enabled(tester, 'label-printer-test'), isTrue);
    });
  });

  group('LabelPrinterSettingsScreen', () {
    testWidgets('is a screen titled "Label printer" holding the section',
        (tester) async {
      final rig = await _Rig.build();
      await tester.pumpWidget(MaterialApp(
        home: LabelPrinterSettingsScreen(
          settings: rig.settings,
          printing: rig.service,
        ),
      ));

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Label printer'),
        ),
        findsOneWidget,
      );
      expect(find.byType(LabelPrinterSettingsSection), findsOneWidget);
      expect(_key('label-printer-find'), findsOneWidget);
    });
  });

  group('SettingsScreen', () {
    // A tall view, so the lazy ListView builds the whole page.
    void tallView(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('hides the label printer section without labelPrinting',
        (tester) async {
      tallView(tester);
      final rig = await _Rig.build();
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(notifier: rig.settings)),
      );

      expect(find.text('Gas analyzer', skipOffstage: false), findsOneWidget);
      expect(find.text('Label printer', skipOffstage: false), findsNothing);
      expect(find.byType(LabelPrinterSettingsSection, skipOffstage: false),
          findsNothing);
    });

    testWidgets('shows it after "Gas analyzer" when labelPrinting is set',
        (tester) async {
      tallView(tester);
      final rig = await _Rig.build();
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          notifier: rig.settings,
          labelPrinting: rig.service,
        ),
      ));

      final analyzer = tester.getTopLeft(find.text('Gas analyzer'));
      final heading = tester.getTopLeft(find.text('Label printer'));
      expect(heading.dy, greaterThan(analyzer.dy));
      expect(find.byType(LabelPrinterSettingsSection), findsOneWidget);
      expect(_key('label-printer-find'), findsOneWidget);
      expect(_key('label-printer-use14'), findsOneWidget);
    });
  });
}
