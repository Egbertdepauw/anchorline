import 'dart:async';

import 'package:ccrlogger/ble/ble_central.dart';
import 'package:ccrlogger/ble/windows_ble_central.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _nus = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const _tx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// Fakes the runner's channels: answers method calls with [answer] and
/// lets the test push events.
class _FakeChannel {
  _FakeChannel() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(kWindowsBleMethodChannel),
      (call) async {
        calls.add(call);
        return answer(call);
      },
    );
    messenger.setMockStreamHandler(
      const EventChannel(kWindowsBleEventChannel),
      MockStreamHandler.inline(
        onListen: (_, sink) {
          _sink = sink;
        },
        onCancel: (_) {
          _sink = null;
        },
      ),
    );
  }

  final List<MethodCall> calls = [];
  FutureOr<Object?> Function(MethodCall call) answer = (_) => null;
  MockStreamHandlerEventSink? _sink;

  void push(Map<String, Object?> event) => _sink!.success(event);

  List<String> get methods => [for (final c in calls) c.method];

  void dispose() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel(kWindowsBleMethodChannel),
      null,
    );
    messenger.setMockStreamHandler(
      const EventChannel(kWindowsBleEventChannel),
      null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decodeWindowsBleEvent', () {
    test('a native log line', () {
      final e = decodeWindowsBleEvent({'event': 'log', 'message': 'pair: paired'});
      expect(e, isA<WindowsBleLog>());
      expect((e! as WindowsBleLog).message, 'pair: paired');
      expect(decodeWindowsBleEvent({'event': 'log'}), isNull);
    });

    test('scan result, UUIDs normalised', () {
      final e = decodeWindowsBleEvent({
        'event': 'scan',
        'id': 'A0B1C2D3E4F5',
        'name': ' Anchorline Bridge 1A2B ',
        'rssi': -61,
        'services': ['6E400001-B5A3-F393-E0A9-E50E24DCCA9E', 'ff00'],
      });
      final r = (e! as WindowsBleAdvertisement).result;
      expect(r.id, 'A0B1C2D3E4F5');
      expect(r.name, 'Anchorline Bridge 1A2B');
      expect(r.rssi, -61);
      expect(r.serviceUuids, [
        _nus,
        '0000ff00-0000-1000-8000-00805f9b34fb',
      ]);
      expect(r.advertises('FF00'), isTrue);
    });

    test('notification carries its bytes', () {
      final e = decodeWindowsBleEvent({
        'event': 'notify',
        'id': 'A0B1C2D3E4F5',
        'service': _nus,
        'characteristic': _tx,
        'value': Uint8List.fromList([1, 2, 3]),
      })! as WindowsBleNotification;
      expect(e.value, [1, 2, 3]);
      expect(e.characteristicUuid, _tx);
    });

    test('connection, mtu, adapter, scanStopped', () {
      expect(
        decodeWindowsBleEvent({
          'event': 'connection',
          'id': 'X',
          'connected': false,
        }),
        isA<WindowsBleConnection>()
            .having((e) => e.connected, 'connected', isFalse),
      );
      expect(
        decodeWindowsBleEvent({'event': 'mtu', 'id': 'X', 'mtu': 247}),
        isA<WindowsBleMtu>().having((e) => e.mtu, 'mtu', 247),
      );
      expect(
        decodeWindowsBleEvent({'event': 'adapter', 'state': 'off'}),
        isA<WindowsBleAdapter>()
            .having((e) => e.state, 'state', BleAdapterState.off),
      );
      expect(
        decodeWindowsBleEvent({'event': 'scanStopped', 'error': 'radio'}),
        isA<WindowsBleScanStopped>().having((e) => e.error, 'error', 'radio'),
      );
    });

    test('unknown or malformed events are ignored', () {
      expect(decodeWindowsBleEvent('nope'), isNull);
      expect(decodeWindowsBleEvent({'event': 'future-thing'}), isNull);
      expect(decodeWindowsBleEvent({'event': 'scan'}), isNull);
      expect(decodeWindowsBleEvent({'event': 'mtu', 'id': 'X'}), isNull);
    });
  });

  test('decodeWindowsProperties', () {
    final p = decodeWindowsProperties(2 | 8);
    expect(p.write, isTrue);
    expect(p.notify, isTrue);
    expect(p.read || p.writeWithoutResponse || p.indicate, isFalse);
    expect(decodeWindowsProperties(4 | 16).canWrite, isTrue);
    expect(decodeWindowsProperties(4 | 16).canNotify, isTrue);
  });

  group('WindowsScanMerger', () {
    test('merges an advertisement and its scan response', () {
      final m = WindowsScanMerger([_nus]);
      // The name comes in the scan response, the UUID in the advertisement.
      expect(m.add(const BleScanResult(id: 'A', name: 'Anchorline Bridge 1')),
          isNull);
      final merged = m.add(
        const BleScanResult(id: 'A', name: '', serviceUuids: [_nus]),
      );
      expect(merged?.name, 'Anchorline Bridge 1');
      expect(merged?.serviceUuids, [_nus]);
    });

    test('without a filter everything passes', () {
      final m = WindowsScanMerger(const []);
      expect(m.add(const BleScanResult(id: 'A', name: 'M110')), isNotNull);
    });

    test('a device that never advertises the service stays out', () {
      final m = WindowsScanMerger([_nus]);
      expect(m.add(const BleScanResult(id: 'A', name: 'x', serviceUuids: [
        '0000180f-0000-1000-8000-00805f9b34fb',
      ])), isNull);
    });
  });

  group('WindowsBleCentral over the channel', () {
    late _FakeChannel channel;
    setUp(() => channel = _FakeChannel());
    tearDown(() => channel.dispose());

    test('adapter state comes from the channel', () async {
      channel.answer = (c) => c.method == 'adapterState' ? 'on' : null;
      final central = WindowsBleCentral();
      expect(central.adapterStateNow, BleAdapterState.unknown);
      expect(
        await waitForAdapterOn(central, const Duration(seconds: 1)),
        BleAdapterState.on,
      );
    });

    test('no Bluetooth reads as unavailable', () async {
      channel.answer = (c) => 'unavailable';
      final central = WindowsBleCentral();
      final first = await central.adapterStates.first;
      expect(first, BleAdapterState.unavailable);
    });

    test('scan filters and merges, and stops on cancel', () async {
      final central = WindowsBleCentral();
      final results = <BleScanResult>[];
      final sub = central.scan(withServices: [_nus]).listen(results.add);
      await pumpEventQueue();
      expect(channel.methods, contains('startScan'));

      channel
        ..push({'event': 'scan', 'id': 'A', 'name': 'Bridge', 'rssi': -50})
        ..push({
          'event': 'scan',
          'id': 'A',
          'name': '',
          'rssi': -52,
          'services': [_nus],
        })
        ..push({'event': 'scan', 'id': 'B', 'name': 'Other', 'rssi': -70});
      await pumpEventQueue();
      expect(results.map((r) => (r.id, r.name)), [('A', 'Bridge')]);

      await sub.cancel();
      await pumpEventQueue();
      expect(channel.methods.last, 'stopScan');
    });

    test('a scan that fails to start is an error event', () async {
      channel.answer = (c) => c.method == 'startScan'
          ? throw PlatformException(code: kBleErrorScanFailed, message: 'x')
          : null;
      final central = WindowsBleCentral();
      Object? error;
      central.scan().listen(null, onError: (Object e) => error = e);
      await pumpEventQueue();
      expect(
        error,
        isA<BleException>().having((e) => e.code, 'code', kBleErrorScanFailed),
      );
    });

    test('a watcher that stops by itself ends the scan with an error',
        () async {
      final central = WindowsBleCentral();
      Object? error;
      var done = false;
      central.scan().listen(
            null,
            onError: (Object e) => error = e,
            onDone: () => done = true,
          );
      await pumpEventQueue();
      channel.push({'event': 'scanStopped', 'error': 'radio not available'});
      await pumpEventQueue();
      expect(error, isA<BleException>());
      expect(done, isTrue);
    });

    test('connect, discover, notify, write and drop', () async {
      channel.answer = (c) => switch (c.method) {
            'connect' => {'mtu': 247},
            'discover' => [
                {'service': _nus, 'characteristic': _tx, 'properties': 8},
                {
                  'service': _nus,
                  'characteristic': '6e400002-b5a3-f393-e0a9-e50e24dcca9e',
                  'properties': 4,
                },
              ],
            _ => null,
          };
      final central = WindowsBleCentral();
      final p = central.peripheral('a0b1c2d3e4f5');
      expect(p.id, 'A0B1C2D3E4F5');
      final states = <bool>[];
      p.connectionChanges.listen(states.add);

      await p.connect();
      expect(p.isConnected, isTrue);
      expect(p.mtu, 247);
      expect(p.maxWritePayload, 244);
      expect(channel.calls.last.arguments, {'id': 'A0B1C2D3E4F5'});

      final chars = await p.discoverServices();
      final tx = findCharacteristic(chars, _nus, _tx)!;
      expect(tx.properties.notify, isTrue);
      final rx = chars.firstWhere((c) => c != tx);
      expect(rx.properties.writeWithoutResponse, isTrue);

      final got = <List<int>>[];
      tx.notifications.listen(got.add);
      await tx.setNotify(true);
      expect(channel.calls.last.method, 'setNotify');
      expect(channel.calls.last.arguments, {
        'id': 'A0B1C2D3E4F5',
        'service': _nus,
        'characteristic': _tx,
        'enable': true,
      });
      channel.push({
        'event': 'notify',
        'id': 'A0B1C2D3E4F5',
        'service': _nus,
        'characteristic': _tx,
        'value': Uint8List.fromList([72, 10]),
      });
      await pumpEventQueue();
      expect(got, [
        [72, 10],
      ]);

      await rx.write([1, 2, 3], withoutResponse: true);
      final write = channel.calls.last;
      expect(write.method, 'write');
      expect((write.arguments as Map)['value'], Uint8List.fromList([1, 2, 3]));
      expect((write.arguments as Map)['withoutResponse'], isTrue);

      channel.push({
        'event': 'connection',
        'id': 'A0B1C2D3E4F5',
        'connected': false,
      });
      await pumpEventQueue();
      expect(p.isConnected, isFalse);
      expect(p.mtu, 23, reason: 'the MTU resets with the link');
      expect(states, [false, true, false]);
    });

    test('platform errors become BleExceptions', () async {
      channel.answer = (c) => throw PlatformException(
            code: kBleErrorUnreachable,
            message: 'Device unreachable',
          );
      final p = WindowsBleCentral().peripheral('A0B1C2D3E4F5');
      await expectLater(
        p.connect(),
        throwsA(isA<BleException>()
            .having((e) => e.code, 'code', kBleErrorUnreachable)),
      );
      expect(p.isConnected, isFalse);
    });

    testWidgets('a connect that times out cancels the native attempt',
        (tester) async {
      final never = Completer<Object?>();
      channel.answer = (c) => c.method == 'connect' ? never.future : null;
      final p = WindowsBleCentral().peripheral('A0B1C2D3E4F5');
      Object? error;
      unawaited(
        p.connect(timeout: const Duration(seconds: 2))
            .catchError((Object e) => error = e),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(error, isA<TimeoutException>());
      expect(channel.methods, ['connect', 'disconnect']);
    });

    test('an MTU change is picked up', () async {
      channel.answer = (c) => c.method == 'connect' ? {'mtu': 23} : null;
      final p = WindowsBleCentral().peripheral('A0B1C2D3E4F5');
      await p.connect();
      channel.push({'event': 'mtu', 'id': 'A0B1C2D3E4F5', 'mtu': 185});
      await pumpEventQueue();
      expect(p.mtu, 185);
    });
  });

  test('serial events decode', () {
    final data = decodeWindowsBleEvent({
      'event': 'serialData',
      'id': 'AABBCCDDEEFF',
      'value': Uint8List.fromList([1, 2, 3]),
    });
    expect(data, isA<WindowsSerialData>());
    expect((data! as WindowsSerialData).value, [1, 2, 3]);

    final dropped = decodeWindowsBleEvent({
      'event': 'serialConnection',
      'id': 'AABBCCDDEEFF',
      'connected': false,
    });
    expect(dropped, isA<WindowsSerialDropped>());
  });
}
