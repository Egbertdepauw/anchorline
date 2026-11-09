import 'dart:async';
import 'dart:convert';

import 'package:ccrlogger/analyzer/bridge/bridge_link.dart';
import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/transport/ble_bridge_transport.dart';
import 'package:ccrlogger/analyzer/transport/serial_line_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/fake_bridge_link.dart';

const _hello =
    'HELLO proto=1 fw=0.1.0 bridge=a0b1c2d3e4f5 epoch=1a2b3c4d boot=7 '
    'up=123456 solo=1 rec=off vbus=off batt=3987 pending=0';

final _now = DateTime.fromMillisecondsSinceEpoch(1762700000000);

BleBridgeTransport _transport(
  FakeBridgeLink link, {
  bool rec = false,
  bool vbus = false,
}) => BleBridgeTransport(
  link: link,
  recording: () => rec,
  vbusOn: () => vbus,
  now: () => _now,
);

/// Lets queued microtasks and stream events run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('connect sends TIME, CFG and LIVE ON in order', () async {
    final link = FakeBridgeLink();
    final t = _transport(link);
    final done = t.connect();
    await _settle();
    expect(t.status, AnalyzerConnectionStatus.connecting);
    expect(link.sent, ['TIME 1762700000000', 'CFG rec=off vbus=off', 'LIVE ON']);
    link.pushLine(_hello);
    await done;
    await t.dispose();
  });

  test('CFG carries the recording and vbus settings read at connect', () async {
    final link = FakeBridgeLink();
    final t = _transport(link, rec: true, vbus: true);
    final done = t.connect();
    await _settle();
    expect(link.sent[1], 'CFG rec=on vbus=on');
    link.pushLine(_hello);
    await done;
    await t.dispose();
  });

  test('HELLO makes the transport connected', () async {
    final link = FakeBridgeLink();
    final t = _transport(link);
    final done = t.connect();
    await _settle();
    link.pushLine(_hello);
    await done;
    expect(t.status, AnalyzerConnectionStatus.connected);
    expect(t.lastHello?.bridgeId, 'a0b1c2d3e4f5');
    expect(t.lastStatus?.batteryMv, 3987);
    await t.dispose();
  });

  test('L lines come out as analyzer lines, spaces intact', () async {
    final link = FakeBridgeLink();
    final t = _transport(link);
    final lines = <String>[];
    final messages = <BridgeMessage>[];
    t.lines.listen(lines.add);
    t.messages.listen(messages.add);
    final done = t.connect();
    await _settle();
    link.pushLine(_hello);
    await done;
    const raw = 'He   0.4 %  O2  19.8 %  Ti  21.7 ~C  1029.5 hPa';
    link.pushLine('L $raw');
    await _settle();
    expect(lines, [raw]);
    // L lines stay out of messages.
    expect(messages.whereType<BridgeLiveLine>(), isEmpty);
    expect(messages.whereType<BridgeHello>(), hasLength(1));
    await t.dispose();
  });

  test('HELLO with proto=2 is an error naming the version', () async {
    final link = FakeBridgeLink();
    final t = _transport(link);
    final done = t.connect();
    await _settle();
    link.pushLine(_hello.replaceFirst('proto=1', 'proto=2'));
    await done;
    expect(t.status, AnalyzerConnectionStatus.error);
    expect(
      t.errorMessage,
      'Bridge firmware speaks protocol 2. Update the app or the bridge.',
    );
    expect(link.state, BridgeLinkState.disconnected);
    await t.dispose();
  });

  // testWidgets gives the fake clock; pump() moves it.
  testWidgets('no HELLO in 5 s is an error', (tester) async {
    final link = FakeBridgeLink();
    final t = _transport(link);
    var finished = false;
    unawaited(t.connect().then((_) => finished = true));
    await tester.pump(const Duration(seconds: 4));
    expect(t.status, AnalyzerConnectionStatus.connecting);
    expect(finished, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(finished, isTrue);
    expect(t.status, AnalyzerConnectionStatus.error);
    expect(t.errorMessage, 'The bridge did not answer.');
    expect(link.state, BridgeLinkState.disconnected);
  });

  test('a first connect that throws is an error with its message', () async {
    final link = FakeBridgeLink(
      connectError: const BridgeLinkException(
        'Bridge not found. Is it switched on?',
      ),
    );
    final t = _transport(link);
    await t.connect();
    expect(t.status, AnalyzerConnectionStatus.error);
    expect(t.errorMessage, 'Bridge not found. Is it switched on?');
    await t.dispose();
  });

  test('a dropped link goes back to connecting and resends TIME, CFG, '
      'LIVE ON on reconnect', () async {
    final link = FakeBridgeLink();
    final t = _transport(link);
    final seen = <AnalyzerConnectionStatus>[];
    t.statusChanges.listen(seen.add);
    final done = t.connect();
    await _settle();
    link.pushLine(_hello);
    await done;
    link.sent.clear();

    link.pushState(BridgeLinkState.connecting);
    await _settle();
    expect(t.status, AnalyzerConnectionStatus.connecting);
    expect(link.sent, isEmpty);

    link.pushState(BridgeLinkState.connected);
    await _settle();
    expect(link.sent, ['TIME 1762700000000', 'CFG rec=off vbus=off', 'LIVE ON']);
    expect(t.status, AnalyzerConnectionStatus.connecting);
    link.pushLine(_hello);
    await _settle();
    expect(t.status, AnalyzerConnectionStatus.connected);
    expect(seen, [
      AnalyzerConnectionStatus.connecting,
      AnalyzerConnectionStatus.connected,
      AnalyzerConnectionStatus.connecting,
      AnalyzerConnectionStatus.connected,
    ]);
    await t.dispose();
  });

  test('HELLO before the link reports connected still sends TIME, CFG and '
      'LIVE ON', () async {
    // The real bridge sends HELLO as soon as notifications are on, which is
    // before the link layer reports the connection.
    final link = FakeBridgeLink(lineBeforeConnected: _hello);
    final t = _transport(link);
    await t.connect();
    await _settle();
    expect(t.status, AnalyzerConnectionStatus.connected);
    expect(link.sent, ['TIME 1762700000000', 'CFG rec=off vbus=off', 'LIVE ON']);
    await t.dispose();
  });

  test('on a reconnect, HELLO before the connected state still resends '
      'TIME, CFG and LIVE ON', () async {
    final link = FakeBridgeLink();
    final t = _transport(link);
    final done = t.connect();
    await _settle();
    link.pushLine(_hello);
    await done;
    link.sent.clear();

    link.pushState(BridgeLinkState.connecting);
    await _settle();
    link.pushLine(_hello);
    link.pushState(BridgeLinkState.connected);
    await _settle();
    expect(t.status, AnalyzerConnectionStatus.connected);
    expect(link.sent, ['TIME 1762700000000', 'CFG rec=off vbus=off', 'LIVE ON']);
    await t.dispose();
  });

  test('disconnect sends LIVE OFF', () async {
    final link = FakeBridgeLink();
    final t = _transport(link);
    final done = t.connect();
    await _settle();
    link.pushLine(_hello);
    await done;
    link.sent.clear();
    await t.disconnect();
    expect(link.sent, ['LIVE OFF']);
    expect(t.status, AnalyzerConnectionStatus.disconnected);
    expect(link.state, BridgeLinkState.disconnected);
    await t.dispose();
  });

  test('ST updates lastStatus and fires bridgeChanges', () async {
    final link = FakeBridgeLink();
    final t = _transport(link);
    final done = t.connect();
    await _settle();
    link.pushLine(_hello);
    await done;
    var changes = 0;
    t.bridgeChanges.listen((_) => changes++);
    link.pushLine('ST solo=0 data=0 pending=2 batt=0 up=5000');
    await _settle();
    expect(changes, 1);
    expect(t.lastStatus?.soloAttached, isFalse);
    expect(t.lastStatus?.pending, 2);
    await t.dispose();
  });

  test('sendConfig sends the current settings, and send is a no-op when the '
      'link is down', () async {
    var vbus = false;
    final link = FakeBridgeLink();
    final t = BleBridgeTransport(
      link: link,
      recording: () => false,
      vbusOn: () => vbus,
      now: () => _now,
    );
    await t.sendConfig();
    expect(link.sent, isEmpty);
    final done = t.connect();
    await _settle();
    link.pushLine(_hello);
    await done;
    link.sent.clear();
    vbus = true;
    await t.sendConfig();
    expect(link.sent, ['CFG rec=off vbus=on']);
    await t.dispose();
  });

  test('a line split over three notifications arrives whole', () {
    // What FbpBridgeLink does with notifications: bytes go through a
    // SerialLineBuffer. A 140-byte L line over a 23-byte MTU is 20 bytes
    // per notification.
    final line = 'L He   0.4 %  O2  19.8 %  Ti  21.7 ~C  1029.5 hPa   '
        '${'x' * 88}';
    expect(line.length, 140);
    final bytes = utf8.encode('$line\n');
    final buffer = SerialLineBuffer();
    final out = <String>[];
    for (var i = 0; i < bytes.length; i += 20) {
      final end = i + 20 < bytes.length ? i + 20 : bytes.length;
      out.addAll(buffer.add(bytes.sublist(i, end)));
    }
    expect(bytes.length / 20, greaterThan(2));
    expect(out, [line]);
    expect(parseBridgeMessage(out.single), isA<BridgeLiveLine>());
  });
}
