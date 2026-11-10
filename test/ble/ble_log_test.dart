import 'dart:io';

import 'package:ccrlogger/ble/ble_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ble_log_test'));
  tearDown(() {
    bleLogFile = null;
    dir.deleteSync(recursive: true);
  });

  test('bleLog appends timestamped lines to the log file', () {
    final f = bleLogFile = File('${dir.path}/ble.log');
    bleLog('Phomemo BLE: connect failed: x');
    bleLog('second');
    final lines = f.readAsLinesSync();
    expect(lines, hasLength(2));
    expect(lines[0], endsWith(' Phomemo BLE: connect failed: x'));
    expect(lines[1], endsWith(' second'));
  });

  test('a log past its limit is cut to its last half first', () {
    final f = File('${dir.path}/ble.log')..writeAsStringSync('a' * 100);
    appendBleLogLine(f, 'new\n', maxBytes: 80);
    final text = f.readAsStringSync();
    expect(text, '${'a' * 40}new\n');
  });

  test('a file that cannot be written is ignored', () {
    final f = File('${dir.path}/missing/dir/ble.log');
    expect(() => appendBleLogLine(f, 'x\n'), returnsNormally);
  });
}
