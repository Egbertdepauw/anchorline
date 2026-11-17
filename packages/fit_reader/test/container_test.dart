import 'dart:typed_data';

import 'package:fit_reader/fit_reader.dart';
import 'package:test/test.dart';

import 'support/fit_writer.dart';

const _enumT = 0x00, _u8 = 0x02, _u16 = 0x84, _s32 = 0x85, _u32 = 0x86;
const _str = 0x07, _f32 = 0x88, _u32z = 0x8C;

FitMessageSpec _m(int g, Map<int, (int, Object)> f) => FitMessageSpec(g, f);

void main() {
  test('12- and 14-byte headers both decode', () {
    for (final size in [12, 14]) {
      final f = decodeFit(
        buildFit([
          _m(20, {3: (_u8, 7)}),
        ], headerSize: size),
      );
      expect(f.messages.single.intField(3), 7);
      expect(f.profileVersion, 2000);
      expect(f.protocolVersion, 0x20);
    }
  });

  test('little- and big-endian definitions give the same values', () {
    final specs = [
      _m(20, {1: (_u16, 0x1234), 2: (_s32, -5), 3: (_u32, 0xDEADBEEF)}),
    ];
    for (final big in [false, true]) {
      final m = decodeFit(buildFit(specs, bigEndian: big)).messages.single;
      expect(m.intField(1), 0x1234);
      expect(m.intField(2), -5);
      expect(m.intField(3), 0xDEADBEEF);
    }
  });

  test('a compressed timestamp header adds its offset to the last '
      'timestamp, with rollover', () {
    const t = 1000000; // low 5 bits: 1000000 & 31 == 0
    final f = decodeFit(
      buildFit([
        _m(20, {253: (_u32, t), 1: (_u8, 1)}),
        _m(20, {253: (_u32, t + 10), 1: (_u8, 2)}),
        _m(20, {253: (_u32, t + 31), 1: (_u8, 3)}),
        // offset 31 -> 5 wraps to the next 32-second block
        _m(20, {253: (_u32, t + 37), 1: (_u8, 4)}),
      ], compressedTimestamps: true),
    );
    expect(f.messages.map((m) => m.timestamp), [t, t + 10, t + 31, t + 37]);
    expect(f.messages.map((m) => m.intField(1)), [1, 2, 3, 4]);
    // The compressed ones really carry no field 253.
    expect(f.messages[1].fields.containsKey(253), isFalse);
  });

  test('developer fields are skipped by their declared size and the next '
      'message still decodes', () {
    final f = decodeFit(
      buildFit(
        [
          _m(20, {1: (_u8, 11)}),
          _m(20, {1: (_u8, 22)}),
        ],
        devFields: const [
          FitDevFieldSpec(0, 0, [1, 2, 3, 4, 5]),
          FitDevFieldSpec(1, 0, [9]),
        ],
      ),
    );
    expect(f.messages.map((m) => m.intField(1)), [11, 22]);
    expect(f.messages.first.fields.keys, [1]);
  });

  test(
    'an unknown global message and an unknown field are kept, not fatal',
    () {
      final f = decodeFit(
        buildFit([
          _m(65000, {200: (_u16, 9), 201: (_str, 'hi')}),
        ]),
      );
      expect(f.messages.single.global, 65000);
      expect(f.messages.single.intField(200), 9);
      expect(f.messages.single.stringField(201), 'hi');
    },
  );

  test("each base type's invalid marker reads as null", () {
    final m = decodeFit(
      buildFit([
        _m(20, {
          1: (_u8, 0xFF),
          2: (_u16, 0xFFFF),
          3: (_u32z, 0),
          4: (_s32, 0x7FFFFFFF),
          5: (_str, ''),
          6: (_f32, double.nan),
          7: (_enumT, 0xFF),
          8: (_u32, 0xFFFFFFFF),
          9: (_u8, 0), // 0 is valid for plain uint8
        }),
      ]),
    ).messages.single;
    for (final n in [1, 2, 3, 4, 5, 6, 7, 8]) {
      expect(m.fields[n], isNotNull, reason: 'field $n is present');
      expect(m.fields[n]!.value, isNull, reason: 'field $n');
    }
    expect(m.intField(9), 0);
  });

  test('values of float and string fields read back', () {
    final m = decodeFit(
      buildFit([
        _m(20, {1: (_f32, 1.5), 2: (_str, 'Descent')}),
      ]),
    ).messages.single;
    expect(m.doubleField(1), 1.5);
    expect(m.stringField(2), 'Descent');
    expect(m.doubleField(2), isNull);
  });

  test('arrays decode as lists', () {
    final m = decodeFit(
      buildFit([
        _m(20, {
          1: (_u16, [1, 2, 3]),
        }),
      ]),
    ).messages.single;
    expect(m.fields[1]!.value, [1, 2, 3]);
    expect(m.fields[1]!.size, 6);
  });

  test('array elements holding the invalid marker read as null', () {
    final m = decodeFit(
      buildFit([
        _m(20, {
          1: (_u8, [1, 0xFF, 3]),
          2: (0x01, [-1, 0x7F, 2]), // sint8: -1 is real, 0x7F is invalid
          3: (_u8, [0xFF, 0xFF]),
        }),
      ]),
    ).messages.single;
    expect(m.fields[1]!.value, isA<List<int?>>());
    expect(m.fields[1]!.value, [1, null, 3]);
    expect(m.fields[2]!.value, [-1, null, 2]);
    expect(m.fields[3]!.value, isNull);
  });

  test('float arrays are List<double?>; byte arrays keep real 0xFF bytes', () {
    final m = decodeFit(
      buildFit([
        _m(20, {
          1: (_f32, [1.5, double.nan]),
          2: (0x0D, [1, 0xFF, 3]),
          3: (0x0D, [0xFF, 0xFF]),
        }),
      ]),
    ).messages.single;
    expect(m.fields[1]!.value, isA<List<double?>>());
    expect(m.fields[1]!.value, [1.5, null]);
    expect(m.fields[2]!.value, [1, 255, 3]);
    expect(m.fields[3]!.value, isNull);
  });

  test('a wrong file CRC throws FitFormatException', () {
    expect(
      () => decodeFit(
        buildFit([
          _m(20, {1: (_u8, 1)}),
        ], badCrc: true),
      ),
      throwsA(isA<FitFormatException>()),
    );
  });

  test('a wrong header CRC, bad tag or bad header size throws', () {
    final ok = buildFit([
      _m(20, {1: (_u8, 1)}),
    ]);
    final badHeaderCrc = Uint8List.fromList(ok)..[12] ^= 0xFF;
    final badTag = Uint8List.fromList(ok)..[9] = 0x00;
    final badSize = Uint8List.fromList(ok)..[0] = 13;
    for (final b in [badHeaderCrc, badTag, badSize]) {
      expect(() => decodeFit(b), throwsA(isA<FitFormatException>()));
    }
  });

  test('a truncated file throws FitFormatException', () {
    for (final cut in [1, 2, 5]) {
      expect(
        () => decodeFit(
          buildFit([
            _m(20, {1: (_u8, 1)}),
          ], truncateBy: cut),
        ),
        throwsA(isA<FitFormatException>()),
      );
    }
    expect(() => decodeFit(Uint8List(5)), throwsA(isA<FitFormatException>()));
  });

  test('stopAfter ends decoding without a CRC check', () {
    final bytes = buildFit([
      _m(20, {1: (_u8, 1)}),
      _m(21, {1: (_u8, 2)}),
      _m(22, {1: (_u8, 3)}),
    ], badCrc: true);
    final f = decodeFit(bytes, stopAfter: (m) => m.global == 21);
    expect(f.messages.map((m) => m.global), [20, 21]);
  });

  test('a data message whose local type was never defined throws', () {
    expect(
      () => decodeFit(
        buildFit([
          _m(20, {1: (_u8, 1)}),
        ], skipDefinitions: true),
      ),
      throwsA(isA<FitFormatException>()),
    );
  });

  test('FitField.offset points at the value bytes', () {
    final bytes = buildFit([
      _m(20, {1: (_u8, 1), 2: (_u16, 0x0102)}),
    ]);
    final field = decodeFit(bytes).messages.single.fields[2]!;
    final patched = Uint8List.fromList(bytes);
    ByteData.sublistView(
      patched,
    ).setUint16(field.offset, 0x0A0B, Endian.little);
    // Patching leaves the CRC stale; fix it as the anonymiser will.
    final end = patched.length - 2;
    final crc = fitCrc16(patched, 0, end);
    patched[end] = crc & 0xFF;
    patched[end + 1] = crc >> 8;
    expect(decodeFit(patched).messages.single.intField(2), 0x0A0B);
  });

  test('fitCrc16 equals a bit-by-bit CRC-16/ARC', () {
    int ref(List<int> bytes) {
      var crc = 0;
      for (final b in bytes) {
        crc ^= b;
        for (var i = 0; i < 8; i++) {
          crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
        }
      }
      return crc;
    }

    for (var b = 0; b < 256; b++) {
      expect(fitCrc16(Uint8List.fromList([b])), ref([b]), reason: 'byte $b');
    }
    final long = [for (var i = 0; i < 1000; i++) (i * 37 + 11) & 0xFF];
    expect(fitCrc16(Uint8List.fromList(long)), ref(long));
  });

  test('fitCrc16 matches the CRC of a real Garmin header', () {
    final h = Uint8List.fromList([
      0x0e,
      0x10,
      0x7e,
      0x08,
      0xff,
      0xea,
      0x03,
      0x00,
      0x2e,
      0x46,
      0x49,
      0x54,
    ]);
    expect(fitCrc16(h), 0x6263);
  });

  test('fitCrc16 matches a known vector and honours the range', () {
    final b = Uint8List.fromList('123456789'.codeUnits);
    expect(fitCrc16(b), 0xBB3D); // CRC-16/ARC
    final padded = Uint8List.fromList([0xAA, ...b, 0xBB]);
    expect(fitCrc16(padded, 1, 10), 0xBB3D);
  });
}
