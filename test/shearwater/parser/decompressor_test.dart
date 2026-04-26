import 'dart:typed_data';

import 'package:ccrlogger/shearwater/parser/decompressor.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to pack a list of 9-bit values into a byte stream (big-endian).
///
/// Each value must be 0-511. The total bits are padded to a multiple of 8
/// with zero bits.
Uint8List pack9bit(List<int> values) {
  final totalBits = values.length * 9;
  final totalBytes = (totalBits + 7) ~/ 8;
  final bytes = Uint8List(totalBytes);

  var bitOffset = 0;
  for (final value in values) {
    assert(value >= 0 && value <= 0x1FF);
    // Write 9 bits big-endian starting at bitOffset.
    final byteIndex = bitOffset ~/ 8;
    final bitIndex = bitOffset % 8;
    // Place the 9-bit value into a 24-bit window and shift into position.
    final shifted = value << (24 - 9 - bitIndex);
    bytes[byteIndex] |= (shifted >> 16) & 0xFF;
    if (byteIndex + 1 < totalBytes) {
      bytes[byteIndex + 1] |= (shifted >> 8) & 0xFF;
    }
    if (byteIndex + 2 < totalBytes) {
      bytes[byteIndex + 2] |= shifted & 0xFF;
    }
    bitOffset += 9;
  }

  return bytes;
}

void main() {
  group('pack9bit helper', () {
    test('packs single literal correctly', () {
      // Value 0x1AB = 0b1_10101011 (9 bits)
      // Bit 8 set = literal, lower 8 bits = 0xAB
      // In bytes: 110101011 + padding → 0xD5 0x80
      final packed = pack9bit([0x1AB]);
      // 1_10101011 → byte 0: 11010101, byte 1: 1_0000000
      expect(packed, equals([0xD5, 0x80]));
    });

    test('packs end-of-stream (0x000) correctly', () {
      // Value 0x000 = 0b000000000 (9 zero bits)
      final packed = pack9bit([0x000]);
      expect(packed, equals([0x00, 0x00]));
    });
  });

  group('lreDecode', () {
    test('decodes single literal byte', () {
      // 0x1AB → literal 0xAB, then 0x000 → end of stream
      // pack9bit([0x1AB, 0x000]) = 18 bits → 3 bytes
      // But total bits must be multiple of 9 (it is: 2 * 9 = 18, 18 % 9 == 0)
      // However 18 bits → ceil(18/8) = 3 bytes → 24 bits, 24 % 9 != 0
      // The C code checks nbits = size * 8, and nbits % 9 must == 0.
      // So we need total byte count where byteCount * 8 % 9 == 0.
      // 9 bytes = 72 bits = 8 nine-bit values.
      // Let's use: [0x1AB, 0x000, padding...]
      // Simplest: 9 bytes = 8 nine-bit values.
      // Use [0x1AB, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000]
      final compressed = pack9bit(
          [0x1AB, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000]);
      expect(compressed.length, equals(9)); // 72 bits / 8
      final result = lreDecode(compressed);
      expect(result.data, equals([0xAB]));
      expect(result.isFinal, isTrue);
    });

    test('decodes multiple literal bytes', () {
      // Literals: 0x1FF (=0xFF), 0x100 (=0x00), 0x141 (=0x41='A')
      // Then end: 0x000, pad to 8 values for 9-byte alignment
      final compressed = pack9bit(
          [0x1FF, 0x100, 0x141, 0x000, 0x000, 0x000, 0x000, 0x000]);
      final result = lreDecode(compressed);
      expect(result.data, equals([0xFF, 0x00, 0x41]));
      expect(result.isFinal, isTrue);
    });

    test('decodes zero-run (N zero bytes)', () {
      // Run of 5 zeros: value = 0x005 (bit 8 clear, count=5)
      // Then end: 0x000
      final compressed = pack9bit(
          [0x005, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000]);
      final result = lreDecode(compressed);
      expect(result.data, equals([0, 0, 0, 0, 0]));
      expect(result.isFinal, isTrue);
    });

    test('decodes mixed literals and zero-runs', () {
      // Literal 0xAA, run of 3 zeros, literal 0xBB, end
      final compressed = pack9bit(
          [0x1AA, 0x003, 0x1BB, 0x000, 0x000, 0x000, 0x000, 0x000]);
      final result = lreDecode(compressed);
      expect(result.data, equals([0xAA, 0, 0, 0, 0xBB]));
      expect(result.isFinal, isTrue);
    });

    test('handles max zero-run length (255)', () {
      // Run of 255 zeros (0x0FF, bit 8 clear)
      final compressed = pack9bit(
          [0x0FF, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000, 0x000]);
      final result = lreDecode(compressed);
      expect(result.data.length, equals(255));
      expect(result.data.every((b) => b == 0), isTrue);
      expect(result.isFinal, isTrue);
    });

    test('returns isFinal=false when no end marker reached', () {
      // 8 literals, no end marker — all 8 nine-bit slots used for data
      final compressed = pack9bit(
          [0x101, 0x102, 0x103, 0x104, 0x105, 0x106, 0x107, 0x108]);
      final result = lreDecode(compressed);
      expect(result.data, equals([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]));
      expect(result.isFinal, isFalse);
    });

    test('rejects input whose bit count is not a multiple of 9', () {
      // 1 byte = 8 bits, 8 % 9 != 0
      expect(
        () => lreDecode(Uint8List.fromList([0x00])),
        throwsArgumentError,
      );
    });

    test('handles empty input (0 bytes)', () {
      final result = lreDecode(Uint8List(0));
      expect(result.data, isEmpty);
      expect(result.isFinal, isFalse);
    });
  });

  group('xorDecode', () {
    test('leaves first 32 bytes unchanged', () {
      final data = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        data[i] = i;
      }
      final original = Uint8List.fromList(data);
      xorDecode(data);
      expect(data, equals(original));
    });

    test('XORs second block with first block', () {
      final data = Uint8List(64);
      // First block: all 0x01
      for (var i = 0; i < 32; i++) {
        data[i] = 0x01;
      }
      // Second block: all 0x01 (XOR with first → 0x00)
      for (var i = 32; i < 64; i++) {
        data[i] = 0x01;
      }
      xorDecode(data);
      // First block unchanged
      for (var i = 0; i < 32; i++) {
        expect(data[i], equals(0x01));
      }
      // Second block: 0x01 ^ 0x01 = 0x00
      for (var i = 32; i < 64; i++) {
        expect(data[i], equals(0x00));
      }
    });

    test('XOR is cumulative across 3 blocks', () {
      // The C code does: data[i] ^= data[i - 32] for i >= 32.
      // After XOR, block 2 = block2_orig ^ block1.
      // Then block 3: data[i] ^= data[i-32] which is already-decoded block 2.
      final data = Uint8List(96);
      // Block 0: 0xAA
      for (var i = 0; i < 32; i++) {
        data[i] = 0xAA;
      }
      // Block 1: 0x55 → after XOR: 0x55 ^ 0xAA = 0xFF
      for (var i = 32; i < 64; i++) {
        data[i] = 0x55;
      }
      // Block 2: 0x0F → after XOR: 0x0F ^ 0xFF = 0xF0
      for (var i = 64; i < 96; i++) {
        data[i] = 0x0F;
      }

      xorDecode(data);

      for (var i = 0; i < 32; i++) {
        expect(data[i], equals(0xAA));
      }
      for (var i = 32; i < 64; i++) {
        expect(data[i], equals(0xFF));
      }
      for (var i = 64; i < 96; i++) {
        expect(data[i], equals(0xF0));
      }
    });

    test('handles data shorter than 32 bytes (no-op)', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final original = Uint8List.fromList(data);
      xorDecode(data);
      expect(data, equals(original));
    });

    test('handles data not a multiple of 32 (partial last block)', () {
      // 40 bytes: full 32-byte block + 8 extra bytes
      final data = Uint8List(40);
      for (var i = 0; i < 32; i++) {
        data[i] = 0x10;
      }
      for (var i = 32; i < 40; i++) {
        data[i] = 0x20;
      }

      xorDecode(data);

      for (var i = 0; i < 32; i++) {
        expect(data[i], equals(0x10));
      }
      // bytes 32-39: 0x20 ^ 0x10 = 0x30
      for (var i = 32; i < 40; i++) {
        expect(data[i], equals(0x30));
      }
    });
  });

  group('decompress (LRE + XOR combined)', () {
    test('decompresses data through LRE then XOR', () {
      // Create a simple compressed stream: two literal 32-byte blocks
      // Block 0: [0x01 * 32], Block 1 (pre-XOR): [0x02 * 32]
      // After XOR decode: Block 1 becomes 0x02 ^ 0x01 = 0x03

      // Build 9-bit values: 64 literals + end = 65 values
      // 65 * 9 = 585 bits → need 585 % 9 == 0 ✓
      // 585 / 8 = 73.125 → 74 bytes → 592 bits → 592 % 9 != 0
      // Need byte count where bytes * 8 % 9 == 0: 9, 18, 27, ..., 72, 81...
      // 65 values = 585 bits → need ≥ 74 bytes → next valid: 81 bytes = 648 bits = 72 values
      // So we need 72 nine-bit values: 64 literals + 1 end + 7 padding zeros
      final values = <int>[];
      for (var i = 0; i < 32; i++) {
        values.add(0x101); // literal 0x01
      }
      for (var i = 0; i < 32; i++) {
        values.add(0x102); // literal 0x02
      }
      values.add(0x000); // end
      while (values.length < 72) {
        values.add(0x000); // padding
      }

      final compressed = pack9bit(values);
      expect(compressed.length, equals(81)); // 72 * 9 / 8 = 81

      final result = decompress(compressed);

      // After LRE: [0x01 * 32, 0x02 * 32]
      // After XOR: block 0 unchanged, block 1: 0x02 ^ 0x01 = 0x03
      expect(result.length, equals(64));
      for (var i = 0; i < 32; i++) {
        expect(result[i], equals(0x01));
      }
      for (var i = 32; i < 64; i++) {
        expect(result[i], equals(0x03));
      }
    });
  });
}
