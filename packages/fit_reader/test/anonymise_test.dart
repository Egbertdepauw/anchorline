import 'dart:typed_data';

import 'package:fit_reader/fit_reader.dart';
import 'package:test/test.dart';

import '../tool/anonymise_fit.dart';
import 'support/fit_writer.dart';

const _serial = 0xC0FFEE42;
const _newSerial = 1000000001;
const _uint8 = 0x02;
const _uint16 = 0x84;
const _uint32 = 0x86;
const _uint32z = 0x8C;
const _sint32 = 0x85;
const _string = 0x07;

List<FitMessageSpec> _messages() => [
  FitMessageSpec(FitMesg.fileId, {
    0: (0x00, 4),
    1: (_uint16, 1),
    2: (_uint16, 2859),
    3: (_uint32z, _serial),
    4: (_uint32, 1000),
    8: (_string, 'Descent Mk1'),
  }),
  FitMessageSpec(3, {
    0: (_string, 'Jane Diver'),
    1: (_uint8, 1),
    3: (_uint8, 172),
    4: (_uint16, 640),
    28: (_uint32, 123456),
  }),
  FitMessageSpec(FitMesg.deviceInfo, {
    253: (_uint32, 1001),
    2: (_uint16, 2859),
    3: (_uint32z, _serial),
    17: (_string, 'Jane watch'),
  }),
  FitMessageSpec(FitMesg.deviceInfo, {
    253: (_uint32, 1002),
    2: (_uint16, 7),
    3: (_uint32z, 555),
    17: (_string, 'Jane strap'),
  }),
  // An undocumented message that repeats the serial, once as a lone field
  // and once inside an array, beside values that must stay.
  FitMessageSpec(777, {
    0: (_uint32, _serial),
    1: (_uint32, 4242),
    2: (_uint32, _serial),
    3: (_sint32, 99),
  }),
  FitMessageSpec(FitMesg.session, {
    253: (_uint32, 1010),
    2: (_uint32, 1000),
    3: (_sint32, 523000000),
    4: (_sint32, 45000000),
    29: (_sint32, 523100000),
    30: (_sint32, 45100000),
    31: (_sint32, 522900000),
    32: (_sint32, 44900000),
    38: (_sint32, 523200000),
    39: (_sint32, 45200000),
    7: (_uint32, 5000),
  }),
  FitMessageSpec(19, {
    253: (_uint32, 1011),
    3: (_sint32, 523000001),
    4: (_sint32, 45000001),
    5: (_sint32, 523000002),
    6: (_sint32, 45000002),
    27: (_sint32, 523000003),
    28: (_sint32, 45000003),
    29: (_sint32, 523000004),
    30: (_sint32, 45000004),
    10: (_uint32, 77),
  }),
  for (var i = 0; i < 3; i++)
    FitMessageSpec(FitMesg.record, {
      253: (_uint32, 1000 + i),
      0: (_sint32, 523000100 + i),
      1: (_sint32, 45000100 + i),
      92: (_uint32, 1000 * i),
      13: (0x01, 20),
    }),
];

/// Offsets of every byte [anonymiseFit] is allowed to change in
/// [_messages]' file, found by decoding the input.
Set<int> _mayChange(Uint8List bytes) {
  final out = <int>{};
  const gps = {
    FitMesg.session: {3, 4, 29, 30, 31, 32, 38, 39},
    19: {3, 4, 5, 6, 27, 28, 29, 30},
    FitMesg.record: {0, 1},
  };
  final file = decodeFit(bytes);
  for (final m in file.messages) {
    for (final f in m.fields.values) {
      final isSerial =
          (m.global == FitMesg.fileId || m.global == FitMesg.deviceInfo) &&
          f.number == 3;
      final isGps = gps[m.global]?.contains(f.number) ?? false;
      final isProfile = m.global == 3;
      final isString =
          (f.baseType & 0x1F) == _string &&
          (m.global == 3 || m.global == FitMesg.deviceInfo);
      final repeats = m.global == 777 && (f.number == 0 || f.number == 2);
      if (isSerial || isGps || isProfile || isString || repeats) {
        for (var i = 0; i < f.size; i++) {
          out.add(f.offset + i);
        }
      }
    }
  }
  return out;
}

void main() {
  for (final bigEndian in [false, true]) {
    test('serials, GPS, profile and strings are replaced; the rest is '
        'byte-identical; CRC valid (bigEndian: $bigEndian)', () {
      final input = buildFit(_messages(), bigEndian: bigEndian);
      final report = anonymiseFit(input, serial: _newSerial);
      final out = report.bytes;

      expect(out.length, input.length);
      // decodeFit throws on a bad CRC.
      final file = decodeFit(out);
      final byGlobal = <int, List<FitMessage>>{};
      for (final m in file.messages) {
        byGlobal.putIfAbsent(m.global, () => []).add(m);
      }

      // Serials: file id, device info with a serial, and the repeats.
      expect(byGlobal[FitMesg.fileId]!.single.intField(3), _newSerial);
      expect(byGlobal[FitMesg.deviceInfo]![0].intField(3), _newSerial);
      expect(byGlobal[FitMesg.deviceInfo]![1].intField(3), _newSerial);
      final repeat = byGlobal[777]!.single;
      expect(repeat.intField(0), _newSerial);
      expect(repeat.intField(2), _newSerial);
      expect(repeat.intField(1), 4242);
      expect(repeat.intField(3), 99);

      // GPS is invalid everywhere Subsurface declares a position.
      final s = byGlobal[FitMesg.session]!.single;
      for (final n in [3, 4, 29, 30, 31, 32, 38, 39]) {
        expect(s.fields[n]!.value, isNull, reason: 'session $n');
      }
      expect(s.intField(7), 5000);
      final lap = byGlobal[19]!.single;
      for (final n in [3, 4, 5, 6, 27, 28, 29, 30]) {
        expect(lap.fields[n]!.value, isNull, reason: 'lap $n');
      }
      expect(lap.intField(10), 77);
      for (final r in byGlobal[FitMesg.record]!) {
        expect(r.fields[0]!.value, isNull);
        expect(r.fields[1]!.value, isNull);
        expect(r.intField(13), 20);
      }
      expect(
        byGlobal[FitMesg.record]!.map((r) => r.intField(92)),
        [0, 1000, 2000],
      );

      // User profile: every field invalid. Strings in profile and device
      // messages are gone; the file id's product name stays.
      for (final f in byGlobal[3]!.single.fields.values) {
        expect(f.value, isNull, reason: 'profile field ${f.number}');
      }
      for (final m in byGlobal[FitMesg.deviceInfo]!) {
        expect(m.stringField(17), isNull);
      }
      expect(byGlobal[FitMesg.fileId]!.single.stringField(8), 'Descent Mk1');
      expect(byGlobal[FitMesg.deviceInfo]![0].intField(2), 2859);

      // Nothing outside those fields moved, and the original serial is
      // nowhere in the file any more.
      final allowed = _mayChange(input);
      for (var i = 0; i < input.length - 2; i++) {
        if (input[i] != out[i]) {
          expect(allowed, contains(i), reason: 'byte $i changed');
        }
      }
      for (final e in [Endian.little, Endian.big]) {
        final needle = Uint8List(4)..buffer.asByteData().setUint32(0, _serial, e);
        for (var i = 0; i + 4 <= out.length; i++) {
          expect(
            [for (var k = 0; k < 4; k++) out[i + k]],
            isNot(needle.toList()),
            reason: 'serial at $i',
          );
        }
      }

      // The report counts, and never carries values.
      expect(report.counts[FitMesg.fileId], {'serial': 1});
      expect(report.counts[FitMesg.deviceInfo], {'serial': 2, 'string': 2});
      expect(report.counts[3]!['profile'], 5);
      expect(report.counts[FitMesg.session], {'gps': 8});
      expect(report.counts[19], {'gps': 8});
      expect(report.counts[FitMesg.record], {'gps': 6});
      expect(report.counts[777], {'serial': 2});
    });
  }

  test('a file whose serial is invalid keeps its other 4-byte values', () {
    final input = buildFit([
      FitMessageSpec(FitMesg.fileId, {0: (0x00, 4), 3: (_uint32z, 0)}),
      FitMessageSpec(777, {0: (_uint32, 0), 1: (_uint32, 0xFFFFFFFF)}),
    ]);
    final report = anonymiseFit(input, serial: _newSerial);
    expect(report.bytes, input);
    expect(report.counts, isEmpty);
  });

  test('a string that starts with a NUL still has its later bytes removed',
      () {
    final input = buildFit([
      FitMessageSpec(FitMesg.fileId, {0: (0x00, 4), 3: (_uint32z, _serial)}),
      FitMessageSpec(3, {0: (_string, '\u0000Jane Diver'), 1: (_uint8, 1)}),
      FitMessageSpec(FitMesg.deviceInfo, {
        253: (_uint32, 1001),
        17: (_string, '\u0000Jane watch'),
      }),
    ]);
    final needle = 'Jane'.codeUnits;
    bool contains(Uint8List b) {
      for (var i = 0; i + 4 <= b.length; i++) {
        if (b[i] == needle[0] &&
            b[i + 1] == needle[1] &&
            b[i + 2] == needle[2] &&
            b[i + 3] == needle[3]) {
          return true;
        }
      }
      return false;
    }

    expect(contains(input), isTrue);
    final out = anonymiseFit(input, serial: _newSerial).bytes;
    expect(contains(out), isFalse);
    decodeFit(out);
  });

  test('a chained file (data after the first CRC) is refused', () {
    final first = buildFit(_messages());
    final second = buildFit(_messages());
    expect(
      () => anonymiseFit(
        Uint8List.fromList([...first, ...second]),
        serial: _newSerial,
      ),
      throwsA(isA<FitFormatException>()),
    );
  });

  test('a corrupt file is refused', () {
    final input = buildFit(_messages(), badCrc: true);
    expect(
      () => anonymiseFit(input, serial: _newSerial),
      throwsA(isA<FitFormatException>()),
    );
  });
}
