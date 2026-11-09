import 'dart:io';

import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the firmware golden lines all parse', () {
    // flutter test runs with the package root as the working directory.
    final file = File('firmware/solo_bridge/host_test/golden/wire_v1.txt');
    final lines = file
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .toList();
    expect(lines, isNotEmpty);
    for (final line in lines) {
      expect(
        parseBridgeMessage(line),
        isNot(isA<BridgeUnknown>()),
        reason: line,
      );
    }
    final hello = parseBridgeMessage(
      lines.firstWhere((l) => l.startsWith('HELLO ')),
    );
    expect((hello as BridgeHello).bridgeId, 'a0b1c2d3e4f5');
    expect(hello.proto, kBridgeProtocolVersion);
  });
}
