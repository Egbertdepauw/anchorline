import 'package:ccrlogger/ble/ble_central.dart';
import 'package:ccrlogger/ble/ble_device_scan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/fake_ble_central.dart';

void main() {
  group('normalizeBleUuid', () {
    test('expands 16- and 32-bit UUIDs on the base UUID', () {
      expect(normalizeBleUuid('FF00'), '0000ff00-0000-1000-8000-00805f9b34fb');
      expect(
        normalizeBleUuid('0000180f'),
        '0000180f-0000-1000-8000-00805f9b34fb',
      );
    });

    test('lower-cases a 128-bit UUID', () {
      expect(
        normalizeBleUuid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E'),
        '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
      );
    });
  });

  group('chunkForWrite', () {
    test('cuts to the payload, last chunk short', () {
      final chunks = chunkForWrite(List.generate(45, (i) => i), 20);
      expect(chunks.map((c) => c.length), [20, 20, 5]);
      expect([for (final c in chunks) ...c], List.generate(45, (i) => i));
    });

    test('an exact multiple has no empty tail', () {
      expect(chunkForWrite(List.filled(40, 0), 20).length, 2);
    });

    test('nothing to write is no chunks', () {
      expect(chunkForWrite(const [], 20), isEmpty);
    });
  });

  test('maxWritePayload is MTU minus 3, never below 20', () {
    final p = FakeBleCentral().peripheral('x');
    p.mtu = 23;
    expect(p.maxWritePayload, 20);
    p.mtu = 247;
    expect(p.maxWritePayload, 244);
    p.mtu = 10;
    expect(p.maxWritePayload, 20);
  });

  test('findCharacteristic compares UUIDs in any form', () {
    final c = FakeBleCharacteristic('ff00', 'ff02');
    expect(
      findCharacteristic([c], '0000FF00-0000-1000-8000-00805F9B34FB', 'FF02'),
      same(c),
    );
    expect(findCharacteristic([c], 'ff00', 'ff03'), isNull);
  });

  group('waitForAdapterOn', () {
    testWidgets('returns at once when on', (tester) async {
      expect(
        await waitForAdapterOn(FakeBleCentral(), const Duration(seconds: 1)),
        BleAdapterState.on,
      );
    });

    testWidgets('waits for on', (tester) async {
      final central = FakeBleCentral(adapter: BleAdapterState.unknown);
      BleAdapterState? got;
      waitForAdapterOn(central, const Duration(seconds: 5))
          .then((s) => got = s);
      await tester.pump(const Duration(seconds: 1));
      expect(got, isNull);
      central.setAdapter(BleAdapterState.on);
      await tester.pump();
      expect(got, BleAdapterState.on);
    });

    testWidgets('times out with the last state seen', (tester) async {
      final central = FakeBleCentral(adapter: BleAdapterState.unknown);
      BleAdapterState? got;
      waitForAdapterOn(central, const Duration(seconds: 5))
          .then((s) => got = s);
      central.setAdapter(BleAdapterState.unavailable);
      await tester.pump(const Duration(seconds: 5));
      expect(got, BleAdapterState.unavailable);
    });
  });

  test('bleAdapterProblem', () {
    expect(bleAdapterProblem(BleAdapterState.on), isNull);
    expect(bleAdapterProblem(BleAdapterState.off), 'Bluetooth is off');
    expect(bleAdapterProblem(BleAdapterState.unknown), 'Bluetooth is off');
    expect(
      bleAdapterProblem(BleAdapterState.unavailable),
      'Bluetooth LE is not available',
    );
  });

  group('BleDeviceScan', () {
    testWidgets('keeps a real name over a later unnamed packet',
        (tester) async {
      final central = FakeBleCentral();
      final scan = BleDeviceScan(
        central: central,
        match: (r) => r.name.isEmpty ? 'Unnamed' : r.name,
        error: (m) => m,
        unnamed: 'Unnamed',
      );
      final lists = <List<BleFoundDevice>>[];
      scan.stream.listen(lists.add);
      await tester.pump();
      central
        ..advertise(const BleScanResult(id: 'A', name: ''))
        ..advertise(const BleScanResult(id: 'A', name: 'M110 1234'))
        ..advertise(const BleScanResult(id: 'A', name: ''));
      await tester.pump();
      expect(lists.map((l) => l.single.name), ['Unnamed', 'M110 1234']);
      scan.end();
    });

    testWidgets('sorts case-insensitively when asked', (tester) async {
      final central = FakeBleCentral();
      final scan = BleDeviceScan(
        central: central,
        match: (r) => r.name,
        error: (m) => m,
        caseInsensitiveSort: true,
      );
      final lists = <List<BleFoundDevice>>[];
      scan.stream.listen(lists.add);
      await tester.pump();
      central
        ..advertise(const BleScanResult(id: '1', name: 'b'))
        ..advertise(const BleScanResult(id: '2', name: 'A'));
      await tester.pump();
      expect(lists.last.map((d) => d.name), ['A', 'b']);
      scan.end();
    });

    testWidgets('ends when the platform scan ends', (tester) async {
      final central = FakeBleCentral();
      final scan = BleDeviceScan(
        central: central,
        match: (r) => r.name,
        error: (m) => m,
      );
      var done = false;
      scan.stream.listen(null, onDone: () => done = true);
      await tester.pump();
      await central.endScan();
      await tester.pump();
      expect(done, isTrue);
    });
  });
}
