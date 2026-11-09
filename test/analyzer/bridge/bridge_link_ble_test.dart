import 'dart:async';
import 'dart:convert';

import 'package:ccrlogger/analyzer/bridge/bridge_link.dart';
import 'package:ccrlogger/analyzer/bridge/bridge_link_ble.dart';
import 'package:ccrlogger/ble/ble_central.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/fake_ble_central.dart';

const _id = 'A0B1C2D3E4F5';

({FakeBleCharacteristic tx, FakeBleCharacteristic rx}) _nus(
  FakeBlePeripheral p, {
  bool rxWithResponse = false,
}) {
  final tx = FakeBleCharacteristic(
    kNusServiceUuid,
    kNusTxUuid,
    properties: const BleCharacteristicProperties(notify: true),
  );
  final rx = FakeBleCharacteristic(
    kNusServiceUuid,
    kNusRxUuid,
    properties: BleCharacteristicProperties(
      write: rxWithResponse,
      writeWithoutResponse: true,
    ),
  );
  p.characteristics = [tx, rx];
  return (tx: tx, rx: rx);
}

/// A link on a central that can't reconnect by itself (Windows, Linux).
({CentralBridgeLink link, FakeBlePeripheral device, FakeBleCentral central})
_manual() {
  final central = FakeBleCentral();
  final link = CentralBridgeLink(remoteId: _id, central: central);
  return (link: link, device: central.peripheral(_id), central: central);
}

void main() {
  group('Dart reconnect (Windows, Linux)', () {
    testWidgets('connects, subscribes and reports connected', (tester) async {
      final (:link, :device, central: _) = _manual();
      final (:tx, rx: _) = _nus(device);
      final states = <BridgeLinkState>[];
      link.states.listen(states.add);

      await link.connect();
      await tester.pump();

      expect(link.state, BridgeLinkState.connected);
      expect(states, [BridgeLinkState.connecting, BridgeLinkState.connected]);
      expect(device.connectCalls, 1);
      expect(device.autoConnectCalls, 0);
      expect(tx.notifyCalls, [true]);
      await link.dispose();
    });

    testWidgets('first connect retries until the bridge shows up',
        (tester) async {
      final (:link, :device, central: _) = _manual();
      _nus(device);
      device.reachable = false;
      var done = false;
      unawaited(link.connect().then((_) => done = true));

      await tester.pump(const Duration(seconds: 2));
      expect(done, isFalse);
      expect(device.connectCalls, greaterThan(1));
      expect(link.state, BridgeLinkState.connecting);

      device.reachable = true;
      await tester.pump(const Duration(seconds: 1));
      expect(done, isTrue);
      expect(link.state, BridgeLinkState.connected);
      await link.dispose();
    });

    testWidgets('first connect gives up after the timeout', (tester) async {
      final (:link, :device, central: _) = _manual();
      _nus(device);
      device.reachable = false;
      Object? error;
      unawaited(link.connect().catchError((Object e) => error = e));

      await tester.pump(kBridgeFirstConnectTimeout);
      await tester.pump(const Duration(seconds: 1));
      expect(error, isA<BridgeLinkException>().having(
        (e) => e.message,
        'message',
        'Bridge not found. Is it switched on?',
      ));
      expect(link.state, BridgeLinkState.disconnected);
      final calls = device.connectCalls;
      await tester.pump(const Duration(seconds: 5));
      expect(device.connectCalls, calls, reason: 'no retries after giving up');
      await link.dispose();
    });

    testWidgets('a device without the NUS service fails at once',
        (tester) async {
      final (:link, :device, central: _) = _manual();
      device.characteristics = [
        FakeBleCharacteristic('180f', '2a19'),
      ];
      Object? error;
      unawaited(link.connect().catchError((Object e) => error = e));
      await tester.pump();
      await tester.pump();
      expect(error, isA<BridgeLinkException>().having(
        (e) => e.message,
        'message',
        'Not an Anchorline bridge',
      ));
      expect(device.connectCalls, 1);
      expect(device.isConnected, isFalse);
      await link.dispose();
    });

    testWidgets('Bluetooth off fails with a message', (tester) async {
      final central = FakeBleCentral(adapter: BleAdapterState.off);
      final link = CentralBridgeLink(remoteId: _id, central: central);
      Object? error;
      unawaited(link.connect().catchError((Object e) => error = e));
      await tester.pump(kBridgeBluetoothOnTimeout);
      expect(
        error,
        isA<BridgeLinkException>()
            .having((e) => e.message, 'message', 'Bluetooth is off'),
      );
      expect(link.state, BridgeLinkState.disconnected);
      await link.dispose();
    });

    testWidgets('no Bluetooth LE adapter fails with a message', (tester) async {
      final central = FakeBleCentral(adapter: BleAdapterState.unavailable);
      final link = CentralBridgeLink(remoteId: _id, central: central);
      Object? error;
      unawaited(link.connect().catchError((Object e) => error = e));
      await tester.pump(kBridgeBluetoothOnTimeout);
      expect(
        error,
        isA<BridgeLinkException>().having(
          (e) => e.message,
          'message',
          'Bluetooth LE is not available',
        ),
      );
      await link.dispose();
    });

    testWidgets('a drop goes connecting, then reconnects with backoff',
        (tester) async {
      final (:link, :device, central: _) = _manual();
      final (:tx, rx: _) = _nus(device);
      await link.connect();
      final states = <BridgeLinkState>[];
      link.states.listen(states.add);

      device.reachable = false;
      device.drop();
      await tester.pump();
      expect(link.state, BridgeLinkState.connecting);
      expect(states, [BridgeLinkState.connecting]);

      final before = device.connectCalls;
      // Attempts after 0.5, 1, 2 and 4 s: at 7.5 s four have been made.
      await tester.pump(const Duration(milliseconds: 500));
      expect(device.connectCalls, before + 1);
      await tester.pump(const Duration(seconds: 1));
      expect(device.connectCalls, before + 2);
      await tester.pump(const Duration(seconds: 2));
      expect(device.connectCalls, before + 3);
      await tester.pump(const Duration(seconds: 3));
      expect(device.connectCalls, before + 3, reason: 'next one at +4 s');
      await tester.pump(const Duration(seconds: 1));
      expect(device.connectCalls, before + 4);

      device.reachable = true;
      await tester.pump(const Duration(seconds: 8));
      expect(link.state, BridgeLinkState.connected);
      expect(states.last, BridgeLinkState.connected);
      // Re-subscribed on the new link.
      expect(tx.notifyCalls, [true, true]);

      // Lines flow again.
      final lines = <String>[];
      link.lines.listen(lines.add);
      tx.notify(utf8.encode('HELLO\n'));
      await tester.pump();
      expect(lines, ['HELLO']);
      await link.dispose();
    });

    testWidgets('disconnect stops the reconnection loop', (tester) async {
      final (:link, :device, central: _) = _manual();
      _nus(device);
      await link.connect();
      device.reachable = false;
      device.drop();
      await tester.pump(const Duration(seconds: 2));
      await link.disconnect();
      final calls = device.connectCalls;
      await tester.pump(const Duration(seconds: 30));
      expect(device.connectCalls, calls);
      expect(link.state, BridgeLinkState.disconnected);
      await link.dispose();
    });

    testWidgets('a requested disconnect is not treated as a drop',
        (tester) async {
      final (:link, :device, central: _) = _manual();
      _nus(device);
      await link.connect();
      final calls = device.connectCalls;
      await link.disconnect();
      await tester.pump(const Duration(seconds: 30));
      expect(device.connectCalls, calls);
      expect(link.state, BridgeLinkState.disconnected);
      await link.dispose();
    });
  });

  group('autoConnect (Android, iOS, macOS)', () {
    testWidgets('connects through autoConnect and follows the platform',
        (tester) async {
      final central = FakeBleCentral(supportsAutoConnect: true);
      final link = CentralBridgeLink(remoteId: _id, central: central);
      final device = central.peripheral(_id);
      _nus(device);

      await link.connect();
      expect(device.autoConnectCalls, 1);
      expect(device.connectCalls, 0);
      expect(link.state, BridgeLinkState.connected);

      device.drop();
      await tester.pump();
      expect(link.state, BridgeLinkState.connecting);
      await tester.pump(const Duration(seconds: 30));
      expect(device.connectCalls, 0, reason: 'the platform reconnects');

      device.autoReconnect();
      await tester.pump();
      await tester.pump();
      expect(link.state, BridgeLinkState.connected);
      await link.dispose();
    });

    testWidgets('gives up when the bridge never comes', (tester) async {
      final central = FakeBleCentral(supportsAutoConnect: true);
      final link = CentralBridgeLink(remoteId: _id, central: central);
      central.peripheral(_id).reachable = false;
      Object? error;
      unawaited(link.connect().catchError((Object e) => error = e));
      await tester.pump(kBridgeFirstConnectTimeout);
      await tester.pump();
      expect(error, isA<BridgeLinkException>());
      expect(link.state, BridgeLinkState.disconnected);
      await link.dispose();
    });
  });

  group('send', () {
    testWidgets('chunks a message to the MTU payload', (tester) async {
      final (:link, :device, central: _) = _manual();
      final (tx: _, :rx) = _nus(device);
      device.mtu = 23; // 20-byte payload
      await link.connect();

      final message = 'X' * 45; // 46 bytes with the newline
      await link.send(message);
      expect(rx.writes.map((w) => w.value.length), [20, 20, 6]);
      expect(rx.writes.every((w) => w.withoutResponse), isTrue);
      expect(
        utf8.decode([for (final w in rx.writes) ...w.value]),
        '$message\n',
      );
      await link.dispose();
    });

    testWidgets('uses the larger payload a larger MTU gives', (tester) async {
      final (:link, :device, central: _) = _manual();
      final (tx: _, :rx) = _nus(device, rxWithResponse: true);
      device.mtu = 247;
      await link.connect();
      await link.send('Y' * 300);
      expect(rx.writes.map((w) => w.value.length), [244, 57]);
      expect(rx.writes.every((w) => !w.withoutResponse), isTrue);
      await link.dispose();
    });

    testWidgets('a failed write is a BridgeLinkException', (tester) async {
      final (:link, :device, central: _) = _manual();
      final (tx: _, :rx) = _nus(device);
      await link.connect();
      rx.writeError = const BleException(kBleErrorWriteFailed, 'nope');
      await expectLater(
        link.send('PING'),
        throwsA(isA<BridgeLinkException>().having(
          (e) => e.message,
          'message',
          'Bridge write failed: nope',
        )),
      );
      await link.dispose();
    });

    testWidgets('fails while not connected', (tester) async {
      final (:link, device: _, central: _) = _manual();
      await expectLater(link.send('PING'), throwsA(isA<BridgeLinkException>()));
      await link.dispose();
    });
  });

  testWidgets('a line split over notifications arrives whole',
      (tester) async {
    final (:link, :device, central: _) = _manual();
    final (:tx, rx: _) = _nus(device);
    await link.connect();
    final lines = <String>[];
    link.lines.listen(lines.add);
    final bytes = utf8.encode('L O2=20.9 He=0.0\nSTATUS ok\n');
    for (var i = 0; i < bytes.length; i += 7) {
      tx.notify(bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7));
    }
    await tester.pump();
    expect(lines, ['L O2=20.9 He=0.0', 'STATUS ok']);
    await link.dispose();
  });

  group('scanForBridges', () {
    testWidgets('lists named bridges advertising NUS, sorted', (tester) async {
      final central = FakeBleCentral();
      final found = <List<FoundBridge>>[];
      final sub = scanForBridges(central: central).listen(found.add);
      await tester.pump();
      expect(central.scans, [
        [kNusServiceUuid],
      ]);

      central
        ..advertise(const BleScanResult(id: 'B', name: 'Anchorline Bridge 9F'))
        ..advertise(const BleScanResult(id: 'X', name: 'Somebody else'))
        ..advertise(const BleScanResult(id: 'A', name: 'Anchorline Bridge 1A'))
        ..advertise(const BleScanResult(id: 'A', name: 'Anchorline Bridge 1A'));
      await tester.pump();
      expect(found.length, 2, reason: 'a repeat changes nothing');
      expect(found.last.map((b) => b.name), [
        'Anchorline Bridge 1A',
        'Anchorline Bridge 9F',
      ]);
      // Not awaited: awaiting a cancel hangs testWidgets.
      unawaited(sub.cancel());
      await tester.pump();
    });

    testWidgets('ends at the timeout', (tester) async {
      final central = FakeBleCentral();
      var done = false;
      scanForBridges(central: central, timeout: const Duration(seconds: 3))
          .listen(null, onDone: () => done = true);
      await tester.pump(const Duration(seconds: 3));
      expect(done, isTrue);
    });

    testWidgets('Bluetooth off is an error event', (tester) async {
      final central = FakeBleCentral(adapter: BleAdapterState.off);
      Object? error;
      scanForBridges(central: central).listen(
        null,
        onError: (Object e) => error = e,
      );
      await tester.pump(kBridgeBluetoothOnTimeout);
      expect(
        error,
        isA<BridgeLinkException>()
            .having((e) => e.message, 'message', 'Bluetooth is off'),
      );
    });

    testWidgets('waits for the adapter to come on', (tester) async {
      final central = FakeBleCentral(adapter: BleAdapterState.unknown);
      final found = <List<FoundBridge>>[];
      final sub = scanForBridges(central: central).listen(found.add);
      await tester.pump(const Duration(seconds: 1));
      expect(central.scans, isEmpty);
      central.setAdapter(BleAdapterState.on);
      await tester.pump();
      expect(central.scans, hasLength(1));
      // Not awaited: awaiting a cancel hangs testWidgets.
      unawaited(sub.cancel());
      await tester.pump();
    });

    testWidgets('a failed scan is an error event', (tester) async {
      final central = FakeBleCentral()
        ..scanError = const BleException(kBleErrorScanFailed, 'x');
      Object? error;
      scanForBridges(central: central).listen(
        null,
        onError: (Object e) => error = e,
      );
      await tester.pump();
      await tester.pump();
      expect(
        error,
        isA<BridgeLinkException>()
            .having((e) => e.message, 'message', 'Bluetooth scan failed'),
      );
    });
  });
}
