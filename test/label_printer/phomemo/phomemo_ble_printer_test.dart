import 'package:ccrlogger/label_printer/label_printer.dart';
import 'package:ccrlogger/label_printer/phomemo/ble/phomemo_ble_printer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/fake_ble_central.dart';

void main() {
  test('a connect the BLE layer refuses says why, after "Printer not found"',
      () async {
    final central = FakeBleCentral();
    central.peripheral('AABBCCDDEEFF').reachable = false;
    final printer = PhomemoBlePrinter(remoteId: 'AABBCCDDEEFF', central: central);

    await expectLater(
      printer.connect(),
      throwsA(
        isA<LabelPrinterException>().having(
          (e) => e.message,
          'message',
          'Printer not found (unreachable)',
        ),
      ),
    );
    await printer.disconnect();
  });
}
