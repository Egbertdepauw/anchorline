import 'package:ccrlogger/ble/ble_central.dart';
import 'package:ccrlogger/label_printer/label_printer.dart';
import 'package:ccrlogger/label_printer/phomemo/phomemo_encoder.dart';
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

  FakeBleCharacteristic writeChar() => FakeBleCharacteristic(
        kPhomemoServiceUuid,
        kPhomemoWriteUuid,
        properties: const BleCharacteristicProperties(
          write: true,
          writeWithoutResponse: true,
        ),
      );
  FakeBleCharacteristic notifyChar() => FakeBleCharacteristic(
        kPhomemoServiceUuid,
        kPhomemoNotifyUuid,
        properties: const BleCharacteristicProperties(notify: true),
      );

  test('connect pairs first, then turns notifications on', () async {
    final central = FakeBleCentral();
    final p = central.peripheral('AABBCCDDEEFF')..pairResult = true;
    final n = notifyChar();
    p.characteristics = [writeChar(), n];
    final printer = PhomemoBlePrinter(remoteId: 'AABBCCDDEEFF', central: central);

    await printer.connect();
    expect(p.pairCalls, 1);
    expect(n.notifyCalls, [true]);
    expect(printer.notifying, isTrue);
    await printer.disconnect();
  });

  test('notifications the device refuses still leave a usable printer',
      () async {
    final central = FakeBleCentral();
    final p = central.peripheral('AABBCCDDEEFF');
    final n = notifyChar()
      ..notifyError = const BleException(kBleErrorGatt, 'access denied');
    p.characteristics = [writeChar(), n];
    final printer = PhomemoBlePrinter(remoteId: 'AABBCCDDEEFF', central: central);

    await printer.connect();
    expect(printer.notifying, isFalse);
    await printer.disconnect();
  });
}
