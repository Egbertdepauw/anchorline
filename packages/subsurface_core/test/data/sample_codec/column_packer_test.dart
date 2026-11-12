import 'dart:typed_data';

import 'package:subsurface_core/data/sample_codec/column_packer.dart';
import 'package:test/test.dart';

void main() {
  group('Float32 round-trip', () {
    test('packs and unpacks float32 data losslessly', () {
      final original = Float32List.fromList([1.5, -3.14, 0.0, 100.25, 42.0]);
      final packed = ColumnPacker.packFloat32(original);
      final unpacked = ColumnPacker.unpackFloat32(packed, original.length);
      expect(unpacked, equals(original));
    });

    test('compressed size is smaller for repetitive data', () {
      final repetitive = Float32List(1000);
      for (var i = 0; i < 1000; i++) {
        repetitive[i] = 25.0; // same value repeats
      }
      final packed = ColumnPacker.packFloat32(repetitive);
      // 1000 floats = 4000 bytes raw; gzip should compress well
      expect(packed.length, lessThan(1000));
    });

    test('handles empty list', () {
      final original = Float32List(0);
      final packed = ColumnPacker.packFloat32(original);
      final unpacked = ColumnPacker.unpackFloat32(packed, 0);
      expect(unpacked, isEmpty);
    });
  });

  group('Int32 round-trip', () {
    test('packs and unpacks int32 data losslessly', () {
      final original = Int32List.fromList([0, -1, 2147483647, -2147483648, 42]);
      final packed = ColumnPacker.packInt32(original);
      final unpacked = ColumnPacker.unpackInt32(packed, original.length);
      expect(unpacked, equals(original));
    });
  });

  group('Uint8 round-trip', () {
    test('packs and unpacks uint8 data losslessly', () {
      final original = Uint8List.fromList([0, 127, 255, 1, 42]);
      final packed = ColumnPacker.packUint8(original);
      final unpacked = ColumnPacker.unpackUint8(packed, original.length);
      expect(unpacked, equals(original));
    });

    test('handles large arrays', () {
      final original = Uint8List(10000);
      for (var i = 0; i < 10000; i++) {
        original[i] = i & 0xFF;
      }
      final packed = ColumnPacker.packUint8(original);
      final unpacked = ColumnPacker.unpackUint8(packed, original.length);
      expect(unpacked, equals(original));
    });
  });

  group('realistic dive data', () {
    test('round-trips depth profile (Float32)', () {
      // Simulate a depth profile: descend, stay, ascend
      final depth = Float32List(360); // 1 hour at 10s intervals
      for (var i = 0; i < 60; i++) {
        depth[i] = i * 0.5; // descend 0.5m per sample
      }
      for (var i = 60; i < 300; i++) {
        depth[i] = 30.0; // bottom at 30m
      }
      for (var i = 300; i < 360; i++) {
        depth[i] = 30.0 - (i - 300) * 0.5; // ascend
      }

      final packed = ColumnPacker.packFloat32(depth);
      final unpacked = ColumnPacker.unpackFloat32(packed, depth.length);
      expect(unpacked, equals(depth));
      // Should compress reasonably (lots of repeated 30.0 values)
      expect(packed.length, lessThan(depth.lengthInBytes));
    });
  });
}
