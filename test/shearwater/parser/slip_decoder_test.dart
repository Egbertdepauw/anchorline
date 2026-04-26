import 'dart:typed_data';

import 'package:ccrlogger/shearwater/parser/slip_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slipDecode', () {
    test('decodes plain bytes with no special characters', () {
      // [0x01, 0x02, 0x03] terminated by END (0xC0)
      final frame = Uint8List.fromList([0x01, 0x02, 0x03, 0xC0]);
      expect(slipDecode(frame), equals([0x01, 0x02, 0x03]));
    });

    test('decodes escaped END character (0xDB 0xDC -> 0xC0)', () {
      // A literal 0xC0 inside data is escaped as 0xDB 0xDC
      final frame = Uint8List.fromList([0x01, 0xDB, 0xDC, 0x02, 0xC0]);
      expect(slipDecode(frame), equals([0x01, 0xC0, 0x02]));
    });

    test('decodes escaped ESC character (0xDB 0xDD -> 0xDB)', () {
      // A literal 0xDB inside data is escaped as 0xDB 0xDD
      final frame = Uint8List.fromList([0x01, 0xDB, 0xDD, 0x02, 0xC0]);
      expect(slipDecode(frame), equals([0x01, 0xDB, 0x02]));
    });

    test('decodes multiple escaped characters in sequence', () {
      // Two escaped characters back to back
      final frame =
          Uint8List.fromList([0xDB, 0xDC, 0xDB, 0xDD, 0xC0]);
      expect(slipDecode(frame), equals([0xC0, 0xDB]));
    });

    test('returns empty list for empty frame (just END)', () {
      final frame = Uint8List.fromList([0xC0]);
      expect(slipDecode(frame), isEmpty);
    });

    test('ignores leading END characters (consecutive ENDs)', () {
      // Leading ENDs should be skipped per SLIP spec (empty packets ignored)
      final frame = Uint8List.fromList([0xC0, 0xC0, 0x01, 0x02, 0xC0]);
      expect(slipDecode(frame), equals([0x01, 0x02]));
    });

    test('decodes frame without trailing END (tolerant)', () {
      // Some implementations may not have a trailing END
      final frame = Uint8List.fromList([0x01, 0x02, 0x03]);
      expect(slipDecode(frame), equals([0x01, 0x02, 0x03]));
    });

    test('handles ESC followed by unknown byte (pass through per libdc)', () {
      // libdc passes unknown escaped bytes through unchanged
      final frame = Uint8List.fromList([0x01, 0xDB, 0xAA, 0xC0]);
      expect(slipDecode(frame), equals([0x01, 0xAA]));
    });

    test('handles all-zero data', () {
      final frame = Uint8List.fromList([0x00, 0x00, 0x00, 0xC0]);
      expect(slipDecode(frame), equals([0x00, 0x00, 0x00]));
    });

    test('handles single byte frame', () {
      final frame = Uint8List.fromList([0xFF, 0xC0]);
      expect(slipDecode(frame), equals([0xFF]));
    });
  });

  group('slipEncode', () {
    test('encodes plain bytes with END terminator', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final encoded = slipEncode(data);
      expect(encoded, equals([0x01, 0x02, 0x03, 0xC0]));
    });

    test('escapes END character in data', () {
      final data = Uint8List.fromList([0x01, 0xC0, 0x02]);
      final encoded = slipEncode(data);
      expect(encoded, equals([0x01, 0xDB, 0xDC, 0x02, 0xC0]));
    });

    test('escapes ESC character in data', () {
      final data = Uint8List.fromList([0x01, 0xDB, 0x02]);
      final encoded = slipEncode(data);
      expect(encoded, equals([0x01, 0xDB, 0xDD, 0x02, 0xC0]));
    });

    test('escapes multiple special characters', () {
      final data = Uint8List.fromList([0xC0, 0xDB]);
      final encoded = slipEncode(data);
      expect(encoded, equals([0xDB, 0xDC, 0xDB, 0xDD, 0xC0]));
    });

    test('encodes empty data as just END', () {
      final data = Uint8List.fromList([]);
      final encoded = slipEncode(data);
      expect(encoded, equals([0xC0]));
    });

    test('round-trips plain data', () {
      final original = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]);
      final roundTripped = slipDecode(slipEncode(original));
      expect(roundTripped, equals(original));
    });

    test('round-trips data containing special characters', () {
      final original = Uint8List.fromList([0xC0, 0xDB, 0x00, 0xFF, 0xC0, 0xDB]);
      final roundTripped = slipDecode(slipEncode(original));
      expect(roundTripped, equals(original));
    });
  });
}
