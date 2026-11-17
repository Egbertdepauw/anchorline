import 'dart:async';
import 'dart:typed_data';

import 'package:ccrlogger/ble/ble_central.dart';
import 'package:ccrlogger/devices/libdc/ble_central_libdc_link.dart';
import 'package:ccrlogger/devices/libdc/libdc_ble_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libdivecomputer/libdivecomputer.dart';

import 'support/fake_gatt.dart';

const _divesoft = '0000fcef-0000-1000-8000-00805f9b34fb';
const _nordic = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const _halcyon = '00000001-8c3b-4f2c-a59e-8c08224f3253';
const _telit = '0000fefb-0000-1000-8000-00805f9b34fb';
const _ublox = '2456e1b9-26e2-8f83-e744-f34f01e9d701';
const _telitData = '00000002-0000-1000-8000-008025000000';
const _telitWrite = '00000001-0000-1000-8000-008025000000';
const _telitCreditTx = '00000003-0000-1000-8000-008025000000';
const _telitCreditRx = '00000004-0000-1000-8000-008025000000';
const _ubloxData = '2456e1b9-26e2-8f83-e744-f34f01e9d703';
const _ubloxCredit = '2456e1b9-26e2-8f83-e744-f34f01e9d704';

LibdcBleProfile _generic() => libdcProfileFor(
  const LibdcDescriptor(
    vendor: 'T',
    product: 'T',
    family: dc_family_t.DC_FAMILY_NULL,
    model: 0,
    transports: 0,
  ),
);

LibdcBleProfile _hw() => libdcProfileFor(
  const LibdcDescriptor(
    vendor: 'HW',
    product: 'OSTC',
    family: dc_family_t.DC_FAMILY_HW_OSTC3,
    model: 0,
    transports: 0,
  ),
);

Future<BleCentralLibdcLink> _connect(
  FakeGatt g, {
  LibdcBleProfile? profile,
  bool pairOnNotifyFailure = false,
}) => BleCentralLibdcLink.connect(
  g.central,
  g.peripheral.id,
  advertisedName: 'Dev',
  profile: profile ?? _generic(),
  pairOnNotifyFailure: pairOnNotifyFailure,
);

void main() {
  test('Divesoft: the fcef service is chosen over a Nordic UART', () async {
    final g = FakeGatt();
    addSerialService(
      g,
      _nordic,
      notifyUuid: '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
      writeUuid: '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
    );
    addSerialService(g, _divesoft);
    final link = await _connect(g);
    expect(g['$_divesoft/0001'].notifyCalls, [true]);
    expect(
      g['$_nordic/6e400003-b5a3-f393-e0a9-e50e24dcca9e'].notifyCalls,
      isEmpty,
    );
    await link.close();
  });

  test(
    'Halcyon: the Rx/Tx characteristics Subsurface skips are unused',
    () async {
      final g = FakeGatt();
      final rxIgnored = g.add(
        _halcyon,
        '00000101-8c3b-4f2c-a59e-8c08224f3253',
        kNotifyProps,
      );
      final rx = g.add(
        _halcyon,
        '00000102-8c3b-4f2c-a59e-8c08224f3253',
        kNotifyProps,
      );
      final txIgnored = g.add(
        _halcyon,
        '00000201-8c3b-4f2c-a59e-8c08224f3253',
        kWriteNoRspProps,
      );
      final tx = g.add(
        _halcyon,
        '00000202-8c3b-4f2c-a59e-8c08224f3253',
        kWriteNoRspProps,
      );
      final link = await _connect(g);
      await link.write(Uint8List.fromList([1, 2]));
      expect(rx.notifyCalls, [true]);
      expect(rxIgnored.notifyCalls, isEmpty);
      expect(tx.writes, hasLength(1));
      expect(txIgnored.writes, isEmpty);
      await link.close();
    },
  );

  test('an unknown vendor service with notify and write is chosen; '
      'upgrade and standard services are not', () async {
    final g = FakeGatt();
    // Standard 16-bit services (a Generic Access style one) come first.
    addSerialService(g, '1800');
    addSerialService(g, '00001530-1212-efde-1523-785feabcd123');
    addSerialService(g, '9e5d1e47-5c13-43a0-8635-82ad38a1386f');
    // Notify only: no write characteristic.
    g.add('11111111-0000-0000-0000-000000000000', '0001', kNotifyProps);
    addSerialService(g, '22222222-0000-0000-0000-000000000000');
    final link = await _connect(g);
    expect(g['22222222-0000-0000-0000-000000000000/0001'].notifyCalls, [true]);
    expect(g['1800/0001'].notifyCalls, isEmpty);
    expect(g['00001530-1212-efde-1523-785feabcd123/0001'].notifyCalls, isEmpty);
    expect(g['9e5d1e47-5c13-43a0-8635-82ad38a1386f/0001'].notifyCalls, isEmpty);
    expect(g['11111111-0000-0000-0000-000000000000/0001'].notifyCalls, isEmpty);
    await link.close();
  });

  test('no usable service fails the connect and disconnects', () async {
    final g = FakeGatt();
    addSerialService(g, '1800');
    await expectLater(_connect(g), throwsA(isA<BleException>()));
    expect(g.peripheral.isConnected, isFalse);
  });

  group('flow control', () {
    Future<(FakeGatt, BleCentralLibdcLink)> telit() async {
      final g = FakeGatt();
      g.add(_telit, _telitWrite, kWriteNoRspProps);
      g.add(_telit, _telitData, kNotifyProps);
      g.add(_telit, _telitCreditTx, kWriteProps);
      g.add(_telit, _telitCreditRx, kIndicateProps);
      return (g, await _connect(g, profile: _hw()));
    }

    test('HW Telit: 254 credits at connect, 222 more after 222 packets, '
        'other characteristics dropped', () async {
      final (g, link) = await telit();
      final credits = g['$_telit/$_telitCreditTx'];
      final data = g['$_telit/$_telitData'];
      expect(g['$_telit/$_telitCreditRx'].notifyCalls, [true]);
      expect(data.notifyCalls, [true]);
      expect(credits.writes.map((w) => w.value), [
        [254],
      ]);
      expect(credits.writes.single.withoutResponse, isFalse);

      final got = <Uint8List>[];
      link.notifications.listen(got.add);
      // Credit indications and other characteristics don't count or pass.
      g['$_telit/$_telitCreditRx'].notify([9, 9]);
      for (var i = 0; i < 221; i++) {
        data.notify([i & 0xff]);
      }
      await pumpEventQueue();
      expect(credits.writes, hasLength(1));
      data.notify([0xAA]);
      await pumpEventQueue();
      expect(got, hasLength(222));
      expect(credits.writes.map((w) => w.value), [
        [254],
        [222],
      ]);
      await link.close();
    });

    test('HW u-blox: the same credit rule on d704, data on d703', () async {
      final g = FakeGatt();
      g.add(_ublox, _ubloxData, kNotifyWriteProps);
      g.add(_ublox, _ubloxCredit, kNotifyWriteProps);
      final link = await _connect(g, profile: _hw());
      final credits = g['$_ublox/$_ubloxCredit'];
      final data = g['$_ublox/$_ubloxData'];
      expect(credits.notifyCalls, [true]);
      expect(credits.writes.map((w) => w.value), [
        [254],
      ]);
      final got = <Uint8List>[];
      link.notifications.listen(got.add);
      credits.notify([1]); // not data
      for (var i = 0; i < 222; i++) {
        data.notify([1]);
      }
      await pumpEventQueue();
      expect(got, hasLength(222));
      expect(credits.writes.map((w) => w.value), [
        [254],
        [222],
      ]);
      // Writes go to the data characteristic.
      await link.write(Uint8List.fromList([7]));
      expect(data.writes, hasLength(1));
      await link.close();
    });
  });

  test('a write longer than the payload is chunked in order; '
      'without-response when supported', () async {
    final g = FakeGatt(mtu: 23);
    addSerialService(g, '22222222-0000-0000-0000-000000000000');
    final w = g['22222222-0000-0000-0000-000000000000/0002'];
    final link = await _connect(g);
    await link.write(Uint8List.fromList(List.generate(45, (i) => i)));
    expect(w.writes.map((e) => e.value.length), [20, 20, 5]);
    expect(w.writes.expand((e) => e.value), List.generate(45, (i) => i));
    expect(w.writes.every((e) => e.withoutResponse), isTrue);
    await link.close();

    final g2 = FakeGatt();
    addSerialService(
      g2,
      '22222222-0000-0000-0000-000000000000',
      writeProps: kWriteProps,
    );
    final link2 = await _connect(g2);
    await link2.write(Uint8List.fromList([1]));
    expect(
      g2['22222222-0000-0000-0000-000000000000/0002']
          .writes
          .single
          .withoutResponse,
      isFalse,
    );
    await link2.close();
  });

  test('notifications are delivered, the first one included', () async {
    final g = FakeGatt();
    addSerialService(g, '22222222-0000-0000-0000-000000000000');
    final link = await _connect(g);
    g['22222222-0000-0000-0000-000000000000/0001'].notify([1, 2, 3]);
    final first = await link.notifications.first;
    expect(first, [1, 2, 3]);
    expect(link.advertisedName, 'Dev');
    await link.close();
  });

  test('a dropped connection completes disconnected', () async {
    final g = FakeGatt();
    addSerialService(g, '22222222-0000-0000-0000-000000000000');
    final link = await _connect(g);
    var done = false;
    unawaited(link.disconnected.then((_) => done = true));
    await pumpEventQueue();
    expect(done, isFalse);
    g.peripheral.drop();
    await pumpEventQueue();
    expect(done, isTrue);
    await link.close();
  });

  test(
    'Windows: a notify failure triggers pair() once, then retries',
    () async {
      final g = FakeGatt();
      addSerialService(g, '22222222-0000-0000-0000-000000000000');
      final n = g['22222222-0000-0000-0000-000000000000/0001'];
      n.notifyError = const BleException(kBleErrorGatt, 'denied');
      n.onSetNotify = () {
        if (n.notifyCalls.length >= 2) n.notifyError = null;
      };
      g.peripheral.pairResult = true;
      final link = await _connect(g, pairOnNotifyFailure: true);
      expect(g.peripheral.pairCalls, 1);
      expect(n.notifyCalls, [true, true]);
      await link.close();
    },
  );

  test('elsewhere a notify failure is not retried', () async {
    final g = FakeGatt();
    addSerialService(g, '22222222-0000-0000-0000-000000000000');
    g['22222222-0000-0000-0000-000000000000/0001'].notifyError =
        const BleException(kBleErrorGatt, 'denied');
    await expectLater(_connect(g), throwsA(isA<BleException>()));
    expect(g.peripheral.pairCalls, 0);
    expect(g.peripheral.isConnected, isFalse);
  });

  test('characteristic access is unsupported until Task 18', () async {
    final g = FakeGatt();
    addSerialService(g, '22222222-0000-0000-0000-000000000000');
    final link = await _connect(g);
    await expectLater(link.readCharacteristic('2a00'), throwsUnsupportedError);
    await expectLater(
      link.writeCharacteristic('2a00', Uint8List(1)),
      throwsUnsupportedError,
    );
    await link.close();
  });

  test(
    'gattSummary lists services and characteristics; close is idempotent',
    () async {
      final g = FakeGatt();
      addSerialService(g, '22222222-0000-0000-0000-000000000000');
      final link = await _connect(g);
      expect(link.gattSummary.length, 3);
      expect(link.gattSummary.first, contains('22222222-0000'));
      expect(link.gattSummary.join('\n'), contains('notify'));
      await link.close();
      await link.close();
      await link.disconnected;
    },
  );
}
