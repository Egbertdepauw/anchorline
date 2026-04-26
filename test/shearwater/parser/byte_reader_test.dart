import 'dart:typed_data';

import 'package:ccrlogger/shearwater/parser/byte_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // All Shearwater protocol values are big-endian.
  final data = Uint8List.fromList([
    0x00, 0x01, 0x02, 0x03, // offset 0-3
    0xFF, 0xFE, 0xFD, 0xFC, // offset 4-7
    0x80, 0x00, 0x00, 0x01, // offset 8-11
    0x7F, 0x80, // offset 12-13: signed boundary values
  ]);

  group('uint8', () {
    test('reads single byte', () {
      expect(uint8(data, 0), equals(0x00));
      expect(uint8(data, 4), equals(0xFF));
      expect(uint8(data, 12), equals(0x7F));
    });
  });

  group('uint16BE', () {
    test('reads big-endian 16-bit unsigned', () {
      expect(uint16BE(data, 0), equals(0x0001));
      expect(uint16BE(data, 4), equals(0xFFFE));
      expect(uint16BE(data, 8), equals(0x8000));
    });
  });

  group('uint24BE', () {
    test('reads big-endian 24-bit unsigned', () {
      expect(uint24BE(data, 0), equals(0x000102));
      expect(uint24BE(data, 4), equals(0xFFFEFD));
    });
  });

  group('uint32BE', () {
    test('reads big-endian 32-bit unsigned', () {
      expect(uint32BE(data, 0), equals(0x00010203));
      expect(uint32BE(data, 4), equals(0xFFFEFDFC));
      expect(uint32BE(data, 8), equals(0x80000001));
    });
  });

  group('int8', () {
    test('reads signed byte', () {
      expect(int8(data, 0), equals(0));
      expect(int8(data, 4), equals(-1)); // 0xFF signed
      expect(int8(data, 12), equals(127)); // 0x7F
      expect(int8(data, 13), equals(-128)); // 0x80
    });
  });

  group('hexToBytes', () {
    test('converts hex string to bytes', () {
      expect(hexToBytes('B89641E4'), equals([0xB8, 0x96, 0x41, 0xE4]));
    });

    test('handles lowercase', () {
      expect(hexToBytes('ff00ab'), equals([0xFF, 0x00, 0xAB]));
    });

    test('returns empty for empty string', () {
      expect(hexToBytes(''), isEmpty);
    });
  });
}
