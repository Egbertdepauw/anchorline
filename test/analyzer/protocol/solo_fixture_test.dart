import 'dart:convert';
import 'dart:io';

import 'package:ccrlogger/analyzer/protocol/solo_line_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real USB output of a trimix Divesoft SOLO (#104), captured 2026-10-31
/// on macOS from `/dev/cu.usbmodem2101` at 115200 8N1 with DTR raised,
/// analysing air. 20 s of output, bytes kept exactly as received (CRLF).
///
/// What it shows about the device:
/// - Field order is `He … O2 … Ti … hPa <timestamp>`, padded with extra
///   spaces.
/// - The helium sensor reports `***.*` while it warms up, then 0.4 % on air
///   (sensor offset).
/// - The SOLO sends 5 lines per device second, not 1 (#127).
/// - The first 15 lines are a stale burst buffered before the port was
///   opened (15:42:13–15:42:15), followed by a gap to the live stream.
/// - The device clock was ~42 min behind real time, so device timestamps
///   are not a usable time base.
const _fixture = 'test/fixtures/analyzer/solo_trimix_air_2026-10-31.txt';

void main() {
  late List<String> lines;

  setUpAll(() {
    final bytes = File(_fixture).readAsBytesSync();
    lines = const LineSplitter().convert(latin1.decode(bytes));
  });

  test('every line of the capture is a data line', () {
    expect(lines, hasLength(114));
    for (final line in lines) {
      expect(parseSoloLine(line), isNotNull, reason: line);
    }
  });

  test('warming-up helium sensor (***.*) parses as NaN, O2 still valid', () {
    final errors =
        lines.map(parseSoloLine).where((r) => r!.he!.isNaN).toList();
    expect(errors, hasLength(9));
    for (final r in errors) {
      expect(r!.o2, 19.7);
    }
  });

  test('a live line parses every field', () {
    final r = parseSoloLine(lines.last)!;
    expect(r.he, 0.4);
    expect(r.o2, 19.7);
    expect(r.tempC, 19.1);
    expect(r.baroHpa, 1033.4);
    expect(r.deviceTime, DateTime(2026, 10, 31, 15, 42, 57));
    expect(r.raw, isNot(endsWith('\r')));
  });

  test('the SOLO sends 5 lines per device second', () {
    final perSecond = <DateTime, int>{};
    for (final line in lines) {
      final t = parseSoloLine(line)!.deviceTime!;
      perSecond[t] = (perSecond[t] ?? 0) + 1;
    }
    // Full seconds only: the first and last second of each stretch can be
    // cut off by the capture window.
    final full = perSecond.values.where((n) => n != 2);
    expect(full, everyElement(5));
  });

  test('the first 15 lines are a stale burst before a gap', () {
    final times = lines.map((l) => parseSoloLine(l)!.deviceTime!).toList();
    expect(times[14], DateTime(2026, 10, 31, 15, 42, 15));
    expect(times[15].difference(times[14]).inSeconds, greaterThan(10));
  });
}
