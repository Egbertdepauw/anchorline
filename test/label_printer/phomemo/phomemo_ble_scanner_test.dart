import 'dart:async';

import 'package:ccrlogger/ble/ble_central.dart';
import 'package:ccrlogger/label_printer/label_printer.dart';
import 'package:ccrlogger/label_printer/phomemo/ble/phomemo_ble_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/fake_ble_central.dart';

void main() {
  group('phomemoNameOf', () {
    test('a known name prefix, any case', () {
      expect(phomemoNameOf(const BleScanResult(id: 'a', name: 'm110 4F2A')),
          'm110 4F2A');
      expect(phomemoNameOf(const BleScanResult(id: 'a', name: 'Q199E')),
          'Q199E');
    });

    test('the Phomemo service without a name', () {
      expect(
        phomemoNameOf(const BleScanResult(
          id: 'a',
          name: '',
          serviceUuids: ['0000ff00-0000-1000-8000-00805f9b34fb'],
        )),
        'Phomemo printer',
      );
    });

    test('anything else is not a printer', () {
      expect(phomemoNameOf(const BleScanResult(id: 'a', name: 'Petrel 3')),
          isNull);
      expect(phomemoNameOf(const BleScanResult(id: 'a', name: '')), isNull);
    });
  });

  testWidgets('scans unfiltered and lists printers sorted', (tester) async {
    final central = FakeBleCentral();
    final scanner = PhomemoBleScanner(central: central);
    final lists = <List<FoundLabelPrinter>>[];
    final sub = scanner.scan().listen(lists.add);
    await tester.pump();
    expect(central.scans, [const <String>[]]);
    central
      ..advertise(const BleScanResult(id: '2', name: 'M110 B'))
      ..advertise(const BleScanResult(id: '9', name: 'Shearwater'))
      ..advertise(const BleScanResult(id: '1', name: 'm110 a'));
    await tester.pump();
    expect(lists.last.map((p) => p.name), ['m110 a', 'M110 B']);
    // Not awaited: awaiting a cancel hangs testWidgets.
    unawaited(sub.cancel());
    await tester.pump();
    await scanner.stop();
    expect(central.stopScanCalls, 1);
  });

  testWidgets('Bluetooth off is a LabelPrinterException event',
      (tester) async {
    final central = FakeBleCentral(adapter: BleAdapterState.off);
    Object? error;
    PhomemoBleScanner(central: central)
        .scan()
        .listen(null, onError: (Object e) => error = e);
    await tester.pump(const Duration(seconds: 10));
    expect(
      error,
      isA<LabelPrinterException>()
          .having((e) => e.message, 'message', 'Bluetooth is off'),
    );
  });
}
