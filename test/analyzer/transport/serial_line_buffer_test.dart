import 'dart:convert';

import 'package:ccrlogger/analyzer/transport/serial_line_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<int> b(String s) => utf8.encode(s);

  test('splits on \\r\\n and \\n, stripping terminators', () {
    final buf = SerialLineBuffer();
    expect(buf.add(b('He 45.1 O2 18.2 %\r\nHe 45.0 O2 18.3 %\nrest')),
        ['He 45.1 O2 18.2 %', 'He 45.0 O2 18.3 %']);
    expect(buf.pendingLength, 4);
  });

  test('keeps a partial line across chunks', () {
    final buf = SerialLineBuffer();
    expect(buf.add(b('He 45.1 O2')), isEmpty);
    expect(buf.add(b(' 18.2 %\r')), isEmpty);
    expect(buf.add(b('\nHe')), ['He 45.1 O2 18.2 %']);
    expect(buf.add(b(' 1\r\n')), ['He 1']);
  });

  test('a \\r\\n split between chunks still strips the \\r', () {
    final buf = SerialLineBuffer();
    expect(buf.add(b('abc\r')), isEmpty);
    expect(buf.add(b('\n')), ['abc']);
  });

  test('skips blank lines', () {
    final buf = SerialLineBuffer();
    expect(buf.add(b('\r\n\r\nx\n\n')), ['x']);
  });

  test('a lone \\r is part of the line', () {
    final buf = SerialLineBuffer();
    expect(buf.add(b('a\rb\n')), ['a\rb']);
  });

  test('decodes a multi-byte character split across chunks', () {
    final buf = SerialLineBuffer();
    final bytes = b('20 °C\n');
    final cut = bytes.indexOf(0xC2) + 1; // inside the two-byte '°'
    expect(buf.add(bytes.sublist(0, cut)), isEmpty);
    expect(buf.add(bytes.sublist(cut)), ['20 °C']);
  });

  test('malformed bytes do not throw', () {
    final buf = SerialLineBuffer();
    expect(buf.add([0x41, 0xFF, 0x42, 0x0A]), ['A�B']);
  });

  test('drops a runaway partial line', () {
    final buf = SerialLineBuffer(maxLineLength: 8);
    expect(buf.add(b('0123456789abc')), isEmpty);
    expect(buf.pendingLength, lessThanOrEqualTo(8));
    expect(buf.add(b('\nok\n')), hasLength(2));
    expect(buf.add(b('ok\n')), ['ok']);
  });

  test('clear drops the partial line', () {
    final buf = SerialLineBuffer();
    buf.add(b('stale'));
    buf.clear();
    expect(buf.add(b('fresh\n')), ['fresh']);
  });
}
