import 'dart:io';

import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/transport/desktop_serial_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final desktop = Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  // Real hardware cannot be exercised here; this checks the failure path
  // end to end (isolate spawn, native open, error reporting, cleanup).
  test('a missing port ends in error with a message, and disposes cleanly',
      () async {
    final t = DesktopSerialTransport(
        portPath: Platform.isWindows ? 'COM250' : '/dev/cu.no-such-port');
    final seen = <AnalyzerConnectionStatus>[];
    t.statusChanges.listen(seen.add);

    await t.connect();

    expect(t.status, AnalyzerConnectionStatus.error);
    expect(t.errorMessage, contains('Could not open'));
    expect(seen.first, AnalyzerConnectionStatus.connecting);
    await t.disconnect();
    expect(t.status, AnalyzerConnectionStatus.error);
    await t.dispose();
  }, skip: !desktop);

  test('listDesktopSerialPorts never throws', () {
    expect(listDesktopSerialPorts, returnsNormally);
  }, skip: !desktop);
}
